# Templar Protocol connector — the wallet side

For developers and testers of the wallet. It covers what Templar Wallet
implements of the Templar Protocol connector, where that lives in this
repository, and how to exercise it without a site.

- **Using the wallet with a protocol site** (connect, sign, Loans, errors):
  [`TEMPLAR_PROTOCOL.md`](TEMPLAR_PROTOCOL.md).
- **The contract itself** — the `templar://` links, the request and callback
  JSON, the portfolio and open-link endpoints, the loan key and the proof of
  key: [`docs/CONNECTOR.md`](https://github.com/0xB4LdW1n/templarlib/blob/main/docs/CONNECTOR.md)
  in templarlib.
- **The engine methods** the wallet calls for it (`get_protocol_escrow_xpub`,
  `inspect_pset`, `sign_pset` / `sign_pset_hw`, `protocol_check_pset`,
  `protocol_is_check_pset`):
  [`docs/API.md`](https://github.com/0xB4LdW1n/templarlib/blob/main/docs/API.md)
  in templarlib. `crates/wallet-ffi` always builds them in (the library's
  `protocol` feature is on for every platform).

Today the protocol runs on a test regtest; in beta it will run on a server of
ours; then Liquid mainnet.

## What the wallet does

| Step | Entry point | Wallet behaviour |
|---|---|---|
| Connect | `templar://connect` from the site | Fetches and validates the request (version, nonce, origin, transport, expiry, network), lets the user choose a Liquid wallet (software seed or Jade), shows what will be shared, and after the confirmation gate posts the watch-only CT descriptor, the loan key and a receive address. When the request carries a challenge, a software wallet also signs the proof of key and sends it. The answer's portfolio token is kept for the Loans page. |
| Sign | `templar://sign` from a loan page | Shows the site's summary next to the engine's own reading of the PSET (`inspect_pset`), requires the gate, signs (`sign_pset`, or `sign_pset_hw` on a Jade) and posts the signed PSET. Never broadcasts, never stores the PSET. |
| Proof of key | `templar://sign` with action `proof` | The engine rebuilds the expected check PSET from the challenge and this wallet's loan key (`protocol_is_check_pset`); the screen refuses anything else, naming the reason, then signs through the ordinary route. |
| Loans | `/loans` | Reads the portfolio with the stored token; **Sign now** feeds a loan's `templar://sign` link to the app's own link handler; **Open on Templar Protocol** asks the site for a one-time link and opens it in the system browser (the token never goes in a URL; a link to another host is refused). A `401` drops the token. |
| Forget a site | Settings › Templar Protocol | Removes the local record; when the site handed out a portfolio token, also revokes it on the site. |

The confirmation gate (`features/protocol/protocol_confirm_gate.dart`) is the
same everywhere: a ticked statement, then the button, then the app password.
The preferred wallet only decides which wallet is offered first.

## Where it lives

All paths under `apps/gui/lib/`.

| Path | What |
|---|---|
| `services/protocol_link_service.dart` | Receives links through `app_links`; holds them until the vault is unlocked |
| `features/protocol/models/protocol_link.dart` | Link and request parsing, `validateProtocolRequest`, the typed `ProtocolNetworkMismatch` |
| `features/protocol/protocol_request_screen.dart` | Connect, sign and proof screens, the wallet chooser, the callbacks |
| `features/protocol/protocol_transaction_review.dart` | The transaction reading shown beside the site's summary |
| `features/protocol/protocol_network_mismatch_card.dart` | The mismatch card and its switch |
| `features/protocol/models/protocol_proof.dart` | Proof-of-key wording, including the Jade limitation |
| `services/protocol_portfolio_service.dart` | Portfolio read and one-time open link |
| `services/protocol_store.dart` | Local records (below) |
| `features/loans/` | The Loans page and loan detail |
| `features/settings/protocol_section.dart` | Settings › Templar Protocol |
| `features/settings/liquid_network_switch.dart` | `switchLiquidNetwork`, shared with Settings › Network & Sync |

## When the networks disagree

`validateProtocolRequest` throws a `ProtocolNetworkMismatch` instead of a
sentence, and the request screen renders `ProtocolNetworkMismatchCard`
instead of the generic error.

| Kind | When | What the card offers |
|---|---|---|
| `network` | The site is on the other network the wallet runs (`liquid-testnet` ↔ `liquid-regtest`). | Switch this wallet's Liquid network, then the request is fetched again. |
| `chain` | Both say `liquid-regtest` but the policy assets differ: two separately started `elementsd` instances are different chains. | Switch to the site's chain, re-applying regtest with the site's asset id. |
| `unsupported` | `liquid` (mainnet) or a name this build does not know. | Only **Open Network settings**. |

When `TEMPLAR_LIQUID_NETWORK` fixes the network for the run, the card says so
and drops the switch. When the site's single-use token expired while the
network was being switched, the refusal offers to open the site, where a new
one is issued.

The switch is `switchLiquidNetwork`: the same confirmation and the same
closing of the open wallet as Settings › Network & Sync. Afterwards the
wallet list is read again and the wallet chosen anew, because the engine
closed whatever was open.

On regtest a request may carry `policy_asset`, the L-BTC asset id of the
site's chain (64 lower-case hex characters). The wallet uses it to notice a
same-name, different-chain mismatch and to prefill the asset id the switch
applies; without it the stock `liquidregtest` id is offered. A malformed
value is ignored rather than treated as another chain; on testnet it is not
read.

## Local records

`services/protocol_store.dart` keeps the connector's bookkeeping in
SharedPreferences under `protocol_sites_v1`, `protocol_history_v1` and
`protocol_preferred_wallet_v1`, plus the portfolio token of each connected
site. They are device-local: not in a backup, not on another machine. They
never hold a PSET, amounts, the site's summary, a descriptor or a key — the
loan key appears as its fingerprint alone. Deleting a wallet deletes its
records.

## URL scheme registration

| OS | Registration | Notes |
|---|---|---|
| macOS | `apps/gui/macos/Runner/Info.plist`, `CFBundleURLTypes` (`templar`) | Launch Services registers the scheme when the `.app` is built or copied to `/Applications`. |
| Windows | `packaging/windows/templar-wallet.iss`, `[Registry]` (`HKA\Software\Classes\templar`) | Only the installer registers it; the zip does not. A second launch hands the link to the running instance (`apps/gui/windows/runner/main.cpp`). |
| Linux | `packaging/linux/dev.templarwallet.templar_wallet.desktop` (`MimeType=x-scheme-handler/templar;`, `Exec=templar_wallet %u`) | Install the file into `~/.local/share/applications/` with the executable on `PATH`, then `xdg-mime default dev.templarwallet.templar_wallet.desktop x-scheme-handler/templar`. A second launch forwards the link to the running window. |
| Android | `apps/gui/android/app/src/main/AndroidManifest.xml`, `VIEW` + `BROWSABLE` intent filter for `templar` | Delivered through `app_links`. |

## Testing without a site

The fixtures in `docs/fixtures/protocol/` stand in for a protocol site:

```bash
python3 scripts/protocol_fixture_server.py       # serves them on 127.0.0.1:8765
                                                 # and prints every callback body
open "templar://connect?url=http://127.0.0.1:8765/connect.json&nonce=fixture-nonce-connect"
open "templar://sign?url=http://127.0.0.1:8765/sign.json&nonce=fixture-nonce-sign"
```

The fixtures are on **Liquid testnet**. The sign fixture spends a fake loan
escrow whose contract names the key of the BIP39 test vector
`abandon abandon … about` (fingerprint `73c5da0a`): restore that phrase as a
software wallet with Liquid enabled and the request shows the escrow input as
this wallet's key. Any other wallet sees it as not its own and the gate stays
disabled.

Plain `http://` is accepted only for `localhost`, `127.0.0.1` and `::1`; a
remote site must use `https://`.

## Against a local regtest

Start the protocol's regtest node and site as the protocol's own
documentation describes. The engine's defaults for the regtest backend are
`elementsd` RPC at `http://127.0.0.1:18884` with user and password
`templar` (overridable with `TEMPLAR_ELEMENTS_RPC_URL`, `_USER`, `_PASS`).
In the wallet: Settings › Network & Sync › Liquid network › Regtest, reopen
the wallet, sync, and fund a Liquid receive address from the node. Then
connect from the site and take an offer; the origination request opens
through `templar://sign`.

The headless acceptance tests that drive the connector against a running
site, without the GUI, live in templarlib with the engine; see its
[`docs/CONNECTOR.md`](https://github.com/0xB4LdW1n/templarlib/blob/main/docs/CONNECTOR.md).

## Limits

- Connect takes a software wallet or a Jade (its BIP87 key is the loan key).
  Signing a loan step works with both; the proof of key needs a software
  wallet: Jade signing of the check's zero-value input has not been
  exercised on hardware.
- The site's summary is free text; the wallet shows it beside its own reading
  of the PSET and asks the user to compare. It cannot reconcile the two
  arithmetically.
- No wallet-side broadcast, no mainnet.
- Forgetting a site is local bookkeeping: the protocol has no revocation of a
  watch-only descriptor.
- The signing history is this device's alone.
