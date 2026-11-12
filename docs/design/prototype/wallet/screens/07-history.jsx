// 07 — Activity: unified BTC + Liquid history with live filters, timeline/table views, tx detail.
(() => {
const { TX_TIMELINE } = window.WDATA;

const confPill = (tx) =>
  tx.conf === 0
    ? <Pill tone="warn" dot>unconfirmed</Pill>
    : <span className="dim mono" style={{fontSize: 11.5}}>{tx.conf >= 999 ? "999+" : tx.conf}{tx.conf >= 142 && tx.conf < 999 ? "+" : ""} confirmations</span>;

function matches(tx, chain, asset, q) {
  if (chain !== "all" && tx.chain !== chain) return false;
  if (asset !== "all assets" && tx.asset !== asset) return false;
  if (q.trim()) {
    const hay = (tx.id + " " + tx.to + " " + tx.note + " " + tx.asset).toLowerCase();
    if (!hay.includes(q.trim().toLowerCase())) return false;
  }
  return true;
}

function TxDetail({ tx, onClose }) {
  return (
    <Modal title={`Transaction ${tx.id}…`} onClose={onClose} wide
      foot={<Btn variant="primary" onClick={onClose}>close</Btn>}>
      <div className="row" style={{flexWrap: "wrap", marginBottom: 14}}>
        {chainPill(tx.chain)}
        {confPill(tx)}
        {tx.note && <Pill tone="violet">{tx.note}</Pill>}
      </div>
      <Card flat tight>
        <div className="between">
          <span className="dim">{tx.dir === "in" ? "Received" : "Sent"}</span>
          <span className={`value-md mono ${tx.dir === "in" ? "amount-in" : ""}`}>{tx.amt} {tx.asset}</span>
        </div>
        <div className="between" style={{marginTop: 6}}>
          <span className="dim">{tx.dir === "in" ? "To (mine)" : "To"}</span>
          <span className="mono">{tx.to}</span>
        </div>
        <div className="between" style={{marginTop: 6}}>
          <span className="dim">Value</span>
          <span className="mono">{tx.value}</span>
        </div>
        <div className="between" style={{marginTop: 6}}>
          <span className="dim">Time</span>
          <span className="mono">{tx.time}</span>
        </div>
      </Card>
      <div style={{marginTop: 12}}>
        <span className="label" style={{margin: "0 0 6px"}}>txid</span>
        <CodeBlock value={tx.id + "3c1b7a02de915646ce77b1a4f2ddc90ab34cf1e6d8290b44aa10fe92c447"} />
      </div>
      <p className="help">Inputs, outputs and fee breakdown open in the PSBT inspector for multisig wallets.</p>
    </Modal>
  );
}

function HistoryScreen({ wallet }) {
  const [chain, setChain] = useState("all");
  const [asset, setAsset] = useState("all assets");
  const [time, setTime] = useState("all time");
  const [q, setQ] = useState("");
  const [view, setView] = useState("timeline");
  const [detail, setDetail] = useState(null);

  // mock "now" is 16 May 2026 — "this week" keeps today + yesterday, wider ranges keep all
  const timeCut = time === "this week" ? 2 : TX_TIMELINE.length;
  const days = TX_TIMELINE
    .slice(0, timeCut)
    .map(d => ({ ...d, items: d.items.filter(tx => matches(tx, chain, asset, q)) }))
    .filter(d => d.items.length > 0);
  const flat = days.flatMap(d => d.items.map(tx => ({ ...tx, day: d.day })));

  const exportCsv = () => {
    const rows = [["day", "txid", "chain", "direction", "amount", "asset", "counterparty", "note", "time", "confirmations"]];
    flat.forEach(tx => rows.push([tx.day, tx.id, tx.chain, tx.dir, tx.amt, tx.asset, tx.to, tx.note, tx.time, tx.conf]));
    download("templar-activity.csv", rows.map(r => r.map(c => `"${String(c).replace(/"/g, '""')}"`).join(",")).join("\n"), "text/csv");
    window.toast?.("CSV exported");
  };

  return (
    <React.Fragment>
      <Topbar
        title="Activity"
        sub="All transactions on both chains"
        right={
          <React.Fragment>
            <input className="input" style={{width: 230, height: 32}} placeholder="search id / address / note…" value={q} onChange={e => setQ(e.target.value)} />
            <Btn onClick={exportCsv}>⇩ Export CSV</Btn>
          </React.Fragment>
        }
      />
      <div className="canvas">
        <div className="between" style={{flexWrap: "wrap", gap: 10}}>
          <div className="row" style={{flexWrap: "wrap"}}>
            <Seg
              value={chain}
              onChange={setChain}
              options={[
                { id: "all", label: "All" },
                { id: "BTC", label: "● BTC", tone: "btc" },
                { id: "LQ", label: "● Liquid", tone: "lq" },
              ]}
            />
            <select className="input" style={{width: 130, height: 30}} value={asset} onChange={e => setAsset(e.target.value)}>
              <option>all assets</option><option>BTC</option><option>LBTC</option><option>USDt</option><option>DEPIX</option>
            </select>
            <select className="input" style={{width: 120, height: 30}} value={time} onChange={e => setTime(e.target.value)}>
              <option>all time</option><option>this week</option><option>this month</option><option>this year</option>
            </select>
          </div>
          <Seg value={view} onChange={setView} options={[{ id: "timeline", label: "Timeline" }, { id: "table", label: "Table" }]} />
        </div>

        {days.length === 0 && (
          <Card flat style={{marginTop: 22, textAlign: "center", color: "var(--ink-3)"}}>
            Nothing matches these filters.
          </Card>
        )}

        {view === "timeline" && days.map(d => (
          <React.Fragment key={d.day}>
            <div className="tl-day">{d.day}</div>
            {d.items.map((tx, i) => (
              <div key={tx.id + i} className={`tl-row ${tx.dir}`} onClick={() => setDetail(tx)} style={{cursor: "pointer"}}>
                <div className="marker">{tx.dir === "in" ? "↓" : "↑"}</div>
                <div className="col" style={{gap: 3, minWidth: 0}}>
                  <div style={{whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis"}}>
                    <strong>{tx.dir === "in" ? "Received" : "Sent"} {tx.amt} {tx.asset}</strong>
                    <span className="dim"> {tx.dir === "in" ? "from" : "to"} </span>
                    <span className="mono">{tx.to}</span>
                    {tx.note && <span className="dim"> · {tx.note}</span>}
                  </div>
                  <div className="row" style={{fontSize: 12, color: "var(--ink-3)"}}>
                    <span className="mono">{tx.id}</span>
                    <span>· {tx.time} ·</span>
                    {tx.conf === 0 ? <span style={{color: "var(--warn-ink)"}}>unconfirmed</span> : <span>{tx.conf >= 999 ? "999+" : tx.conf} confirmations</span>}
                    <span>·</span>
                    {chainPill(tx.chain)}
                  </div>
                </div>
                <div className="col right" style={{gap: 3}}>
                  <span className="mono dim" style={{fontSize: 12.5}}>{tx.value}</span>
                  <span className="dim" style={{fontSize: 12}}>view ›</span>
                </div>
              </div>
            ))}
          </React.Fragment>
        ))}

        {view === "table" && days.length > 0 && (
          <Card tabular style={{marginTop: 18}}>
            <table className="table">
              <thead>
                <tr><th></th><th>txid</th><th>asset</th><th>counterparty</th><th>note</th><th style={{textAlign: "right"}}>amount</th><th>state</th><th>time</th></tr>
              </thead>
              <tbody>
                {flat.map((tx, i) => (
                  <tr key={tx.id + i} onClick={() => setDetail(tx)} style={{cursor: "pointer"}}>
                    <td style={{width: 30}}>{tx.dir === "in" ? "↓" : "↑"}</td>
                    <td className="mono">{tx.id}</td>
                    <td>{chainPill(tx.chain)}</td>
                    <td className="mono">{tx.to}</td>
                    <td className="dim">{tx.note || "—"}</td>
                    <td className={`num ${tx.dir === "in" ? "amount-in" : ""}`}>{tx.amt} {tx.asset}</td>
                    <td>{tx.conf === 0 ? <Pill tone="warn">pending</Pill> : <Pill tone="ok">{tx.conf >= 999 ? "999+" : tx.conf}</Pill>}</td>
                    <td className="dim mono">{tx.time}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Card>
        )}
      </div>

      {detail && <TxDetail tx={detail} onClose={() => setDetail(null)} />}
    </React.Fragment>
  );
}

(window.WSCREENS = window.WSCREENS || {}).history = HistoryScreen;
})();
