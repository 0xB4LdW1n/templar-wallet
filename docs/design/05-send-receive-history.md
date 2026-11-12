# Send, Receive, and History

This document defines the core transaction-facing screens.

## Send screen

Purpose:

- Build a transaction for BTC, L-BTC, or another Liquid asset.

Main UI elements:

- Asset selector tabs
- Recipient address input
- Scan / paste actions
- Amount input
- Unit selector
- Optional note field
- Advanced section
- Fee selection block
- Coin selection block
- Summary panel
- Main CTA: Review & sign

Advanced options:

- OP_RETURN message
- Manual UTXO selection, which opens the dedicated UTXO page

Behavior:

- Address validation depends on selected chain / asset
- Amount validation depends on selected asset precision and balance
- Summary updates live as user changes fields
- Review & sign builds PSBT/PSET preview via backend

## Receive screen

Purpose:

- Generate a fresh receive address and optional BIP21 / payment request metadata

Main UI elements:

- Asset selector tabs
- QR code
- Address display
- Copy address action
- Save QR action
- New address action
- Optional amount field
- Optional label field
- Advanced toggle / section
- Previous addresses table

Previous addresses table columns:

- Index
- Address
- Label
- Received
- Copy action

Behavior:

- Amount and label can affect generated QR / URI if supported
- Label is local-only and not written on-chain
- New address advances address derivation via backend

## Activity / history

Purpose:

- Unified cross-chain history view for Bitcoin and Liquid

Main UI elements:

- Chain filter
- Asset filter
- Time filter
- Search field
- Timeline / table toggle
- Grouped date sections
- History rows with view action

History row contents:

- Direction
- Amount
- Asset label
- Counterparty snippet or local note
- Confirmation state
- Fiat estimate if available
- Timestamp or relative time

Behavior:

- Filters should update results in-place
- Search should work across txid, address, note, or label where available
- View opens transaction detail / inspector page or detail drawer

## Shared components

Build reusable widgets for:

- Asset selector tab group
- Address input block
- Amount input panel
- Fee preset selector
- Summary table / summary panel
- History row
- History filter bar
- QR address card
- Previous address table

## Backend integration hints

Likely methods:

- Generate receive address
- Build payment request / QR payload
- List previous receive addresses
- Build send preview
- Estimate fee / quote fee presets
- Load activity list with filters
- Load tx detail for a selected activity item
