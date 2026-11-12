# Home Dashboard and Wallet Picker

This document covers the wallet picker screen and the main wallet dashboard.

## Wallet picker

Purpose:

- Show all wallets stored locally and allow the user to open one.

Main UI elements:

- Search field
- Restore button
- New wallet button
- Grid of wallet cards
- “Add a new wallet” card

Wallet card contents:

- Wallet name
- Type / short tag
- Balance or watch-only state
- Last sync information
- Transaction count

Behavior:

- Click a wallet card to open it
- Search filters the card list
- Restore starts import / recovery flow
- New wallet starts the creation wizard

## Home dashboard

Purpose:

- Main overview for an opened wallet

Main UI elements:

- Large total portfolio balance
- Asset chips summarizing BTC and Liquid holdings
- Primary actions: Send and Receive
- Shortcut to activity / history
- Asset cards
- Recent activity list

Asset card contents:

- Asset name or ticker
- Balance
- Optional fiat estimate
- Status badge such as synced, third-party, your asset, or reissuance token held
- Quick context such as UTXO count or confirmation state

Behavior:

- Send opens send flow
- Receive opens receive flow
- See activity opens history page
- Clicking an asset can later open an asset-specific page

## Important cleanup

- Remove the “track another asset” button / card from this dashboard

## Shared components

Create reusable widgets for:

- Wallet card
- Asset summary chip
- Asset balance card
- Recent activity row
- Portfolio hero / balance panel

## Backend integration hints

Likely data required:

- Wallet summary
- Total portfolio balance
- Per-asset balances
- Asset metadata / labels
- Recent activity preview
- Sync state
