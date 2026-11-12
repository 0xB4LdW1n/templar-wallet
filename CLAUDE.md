# CLAUDE.md — Templar Wallet

## What this is

Templar Wallet is a Bitcoin + Liquid wallet for macOS, Windows, Linux and
Android, built around **Miniscript custody**, and the signing wallet of
Templar Protocol (`templar://` links). **Test networks only**: Bitcoin
testnet, Liquid testnet, a local Liquid regtest. No mainnet path, ever.

This repository is the wallet's two clients and the adapter between them and
the engine. The engine (`templar-core`, `templarlib`: BDK, LWK, Miniscript,
vault, devices, every JSON method) is its own repository,
[templarlib](https://github.com/0xB4LdW1n/templarlib), with its own
`CLAUDE.md` — engine work happens there, not here.

## Layout

```text
apps/gui/            Flutter app (macOS / Windows / Linux / Android)
  lib/bridge/        wallet_bridge.dart (typed interface), ffi_wallet_bridge.dart
                     (dart:ffi), bridge_provider.dart (which bridge), mock_wallet_bridge.dart
  lib/features/      one folder per destination (dashboard, send, receive, utxos,
                     psbt, liquid, protocol, loans, settings, …)
  lib/shared/widgets/  the design-system kit
  lib/theme/         tokens: app_colors, app_scheme, app_typography, app_layout, …
  lib/services/      platform services and SharedPreferences stores
  macos/ windows/ linux/ android/   platform runners
  packages/biometric_storage/       vendored plugin (MIT)
apps/tui/            `templar` CLI + read-only TUI (package templar-tui)
crates/wallet-ffi/   C ABI adapter over templarlib → libwallet_ffi.{dylib,so} / wallet_ffi.dll
assets/brand/        logo SVGs, source of every icon raster
packaging/           DMG art, Inno Setup script, Linux desktop entry
reproducible/        pinned build container (Dockerfile, apt-install) + in-container
                     build script (Linux, Android)
scripts/             build, packaging, icons, protocol fixture server
docs/                index at docs/README.md
design.md            the design rules
```

## The engine dependency

`apps/tui/Cargo.toml` and `crates/wallet-ffi/Cargo.toml` depend on templarlib
**by git tag** (`git = "https://github.com/0xB4LdW1n/templarlib"`,
`tag = "v0.1.0"`); `Cargo.lock` pins the commit. Cargo fetches it, so no
sibling checkout is needed. Bumping the engine: tag templarlib, change `tag`
in both manifests, `cargo update -p templarlib`, commit manifests and lock
together. To build against a local templarlib working copy, pass a Cargo
`[patch."https://github.com/0xB4LdW1n/templarlib"]` (recipe in
`docs/build/README.md`); it rewrites `Cargo.lock`, which must never be
committed that way. Never vendor or copy engine code into this repository.

`crates/wallet-ffi` takes templarlib with `default-features = false` and:

- `protocol` — always on: the Templar Protocol connector methods (Loans on
  every platform);
- `hardware` — its own feature, default on, forwarding to
  `templarlib/hardware`. Android builds with `--no-default-features`: hardware
  methods answer `HW_UNSUPPORTED`, `hwi_status` says
  `hardware_supported: false`, and the UI hides the flows.

## The bridge

- `wallet-ffi` exports `wallet_call(method, params_json)`,
  `wallet_free_string`, `wallet_set_data_dir`. It owns C strings, panic
  containment (`catch_unwind`; the workspace pins `panic = "unwind"` — keep
  it) and zeroizing request/response strings. No workflows here.
- Every answer is `{"ok": …}` or `{"err": "…"}`. Method list:
  `templar methods`, or templarlib's `docs/API.md`.
- Dart: screens talk to `WalletBridge` only. `FfiWalletBridge` runs each call
  in `Isolate.run`. A new engine method needs a `WalletBridge` member, its
  `FfiWalletBridge` mapping and a `MockWalletBridge` answer.
- **A mock can look like a working wallet.** Debug builds fall back to
  `MockWalletBridge` when the library fails to load (persistent badge);
  `--dart-define=TEMPLAR_MOCK_BRIDGE=true` forces it; widget tests always use
  it. Release builds never do: fatal error screen. Check which bridge is live
  before trusting a balance.
- Library search paths: `apps/gui/lib/bridge/ffi_wallet_bridge.dart`; the
  macOS Xcode run script (`apps/gui/macos/copy_wallet_ffi.sh`) builds and
  bundles the dylib.

## Platforms

- Desktop: sidebar shell. Android (iOS too in code; there is no iOS runner):
  `MobileShell` with the
  carousel; every phone layout behind `AppLayout.isPhone`, desktop trees
  untouched (`docs/decisions/0005-mobile-shell.md`).
- macOS runs sandboxed: Ledger and Jade work natively, HWI cannot run.
  Windows/Linux: HWI families too (in-app installer; Linux udev rules via
  `pkexec`). Android: no USB hardware, QR air-gap only.
- Camera QR scanning: macOS and Android only; elsewhere paste or file.
- Flutter desktop does not cross-compile. Build guides: `docs/build/`.

## Brand

- Name **Templar Wallet**. Bundle id `dev.templarwallet.templarWallet`;
  binary/product name `templar_wallet`; inside the DMG the bundle is
  `Templar Wallet.app`.
- Accent: **Templar crimson `#C1121F`** (`AppColors.accentDefault`); every
  other accent shade derives from it. `danger` is `#EF4444`, brighter on
  purpose — never darken it toward the accent.
- Logo sources: `assets/brand/templar-icon.svg` (badge),
  `assets/brand/templar-cross.svg` (bare mark). Rasters are build products:
  edit the SVG, run `./scripts/generate_icons.sh` (macOS).
- **`design.md` is the rule set every screen is held to.** Read it before
  changing a pixel.

## Rules

1. English only: code, comments, UI strings, docs (except `INSTALL.it.md`).
2. No wallet-critical logic in Dart.
3. Frozen coins are never spent and nothing is signed without the user's
   confirmation (password gate): keep both in every new flow.
4. Cross-OS parity: no platform-divergent flows beyond the documented
   platform limits.
5. The product name is "Templar Protocol"; network status of the protocol,
   when stated: "Today the protocol runs on a test regtest; in beta it will
   run on a server of ours; then Liquid mainnet."

## Gate

```bash
cargo fmt --all -- --check
cargo clippy --locked --workspace --all-targets -- -D warnings
cargo test --locked --workspace
cd apps/gui
flutter pub get --enforce-lockfile
flutter analyze --fatal-infos --fatal-warnings   # zero issues, infos included
flutter test
```

CI (`.github/workflows/ci.yml`, `release.yml`) runs on GitHub-hosted runners
only — never attach a self-hosted runner to this public repository. Release
runbook: `docs/build/RELEASE.md`.

The Linux and Android release files are reproducible: built in
`reproducible/Dockerfile` (every input pinned) by `scripts/repro_build.sh`,
rebuilt on a second runner and compared before `release.yml` publishes
(`docs/build/REPRODUCIBLE.md`). A toolchain bump touches the Dockerfile too;
anything that makes the build depend on time, paths or the host breaks the
`compare` job.

## Docs

`docs/README.md` is the map. Architecture of the wallet side:
`docs/ARCHITECTURE.md`. Decisions: `docs/decisions/`. Engine internals,
environment variables and the connector contract: templarlib's docs.
