# UTXOs and Wallet Info

This document covers manual coin control and wallet identity / descriptor information.

## UTXO screen

Purpose:

- Manual coin control and advanced output management

Main UI elements:

- Chain toggle: BTC / Liquid
- State filters
- Search field
- Summary counters
- Visual UTXO cards shown as banknotes
- Selection state
- Bottom action bar

Bottom action bar actions:

- Send selected
- Tag
- Freeze
- Consolidate
- Clear

Behavior:

- User can select multiple UTXOs
- Frozen / tagged / dust states should be visible
- Freeze / Unfreeze acts on the selection (Unfreeze when every selected coin
  is frozen) and on one coin from its details sheet; the engine never spends
  a frozen coin, and the send picker shows it locked
- UTXO selection should feed back into the send flow
- Manual mode from send should deep-link into this page

Important note:

- Preserve the visual “banknote” metaphor because it is part of the product identity

## Wallet info screen

Purpose:

- Show all technical wallet metadata needed for interoperability, export, and backup

Main UI sections:

- Identity
- Backup
- Bitcoin descriptors
- Liquid descriptors
- For other apps

Identity section contents:

- Wallet name
- Network
- Master fingerprint
- Derivation path
- Script type

Backup section contents:

- Seed status
- Last backup status
- BIP39 passphrase status
- Actions to reveal or configure where allowed

Descriptor sections:

- XPUB
- Receive descriptor
n- Change descriptor
- Multipath descriptor if applicable
- Confidential / Liquid descriptors
- Master blinding key

External interoperability actions:

- Copy descriptor bundle
- Export JSON
- Show QR / animated QR
- Copyable fields for Sparrow / Specter / Jade / SeedSigner / BlueWallet workflows

Behavior:

- Copy actions give immediate feedback
- Sensitive values should be clearly labeled
- Export actions should be driven by backend-generated payloads

## Shared components

Build reusable widgets for:

- Filter bar
- UTXO note / banknote card
- Bottom action bar
- Copyable field row
- Technical info card
- Export action row
- External app integration card
