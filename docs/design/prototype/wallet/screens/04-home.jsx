// 04 — Home dashboard: portfolio hero, asset cards, recent activity.
(() => {
const { TX_TIMELINE } = window.WDATA;

const CHIPS = [
  { ticker: "BTC",   amt: "0.01106552" },
  { ticker: "L-BTC", amt: "0.00299860" },
  { ticker: "USDt",  amt: "25.00" },
  { ticker: "DEPIX", amt: "50.00" },
];

const CARDS = [
  { ticker: "BTC",   fiat: "≈ $720.14", badge: <Pill tone="ok" dot>synced</Pill>,      amt: "0.01106552", sub: "12 UTXOs · 1 unconfirmed", goTo: "utxo" },
  { ticker: "L-BTC", fiat: "≈ $194.91", badge: <Pill tone="ok" dot>synced</Pill>,      amt: "0.00299860", sub: "4 UTXOs · all confirmed",  goTo: "liquid" },
  { ticker: "USDt",  fiat: "≈ $25.00",  badge: <Pill tone="outline">third-party</Pill>, amt: "25.00",      sub: "third-party · 1 UTXO",     goTo: "liquid" },
  { ticker: "DEPIX", fiat: "—",         badge: <Pill tone="warn">your asset</Pill>,     amt: "50.00",      sub: "reissuance token held",    goTo: "liquid" },
];

const RECENT = TX_TIMELINE.flatMap(d => d.items).slice(0, 4);
const AGO = ["2 min", "12 min", "1 h", "1 d"];

const TICKER = (
  <React.Fragment>
    <span><b>BTC</b> $65,012 <span className="up">▲ 0.8%</span></span>
    <span><b>L-BTC</b> 1.0000 ₿ <span className="up">peg ok</span></span>
    <span><b>USDt</b> $1.00</span>
    <span><b>DEPIX</b> your asset · reissuable</span>
    <span><b>block</b> 3,041,142</span>
    <span><b>mempool</b> 3 sat/vB</span>
    <span><b>liquid</b> 0.1 sat/vB</span>
    <span className="down">testnet · coins worthless</span>
  </React.Fragment>
);

// deterministic particle field for the hero (position, duration, delay, drift)
const DOTS = Array.from({ length: 12 }, (_, i) => ({
  left: `${8 + ((i * 83) % 88)}%`,
  bottom: `${6 + ((i * 37) % 40)}%`,
  "--fd": `${7 + (i % 5) * 1.7}s`,
  "--fdel": `${(i * 0.9) % 6}s`,
  "--fx": `${((i % 2 ? 1 : -1) * (6 + (i * 5) % 22))}px`,
}));

function HomeScreen({ wallet, go }) {
  return (
    <React.Fragment>
      <Topbar
        title={wallet.name}
        sub={`${wallet.kind} · ${wallet.network}`}
        right={
          <React.Fragment>
            <Btn variant="primary" onClick={() => go("send")}>↑ Send</Btn>
            <Btn onClick={() => go("receive")}>↓ Receive</Btn>
          </React.Fragment>
        }
      />
      <div className="canvas">
        <div className="fx-marquee">
          <div className="track">{TICKER}{TICKER}</div>
        </div>

        <div className="hero">
          <span className="fx-particles">
            {DOTS.map((s, i) => <i key={i} style={s} />)}
          </span>
          <span className="label">Portfolio · {wallet.network}</span>
          <div className="hero-num">$915.05</div>
          <div className="hero-chains">
            {CHIPS.map(c => (
              <span key={c.ticker} className="hero-chip">
                <AssetGlyph ticker={c.ticker} size={20} />
                {c.amt}
              </span>
            ))}
          </div>
          <div className="row" style={{justifyContent: "center", marginTop: 18}}>
            <Btn variant="primary" onClick={() => go("send")}>↑ Send</Btn>
            <Btn onClick={() => go("receive")}>↓ Receive</Btn>
            <Btn variant="ghost" onClick={() => go("history")}>see activity →</Btn>
          </div>
        </div>

        <div className="g4">
          {CARDS.map(c => (
            <div key={c.ticker} className="asset-card" onClick={() => go(c.goTo)}>
              <div className="top">
                <span className="row" style={{gap: 8}}>
                  <AssetGlyph ticker={c.ticker} size={26} />
                  <span className="col">
                    <strong>{c.ticker}</strong>
                    <span className="dim mono" style={{fontSize: 10.5}}>{c.fiat}</span>
                  </span>
                </span>
                {c.badge}
              </div>
              <div className="value-lg mono" style={{marginTop: 12}}>{c.amt}</div>
              <div className="dim" style={{fontSize: 12, marginTop: 3}}>{c.sub}</div>
            </div>
          ))}
        </div>

        <SectionH right={<Btn variant="ghost" size="sm" onClick={() => go("history")}>see all →</Btn>}>
          Recent activity
        </SectionH>
        <Card tabular>
          <table className="table">
            <tbody>
              {RECENT.map((tx, i) => (
                <tr key={tx.id + i} onClick={() => go("history")} style={{cursor: "pointer"}}>
                  <td style={{width: 42}}><AssetGlyph ticker={tx.asset === "LBTC" ? "L-BTC" : tx.asset} size={26} /></td>
                  <td className="mono" style={{color: "var(--ink-2)"}}>{tx.id}…</td>
                  <td className="dim">{tx.note || "—"}</td>
                  <td className={`num ${tx.dir === "in" ? "amount-in" : "amount-out"}`}>{tx.amt}</td>
                  <td className="num dim" style={{width: 80}}>{AGO[i]}</td>
                  <td className="dim" style={{width: 28}}>›</td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
      </div>
    </React.Fragment>
  );
}

(window.WSCREENS = window.WSCREENS || {}).home = HomeScreen;
})();
