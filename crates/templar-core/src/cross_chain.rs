//! Testnet-only Bitcoin <-> Liquid atomic-swap primitives.
//!
//! The order book never receives private keys or the preimage before the
//! maker claims. Both chains use the same SHA256 HTLC:
//!
//! `IF SHA256 <hash> EQUALVERIFY <claim key> CHECKSIG
//!  ELSE <timeout> CLTV DROP <refund key> CHECKSIG ENDIF`.
//!
//! Liquid funding outputs are deliberately explicit in v1. This exposes the
//! swap asset and amount, but makes the contract independently verifiable by
//! the other wallet without exchanging a blinding key. Normal wallet change
//! and claim outputs remain confidential.

use std::str::FromStr;

use bdk::bitcoin::bip32::{ChildNumber, DerivationPath, ExtendedPrivKey};
use bdk::bitcoin::{
    absolute, consensus,
    hashes::{sha256, Hash},
    opcodes::all::*,
    script::{Builder, PushBytesBuf},
    secp256k1::{Message, PublicKey, Secp256k1, SecretKey},
    sighash::{EcdsaSighashType, SighashCache},
    Address, Network, OutPoint, ScriptBuf, Sequence, Transaction, TxIn, TxOut, Witness,
};
use bdk::keys::bip39::Mnemonic;
use bdk::keys::{DerivableKey, ExtendedKey};
use getrandom::getrandom;
use serde::{Deserialize, Serialize};

use crate::error::{BitcoinError, TemplarError};

pub const MAKER_TIMEOUT_SECS: u64 = 48 * 60 * 60;
pub const TAKER_TIMEOUT_SECS: u64 = 24 * 60 * 60;
pub const MIN_CROSS_AMOUNT_SATS: u64 = 1_000;
const KEY_PURPOSE: u32 = 1_017;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CrossChain {
    Bitcoin,
    Liquid,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HtlcTerms {
    pub payment_hash: String,
    pub claim_pubkey: String,
    pub refund_pubkey: String,
    pub timeout: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HtlcContract {
    pub chain: CrossChain,
    pub address: String,
    pub script_hex: String,
    pub terms: HtlcTerms,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SwapSecret {
    pub preimage: [u8; 32],
    pub payment_hash: [u8; 32],
}

pub fn new_swap_secret() -> Result<SwapSecret, TemplarError> {
    let mut preimage = [0u8; 32];
    getrandom(&mut preimage)
        .map_err(|e| BitcoinError::TxBuildFailed(format!("swap entropy: {e}")))?;
    let payment_hash = sha256::Hash::hash(&preimage).to_byte_array();
    Ok(SwapSecret {
        preimage,
        payment_hash,
    })
}

pub fn payment_hash_hex(preimage: &[u8]) -> String {
    sha256::Hash::hash(preimage).to_string()
}

/// Dedicated BIP32 branch: `m/1017'/1'/0'/role/index`.
/// It is intentionally outside normal BIP84 receive/change branches.
pub fn derive_swap_secret_key(
    mnemonic: &str,
    role: u32,
    index: u32,
) -> Result<SecretKey, TemplarError> {
    if role > 1 {
        return Err(BitcoinError::InvalidMnemonic("swap role must be 0 or 1".into()).into());
    }
    let mnemonic =
        Mnemonic::parse(mnemonic).map_err(|e| BitcoinError::InvalidMnemonic(e.to_string()))?;
    let xkey: ExtendedKey = mnemonic
        .into_extended_key()
        .map_err(|e| BitcoinError::InvalidMnemonic(format!("ExtendedKey: {e}")))?;
    let root = xkey
        .into_xprv(Network::Testnet)
        .ok_or_else(|| BitcoinError::InvalidMnemonic("Cannot derive swap root".into()))?;
    let path = DerivationPath::from(vec![
        ChildNumber::from_hardened_idx(KEY_PURPOSE).expect("constant"),
        ChildNumber::from_hardened_idx(1).expect("constant"),
        ChildNumber::from_hardened_idx(0).expect("constant"),
        ChildNumber::from_normal_idx(role).expect("validated"),
        ChildNumber::from_normal_idx(index)
            .map_err(|e| BitcoinError::InvalidMnemonic(format!("swap index: {e}")))?,
    ]);
    let child = ExtendedPrivKey::derive_priv(&root, &Secp256k1::new(), &path)
        .map_err(|e| BitcoinError::InvalidMnemonic(format!("swap key derivation: {e}")))?;
    Ok(child.private_key)
}

pub fn swap_public_key(secret: &SecretKey) -> PublicKey {
    PublicKey::from_secret_key(&Secp256k1::new(), secret)
}

pub fn htlc_script(terms: &HtlcTerms) -> Result<ScriptBuf, TemplarError> {
    let hash = hex::decode(&terms.payment_hash)
        .map_err(|e| BitcoinError::TxBuildFailed(format!("payment hash: {e}")))?;
    let hash = PushBytesBuf::try_from(hash)
        .map_err(|e| BitcoinError::TxBuildFailed(format!("payment hash push: {e}")))?;
    if hash.len() != 32 {
        return Err(BitcoinError::TxBuildFailed("payment hash must be 32 bytes".into()).into());
    }
    let claim = PublicKey::from_str(&terms.claim_pubkey)
        .map_err(|e| BitcoinError::TxBuildFailed(format!("claim pubkey: {e}")))?;
    let refund = PublicKey::from_str(&terms.refund_pubkey)
        .map_err(|e| BitcoinError::TxBuildFailed(format!("refund pubkey: {e}")))?;
    let claim = PushBytesBuf::try_from(claim.serialize().to_vec()).expect("33 bytes");
    let refund = PushBytesBuf::try_from(refund.serialize().to_vec()).expect("33 bytes");
    let timeout = i64::try_from(terms.timeout)
        .map_err(|_| BitcoinError::TxBuildFailed("timeout exceeds script integer".into()))?;
    Ok(Builder::new()
        .push_opcode(OP_IF)
        .push_opcode(OP_SHA256)
        .push_slice(hash)
        .push_opcode(OP_EQUALVERIFY)
        .push_slice(claim)
        .push_opcode(OP_CHECKSIG)
        .push_opcode(OP_ELSE)
        .push_int(timeout)
        .push_opcode(OP_CLTV)
        .push_opcode(OP_DROP)
        .push_slice(refund)
        .push_opcode(OP_CHECKSIG)
        .push_opcode(OP_ENDIF)
        .into_script())
}

pub fn bitcoin_contract(terms: HtlcTerms) -> Result<HtlcContract, TemplarError> {
    let script = htlc_script(&terms)?;
    Ok(HtlcContract {
        chain: CrossChain::Bitcoin,
        address: Address::p2wsh(&script, Network::Testnet).to_string(),
        script_hex: hex::encode(script.as_bytes()),
        terms,
    })
}

pub fn liquid_contract(terms: HtlcTerms) -> Result<HtlcContract, TemplarError> {
    use lwk_wollet::elements::{Address as EAddress, AddressParams, Script};
    let script = htlc_script(&terms)?;
    let escript = Script::from(script.as_bytes().to_vec());
    let address = EAddress::p2wsh(&escript, None, &AddressParams::LIQUID_TESTNET);
    Ok(HtlcContract {
        chain: CrossChain::Liquid,
        address: address.to_string(),
        script_hex: hex::encode(script.as_bytes()),
        terms,
    })
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BitcoinSpendRequest {
    pub funding_txid: String,
    pub funding_vout: u32,
    pub amount_sats: u64,
    pub destination: String,
    pub terms: HtlcTerms,
    pub preimage_hex: Option<String>,
    pub fee_sats: u64,
}

/// Builds and signs a Bitcoin HTLC claim or refund. Refund mode is selected
/// when `preimage_hex` is absent and uses the contract CLTV as nLockTime.
pub fn spend_bitcoin_htlc(
    request: &BitcoinSpendRequest,
    key: &SecretKey,
) -> Result<Transaction, TemplarError> {
    if request.fee_sats >= request.amount_sats {
        return Err(BitcoinError::TxBuildFailed("HTLC fee consumes the output".into()).into());
    }
    let script = htlc_script(&request.terms)?;
    let txid = request
        .funding_txid
        .parse()
        .map_err(|e| BitcoinError::TxBuildFailed(format!("funding txid: {e}")))?;
    let destination = Address::from_str(&request.destination)
        .map_err(|e| BitcoinError::TxBuildFailed(format!("destination: {e}")))?
        .require_network(Network::Testnet)
        .map_err(|e| BitcoinError::TxBuildFailed(format!("destination network: {e}")))?;
    let claim = request.preimage_hex.is_some();
    let lock_time = if claim {
        absolute::LockTime::ZERO
    } else {
        absolute::LockTime::from_consensus(request.terms.timeout as u32)
    };
    let mut tx = Transaction {
        version: 2,
        lock_time,
        input: vec![TxIn {
            previous_output: OutPoint {
                txid,
                vout: request.funding_vout,
            },
            script_sig: ScriptBuf::new(),
            sequence: Sequence::ENABLE_LOCKTIME_NO_RBF,
            witness: Witness::new(),
        }],
        output: vec![TxOut {
            value: request.amount_sats - request.fee_sats,
            script_pubkey: destination.script_pubkey(),
        }],
    };
    let sighash = SighashCache::new(&tx)
        .segwit_signature_hash(0, &script, request.amount_sats, EcdsaSighashType::All)
        .map_err(|e| BitcoinError::SigningFailed(format!("HTLC sighash: {e}")))?;
    let msg = Message::from_slice(sighash.as_ref())
        .map_err(|e| BitcoinError::SigningFailed(format!("HTLC message: {e}")))?;
    let mut sig = Secp256k1::new()
        .sign_ecdsa(&msg, key)
        .serialize_der()
        .to_vec();
    sig.push(EcdsaSighashType::All as u8);
    let mut witness = Witness::new();
    witness.push(sig);
    if let Some(preimage) = &request.preimage_hex {
        let preimage = hex::decode(preimage)
            .map_err(|e| BitcoinError::SigningFailed(format!("preimage: {e}")))?;
        if sha256::Hash::hash(&preimage).to_string() != request.terms.payment_hash {
            return Err(
                BitcoinError::SigningFailed("preimage does not match payment hash".into()).into(),
            );
        }
        witness.push(preimage);
        witness.push([1u8]);
    } else {
        witness.push([]);
    }
    witness.push(script.as_bytes());
    tx.input[0].witness = witness;
    Ok(tx)
}

pub fn bitcoin_tx_hex(tx: &Transaction) -> String {
    hex::encode(consensus::serialize(tx))
}

#[cfg(test)]
mod tests {
    use super::*;

    const MNEMONIC: &str =
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

    fn terms() -> HtlcTerms {
        let maker = derive_swap_secret_key(MNEMONIC, 0, 7).unwrap();
        let taker = derive_swap_secret_key(MNEMONIC, 1, 7).unwrap();
        HtlcTerms {
            payment_hash: sha256::Hash::hash(&[42u8; 32]).to_string(),
            claim_pubkey: swap_public_key(&taker).to_string(),
            refund_pubkey: swap_public_key(&maker).to_string(),
            timeout: 1_900_000_000,
        }
    }

    #[test]
    fn contracts_share_the_exact_script() {
        let b = bitcoin_contract(terms()).unwrap();
        let l = liquid_contract(terms()).unwrap();
        assert_eq!(b.script_hex, l.script_hex);
        assert!(b.address.starts_with("tb1q"));
        assert!(l.address.starts_with("tex1"));
        assert_eq!(hex::decode(&b.script_hex).unwrap()[0], OP_IF.to_u8());
    }

    #[test]
    fn swap_key_branch_is_deterministic_and_role_separated() {
        let a = derive_swap_secret_key(MNEMONIC, 0, 9).unwrap();
        let b = derive_swap_secret_key(MNEMONIC, 0, 9).unwrap();
        let c = derive_swap_secret_key(MNEMONIC, 1, 9).unwrap();
        assert_eq!(a.secret_bytes(), b.secret_bytes());
        assert_ne!(a.secret_bytes(), c.secret_bytes());
    }

    #[test]
    fn bitcoin_claim_and_refund_have_expected_witnesses() {
        let terms = terms();
        let key = derive_swap_secret_key(MNEMONIC, 1, 7).unwrap();
        let destination = Address::p2wpkh(
            &bdk::bitcoin::PublicKey::new(swap_public_key(&key)),
            Network::Testnet,
        )
        .unwrap()
        .to_string();
        let base = BitcoinSpendRequest {
            funding_txid: "11".repeat(32),
            funding_vout: 0,
            amount_sats: 100_000,
            destination,
            terms: terms.clone(),
            preimage_hex: Some(hex::encode([42u8; 32])),
            fee_sats: 500,
        };
        let claim = spend_bitcoin_htlc(&base, &key).unwrap();
        assert_eq!(claim.input[0].witness.len(), 4);
        assert_eq!(claim.lock_time, absolute::LockTime::ZERO);
        let refund_key = derive_swap_secret_key(MNEMONIC, 0, 7).unwrap();
        let refund = spend_bitcoin_htlc(
            &BitcoinSpendRequest {
                preimage_hex: None,
                ..base
            },
            &refund_key,
        )
        .unwrap();
        assert_eq!(refund.input[0].witness.len(), 3);
        assert_eq!(refund.lock_time.to_consensus_u32(), terms.timeout as u32);
    }
}
