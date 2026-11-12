# Use Templar Wallet with Templar Protocol

Templar Wallet is the signing wallet of **Templar Protocol**, a peer-to-peer
lending protocol on Liquid. Your keys never leave the wallet: the site builds
the loan transactions, the wallet shows you what each one does and signs only
after you confirm. The site broadcasts; the wallet never does.

Today the protocol runs on a test regtest; in beta it will run on a server of
ours; then Liquid mainnet. Use test coins only.

This guide is for people using the wallet with a protocol site. How the
wallet implements the connector — links, stored records, network checks,
testing without a site — is in [`PROTOCOL_CONNECTOR.md`](PROTOCOL_CONNECTOR.md).

---

## 1. Before you start

1. Install the wallet ([`INSTALL.md`](../../INSTALL.md)). On Windows use the
   **installer**: the portable zip does not register `templar://` links. On
   Linux, install the desktop entry as `INSTALL.md` describes.
2. First launch: set the **app password**. It encrypts wallet storage and is
   asked again before every signature.
3. Create or restore a wallet that can take part:
   - a **software wallet with Liquid enabled** — it can connect, sign loan
     steps and prove its key;
   - or a **Jade** with Liquid — it can connect and sign loan steps, but
     cannot sign the proof of key yet (see section 6).

   Watch-only and multisig wallets cannot take part.
4. Pick the Liquid network the site runs on: **Settings › Network & Sync ›
   Liquid network** (`Testnet` or `Regtest`), or the **Change network**
   button in **Settings › Templar Protocol**. Switching closes the open wallet:
   open it again and press **Sync**. If you get it wrong, the request screen
   tells you and offers the switch (section 7).
5. Fund the wallet with test L-BTC. On Liquid testnet use
   https://liquidtestnet.com/faucet or https://faucet.vulpem.com; on a regtest,
   the coins come from that regtest's node.

---

## 2. Connect the wallet to a site

1. On the site, click **Connect Templar Wallet**.
2. The wallet comes to the front on the *Connect wallet* screen. If storage is
   locked it asks for the app password first; if no wallet qualifies it says
   why.
3. Pick the wallet. The wallet always asks — it never picks one by itself. It
   lists first the wallet this device already connected to that site
   (*Connected to this site*), then the preferred and the open one, and shows
   why the others cannot take part.
4. Read what the site will receive:
   - a **watch-only** descriptor: the site can see this wallet's Liquid
     balance and history, it cannot spend;
   - the **loan key**, a separate account used only inside loan contracts;
   - a receive address and the wallet name.
5. Tick the statement, press **Share with …**, enter the app password.
6. *Wallet connected*. **Open in browser** takes you back to the site.

Nothing secret leaves the device at any point.

---

## 3. Sign a loan step

When a loan needs your signature the site shows a **Sign with Templar** link
(and a QR). Click it, or use **Sign now** on the Loans page (section 4).

The review screen has:

- a header with the action, the loan and your role;
- **What changes for this wallet**: the net change per asset, worked out by
  the wallet from the transaction itself;
- **Where the money goes**: every output, marked as this wallet, the loan
  escrow, someone else, or the fee;
- the site's own summary, to compare;
- **Technical details**, folded: the raw inputs and outputs, the request ids
  and the escrow contract.

Compare the wallet's reading with the site's summary. If they describe
different things, press **Cancel** and report it. Otherwise tick the
statement, press the sign button, enter the app password. *Signature sent*:
once every party has signed, the site broadcasts and the loan page shows the
transaction id.

If nothing in the transaction asks for this wallet's key, the button stays
disabled: the request was opened in the wrong wallet. **Change wallet** picks
another one.

---

## 4. The Loans page

The Loans page shows this wallet's loans as the connected site reports them:
one card per loan with its reference, your role, its state, what happens
next, the term as a time bar with the due estimate, and the amounts. Your own
offers follow, and the closed loans sit under an expander.

- It is **off by default**: switch it on in **Settings › Advanced › Loans**.
  It then appears in the menu (on a phone, as a tab of the bottom bar), at
  the top of Settings › Templar Protocol, and behind the Templar Protocol row
  of the desktop dashboard's Liquid panel.
- **Sign now** opens a pending signing request straight in the wallet.
- **Open on Templar Protocol** opens the loan in your browser, already signed
  in as this wallet. The link is single use and expires after two minutes.
- **Refresh** asks the site again; the page also refreshes after every
  signature you answer for that site.
- *Reconnect to see your loans*: the site no longer accepts this wallet's
  access, or the site was connected by Templar Wallet 0.1.0. Connect again
  from the site.
- When the site is offline or busy, the last answer stays on screen with the
  reason.

---

## 5. If the link does not open the wallet

- Open the wallet, go to **Settings › Templar Protocol › Open a request**,
  and paste the link from the site (right-click the button › copy link) or
  scan its QR.
- Windows: reinstall with the installer, not the zip.
- Linux: install the desktop entry ([`INSTALL.md`](../../INSTALL.md#linux)).

---

## 6. Proof of key

A site can ask the wallet to prove it holds the loan key — to let it back in
to its loans from a new browser, for example. The wallet signs a special
check transaction that can never be broadcast and never moves funds; its
screen shows the challenge text, the site, the expiry and *This signature
never moves funds*, and refuses anything that is not exactly that check.

A software wallet signs the proof during **Connect** when the site asks for
it, or from a separate request. A Jade cannot sign the proof yet: every proof
screen says so and suggests a software wallet; the site then falls back to an
ordinary signing request where it needs one.

---

## 7. Errors you may see

All of these are expected and safe: nothing was signed or sent.

| Message | Meaning |
|---|---|
| The site is on another network than this wallet | The card offers to switch this wallet to the site's network (or to the site's regtest chain) and fetches the request again. When the network is fixed for this run (`TEMPLAR_LIQUID_NETWORK`), it explains that instead. |
| *This request expired at …* | Go back to the site and start the step again. |
| *… rejected the answer (HTTP 4xx): …* | The site refused the signature (already signed, wrong request, expired). Retry from the site. |
| *Could not reach …* | The site is down or you are offline. Nothing was sent. |
| *Nothing here is for this wallet to sign* | Open the wallet that took part in the loan, or use **Change wallet**. |
| *Signing failed: …* | Report it with the request id shown on the review screen. |

---

## 8. Settings › Templar Protocol

| Card | What it does |
|---|---|
| Status | The network the wallet is ready for, and **Change network**. |
| Open a request | Paste a `templar://` link or scan its QR. |
| Connected sites | Every site that holds a watch-only view of one of your wallets. **Forget** removes the record from this device; the site keeps the watch-only view until you remove the wallet there. |
| Signing history | The requests this device answered, with their outcome. **Clear history**. |
| Preferred wallet | The wallet offered first. It never skips the confirmation: password and tick, every time. |
| How it works | A short summary, and a link to the connector guide. |

---

## 9. What to report

For every problem, please send:

- app version (Settings › About), OS, Liquid network;
- the site's **loan reference** and the **request id** shown on the review
  screen;
- a screenshot of the review screen;
- what you expected and what happened.

Especially useful: any case where the wallet's reading and the site's summary
disagree, any signature the site did not accept, and anything that felt
unclear. Where to file it: [`INSTALL.md`](../../INSTALL.md#reporting-a-problem).

---

## 10. Known limits

- The wallet shows the site's summary next to its own reading of the
  transaction; it does not reconcile the two automatically. That comparison
  is yours to make on the review screen.
- No broadcast from the wallet, no mainnet.
- Forgetting a site is local: the protocol has no way to revoke a watch-only
  view.
- The signing history belongs to this device; your loans live on the site and
  on the chain.
