# Join a test server

A Templar **test server** ("testlab") is a controlled test environment: its
own Bitcoin regtest and Liquid regtest chains, a faucet, and a LiquiDEX order
book wired to those chains. The wallet joins one with a single setting, its
URL; the wallet reads everything else (chains, servers, order book) from the
server's `GET /api/config`.

Test networks only. Coins on a test server's chains have no value, and the
operator can reset the chains at any time.

## Join

1. **Settings › Network & Sync › Test server.** On a phone: Settings, then
   **Nodes & explorers**.
2. Enter the URL the operator gave you, for example `http://127.0.0.1:8096`
   for a lab running on your own computer, and choose **Join**.
3. The wallet asks first. Joining **closes the open wallet**: confirm, then
   open the wallet again from the wallet list and sync it.

From then on:

- Liquid runs on the test server's regtest (`el1…` confidential addresses)
  and Bitcoin on its Bitcoin regtest (`bcrt1…` addresses). A strip at the top
  of every screen reads `REGTEST — test server <name>`, and the Dashboard
  says `REGTEST`.
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

Use the test server's own faucet: open the server's URL in a browser (the
tester page) and paste a receive address from the wallet (Receive, Bitcoin
or Liquid). Then sync the wallet.

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
