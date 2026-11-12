//! Real testnet Bitcoin <-> Liquid atomic-swap workflow.
//!
//! The localhost order book is only a public state coordinator. Swap keys and
//! the maker preimage are deterministically recovered from the software-wallet
//! seed and never sent to the server.

use std::fs;
use std::str::FromStr;
use std::time::{SystemTime, UNIX_EPOCH};

use bdk::bitcoin::consensus::encode::serialize as serialize_bitcoin;
use bdk::bitcoin::{Address as BitcoinAddress, Network as BitcoinNetwork};
use serde::{Deserialize, Serialize};

use templar_core::registry::WalletProfile;
use templar_core::{
    bitcoin_contract, derive_swap_secret_key, liquid_contract, spend_bitcoin_htlc,
    spend_liquid_htlc, swap_public_key, BitcoinSpendRequest, HtlcTerms, LiquidHtlcSpendRequest,
    MAKER_TIMEOUT_SECS, TAKER_TIMEOUT_SECS,
};

use crate::state::AppState;

const STORE_FILE: &str = "atomic_swaps.json";
const API: &str = "http://127.0.0.1:3210/api/atomic-swaps";
const NETWORK: &str = "liquid-testnet";
const DEFAULT_BTC_FEE_RATE: f32 = 2.0;
const CLAIM_FEE_SATS: u64 = 500;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AtomicSwapState {
    pub offered_chain: String,
    pub offered_asset_id: String,
    pub offered_ticker: String,
    pub offered_name: String,
    pub offered_precision: u8,
    pub offered_amount_sats: u64,
    pub wanted_chain: String,
    pub wanted_asset_id: String,
    pub wanted_ticker: String,
    pub wanted_name: String,
    pub wanted_precision: u8,
    pub wanted_amount_sats: u64,
    pub payment_hash: String,
    pub maker_refund_pubkey: String,
    pub taker_claim_pubkey: Option<String>,
    pub maker_timeout: u64,
    pub taker_timeout: Option<u64>,
    pub maker_contract_address: Option<String>,
    pub maker_contract_script: Option<String>,
    pub taker_contract_address: Option<String>,
    pub taker_contract_script: Option<String>,
    pub maker_funding_txid: Option<String>,
    pub maker_funding_tx_hex: Option<String>,
    pub maker_funding_vout: Option<u32>,
    pub taker_funding_txid: Option<String>,
    pub taker_funding_tx_hex: Option<String>,
    pub taker_funding_vout: Option<u32>,
    pub preimage_hex: Option<String>,
    pub maker_claim_txid: Option<String>,
    pub taker_claim_txid: Option<String>,
    pub maker_refund_txid: Option<String>,
    pub taker_refund_txid: Option<String>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AtomicSwapRow {
    pub id: u64,
    pub network: String,
    pub status: String,
    pub state: AtomicSwapState,
    pub created_at: u64,
    pub updated_at: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MyAtomicSwap {
    pub offer_id: u64,
    pub wallet_id: String,
    pub role: String,
    pub key_index: u32,
    pub row: AtomicSwapRow,
    pub next_action: String,
    pub can_fund: bool,
    pub can_claim: bool,
    pub can_refund: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct StoredAtomicSwap {
    offer_id: u64,
    wallet_id: String,
    role: String,
    key_index: u32,
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct AtomicStore {
    swaps: Vec<StoredAtomicSwap>,
}

#[derive(Debug, Deserialize)]
pub struct CreateParams {
    pub wallet_id: String,
    pub direction: String,
    pub btc_amount_sats: u64,
    pub liquid_asset_id: String,
    pub liquid_ticker: String,
    pub liquid_name: String,
    #[serde(default = "eight")]
    pub liquid_precision: u8,
    pub liquid_amount_sats: u64,
    #[serde(default)]
    pub note: String,
}

#[derive(Debug, Deserialize)]
pub struct IdParams {
    pub wallet_id: String,
    pub offer_id: u64,
}

#[derive(Debug, Deserialize)]
pub struct ListParams {
    pub wallet_id: String,
}

fn eight() -> u8 {
    8
}

pub fn create(state: &AppState, p: CreateParams) -> Result<MyAtomicSwap, String> {
    require_testnet_software(state, &p.wallet_id)?;
    let mnemonic = mnemonic(state, &p.wallet_id)?;
    let mut store = load_store(state)?;
    let key_index = next_index(&store, &p.wallet_id);
    let maker_key = derive_swap_secret_key(mnemonic, 0, key_index).map_err(|e| e.to_string())?;
    let preimage = deterministic_preimage(&maker_key.secret_bytes());
    let payment_hash = sha256_hex(&preimage);
    let btc = Leg::btc(p.btc_amount_sats);
    let liquid = Leg {
        chain: "liquid".into(),
        asset_id: p.liquid_asset_id.to_ascii_lowercase(),
        ticker: p.liquid_ticker,
        name: p.liquid_name,
        precision: p.liquid_precision,
        amount: p.liquid_amount_sats,
    };
    let (offered, wanted) = match p.direction.as_str() {
        "btc-to-liquid" => (btc, liquid),
        "liquid-to-btc" => (liquid, btc),
        _ => return Err("Direction must be btc-to-liquid or liquid-to-btc".into()),
    };
    let state_public = AtomicSwapState::new(
        offered,
        wanted,
        payment_hash,
        swap_public_key(&maker_key).to_string(),
        p.note,
    );
    let row: AtomicSwapRow = post_json(
        API,
        &serde_json::json!({
            "network": NETWORK,
            "state": state_public,
        }),
    )?;
    store.swaps.push(StoredAtomicSwap {
        offer_id: row.id,
        wallet_id: p.wallet_id.clone(),
        role: "maker".into(),
        key_index,
    });
    save_store(state, &store)?;
    Ok(enrich(row, &p.wallet_id, "maker", key_index))
}

pub fn join(state: &AppState, p: IdParams) -> Result<MyAtomicSwap, String> {
    require_testnet_software(state, &p.wallet_id)?;
    let mnemonic = mnemonic(state, &p.wallet_id)?;
    let mut row = fetch(p.offer_id)?;
    if row.status != "open" {
        return Err("Offer is no longer open".into());
    }
    let mut store = load_store(state)?;
    if store.swaps.iter().any(|s| s.offer_id == p.offer_id) {
        return Err("This wallet already participates in the swap".into());
    }
    let key_index = next_index(&store, &p.wallet_id);
    let taker_key = derive_swap_secret_key(mnemonic, 1, key_index).map_err(|e| e.to_string())?;
    let taker_pubkey = swap_public_key(&taker_key).to_string();
    let now = now_secs();
    if row.state.maker_timeout <= now + TAKER_TIMEOUT_SECS + 3_600 {
        return Err("Maker refund window is too short; create a fresh offer".into());
    }
    row.state.taker_claim_pubkey = Some(taker_pubkey.clone());
    row.state.taker_timeout = Some(now + TAKER_TIMEOUT_SECS);
    let maker_terms = HtlcTerms {
        payment_hash: row.state.payment_hash.clone(),
        claim_pubkey: taker_pubkey.clone(),
        refund_pubkey: row.state.maker_refund_pubkey.clone(),
        timeout: row.state.maker_timeout,
    };
    let taker_terms = HtlcTerms {
        payment_hash: row.state.payment_hash.clone(),
        claim_pubkey: row.state.maker_refund_pubkey.clone(),
        refund_pubkey: taker_pubkey,
        timeout: row.state.taker_timeout.expect("set"),
    };
    let maker_contract = contract(&row.state.offered_chain, maker_terms)?;
    let taker_contract = contract(&row.state.wanted_chain, taker_terms)?;
    row.state.maker_contract_address = Some(maker_contract.address);
    row.state.maker_contract_script = Some(maker_contract.script_hex);
    row.state.taker_contract_address = Some(taker_contract.address);
    row.state.taker_contract_script = Some(taker_contract.script_hex);
    row = transition(&row, "reserved")?;
    store.swaps.push(StoredAtomicSwap {
        offer_id: row.id,
        wallet_id: p.wallet_id.clone(),
        role: "taker".into(),
        key_index,
    });
    save_store(state, &store)?;
    Ok(enrich(row, &p.wallet_id, "taker", key_index))
}

pub fn list_mine(state: &AppState, wallet_id: &str) -> Result<Vec<MyAtomicSwap>, String> {
    let store = load_store(state)?;
    store
        .swaps
        .iter()
        .filter(|s| s.wallet_id == wallet_id)
        .map(|s| fetch(s.offer_id).map(|row| enrich(row, wallet_id, &s.role, s.key_index)))
        .collect()
}

pub fn fund(state: &AppState, p: IdParams) -> Result<MyAtomicSwap, String> {
    require_testnet_software(state, &p.wallet_id)?;
    let local = owned(state, &p.wallet_id, p.offer_id)?;
    let mut row = fetch(p.offer_id)?;
    let maker = local.role == "maker";
    if (maker && row.status != "reserved") || (!maker && row.status != "maker_funded") {
        return Err(format!(
            "{} cannot fund while swap is {}",
            local.role, row.status
        ));
    }
    let (chain, asset, amount, address) = if maker {
        (
            &row.state.offered_chain,
            &row.state.offered_asset_id,
            row.state.offered_amount_sats,
            row.state.maker_contract_address.as_deref(),
        )
    } else {
        (
            &row.state.wanted_chain,
            &row.state.wanted_asset_id,
            row.state.wanted_amount_sats,
            row.state.taker_contract_address.as_deref(),
        )
    };
    let address = address.ok_or("HTLC contract is missing")?;
    if !maker {
        verify_funding(
            state,
            &row.state.offered_chain,
            &row.state.offered_asset_id,
            row.state.offered_amount_sats,
            row.state
                .maker_contract_address
                .as_deref()
                .ok_or("Maker contract missing")?,
            row.state
                .maker_funding_txid
                .as_deref()
                .ok_or("Maker funding txid missing")?,
            row.state
                .maker_funding_vout
                .ok_or("Maker funding vout missing")?,
        )?;
    }
    let funded = fund_contract(state, chain, asset, amount, address)?;
    if maker {
        row.state.maker_funding_txid = Some(funded.txid);
        row.state.maker_funding_tx_hex = Some(funded.tx_hex);
        row.state.maker_funding_vout = Some(funded.vout);
        row = transition(&row, "maker_funded")?;
    } else {
        row.state.taker_funding_txid = Some(funded.txid);
        row.state.taker_funding_tx_hex = Some(funded.tx_hex);
        row.state.taker_funding_vout = Some(funded.vout);
        row = transition(&row, "taker_funded")?;
    }
    Ok(enrich(row, &p.wallet_id, &local.role, local.key_index))
}

pub fn claim(state: &AppState, p: IdParams) -> Result<MyAtomicSwap, String> {
    require_testnet_software(state, &p.wallet_id)?;
    let local = owned(state, &p.wallet_id, p.offer_id)?;
    let mut row = fetch(p.offer_id)?;
    let maker = local.role == "maker";
    if (maker && row.status != "taker_funded") || (!maker && row.status != "maker_claimed") {
        return Err(format!(
            "{} cannot claim while swap is {}",
            local.role, row.status
        ));
    }
    let mnemonic = mnemonic(state, &p.wallet_id)?;
    let key = derive_swap_secret_key(mnemonic, if maker { 0 } else { 1 }, local.key_index)
        .map_err(|e| e.to_string())?;
    let preimage = if maker {
        deterministic_preimage(&key.secret_bytes())
    } else {
        let raw = row
            .state
            .preimage_hex
            .as_deref()
            .ok_or("Maker preimage is not published")?;
        let bytes = hex::decode(raw).map_err(|e| format!("Invalid preimage: {e}"))?;
        bytes
            .try_into()
            .map_err(|_| "Preimage must be 32 bytes".to_string())?
    };
    let (chain, asset, amount, txid, vout, script, terms) = if maker {
        (
            &row.state.wanted_chain,
            &row.state.wanted_asset_id,
            row.state.wanted_amount_sats,
            row.state.taker_funding_txid.as_deref(),
            row.state.taker_funding_vout,
            row.state.taker_contract_script.as_deref(),
            HtlcTerms {
                payment_hash: row.state.payment_hash.clone(),
                claim_pubkey: row.state.maker_refund_pubkey.clone(),
                refund_pubkey: row
                    .state
                    .taker_claim_pubkey
                    .clone()
                    .ok_or("Taker pubkey missing")?,
                timeout: row.state.taker_timeout.ok_or("Taker timeout missing")?,
            },
        )
    } else {
        (
            &row.state.offered_chain,
            &row.state.offered_asset_id,
            row.state.offered_amount_sats,
            row.state.maker_funding_txid.as_deref(),
            row.state.maker_funding_vout,
            row.state.maker_contract_script.as_deref(),
            HtlcTerms {
                payment_hash: row.state.payment_hash.clone(),
                claim_pubkey: row
                    .state
                    .taker_claim_pubkey
                    .clone()
                    .ok_or("Taker pubkey missing")?,
                refund_pubkey: row.state.maker_refund_pubkey.clone(),
                timeout: row.state.maker_timeout,
            },
        )
    };
    let contract_address = if maker {
        row.state.taker_contract_address.as_deref()
    } else {
        row.state.maker_contract_address.as_deref()
    }
    .ok_or("HTLC contract address missing")?;
    verify_funding(
        state,
        chain,
        asset,
        amount,
        contract_address,
        txid.ok_or("Funding txid missing")?,
        vout.ok_or("Funding vout missing")?,
    )?;
    let spend_txid = spend_contract(
        state,
        SpendSpec {
            chain,
            asset,
            amount,
            funding_txid: txid.expect("verified"),
            funding_vout: vout.expect("verified"),
            script_hex: script.ok_or("HTLC script missing")?,
            terms,
            preimage: Some(hex::encode(preimage)),
            key: key.secret_bytes(),
        },
    )?;
    if maker {
        row.state.preimage_hex = Some(hex::encode(preimage));
        row.state.maker_claim_txid = Some(spend_txid);
        row = transition(&row, "maker_claimed")?;
    } else {
        row.state.taker_claim_txid = Some(spend_txid);
        row = transition(&row, "completed")?;
    }
    Ok(enrich(row, &p.wallet_id, &local.role, local.key_index))
}

pub fn refund(state: &AppState, p: IdParams) -> Result<MyAtomicSwap, String> {
    require_testnet_software(state, &p.wallet_id)?;
    let local = owned(state, &p.wallet_id, p.offer_id)?;
    let mut row = fetch(p.offer_id)?;
    let maker = local.role == "maker";
    let timeout = if maker {
        row.state.maker_timeout
    } else {
        row.state.taker_timeout.ok_or("Taker timeout missing")?
    };
    if now_secs() < timeout {
        return Err(format!("Refund unlocks at Unix time {timeout}"));
    }
    let mnemonic = mnemonic(state, &p.wallet_id)?;
    let key = derive_swap_secret_key(mnemonic, if maker { 0 } else { 1 }, local.key_index)
        .map_err(|e| e.to_string())?;
    let (chain, asset, amount, txid, vout, script, terms) = if maker {
        (
            &row.state.offered_chain,
            &row.state.offered_asset_id,
            row.state.offered_amount_sats,
            row.state.maker_funding_txid.as_deref(),
            row.state.maker_funding_vout,
            row.state.maker_contract_script.as_deref(),
            HtlcTerms {
                payment_hash: row.state.payment_hash.clone(),
                claim_pubkey: row
                    .state
                    .taker_claim_pubkey
                    .clone()
                    .ok_or("Taker pubkey missing")?,
                refund_pubkey: row.state.maker_refund_pubkey.clone(),
                timeout: row.state.maker_timeout,
            },
        )
    } else {
        (
            &row.state.wanted_chain,
            &row.state.wanted_asset_id,
            row.state.wanted_amount_sats,
            row.state.taker_funding_txid.as_deref(),
            row.state.taker_funding_vout,
            row.state.taker_contract_script.as_deref(),
            HtlcTerms {
                payment_hash: row.state.payment_hash.clone(),
                claim_pubkey: row.state.maker_refund_pubkey.clone(),
                refund_pubkey: row
                    .state
                    .taker_claim_pubkey
                    .clone()
                    .ok_or("Taker pubkey missing")?,
                timeout,
            },
        )
    };
    let contract_address = if maker {
        row.state.maker_contract_address.as_deref()
    } else {
        row.state.taker_contract_address.as_deref()
    }
    .ok_or("HTLC contract address missing")?;
    verify_funding(
        state,
        chain,
        asset,
        amount,
        contract_address,
        txid.ok_or("Funding txid missing")?,
        vout.ok_or("Funding vout missing")?,
    )?;
    let refund_txid = spend_contract(
        state,
        SpendSpec {
            chain,
            asset,
            amount,
            funding_txid: txid.expect("verified"),
            funding_vout: vout.expect("verified"),
            script_hex: script.ok_or("HTLC script missing")?,
            terms,
            preimage: None,
            key: key.secret_bytes(),
        },
    )?;
    let next = if maker {
        row.state.maker_refund_txid = Some(refund_txid);
        "maker_refunded"
    } else {
        row.state.taker_refund_txid = Some(refund_txid);
        "taker_refunded"
    };
    row = transition(&row, next)?;
    Ok(enrich(row, &p.wallet_id, &local.role, local.key_index))
}

#[derive(Clone)]
struct Leg {
    chain: String,
    asset_id: String,
    ticker: String,
    name: String,
    precision: u8,
    amount: u64,
}
impl Leg {
    fn btc(amount: u64) -> Self {
        Self {
            chain: "bitcoin".into(),
            asset_id: "btc-testnet".into(),
            ticker: "BTC".into(),
            name: "Bitcoin Testnet".into(),
            precision: 8,
            amount,
        }
    }
}

impl AtomicSwapState {
    fn new(
        offered: Leg,
        wanted: Leg,
        payment_hash: String,
        maker_key: String,
        note: String,
    ) -> Self {
        Self {
            offered_chain: offered.chain,
            offered_asset_id: offered.asset_id,
            offered_ticker: offered.ticker,
            offered_name: offered.name,
            offered_precision: offered.precision,
            offered_amount_sats: offered.amount,
            wanted_chain: wanted.chain,
            wanted_asset_id: wanted.asset_id,
            wanted_ticker: wanted.ticker,
            wanted_name: wanted.name,
            wanted_precision: wanted.precision,
            wanted_amount_sats: wanted.amount,
            payment_hash,
            maker_refund_pubkey: maker_key,
            taker_claim_pubkey: None,
            maker_timeout: now_secs() + MAKER_TIMEOUT_SECS,
            taker_timeout: None,
            maker_contract_address: None,
            maker_contract_script: None,
            taker_contract_address: None,
            taker_contract_script: None,
            maker_funding_txid: None,
            maker_funding_tx_hex: None,
            maker_funding_vout: None,
            taker_funding_txid: None,
            taker_funding_tx_hex: None,
            taker_funding_vout: None,
            preimage_hex: None,
            maker_claim_txid: None,
            taker_claim_txid: None,
            maker_refund_txid: None,
            taker_refund_txid: None,
            note,
        }
    }
}

struct Funded {
    txid: String,
    tx_hex: String,
    vout: u32,
}

fn fund_contract(
    state: &AppState,
    chain: &str,
    asset: &str,
    amount: u64,
    address: &str,
) -> Result<Funded, String> {
    if chain == "bitcoin" {
        let wallet = state.bitcoin.as_ref().ok_or("Bitcoin wallet not open")?;
        let mut psbt = wallet
            .create_tx(address, amount, DEFAULT_BTC_FEE_RATE, None, None)
            .map_err(|e| e.to_string())?;
        if !wallet.sign(&mut psbt).map_err(|e| e.to_string())? {
            return Err("Bitcoin funding PSBT did not finalize".into());
        }
        let tx = psbt.extract_tx();
        let target = BitcoinAddress::from_str(address)
            .map_err(|e| e.to_string())?
            .require_network(BitcoinNetwork::Testnet)
            .map_err(|e| e.to_string())?
            .script_pubkey();
        let vout = tx
            .output
            .iter()
            .position(|o| o.value == amount && o.script_pubkey == target)
            .ok_or("Bitcoin funding output missing from signed transaction")?
            as u32;
        let tx_hex = hex::encode(serialize_bitcoin(&tx));
        let txid = wallet.broadcast(tx).map_err(|e| e.to_string())?.to_string();
        Ok(Funded { txid, tx_hex, vout })
    } else {
        use lwk_wollet::elements::{encode::serialize_hex, Address, AssetId};
        let wallet = state.liquid.as_ref().ok_or("Liquid wallet not open")?;
        let mut pset = wallet
            .create_tx(address, amount, asset)
            .map_err(|e| e.to_string())?;
        wallet.sign(&mut pset).map_err(|e| e.to_string())?;
        let tx = wallet.finalize(&mut pset).map_err(|e| e.to_string())?;
        let target = Address::parse_with_params(address, state.liquid_network.address_params())
            .map_err(|e| e.to_string())?
            .script_pubkey();
        let asset_id = AssetId::from_str(asset).map_err(|e| e.to_string())?;
        let vout = tx
            .output
            .iter()
            .position(|o| {
                o.script_pubkey == target
                    && o.value.explicit() == Some(amount)
                    && o.asset.explicit() == Some(asset_id)
            })
            .ok_or("Liquid explicit HTLC output missing from signed transaction")?
            as u32;
        let tx_hex = serialize_hex(&tx);
        let txid =
            templar_core::liquid::liquidex::broadcast_transaction_on(&tx, &state.liquid_network)
                .map_err(|e| e.to_string())?;
        Ok(Funded { txid, tx_hex, vout })
    }
}

fn verify_funding(
    state: &AppState,
    chain: &str,
    asset: &str,
    amount: u64,
    address: &str,
    txid: &str,
    vout: u32,
) -> Result<(), String> {
    if chain == "bitcoin" {
        let wallet = state.bitcoin.as_ref().ok_or("Bitcoin wallet not open")?;
        let parsed = txid.parse().map_err(|e| format!("Funding txid: {e}"))?;
        let tx = wallet
            .fetch_transaction(&parsed)
            .map_err(|e| e.to_string())?
            .ok_or("Maker Bitcoin funding transaction is not visible on Electrum yet")?;
        if tx.txid().to_string() != txid {
            return Err("Bitcoin funding txid mismatch".into());
        }
        let target = BitcoinAddress::from_str(address)
            .map_err(|e| e.to_string())?
            .require_network(BitcoinNetwork::Testnet)
            .map_err(|e| e.to_string())?
            .script_pubkey();
        let output = tx
            .output
            .get(vout as usize)
            .ok_or("Bitcoin funding vout missing")?;
        if output.value != amount || output.script_pubkey != target {
            return Err("Bitcoin funding output does not match the signed swap terms".into());
        }
    } else {
        use lwk_wollet::elements::{Address, AssetId, Txid};
        let wallet = state.liquid.as_ref().ok_or("Liquid wallet not open")?;
        let parsed = Txid::from_str(txid).map_err(|e| format!("Funding txid: {e}"))?;
        let tx = wallet
            .chain()
            .map_err(|e| e.to_string())?
            .fetch_transaction(&parsed)
            .map_err(|e| e.to_string())?
            .ok_or("Maker Liquid funding transaction is not visible yet")?;
        let target = Address::parse_with_params(address, state.liquid_network.address_params())
            .map_err(|e| e.to_string())?
            .script_pubkey();
        let asset_id = AssetId::from_str(asset).map_err(|e| e.to_string())?;
        let output = tx
            .output
            .get(vout as usize)
            .ok_or("Liquid funding vout missing")?;
        if output.script_pubkey != target
            || output.value.explicit() != Some(amount)
            || output.asset.explicit() != Some(asset_id)
        {
            return Err("Liquid funding output does not match the signed swap terms".into());
        }
    }
    Ok(())
}

struct SpendSpec<'a> {
    chain: &'a str,
    asset: &'a str,
    amount: u64,
    funding_txid: &'a str,
    funding_vout: u32,
    script_hex: &'a str,
    terms: HtlcTerms,
    preimage: Option<String>,
    key: [u8; 32],
}

fn spend_contract(state: &AppState, s: SpendSpec<'_>) -> Result<String, String> {
    let rebuilt = templar_core::htlc_script(&s.terms).map_err(|e| e.to_string())?;
    if hex::encode(rebuilt.as_bytes()) != s.script_hex {
        return Err("HTLC script does not match swap state".into());
    }
    if s.chain == "bitcoin" {
        let wallet = state.bitcoin.as_ref().ok_or("Bitcoin wallet not open")?;
        let destination = wallet
            .get_fresh_address()
            .map_err(|e| e.to_string())?
            .address
            .to_string();
        let secret =
            bdk::bitcoin::secp256k1::SecretKey::from_slice(&s.key).map_err(|e| e.to_string())?;
        let tx = spend_bitcoin_htlc(
            &BitcoinSpendRequest {
                funding_txid: s.funding_txid.into(),
                funding_vout: s.funding_vout,
                amount_sats: s.amount,
                destination,
                terms: s.terms,
                preimage_hex: s.preimage,
                fee_sats: CLAIM_FEE_SATS,
            },
            &secret,
        )
        .map_err(|e| e.to_string())?;
        wallet
            .broadcast(tx)
            .map(|t| t.to_string())
            .map_err(|e| e.to_string())
    } else {
        let wallet = state.liquid.as_ref().ok_or("Liquid wallet not open")?;
        let tx = spend_liquid_htlc(
            wallet,
            &LiquidHtlcSpendRequest {
                funding_txid: s.funding_txid.into(),
                funding_vout: s.funding_vout,
                asset_id: s.asset.into(),
                amount_sats: s.amount,
                script_hex: s.script_hex.into(),
                payment_hash: s.terms.payment_hash.clone(),
                timeout: s.terms.timeout,
                preimage_hex: s.preimage,
                fee_sats: CLAIM_FEE_SATS,
            },
            &s.key,
        )
        .map_err(|e| e.to_string())?;
        templar_core::liquid::liquidex::broadcast_transaction_on(&tx, &state.liquid_network)
            .map_err(|e| e.to_string())
    }
}

fn contract(chain: &str, terms: HtlcTerms) -> Result<templar_core::HtlcContract, String> {
    match chain {
        "bitcoin" => bitcoin_contract(terms),
        "liquid" => liquid_contract(terms),
        _ => return Err("Unknown chain".into()),
    }
    .map_err(|e| e.to_string())
}

fn require_testnet_software(state: &AppState, wallet_id: &str) -> Result<(), String> {
    if state.liquid_network.name() != NETWORK {
        return Err("Cross-chain swaps v1 require Liquid testnet".into());
    }
    let entry = state.registry.find(wallet_id).ok_or("Wallet not found")?;
    if !matches!(entry.profile, WalletProfile::Software { .. }) {
        return Err("Cross-chain swaps v1 currently require a software wallet".into());
    }
    if state.bitcoin.is_none() || state.liquid.is_none() {
        return Err("Open a wallet with both Bitcoin and Liquid enabled".into());
    }
    Ok(())
}

fn mnemonic<'a>(state: &'a AppState, wallet_id: &str) -> Result<&'a str, String> {
    match &state
        .registry
        .find(wallet_id)
        .ok_or("Wallet not found")?
        .profile
    {
        WalletProfile::Software { mnemonic } => Ok(mnemonic),
        _ => Err("Software wallet required".into()),
    }
}

fn owned(state: &AppState, wallet_id: &str, offer_id: u64) -> Result<StoredAtomicSwap, String> {
    load_store(state)?
        .swaps
        .into_iter()
        .find(|s| s.wallet_id == wallet_id && s.offer_id == offer_id)
        .ok_or_else(|| "This wallet is not a participant in the swap".into())
}

fn enrich(row: AtomicSwapRow, wallet_id: &str, role: &str, key_index: u32) -> MyAtomicSwap {
    let now = now_secs();
    let can_fund = (role == "maker" && row.status == "reserved")
        || (role == "taker" && row.status == "maker_funded");
    let can_claim = (role == "maker" && row.status == "taker_funded")
        || (role == "taker" && row.status == "maker_claimed");
    let timeout = if role == "maker" {
        Some(row.state.maker_timeout)
    } else {
        row.state.taker_timeout
    };
    let funded = if role == "maker" {
        row.state.maker_funding_txid.is_some()
    } else {
        row.state.taker_funding_txid.is_some()
    };
    let can_refund = funded
        && timeout.is_some_and(|t| now >= t)
        && !matches!(
            row.status.as_str(),
            "completed" | "maker_refunded" | "taker_refunded"
        );
    let next_action = if can_fund {
        "fund"
    } else if can_claim {
        "claim"
    } else if can_refund {
        "refund"
    } else {
        "wait"
    }
    .to_string();
    MyAtomicSwap {
        offer_id: row.id,
        wallet_id: wallet_id.into(),
        role: role.into(),
        key_index,
        row,
        next_action,
        can_fund,
        can_claim,
        can_refund,
    }
}

fn transition(row: &AtomicSwapRow, status: &str) -> Result<AtomicSwapRow, String> {
    put_json(
        &format!("{API}/{}", row.id),
        &serde_json::json!({ "status": status, "state": row.state }),
    )
}
fn fetch(id: u64) -> Result<AtomicSwapRow, String> {
    get_json(&format!("{API}/{id}"))
}

fn client() -> Result<reqwest::blocking::Client, String> {
    reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(15))
        .build()
        .map_err(|e| e.to_string())
}
fn response<T: for<'de> Deserialize<'de>>(r: reqwest::blocking::Response) -> Result<T, String> {
    let status = r.status();
    let body = r.text().map_err(|e| e.to_string())?;
    if !status.is_success() {
        let msg = serde_json::from_str::<serde_json::Value>(&body)
            .ok()
            .and_then(|v| v["error"].as_str().map(str::to_string))
            .unwrap_or(body);
        return Err(format!("Order book HTTP {}: {msg}", status.as_u16()));
    }
    serde_json::from_str(&body).map_err(|e| format!("Order book response: {e}"))
}
fn get_json<T: for<'de> Deserialize<'de>>(url: &str) -> Result<T, String> {
    response(client()?.get(url).send().map_err(|e| e.to_string())?)
}
fn post_json<T: for<'de> Deserialize<'de>>(
    url: &str,
    body: &serde_json::Value,
) -> Result<T, String> {
    response(
        client()?
            .post(url)
            .json(body)
            .send()
            .map_err(|e| e.to_string())?,
    )
}
fn put_json<T: for<'de> Deserialize<'de>>(
    url: &str,
    body: &serde_json::Value,
) -> Result<T, String> {
    response(
        client()?
            .put(url)
            .json(body)
            .send()
            .map_err(|e| e.to_string())?,
    )
}

fn store_path(state: &AppState) -> std::path::PathBuf {
    state.data_dir.join(STORE_FILE)
}
fn load_store(state: &AppState) -> Result<AtomicStore, String> {
    let path = store_path(state);
    if !path.exists() {
        return Ok(AtomicStore::default());
    }
    serde_json::from_str(&fs::read_to_string(path).map_err(|e| e.to_string())?)
        .map_err(|e| format!("{STORE_FILE}: {e}"))
}
fn save_store(state: &AppState, store: &AtomicStore) -> Result<(), String> {
    let raw = serde_json::to_string_pretty(store).map_err(|e| e.to_string())?;
    templar_core::registry::atomic_write(&store_path(state), &raw).map_err(|e| e.to_string())
}
fn next_index(store: &AtomicStore, wallet_id: &str) -> u32 {
    store
        .swaps
        .iter()
        .filter(|s| s.wallet_id == wallet_id)
        .map(|s| s.key_index)
        .max()
        .map_or(0, |i| i.saturating_add(1))
}
fn deterministic_preimage(key: &[u8; 32]) -> [u8; 32] {
    use bdk::bitcoin::hashes::{sha256, Hash, HashEngine};
    let mut e = sha256::Hash::engine();
    e.input(b"Templar atomic swap preimage v1");
    e.input(key);
    sha256::Hash::from_engine(e).to_byte_array()
}
fn sha256_hex(data: &[u8]) -> String {
    use bdk::bitcoin::hashes::{sha256, Hash};
    sha256::Hash::hash(data).to_string()
}
fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn deterministic_secret_is_stable_and_domain_separated() {
        let key = [7u8; 32];
        assert_eq!(deterministic_preimage(&key), deterministic_preimage(&key));
        assert_ne!(deterministic_preimage(&key), key);
        assert_eq!(sha256_hex(&deterministic_preimage(&key)).len(), 64);
    }
}
