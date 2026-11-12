# Wallet Creation Flow

This document defines the wallet creation wizard.

## Flow summary

The wallet creation flow is a step-based wizard.

Observed stages:

1. Wallet type selection / details setup
2. Seed length choice
3. Seed backup display
4. Seed confirmation
5. Success / completion

## Shared wizard rules

- Use a consistent step header across all creation screens.
- Show current step and total steps.
- Support Back, Cancel, and Next actions where appropriate.
- Each step should validate before allowing continuation.

## Step: choose seed length

Purpose:

- Let the user choose between 12-word and 24-word mnemonic.

UI requirements:

- Two selectable cards
- Clear explanation of entropy / trade-off
- Selected state clearly highlighted
- CTA label reflects selected choice

Behavior:

- Only one option can be selected.
- Selection is passed to backend wallet creation.

## Step: show generated seed

Purpose:

- Display the newly generated mnemonic for manual backup.

UI requirements:

- Numbered word grid
- Strong warning to write the words down on paper
- Explicit warning never to type or photograph the seed phrase
- Clear CTA to continue to verification

Behavior:

- Seed is shown only at the correct stage.
- Screen should visually communicate seriousness and irreversibility of loss.

## Step: confirm seed

Purpose:

- Verify the user backed up the seed correctly.

UI requirements:

- Ask for 3 random word positions
- Provide clear instruction
- Allow user to go back and review the seed again
- Confirm and finish CTA

Behavior:

- Backend provides requested word indexes
- User must enter correct answers to continue
- Validation errors should be explicit and calm

## Step: success

Purpose:

- Confirm that wallet creation is complete.

UI requirements:

- Success indicator
- Friendly success message using the wallet name
- Primary action: open wallet
- Secondary action: get receive address

Behavior:

- Open wallet goes to dashboard
- Get receive address opens the receive page immediately

## Implementation notes

Recommended reusable widgets:

- `WizardHeader`
- `WizardStepProgress`
- `SelectableOptionCard`
- `MnemonicWordGrid`
- `SeedVerificationForm`
- `SuccessStateCard`

## Backend integration hints

Likely backend needs:

- Create wallet draft
- Generate mnemonic
- Confirm mnemonic challenge
- Finalize wallet creation
- Open created wallet
- Generate first receive address
