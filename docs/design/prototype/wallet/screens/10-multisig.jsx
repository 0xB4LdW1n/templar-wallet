// 10 — Co-sign PSBT: review, policy state, inputs/outputs, impact, sign & broadcast.
(() => {
const { COSIGNERS } = window.WDATA;

const RAW_PSBT = "cHNidP8BAHECAAAAAeJQY1VfV3GKGXMFTXMBP2wG3vB2gE0slgKO3LFKp0mkAAAAAAD9////AoDDyQEAAAAAFgAUqiCWpFq8dGNjTZ4wZ0FWvZ6d0WGA8PoCAAAAABYAFO+SBRfqZP24TSA2rvUeOU9UGSqLAAAAAAABAR+ghgEAAAAAABYAFDBqz0K1Bkw1t7cDW9GFyvyeCFCPIgYDkX9uY1v0uS1p7fEqLj0aWWJmVAWXjXPLzSLDsSMLmWEY73xrhlQAAIABAACAAAAAgAAAAAAOAAAAACICAtq4EBTFRkyH1PVIhBBOvyNXY7XoRhL5CGmXBWJ0LrgUGO98a4ZUAACAAQAAgAAAAIABAAAAAgAAAAA=";

const INPUTS = [
  { op: "c8f768e1:3", amt: "0.02188869", mine: true },
  { op: "17a4fe5a:0", amt: "0.02500000", mine: true },
  { op: "2c197e62:1", amt: "0.00320765", mine: true },
];

function MultisigScreen({ go }) {
  const [loaded, setLoaded] = useState(true);
  const [signers, setSigners] = useState(COSIGNERS.map(c => ({ ...c })));
  const [phase, setPhase] = useState("ready");   // ready | signing | signed | broadcasting | broadcast
  const [showRaw, setShowRaw] = useState(false);
  const [paste, setPaste] = useState(false);
  const [pasteText, setPasteText] = useState("");
  const [declineAsk, setDeclineAsk] = useState(false);

  const signedCt = signers.filter(s => s.signed).length;
  const need = 2;

  const sign = () => {
    setPhase("signing");
    setTimeout(() => {
      setSigners(list => list.map(s => s.role === "you" ? { ...s, signed: true } : s));
      setPhase("signed");
      window.toast?.("Signed as Laptop (73c5a9f1) — quorum reached");
    }, 1600);
  };
  const broadcast = () => {
    setPhase("broadcasting");
    setTimeout(() => setPhase("broadcast"), 1500);
  };
  const resetPsbt = () => {
    setSigners(COSIGNERS.map(c => ({ ...c })));
    setPhase("ready");
    setLoaded(true);
  };

  const sigState = (s) =>
    s.signed ? <Pill tone="ok">✓ signed</Pill>
    : s.role === "you" ? <Pill tone="warn">awaiting you</Pill>
    : <Pill tone="outline">not yet</Pill>;

  if (!loaded) {
    return (
      <React.Fragment>
        <Topbar title="Co-sign PSBT" sub="No transaction loaded"
          right={
            <React.Fragment>
              <Btn onClick={() => setPaste(true)}>⧉ Paste PSBT</Btn>
              <Btn onClick={resetPsbt}>▤ Load…</Btn>
              <Btn onClick={resetPsbt}>▣ Scan QR</Btn>
            </React.Fragment>
          } />
        <div className="canvas">
          <Card flat style={{textAlign: "center", padding: "64px 32px", marginTop: 24}}>
            <div style={{fontSize: 30, marginBottom: 10}}>⌘</div>
            <strong style={{fontSize: 16}}>Nothing waiting for a signature</strong>
            <p className="sub" style={{marginTop: 6}}>Paste a PSBT, load a .psbt file, or scan an animated QR from a cosigner.</p>
            <div className="row" style={{justifyContent: "center", marginTop: 18}}>
              <Btn variant="primary" onClick={() => setPaste(true)}>⧉ Paste PSBT</Btn>
              <Btn onClick={resetPsbt}>▤ Load file</Btn>
            </div>
          </Card>
        </div>
        {paste && (
          <Modal title="Paste PSBT / PSET" onClose={() => setPaste(false)}
            foot={
              <React.Fragment>
                <Btn onClick={() => setPaste(false)}>cancel</Btn>
                <Btn variant="primary" onClick={() => { setPaste(false); setPasteText(""); resetPsbt(); window.toast?.("PSBT parsed — 1 signature present"); }}>Parse →</Btn>
              </React.Fragment>
            }>
            <textarea className="input mono" rows={6} placeholder="cHNidP8BAH…" value={pasteText} onChange={e => setPasteText(e.target.value)} />
          </Modal>
        )}
      </React.Fragment>
    );
  }

  return (
    <React.Fragment>
      <Topbar
        title="Co-sign PSBT"
        sub={`Treasury 2-of-3 · ${signedCt} signature${signedCt === 1 ? "" : "s"} so far`}
        right={
          <React.Fragment>
            <Btn onClick={() => setPaste(true)}>⧉ Paste PSBT</Btn>
            <Btn onClick={() => window.toast?.("File picker not wired in mockup", "▤")}>▤ Load…</Btn>
            <Btn onClick={() => window.toast?.("Camera not wired in mockup", "▣")}>▣ Scan QR</Btn>
          </React.Fragment>
        }
      />
      <div className="canvas">
        {/* summary banner */}
        <Card className="fx-beam" style={{borderLeft: "3px solid var(--btc)"}}>
          <div className="between" style={{alignItems: "flex-start", flexWrap: "wrap", gap: 14}}>
            <div>
              <span className="label" style={{margin: "0 0 4px"}}>Sending</span>
              <div className="row" style={{gap: 10, alignItems: "baseline"}}>
                <span className="value-xl">0.05000000</span>
                <span className="value-md dim">BTC</span>
              </div>
              <div className="mono" style={{fontSize: 13, marginTop: 6}}>to tb1qx2gpwj3a4kx5cnqf3xglf8sgu</div>
              <div className="dim" style={{fontSize: 12.5, marginTop: 3}}>≈ $3,259.40 at current rates</div>
            </div>
            <div className="col right" style={{gap: 3}}>
              <span className="label" style={{margin: "0 0 4px"}}>From</span>
              <strong>Treasury 2-of-3</strong>
              <span className="mono dim" style={{fontSize: 12}}>balance 0.84410000 ₿</span>
              <span className="mono dim" style={{fontSize: 12}}>3 inputs · 2 outputs · 142 vB</span>
            </div>
          </div>
          <div className="row" style={{marginTop: 14, flexWrap: "wrap"}}>
            <Pill tone="ok" dot>address parses</Pill>
            <Pill tone="ok" dot>inputs are mine</Pill>
            <Pill tone="ok" dot>change returns to wallet</Pill>
            <Pill tone="ok" dot>fee within market range</Pill>
            <Pill tone="warn">recipient is brand new</Pill>
          </div>
        </Card>

        <SectionH right={
          <span style={{fontSize: 12.5, color: signedCt >= need ? "var(--ok-ink)" : "var(--warn-ink)"}}>
            {signedCt} of {need} signatures · {signedCt >= need ? "quorum reached" : `${need - signedCt} still needed`}
          </span>
        }>
          Spending policy
        </SectionH>
        <Card>
          <div className="row" style={{marginBottom: 10}}>
            <Pill tone="violet" className="mono">thresh(2,</Pill>
            <span className="dim" style={{fontSize: 12.5}}>2 of 3 keys must sign</span>
          </div>
          <div className="policy">
            <div>thresh(,</div>
            <div className="branch">
              {signers.map(s => (
                <div key={s.fp} className="sig-row">
                  <span className="row" style={{gap: 8}}>
                    <span>{s.signed ? "✓" : s.role === "you" ? "✎" : "…"}</span>
                    <span className="name">pk({s.name})</span>
                    <span className="pol">fp {s.fp}</span>
                  </span>
                  {sigState(s)}
                </div>
              ))}
            </div>
            <div>)</div>
          </div>
        </Card>

        <SectionH>Inputs & outputs</SectionH>
        <div className="g2" style={{alignItems: "start"}}>
          <Card tabular>
            <table className="table">
              <thead><tr><th>Inputs (3) · outpoint</th><th style={{textAlign: "right"}}>Amount</th><th>Owner</th></tr></thead>
              <tbody>
                {INPUTS.map(i => (
                  <tr key={i.op}>
                    <td className="mono">{i.op}</td>
                    <td className="num">{i.amt}</td>
                    <td><Pill tone="ok">mine</Pill></td>
                  </tr>
                ))}
                <tr>
                  <td><strong>Total in</strong></td>
                  <td className="num"><strong>0.05009634</strong></td>
                  <td />
                </tr>
              </tbody>
            </table>
          </Card>
          <Card tabular>
            <table className="table">
              <thead><tr><th>Outputs (2) · address</th><th style={{textAlign: "right"}}>Amount</th><th></th></tr></thead>
              <tbody>
                <tr>
                  <td className="mono">tb1qx2gp…8sgu</td>
                  <td className="num">0.05000000</td>
                  <td><Pill tone="warn">external ⚠</Pill></td>
                </tr>
                <tr>
                  <td className="mono">tb1q…2pqv <span className="dim">(change)</span></td>
                  <td className="num">0.00009151</td>
                  <td><Pill tone="ok">mine</Pill></td>
                </tr>
                <tr>
                  <td><strong>Fee · 3.4 sat/vB · 142 vB</strong></td>
                  <td className="num">0.00000483</td>
                  <td />
                </tr>
              </tbody>
            </table>
          </Card>
        </div>

        <SectionH>Impact on wallet</SectionH>
        <Card>
          <div className="banner" style={{border: "none", padding: 0, background: "none"}}>
            <div className="stat center">
              <span className="label">Before</span>
              <div className="value-lg">0.84410000 ₿</div>
            </div>
            <div className="stat center">
              <span className="label">After signing & broadcasting</span>
              <div className="value-lg">0.79409517 ₿</div>
            </div>
            <div className="stat center">
              <span className="label">Net change</span>
              <div className="value-lg" style={{color: "var(--danger-ink)"}}>−0.05000483 ₿</div>
              <span className="dim" style={{fontSize: 12}}>(incl. 483 sat fee)</span>
            </div>
          </div>
        </Card>

        <SectionH right={
          <label className="check">
            <input type="checkbox" checked={showRaw} onChange={e => setShowRaw(e.target.checked)} />
            show raw bytes
          </label>
        }>
          Raw PSBT
        </SectionH>
        {showRaw && <CodeBlock value={RAW_PSBT} height={80} />}

        {/* action bar */}
        <div className="action-bar">
          {phase === "broadcast" ? (
            <React.Fragment>
              <div className="big-check" style={{width: 34, height: 34, fontSize: 17, margin: 0}}>✓</div>
              <div className="col" style={{gap: 2}}>
                <strong>Broadcast to Bitcoin Testnet</strong>
                <span className="dim" style={{fontSize: 12}}>txid 8f3c1b7a02de…290b · waiting for confirmation</span>
              </div>
              <span className="spacer" />
              <Btn onClick={() => { setLoaded(false); setPhase("ready"); }}>load another</Btn>
              <Btn variant="primary" onClick={() => go("history")}>view in activity →</Btn>
            </React.Fragment>
          ) : (
            <React.Fragment>
              <div className="col" style={{gap: 2}}>
                <strong>
                  {phase === "signing" ? "Signing as Laptop (73c5a9f1)…"
                    : phase === "signed" ? "Quorum reached — 2 of 2 signatures"
                    : phase === "broadcasting" ? "Broadcasting…"
                    : "Ready to sign as Laptop (73c5a9f1)"}
                </strong>
                <span className="dim" style={{fontSize: 12}}>
                  {phase === "signed" ? "You can broadcast now, or export for someone else to broadcast."
                    : "After signing, share with Phone or Cold to finalize."}
                </span>
              </div>
              <span className="spacer" />
              {(phase === "signing" || phase === "broadcasting") && <span className="sign-anim"><i /><i /><i /></span>}
              {phase === "ready" && (
                <React.Fragment>
                  <Btn variant="ghost" onClick={() => setDeclineAsk(true)}>decline</Btn>
                  <Btn onClick={() => { download("treasury-unsigned.psbt", RAW_PSBT, "text/plain"); window.toast?.("Saved treasury-unsigned.psbt"); }}>save unsigned</Btn>
                  <Btn variant="primary" onClick={sign}>✎ Sign & export →</Btn>
                </React.Fragment>
              )}
              {phase === "signed" && (
                <React.Fragment>
                  <Btn onClick={() => { download("treasury-signed.psbt", RAW_PSBT, "text/plain"); window.toast?.("Saved treasury-signed.psbt — pass it to the broadcaster"); }}>⇩ export signed</Btn>
                  <Btn variant="primary" onClick={broadcast}>⇪ Broadcast →</Btn>
                </React.Fragment>
              )}
            </React.Fragment>
          )}
        </div>
      </div>

      {paste && (
        <Modal title="Paste PSBT / PSET" onClose={() => setPaste(false)}
          foot={
            <React.Fragment>
              <Btn onClick={() => setPaste(false)}>cancel</Btn>
              <Btn variant="primary" onClick={() => { setPaste(false); setPasteText(""); resetPsbt(); window.toast?.("PSBT parsed — replaced current draft"); }}>Parse →</Btn>
            </React.Fragment>
          }>
          <textarea className="input mono" rows={6} placeholder="cHNidP8BAH…" value={pasteText} onChange={e => setPasteText(e.target.value)} />
          <p className="help">Accepts base64 PSBT, hex, or a Liquid PSET.</p>
        </Modal>
      )}

      {declineAsk && (
        <Modal title="Decline this transaction?" onClose={() => setDeclineAsk(false)}
          foot={
            <React.Fragment>
              <Btn onClick={() => setDeclineAsk(false)}>keep it</Btn>
              <Btn variant="danger" onClick={() => { setDeclineAsk(false); setLoaded(false); window.toast?.("Draft discarded — cosigners were not notified"); }}>discard draft</Btn>
            </React.Fragment>
          }>
          <p className="sub">This only deletes the local draft. Nothing was broadcast, and other cosigners keep their copies.</p>
        </Modal>
      )}
    </React.Fragment>
  );
}

(window.WSCREENS = window.WSCREENS || {}).multisig = MultisigScreen;
})();
