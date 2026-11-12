# 0002 — The host app can inject the data directory

**Status:** accepted, in force.

## Context

On the desktop the engine finds its data folder by itself (the saved config,
the installer's choice, the platform default). Android has no such default
for a native library: the only safe place is the app-private directory that
Flutter's `path_provider` reports, and only Dart knows it.

## Decision

`crates/wallet-ffi` exports `wallet_set_data_dir(const char*) -> i32`, to be
called once before the first `wallet_call`:

| Return | Meaning |
|---|---|
| `0` | set |
| `1` | null pointer or not UTF-8 |
| `2` | empty string |
| `3` | too late: the engine already started |

On Android, `apps/gui/lib/main.dart` resolves
`getApplicationSupportDirectory()` once and passes it to
`FfiWalletBridge.setDataDir` before the bridge is used. The injected folder
wins over `TEMPLAR_DATA_DIR`, and under it every persisted file — config,
registry, vault, chain databases — stays inside that folder.

## Consequences

- The export is part of the ABI the Dart side checks for; the release
  workflow and `scripts/build_android.sh` fail a library that does not
  export `wallet_call`, `wallet_free_string` and `wallet_set_data_dir`.
- Desktop builds do not call it and keep their own resolution order
  (`docs/build/RELEASE.md`, "The Windows installer").
