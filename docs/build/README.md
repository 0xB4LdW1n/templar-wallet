# Building Templar Wallet from source

What every platform build has in common, and where each platform's steps
are. Releases are not built by hand: they come from CI ([`RELEASE.md`](RELEASE.md)).

| Platform | Guide |
|---|---|
| macOS (app and DMG) | [`MacOSBuild.md`](MacOSBuild.md) |
| Linux x64 | [`LinuxBuild.md`](LinuxBuild.md) |
| Windows x64 (app, zip, installer) | [`WindowsBuild.md`](WindowsBuild.md) |
| Android (APKs) | [`AndroidBuild.md`](AndroidBuild.md) |
| Linux / Windows on someone else's PC, from a source zip | [`HELPER_BUILDS.md`](HELPER_BUILDS.md) |
| Cutting and publishing a release | [`RELEASE.md`](RELEASE.md) |

The terminal client (`templar`) needs only Rust:
[`../guides/TUI.md`](../guides/TUI.md).

## The checkout

The wallet engine lives in its own repository,
[templarlib](https://github.com/0xB4LdW1n/templarlib). Until the library's
first tag, `apps/tui/Cargo.toml` and `crates/wallet-ffi/Cargo.toml` read it by
path from a sibling checkout, so the two repositories must sit side by side
and the library's folder must be named `templarlib`:

```text
<any folder>/
├── templarlib/       git clone https://github.com/0xB4LdW1n/templarlib.git
└── TemplarWallet/    git clone https://github.com/0xB4LdW1n/TemplarWallet.git
```

Every command in these guides runs from the wallet checkout's root, where
the workspace `Cargo.toml` is, unless it says otherwise.

The GitHub workflows check out this repository alone, so CI and the release
builds cannot build until the manifests switch to a `git` + `tag` dependency
(the TODO in those two manifests). The helper scripts have the same limit
(see `HELPER_BUILDS.md`).

## Toolchains

| Tool | Version |
|---|---|
| Rust | the CI pin, `RUST_TOOLCHAIN` in `.github/workflows/ci.yml` (any recent stable builds; clippy results can differ) |
| Flutter | the CI pin, `FLUTTER_VERSION` in `.github/workflows/ci.yml` (Dart SDK as in `apps/gui/pubspec.yaml`) |

The first Rust build compiles the whole engine (BDK, LWK and their
dependencies) and takes several minutes.

## Two artifacts, shipped together

1. the Rust FFI library, built from `crates/wallet-ffi`:
   `libwallet_ffi.dylib` (macOS), `libwallet_ffi.so` (Linux, Android),
   `wallet_ffi.dll` (Windows);
2. the Flutter app from `apps/gui`.

Flutter desktop does not cross-compile: each OS is built on that OS. If the
native library is missing at runtime, a release build stops on a fatal error
screen; it never falls back to fake data. (A debug build falls back to an
in-memory mock and shows a persistent badge.)

## Where the app looks for the native library

`apps/gui/lib/bridge/ffi_wallet_bridge.dart`, in order, then the OS loader's
default search:

| OS | Search order |
|---|---|
| macOS | `<app>/Contents/Frameworks/`, next to the executable, then the workspace `target/release/` and `target/debug/` (relative to the working directory `apps/gui`) |
| Linux | `<exe dir>/lib/`, `<exe dir>/` |
| Windows | `<exe dir>\`, `<exe dir>\lib\`, the working directory, then the workspace `target\release\` and `target\debug\` |
| Android | by soname, from the APK's `jniLibs/<abi>/` |

On macOS the Xcode build bundles the library by itself; on Linux and Windows
copy it beside the executable as the platform guides show.
