# Backend Integration Map

This document is not a strict API definition. It is a planning map to help connect Flutter UI to the Rust wallet core cleanly.

## Principle

Flutter should request high-level wallet use cases. Rust should remain responsible for all blockchain-critical and wallet-critical operations.

## Flutter responsibilities

- Render UI
- Hold temporary form state
- Handle navigation
- Handle visual loading / success / error states
- Format and display backend data
- Trigger backend operations through explicit bridge methods

## Rust responsibilities

- Wallet creation and restoration
- Mnemonic generation / verification
- Address generation
- Balance loading
- Activity loading
- UTXO state / freeze / tag / consolidation logic
- Fee estimation logic or fee quote generation
- PSBT / PSET building
- Signing / co-signing
- Descriptor export
- Liquid issuance / reissuance / burn workflows
- Sync / resync actions
- Persistent storage and secure state

## Recommended bridge style

Prefer explicit methods such as:

- `listWallets`
- `openWallet`
- `createWallet`
- `generateMnemonic`
- `verifyMnemonicChallenge`
- `getWalletSummary`
- `getAssetBalances`
- `getRecentActivity`
- `buildSendPreview`
- `generateReceiveAddress`
- `listPreviousAddresses`
- `listActivity`
- `listUtxos`
- `updateUtxoTags`
- `setUtxosFrozen`
- `consolidateUtxos`
- `getWalletInfo`
- `exportDescriptors`
- `inspectPsbt`
- `signPsbt`
- `buildIssuancePreview`
- `buildReissuancePreview`
- `buildBurnPreview`
- `syncWallet`
- `getSettings`
- `updateSettings`

Avoid:

- Generic `execute(json)` style commands
- Business logic in Dart
- Direct UI dependence inside Rust core

## Data contract guidance

DTOs returned to Flutter should be:

- explicit
- typed
- feature-specific
- stable
- easy to serialize across FFI / bridge boundaries

## Suggested migration order

1. Shell + navigation
2. Wallet picker
3. Home dashboard
4. Wallet creation flow
5. Receive
6. Send
7. History
8. UTXOs
9. Wallet info
10. Settings
11. PSBT / cosign
12. Liquid dashboard
13. Issue / reissue / burn

## State handling guidance

For each screen define:

- initial state
- loading state
- success state
- empty state
- validation error state
- backend error state

This will reduce complexity during implementation and make Claude Code more reliable when generating code.
