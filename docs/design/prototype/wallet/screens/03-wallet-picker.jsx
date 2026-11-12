// 03 — Open a wallet: searchable card grid of local wallets.
(() => {
const { WALLETS } = window.WDATA;

const kindTag = (w) =>
  w.kind === "Multisig" ? <Pill tone="lq">2-of-3</Pill> :
  w.kind === "Air-gap QR" ? <Pill tone="outline">watch</Pill> :
  <Pill>SW</Pill>;

const kindGlyph = (w) =>
  w.kind === "Multisig" ? "⌘" : w.kind === "Air-gap QR" ? "▢" : "▭";

function bigLine(w) {
  if (w.watchOnly) return <span className="value-lg mono">watch only</span>;
  if (w.lcad != null) return <span className="value-lg mono">12.5M LCAD</span>;
  return <span className="value-lg mono">{w.btc.toFixed(5)} ₿</span>;
}

function WalletPickerScreen({ go, setWalletId }) {
  const [q, setQ] = useState("");
  const list = WALLETS.filter(w =>
    (w.name + " " + w.kind + " " + w.network).toLowerCase().includes(q.trim().toLowerCase())
  );

  const open = (w) => { setWalletId(w.id); go("home"); window.toast?.(`Opened ${w.name}`); };

  return (
    <React.Fragment>
      <Topbar
        title="Open a wallet"
        sub={`${WALLETS.length} wallets on this machine`}
        right={
          <React.Fragment>
            <input
              className="input"
              style={{width: 220, height: 32}}
              placeholder="search wallets…"
              value={q}
              onChange={e => setQ(e.target.value)}
            />
            <Btn onClick={() => go("wallet-type")}>↺ Restore</Btn>
            <Btn variant="primary" onClick={() => go("onboarding")}>+ New wallet</Btn>
          </React.Fragment>
        }
      />
      <div className="canvas">
        <h1 className="h1">Wallets</h1>
        <p className="sub">Pick one to open. Hover any card to see sync state and tx count.</p>

        <div className="picker-grid" style={{marginTop: 22}}>
          {list.map(w => (
            <div key={w.id} className="picker-card" onClick={() => open(w)}>
              <div className="between">
                <span className="row" style={{gap: 8, minWidth: 0}}>
                  <span className="mono dim">{kindGlyph(w)}</span>
                  <strong style={{whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis"}}>{w.name}</strong>
                </span>
                {kindTag(w)}
              </div>
              <div style={{marginTop: 10}}>
                {bigLine(w)}
                <div className="dim mono" style={{fontSize: 12, marginTop: 4, minHeight: 16}}>
                  {w.lbtc ? `+ ${w.lbtc.toFixed(8)} L-BTC` : w.issuedAssets ? `${w.issuedAssets} issued assets` : " "}
                </div>
              </div>
              <hr style={{margin: "auto 0 10px", marginTop: "auto"}} />
              <div className="between mono dim" style={{fontSize: 11.5}}>
                <span>sync {w.lastSync}</span>
                <span>{w.txCount} tx</span>
              </div>
            </div>
          ))}

          <div className="picker-card add" onClick={() => go("onboarding")}>
            <div style={{textAlign: "center"}}>
              <div style={{fontSize: 22, marginBottom: 6}}>+</div>
              <div style={{fontWeight: 500, color: "var(--ink-2)"}}>Add a new wallet</div>
              <div className="dim" style={{fontSize: 12, marginTop: 3}}>create · restore · import</div>
            </div>
          </div>
        </div>

        {list.length === 0 && (
          <Card flat style={{marginTop: 16, textAlign: "center", color: "var(--ink-3)"}}>
            No wallet matches “{q}”.
          </Card>
        )}

        <p className="help" style={{marginTop: 22}}>
          Tip — last-opened wallet auto-opens on launch. Press <span className="kbd">⌘K</span> anywhere to switch.
        </p>
      </div>
    </React.Fragment>
  );
}

(window.WSCREENS = window.WSCREENS || {})["wallet-picker"] = WalletPickerScreen;
})();
