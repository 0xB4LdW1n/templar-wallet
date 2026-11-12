// 05 — Send: one form for BTC, L-BTC, or any Liquid asset. Review & sign builds a fake PSBT.
(() => {

const SENDABLE = [
  { ticker: "BTC",   chain: "BTC", prefix: "tb1",  balance: 0.01106552, unit: "BTC",   dp: 8 },
  { ticker: "L-BTC", chain: "LQ",  prefix: "tlq1", balance: 0.00299860, unit: "L-BTC", dp: 8 },
  { ticker: "USDt",  chain: "LQ",  prefix: "tlq1", balance: 25.00,      unit: "USDt",  dp: 2 },
  { ticker: "DEPIX", chain: "LQ",  prefix: "tlq1", balance: 50.00,      unit: "DEPIX", dp: 2 },
];

const FEES = {
  BTC: [
    { id: "slow",   label: "Slow",   rate: 1.0, eta: "~12h confirmation", sats: 142 },
    { id: "normal", label: "Normal", rate: 3.4, eta: "~1h confirmation",  sats: 483 },
    { id: "fast",   label: "Fast",   rate: 8.2, eta: "~10 min",           sats: 1164 },
  ],
  LQ: [
    { id: "slow",   label: "Low",    rate: 0.1, eta: "~2 min",  sats: 26 },
    { id: "normal", label: "Normal", rate: 0.15, eta: "~1 min", sats: 39 },
    { id: "fast",   label: "High",   rate: 0.3, eta: "next block", sats: 77 },
  ],
};

const fmt = (n, dp) => n.toLocaleString("en-US", { minimumFractionDigits: dp, maximumFractionDigits: dp });

function SendScreen({ wallet, go }) {
  const [ticker, setTicker] = useState(window.FLOW.sendAsset || "BTC");
  const [addr, setAddr] = useState("");
  const [amount, setAmount] = useState("0.00050000");
  const [unit, setUnit] = useState("BTC");
  const [note, setNote] = useState("");
  const [advanced, setAdvanced] = useState(false);
  const [opReturn, setOpReturn] = useState("");
  const [fee, setFee] = useState("normal");
  const [coinMode, setCoinMode] = useState(window.FLOW.selectedUtxos ? "manual" : "auto");
  const [manualCoins, setManualCoins] = useState(window.FLOW.selectedUtxos || null);
  const [review, setReview] = useState(false);
  const [phase, setPhase] = useState("form"); // form | signing | sent

  useEffect(() => {
    // consume the handoff so it doesn't stick on next visit
    if (window.FLOW.selectedUtxos) window.toast?.(`${window.FLOW.selectedUtxos.length} UTXOs attached from coin control`);
    window.FLOW.selectedUtxos = null;
    window.FLOW.sendAsset = null;
  }, []);

  const asset = SENDABLE.find(a => a.ticker === ticker);
  const feeOpt = FEES[asset.chain].find(f => f.id === fee);
  const isBtc = asset.chain === "BTC";

  const addrOk = addr.trim() === "" ? null : addr.trim().startsWith(asset.prefix) && addr.trim().length > 8;
  const amtNum = parseFloat(unit === "sats" ? String((parseFloat(amount) || 0) / 1e8) : amount) || 0;
  const amtOk = amount.trim() === "" ? null : amtNum > 0 && amtNum <= asset.balance;
  const canReview = addrOk && amtOk;

  const feeCoin = feeOpt.sats / 1e8;
  const changeAddr = isBtc ? "tb1q…9aaf" : "tlq1q…2pqv";
  const short = addr.trim() ? addr.trim().slice(0, 6) + "…" + addr.trim().slice(-4) : "—";

  const sign = () => {
    setPhase("signing");
    setTimeout(() => setPhase("sent"), 1800);
  };
  const resetAll = () => {
    setReview(false); setPhase("form"); setAddr(""); setNote(""); setOpReturn(""); setManualCoins(null); setCoinMode("auto");
  };

  return (
    <React.Fragment>
      <Topbar
        title="Send"
        sub="One form — BTC, L-BTC, or any Liquid asset"
        right={<Pill tone="outline">{wallet.name} · {wallet.network}</Pill>}
      />
      <div className="canvas">
        <h1 className="h1">Send</h1>
        <p className="sub">Pick the asset, paste an address, and pick a fee. We'll build the {isBtc ? "PSBT" : "PSET"}.</p>

        <div className="rowg4" style={{marginTop: 18, alignItems: "center"}}>
          <AssetTabs assets={SENDABLE} value={ticker} onChange={t => { setTicker(t); setUnit(SENDABLE.find(a => a.ticker === t).unit); }} />
          <span className="dim" style={{fontSize: 12.5}}>address & fee fields auto-validate for the chain.</span>
        </div>

        <div style={{display: "grid", gridTemplateColumns: "1fr 380px", gap: 18, marginTop: 18, alignItems: "start"}}>
          {/* left — form */}
          <Card>
            <Field label="Recipient address">
              <input
                className={`input lg mono ${addrOk === null ? "" : addrOk ? "input-ok" : "input-err"}`}
                placeholder={`${asset.prefix}q… or paste / scan QR`}
                value={addr}
                onChange={e => setAddr(e.target.value)}
              />
            </Field>
            <div className="row" style={{marginTop: 8}}>
              <Btn size="sm" onClick={() => window.toast?.("Camera not wired in mockup", "▣")}>▣ scan</Btn>
              <Btn size="sm" onClick={async () => {
                try { const t = await navigator.clipboard.readText(); if (t) setAddr(t.trim()); } catch (e) { setAddr(asset.prefix + "qx2gpwj3a4kx5cnqf3xglf8sgu"); }
              }}>⧉ paste</Btn>
              <span className="dim" style={{fontSize: 12}}>detects BIP21 URI · embedded amount / label</span>
            </div>
            {addrOk === false && <div className="help" style={{color: "var(--danger-ink)"}}>Doesn't parse as a {asset.chain === "BTC" ? "Bitcoin testnet" : "Liquid testnet"} address — expected “{asset.prefix}…”.</div>}

            <Field label={`Amount (${unit})`}>
              <div className="input-row">
                <input
                  className={`input lg mono ${amtOk === null ? "" : amtOk ? "" : "input-err"}`}
                  value={amount}
                  onChange={e => setAmount(e.target.value)}
                />
                {isBtc ? (
                  <select className="input" style={{width: 90}} value={unit} onChange={e => setUnit(e.target.value)}>
                    <option>BTC</option>
                    <option>sats</option>
                  </select>
                ) : (
                  <span className="input-affix">{asset.unit}</span>
                )}
                <Btn onClick={() => { setUnit(asset.unit); setAmount(fmt(asset.balance - (isBtc ? feeCoin : 0), asset.dp).replace(/,/g, "")); }}>max</Btn>
              </div>
              <div className="help mono">
                {isBtc
                  ? `≈ ${Math.round(amtNum * 1e8).toLocaleString()} sats · ≈ $${(amtNum * 65000).toFixed(2)}`
                  : `balance ${fmt(asset.balance, asset.dp)} ${asset.unit}`}
                {amtOk === false && <span style={{color: "var(--danger-ink)"}}> — exceeds spendable balance</span>}
              </div>
            </Field>

            <Field label="Note" optional hint="Stored locally only — never written on-chain.">
              <input className="input" placeholder="What's this for?" value={note} onChange={e => setNote(e.target.value)} />
            </Field>

            <label className="check" style={{marginTop: 14}}>
              <input type="checkbox" checked={advanced} onChange={e => setAdvanced(e.target.checked)} />
              Advanced
            </label>
            {advanced && (
              <Card flat tight style={{marginTop: 10}}>
                <Field label="OP_RETURN message" optional hint={`${opReturn.length} / 80 bytes — written on-chain, public forever.`}>
                  <input className="input mono" maxLength={80} placeholder="—" value={opReturn} onChange={e => setOpReturn(e.target.value)} />
                </Field>
              </Card>
            )}
          </Card>

          {/* right — fee, coins, summary */}
          <div className="col" style={{gap: 14}}>
            <Card>
              <div className="between">
                <strong>Fee rate</strong>
                <span className="dim mono" style={{fontSize: 11.5}}>142 vB tx</span>
              </div>
              <div className="fee-row" style={{marginTop: 12}}>
                {FEES[asset.chain].map(f => (
                  <button key={f.id} className={`fee-opt ${fee === f.id ? "on" : ""}`} onClick={() => setFee(f.id)}>
                    {f.label} <span className="r">{f.rate} sat/vB</span>
                  </button>
                ))}
              </div>
              <div className="help">{feeOpt.eta} · ≈ {feeOpt.sats} sat fee</div>
            </Card>

            <Card>
              <div className="between">
                <strong>Coin selection</strong>
                <Btn variant="ghost" size="sm" onClick={() => { window.FLOW.returnTo = "send"; go("utxo"); }}>pick UTXOs →</Btn>
              </div>
              <div className="row" style={{marginTop: 10, gap: 18}}>
                <label className="check">
                  <input type="radio" name="coins" checked={coinMode === "auto"} onChange={() => { setCoinMode("auto"); setManualCoins(null); }} />
                  Auto (privacy first)
                </label>
                <label className="check">
                  <input type="radio" name="coins" checked={coinMode === "manual"} onChange={() => { window.FLOW.returnTo = "send"; go("utxo"); }} />
                  Manual
                </label>
              </div>
              {manualCoins && (
                <div className="help mono">
                  {manualCoins.length} input{manualCoins.length > 1 ? "s" : ""} attached · {fmt(manualCoins.reduce((s, u) => s + u.amt, 0), 8)} ₿
                </div>
              )}
            </Card>

            <Card>
              <strong>Summary</strong>
              <table className="table" style={{marginTop: 6}}>
                <tbody>
                  <tr><td className="dim">To</td><td className="num mono">{short}</td></tr>
                  <tr><td className="dim">Amount</td><td className="num mono">{fmt(amtNum, asset.dp)} {asset.unit}</td></tr>
                  <tr><td className="dim">Fee · {feeOpt.rate} sat/vB</td><td className="num mono">~{fmt(feeCoin, 8)}</td></tr>
                  <tr><td className="dim">Change to</td><td className="num mono">{changeAddr} (new)</td></tr>
                  {opReturn && <tr><td className="dim">OP_RETURN</td><td className="num mono">{opReturn.length} bytes</td></tr>}
                  <tr><td className="dim"><strong style={{color: "var(--ink)"}}>Total</strong></td>
                      <td className="num mono"><strong>{fmt(amtNum, asset.dp)} {asset.unit} + fee</strong></td></tr>
                </tbody>
              </table>
            </Card>

            <Btn variant="primary" size="lg" fill disabled={!canReview} style={!canReview ? {opacity: 0.5, pointerEvents: "none"} : null}
              onClick={() => { setPhase("form"); setReview(true); }}>
              Review & sign →
            </Btn>
          </div>
        </div>
      </div>

      {review && (
        <Modal
          title={phase === "sent" ? "Broadcast" : `Review ${isBtc ? "PSBT" : "PSET"}`}
          onClose={() => { if (phase === "sent") resetAll(); else setReview(false); }}
          foot={
            phase === "form" ? (
              <React.Fragment>
                <Btn onClick={() => setReview(false)}>back to edit</Btn>
                <Btn variant="primary" onClick={sign}>✎ Sign & broadcast</Btn>
              </React.Fragment>
            ) : phase === "sent" ? (
              <React.Fragment>
                <Btn onClick={resetAll}>send another</Btn>
                <Btn variant="primary" onClick={() => { resetAll(); go("history"); }}>view in activity →</Btn>
              </React.Fragment>
            ) : null
          }
        >
          {phase !== "sent" && (
            <React.Fragment>
              <Card flat tight>
                <div className="between">
                  <span className="dim">Sending</span>
                  <span className="value-md mono">{fmt(amtNum, asset.dp)} {asset.unit}</span>
                </div>
                <div className="between" style={{marginTop: 6}}>
                  <span className="dim">To</span>
                  <span className="mono" style={{fontSize: 12.5}}>{addr.trim()}</span>
                </div>
                <div className="between" style={{marginTop: 6}}>
                  <span className="dim">Fee</span>
                  <span className="mono">{feeOpt.sats} sats · {feeOpt.rate} sat/vB</span>
                </div>
                {note && (
                  <div className="between" style={{marginTop: 6}}>
                    <span className="dim">Note</span><span>{note}</span>
                  </div>
                )}
              </Card>
              <div className="row" style={{marginTop: 12, flexWrap: "wrap"}}>
                <Pill tone="ok" dot>address parses</Pill>
                <Pill tone="ok" dot>{coinMode === "manual" && manualCoins ? `${manualCoins.length} manual inputs` : "inputs auto-selected"}</Pill>
                <Pill tone="ok" dot>change returns to wallet</Pill>
                {asset.chain === "LQ" && <Pill tone="lq" dot>amounts blinded</Pill>}
              </div>
              {phase === "signing" && (
                <div className="row" style={{marginTop: 16, justifyContent: "center", color: "var(--ink-3)"}}>
                  <span className="sign-anim"><i /><i /><i /></span>
                  <span style={{fontSize: 13}}>signing inputs & broadcasting…</span>
                </div>
              )}
            </React.Fragment>
          )}
          {phase === "sent" && (
            <div style={{textAlign: "center", padding: "8px 0"}}>
              <div className="big-check">✓</div>
              <strong style={{fontSize: 16}}>Broadcast to {isBtc ? "Bitcoin" : "Liquid"} {wallet.network}</strong>
              <p className="sub" style={{marginTop: 6}}>Waiting for first confirmation.</p>
              <div style={{marginTop: 14}}>
                <CodeBlock value={"txid · " + (isBtc ? "8f3c1b7a02de915646ce77b1a4f2ddc90ab34cf1e6d8290b" : "aa10fe92c4477d3be1902bb4e8f6a3d1c05b8fa2e94d1c60")} />
              </div>
            </div>
          )}
        </Modal>
      )}
    </React.Fragment>
  );
}

(window.WSCREENS = window.WSCREENS || {}).send = SendScreen;
})();
