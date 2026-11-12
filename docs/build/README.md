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
| Rebuilding a release's Linux and Android files to check them | [`REPRODUCIBLE.md`](REPRODUCIBLE.md) |

The terminal client (`templar`) needs only Rust:
[`../guides/TUI.md`](../guides/TUI.md).

## The checkout

One clone:

```bash
git clone https://github.com/0xB4LdW1n/templar-wallet.git
cd templar-wallet
```

Every command in these guides runs from the wallet checkout's root, where
the workspace `Cargo.toml` is, unless it says otherwise.

The wallet engine lives in its own repository,
[templarlib](https://github.com/0xB4LdW1n/templarlib).
`apps/tui/Cargo.toml` and `crates/wallet-ffi/Cargo.toml` name it by git tag
(`tag = "vX.Y.Z"`) and `Cargo.lock` pins that tag's commit, so the first
build fetches it from GitHub like any other dependency. CI, the release
workflow and the helper scripts build the same way.

**Building against a local templarlib.** To try engine changes in the
wallet before they are tagged, clone templarlib next to the wallet and
override the git source with a Cargo patch:

```bash
cargo build --config 'patch."https://github.com/0xB4LdW1n/templarlib".templarlib.path="../templarlib/crates/templarlib"'
```

or put the same table in an untracked `.cargo/config.toml`:

```toml
[patch."https://github.com/0xB4LdW1n/templarlib"]
templarlib = { path = "../templarlib/crates/templarlib" }
```

While the patch is active Cargo rewrites `Cargo.lock` (the `source` lines
of `templarlib` and `templar-core` disappear), so `--locked` builds fail.
Never commit that `Cargo.lock` or the config file; drop the patch and
`git restore Cargo.lock` when done.

**Bumping the engine.** Tag the new version in templarlib, change
`tag = "vX.Y.Z"` in both manifests, run `cargo update -p templarlib`, and
commit the manifests and `Cargo.lock` together.

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
