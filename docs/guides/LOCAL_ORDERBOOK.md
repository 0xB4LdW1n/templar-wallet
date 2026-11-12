# Local LiquiDEX order book

Templar includes a localhost-only market service for controlled test offers.
It supports real **LiquiDEX v0** swaps on Liquid testnet and regtest, plus real
**HTLC v1** atomic swaps between Bitcoin testnet and LBTC or any registered
Liquid testnet asset. Each Liquid network has a separate book.

The service never receives or stores seeds, descriptors, private keys, or
wallet passwords. It stores signed public LiquiDEX proposals, public asset
metadata and the public HTLC state machine. Swap keys and the maker preimage
before claim remain in the wallet.

## What the order book does

The order book is a **coordinator, not an exchange wallet**. A maker creates a
signed proposal that says “I give this exact Liquid coin and want this amount
of that Liquid asset”. The local service publishes that public proposal so a
taker can discover it. It never controls either wallet and cannot sign or move
funds.

In the wallet, every row is written from the taker's point of view:

- **Receive** is the asset and amount committed by the maker.
- **Pay** is the asset and amount the maker asks from the taker.

The taker independently verifies the proposal, adds their inputs and outputs,
signs, and broadcasts one Liquid transaction. Both asset legs settle together
or the transaction is invalid; there is no intermediate state in which the
service holds one side. Confidential Transactions keep on-chain values and
asset types blinded to outside observers, while each participating wallet can
verify its own amounts.

## Start it

From the repository root:

```bash
./scripts/run_local_orderbook.sh
```

Then open <http://127.0.0.1:3210>. The server binds only to `127.0.0.1`; it is
not reachable from another computer on the network.

For a release binary:

```bash
cargo build --locked --release -p templar-orderbook
./target/release/templar-orderbook --help
./target/release/templar-orderbook
```

The default database is `~/.templar-orderbook/orderbook.sqlite3`. Use another
path or port when needed:

```bash
./target/release/templar-orderbook --db /absolute/path/book.sqlite3 --port 3211
```

`TEMPLAR_ORDERBOOK_DB` also overrides the database path. If the wallet and
server do not use port 3210, set both wallet URLs:

```bash
export TEMPLAR_SWAP_BOOK_URL=http://127.0.0.1:3211/api/book
export TEMPLAR_SWAP_MARKETS_URL=http://127.0.0.1:3211/api/markets
export TEMPLAR_SWAP_ADMIN_URL=http://127.0.0.1:3211/api/admin/offers
```

## Use it with Templar Wallet

1. Start the order-book service before opening LiquiDEX in the wallet.
2. In **Settings → Network & Sync**, select the same Liquid network used by the
   dashboard: testnet or regtest.
3. In **Settings → Advanced**, enable **LiquiDEX**. It is hidden by default.
4. Open **LiquiDEX**. The unified market reads the selected local book.
5. Choose **Create Liquid offer**, select the coin to offer and the
   asset/amount wanted,
   then confirm. The wallet signs locally.
6. Select **Publish locally**. Only the signed proposal and optional public note
   are posted to the service.
7. A taker opens the order, reviews the independently verified amounts and fee,
   then signs and broadcasts from their own wallet.

Use the **Admin** button in LiquiDEX to open the dashboard. An offer can be
paused, reopened, marked filled/cancelled, copied, or deleted. Pausing removes
it from the default wallet market without deleting it from the DB.

## Test between two wallets

This flow works with two wallets on the same Templar installation: create and
publish with Wallet A, return to the wallet picker, then open Wallet B and take
the offer. Two separate app instances also work when they use separate wallet
data directories and the same localhost service.

Before starting:

- Both wallets must use the **same Liquid network** and policy asset.
- Wallet A needs the exact Liquid coin it will offer.
- Wallet B needs the asset the maker wants.
- Each signing wallet needs enough LBTC for its transaction fees.
- Use small testnet/regtest amounts; mainnet settlement is disabled.

End-to-end checklist:

1. Open Wallet A, sync it, create the Liquid offer, and choose **Publish**.
2. Open Wallet B, sync it, open LiquiDEX, and refresh the local market.
3. Open the row. Check **Receive** (maker gives), **Pay** (maker wants), the
   network, asset IDs, amounts, and fee before continuing.
4. Choose **Review and take**. Templar deep-verifies the offered coin against
   the active network before Wallet B signs and broadcasts.
5. Copy the resulting transaction ID. Sync Wallet B, then Wallet A. The maker's
   offered coin is spent and both wallets show their received asset after the
   network confirms the transaction.
6. If Wallet A cancels first, it self-spends the offered coin. Any copied or
   published proposal then fails verification and cannot be taken.

If an offer is missing, first verify that the server is running, both wallets
use the same network, the offer is `open`, and the wallet's **Closed** filter is
off. The admin dashboard and `GET /api/health` expose the service state without
requiring wallet secrets.

## Test a real BTC ↔ Liquid swap

Both wallet profiles must be software wallets with Bitcoin and Liquid enabled.
Use two wallets, sync both, and keep the local order book running.

1. In Wallet A choose **New offer → BTC ↔ Liquid**.
2. Choose whether A offers BTC or a Liquid asset. Select LBTC or any token held
   by the wallet and enter both exact amounts.
3. Publish. Wallet A creates the payment secret locally; only its SHA256 hash
   and public refund key enter SQLite.
4. Open Wallet B, refresh, open the **HTLC v1** row, and choose **Reserve offer**.
   This adds B's public claim/refund key and fixes both contracts.
5. Return to Wallet A and press **Fund HTLC**. A broadcasts the maker leg with
   a 48-hour refund timeout.
6. Wallet B refreshes and presses **Fund HTLC**. Before doing so it fetches A's
   transaction from the relevant chain and verifies the script, asset and exact
   amount. B's leg uses a 24-hour timeout.
7. Wallet A presses **Claim**. Its transaction reveals the preimage.
8. Wallet B refreshes and presses **Claim** to redeem A's leg with that same
   preimage. The swap is then `completed`.

If a claim does not happen, the wallet exposes **Refund** only after that
side's absolute timeout. The maker timeout is deliberately longer, so the
taker has time to use the revealed preimage. Liquid tokens require a separate
LBTC input for the claim/refund network fee.

HTLC v1 is hard-locked to Bitcoin testnet + Liquid testnet. Its Liquid contract
output is unconfidential: the asset and exact amount are public so the other
wallet can verify the contract without receiving a blinding secret. Normal
wallet change and claim outputs remain confidential. The legacy dashboard
**Test quote** button still creates non-settling UI rows labelled `HTLC demo`;
real offers must originate in a wallet because the admin server holds no keys.

## Manage Liquid assets

Open **Assets** in the dashboard and add the 64-character asset ID, ticker,
name, and precision. Metadata controls presentation only; the proposal's asset
ID and signed transaction remain authoritative. `LBTC` is seeded as the policy
asset and protected from deletion.

Testnet and regtest rows are isolated. For a custom regtest genesis, start both
the wallet and service with the node's policy asset:

```bash
export TEMPLAR_LIQUID_NETWORK=regtest
export TEMPLAR_LIQUID_REGTEST_POLICY_ASSET=<64-hex-policy-asset>
./scripts/run_local_orderbook.sh
```

## Inspect, edit, and back up the database

The dashboard exposes structured editing for assets, real offers, and demo
quotes and can export the selected network as JSON. The **Database** page
shows the exact SQLite path. The file is ordinary SQLite with foreign keys,
WAL journaling, `FULL` synchronous durability, and versioned schema
migrations.

Schema v3 adds `atomic_swaps` without changing existing `assets`, `offers`, or
`demo_offers`. Before migrating an existing schema-v2 database, the service
checkpoints WAL and creates `<database>.schema-v2.bak`.

Stop the service before making a file-level backup, then copy the database and
its `-wal`/`-shm` companions if present. Direct SQL edits are possible with any
SQLite browser, but the dashboard/API is preferred because it enforces status,
network, and reference constraints.

## Local API

| Route | Purpose |
|---|---|
| `GET /api/health` | Service and database health |
| `GET /api/book?network=liquid-testnet` | Wallet-compatible open book |
| `GET /api/markets?network=liquid-testnet` | Unified LiquiDEX + HTLC market feed |
| `GET /api/atomic-swaps/{id}` | Read one public HTLC state machine |
| `POST /api/atomic-swaps` | Publish testnet HTLC terms from a wallet |
| `PUT /api/atomic-swaps/{id}` | Validated, compare-and-set lifecycle transition |
| `GET /api/admin/state?network=liquid-regtest` | Assets, offers, HTLC state, and stats |
| `POST /api/admin/assets` | Add/update public token metadata |
| `POST /api/admin/offers` | Validate and store a signed proposal |
| `PUT /api/admin/offers/{id}` | Change status or note |
| `DELETE /api/admin/offers/{id}` | Delete an offer |
| `POST /api/admin/demo-offers` | Store a non-settling BTC/Liquid demo quote |
| `PUT /api/admin/demo-offers/{id}` | Change demo status or note |
| `DELETE /api/admin/demo-offers/{id}` | Delete a demo quote |

## Mainnet portability boundary

The schema and wallet DTOs carry explicit chain, network, asset ID, precision,
amount, contract, funding proof and settlement fields, so the design is not
coupled to LBTC. Mainnet spending remains disabled. Before production, HTLC v1
still requires an independent security audit, confirmation/reorg policy,
dynamic claim fees, encrypted crash-recovery hardening and privacy review. Do
not enable mainnet by changing a label or network string.

This is an administrator test tool, not an internet-facing exchange server.
It intentionally has no remote bind or account/authentication system.
