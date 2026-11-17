# Join a test server

A Templar **test server** ("testlab") is a controlled test environment: its
own Bitcoin regtest and Liquid regtest chains, a faucet, and a LiquiDEX order
book wired to those chains. The wallet joins one with a single setting, its
URL; the wallet reads everything else (chains, servers, order book) from the
server's `GET /api/config`.

Test networks only. Coins on a test server's chains have no value, and the
operator can reset the chains at any time.

## Join

1. **Settings › Network › Nodes and explorers › Test server.**
2. Enter the URL the operator gave you, for example `http://127.0.0.1:8096`
   for a lab running on your own computer, and choose **Join**.
3. The wallet asks first. Joining **closes the open wallet**: confirm, then
   open the wallet again from the wallet list and sync it.

From then on:

- Liquid runs on the test server's regtest (`el1…` confidential addresses)
  and Bitcoin on its Bitcoin regtest (`bcrt1…` addresses). A strip at the top
  of every screen reads `Regtest — Bitcoin and Liquid of test server
  <name>`, and the Dashboard says `Regtest`.
- The Test server card lists what the lab provides: its faucet and the
  coins it pays, its order book, its lending site and its peg.
- The swap market uses the test server's order book; its header names the
  test server and the network.
- Transactions on a regtest have no public block explorer, so the wallet
  offers no explorer links there.
- **Nodes**, under the Test server card, lists the servers in use (Bitcoin,
  Liquid, order book) and where each one comes from: the test server, an
  environment variable, or the built-in default.

Your keys and wallets do not change. The same wallet shows its test-server
coins while joined, and its public-testnet coins after you leave.

## Get coins

From the wallet itself: the Dashboard shows a **Test coins** card with
every coin the test server's faucet pays (BTC, L-BTC and the lab's tokens,
such as USDt), one button each; Receive shows the same button for the
coin on screen. The faucet pays a fresh address of this wallet; the coins
show after the lab's next block (about 30 seconds), when the wallet syncs
by itself. A refusal is explained — a limit says when to try again.

## Tokens and the order book

Issue a token from Liquid assets › Issue. On a test server there is no
domain to prove: the token is announced to the lab's order book, so other
wallets see its name; the result says whether the book took it (a ticker
already used there is refused, with a retry). Amounts are typed in the
token's own units (`100.00` of a two-decimal token). A token named by the
order book rather than by your wallet shows its short asset id beside the
name. The BTC ↔ Liquid cross-chain routes exist only on Liquid testnet and
are not shown on a test server.

## Peg between the lab's chains

With **Settings › Advanced › Peg** on, the Peg tab (beside Assets and
LiquiDEX) runs the test server's native peg — the real Elements peg between
its Bitcoin regtest and its Liquid regtest. Software wallets with both
chains only.

**Peg-in (BTC → L-BTC).**

1. Enter the amount and choose **Start peg-in**. The order shows a Bitcoin
   deposit address (and how long it stays valid, as a Liquid block height).
2. Pay it: **Fund from this wallet** shows what will be signed, then asks
   for the app password. You can also pay the address from any other wallet.
3. Wait for the deposit's Bitcoin confirmations (the order counts them,
   `1 of 2`, …). The list re-reads the chains every 30 seconds while an
   order is open, or when you press refresh.
4. When the order says **Ready to claim**, choose **Claim** (confirmation and
   password again). The claim's small Liquid fee comes out of the deposit.
   The order completes once the claim is in a Liquid block.

**Peg-out (L-BTC → BTC).** Start a peg-out to one of your Bitcoin addresses,
then **Fund from this wallet**: the wallet signs the Liquid peg-out (there is
no address to pay by hand). After its Liquid confirmations the test server's
federation pays the BTC, up to the server's peg-out maximum; the order
completes once that payment is in a Bitcoin block.

On **Liquid testnet** (a test server joined, Liquid switched to testnet) the
provider is **SideSwap**, a third party's custodial swap service — not a
peg. The app says so before an order is opened: you send coins to SideSwap,
it pays you on the other chain, and your receive address is sent to it.
SideSwap's testnet currently refuses to open orders; the app shows its
answer.

An order that says **Expired** must never be paid. Orders of another network
and those made with older versions of the app against the retired simulated
provider (labelled **Simulated**; no coins moved for them) are folded under
**Older orders**, below the active network's.

If funding is refused for lack of coins, the order says how much is missing
and offers **Get test BTC** (or **Get test L-BTC**) right there.

## Loans

While joined, Loans (with no site connected yet) and Settings › Templar
Protocol offer **Open the test server's lending site**. Connect from the
site's own **Connect Templar Wallet**; the loans then show in the wallet.

## When the test chain is reset

The operator can reset the lab's chains. The wallet then still points at the
old chain. It finds out:

- the first time you open the swap market in a session, and
- whenever you choose **Check now** on the Test server card.

When the server answers with a new chain, the wallet says **The test chain was
reset** and offers **Re-join**. Re-joining closes the open wallet again; the
regtest balances and history are synced from scratch on the next sync. Keys
and the wallet list are not touched.

If the server does not answer a check, the wallet says so and keeps using
the servers it stored when you joined. Try again later.

## Leave

**Leave** on the Test server card. Liquid and Bitcoin go back to the public
testnet, the order book and servers to their defaults, and the open wallet is
closed: open it again and sync. The test server's regtest data is dropped from
this device.

## When the network is fixed by an environment variable

If the app was started with `TEMPLAR_LIQUID_NETWORK` set, the Liquid network
is fixed for that session and the Test server card says so. You can still
join, but the test server's regtest chains apply only once the variable is
unset and the app restarted.

## The terminal client

The same methods are available from the `templar` terminal client:

```bash
templar call set_test_server -p '{"url": "http://127.0.0.1:8096"}'
templar call get_test_server -p '{"check": true}'
templar call clear_test_server
```

The method contract is templarlib's `docs/API.md` (`get_test_server`,
`set_test_server`, `clear_test_server`).
