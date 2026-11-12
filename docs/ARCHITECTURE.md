# Architecture — the wallet side

How Templar Wallet's two clients sit on the engine, what crosses the boundary
between them, and where state lives. What happens inside the engine is
templarlib's
[`docs/ARCHITECTURE.md`](https://github.com/0xB4LdW1n/templarlib/blob/main/docs/ARCHITECTURE.md).

## The pieces

```text
 apps/gui  (Flutter: macOS, Windows, Linux, Android)     apps/tui  (`templar` binary)
   lib/features/…  screens                                  clap CLI + ratatui TUI
   lib/bridge/     WalletBridge ─ FfiWalletBridge                    │
        │  dart:ffi, two JSON strings in, one out                    │ Rust call
 crates/wallet-ffi (C ABI: libwallet_ffi.{dylib,so} / wallet_ffi.dll)│
        └──────────────── TemplarLib::call(method, params) ──────────┘
                          templarlib    (../templarlib: state, workflows, dispatch)
                          templar-core  (BDK, LWK, Miniscript, vault, devices)
```

| Part | Owns | Must not |
|---|---|---|
| `apps/gui` | Screens, navigation, theme, platform integration, UI-only preferences | Hold wallet-critical logic: balances, descriptors, transaction building and signing all come from the engine |
| `crates/wallet-ffi` | C strings, panic containment, wiping response buffers, the exported symbols | Implement wallet workflows |
| `apps/tui` | CLI parsing, terminal rendering, operator help | Implement wallet workflows, or bypass previews, frozen-coin checks and transaction inspection |
| templarlib | Every wallet workflow and the JSON method contract | — (documented in its own repository) |

A new workflow belongs in templarlib, then appears in both clients.

## The FFI boundary

`crates/wallet-ffi` exports three C functions:

| Symbol | Does |
|---|---|
| `wallet_call(method, params_json) -> char*` | Runs one engine method and returns its JSON answer |
| `wallet_free_string(ptr)` | Frees (and wipes) a string `wallet_call` returned |
| `wallet_set_data_dir(path) -> i32` | Optional, before the first call: where the engine keeps its files ([decision 0002](decisions/0002-host-injects-the-data-directory.md)) |

- `wallet_call` runs the engine inside `catch_unwind`, so a Rust panic comes
  back as an error instead of killing the app. That needs unwinding: the
  workspace `Cargo.toml` pins `panic = "unwind"` for release builds.
- Strings in both the request and the response are zeroized after use,
  because some carry seed or key material.
- On the Dart side `FfiWalletBridge` (`apps/gui/lib/bridge/ffi_wallet_bridge.dart`)
  makes every call in a background isolate (`Isolate.run`), so the UI thread
  never blocks; the engine serialises calls behind its own lock.
- Release builds and CI check that the library exports all three symbols.

### Features

`crates/wallet-ffi` depends on templarlib with `default-features = false`
and chooses:

| Feature | Where | Effect |
|---|---|---|
| `protocol` | always on | The Templar Protocol connector methods; the app offers Loans on every platform |
| `hardware` | default on; off on Android | USB hardware wallets. Without it the hardware methods answer `HW_UNSUPPORTED` and `hwi_status` reports `hardware_supported: false` ([decision 0001](decisions/0001-android-without-usb-hardware.md)) |

## The JSON contract

Every call is a method name and a JSON object of parameters; every answer is
one envelope:

```json
{"ok": <value>}
{"err": "<message>"}
```

Many errors start with a tag (`HWI_MISSING`, `DEVICE_NOT_READY`,
`LIQUID_HW_UNSUPPORTED`, …) that the UI matches to show the right remedy.
The list of methods, their parameters and their answers is templarlib's
[`docs/API.md`](https://github.com/0xB4LdW1n/templarlib/blob/main/docs/API.md);
`templar methods` prints the names the linked engine accepts.

In Dart, `WalletBridge` (`apps/gui/lib/bridge/wallet_bridge.dart`) is the
typed interface the screens use; `FfiWalletBridge` maps each method to
`wallet_call`. `MockWalletBridge` serves in-memory data to widget tests and,
in debug builds only, when the native library fails to load or
`--dart-define=TEMPLAR_MOCK_BRIDGE=true` is set; the shell then shows a
persistent badge. A release build never serves mock data: a missing library
is a fatal error screen (`apps/gui/lib/bridge/bridge_provider.dart`).

## Where state lives

| What | Where | Owner |
|---|---|---|
| Wallet registry (descriptors, frozen coins), encrypted vault, chain databases, asset metadata | The data folder (per platform: [`INSTALL.md`](../INSTALL.md#app-data-and-a-clean-reset)) | Engine |
| Config: data folder location, last wallet, Liquid network | `templar_wallet.json` beside the data folder (inside it when the folder is injected or set by `TEMPLAR_DATA_DIR`) | Engine |
| Single-instance lock | `app.lock` in the data folder: a second process on the same folder is refused, GUI and TUI alike | Engine |
| Log | `logs/templar.log` in the data folder | App (`services/crash_log.dart`) |
| UI preferences, UTXO and co-signer labels, issued-asset list, fee-bump and consolidation bookkeeping, price cache, Templar Protocol records | SharedPreferences | App (`apps/gui/lib/services/`) |
| Biometric unlock key | Android Keystore (`biometric_storage`) or a macOS Secure Enclave key | App ([decision 0006](decisions/0006-biometric-unlock.md)) |

Nothing secret goes to SharedPreferences except a Templar Protocol site's
portfolio token ([`guides/PROTOCOL_CONNECTOR.md`](guides/PROTOCOL_CONNECTOR.md#local-records)).

## Platforms

| Platform | Shell | Native library | Hardware wallets | Camera QR | `templar://` |
|---|---|---|---|---|---|
| macOS | desktop sidebar | universal `libwallet_ffi.dylib` in `Contents/Frameworks`, built by the Xcode run script | Ledger, Jade (sandbox blocks HWI) | yes | `Info.plist` |
| Windows | desktop sidebar | `wallet_ffi.dll` beside the exe | Ledger, Jade, HWI families | no (paste / file) | installer only |
| Linux | desktop sidebar | `lib/libwallet_ffi.so` in the bundle | Ledger, Jade, HWI families (udev rules) | no (paste / file) | desktop entry |
| Android | mobile shell ([decision 0005](decisions/0005-mobile-shell.md)) | `libwallet_ffi.so` per ABI in the APK | none; QR air-gap | yes | intent filter |

The terminal client builds wherever Rust does and reads the same data folder
as the app (not at the same time). Builds per platform: [`build/`](build/README.md).
