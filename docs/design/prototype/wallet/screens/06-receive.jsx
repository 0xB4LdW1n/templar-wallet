// 06 — Receive: fresh address + BIP21 QR, previous address table.
(() => {

const TABS = [
  { ticker: "BTC",   prefix: "tb1q",  scheme: "bitcoin" },
  { ticker: "L-BTC", prefix: "tlq1q", scheme: "liquidnetwork" },
  { ticker: "USDt",  prefix: "tlq1q", scheme: "liquidnetwork" },
  { ticker: "DEPIX", prefix: "tlq1q", scheme: "liquidnetwork" },
];

const POOL = ["x2gpwj3a4kx5cnqf3xglf8sgu", "m94ltd7vze6u2c0hq5rfy8a3w", "t7kfhs29dwq4vxn8pj3mc6z5e", "p3vn8re51ukqm2ysd97hgw4xc", "k6dw2fa87tzpq4hxv3ncj9m5r"];

const PREV = [
  { idx: 13, addr: "tb1q…9aaf", label: "invoice #41", recv: "0.00020000" },
  { idx: 12, addr: "tb1q…82xs", label: "—",           recv: "0.00050000" },
  { idx: 11, addr: "tb1q…tlr3", label: "rent",        recv: "—" },
  { idx: 10, addr: "tb1q…m8z2", label: "—",           recv: "0.00010141" },
];

function ReceiveScreen({ wallet }) {
  const [ticker, setTicker] = useState("BTC");
  const [idx, setIdx] = useState(14);
  const [amount, setAmount] = useState("");
  const [label, setLabel] = useState("");
  const [advanced, setAdvanced] = useState(false);

  const tab = TABS.find(t => t.ticker === ticker);
  const address = tab.prefix + POOL[idx % POOL.length];
  const uri = tab.scheme + ":" + address
    + (amount || label ? "?" : "")
    + (amount ? "amount=" + amount : "")
    + (amount && label ? "&" : "")
    + (label ? "label=" + encodeURIComponent(label) : "");
  const isLiquid = ticker !== "BTC";
  const path = isLiquid ? `m/84'/1'/0'/0/${idx} · blinded` : `m/84'/1'/0'/0/${idx} · wpkh`;

  return (
    <React.Fragment>
      <Topbar
        title="Receive"
        sub="One-time address · BIP21 with amount & label"
        right={<Pill tone="outline">{wallet.name} · {wallet.network}</Pill>}
      />
      <div className="canvas">
        <h1 className="h1">Receive</h1>
        <p className="sub">A fresh address every time. Old ones stay reachable below.</p>

        <div style={{marginTop: 18}}>
          <AssetTabs assets={TABS} value={ticker} onChange={t => { setTicker(t); setIdx(14); }} />
        </div>

        <div style={{display: "grid", gridTemplateColumns: "360px 1fr", gap: 18, marginTop: 18, alignItems: "start"}}>
          {/* left — QR card */}
          <Card style={{textAlign: "center"}}>
            <div className="qr" style={{margin: "8px auto 14px"}} />
            <div className="mono" style={{fontSize: 12.5, wordBreak: "break-all"}}>{address}</div>
            <div className="row" style={{justifyContent: "center", marginTop: 12}}>
              <CopyBtn value={address} label="Copy address" />
              <Btn size="sm" onClick={() => { download(`templar-receive-${idx}.txt`, uri, "text/plain"); window.toast?.("QR payload saved"); }}>↓ Save QR</Btn>
              <Btn size="sm" onClick={() => { setIdx(i => i + 1); window.toast?.("New address derived"); }}>↻ New address</Btn>
            </div>
            <div className="dim mono" style={{fontSize: 11, marginTop: 12}}>idx {idx} · {path}</div>
          </Card>

          {/* right — options */}
          <Card>
            <Field label="Amount" optional hint="Embeds into the BIP21 URI in the QR.">
              <input className="input mono" placeholder="0.00050000" value={amount} onChange={e => setAmount(e.target.value)} />
            </Field>
            <Field label="Label" optional hint="Stored locally only — never written on-chain.">
              <input className="input" placeholder="e.g. invoice #42" value={label} onChange={e => setLabel(e.target.value)} />
            </Field>
            <label className="check" style={{marginTop: 12}}>
              <input type="checkbox" checked={advanced} onChange={e => setAdvanced(e.target.checked)} />
              Advanced
            </label>
            {advanced && (
              <div style={{marginTop: 12}}>
                <span className="label" style={{margin: "0 0 6px"}}>Payment URI</span>
                <CodeBlock value={uri} />
                {isLiquid && (
                  <p className="help">
                    Liquid addresses are confidential — the blinding key is embedded, so amounts stay private on-chain.
                  </p>
                )}
              </div>
            )}
          </Card>
        </div>

        <SectionH>Previous addresses</SectionH>
        <Card tabular>
          <table className="table">
            <thead>
              <tr><th>idx</th><th>Address</th><th>Label</th><th style={{textAlign: "right"}}>Received</th><th></th></tr>
            </thead>
            <tbody>
              {PREV.map(r => (
                <tr key={r.idx}>
                  <td className="mono dim">{r.idx}</td>
                  <td className="mono">{r.addr}</td>
                  <td className="dim">{r.label}</td>
                  <td className="num">{r.recv}</td>
                  <td style={{textAlign: "right", width: 90}}><CopyBtn value={r.addr} label="copy" /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
      </div>
    </React.Fragment>
  );
}

(window.WSCREENS = window.WSCREENS || {}).receive = ReceiveScreen;
})();
