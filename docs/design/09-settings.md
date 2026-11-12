# Settings

This document defines the settings area.

## Purpose

Provide wallet management, app configuration, network setup, and diagnostic information.

## Layout

Settings uses a left subsection menu plus a main content area.

Sections:

- Wallets
- Network & sync
- Security
- Appearance
- Fee defaults
- Advanced & debug
- About

## Wallets section

Purpose:

- Show all locally stored wallets and manage them

Main UI elements:

- Wallet list table
- Columns for name, type, network, balance
- Actions: open, edit, delete
- Add wallet button
- Danger zone

Danger zone actions:

- Delete a wallet
- Wipe everything

Behavior:

- Delete removes encrypted local data for one wallet only
- Wipe everything removes all wallets and settings from the machine
- Use strong confirmation UX for destructive operations

## Network & sync

Fields / controls:

- Network selector: testnet, mainnet, regtest
- Bitcoin node URL
- Liquid node URL
- Auto sync settings
- Tor toggle placeholder

Important note:

- Tor is coming soon and does not need implementation yet

## Security

Fields / controls:

- Require password to log in
- Lock app
- Future local security options

## Appearance

Fields / controls:

- Light mode / dark mode
- Default fiat currency

## Fee defaults

Fields / controls:

- Default fee presets and behavior preferences

## Advanced & debug

Fields / controls:

- Show wallet storage directory
- Future diagnostic items can be added here

## About

Fields / controls:

- Wallet version
- Documentation button linking to GitHub docs
- Source code button linking to the GitHub repository

## Shared components

Build reusable widgets for:

- Settings subsection menu
- Wallet table row
- Danger zone card
- Labeled settings field row
- External link action row
