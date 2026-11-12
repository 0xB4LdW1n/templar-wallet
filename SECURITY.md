# Security

Templar Wallet handles keys, so security reports get priority over everything
else.

## Scope

The wallet runs on **Bitcoin testnet and Liquid testnet** (plus a local Liquid
regtest for development). It refuses mainnet by design, so no report can put
real funds at risk today — but the key handling, the encrypted vault and the
signing checks are the ones mainnet will use, and that is what matters.

This repository is the wallet: the Flutter app (`apps/gui`), the terminal
client (`apps/tui`) and the C ABI adapter between the app and the engine
(`crates/wallet-ffi`). Particularly interesting here:

- a screen that shows a transaction one way while the engine signs another —
  the review, co-sign and Templar Protocol request screens
  (`apps/gui/lib/features/`);
- a `templar://` link, a QR code or a pasted file that makes the app do
  something the user did not confirm, or skips the password gate;
- a recovery phrase or private key that leaks through the app: logs,
  screenshots of secure screens, the clipboard, an export, the biometric
  unlock path, Android backups;
- memory or string handling at the FFI boundary (`crates/wallet-ffi`):
  secrets not wiped, a panic that crosses into Dart;
- a release build that runs with fake data instead of the engine;
- the build and release pipeline (`.github/workflows/`, `scripts/`,
  `packaging/`).

**Engine issues go to the library.** Vault encryption (Argon2id +
XChaCha20-Poly1305), PSBT / PSET inspection, frozen-coin enforcement,
Miniscript, device drivers and the JSON methods live in
[templarlib](https://github.com/0xB4LdW1n/templarlib); report those through
that repository's private reporting. If you are not sure which side a
problem is on, report it here.

The Templar Protocol site and its services are a separate product: a flaw
there that does not involve the wallet is out of scope here.

## Reporting

Please **do not open a public issue** for a vulnerability. Use GitHub's
private reporting instead: the repository's **Security** tab → **Report a
vulnerability**. Include what you did, what happened, and the version
(Settings › About).

You will get an answer within a few days. Fixes ship in a new release, and
the report is credited in the changelog unless you ask otherwise.
