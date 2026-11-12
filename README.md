# Templar Wallet

> [!WARNING]
> **Alpha software, testnet only.** Templar Wallet is still in alpha: expect
> bugs, rough edges and breaking changes between releases. Everything runs on
> Bitcoin testnet and Liquid testnet (plus a local Liquid regtest for
> development) and mainnet is refused by design — use free test coins only,
> and never import a recovery phrase that holds real funds.

A Bitcoin and Liquid wallet for macOS, Windows, Linux and Android, built
around **Miniscript custody**: besides single-sig and multisig, a wallet can
carry a real spending policy — timelocks, hashlocks, thresholds, AND/OR —
from a template or a policy builder.

## What it does

- **Wallets** — software single-sig (BIP84), multisig on Bitcoin (P2WSH) and
  Liquid, Miniscript policy wallets, watch-only, hardware wallets (Ledger and
  Jade over USB, others through HWI) and air-gapped signing over QR (BC-UR).
- **Encrypted at rest** — recovery phrases live in a vault sealed with
  Argon2id + XChaCha20-Poly1305 behind an app password; Touch ID on macOS,
  fingerprint on Android, auto-lock everywhere.
- **Send and receive** — a guided send with fee presets, MAX, several
  recipients, manual coin selection and RBF; payment requests (BIP21) on
  receive; activity and a portfolio chart.
- **Coin control** — every coin as a banknote or a row, sized by its share of
  your holdings; labels, consolidation, and **freezing**: a frozen coin stays
  in the balance but is never spent — not by a payment, not by MAX, not by a
  consolidation — until you unfreeze it.
- **Co-signing** — import a PSBT or PSET by paste, file or camera, read what
  it really does, sign, merge co-signers' copies, broadcast.
- **Liquid** — confidential assets, issuance / reissuance / burn on testnet,
  LiquiDEX swaps and a peg-in / peg-out flow (simulated provider).
- **Templar Protocol** — the wallet is the signing side of Templar Protocol,
  a peer-to-peer lending protocol on Liquid: a site hands over loan
  transactions through `templar://` links, the wallet shows them and signs
  only what you confirm. Today the protocol runs on a test regtest; in beta
  it will run on a server of ours; then Liquid mainnet.

## Download

Every release is built by CI from a tagged commit and published on the
[Releases](https://github.com/0xB4LdW1n/templar-wallet/releases) page, with a
`SHA256SUMS.txt` beside the files. The newest build is always at these links:

| Platform | File |
|---|---|
| macOS 10.15+ (Apple Silicon and Intel) | [TemplarWallet-macos.dmg](https://github.com/0xB4LdW1n/templar-wallet/releases/latest/download/TemplarWallet-macos.dmg) |
| Windows 10/11 x64 — installer | [TemplarWallet-windows-x64-setup.exe](https://github.com/0xB4LdW1n/templar-wallet/releases/latest/download/TemplarWallet-windows-x64-setup.exe) |
| Windows 10/11 x64 — portable | [TemplarWallet-windows-x64.zip](https://github.com/0xB4LdW1n/templar-wallet/releases/latest/download/TemplarWallet-windows-x64.zip) |
| Linux x64 (glibc 2.35+: Ubuntu 22.04+, Debian 12+) | [TemplarWallet-linux-x64.tar.gz](https://github.com/0xB4LdW1n/templar-wallet/releases/latest/download/TemplarWallet-linux-x64.tar.gz) |
| Android 7.0+ phones (arm64) | [TemplarWallet-android-arm64.apk](https://github.com/0xB4LdW1n/templar-wallet/releases/latest/download/TemplarWallet-android-arm64.apk) |
| Android emulators / x86_64 devices | [TemplarWallet-android-x86_64.apk](https://github.com/0xB4LdW1n/templar-wallet/releases/latest/download/TemplarWallet-android-x86_64.apk) |

The Linux and Android files are **reproducible**: rebuild them from the
release's tag with `scripts/repro_verify.sh <tag>` and you get the same
bytes (the APKs, signature aside), so you need not trust the build server:
[docs/build/REPRODUCIBLE.md](docs/build/REPRODUCIBLE.md).

The desktop builds are not signed with a paid certificate yet, so macOS and
Windows warn on first launch. How to get past that, per platform:
[INSTALL.md](INSTALL.md) (English) · [INSTALL.it.md](INSTALL.it.md) (italiano).

## Try it in five minutes

1. Download and install the file for your system (see above; on macOS and
   Windows, [INSTALL.md](INSTALL.md) shows how to open an unsigned build).
2. Launch it and set an **app password** — it encrypts every recovery phrase
   on the device.
3. **Create a wallet** with Liquid enabled. Write the recovery phrase down.
4. Open **Receive** and fund the wallet from a faucet:
   [Bitcoin testnet](https://coinfaucet.eu/en/btc-testnet/),
   [Liquid testnet](https://liquidtestnet.com/faucet).
   Press **Sync**.
5. Send a few sats back to yourself, look at the coins in **UTXOs**, freeze
   one, and try to spend it.

Using it with a Templar Protocol site:
[docs/guides/TEMPLAR_PROTOCOL.md](docs/guides/TEMPLAR_PROTOCOL.md).

## From source

The engine lives in its own repository,
[templarlib](https://github.com/0xB4LdW1n/templarlib); this repository holds
the two clients built on it — the Flutter app (`apps/gui`) and the `templar`
terminal client (`apps/tui`). Cargo fetches the engine at the tag the
manifests pin, so one clone is enough:

```bash
git clone https://github.com/0xB4LdW1n/templar-wallet.git
cd templar-wallet
cargo install --locked --path apps/tui     # the terminal client
templar --help
```

- Building the app for each platform: [docs/build/](docs/build/README.md).
- The terminal client: [docs/guides/TUI.md](docs/guides/TUI.md).
- How the pieces fit: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- Working on the code: [CONTRIBUTING.md](CONTRIBUTING.md).
- Everything else: [docs/README.md](docs/README.md).

## Security

Please report vulnerabilities privately — see [SECURITY.md](SECURITY.md).

## License

Licensed under either of [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at
your option. The vendored `biometric_storage` plugin under `apps/gui/packages/`
keeps its own MIT license, and the bundled fonts their SIL Open Font License
(`apps/gui/assets/fonts/OFL-*.txt`).
