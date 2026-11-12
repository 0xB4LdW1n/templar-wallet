# PSBT Inspector and Co-signing

This document covers the multisig and PSBT/PSET review experience.

## Purpose

Provide a full transaction review and signing experience for multisig / co-sign flows.

## Main UI structure

- Transaction summary banner at the top
- Spending policy section
- Inputs table
- Outputs table
- Wallet impact section
- Raw PSBT section
- Bottom signing action bar

## Transaction summary banner

Display:

- Amount being sent
- Asset / chain
- Recipient summary
- Current wallet name
- Balance snapshot
- Input / output count
- Virtual size
- Inline validation / policy badges such as:
  - address parses
  - inputs are mine
  - change returns to wallet
  - fee within market range
  - recipient is brand new

## Spending policy section

Display:

- Threshold policy (for example 2 of 3)
- Signer list
- Signer state badges such as signed, awaiting you, not yet
- Fingerprints and signer labels where available

## Inputs and outputs

Inputs table columns:

- Outpoint
- Amount
- Owner / ownership state

Outputs table columns:

- Address
- Amount
- Flags such as external, mine, change
- Fee summary row

## Wallet impact section

Display:

- Balance before
- Balance after signing / broadcasting
- Net change
- Fee explanation

## Raw PSBT section

Provide:

- Optional raw PSBT visibility
- Toggle to show raw bytes or raw content later if supported

## Actions

Top or utility actions:

- Paste PSBT
- Load file
- Scan QR

Bottom actions:

- Decline
- Save unsigned
- Sign & export

Behavior:

- Signing availability depends on backend policy and signer role
- The page should be useful for both review and action
- Exported signed PSBT/PSET should be easy to pass to another cosigner or broadcaster

## Product question

Decide whether this page should:

- always appear in navigation, or
- only appear when multisig mode is enabled, or
- appear only when a pending PSBT exists

## Backend integration hints

Likely methods:

- Parse PSBT / PSET
- Inspect policy status
- Return signer states
- Sign as current wallet if allowed
- Export unsigned / signed form
- Decode wallet impact and tx summary
