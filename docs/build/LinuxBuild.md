# Templar Wallet — Linux Build Guide

Builds two artifacts: the Rust FFI library (`libwallet_ffi.so`) and the Flutter
desktop app (`templar_wallet`). Read [`README.md`](README.md) first: the
checkout, where the engine comes from, and the toolchains. Commands run from the
wallet checkout's root, where the workspace `Cargo.toml` lives.

> Building for someone else, or without installing anything? `scripts/build_linux.sh`
> does all of this in a container: see `HELPER_BUILDS.md`. The published
> `TemplarWallet-linux-x64.tar.gz` comes from the `linux` job of
> `.github/workflows/release.yml`, which runs these same steps on Ubuntu 22.04.

## 1. Requirements

### System packages (Debian/Ubuntu)

```bash
sudo apt update
sudo apt install -y \
    build-essential clang cmake ninja-build pkg-config \
    libgtk-3-dev liblzma-dev libstdc++-12-dev libudev-dev \
    curl git unzip xz-utils zip
```

Why each matters:

| Package | Needed by |
|---|---|
| `build-essential`, `clang` | Rust linker + Flutter Linux toolchain (clang is required by Flutter) |
| `cmake`, `ninja-build` | Flutter Linux build system |
| `libgtk-3-dev` | Flutter Linux embedder + `file_selector` (native save/open dialogs) |
| `liblzma-dev`, `libstdc++-12-dev` | Flutter's Linux desktop requirements; clang builds against GCC 12's C++ library |
| `pkg-config`, `libudev-dev` | Rust `hidapi` (hidraw backend, Ledger) and `serialport` (Jade): both find USB devices through libudev, and the Rust build stops without its headers |

No OpenSSL is needed: every TLS connection (Electrum, the explorer HTTP
client) goes through rustls.

Fedora equivalents: `clang cmake ninja-build pkgconf-devel gtk3-devel xz-devel gcc-c++ systemd-devel`.

### Hardware wallet permissions (runtime, not build)

Device nodes are root-only until udev rules are installed, so `hwi enumerate`
comes back empty for a normal user. The app installs the rules for you — the
hardware setup screen offers **Fix device permissions**, which writes the
bundled HWI rules to `/etc/udev/rules.d/` behind one `pkexec` prompt and
reloads udev. Replug the device afterwards, and log out and back in once so
the `plugdev` group takes effect. See
[`apps/gui/assets/udev/README.md`](../../apps/gui/assets/udev/README.md).

### Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
rustc --version   # see README.md, "Toolchains", for the version CI pins
```

### Flutter

The version CI pins (see [`README.md`](README.md#toolchains)).

```bash
git clone https://github.com/flutter/flutter.git -b stable ~/flutter
export PATH="$HOME/flutter/bin:$PATH"
flutter config --enable-linux-desktop
flutter doctor        # must show a green check for "Linux toolchain"
```

## 2. Build the Rust FFI library

From the repo root (where the workspace `Cargo.toml` is):

```bash
cargo build --release -p wallet-ffi
```

Output: `target/release/libwallet_ffi.so`

The first build fetches the engine (templarlib, at the pinned tag), compiles
it with BDK, LWK and their dependencies, and takes several minutes.

## 3. Build the Flutter app

```bash
cd apps/gui
flutter pub get
flutter build linux --release
```

Output bundle: `build/linux/x64/release/bundle/`

## 4. Bundle the FFI library

The app looks for `libwallet_ffi.so` in `<exe dir>/lib/` then `<exe dir>/`
(see `apps/gui/lib/bridge/ffi_wallet_bridge.dart`). Copy it into the bundle
(from `apps/gui`):

```bash
cp ../../target/release/libwallet_ffi.so \
   build/linux/x64/release/bundle/lib/
```

Without this, the app fails at startup with a dynamic library load error.

## 5. Run

```bash
./build/linux/x64/release/bundle/templar_wallet
```

To distribute, ship the whole `bundle/` directory (executable + `lib/` +
`data/`) — it is self-contained apart from GTK 3, which target machines need
installed (`libgtk-3-0`).

`templar://` links (Templar Protocol) need the desktop entry
`packaging/linux/dev.templarwallet.templar_wallet.desktop` installed with the
executable on `PATH`:

```bash
cp packaging/linux/dev.templarwallet.templar_wallet.desktop ~/.local/share/applications/
update-desktop-database ~/.local/share/applications
xdg-mime default dev.templarwallet.templar_wallet.desktop x-scheme-handler/templar
```

See [`../guides/PROTOCOL_CONNECTOR.md`](../guides/PROTOCOL_CONNECTOR.md#url-scheme-registration).

## Notes & caveats

- **Testnet only** — Bitcoin testnet + Liquid testnet; no mainnet.
- **Network endpoints**: Electrum `ssl://electrum.blockstream.info:60002`
  (Bitcoin) and `elements-testnet.blockstream.info:50002` (Liquid); outbound
  TLS access required at runtime.
- **QR camera scanning** (`mobile_scanner`) has no Linux desktop
  implementation — the app builds and runs fine, but the "Scan QR" camera
  option is unavailable; use Paste/File import instead.
- **Hardware wallets**: Ledger and Jade are driven in-process; Trezor,
  Coldcard, KeepKey and BitBox go through the `hwi` binary, which the app
  offers to download. Optional — only needed for those devices.
- Wallet data is stored under the XDG data dir (`~/.local/share/templar_wallet`).
