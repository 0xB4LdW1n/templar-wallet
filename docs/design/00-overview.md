# Templar Wallet UI Migration Overview

This document provides the high-level implementation context for rebuilding the Templar Wallet user interface in Flutter while keeping the Rust wallet core as the source of truth.

## Goal

Rebuild the current desktop wallet UI as a clean, reusable Flutter application connected to the existing Rust backend. The current screenshots define the visual direction and interaction model. The old UI implementation should be treated as reference material, not as code to port mechanically.

## Product direction

- Desktop-first wallet UI.
- Future-friendly architecture for macOS, Windows, Android, and iOS.
- No webview-based shell.
- No wallet-critical logic in Dart.
- Rust remains responsible for balances, descriptors, address generation, PSBT/PSET building, signing, sync, UTXO state, Liquid issuance flows, and secure storage.

## Implementation principles

- Build a reusable Flutter design system first.
- Recreate the UI from screenshots and behavior notes, not from HTML semantics.
- Split work by feature, not by raw screen order.
- Keep presentation, state management, and Rust bridge code separate.
- Prefer explicit DTOs and use-case driven API methods over generic JSON pipes.

## Global visual rules

- Minimal, calm, technical desktop UI.
- Purple is the primary accent for active navigation and main actions.
- Green indicates synced, safe, positive, or completed states.
- Yellow/orange indicates warnings, policy hints, or special asset states.
- Red/pink indicates danger or irreversible operations.
- Use soft cards, clear spacing, and dense but readable data layouts.
- Reuse badges, cards, tables, banners, section headers, and CTA patterns.

## App shell

The app uses a left navigation rail/sidebar visible on desktop. The shell should include:

- Templar Wallet brand area at the top.
- Current wallet selector when applicable.
- Grouped navigation sections.
- Sync status indicator in the lower area.
- Stable content area on the right.

## Recommended document reading order

1. `01-navigation-and-shell.md`
2. `02-design-system.md`
3. `03-wallet-creation-flow.md`
4. `04-home-and-wallet-picker.md`
5. `05-send-receive-history.md`
6. `06-utxos-and-wallet-info.md`
7. `07-psbt-cosign.md`
8. `08-liquid-and-asset-ops.md`
9. `09-settings.md`
10. `10-backend-integration-map.md`

## Important product notes

- Remove the “track another asset” button from the home dashboard.
- Keep the green sync indicator clickable.
- Decide later whether multisig / co-sign pages are always visible or conditionally enabled.
- Add a future “Re-register” action to asset detail pages after issuance when final Asset ID metadata can be published.
