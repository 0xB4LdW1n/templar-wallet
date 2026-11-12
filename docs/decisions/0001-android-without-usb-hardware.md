# 0001 — Android ships without USB hardware wallets

**Status:** accepted, in force.

## Context

The desktop builds drive hardware wallets over USB: Ledger over HID
(`hidapi`), Jade over USB serial (`serialport`, `lwk_jade`), the other
families through the `hwi` command-line tool. None of these transports runs
on stock Android, and their C dependencies do not cross-compile for it.

## Decision

The Android build leaves the whole USB stack out and keeps air-gapped
signing over QR (BC-UR), which is pure Rust, as the external-signer route.

- `crates/wallet-ffi` has a `hardware` feature, on by default, that forwards
  to `templarlib/hardware`. `scripts/build_android.sh` builds the library with
  `--no-default-features`.
- The hardware methods stay in the JSON contract on Android: they answer an
  error starting with `HW_UNSUPPORTED`, and `hwi_status` reports
  `hardware_supported: false` (Dart: `HwiStatus.hardwareSupported`), so the
  UI hides the hardware flows instead of failing inside them.
- The `protocol` feature of the library is on for every platform: Android
  offers the Templar Protocol connector like the desktop.

## Consequences

- One Dart code path for every platform; the bridge never needs to know
  which build it is talking to beyond `hardware_supported`.
- Android users sign with a hardware device only over QR, and Liquid on a
  hardware device (Jade over USB only) is not available there.
- A Bluetooth or USB-OTG transport would be new work in the library, not a
  flag flip.
