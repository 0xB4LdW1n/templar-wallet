// 08 — UTXOs: banknote coin control. Select, tag, freeze, consolidate, feed the send flow.
(() => {
const { UTXOS_BTC } = window.WDATA;

const UTXOS_LQ = [
  { op: "9bd1c0fe:0", addr: "tlq1q…gj3a", path: "0/6", amt: 0.00100000, conf: 2,   tag: "swap in", state: "conf", denom: 100000, asset: "L-BTC" },
  { op: "3e8c22a1:1", addr: "tlq1q…7xw2", path: "0/5", amt: 0.00150000, conf: 40,  tag: null,      state: "conf", denom: 150000, asset: "L-BTC" },
  { op: "c4197bd0:0", addr: "tlq1q…p9r4", path: "0/4", amt: 0.00030000, conf: 210, tag: null,      state: "conf", denom: 30000,  asset: "L-BTC" },
  { op: "77aa41c9:2", addr: "tlq1q…k2m8", path: "0/3", amt: 0.00019860, conf: 999, tag: "change",  state: "conf", denom: 20000,  asset: "L-BTC" },
  { op: "f211d8f8:1", addr: "tlq1q…m8z2", path: "0/2", amt: 25.00,      conf: 6,   tag: null,      state: "conf", denom: 25,     asset: "USDt" },
  { op: "a09b2243:0", addr: "tlq1q…4tlr", path: "0/1", amt: 50.00,      conf: 142, tag: "issuance",state: "conf", denom: 50,     asset: "DEPIX" },
];

function sizeOf(u, chain) {
  const d = chain === "BTC" ? u.denom : u.denom * (u.asset === "L-BTC" ? 1 : 4000);
  if (d >= 250000) return { cls: "size-xl", col: 6, row: 2 };
  if (d >= 150000) return { cls: "size-lg", col: 4, row: 2 };
  if (d >= 50000)  return { cls: "size-md", col: 3, row: 1 };
  if (d >= 20000)  return { cls: "size-sm", col: 3, row: 1 };
  return { cls: "size-xs", col: 2, row: 1 };
}

const stamp = (u) => u.denom >= 1000 ? Math.round(u.denom / 1000) + " k" : u.denom;

function UtxoScreen({ wallet, go }) {
  const [chain, setChain] = useState("BTC");
  const [btc, setBtc] = useState(UTXOS_BTC.map(u => ({ ...u })));
  const [lq, setLq] = useState(UTXOS_LQ.map(u => ({ ...u })));
  const [sel, setSel] = useState([]);          // array of op ids
  const [state, setState] = useState("all states");
  const [q, setQ] = useState("");
  const [view, setView] = useState("banknotes");
  const [tagging, setTagging] = useState(false);
  const [tagText, setTagText] = useState("");
  const [consolidate, setConsolidate] = useState(false);

  const utxos = chain === "BTC" ? btc : lq;
  const setUtxos = chain === "BTC" ? setBtc : setLq;

  const shown = utxos.filter(u => {
    if (state === "frozen" && u.state !== "frozen") return false;
    if (state === "dust" && u.state !== "dust") return false;
    if (state === "confirmed" && !(u.conf >= 6 && u.state !== "frozen")) return false;
    if (state === "unconfirmed" && u.conf >= 6) return false;
    if (state === "tagged" && !u.tag) return false;
    if (q.trim() && !((u.op + " " + u.addr + " " + (u.tag || "")).toLowerCase().includes(q.trim().toLowerCase()))) return false;
    return true;
  });

  const selected = utxos.filter(u => sel.includes(u.op));
  const sum = selected.reduce((s, u) => s + u.amt, 0);
  const total = utxos.filter(u => u.asset == null || u.asset === "L-BTC").reduce((s, u) => s + u.amt, 0);
  const frozenCt = utxos.filter(u => u.state === "frozen").length;
  const dustCt = utxos.filter(u => u.state === "dust").length;

  const toggle = (op) => setSel(s => s.includes(op) ? s.filter(x => x !== op) : [...s, op]);
  const clear = () => { setSel([]); setTagging(false); };

  const applyTag = () => {
    setUtxos(list => list.map(u => sel.includes(u.op) ? { ...u, tag: tagText.trim() || null } : u));
    setTagging(false); setTagText("");
    window.toast?.(tagText.trim() ? `Tagged ${sel.length} UTXO${sel.length > 1 ? "s" : ""} “${tagText.trim()}”` : "Tags cleared");
  };
  const freeze = () => {
    const anyActive = selected.some(u => u.state !== "frozen");
    setUtxos(list => list.map(u => sel.includes(u.op) ? { ...u, state: anyActive ? "frozen" : (u.amt < 0.00002 ? "dust" : "conf") } : u));
    window.toast?.(anyActive ? "Frozen — excluded from coin selection" : "Unfrozen");
  };
  const sendSelected = () => {
    window.FLOW.selectedUtxos = selected.map(u => ({ op: u.op, amt: u.amt }));
    window.FLOW.sendAsset = chain === "BTC" ? "BTC" : (selected[0]?.asset || "L-BTC");
    clear();
    go("send");
  };

  return (
    <React.Fragment>
      <Topbar
        title="UTXOs"
        sub="Always-on coin control — tag, freeze, consolidate"
        right={
          <Seg
            value={chain}
            onChange={c => { setChain(c); setSel([]); }}
            options={[
              { id: "BTC", label: "● BTC", count: btc.length, tone: "btc" },
              { id: "LQ", label: "● Liquid", count: lq.length, tone: "lq" },
            ]}
          />
        }
      />
      <div className="canvas">
        <div className="between" style={{flexWrap: "wrap", gap: 10}}>
          <div className="row" style={{flexWrap: "wrap"}}>
            <select className="input" style={{width: 140, height: 30}} value={state} onChange={e => setState(e.target.value)}>
              <option>all states</option><option>confirmed</option><option>unconfirmed</option><option>frozen</option><option>dust</option><option>tagged</option>
            </select>
            <input className="input" style={{width: 230, height: 30}} placeholder="search outpoint / address / tag…" value={q} onChange={e => setQ(e.target.value)} />
            <span className="dim" style={{fontSize: 12}}>area ∝ amount · click a note to select</span>
          </div>
          <Seg value={view} onChange={setView} options={[{ id: "banknotes", label: "Banknotes" }, { id: "table", label: "Table" }]} />
        </div>

        <div className="row" style={{gap: 28, margin: "16px 0 14px"}}>
          <div className="col">
            <span className="label" style={{margin: 0}}>Total · {chain === "BTC" ? "BTC" : "L-BTC"}</span>
            <span className="value-md mono">{total.toFixed(8)} {chain === "BTC" ? "₿" : ""}</span>
          </div>
          <div className="col"><span className="label" style={{margin: 0}}>Outputs</span><span className="value-md mono">{utxos.length}</span></div>
          <div className="col"><span className="label" style={{margin: 0}}>Frozen</span><span className="value-md mono">{frozenCt}</span></div>
          <div className="col"><span className="label" style={{margin: 0}}>Dust</span><span className="value-md mono">{dustCt}</span></div>
        </div>

        {view === "banknotes" && (
          <div className="bn-grid">
            {shown.map(u => {
              const s = sizeOf(u, chain);
              const isSel = sel.includes(u.op);
              return (
                <div
                  key={u.op}
                  className={`banknote ${s.cls} ${chain === "LQ" ? "lq" : ""} ${u.state === "frozen" ? "frozen" : ""} ${isSel ? "selected" : ""}`}
                  style={{gridColumn: `span ${s.col}`, gridRow: `span ${s.row}`}}
                  onClick={() => toggle(u.op)}
                >
                  <div className="bn-top">
                    <span>TEMPLAR · {chain === "BTC" ? "BTC" : (u.asset || "LQ")}</span>
                    <span>№ {u.op.toUpperCase()}</span>
                  </div>
                  <div className="bn-amt">
                    {u.asset && u.asset !== "L-BTC" ? u.amt.toFixed(2) : u.amt.toFixed(8)}{" "}
                    {chain === "BTC" ? "₿" : u.asset === "USDt" ? "$" : u.asset === "DEPIX" ? "D" : "₿"}
                  </div>
                  <div className="bn-bot">
                    <span>{u.path}</span>
                    {u.tag && <span className="pill" style={{height: 16, fontSize: 9}}>{u.tag}</span>}
                    {u.state === "dust" && !u.tag && <span className="pill warn" style={{height: 16, fontSize: 9}}>dust</span>}
                  </div>
                  <span className="denom-stamp">{stamp(u)}</span>
                </div>
              );
            })}
          </div>
        )}

        {view === "table" && (
          <Card tabular>
            <table className="table">
              <thead>
                <tr><th></th><th>Outpoint</th><th>Address</th><th>Path</th><th style={{textAlign: "right"}}>Amount</th><th>Confs</th><th>Tag / state</th></tr>
              </thead>
              <tbody>
                {shown.map(u => (
                  <tr key={u.op} className={sel.includes(u.op) ? "active" : ""} onClick={() => toggle(u.op)} style={{cursor: "pointer"}}>
                    <td style={{width: 34}}><input type="checkbox" readOnly checked={sel.includes(u.op)} /></td>
                    <td className="mono">{u.op}</td>
                    <td className="mono">{u.addr}</td>
                    <td className="mono dim">{u.path}</td>
                    <td className="num">{u.asset && u.asset !== "L-BTC" ? u.amt.toFixed(2) + " " + u.asset : u.amt.toFixed(8)}</td>
                    <td className="mono dim">{u.conf >= 999 ? "999+" : u.conf}</td>
                    <td>
                      {u.state === "frozen" ? <Pill tone="outline">frozen</Pill>
                        : u.state === "dust" ? <Pill tone="warn">dust</Pill>
                        : u.tag ? <Pill>{u.tag}</Pill> : <span className="dim">—</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Card>
        )}

        {sel.length > 0 && (
          <div className="action-bar">
            <div className="col" style={{gap: 2}}>
              <strong>{sel.length} selected · {sum >= 1 ? sum.toFixed(2) : sum.toFixed(8)} {chain === "BTC" ? "₿" : ""}</strong>
              <span className="dim" style={{fontSize: 12}}>enough to spend ≈ {(sum * 0.99).toFixed(8)} after fee</span>
            </div>
            <span className="spacer" />
            {tagging ? (
              <React.Fragment>
                <input className="input" style={{width: 180, height: 32}} autoFocus placeholder="tag name…" value={tagText}
                  onChange={e => setTagText(e.target.value)}
                  onKeyDown={e => { if (e.key === "Enter") applyTag(); if (e.key === "Escape") setTagging(false); }} />
                <Btn variant="primary" onClick={applyTag}>apply</Btn>
                <Btn variant="ghost" onClick={() => setTagging(false)}>cancel</Btn>
              </React.Fragment>
            ) : (
              <React.Fragment>
                <Btn variant="primary" onClick={sendSelected}>↑ Send selected</Btn>
                <Btn onClick={() => { setTagText(""); setTagging(true); }}>+ Tag…</Btn>
                <Btn onClick={freeze}>❄ {selected.some(u => u.state !== "frozen") ? "Freeze" : "Unfreeze"}</Btn>
                <Btn onClick={() => setConsolidate(true)} disabled={sel.length < 2} style={sel.length < 2 ? {opacity: 0.5, pointerEvents: "none"} : null}>⇈ Consolidate</Btn>
                <Btn variant="ghost" onClick={clear}>clear</Btn>
              </React.Fragment>
            )}
          </div>
        )}
      </div>

      {consolidate && (
        <Modal
          title="Consolidate UTXOs"
          onClose={() => setConsolidate(false)}
          foot={
            <React.Fragment>
              <Btn onClick={() => setConsolidate(false)}>cancel</Btn>
              <Btn variant="primary" onClick={() => {
                setConsolidate(false);
                window.FLOW.selectedUtxos = selected.map(u => ({ op: u.op, amt: u.amt }));
                window.FLOW.sendAsset = chain === "BTC" ? "BTC" : "L-BTC";
                clear();
                go("send");
              }}>Build consolidation tx →</Btn>
            </React.Fragment>
          }
        >
          <p className="sub" style={{marginBottom: 12}}>
            Merges <strong style={{color: "var(--ink)"}}>{sel.length} inputs</strong> ({sum.toFixed(8)}) into a single output back to your own wallet.
          </p>
          <Card flat tight>
            <div className="between"><span className="dim">New output</span><span className="mono">1 × {(sum * 0.99).toFixed(8)}</span></div>
            <div className="between" style={{marginTop: 6}}><span className="dim">Est. fee</span><span className="mono">~{Math.round(sel.length * 68 * 3.4)} sats</span></div>
            <div className="between" style={{marginTop: 6}}><span className="dim">Privacy note</span><span style={{fontSize: 12.5}}>links all selected coins together</span></div>
          </Card>
        </Modal>
      )}
    </React.Fragment>
  );
}

(window.WSCREENS = window.WSCREENS || {}).utxo = UtxoScreen;
})();
