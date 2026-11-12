# Local order book

The localhost LiquiDEX / atomic-swap order book is one of the services of
Templar Protocol and lives in the `templar-protocol` repository
(`services/orderbook`, guide in `docs/guides/orderbook.md`). It is no longer
built from this repository.

The wallet only needs to know where a book is. With nothing set it talks to
the service's default localhost address; these variables, read by the engine
(`templarlib`), point it elsewhere:

| Variable | What it overrides |
|---|---|
| `TEMPLAR_SWAP_BOOK_URL` | the book feed (`…/api/book`) |
| `TEMPLAR_SWAP_MARKETS_URL` | the unified market feed (`…/api/markets`) |
| `TEMPLAR_SWAP_ADMIN_URL` | where a maker's proposal is published (`…/api/admin/offers`) |

The active Liquid network is always sent with each request, so testnet and
regtest books stay apart. Start the service from a `templar-protocol`
checkout, then launch the wallet.
