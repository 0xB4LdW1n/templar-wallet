# Liquid and Asset Operations

This document covers Liquid asset management, issuance, reissuance, and burn flows.

## Liquid dashboard

Purpose:

- Central place to view held and issued Liquid assets and launch related actions

Main UI elements:

- Liquid balances / asset cards
- Register asset action / card
- Asset operations panel
- Recent Liquid activity table

Behavior:

- Show both held assets and issued assets
- Support future dedicated asset detail pages
- Provide clear entry points to issue, reissue, burn, and registry-related actions

## Asset operations menu

Purpose:

- Let user choose between issue, reissue, and burn

Options:

- Issue
- Reissue
- Burn

Behavior:

- Each option opens its own guided flow
- Explanations must clearly describe consequences

## Issue flow

### Step 1 — Define asset

Fields:

- Token name
- Ticker
- Precision
- Domain

Supporting UI:

- Contract preview
- Immutable warning
- Derived contract hash explanation

Behavior:

- Preview updates as user edits fields
- Validation applies to ticker, precision, and domain rules

### Step 2 — Initial supply

Fields:

- Initial supply amount
- Destination address for minted supply
- Fee rate
- Whether to create reissuance token
- Destination / storage location of reissuance token

Behavior:

- Explain that losing the reissuance token means no future reissuance
- Make consequences easy to understand

### Step 3 — Review & sign

Summary should show:

- Operation type
- Name and ticker
- Precision
- Domain
- Initial supply
- Reissuance token choice
- Contract hash
- Derived Asset ID
- Network fee

Behavior:

- Final review before building/signing issuance transaction
- After signing, issuance PSET exists and can be reviewed further in inspector flow if needed

## Reissue flow

Purpose:

- Mint more units of an existing asset

Main UI elements:

- Asset selector
- Current supply card
- User holdings card
- Reissuance token card
- Additional amount field
- Destination address field
- Side explanation panel
- Build PSET CTA

Behavior:

- Only reissuable assets should be selectable
- Clearly explain resulting total supply and output destination

## Burn flow

Purpose:

- Permanently destroy asset supply

Main UI elements:

- Strong irreversible warning
- Asset selector
- Amount to burn
- Quick burn-all helper
- Confirmation by typing ticker
- Build burn transaction CTA

Behavior:

- Final action enabled only after confirmation matches ticker
- New total supply should be previewed
- This is irreversible and must be visually explicit

## Future feature

After issuance, add a future `Re-register` action in the asset-specific section/page once final Asset ID metadata can be submitted to an external registry server.

## Shared components

Build reusable widgets for:

- Step header
- Asset operation card
- Contract preview box
- Supply summary card
- What happens / consequences side panel
- Irreversible warning banner
- Asset selector dropdown / tabs
