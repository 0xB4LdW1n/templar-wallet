# Templar Wallet — macOS build guide

Builds `templar_wallet.app` with the Rust library inside, and optionally the
DMG. Read [`README.md`](README.md) first: the engine must be checked out
beside this repository.

## 1. Requirements

- Xcode and its command line tools (`xcode-select --install`).
- Rust through [rustup](https://rustup.rs) — the Xcode build looks for
  `~/.cargo/bin/cargo` and `~/.cargo/bin/rustup`.
- Flutter at the CI pin (see [`README.md`](README.md#toolchains)).

For a build that also runs on Intel Macs, install both Rust targets once:

```bash
rustup target add aarch64-apple-darwin x86_64-apple-darwin
```

## 2. Build the app

```bash
cd apps/gui
flutter pub get
flutter build macos --release
open build/macos/Build/Products/Release/templar_wallet.app
```

Nothing else to do: the Runner target's Run Script phase
(`apps/gui/macos/copy_wallet_ffi.sh`) builds `libwallet_ffi.dylib` for every
installed Rust target among `aarch64-apple-darwin` and `x86_64-apple-darwin`,
`lipo`s them into one universal library, copies it into
`templar_wallet.app/Contents/Frameworks/` and ad-hoc signs it. With only the
host target installed the library is host-only, which is fine for local runs.

During development:

```bash
cd apps/gui
flutter run -d macos
```

`./scripts/build_debug_app.sh` builds a debug app and copies it to the
Desktop as *Templar Wallet Debug.app*. It has the release bundle id, so it
opens the real wallet data: run one Templar instance at a time.

## 3. The DMG

```bash
./scripts/make_dmg.sh            # from the repository root
# → dist/TemplarWallet-<version>-macos.dmg
```

It packs the release build under `apps/gui/build` (or the `.app` passed as
the first argument) beside an Applications link, on the artwork from
`./scripts/make_packaging_assets.sh`. Without signing variables the DMG is
unsigned, which is what CI publishes today. Signing and notarization:
[`RELEASE.md`](RELEASE.md) § 6a.

## 4. Hardware wallets

Ledger and Jade are driven in-process and need nothing installed. The app
runs in the App Sandbox, which does not let it start the `hwi` tool, so
Trezor, Coldcard, KeepKey and BitBox are detected but cannot be used on
macOS. `scripts/setup_hwi_macos.sh` creates an HWI virtualenv in the app's
data container; it is a development convenience, not a user path.

## 5. Brand rasters

The icons and DMG art are build products of the SVGs in `assets/brand/`.
After editing one, regenerate them (macOS only):

```bash
./scripts/generate_icons.sh
```

## Notes

- Wallet data: `~/Library/Containers/dev.templarwallet.templarWallet/Data/Library/Application Support/templar_wallet`.
- Inside the DMG the bundle is named `Templar Wallet.app` (`make_dmg.sh`
  copies it under the volume name).
- CI's `macos` job builds the same way and fails unless both the app and
  `libwallet_ffi.dylib` are universal.
