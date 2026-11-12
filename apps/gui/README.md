# templar_wallet

The Flutter app of Templar Wallet — macOS, Windows, Linux and Android. Every
wallet operation goes to the Rust engine ([templarlib](https://github.com/0xB4LdW1n/templarlib))
through the C ABI in [`crates/wallet-ffi`](../../crates/wallet-ffi/README.md);
the Dart side of that boundary is `lib/bridge/`.

- Build and run, per platform: [`docs/build/`](../../docs/build/README.md).
- The checks every change passes: [`CONTRIBUTING.md`](../../CONTRIBUTING.md).
- How the app, the adapter and the engine fit: [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md).
- The visual rules every screen follows: [`design.md`](../../design.md).

`packages/biometric_storage` is a vendored copy of a plugin and keeps its own
MIT licence.
