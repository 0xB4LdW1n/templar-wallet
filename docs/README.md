# Templar Wallet documentation

Where to find what. Nothing under `docs/` is compiled; the one file that
ships inside the release bundles is the root [`INSTALL.md`](../INSTALL.md).

## Using the wallet

| Read | When you want to |
|---|---|
| [`../INSTALL.md`](../INSTALL.md) · [`../INSTALL.it.md`](../INSTALL.it.md) | Install a release and get started (English · Italian) |
| [`guides/TEMPLAR_PROTOCOL.md`](guides/TEMPLAR_PROTOCOL.md) | Use the wallet with a Templar Protocol site: connect, sign, Loans |
| [`guides/TUI.md`](guides/TUI.md) | Install and operate the `templar` terminal client |
| [`guides/LOCAL_ORDERBOOK.md`](guides/LOCAL_ORDERBOOK.md) | Point the wallet at a LiquiDEX order book (the service lives in Templar Protocol) |

## Building and releasing

| Read | When you want to |
|---|---|
| [`build/README.md`](build/README.md) | Build from source: the checkout and the engine's tag, toolchains, then one guide per platform |
| [`build/HELPER_BUILDS.md`](build/HELPER_BUILDS.md) | Have someone else build Linux and Windows from a source zip |
| [`build/RELEASE.md`](build/RELEASE.md) | Cut a release, the download links, signing keys, code signing |
| [`build/REPRODUCIBLE.md`](build/REPRODUCIBLE.md) | Check that a release's Linux and Android files were built from its tag |
| [`../CONTRIBUTING.md`](../CONTRIBUTING.md) | Set up a working tree and pass the gate |

## How it works

| Read | When you want to |
|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | The two clients, the FFI boundary, the JSON contract, where state lives, platforms |
| [`guides/PROTOCOL_CONNECTOR.md`](guides/PROTOCOL_CONNECTOR.md) | The wallet side of the Templar Protocol connector, and testing it without a site |
| [`decisions/`](#decisions) | Why things are the way they are |
| [`../design.md`](../design.md) | The design rules every screen is held to (tokens in `apps/gui/lib/theme/`) |
| [`design/`](design/00-overview.md) | The original UI migration notes, mockups and HTML prototype. Historical: where they disagree with `design.md` (the accent colour, for one), `design.md` wins |

The engine has its own documentation in
[templarlib](https://github.com/0xB4LdW1n/templarlib):
[architecture](https://github.com/0xB4LdW1n/templarlib/blob/main/docs/ARCHITECTURE.md),
[every JSON method](https://github.com/0xB4LdW1n/templarlib/blob/main/docs/API.md),
[integration and environment variables](https://github.com/0xB4LdW1n/templarlib/blob/main/docs/INTEGRATION.md),
[the Templar Protocol connector contract](https://github.com/0xB4LdW1n/templarlib/blob/main/docs/CONNECTOR.md).

## Testing

| Read | When you want to |
|---|---|
| [`guides/HARDWARE_TESTING.md`](guides/HARDWARE_TESTING.md) | Test Ledger and Jade over USB, Jade over QR, devices in a multisig |
| [`guides/LIQUID_MULTISIG.md`](guides/LIQUID_MULTISIG.md) | How a multisig spans Bitcoin and Liquid, and its test plan |
| [`fixtures/protocol/`](fixtures/protocol/connect.json) | Stand-in Templar Protocol requests, served by `scripts/protocol_fixture_server.py` |

`images/` holds the golden images the Flutter protocol tests compare
against. They are rendered on macOS, so those tests carry the `golden` tag
and CI (Ubuntu) skips them: `flutter test --tags golden` on a Mac.

## Decisions

| Record | Decision |
|---|---|
| [0001](decisions/0001-android-without-usb-hardware.md) | Android ships without USB hardware wallets |
| [0002](decisions/0002-host-injects-the-data-directory.md) | The host app can inject the data directory |
| [0003](decisions/0003-android-abis.md) | Android ABIs: arm64-v8a and x86_64 only |
| [0004](decisions/0004-android-data-protection.md) | Android: no app backup, secure screens for secrets |
| [0005](decisions/0005-mobile-shell.md) | One mobile shell; phone layouts never change the desktop |
| [0006](decisions/0006-biometric-unlock.md) | Biometric unlock opens the vault; it does not confirm on Android |
