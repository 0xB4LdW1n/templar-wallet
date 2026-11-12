// Shared sample data — easy to swap when wiring up real backend.
// Numbers are intentionally exact so tnum lines up visually.

const WALLETS = [
  {
    id: "daily",
    name: "Daily",
    kind: "Software",
    network: "Testnet",
    btc: 0.01106552,
    lbtc: 0.00299860,
    usdt: 25.00,
    depix: 50.00,
    utxos: 12,
    lastSync: "2 min ago",
    txCount: 142,
    fingerprint: "73c5a9f1",
    derivation: "m/84'/1'/0'",
    script: "wpkh",
  },
  {
    id: "treasury",
    name: "Treasury 2-of-3",
    kind: "Multisig",
    network: "Testnet",
    btc: 0.84410000,
    lbtc: 0,
    utxos: 8,
    lastSync: "1 h ago",
    txCount: 8,
    fingerprint: "—",
    derivation: "m/48'/1'/0'/2'",
    script: "wsh(sortedmulti)",
  },
  {
    id: "cold",
    name: "Cold air-gap",
    kind: "Air-gap QR",
    network: "Testnet",
    watchOnly: true,
    utxos: 4,
    lastSync: "3 d ago",
    txCount: 4,
  },
  {
    id: "issuer",
    name: "Issuer",
    kind: "Software",
    network: "Testnet",
    lcad: 12500000,
    utxos: 6,
    lastSync: "12 min ago",
    txCount: 31,
    issuedAssets: 2,
  },
];

const UTXOS_BTC = [
  { op: "17a4fe5a:0", addr: "tb1q…lvk5", path: "0/14",  amt: 0.00050000, conf: 6,   tag: null,    state: "conf",   denom: 50000 },
  { op: "2c197e62:1", addr: "tb1q…9aaf", path: "1/2",   amt: 0.00020765, conf: 6,   tag: null,    state: "conf",   denom: 20000 },
  { op: "7576e128:0", addr: "tb1q…82xs", path: "0/13",  amt: 0.00025000, conf: 142, tag: null,    state: "conf",   denom: 25000 },
  { op: "fabba1bd:2", addr: "tb1q…tlr3", path: "0/11",  amt: 0.00050153, conf: 999, tag: "frozen",state: "frozen", denom: 50000 },
  { op: "f211d8f8:0", addr: "tb1q…m8z2", path: "0/8",   amt: 0.00010141, conf: 999, tag: "rent",  state: "conf",   denom: 10000 },
  { op: "f86d92ff:1", addr: "tb1q…6yzs", path: "0/7",   amt: 0.00001011, conf: 999, tag: null,    state: "dust",   denom: 1000 },
  { op: "9cf9ab82:0", addr: "tb1q…2pqv", path: "1/0",   amt: 0.00008223, conf: 999, tag: "change",state: "conf",   denom: 8200 },
  { op: "c8f768e1:3", addr: "tb1q…aa7w", path: "0/4",   amt: 0.00188869, conf: 999, tag: null,    state: "conf",   denom: 200000 },
  { op: "a3c89071:0", addr: "tb1q…uvk9", path: "0/3",   addr2: "tb1q…uvk9", amt: 0.00352390, conf: 999, tag: null, state: "conf", denom: 350000 },
  { op: "b29c0d77:2", addr: "tb1q…h2es", path: "0/2",   amt: 0.00250000, conf: 999, tag: "savings", state: "conf", denom: 250000 },
  { op: "d100eebc:1", addr: "tb1q…41hg", path: "0/1",   amt: 0.00100000, conf: 999, tag: null,    state: "conf", denom: 100000 },
  { op: "ea551290:0", addr: "tb1q…3fmd", path: "0/0",   amt: 0.00050000, conf: 999, tag: null,    state: "conf", denom: 50000 },
];

const TX_TIMELINE = [
  { day: "Today · 16 May 2026", items: [
    { id: "17a4fe5a", chain: "BTC", dir: "in",  amt: "+0.00005000",      asset: "BTC",  to: "tb1q…lvk5", note: "rent",      time: "14:32", conf: 6,   value: "≈ $3.25" },
    { id: "f211d8f8", chain: "LQ", dir: "out", amt: "−25.00",           asset: "USDt", to: "tlq1q…m8z2", note: "",          time: "13:18", conf: 0,   value: "≈ $25.00" },
  ]},
  { day: "Yesterday · 15 May 2026", items: [
    { id: "2c197e62", chain: "BTC", dir: "out", amt: "−0.00020765",      asset: "BTC",  to: "tb1q…9aaf", note: "",          time: "18:42", conf: 6,   value: "≈ $13.50" },
    { id: "9bd1c0fe", chain: "LQ", dir: "in",  amt: "+0.00100000",      asset: "LBTC", to: "tlq1q…gj3a", note: "swap in",   time: "12:09", conf: 2,   value: "≈ $65.00" },
  ]},
  { day: "10 May 2026", items: [
    { id: "a09b2243", chain: "LQ", dir: "in",  amt: "+50.00",           asset: "DEPIX",to: "tlq1q…4tlr", note: "issuance · reissuance kept", time: "09:54", conf: 142, value: "—" },
    { id: "7576e128", chain: "BTC", dir: "in",  amt: "+0.00025000",      asset: "BTC",  to: "tb1q…82xs", note: "",          time: "08:11", conf: 999, value: "≈ $16.25" },
  ]},
  { day: "02 May 2026", items: [
    { id: "fabba1bd", chain: "BTC", dir: "out", amt: "−0.00050153",      asset: "BTC",  to: "tb1q…tlr3", note: "coffee",    time: "12:30", conf: 999, value: "≈ $32.60" },
    { id: "f6211d8f", chain: "BTC", dir: "in",  amt: "+0.00010141",      asset: "BTC",  to: "tb1q…lvk5", note: "",          time: "10:01", conf: 999, value: "≈ $6.60" },
  ]},
];

const ASSETS = [
  { id: "lbtc",  ticker: "L-BTC", name: "Liquid Bitcoin",  type: "native",       balance: 0.00299860, utxos: 4, value: "≈ $194.91", assetId: "144c6541…2dd9c5a8" },
  { id: "usdt",  ticker: "USDt",  name: "Tether USD",      type: "third-party",  balance: 25.00,      utxos: 1, value: "≈ $25.00",  assetId: "ce091c98…b3742c4" },
  { id: "depix", ticker: "DEPIX", name: "DePix",           type: "your asset",   balance: 50.00,      utxos: 1, value: "—",         assetId: "a09b2243…b9c1f10", mine: true, reissuable: true },
];

const COSIGNERS = [
  { name: "Cold · Coldcard",  fp: "e1f4d2a0", role: "cosigner", signed: true,  glyph: "▢" },
  { name: "Laptop · this",    fp: "73c5a9f1", role: "you",      signed: false, glyph: "▭" },
  { name: "Phone · Jade",     fp: "9a37b18c", role: "cosigner", signed: false, glyph: "◇" },
];

// Main nav (top-level screens). Setup screens (onboarding, wallet-type, wallet-picker)
// are reachable from the "Change wallet" footer in the sidebar, not from the main nav.
const NAV = [
  { group: "Wallet", items: [
    { id: "home",      n: "04", t: "Home",        i: "⌂" },
    { id: "send",      n: "05", t: "Send",        i: "↑" },
    { id: "receive",   n: "06", t: "Receive",     i: "↓" },
    { id: "history",   n: "07", t: "History",     i: "≡" },
    { id: "utxo",      n: "08", t: "UTXOs",       i: "⊞" },
    { id: "info",      n: "09", t: "Wallet info", i: "ⓘ" },
  ]},
  { group: "Multisig", items: [
    { id: "multisig",  n: "10", t: "PSBT inspector", i: "⌘" },
  ]},
  { group: "Liquid", items: [
    { id: "liquid",    n: "11", t: "Liquid",         i: "◊" },
    { id: "assets",    n: "12", t: "Issue · Reissue · Burn", i: "○" },
  ]},
  { group: "System", items: [
    { id: "settings",  n: "13", t: "Settings",       i: "⚙" },
  ]},
];

// Setup screens — surfaced via "Change wallet" footer + still routable.
const CHANGE_WALLET = [
  { id: "wallet-picker", t: "Switch wallet",    i: "⇆" },
  { id: "onboarding",    t: "Create new",       i: "+" },
  { id: "wallet-type",   t: "Restore / import", i: "↺" },
];

window.WDATA = { WALLETS, UTXOS_BTC, TX_TIMELINE, ASSETS, COSIGNERS, NAV, CHANGE_WALLET };

// Cross-screen handoff (send → utxo picker → back, liquid → asset op preselect, …).
// Screens read + clear on mount. Plain mutable object is enough for a mockup.
window.FLOW = {};
