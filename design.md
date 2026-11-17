# Design — Templar Wallet

The rules every screen is held to. Read this before changing a pixel. The
tokens named here live in `apps/gui/lib/theme/`; the widgets that carry them
live in `apps/gui/lib/shared/widgets/`.

## The direction

- **Product.** A Bitcoin and Liquid test-network wallet for people who hold
  coins under Miniscript policies — one key, several keys, a hardware device,
  an air-gapped signer — and who sign Templar Protocol loans with it.
- **Character.** Guarded, exact, a little ceremonial.
- **World.** A treasury's ledger room: iron, ink, and one red seal. The
  surfaces are iron-grey, the text is ink, and the only red in the room is
  wax.
- **Moments.** A few places carry the richness, and nothing else does:
  the balance and its chart (Dashboard, and Liquid's own smaller one with
  the split of its assets), the coins as physical notes kept in the cards
  of their addresses (UTXOs), the flow of a transaction from inputs to
  outputs (Send review, a fee bump's before and after), and the wallets as
  a register on the entry screen.
- **Signature.** The seal — the Templar cross in a ring (`SealMark`). It is
  stamped once per collected signature and nowhere else.

Test for any new element: *does it state a fact about the user's coins, or
does it help them reach one?* If neither, it does not ship.

## Surfaces

One neutral ramp, "iron": graphite with a breath of cool in it. Four steps
and never a fifth.

| Step | Token | Dark | Light | Used for |
| --- | --- | --- | --- | --- |
| Chrome | `AppScheme.chrome` | `#0E0F11` | `#EFEFF1` | sidebar, phone tab bar |
| Page | `AppScheme.canvas` | `#131416` | `#F5F5F6` | every page; also `well` |
| Card | `AppScheme.panel` | `#18191C` | `#FFFFFF` | cards, dialogs, sheets |
| Raised | `AppScheme.panelInset` | `#222327` | `#EDEEF0` | fields, glyph tiles, secondary buttons, the selected thing |

- **Depth is a step and a hairline.** `AppScheme.edge` (ink at 8%) around
  every card and between rows; `edgeStrong` for a control's outline. No
  shadow on dark. On light, cards carry `panelShadow` (a whisper). Only what
  floats over the page — dialog, sheet, menu, tooltip — takes `floatShadow`.
- **A recess is the page tone.** Inside a card, the track of a segmented
  control and the box an address is printed in use `AppScheme.well`.
- **Rows, not a card each.** Repeated things (assets, activity, settings,
  coins in a list) sit in ONE card, separated by hairlines inset past the
  icon column (`ListCard` / `ListRow`). One exception: the addresses that
  hold coins are a card each (`AddressCards`), because an address is a
  container of coins, not a row.
- **No gradients, no glass, no glow.** No blur, no translucent panel, no
  radial wash, no coloured shadow. The single gradient in the app is the
  area under a chart line, which encodes data. A coloured edge or a washed
  fill exists only where the colour is data (see "Colour as data").
- **Selection is a surface step**, not a colour, and the primary ink. On a
  card it is `AppScheme.selected` with an `edgeStrong` edge (a chip, a chosen
  option, a selected table row). On the page, the chrome or a well it is
  `AppScheme.thumb` (a nav row, a segment, the current tab) — the same raised
  step on dark, white on light, where those grounds are already grey.

## Ink

Three roles. Styles in `AppTypography` carry no colour; the caller picks one.

- `ink` — what is read: titles, figures, row titles, values.
- `inkSecondary` — what supports it: body copy, row subtitles, keys in a
  key/value row, icons.
- `inkFaint` — meta only: captions, units, timestamps, placeholders. It sits
  near 4.5:1, so never body text.

## The accent

Templar crimson `#C1121F` (`AppColors.accentDefault`, re-tinted per wallet;
read it as `AppScheme.accent`, with `onAccent` for ink on top of it).

- **One filled accent control per screen** — the thing the screen exists
  for (`PrimaryButton`). Everything beside it is neutral.
- Beyond that button the accent is a **mark**, never an area: the wax on
  the page. It is small, it is the user's, and it says one of four things.
  - *You are here.* A 3 px bar (`CurrentMark`) on the leading edge of the
    current destination — the sidebar row, the Settings section — and over
    the current tab on a phone; the current segment of a wizard's steps.
  - *You chose this.* The dot of the chosen radio, the tick of a checkbox,
    the check on a picked coin.
  - *You are typing here.* The caret and the text selection.
  - *This is yours.* The 6 px dot of the wallet's colour on its plate, the
    seal of a signature, this wallet's key on a key ring (`KeyRingMark`).
- In data it is two things more: the Dashboard chart's line, and the
  recipient of a transaction's flow.
- **It is also the colour of small glyphs** (`AppScheme.accentGlyph`): the
  icon of a secondary or ghost button, the icon of the current destination
  (sidebar row, Settings section, phone tab), an icon control under the
  pointer, a spinner, the arrow of a section's link. A glyph, never its
  label: the words beside it stay ink. `accentGlyph` is the accent itself
  where it stands 3:1 clear of the raised surface and is otherwise lifted
  (dark) or deepened (light) just far enough to — still the wallet's own
  colour, still short of the danger red.
- Two more places say *you chose this* with it: the 6 px dot of a chosen
  chip (the radio's dot again) and the short bar at the foot of the chosen
  segment of a segmented control.
- Every mark reads `AppScheme.accent` or `accentGlyph`, so the colour a
  wallet is given in Settings › Appearance moves all of them at once.
- **A mark is never the only sign.** The current row is also a surface step
  and the primary ink; a ticked box is also a tick; a chosen chip is also a
  surface step. Take the colour away and the screen still reads.
- **Never accent text, and never an accent ring.** Links and text actions
  are ink; a red outline around a chip or a field reads as an error.
- **A switch that is on is ink**, not the accent: a column of red switches
  reads as a column of alarms.
- **Focus is neutral** (`AppScheme.focus`). A red ring around a field reads
  as an error.
- `danger` is a different, brighter red and is only ever loss: delete, burn,
  failed, an invalid field. Never darken it toward the accent. A destructive
  control also carries a verb and, where there is room, an icon.
- `success` and `warning` carry meaning only, as a 6 px dot or as the ink of
  a short status. Never a filled pill, never a tinted panel. `success` is
  also the check a copy turns into, a step that landed, and the live edge
  of a signature and a broadcast; `pending` — orange, apart from the
  warning's amber — is a wait: the dot of a pending status and the
  breathing edge of its row (see "Motion").
- Chains own a hue for identification only — Bitcoin orange, Liquid teal —
  and it appears on the asset's glyph (`AssetLogo`), as a 6 px dot beside
  a network name, and as the line of Liquid's own balance chart. Never a
  title colour, a border, or a card fill.

## Colour as data

The chrome is iron. Colour comes back only where it states a fact the user
would otherwise have to read, and then it is a tool, not a decoration.

- **The palette** is `AppScheme`'s data hues — `hueSlate`, `hueTeal`,
  `hueBlue`, `hueViolet`, `hueGold`, `hueRose`, with the chain hues and the
  accent. No other colour, and none defined in a screen.
- **How it is applied**, always the same three ways: a washed fill
  (`AppScheme.wash(hue)`, a few percent over the card), a hairline in the
  hue (`AppScheme.washEdge(hue)`), and a short word or a glyph in the hue.
  Figures, addresses and titles stay ink. Never a saturated slab, never a
  gradient, never a glow.
- **Where**, and nowhere else:
  - *The flow of a transaction.* An input wears its chain's hue, the
    recipient the accent, change `flowChange` (it comes back), the fee
    `flowFee` (it is gone). The curve into or out of a box takes the box's
    hue.
  - *A coin's size tier.* Dust slate, small teal, big blue, huge violet,
    whale gold — on the note's edge, its engraving and its tier word; in a
    list, on the coin's miniature note and its share meter.
  - *A chart's slices.* `AppScheme.series`, in its fixed order; a chain's
    own coin keeps the chain hue.
  - *A wallet's own colour*, the one picked in Settings: the spine of its
    row on the entry screen, and the accent once it is open.
  - *An address's own colour.* Grey (`hueSlate`,
    `AddressLabelStore.greyHue`) until the user picks a hue with its label
    (`AddressLabelStore`, the tag hues of `AppScheme.series`; grey leads
    the picker and picking it is picking nothing), so colour on an address
    always means someone chose it. It is the fill and hairline of the
    address's label tag (`AddressTag`) and the square that leads the
    address (`AddressSwatch`) — in the head of its card wherever coins are
    kept under their address (the coin wall, a phone's coin list, Send's
    coin picker) and before it in the coin list. A mark, never an area: no
    band, edge or fill of the card is in it. The same address is the same
    colour on Receive, in the coin list, in Send's own-address picker — and
    two coins that share an address visibly share it.
  - *A fee bump.* Yellow (`AppScheme.boost`, the fee's amber brightened
    into a signal): the double bolt of "Speed up" (`DoubleBolt`), the bolt
    that marks a row whose fee was raised, and — the one filled use — the
    "Sped up" state that takes the button's place once it was, with a green
    tick (`SpedUpButton`). It is a state, not a second primary: it opens
    the detail, it does not act.
- A colour never stands alone: the word, the glyph or the position says the
  same thing, so the screen reads in greyscale.
- **What a thing is, is not a colour.** A payment, a loan, a swap and a peg
  are told apart in Activity by their glyph and their title; all four sit
  on the same iron tile.

## Type

IBM Plex Sans for the interface; IBM Plex Mono for what a user compares
character by character (addresses, txids, fingerprints, descriptors) and for
small meta. Both are vendored in `apps/gui/assets/fonts/`.

- **Two weights: 400 and 500.** Nothing is bold. Hierarchy is size and ink.
- **Sentence case everywhere.** No uppercase labels, no letter-spacing on
  anything under 40 px. `Wallet info`, `Total balance`, `Step 2 of 6`.
- **Use the tokens**; no `fontSize:` literal outside `app_typography.dart`.

| Token | Size / line | Use |
| --- | --- | --- |
| `balanceHero` | 44 / 48, 500 | the balance, once |
| `displayTitle` | 32 / 36, 500 | headline of a pre-wallet screen |
| `pageTitle` | 28 / 32, 500 | the page's name, once per screen |
| `balanceLarge` | 28 / 32, 500 | a card's lead figure |
| `balanceMedium`, `numericLarge` | 20 / 28, 500 | a secondary figure |
| `sectionTitle` | 16 / 24, 500 | a card or section title |
| `bodyLarge` | 16 / 24 | phone body, phone fields |
| `body` | 14 / 20 | body, row titles |
| `numeric` | 14 / 20, 500 | an amount in a row |
| `button` | 14 / 20, 500 | button labels (`buttonOf` on a phone: 16) |
| `caption`, `bodySmall`, `numericSmall` | 13 / 20 | row subtitles, help text |
| `label` | 13 / 20, 500 | a key, a control's label |
| `eyebrow` | 12 / 16, 500 | the label that names a block |
| `mono` / `monoSmall` | 13 / 20, 12 / 16 | hashes, addresses, meta |

- **Figures are tabular** (every `balance*` / `numeric*` token is) and use
  one format per screen. Sats are grouped (`1,734,567 sats`), BTC has eight
  decimals (`0.01734567 BTC`), fiat has two (`€1,183.20`). A balance is never
  abbreviated to `1.18k`: this is someone's money.
- **A figure is big and its unit is quiet**: the number in `ink`, the unit
  beside it one size down in `inkFaint`.
- A change says what it compares to: `+30.5% in 30 days`.
- Never two competing headlines on one screen.

## Space

Everything sits on a 4 px grid: `AppSpacing.xs` 4, `sm` 8, `md` 12, `lg` 16,
`xl` 24, `xxl` 32, `xxxl` 48, `huge` 64. No `+ 2`, no `- 1`, no literal 5, 7,
9, 10, 14, 18. (2 px is allowed for a nudge inside a small control.)

- Space shows grouping: less inside a group than between two of them.
  A label sits 8 above its block and 24–32 below the previous block.
- Same thing, same size: every row in a list one height, every card in a
  row one padding.
- Page padding `AppSpacing.pagePadding(context)` (32 desktop, 16 phone).
  Cards pad 20 (`cardPadding`), compact ones 16.
- A page's content column is capped (`contentMaxWidth` 1200) and a form or
  wizard step is one readable column (`formMaxWidth` 640), aligned the same
  way on every step.
- Icons sit in one column, labels start on one line, amounts align right in
  one column.

## Shape

Radius by size; nested radii add up (inner = outer − padding, floor 4).

| Token | px | Use |
| --- | --- | --- |
| `radiusXs` | 4 | tags, keycaps |
| `radiusSm` | 6 | chips, a segment inside its track |
| `radiusMd` | 8 | buttons, fields, rows |
| `radiusLg` | 12 | cards |
| `radiusXl` | 16 | the hero, dialogs, sheets |

Not everything is a pill: `999` is for a status dot and nothing else.

## Icons

Material Symbols, the **outlined** variant (`Icons.*_outlined`; the plain
name only when no outlined form exists). One size in chrome —
`AppSpacing.icon` (18), `iconSmall` (16) inside a small control, 22 in the
phone's tab bar — and the colour of its text role, normally `inkSecondary`.
An icon never gets a colour of its own, except a status dot, an asset's
glyph, and the accent's glyphs ("The accent": a neutral button's icon, the
current destination's, a control under the pointer). Drop the icon that
adds nothing: not every card title needs one.

Icons in lists are a `ListIconTile`: a `panelInset` tile with the glyph in
`inkSecondary`.

Templar Protocol's icon is the Templar cross (`CrossGlyph`): the bare mark,
no ring, drawn at an icon's size in the ink of its row like any other icon.
The ring is what makes it a seal; without it the cross says "Templar", not
"signed".

## Copy

- The title names the context: the page, the wallet, the period. No
  greeting, no subtitle that restates the title.
- Short labels. `Search`, not `Search by txid or note...`.
- No exclamation marks. `Copied`, not `Copied!`.
- Headlines, labels, buttons, captions and row subtitles end without a
  period. Only a paragraph of several sentences keeps its periods.
- No hype, no badge that is not a fact (`Easiest`, `Safest`, `New`).
- Never "this computer" on a phone, never "verified" for something the app
  has not verified, never a number the engine did not give us presented as
  if it had.
- The product name is "Templar Protocol"; its network status, when stated:
  "Today the protocol runs on a test regtest; in beta it will run on a
  server of ours; then Liquid mainnet."

## Controls

Desktop metrics; the phone's follow below.

- **Buttons** (`buttons.dart`) — 36 tall, radius 8, 16 side padding, label
  `button`, optional 16 px icon 8 from the label. `large: true` is the
  screen's lead pair and nothing else — Send and Receive on the Dashboard,
  Restore and New wallet on the entry screen: 48 tall, radius 12, label 16,
  an 18 px icon, and one minimum width so the pair is the same size.
  `PrimaryButton`: accent fill, `onAccent` ink. `SecondaryButton`:
  `panelInset` with a hairline. `GhostButton`: bare text, a hover surface.
  `DangerButton`: the secondary surface with danger ink and a danger
  hairline. The icon of a secondary or ghost button is drawn in
  `accentGlyph` — the label stays ink — and a secondary button's outline
  takes it under the pointer. Hover is a state layer, press is a 0.98
  scale, keyboard focus is a 2 px `focus` ring. Nothing glows.
- **Fields** — 44 tall, `panelInset` fill, hairline, radius 8; focus is a
  1.5 px `focus` border; error is `danger`. A field's label is an `eyebrow`
  above it, never floating inside.
- **Segmented control** (`SegmentedSwitch`, `ChainSwitch`) — a `well` track
  with a hairline, 2 px inner padding, radius 8; the chosen segment is
  `thumb`, radius 6, primary ink, with a 12 × 2 bar in the accent at its
  foot; the others `inkSecondary`. 32 tall.
- **Chip** (`ChoiceTile`) — 32 tall outline; selected is the raised surface
  with the accent's 6 px dot before its label.
- **Option card** (`SelectableOptionCard`, `ChoiceList`) — a card with a
  radio. Selected: `edgeStrong` border, the radio's dot in the accent.
  Never a filled slab.
- **Switch, checkbox, radio** — a switch that is on is the ink. A ticked
  checkbox is the accent with the tick in `onAccent`; a chosen radio is an
  ink ring around a dot in the accent.
- **Tag** (`QuietTag`, `TagChip`, `StatusBadge`, `AssetBadge`) — quiet text:
  `monoSmall` or `eyebrow` in `inkSecondary` on `panelInset`, radius 4, 2×6
  padding. A status is a 6 px dot and a word. No coloured fill, no outline
  in a colour — with one exception, the tag whose colour is data:
- **Address tag** (`AddressTag`) — the label of an address as a small
  rectangle: the address's own hue as a washed fill and a hairline, the
  label in `eyebrow` and the primary ink, radius 4. It is its own editor
  (the label prompt, which also picks the hue from six swatches). An
  address with no label shows a dashed "add label" tag in its place where
  labelling is the point (Receive), so the possibility is on screen.
- **Banner** (`InfoBanner`, `WarningBanner`, `DangerBanner`) — `panelInset`,
  radius 8, a 16 px icon in the status colour, text in `ink`. No tinted
  background.
- **Card** (`SectionCard`, `FormCard`, `SummaryCard`, `PlainCard`) — `panel`,
  hairline, radius 12, padding 20; the title is `sectionTitle`, with 16
  between it and the content. No tinted header strip. A card may lead its
  title with one mark that says what it is about — the key ring on a card
  about a multisig, the chain's glyph on a card about one chain (Wallet
  info's Bitcoin and Liquid descriptors) — never with an icon that only
  fills the space.
- **Dialog / sheet** (`AppDialog`, `PromptDialog`, `AppSheet`) — solid
  `panel`, radius 16, hairline, `floatShadow`, over `AppScheme.scrim`. Open
  them with `showAppDialog`: a phone gets a sheet where the desktop gets a
  dialog, with its actions stacked full width and the primary on top. A
  dialog is as wide as a transaction's detail (480 of content) unless it
  shows two things side by side (`maxWidth`); a list inside one scrolls in
  its own card instead of growing the window ("Use my own address"). Its
  edge can be live (`edge`, see "Motion").
- **Page header** (`PageHeader`) — the page's name in `pageTitle`, actions
  on the right, 24 below it. One optional line of meta under the title.
- **Steps** (`StepHeader`, `StepFlowScaffold`) — `Step 2 of 6` as an
  `eyebrow` with a row of thin segments under it (done in `ink`, the current
  one in the accent, the rest in `edgeStrong`), then the step's question as
  the title. No numbered circles. One column, the same width on every step.
- **Code box** (`CodeBox`, `CopyRow`, `DataWell`) — a `well` with a hairline,
  radius 8, `mono` in `ink`; copy and QR are icon buttons at its edge. Copy
  turns into a check for a moment.

## Navigation

- **Desktop**: a sidebar 264 wide on `chrome`. The wallet switcher at the
  top; rows 40 tall, radius 8, 2 apart, a 20 px icon and the label (15 px)
  on one line; group labels are `eyebrow` in `inkFaint`, 24 above and 8
  below. The current row is `thumb` with the primary ink and the
  `CurrentMark` on its leading edge. Sync state and the network sit at the
  foot. Three groups: Wallet, Liquid (Liquid assets, Loans, LiquiDEX, Peg —
  a loan is a Liquid covenant), System.
- **Phone**: a header (the wallet, the sync state) and a tab bar on `chrome`
  with every destination visible and labelled, the `CurrentMark` over the
  current one. No carousel. Send and Receive live on the Dashboard; Wallet
  info lives in Settings.

## Flows

- A step exists only where there is a real choice to make. A default almost
  nobody changes is a row on the page, not a screen of its own: Send is
  Compose (recipient, fee and coins on one page, coins chosen automatically
  until the user asks) and then Review.
- One question per step, in one column that keeps its width and position
  from the first step to the last.
- The last step says what is about to happen in the user's terms — amounts,
  addresses, fee, total — and carries the flow's one primary. Nothing is
  signed before the password gate.
- When an action is unavailable, the reason is written next to it. An
  action that can never apply is not drawn at all: a payment that came in
  is not ours to replace, so its row offers "Speed up" (a child pays, CPFP)
  and no "Cancel", and its speed-up offers no RBF.
- **A fee bump is one payment, not two.** The chain holds a second
  transaction for it — a CPFP child, a replacement — and Activity folds
  that into the row of the payment it belongs to (`foldFeeBumps`): one row,
  pending or confirmed, marked with the double bolt and the method, and
  one detail window that spells the bump out — what was done, what it
  cost, the other txid.
- After a send, the receipt offers the transaction two ways: in an
  explorer, and in this wallet's own Activity, its detail open.

## The moments

- **The balance and its chart.** The figure in `balanceHero`, its unit and
  its other denomination quiet beside it, the change with its period. The
  chart is the largest thing on the Dashboard: one line in the accent, the
  soft area under it, a muted grid, `monoSmall` axis labels, a dot on "now".
- **The notes** (UTXOs, desktop). Each coin is a banknote printed in its
  tier's hue: the paper is the card washed with it, the edge and the
  engraving — a fine inner frame and the Templar cross in guilloche: a
  soft silhouette under a nest of the cross's own outline, set in a braided
  ring like the seal on a note, its fine waves and scallops drawn from the
  coin's outpoint, so no two notes are alike and the same coin always looks
  the same — are the hue itself, and the tier is a word in it. The writing
  and the seal never share paper (`NoteFace`): the figures keep a column
  of their own on the left, wide enough for an eight-decimal amount set
  whole, and the seal stands at the note's right edge on what that column
  leaves — as large as that paper allows, so a longer note carries a
  larger seal, and nothing is printed over the amount or under it. The
  amount stays ink. Every note is one height (`kNoteHeight`) and its tier
  sets its length, five lengths for five denominations, so a row lines up
  and a coin worth more is a longer piece of paper. Paper is cut nearly
  square: radius 4. Frozen and pending are states, not colours: they drain the note to
  iron. A pending coin — a payment on its way in, the change of one on its
  way out, a consolidation waiting for its block — is that grey note with
  its loading drawn on it: a stroke running round its edge and a spinner
  beside "Pending", its three lines standing where a banknote's do. A note
  carries its label, the one the user wrote, and its two controls only
  under the pointer, the focus or a pick — a wall at rest is paper. The
  controls come over the end of the writing's lines, on a patch of the
  paper's own tone; never over the seal.
- **The address cards.** A coin sits on an address, and two coins on one
  address are tied together on-chain. So the wall keeps every note in the
  card of its address (`AddressTray`), the cards one under the other at
  the page's width (`AddressCards`, 12 px apart), the fullest first — never
  a grid of boxes. A card is the kit's card (panel, hairline, radius 12)
  and wears no colour of its own. Its head is one line: the address's
  swatch, its label as a tag, the address in mono (in ink when it has no
  label, quieter beside one), and on the far side how many coins it holds
  and what they add up to; a hairline; then the notes, wrapping, inset
  16. Label and colour are the ones Receive gives the address, and can be
  changed from the card; its two controls — label, copy — come with the
  pointer anywhere on the card, at the end of the head; the tag is its own
  editor. Wherever coins are picked — Send's coin picker, in its list and
  its notes alike — they sit in their address's card the same way.
- **The coin list.** The same coins as a ledger: each row leads with its
  note in miniature (`MiniNote`, the five lengths again), then the coin and
  its label, the address under *its* tag (or its colour's square), the tier
  with the share and its meter, the amount over its fiat value. A phone has
  no wall: it shows the same cards with the coins as rows
  (`AddressCoinGroup`), each head on two lines — the swatch, the label (or
  the address) over the address, the count and the sum — and the whole
  head opens the label prompt.
- **The flow** (Send review, and a fee bump's before and after):
  `TxFlowDiagram`. Inputs on the left, outputs and the fee on the right,
  joined by curves through one node. Each box is washed in its role's hue
  and its curve follows; the recipient is the accent. A fee bump is a
  **pair**: the transaction as it stands on the left, an arrow, and as it
  will be on the right — two compact diagrams drawn to one scale, so a box
  is as tall as what it holds is large, an output that shrank is a shorter
  box with the difference written on it, and one that is gone is a missing
  box. "Before" is drawn only where it can be worked out exactly from what
  the engine gave. The inspection of a transaction to co-sign tells the
  same story as a list, because there every outpoint and address is
  printed in full.
- **The register** (the entry screen). The wallets are the rows of one
  card, not a grid of tiles: a spine in the wallet's own colour, the glyph
  of its kind, its name over how its keys are held and when it was last
  opened, then its chains and its fingerprint in columns that line up down
  the rows. The screen exists to get back into a wallet, almost always the
  same one, so the cursor starts on the wallet opened last and Enter opens
  it; the arrows and the pointer move the cursor, and 1–9 open a row
  outright. The rows keep the order of their kinds, so a digit means the
  same wallet every day; the keys are printed as keycaps at the foot.

## The seal

`SealMark` is the Templar cross in a ring. Stamped (accent fill, cross in
`onAccent`) means *this key has signed*; empty (hairline ring, faint cross)
means *this signature is still missing*. It appears wherever signatures are
counted — a multisig's m-of-n, a PSBT being passed around, the moment a
transaction is signed — and nowhere else. It is not a logo, not a bullet,
not a success icon for anything that is not a signature. Where a block is
about a multisig and nothing has been signed, the mark is the key ring
(`KeyRingMark`), not the seal.

## Motion

- One curve, `AppMotion.settle`, and it does not overshoot. Durations:
  `instant` 120 (hover, press), `quick` 160 (toggles, selection), `standard`
  220 (menus, expansion), `emphasized` 360 (things that enter), `grand` 500
  (the chart's first draw).
- A hover is a surface change; a press is a 0.98 scale; a menu fades and
  rises a few pixels; a changed figure tweens.
- Nothing loops unless it is live (a sync in progress, a pending
  transaction). Nothing bounces, floats or parallaxes.
- **The live edge** (`LiveEdge`) is how a thing in motion says so: an
  outline painted over its own border, never around it. Three states.
  *Breathing* — it waits on the network: the row of a pending transaction
  or operation in Activity, in `pending` orange, swelling and fading
  slowly. *Working* — the app is doing something to it now: a stroke runs
  round the dialog while a transaction is signed or broadcast (in
  `success`), round the flow on Send's review while it is sent, round a
  coin that is on its way (in the secondary ink). *Done* — it landed: the
  outline draws itself closed, once, and stays — the signed transaction's
  dialog, the "Sent" receipt.
- Animate colour, opacity and transform. Never width, height or position.
- Small rewards, each tied to something true: the chart draws itself and
  lands a dot on "now"; a copy turns into a green check; the seal stamps
  and the dialog's edge closes in green when a signature lands; amounts
  echo their other unit under the field while you type.
- All of it is skipped under `AppMotion.reduced` / `prefers-reduced-motion`.

## The phone

Same icons, same palette, same type — a wallet, not two wallets. What
changes is geometry.

- Buttons are 54 dp tall (44 when `dense`), radius 12, label 16 px.
- Fields are filled `panelInset`, radius 12, at least 56 dp, no border at
  rest, a 1.5 px `focus` ring. An `eyebrow` label sits above the field.
- Body text is 15–16 px. Nothing is under 11 px.
- Every touch target is at least 48 dp (`AppLayout.minTouchTarget`).
- Sheets instead of dialogs, one column, stacked cards.
- Every phone layout is behind `AppLayout.isPhone(context)`.

## Never

- A fifth surface tone, a gradient, a glow, a blur.
- Accent as decoration, or a second filled accent control on a screen.
- Accent text, or an accent ring around a control.
- A colour that is not data, or data shown by colour alone.
- An uppercase label, a bold weight, a `fontSize:` literal.
- A colour defined outside `AppColors` / `AppScheme`.
- A control under 48 dp on touch.
- A tab bar taller than a fifth of the screen.
- Copy that says "this computer" on a phone, or "verified" for something the
  app has not verified.
- A number the engine did not give us, presented as if it had.
