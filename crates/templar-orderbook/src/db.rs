use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use rusqlite::types::Type;
use rusqlite::{params, Connection, OpenFlags, OptionalExtension, TransactionBehavior};
use serde::{Deserialize, Serialize};

use templar_core::liquid::network::ENV_REGTEST_POLICY_ASSET;
use templar_core::{LiquidNetwork, TESTNET_POLICY_ASSET};

pub const TESTNET: &str = "liquid-testnet";
pub const REGTEST: &str = "liquid-regtest";

#[derive(Debug, Clone)]
pub struct Database {
    path: PathBuf,
    regtest_policy_asset: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AssetRow {
    pub network: String,
    pub asset_id: String,
    pub ticker: String,
    pub name: String,
    pub precision: u8,
    pub is_policy_asset: bool,
    pub created_at: u64,
    pub updated_at: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AssetInput {
    pub network: String,
    pub asset_id: String,
    pub ticker: String,
    pub name: String,
    pub precision: u8,
    #[serde(default)]
    pub is_policy_asset: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct OfferRow {
    pub id: u64,
    pub network: String,
    pub status: String,
    pub proposal_json: String,
    pub offered_asset_id: String,
    pub offered_amount_sats: u64,
    pub offered_ticker: String,
    pub offered_name: String,
    pub offered_precision: u8,
    pub wanted_asset_id: String,
    pub wanted_amount_sats: u64,
    pub wanted_ticker: String,
    pub wanted_name: String,
    pub wanted_precision: u8,
    pub note: String,
    pub created_at: u64,
    pub updated_at: u64,
}

#[derive(Debug, Clone)]
pub struct NewOffer {
    pub network: String,
    pub proposal_json: String,
    pub offered_asset_id: String,
    pub offered_amount_sats: u64,
    pub wanted_asset_id: String,
    pub wanted_amount_sats: u64,
    pub note: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct OfferUpdate {
    pub status: String,
    #[serde(default)]
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct DemoOfferRow {
    pub id: u64,
    pub network: String,
    pub status: String,
    pub settlement: String,
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
    pub note: String,
    pub created_at: u64,
    pub updated_at: u64,
}

#[derive(Debug, Clone)]
pub struct NewDemoOffer {
    pub network: String,
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
    pub note: String,
}

/// Public coordinator state for a real testnet cross-chain atomic swap.
/// Private keys and the preimage before the maker claim never enter SQLite.
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
    #[serde(default)]
    pub taker_claim_pubkey: Option<String>,
    pub maker_timeout: u64,
    #[serde(default)]
    pub taker_timeout: Option<u64>,
    #[serde(default)]
    pub maker_contract_address: Option<String>,
    #[serde(default)]
    pub maker_contract_script: Option<String>,
    #[serde(default)]
    pub taker_contract_address: Option<String>,
    #[serde(default)]
    pub taker_contract_script: Option<String>,
    #[serde(default)]
    pub maker_funding_txid: Option<String>,
    #[serde(default)]
    pub maker_funding_tx_hex: Option<String>,
    #[serde(default)]
    pub maker_funding_vout: Option<u32>,
    #[serde(default)]
    pub taker_funding_txid: Option<String>,
    #[serde(default)]
    pub taker_funding_tx_hex: Option<String>,
    #[serde(default)]
    pub taker_funding_vout: Option<u32>,
    #[serde(default)]
    pub preimage_hex: Option<String>,
    #[serde(default)]
    pub maker_claim_txid: Option<String>,
    #[serde(default)]
    pub taker_claim_txid: Option<String>,
    #[serde(default)]
    pub maker_refund_txid: Option<String>,
    #[serde(default)]
    pub taker_refund_txid: Option<String>,
    #[serde(default)]
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

#[derive(Debug, Clone, Deserialize)]
pub struct AtomicSwapCreate {
    pub network: String,
    pub state: AtomicSwapState,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AtomicSwapTransition {
    pub status: String,
    pub state: AtomicSwapState,
}

impl Database {
    pub fn open(path: PathBuf) -> Result<Self, String> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .map_err(|e| format!("Cannot create {}: {e}", parent.display()))?;
        }
        let configured_policy = std::env::var(ENV_REGTEST_POLICY_ASSET).unwrap_or_default();
        let regtest_policy_asset = LiquidNetwork::regtest(&configured_policy)
            .map_err(|e| format!("Invalid {ENV_REGTEST_POLICY_ASSET}: {e}"))?
            .policy_asset_hex();
        let database = Self {
            path,
            regtest_policy_asset,
        };
        database.migrate()?;
        Ok(database)
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn regtest_policy_asset(&self) -> &str {
        &self.regtest_policy_asset
    }

    fn connection(&self) -> Result<Connection, String> {
        let flags = OpenFlags::SQLITE_OPEN_READ_WRITE
            | OpenFlags::SQLITE_OPEN_CREATE
            | OpenFlags::SQLITE_OPEN_NO_MUTEX;
        let conn = Connection::open_with_flags(&self.path, flags)
            .map_err(|e| format!("Open SQLite {}: {e}", self.path.display()))?;
        conn.busy_timeout(Duration::from_secs(5))
            .map_err(|e| format!("Configure SQLite busy timeout: {e}"))?;
        conn.pragma_update(None, "foreign_keys", "ON")
            .map_err(|e| format!("Enable SQLite foreign keys: {e}"))?;
        conn.pragma_update(None, "synchronous", "FULL")
            .map_err(|e| format!("Configure SQLite durability: {e}"))?;
        Ok(conn)
    }

    fn migrate(&self) -> Result<(), String> {
        let mut conn = self.connection()?;
        conn.pragma_update(None, "journal_mode", "WAL")
            .map_err(|e| format!("Enable SQLite WAL: {e}"))?;
        let version: i64 = conn
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .map_err(|e| format!("Read database version: {e}"))?;
        if version > 3 {
            return Err(format!(
                "Database schema {version} is newer than this server supports"
            ));
        }
        let mut current_version = version;
        if current_version == 0 {
            let tx = conn
                .transaction_with_behavior(TransactionBehavior::Immediate)
                .map_err(|e| format!("Start database migration: {e}"))?;
            tx.execute_batch(
                "CREATE TABLE assets (
                    network TEXT NOT NULL CHECK(network IN ('liquid-testnet','liquid-regtest')),
                    asset_id TEXT NOT NULL CHECK(length(asset_id) = 64),
                    ticker TEXT NOT NULL CHECK(length(ticker) BETWEEN 1 AND 16),
                    name TEXT NOT NULL CHECK(length(name) BETWEEN 1 AND 80),
                    precision INTEGER NOT NULL CHECK(precision BETWEEN 0 AND 8),
                    is_policy_asset INTEGER NOT NULL DEFAULT 0 CHECK(is_policy_asset IN (0,1)),
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    PRIMARY KEY(network, asset_id)
                );
                CREATE TABLE offers (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    network TEXT NOT NULL CHECK(network IN ('liquid-testnet','liquid-regtest')),
                    status TEXT NOT NULL DEFAULT 'open'
                        CHECK(status IN ('open','paused','filled','cancelled')),
                    proposal_json TEXT NOT NULL,
                    offered_asset_id TEXT NOT NULL,
                    offered_amount_sats INTEGER NOT NULL CHECK(offered_amount_sats > 0),
                    wanted_asset_id TEXT NOT NULL,
                    wanted_amount_sats INTEGER NOT NULL CHECK(wanted_amount_sats > 0),
                    note TEXT NOT NULL DEFAULT '',
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    UNIQUE(network, proposal_json),
                    FOREIGN KEY(network, offered_asset_id)
                        REFERENCES assets(network, asset_id) ON UPDATE CASCADE ON DELETE RESTRICT,
                    FOREIGN KEY(network, wanted_asset_id)
                        REFERENCES assets(network, asset_id) ON UPDATE CASCADE ON DELETE RESTRICT
                );
                CREATE INDEX offers_network_status_created
                    ON offers(network, status, created_at DESC);
                PRAGMA user_version = 1;",
            )
            .map_err(|e| format!("Apply database migration 1: {e}"))?;
            tx.commit()
                .map_err(|e| format!("Commit database migration: {e}"))?;
            current_version = 1;
        }
        if current_version == 1 {
            if version == 1 {
                conn.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);")
                    .map_err(|e| format!("Checkpoint database before migration 2: {e}"))?;
                let backup = schema_v1_backup_path(&self.path);
                if !backup.exists() {
                    fs::copy(&self.path, &backup).map_err(|e| {
                        format!("Back up schema 1 database to {}: {e}", backup.display())
                    })?;
                }
            }
            let tx = conn
                .transaction_with_behavior(TransactionBehavior::Immediate)
                .map_err(|e| format!("Start database migration 2: {e}"))?;
            tx.execute_batch(
                "CREATE TABLE demo_offers (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    network TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'open'
                        CHECK(status IN ('open','paused','filled','cancelled')),
                    settlement TEXT NOT NULL DEFAULT 'htlc-demo',
                    offered_chain TEXT NOT NULL,
                    offered_asset_id TEXT NOT NULL,
                    offered_ticker TEXT NOT NULL,
                    offered_name TEXT NOT NULL,
                    offered_precision INTEGER NOT NULL CHECK(offered_precision BETWEEN 0 AND 8),
                    offered_amount_sats INTEGER NOT NULL CHECK(offered_amount_sats > 0),
                    wanted_chain TEXT NOT NULL,
                    wanted_asset_id TEXT NOT NULL,
                    wanted_ticker TEXT NOT NULL,
                    wanted_name TEXT NOT NULL,
                    wanted_precision INTEGER NOT NULL CHECK(wanted_precision BETWEEN 0 AND 8),
                    wanted_amount_sats INTEGER NOT NULL CHECK(wanted_amount_sats > 0),
                    note TEXT NOT NULL DEFAULT '',
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    CHECK(offered_chain <> wanted_chain)
                );
                CREATE INDEX demo_offers_network_status_created
                    ON demo_offers(network, status, created_at DESC);
                PRAGMA user_version = 2;",
            )
            .map_err(|e| format!("Apply database migration 2: {e}"))?;
            tx.commit()
                .map_err(|e| format!("Commit database migration 2: {e}"))?;
            current_version = 2;
        }
        if current_version == 2 {
            if version == 2 {
                conn.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);")
                    .map_err(|e| format!("Checkpoint database before migration 3: {e}"))?;
                let backup = schema_backup_path(&self.path, 2);
                if !backup.exists() {
                    fs::copy(&self.path, &backup).map_err(|e| {
                        format!("Back up schema 2 database to {}: {e}", backup.display())
                    })?;
                }
            }
            let tx = conn
                .transaction_with_behavior(TransactionBehavior::Immediate)
                .map_err(|e| format!("Start database migration 3: {e}"))?;
            tx.execute_batch(
                "CREATE TABLE IF NOT EXISTS atomic_swaps (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    network TEXT NOT NULL CHECK(network = 'liquid-testnet'),
                    status TEXT NOT NULL DEFAULT 'open'
                        CHECK(status IN ('open','reserved','maker_funded','taker_funded',
                            'maker_claimed','completed','cancelled','maker_refunded',
                            'taker_refunded','failed')),
                    state_json TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                );
                CREATE INDEX IF NOT EXISTS atomic_swaps_network_status_created
                    ON atomic_swaps(network, status, created_at DESC);
                PRAGMA user_version = 3;",
            )
            .map_err(|e| format!("Apply database migration 3: {e}"))?;
            tx.commit()
                .map_err(|e| format!("Commit database migration 3: {e}"))?;
        }
        self.seed_policy_assets()
    }

    fn seed_policy_assets(&self) -> Result<(), String> {
        let mut conn = self.connection()?;
        let tx = conn
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(|e| format!("Start policy-asset seed: {e}"))?;
        let now = to_i64(now_secs())?;
        for input in [
            AssetInput {
                network: TESTNET.to_string(),
                asset_id: TESTNET_POLICY_ASSET.to_string(),
                ticker: "LBTC".to_string(),
                name: "Liquid Bitcoin".to_string(),
                precision: 8,
                is_policy_asset: true,
            },
            AssetInput {
                network: REGTEST.to_string(),
                asset_id: self.regtest_policy_asset.clone(),
                ticker: "LBTC".to_string(),
                name: "Liquid Bitcoin".to_string(),
                precision: 8,
                is_policy_asset: true,
            },
        ] {
            validate_asset(&input)?;
            tx.execute(
                "UPDATE assets SET is_policy_asset = 0, updated_at = ?3
                 WHERE network = ?1 AND asset_id <> ?2 AND is_policy_asset = 1",
                params![input.network, input.asset_id.to_ascii_lowercase(), now],
            )
            .map_err(|e| format!("Retire previous policy asset: {e}"))?;
            tx.execute(
                "INSERT INTO assets
                    (network, asset_id, ticker, name, precision, is_policy_asset,
                     created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, 1, ?6, ?6)
                 ON CONFLICT(network, asset_id) DO UPDATE SET
                    is_policy_asset = 1,
                    updated_at = excluded.updated_at",
                params![
                    input.network,
                    input.asset_id.to_ascii_lowercase(),
                    input.ticker,
                    input.name,
                    input.precision,
                    now,
                ],
            )
            .map_err(|e| format!("Seed policy asset: {e}"))?;
        }
        tx.commit()
            .map_err(|e| format!("Commit policy-asset seed: {e}"))
    }

    pub fn health(&self) -> Result<(), String> {
        let conn = self.connection()?;
        let value: i64 = conn
            .query_row("SELECT 1", [], |row| row.get(0))
            .map_err(|e| format!("SQLite health check: {e}"))?;
        if value == 1 {
            Ok(())
        } else {
            Err("SQLite health check returned an unexpected value".to_string())
        }
    }

    pub fn list_assets(&self, network: &str) -> Result<Vec<AssetRow>, String> {
        validate_network(network)?;
        let conn = self.connection()?;
        let mut stmt = conn
            .prepare(
                "SELECT network, asset_id, ticker, name, precision, is_policy_asset,
                        created_at, updated_at
                 FROM assets WHERE network = ?1
                 ORDER BY is_policy_asset DESC, ticker COLLATE NOCASE, asset_id",
            )
            .map_err(|e| format!("Prepare asset list: {e}"))?;
        let rows = stmt
            .query_map([network], asset_from_row)
            .map_err(|e| format!("Query assets: {e}"))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Read asset: {e}"))
    }

    pub fn upsert_asset(&self, input: &AssetInput) -> Result<AssetRow, String> {
        validate_asset(input)?;
        let now = now_secs();
        let conn = self.connection()?;
        conn.execute(
            "INSERT INTO assets
                (network, asset_id, ticker, name, precision, is_policy_asset, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7)
             ON CONFLICT(network, asset_id) DO UPDATE SET
                ticker = excluded.ticker,
                name = excluded.name,
                precision = excluded.precision,
                is_policy_asset = excluded.is_policy_asset,
                updated_at = excluded.updated_at",
            params![
                input.network,
                input.asset_id.to_ascii_lowercase(),
                input.ticker.trim().to_ascii_uppercase(),
                input.name.trim(),
                input.precision,
                input.is_policy_asset,
                to_i64(now)?
            ],
        )
        .map_err(|e| format!("Save asset: {e}"))?;
        self.get_asset(&input.network, &input.asset_id)?
            .ok_or("Saved asset could not be read back".to_string())
    }

    pub fn delete_asset(&self, network: &str, asset_id: &str) -> Result<(), String> {
        validate_network(network)?;
        validate_asset_id(asset_id)?;
        let conn = self.connection()?;
        let changed = conn
            .execute(
                "DELETE FROM assets
                 WHERE network = ?1 AND asset_id = ?2 AND is_policy_asset = 0",
                params![network, asset_id.to_ascii_lowercase()],
            )
            .map_err(|e| format!("Delete asset: {e}"))?;
        if changed == 0 {
            Err("Asset not found or is the protected LBTC policy asset".to_string())
        } else {
            Ok(())
        }
    }

    pub fn create_offer(&self, offer: &NewOffer) -> Result<OfferRow, String> {
        validate_network(&offer.network)?;
        validate_asset_id(&offer.offered_asset_id)?;
        validate_asset_id(&offer.wanted_asset_id)?;
        if offer.offered_amount_sats == 0 || offer.wanted_amount_sats == 0 {
            return Err("Offer amounts must be greater than zero".to_string());
        }
        let mut conn = self.connection()?;
        let tx = conn
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(|e| format!("Start offer transaction: {e}"))?;
        ensure_asset_placeholder(&tx, &offer.network, &offer.offered_asset_id)?;
        ensure_asset_placeholder(&tx, &offer.network, &offer.wanted_asset_id)?;
        let now = now_secs();
        tx.execute(
            "INSERT INTO offers
                (network, status, proposal_json, offered_asset_id, offered_amount_sats,
                 wanted_asset_id, wanted_amount_sats, note, created_at, updated_at)
             VALUES (?1, 'open', ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8)",
            params![
                offer.network,
                offer.proposal_json,
                offer.offered_asset_id.to_ascii_lowercase(),
                to_i64(offer.offered_amount_sats)?,
                offer.wanted_asset_id.to_ascii_lowercase(),
                to_i64(offer.wanted_amount_sats)?,
                offer.note.trim(),
                to_i64(now)?,
            ],
        )
        .map_err(|e| format!("Publish offer: {e}"))?;
        let id = tx.last_insert_rowid() as u64;
        tx.commit().map_err(|e| format!("Commit offer: {e}"))?;
        self.get_offer(id)?
            .ok_or("Published offer could not be read back".to_string())
    }

    pub fn list_offers(&self, network: &str, include_all: bool) -> Result<Vec<OfferRow>, String> {
        validate_network(network)?;
        let conn = self.connection()?;
        let sql = if include_all {
            format!(
                "{} WHERE o.network = ?1 ORDER BY o.created_at DESC, o.id DESC",
                OFFER_SELECT
            )
        } else {
            format!(
                "{} WHERE o.network = ?1 AND o.status = 'open' ORDER BY o.created_at DESC, o.id DESC",
                OFFER_SELECT
            )
        };
        let mut stmt = conn
            .prepare(&sql)
            .map_err(|e| format!("Prepare offer list: {e}"))?;
        let rows = stmt
            .query_map([network], offer_from_row)
            .map_err(|e| format!("Query offers: {e}"))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Read offer: {e}"))
    }

    pub fn update_offer(&self, id: u64, update: &OfferUpdate) -> Result<OfferRow, String> {
        validate_status(&update.status)?;
        let conn = self.connection()?;
        let changed = conn
            .execute(
                "UPDATE offers SET status = ?1, note = ?2, updated_at = ?3 WHERE id = ?4",
                params![
                    update.status,
                    update.note.trim(),
                    to_i64(now_secs())?,
                    to_i64(id)?
                ],
            )
            .map_err(|e| format!("Update offer: {e}"))?;
        if changed == 0 {
            return Err(format!("Unknown offer: {id}"));
        }
        self.get_offer(id)?
            .ok_or_else(|| format!("Updated offer {id} could not be read back"))
    }

    pub fn delete_offer(&self, id: u64) -> Result<(), String> {
        let conn = self.connection()?;
        let changed = conn
            .execute("DELETE FROM offers WHERE id = ?1", [to_i64(id)?])
            .map_err(|e| format!("Delete offer: {e}"))?;
        if changed == 0 {
            Err(format!("Unknown offer: {id}"))
        } else {
            Ok(())
        }
    }

    pub fn create_demo_offer(&self, offer: &NewDemoOffer) -> Result<DemoOfferRow, String> {
        validate_demo_offer(offer)?;
        let conn = self.connection()?;
        let now = to_i64(now_secs())?;
        conn.execute(
            "INSERT INTO demo_offers
                (network, status, settlement,
                 offered_chain, offered_asset_id, offered_ticker, offered_name,
                 offered_precision, offered_amount_sats,
                 wanted_chain, wanted_asset_id, wanted_ticker, wanted_name,
                 wanted_precision, wanted_amount_sats, note, created_at, updated_at)
             VALUES (?1, 'open', 'htlc-demo', ?2, ?3, ?4, ?5, ?6, ?7,
                     ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?15)",
            params![
                offer.network,
                offer.offered_chain,
                offer.offered_asset_id,
                offer.offered_ticker,
                offer.offered_name,
                offer.offered_precision,
                to_i64(offer.offered_amount_sats)?,
                offer.wanted_chain,
                offer.wanted_asset_id,
                offer.wanted_ticker,
                offer.wanted_name,
                offer.wanted_precision,
                to_i64(offer.wanted_amount_sats)?,
                offer.note.trim(),
                now,
            ],
        )
        .map_err(|e| format!("Create cross-chain demo offer: {e}"))?;
        let id = u64::try_from(conn.last_insert_rowid())
            .map_err(|e| format!("Invalid demo offer id: {e}"))?;
        self.get_demo_offer(id)?
            .ok_or("Created demo offer could not be read back".to_string())
    }

    pub fn list_demo_offers(
        &self,
        network: &str,
        include_all: bool,
    ) -> Result<Vec<DemoOfferRow>, String> {
        validate_network(network)?;
        let conn = self.connection()?;
        let filter = if include_all {
            "network = ?1"
        } else {
            "network = ?1 AND status = 'open'"
        };
        let sql = format!("{DEMO_OFFER_SELECT} WHERE {filter} ORDER BY created_at DESC, id DESC");
        let mut stmt = conn
            .prepare(&sql)
            .map_err(|e| format!("Prepare demo offer list: {e}"))?;
        let rows = stmt
            .query_map([network], demo_offer_from_row)
            .map_err(|e| format!("Query demo offers: {e}"))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Read demo offer: {e}"))
    }

    pub fn update_demo_offer(&self, id: u64, update: &OfferUpdate) -> Result<DemoOfferRow, String> {
        validate_status(&update.status)?;
        let conn = self.connection()?;
        let changed = conn
            .execute(
                "UPDATE demo_offers SET status = ?1, note = ?2, updated_at = ?3
                 WHERE id = ?4",
                params![
                    update.status,
                    update.note.trim(),
                    to_i64(now_secs())?,
                    to_i64(id)?,
                ],
            )
            .map_err(|e| format!("Update demo offer: {e}"))?;
        if changed == 0 {
            return Err(format!("Unknown demo offer: {id}"));
        }
        self.get_demo_offer(id)?
            .ok_or_else(|| format!("Updated demo offer {id} could not be read back"))
    }

    pub fn delete_demo_offer(&self, id: u64) -> Result<(), String> {
        let conn = self.connection()?;
        let changed = conn
            .execute("DELETE FROM demo_offers WHERE id = ?1", [to_i64(id)?])
            .map_err(|e| format!("Delete demo offer: {e}"))?;
        if changed == 0 {
            Err(format!("Unknown demo offer: {id}"))
        } else {
            Ok(())
        }
    }

    pub fn get_asset(&self, network: &str, asset_id: &str) -> Result<Option<AssetRow>, String> {
        let conn = self.connection()?;
        conn.query_row(
            "SELECT network, asset_id, ticker, name, precision, is_policy_asset,
                    created_at, updated_at
             FROM assets WHERE network = ?1 AND asset_id = ?2",
            params![network, asset_id.to_ascii_lowercase()],
            asset_from_row,
        )
        .optional()
        .map_err(|e| format!("Read asset: {e}"))
    }

    fn get_offer(&self, id: u64) -> Result<Option<OfferRow>, String> {
        let conn = self.connection()?;
        conn.query_row(
            &format!("{} WHERE o.id = ?1", OFFER_SELECT),
            [to_i64(id)?],
            offer_from_row,
        )
        .optional()
        .map_err(|e| format!("Read offer: {e}"))
    }

    fn get_demo_offer(&self, id: u64) -> Result<Option<DemoOfferRow>, String> {
        let conn = self.connection()?;
        conn.query_row(
            &format!("{DEMO_OFFER_SELECT} WHERE id = ?1"),
            [to_i64(id)?],
            demo_offer_from_row,
        )
        .optional()
        .map_err(|e| format!("Read demo offer: {e}"))
    }

    pub fn create_atomic_swap(&self, input: &AtomicSwapCreate) -> Result<AtomicSwapRow, String> {
        validate_atomic_state(&input.network, "open", &input.state)?;
        let state_json = serde_json::to_string(&input.state)
            .map_err(|e| format!("Serialize atomic swap: {e}"))?;
        let conn = self.connection()?;
        let now = to_i64(now_secs())?;
        conn.execute(
            "INSERT INTO atomic_swaps (network,status,state_json,created_at,updated_at)
             VALUES (?1,'open',?2,?3,?3)",
            params![input.network, state_json, now],
        )
        .map_err(|e| format!("Create atomic swap: {e}"))?;
        let id = u64::try_from(conn.last_insert_rowid())
            .map_err(|e| format!("Invalid atomic swap id: {e}"))?;
        self.get_atomic_swap(id)?
            .ok_or_else(|| "Created atomic swap could not be read back".to_string())
    }

    pub fn list_atomic_swaps(
        &self,
        network: &str,
        include_all: bool,
    ) -> Result<Vec<AtomicSwapRow>, String> {
        validate_network(network)?;
        let conn = self.connection()?;
        let sql = if include_all {
            format!("{ATOMIC_SWAP_SELECT} WHERE network=?1 ORDER BY created_at DESC,id DESC")
        } else {
            format!("{ATOMIC_SWAP_SELECT} WHERE network=?1 AND status IN ('open','reserved','maker_funded','taker_funded','maker_claimed') ORDER BY created_at DESC,id DESC")
        };
        let mut stmt = conn
            .prepare(&sql)
            .map_err(|e| format!("Prepare atomic swaps: {e}"))?;
        let rows = stmt
            .query_map([network], atomic_swap_from_row)
            .map_err(|e| format!("Query atomic swaps: {e}"))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Read atomic swap: {e}"))
    }

    pub fn get_atomic_swap(&self, id: u64) -> Result<Option<AtomicSwapRow>, String> {
        let conn = self.connection()?;
        conn.query_row(
            &format!("{ATOMIC_SWAP_SELECT} WHERE id=?1"),
            [to_i64(id)?],
            atomic_swap_from_row,
        )
        .optional()
        .map_err(|e| format!("Read atomic swap: {e}"))
    }

    pub fn transition_atomic_swap(
        &self,
        id: u64,
        transition: &AtomicSwapTransition,
    ) -> Result<AtomicSwapRow, String> {
        let current = self
            .get_atomic_swap(id)?
            .ok_or_else(|| format!("Unknown atomic swap: {id}"))?;
        validate_transition(&current.status, &transition.status)?;
        validate_atomic_state(&current.network, &transition.status, &transition.state)?;
        preserve_immutable_state(&current.state, &transition.state)?;
        let state_json = serde_json::to_string(&transition.state)
            .map_err(|e| format!("Serialize atomic swap: {e}"))?;
        let conn = self.connection()?;
        let changed = conn.execute(
            "UPDATE atomic_swaps SET status=?1,state_json=?2,updated_at=?3 WHERE id=?4 AND status=?5",
            params![transition.status, state_json, to_i64(now_secs())?, to_i64(id)?, current.status],
        ).map_err(|e| format!("Transition atomic swap: {e}"))?;
        if changed != 1 {
            return Err("Atomic swap changed concurrently; refresh and retry".to_string());
        }
        self.get_atomic_swap(id)?
            .ok_or_else(|| format!("Updated atomic swap {id} disappeared"))
    }
}

const OFFER_SELECT: &str = "SELECT o.id, o.network, o.status, o.proposal_json,
            o.offered_asset_id, o.offered_amount_sats,
            offered.ticker, offered.name, offered.precision,
            o.wanted_asset_id, o.wanted_amount_sats,
            wanted.ticker, wanted.name, wanted.precision,
            o.note, o.created_at, o.updated_at
     FROM offers o
     JOIN assets offered
       ON offered.network = o.network AND offered.asset_id = o.offered_asset_id
     JOIN assets wanted
       ON wanted.network = o.network AND wanted.asset_id = o.wanted_asset_id";

const DEMO_OFFER_SELECT: &str = "SELECT id, network, status, settlement,
        offered_chain, offered_asset_id, offered_ticker, offered_name,
        offered_precision, offered_amount_sats,
        wanted_chain, wanted_asset_id, wanted_ticker, wanted_name,
        wanted_precision, wanted_amount_sats, note, created_at, updated_at
    FROM demo_offers";

const ATOMIC_SWAP_SELECT: &str =
    "SELECT id,network,status,state_json,created_at,updated_at FROM atomic_swaps";

fn schema_v1_backup_path(path: &Path) -> PathBuf {
    let name = path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("orderbook.sqlite3");
    path.with_file_name(format!("{name}.schema-v1.bak"))
}

fn schema_backup_path(path: &Path, version: u32) -> PathBuf {
    let name = path
        .file_name()
        .and_then(|v| v.to_str())
        .unwrap_or("orderbook.sqlite3");
    path.with_file_name(format!("{name}.schema-v{version}.bak"))
}

fn ensure_asset_placeholder(
    tx: &rusqlite::Transaction<'_>,
    network: &str,
    asset_id: &str,
) -> Result<(), String> {
    let prefix: String = asset_id
        .chars()
        .take(8)
        .collect::<String>()
        .to_ascii_uppercase();
    let now = now_secs();
    tx.execute(
        "INSERT OR IGNORE INTO assets
            (network, asset_id, ticker, name, precision, is_policy_asset, created_at, updated_at)
         VALUES (?1, ?2, ?3, 'Unregistered asset', 8, 0, ?4, ?4)",
        params![network, asset_id.to_ascii_lowercase(), prefix, to_i64(now)?],
    )
    .map_err(|e| format!("Create asset placeholder: {e}"))?;
    Ok(())
}

fn asset_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<AssetRow> {
    Ok(AssetRow {
        network: row.get(0)?,
        asset_id: row.get(1)?,
        ticker: row.get(2)?,
        name: row.get(3)?,
        precision: row.get(4)?,
        is_policy_asset: row.get(5)?,
        created_at: row_u64(row, 6)?,
        updated_at: row_u64(row, 7)?,
    })
}

fn offer_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<OfferRow> {
    Ok(OfferRow {
        id: row_u64(row, 0)?,
        network: row.get(1)?,
        status: row.get(2)?,
        proposal_json: row.get(3)?,
        offered_asset_id: row.get(4)?,
        offered_amount_sats: row_u64(row, 5)?,
        offered_ticker: row.get(6)?,
        offered_name: row.get(7)?,
        offered_precision: row.get(8)?,
        wanted_asset_id: row.get(9)?,
        wanted_amount_sats: row_u64(row, 10)?,
        wanted_ticker: row.get(11)?,
        wanted_name: row.get(12)?,
        wanted_precision: row.get(13)?,
        note: row.get(14)?,
        created_at: row_u64(row, 15)?,
        updated_at: row_u64(row, 16)?,
    })
}

fn demo_offer_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<DemoOfferRow> {
    Ok(DemoOfferRow {
        id: row_u64(row, 0)?,
        network: row.get(1)?,
        status: row.get(2)?,
        settlement: row.get(3)?,
        offered_chain: row.get(4)?,
        offered_asset_id: row.get(5)?,
        offered_ticker: row.get(6)?,
        offered_name: row.get(7)?,
        offered_precision: row.get(8)?,
        offered_amount_sats: row_u64(row, 9)?,
        wanted_chain: row.get(10)?,
        wanted_asset_id: row.get(11)?,
        wanted_ticker: row.get(12)?,
        wanted_name: row.get(13)?,
        wanted_precision: row.get(14)?,
        wanted_amount_sats: row_u64(row, 15)?,
        note: row.get(16)?,
        created_at: row_u64(row, 17)?,
        updated_at: row_u64(row, 18)?,
    })
}

fn atomic_swap_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<AtomicSwapRow> {
    let raw: String = row.get(3)?;
    let state = serde_json::from_str(&raw).map_err(|error| {
        rusqlite::Error::FromSqlConversionFailure(3, Type::Text, Box::new(error))
    })?;
    Ok(AtomicSwapRow {
        id: row_u64(row, 0)?,
        network: row.get(1)?,
        status: row.get(2)?,
        state,
        created_at: row_u64(row, 4)?,
        updated_at: row_u64(row, 5)?,
    })
}

pub fn validate_network(network: &str) -> Result<(), String> {
    match network {
        TESTNET | REGTEST => Ok(()),
        _ => Err(format!(
            "Unknown network {network:?}; expected {TESTNET} or {REGTEST}"
        )),
    }
}

fn validate_asset(input: &AssetInput) -> Result<(), String> {
    validate_network(&input.network)?;
    validate_asset_id(&input.asset_id)?;
    let ticker = input.ticker.trim();
    if ticker.is_empty() || ticker.chars().count() > 16 {
        return Err("Ticker must contain 1 to 16 characters".to_string());
    }
    let name = input.name.trim();
    if name.is_empty() || name.chars().count() > 80 {
        return Err("Asset name must contain 1 to 80 characters".to_string());
    }
    if input.precision > 8 {
        return Err("Asset precision must be between 0 and 8".to_string());
    }
    Ok(())
}

fn validate_asset_id(asset_id: &str) -> Result<(), String> {
    if asset_id.len() != 64 || !asset_id.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err("Asset id must be exactly 64 hexadecimal characters".to_string());
    }
    Ok(())
}

fn validate_status(status: &str) -> Result<(), String> {
    match status {
        "open" | "paused" | "filled" | "cancelled" => Ok(()),
        _ => Err("Status must be open, paused, filled, or cancelled".to_string()),
    }
}

fn validate_demo_offer(offer: &NewDemoOffer) -> Result<(), String> {
    validate_network(&offer.network)?;
    if offer.network != TESTNET {
        return Err("Bitcoin cross-chain demos currently require Liquid testnet".to_string());
    }
    let chains = (&offer.offered_chain[..], &offer.wanted_chain[..]);
    if !matches!(chains, ("bitcoin", "liquid") | ("liquid", "bitcoin")) {
        return Err("A cross-chain demo must exchange Bitcoin and Liquid".to_string());
    }
    for (ticker, name, precision, amount) in [
        (
            &offer.offered_ticker,
            &offer.offered_name,
            offer.offered_precision,
            offer.offered_amount_sats,
        ),
        (
            &offer.wanted_ticker,
            &offer.wanted_name,
            offer.wanted_precision,
            offer.wanted_amount_sats,
        ),
    ] {
        if ticker.trim().is_empty() || ticker.chars().count() > 16 {
            return Err("Demo ticker must contain 1 to 16 characters".to_string());
        }
        if name.trim().is_empty() || name.chars().count() > 80 {
            return Err("Demo asset name must contain 1 to 80 characters".to_string());
        }
        if precision > 8 || amount == 0 {
            return Err("Demo amounts must be positive with precision 0 to 8".to_string());
        }
    }
    Ok(())
}

fn validate_atomic_state(
    network: &str,
    status: &str,
    state: &AtomicSwapState,
) -> Result<(), String> {
    if network != TESTNET {
        return Err("Atomic swaps v1 support Bitcoin testnet + Liquid testnet only".to_string());
    }
    if !matches!(
        (state.offered_chain.as_str(), state.wanted_chain.as_str()),
        ("bitcoin", "liquid") | ("liquid", "bitcoin")
    ) {
        return Err("Atomic swap must exchange Bitcoin and Liquid".to_string());
    }
    if state.offered_amount_sats < 1_000 || state.wanted_amount_sats < 1_000 {
        return Err("Atomic swap amounts must be at least 1,000 base units".to_string());
    }
    if state.payment_hash.len() != 64 || !state.payment_hash.bytes().all(|b| b.is_ascii_hexdigit())
    {
        return Err("Payment hash must be 32-byte hex".to_string());
    }
    for key in [
        &state.maker_refund_pubkey,
        state.taker_claim_pubkey.as_deref().unwrap_or(""),
    ] {
        if !key.is_empty() && (key.len() != 66 || !key.bytes().all(|b| b.is_ascii_hexdigit())) {
            return Err("Swap pubkeys must be compressed 33-byte hex".to_string());
        }
    }
    if matches!(status, "open" | "reserved") && state.maker_timeout <= now_secs() {
        return Err("Maker timeout must be in the future".to_string());
    }
    if status != "open" && state.taker_claim_pubkey.is_none() {
        return Err("Reserved swap is missing the taker pubkey".to_string());
    }
    if matches!(
        status,
        "maker_funded" | "taker_funded" | "maker_claimed" | "completed"
    ) && (state.maker_funding_txid.is_none() || state.maker_contract_address.is_none())
    {
        return Err("Maker funding proof is required for this state".to_string());
    }
    if matches!(status, "taker_funded" | "maker_claimed" | "completed")
        && (state.taker_funding_txid.is_none() || state.taker_contract_address.is_none())
    {
        return Err("Taker funding proof is required for this state".to_string());
    }
    if matches!(status, "maker_claimed" | "completed") && state.preimage_hex.is_none() {
        return Err("Claimed swap must publish the preimage".to_string());
    }
    if let Some(preimage) = &state.preimage_hex {
        let raw = decode_hex(preimage)?;
        if raw.len() != 32 || templar_core::payment_hash_hex(&raw) != state.payment_hash {
            return Err("Preimage does not match the payment hash".to_string());
        }
    }
    Ok(())
}

fn decode_hex(value: &str) -> Result<Vec<u8>, String> {
    if value.len() % 2 != 0 || !value.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err("Expected hexadecimal bytes".to_string());
    }
    value
        .as_bytes()
        .chunks_exact(2)
        .map(|pair| {
            let text = std::str::from_utf8(pair).map_err(|e| e.to_string())?;
            u8::from_str_radix(text, 16).map_err(|e| e.to_string())
        })
        .collect()
}

fn validate_transition(from: &str, to: &str) -> Result<(), String> {
    let allowed = matches!(
        (from, to),
        ("open", "reserved")
            | ("open", "cancelled")
            | ("reserved", "maker_funded")
            | ("reserved", "cancelled")
            | ("maker_funded", "taker_funded")
            | ("maker_funded", "maker_refunded")
            | ("taker_funded", "maker_claimed")
            | ("taker_funded", "maker_refunded")
            | ("taker_funded", "taker_refunded")
            | ("maker_claimed", "completed")
            | ("maker_claimed", "taker_refunded")
            | (_, "failed")
    );
    allowed
        .then_some(())
        .ok_or_else(|| format!("Invalid atomic-swap transition {from} -> {to}"))
}

fn preserve_immutable_state(old: &AtomicSwapState, new: &AtomicSwapState) -> Result<(), String> {
    let immutable = old.offered_chain == new.offered_chain
        && old.offered_asset_id == new.offered_asset_id
        && old.offered_amount_sats == new.offered_amount_sats
        && old.wanted_chain == new.wanted_chain
        && old.wanted_asset_id == new.wanted_asset_id
        && old.wanted_amount_sats == new.wanted_amount_sats
        && old.payment_hash == new.payment_hash
        && old.maker_refund_pubkey == new.maker_refund_pubkey
        && old.maker_timeout == new.maker_timeout;
    immutable
        .then_some(())
        .ok_or_else(|| "Atomic swap terms are immutable after publication".to_string())
}

fn to_i64(value: u64) -> Result<i64, String> {
    i64::try_from(value).map_err(|_| format!("Value {value} is too large for SQLite"))
}

fn row_u64(row: &rusqlite::Row<'_>, index: usize) -> rusqlite::Result<u64> {
    let value: i64 = row.get(index)?;
    u64::try_from(value).map_err(|error| {
        rusqlite::Error::FromSqlConversionFailure(index, Type::Integer, Box::new(error))
    })
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
    use tempfile::TempDir;

    fn database() -> (TempDir, Database) {
        let dir = tempfile::tempdir().unwrap();
        let db = Database::open(dir.path().join("book.sqlite3")).unwrap();
        (dir, db)
    }

    fn asset(network: &str, id: char, ticker: &str) -> AssetInput {
        AssetInput {
            network: network.to_string(),
            asset_id: id.to_string().repeat(64),
            ticker: ticker.to_string(),
            name: format!("{ticker} test token"),
            precision: 2,
            is_policy_asset: false,
        }
    }

    #[test]
    fn migrations_enable_wal_and_seed_both_lbtc_assets() {
        let (_dir, db) = database();
        let conn = db.connection().unwrap();
        let mode: String = conn
            .pragma_query_value(None, "journal_mode", |row| row.get(0))
            .unwrap();
        assert_eq!(mode.to_ascii_lowercase(), "wal");
        let version: i64 = conn
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .unwrap();
        assert_eq!(version, 3);
        for network in [TESTNET, REGTEST] {
            let assets = db.list_assets(network).unwrap();
            let lbtc = assets.iter().find(|a| a.is_policy_asset).unwrap();
            assert_eq!(lbtc.ticker, "LBTC");
            assert_eq!(lbtc.precision, 8);
        }
    }

    #[test]
    fn schema_one_migrates_without_losing_existing_assets() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("book.sqlite3");
        let db = Database::open(path.clone()).unwrap();
        let legacy = asset(TESTNET, 'd', "OLD");
        db.upsert_asset(&legacy).unwrap();
        let conn = db.connection().unwrap();
        conn.execute_batch("DROP TABLE demo_offers; PRAGMA user_version = 1;")
            .unwrap();
        drop(conn);
        drop(db);

        let migrated = Database::open(path.clone()).unwrap();
        assert!(migrated
            .get_asset(TESTNET, &legacy.asset_id)
            .unwrap()
            .is_some());
        assert!(schema_v1_backup_path(&path).exists());
        let version: i64 = migrated
            .connection()
            .unwrap()
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .unwrap();
        assert_eq!(version, 3);
    }

    #[test]
    fn changing_regtest_policy_retires_the_previous_policy_row() {
        let (_dir, mut db) = database();
        let old = db.regtest_policy_asset.clone();
        db.regtest_policy_asset = "aa".repeat(32);
        db.seed_policy_assets().unwrap();

        let assets = db.list_assets(REGTEST).unwrap();
        let policies: Vec<_> = assets
            .iter()
            .filter(|asset| asset.is_policy_asset)
            .collect();
        assert_eq!(policies.len(), 1);
        assert_eq!(policies[0].asset_id, "aa".repeat(32));
        assert!(assets
            .iter()
            .any(|asset| asset.asset_id == old && !asset.is_policy_asset));
    }

    #[test]
    fn assets_are_isolated_by_network_and_editable() {
        let (_dir, db) = database();
        db.upsert_asset(&asset(TESTNET, 'a', "USDt")).unwrap();
        db.upsert_asset(&asset(REGTEST, 'b', "LOCAL")).unwrap();
        assert!(db
            .list_assets(TESTNET)
            .unwrap()
            .iter()
            .any(|a| a.ticker == "USDT"));
        assert!(!db
            .list_assets(TESTNET)
            .unwrap()
            .iter()
            .any(|a| a.ticker == "LOCAL"));
    }

    #[test]
    fn offer_lifecycle_is_transactional_and_keeps_referenced_assets() {
        let (_dir, db) = database();
        let offered = asset(TESTNET, 'a', "AAA");
        let wanted = asset(TESTNET, 'b', "BBB");
        db.upsert_asset(&offered).unwrap();
        db.upsert_asset(&wanted).unwrap();
        let row = db
            .create_offer(&NewOffer {
                network: TESTNET.to_string(),
                proposal_json: "signed proposal".to_string(),
                offered_asset_id: offered.asset_id.clone(),
                offered_amount_sats: 125,
                wanted_asset_id: wanted.asset_id.clone(),
                wanted_amount_sats: 250,
                note: "maker A".to_string(),
            })
            .unwrap();
        assert_eq!(db.list_offers(TESTNET, false).unwrap().len(), 1);
        let paused = db
            .update_offer(
                row.id,
                &OfferUpdate {
                    status: "paused".to_string(),
                    note: "testing".to_string(),
                },
            )
            .unwrap();
        assert_eq!(paused.status, "paused");
        assert!(db.list_offers(TESTNET, false).unwrap().is_empty());
        assert!(db.delete_asset(TESTNET, &offered.asset_id).is_err());
        db.delete_offer(row.id).unwrap();
        db.delete_asset(TESTNET, &offered.asset_id).unwrap();
    }

    #[test]
    fn cross_chain_demo_lifecycle_is_testnet_only() {
        let (_dir, db) = database();
        let token = asset(TESTNET, 'a', "USDT");
        db.upsert_asset(&token).unwrap();
        let quote = NewDemoOffer {
            network: TESTNET.to_string(),
            offered_chain: "bitcoin".to_string(),
            offered_asset_id: "btc-testnet".to_string(),
            offered_ticker: "BTC".to_string(),
            offered_name: "Bitcoin".to_string(),
            offered_precision: 8,
            offered_amount_sats: 100_000,
            wanted_chain: "liquid".to_string(),
            wanted_asset_id: token.asset_id,
            wanted_ticker: token.ticker,
            wanted_name: token.name,
            wanted_precision: token.precision,
            wanted_amount_sats: 2_500,
            note: "BTC for token".to_string(),
        };
        let row = db.create_demo_offer(&quote).unwrap();
        assert_eq!(row.settlement, "htlc-demo");
        assert_eq!(db.list_demo_offers(TESTNET, false).unwrap().len(), 1);
        db.update_demo_offer(
            row.id,
            &OfferUpdate {
                status: "paused".to_string(),
                note: "hold".to_string(),
            },
        )
        .unwrap();
        assert!(db.list_demo_offers(TESTNET, false).unwrap().is_empty());
        db.delete_demo_offer(row.id).unwrap();

        let mut regtest = quote;
        regtest.network = REGTEST.to_string();
        assert!(db.create_demo_offer(&regtest).is_err());
    }

    #[test]
    fn atomic_swap_state_machine_is_compare_and_set_and_terms_are_immutable() {
        let (_dir, db) = database();
        let preimage = [9u8; 32];
        let state = AtomicSwapState {
            offered_chain: "bitcoin".into(),
            offered_asset_id: "btc-testnet".into(),
            offered_ticker: "BTC".into(),
            offered_name: "Bitcoin Testnet".into(),
            offered_precision: 8,
            offered_amount_sats: 100_000,
            wanted_chain: "liquid".into(),
            wanted_asset_id: TESTNET_POLICY_ASSET.into(),
            wanted_ticker: "LBTC".into(),
            wanted_name: "Liquid Bitcoin".into(),
            wanted_precision: 8,
            wanted_amount_sats: 90_000,
            payment_hash: templar_core::payment_hash_hex(&preimage),
            maker_refund_pubkey: format!("02{}", "11".repeat(32)),
            taker_claim_pubkey: None,
            maker_timeout: now_secs() + 172_800,
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
            note: "real test".into(),
        };
        let row = db
            .create_atomic_swap(&AtomicSwapCreate {
                network: TESTNET.into(),
                state,
            })
            .unwrap();
        assert_eq!(row.status, "open");
        let mut reserved = row.state.clone();
        reserved.taker_claim_pubkey = Some(format!("03{}", "22".repeat(32)));
        reserved.taker_timeout = Some(now_secs() + 86_400);
        let reserved_row = db
            .transition_atomic_swap(
                row.id,
                &AtomicSwapTransition {
                    status: "reserved".into(),
                    state: reserved.clone(),
                },
            )
            .unwrap();
        assert_eq!(reserved_row.status, "reserved");
        let mut tampered = reserved;
        tampered.offered_amount_sats += 1;
        assert!(db
            .transition_atomic_swap(
                row.id,
                &AtomicSwapTransition {
                    status: "maker_funded".into(),
                    state: tampered,
                }
            )
            .is_err());
        assert!(db
            .transition_atomic_swap(
                row.id,
                &AtomicSwapTransition {
                    status: "completed".into(),
                    state: reserved_row.state,
                }
            )
            .is_err());
    }
}
