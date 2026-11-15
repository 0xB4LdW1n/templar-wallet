# Local order book

The LiquiDEX / atomic-swap order book is one of the services of Templar
Protocol and lives in the `templar-protocol` repository (`services/orderbook`,
guide in `docs/guides/orderbook.md`). It is not built from this repository.

The wallet only needs to know where a book is. The engine (`templarlib`)
picks it, in this order:

1. **Environment variables**, one route each (below).
2. **A joined test server**: its config names the book
   ([TEST_SERVER.md](TEST_SERVER.md)). This is the usual way to test swaps:
   join the test server and its book comes with it.
3. **The default**, the service on `http://127.0.0.1:3210`.

| Variable | What it overrides |
|---|---|
| `TEMPLAR_SWAP_BOOK_URL` | the book feed (`…/api/book`) |
| `TEMPLAR_SWAP_MARKETS_URL` | the unified market feed (`…/api/markets`) |
| `TEMPLAR_SWAP_ADMIN_URL` | where a maker's proposal is published; by default the book's public `POST /api/offers` (set it only for an old book that publishes through its admin route) |

The URLs in use, and where each came from, are shown in **Settings › Network &
Sync › Nodes** (`get_test_server`, `active.orderbook`). The active Liquid
network is sent with every request, so testnet and regtest books stay apart.

## The admin dashboard

The book's admin dashboard is a separate, password-protected page at the
book's address. The swap market links to it (**Order book admin**) only when
the book runs on this computer (`127.0.0.1`, `localhost`); for a book on
another machine the link is hidden, since that admin is its operator's.

## When publishing fails

The book checks every offer against the chain before storing it. When it
refuses, the wallet says why:

| The wallet says | What happened |
|---|---|
| Try again in N seconds / minutes | too many offers were published from here (rate limit) |
| cannot check the chain right now … nothing was stored | the book could not reach its chain; try again later |
| Already published | the same offer is already in the book |
| does not take public offers on this network | the book has public publishing off for this network |
| the book's own reason | the offer was refused (coin spent, wrong network, too large, …) |
| Cannot reach the order book | the book is down or the URL is wrong; check the test server setting |
