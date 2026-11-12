# Navigation and App Shell

This document defines the persistent application shell and the top-level navigation model.

## Purpose

The shell provides a consistent desktop structure across the entire wallet. It should not be rebuilt screen-by-screen. It is a shared layout system.

## Sidebar structure

The left sidebar is the primary navigation component.

Expected navigation groups:

- Home
- Send
- Receive
- History
- UTXOs
- Wallet info
- PSBT inspector / Co-sign
- Liquid
- Issue / Reissue / Burn
- Settings

There may also be grouped headings such as:

- Wallet
- Multisig
- Liquid
- System

## Sidebar behavior

- Active route is highlighted in purple.
- Icons remain visible even when the sidebar is compact.
- On desktop, the sidebar should normally remain visible.
- Collapsed or overlay behavior can be added later if needed.

## Brand area

The top of the sidebar shows:

- Templar Wallet brand/logo.
- Current wallet name and summary when relevant.
- Optional wallet selector / switcher.

## Sync status indicator

A green dot appears in the lower area of the UI.

Behavior requirements:

- It is clickable.
- It should trigger sync or resync behavior.
- It should support future sync states such as idle, syncing, success, warning, offline, and error.
- It should not be decorative only.

## Desktop shell layout

Use a two-region layout:

- Fixed-width left navigation rail/sidebar.
- Flexible main content panel.

Recommended behavior:

- Maintain route state while switching sections.
- Preserve scroll position where it makes sense.
- Support page-level headers in the content area.
- Keep primary actions near the top-right or near the main content focal point.

## Shared shell components

Create reusable shell widgets/components for:

- App sidebar
- Sidebar item
- Sidebar section label
- Sidebar footer status area
- Page header
- Inline top actions row
- Section title and subtitle block

## Notes for Flutter structure

Recommended conceptual split:

- `AppShell`
- `SidebarNavigation`
- `SidebarWalletSwitcher`
- `SyncStatusButton`
- `ContentScaffold`
- `PageHeader`
