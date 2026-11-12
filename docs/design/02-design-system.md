# Design System

This document extracts the shared visual language needed to rebuild the UI cleanly in Flutter.

## Design intent

The interface should feel:

- Technical but friendly
- Sparse but not empty
- Data-dense but readable
- Calm and trustworthy
- More like a serious finance tool than a marketing website

## Color roles

Primary accent:

- Purple for active nav items, primary buttons, selected states, and key CTAs

Positive / success:

- Green for synced, confirmed, safe, completed, or healthy states

Warning / policy / notable status:

- Yellow / orange for warnings, policy hints, irreversible reminders, and asset-specific alerts

Danger:

- Red / pink for delete, wipe, burn, and irreversible destructive actions

Neutrals:

- Very light background surfaces
- Soft card borders
- Light lavender-tinted table headers and code / descriptor boxes where shown

## Common UI primitives

Build reusable components for:

- Primary button
- Secondary button
- Danger button
- Ghost / text button
- Status badge
- Asset badge
- Info banner
- Warning banner
- Danger banner
- Form card
- Summary card
- Data table
- Section card
- Step indicator header
- Asset chip
- Code / descriptor box
- Copy row / copyable field

## Typography behavior

Typography should be clean and highly legible.

Visual hierarchy should include:

- Large dashboard balance / numeric display
- Strong page titles
- Muted subtitles / helper text
- Table labels and captions
- Monospaced or code-like text styling for descriptors, fingerprints, tx-related raw data, and technical values where appropriate

## Spacing behavior

- Consistent spacing scale across cards, forms, tables, and banners
- Comfortable whitespace around page titles and main sections
- Dense but clear tabular layouts
- Avoid over-compressed finance UI; leave room for technical information to breathe

## Interaction patterns

- Primary call to action usually sits at the lower-right of the main form flow or in the top-right header area
- Secondary actions are often inline and low emphasis
- Copy buttons should give immediate success feedback
- Destructive actions must be visually isolated and protected by confirmation UX
- Step-based wizards should use a persistent progress header

## Special visual motifs

- UTXO cards use a “banknote” metaphor and should preserve that identity
- Descriptor and policy areas use tinted boxes and code-like formatting
- Asset cards use small status tags like “your asset”, “third-party”, “synced”, or “reissuance token held”

## Exclusions / cleanup

- Remove the “track another asset” action from the home dashboard
- Do not recreate visual noise or web-specific hacks
- Keep the design system centralized rather than styling screen-by-screen
