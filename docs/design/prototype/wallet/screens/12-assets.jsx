// 12 — Issue · Reissue · Burn: chooser + three guided flows.
(() => {

const hashOf = (s) => {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return h.toString(16).padStart(8, "0");
};

function Chooser({ pick, go }) {
  return (
    <React.Fragment>
      <Topbar title="Asset operations" sub="Pick what you want to do"
        right={<Btn variant="ghost" onClick={() => go("liquid")}>← back to Liquid</Btn>} />
      <div className="canvas">
        <h1 className="h1">What do you want to do?</h1>
        <p className="sub">Pick one. We'll guide you through it step-by-step.</p>
        <div className="chooser" style={{marginTop: 22}}>
          <div className="ch" onClick={() => pick("issue")}>
            <div className="glyph">+</div>
            <h4>Issue</h4>
            <p>Mint a new Liquid asset. Define name, ticker, precision, domain. Mint the initial supply. Optionally create a reissuance token to mint more later.</p>
            <Btn variant="primary" size="sm" style={{marginTop: 12}}>Issue →</Btn>
          </div>
          <div className="ch" onClick={() => pick("reissue")}>
            <div className="glyph">↑↑</div>
            <h4>Reissue</h4>
            <p>Mint more of an existing asset. Requires the reissuance token. Increases total supply. Asset metadata stays unchanged.</p>
            <Btn variant="primary" size="sm" style={{marginTop: 12}}>Reissue →</Btn>
          </div>
          <div className="ch" onClick={() => pick("burn")}>
            <div className="glyph">△</div>
            <h4>Burn</h4>
            <p>Destroy supply forever. Sends an OP_RETURN output that locks the asset away. Irreversible — supply is permanently reduced.</p>
            <Btn variant="primary" size="sm" style={{marginTop: 12}}>Burn →</Btn>
          </div>
        </div>
        <Card flat>
          <strong>Not sure what you need?</strong>
          <ul style={{margin: "8px 0 0", paddingLeft: 18, color: "var(--ink-2)", fontSize: 13.5, lineHeight: 1.7}}>
            <li><strong>Issue</strong> = create a brand new token. Once signed, name/ticker/precision can never change.</li>
            <li><strong>Reissue</strong> = print more of an existing token you already issued. You must hold the reissuance token.</li>
            <li><strong>Burn</strong> = permanently destroy supply. Useful if a token was over-issued or to retire an asset.</li>
          </ul>
        </Card>
      </div>
    </React.Fragment>
  );
}

function IssueFlow({ back, go }) {
  const [step, setStep] = useState(0);
  const [name, setName] = useState("DePix");
  const [ticker, setTicker] = useState("DEPIX");
  const [precision, setPrecision] = useState("8");
  const [domain, setDomain] = useState("depix.local");
  const [supply, setSupply] = useState("1000.00");
  const [dest, setDest] = useState("tlq1q…gj3a (this wallet)");
  const [feeRate, setFeeRate] = useState("0.1");
  const [reToken, setReToken] = useState(true);
  const [reWhere, setReWhere] = useState("same address as the supply");
  const [phase, setPhase] = useState("form"); // form | signing | done

  const contract = `{ "name": "${name}", "ticker": "${ticker}", "precision": ${precision || 0}, "entity": { "domain": "${domain}" }, "version": 0 }`;
  const chash = hashOf(contract);
  const tickerOk = /^[A-Za-z.\-]{3,24}$/.test(ticker);
  const precOk = precision !== "" && +precision >= 0 && +precision <= 8;
  const domainOk = /^[a-z0-9.\-]+\.[a-z]{2,}$/i.test(domain);
  const defineOk = name.trim() && tickerOk && precOk && domainOk;
  const supplyOk = parseFloat(supply) > 0;

  const sign = () => { setPhase("signing"); setTimeout(() => setPhase("done"), 1800); };

  return (
    <React.Fragment>
      <Topbar title="Issue new asset" sub={`Step ${step + 1} of 3 · define metadata, choose supply, review`}
        right={<Btn variant="ghost" onClick={back}>← cancel</Btn>} />
      <div className="canvas">
        <div style={{maxWidth: 920, margin: "0 auto"}}>
          <Stepper steps={["Define", "Supply", "Review & sign"]} current={step} />

          {step === 0 && (
            <React.Fragment>
              <h1 className="h1">Define your asset</h1>
              <p className="sub">These details get hashed into the contract and can't change later.</p>
              <div style={{display: "grid", gridTemplateColumns: "1fr 380px", gap: 18, marginTop: 20, alignItems: "start"}}>
                <Card>
                  <Field label="Token name" hint="Human-readable. Displayed in wallets that show your asset.">
                    <input className="input" value={name} onChange={e => setName(e.target.value)} />
                  </Field>
                  <Field label="Ticker" hint="3 – 24 characters. Convention: UPPERCASE.">
                    <input className={`input mono ${ticker === "" ? "" : tickerOk ? "" : "input-err"}`} value={ticker} onChange={e => setTicker(e.target.value.toUpperCase())} />
                  </Field>
                  <Field label="Precision" hint="Decimal places. 8 = behaves like BTC; 2 = like dollars.">
                    <input className={`input mono ${precOk ? "" : "input-err"}`} value={precision} onChange={e => setPrecision(e.target.value)} />
                  </Field>
                  <Field label="Domain" hint="Issuer URL. Required to publish to the Liquid Asset Registry.">
                    <input className={`input mono ${domain === "" ? "" : domainOk ? "" : "input-err"}`} value={domain} onChange={e => setDomain(e.target.value)} />
                  </Field>
                </Card>
                <div className="col" style={{gap: 14}}>
                  <Card style={{borderLeft: "3px solid var(--ok)"}}>
                    <strong>Contract preview</strong>
                    <div style={{marginTop: 10}}>
                      <CodeBlock value={contract} showCopy={false} />
                    </div>
                    <div className="mono dim" style={{fontSize: 12, marginTop: 10, lineHeight: 1.6}}>
                      contract hash → <strong style={{color: "var(--ink)"}}>{chash.slice(0, 7)}…{chash.slice(-4)}</strong><br />
                      asset id → derived at issuance
                    </div>
                  </Card>
                  <Card tone="warn" tight>
                    <strong>⚠ Immutable</strong>
                    <p className="sub" style={{margin: "4px 0 0", fontSize: 12.5}}>
                      Once signed, the name / ticker / precision / domain are locked into the contract hash and can never be edited. Triple-check before signing.
                    </p>
                  </Card>
                </div>
              </div>
              <div className="between" style={{marginTop: 28}}>
                <Btn variant="ghost" onClick={back}>← Cancel</Btn>
                <Btn variant="primary" size="lg" disabled={!defineOk} style={!defineOk ? {opacity: 0.5, pointerEvents: "none"} : null} onClick={() => setStep(1)}>Next · Supply →</Btn>
              </div>
            </React.Fragment>
          )}

          {step === 1 && (
            <React.Fragment>
              <h1 className="h1">Initial supply</h1>
              <p className="sub">How many tokens to mint, where they go, and whether more can be issued later.</p>
              <div style={{display: "grid", gridTemplateColumns: "1fr 380px", gap: 18, marginTop: 20, alignItems: "start"}}>
                <Card>
                  <Field label="Amount" hint={`In display units (with the precision you chose). ${(+supply || 0).toLocaleString()} ${ticker} = ${Math.round((+supply || 0) * 10 ** +precision).toLocaleString()} base units.`}>
                    <div className="input-row">
                      <input className={`input mono ${supplyOk ? "" : "input-err"}`} value={supply} onChange={e => setSupply(e.target.value)} />
                      <span className="input-affix">{ticker}</span>
                    </div>
                  </Field>
                  <Field label="Send minted supply to">
                    <input className="input mono" value={dest} onChange={e => setDest(e.target.value)} />
                  </Field>
                  <Field label="Fee rate (sat/vB)" hint="Liquid fees are sub-sat — usually 0.1 sat/vB is plenty.">
                    <input className="input mono" value={feeRate} onChange={e => setFeeRate(e.target.value)} />
                  </Field>
                </Card>
                <Card tone="warn">
                  <label className="check" style={{fontWeight: 600, color: "var(--ink)"}}>
                    <input type="checkbox" checked={reToken} onChange={e => setReToken(e.target.checked)} />
                    Create a reissuance token (1.0)
                  </label>
                  <p className="sub" style={{margin: "8px 0 0", fontSize: 12.5}}>
                    With this token in hand, you can mint more of this asset later. Without it, total supply is forever capped at the initial amount.
                  </p>
                  {reToken && (
                    <React.Fragment>
                      <Field label="Keep reissuance token at">
                        <select className="input" value={reWhere} onChange={e => setReWhere(e.target.value)}>
                          <option>same address as the supply</option>
                          <option>a fresh address in this wallet</option>
                          <option>external address…</option>
                        </select>
                      </Field>
                      <p className="help"><strong style={{color: "var(--warn-ink)"}}>Lose it = no more reissuance. Ever.</strong> Back this wallet up.</p>
                    </React.Fragment>
                  )}
                </Card>
              </div>
              <div className="between" style={{marginTop: 28}}>
                <Btn variant="ghost" onClick={() => setStep(0)}>← Back</Btn>
                <Btn variant="primary" size="lg" disabled={!supplyOk} style={!supplyOk ? {opacity: 0.5, pointerEvents: "none"} : null} onClick={() => setStep(2)}>Next · Review →</Btn>
              </div>
            </React.Fragment>
          )}

          {step === 2 && phase !== "done" && (
            <React.Fragment>
              <h1 className="h1">Review & sign</h1>
              <p className="sub">One last look before this becomes an on-chain reality.</p>
              <Card style={{marginTop: 20}}>
                <table className="table">
                  <tbody>
                    <tr><td className="dim" style={{width: 180}}>Operation</td><td><strong>Issue new asset</strong></td></tr>
                    <tr><td className="dim">Name · Ticker</td><td className="mono">{name} · {ticker}</td></tr>
                    <tr><td className="dim">Precision</td><td className="mono">{precision}</td></tr>
                    <tr><td className="dim">Domain</td><td className="mono">{domain}</td></tr>
                    <tr><td className="dim">Initial supply</td><td className="num mono" style={{textAlign: "left"}}>{(+supply).toLocaleString(undefined, { minimumFractionDigits: 2 })} {ticker}</td></tr>
                    <tr><td className="dim">Reissuance token</td>
                        <td>{reToken ? <Pill tone="ok">yes (1.0) — kept in this wallet</Pill> : <Pill tone="danger">no — supply capped forever</Pill>}</td></tr>
                    <tr><td className="dim">Contract hash</td><td className="mono">{chash.slice(0, 7)}…{chash.slice(-4)}</td></tr>
                    <tr><td className="dim">Asset ID (derived)</td><td className="mono">a09b2243…1f10</td></tr>
                    <tr><td className="dim">Network fee</td><td className="num mono" style={{textAlign: "left"}}>≈ 0.00000020 L-BTC</td></tr>
                  </tbody>
                </table>
              </Card>
              <Card tone="warn" tight style={{marginTop: 14}}>
                After signing, the issuance PSET is built. You'll be able to review it once more in the PSBT inspector before broadcasting.
              </Card>
              {phase === "signing" && (
                <div className="row" style={{marginTop: 16, justifyContent: "center", color: "var(--ink-3)"}}>
                  <span className="sign-anim"><i /><i /><i /></span>
                  <span style={{fontSize: 13}}>building issuance PSET & signing…</span>
                </div>
              )}
              <div className="between" style={{marginTop: 28}}>
                <Btn variant="ghost" onClick={() => setStep(1)}>← Back</Btn>
                <Btn variant="primary" size="lg" onClick={sign}>Build PSET & sign →</Btn>
              </div>
            </React.Fragment>
          )}

          {phase === "done" && (
            <Card style={{marginTop: 10, textAlign: "center", padding: "48px 32px"}}>
              <div className="big-check">✓</div>
              <h1 className="h1" style={{marginBottom: 6}}>{ticker} issued</h1>
              <p className="sub">
                {(+supply).toLocaleString()} {ticker} minted to your wallet{reToken ? " · reissuance token (1.0) kept" : ""}.<br />
                Asset ID <span className="mono">a09b2243…1f10</span> — a “Re-register” action will appear on the asset page once the registry accepts the metadata.
              </p>
              <div className="row" style={{justifyContent: "center", marginTop: 22}}>
                <Btn variant="primary" size="lg" onClick={() => go("liquid")}>View in Liquid →</Btn>
                <Btn size="lg" onClick={() => go("multisig")}>inspect PSET</Btn>
              </div>
            </Card>
          )}
        </div>
      </div>
    </React.Fragment>
  );
}

function ReissueFlow({ back, go }) {
  const [amt, setAmt] = useState("");
  const [dest, setDest] = useState("tlq1q…gj3a (this wallet)");
  const [phase, setPhase] = useState("form");
  const n = parseFloat(amt) || 0;
  const ok = n > 0;

  const build = () => { setPhase("signing"); setTimeout(() => setPhase("done"), 1600); };

  if (phase === "done") {
    return (
      <React.Fragment>
        <Topbar title="Reissue existing asset" sub="Done" right={<Btn variant="ghost" onClick={back}>← back</Btn>} />
        <div className="canvas">
          <Card style={{maxWidth: 640, margin: "40px auto", textAlign: "center", padding: "48px 32px"}}>
            <div className="big-check">✓</div>
            <h1 className="h1" style={{marginBottom: 6}}>+{n.toLocaleString()} DEPIX minted</h1>
            <p className="sub">Total supply is now {(1000 + n).toLocaleString(undefined, { minimumFractionDigits: 2 })}. The reissuance token returned to the same address.</p>
            <div className="row" style={{justifyContent: "center", marginTop: 22}}>
              <Btn variant="primary" size="lg" onClick={() => go("liquid")}>View in Liquid →</Btn>
              <Btn size="lg" onClick={back}>another operation</Btn>
            </div>
          </Card>
        </div>
      </React.Fragment>
    );
  }

  return (
    <React.Fragment>
      <Topbar title="Reissue existing asset" sub="Step 1 of 3" right={<Btn variant="ghost" onClick={back}>← cancel</Btn>} />
      <div className="canvas">
        <div style={{maxWidth: 920, margin: "0 auto"}}>
          <Stepper steps={["Pick asset", "Amount", "Review & sign"]} current={ok ? 1 : 0} />
          <h1 className="h1">Reissue · DEPIX</h1>
          <div className="row" style={{flexWrap: "wrap", marginTop: 6}}>
            <Pill tone="warn" dot>your asset</Pill>
            <Pill tone="ok">reissuance token held</Pill>
            <span className="mono dim" style={{fontSize: 12}}>a09b2243…1f10 · precision 8 · depix.local</span>
          </div>

          <div className="g3" style={{marginTop: 18}}>
            <Card style={{borderLeft: "3px solid var(--ok)"}}>
              <span className="label" style={{margin: "0 0 4px"}}>Current supply</span>
              <div className="value-lg mono">1,000.00</div>
            </Card>
            <Card>
              <span className="label" style={{margin: "0 0 4px"}}>You hold</span>
              <div className="value-lg mono">50.00</div>
            </Card>
            <Card tone="warn">
              <span className="label" style={{margin: "0 0 4px"}}>Reissuance token</span>
              <div className="value-lg mono">1.0 ✓</div>
            </Card>
          </div>

          <div style={{display: "grid", gridTemplateColumns: "1fr 380px", gap: 18, marginTop: 18, alignItems: "start"}}>
            <Card>
              <Field label="Asset">
                <select className="input mono">
                  <option>DEPIX · a09b2243…1f10</option>
                </select>
              </Field>
              <Field label="Additional amount" hint={ok ? `New total supply will be ${(1000 + n).toLocaleString(undefined, { minimumFractionDigits: 2 })}` : "Only reissuable assets are selectable."}>
                <div className="input-row">
                  <input className="input mono" placeholder="500.00" value={amt} onChange={e => setAmt(e.target.value)} />
                  <span className="input-affix">DEPIX</span>
                </div>
              </Field>
              <Field label="Send new supply to">
                <input className="input mono" value={dest} onChange={e => setDest(e.target.value)} />
              </Field>
            </Card>
            <Card flat>
              <strong>What happens</strong>
              <ul style={{margin: "8px 0 0", paddingLeft: 18, color: "var(--ink-2)", fontSize: 13, lineHeight: 1.7}}>
                <li>A Liquid issuance tx is built that mints {ok ? n.toLocaleString() : "…"} DEPIX.</li>
                <li>The reissuance token (1.0) is spent and re-output to the same address.</li>
                <li>Newly-minted supply is sent to your chosen Liquid address.</li>
                <li>Total supply increases to {ok ? (1000 + n).toLocaleString(undefined, { minimumFractionDigits: 2 }) : "…"}.</li>
              </ul>
            </Card>
          </div>

          {phase === "signing" && (
            <div className="row" style={{marginTop: 16, justifyContent: "center", color: "var(--ink-3)"}}>
              <span className="sign-anim"><i /><i /><i /></span>
              <span style={{fontSize: 13}}>building reissuance PSET…</span>
            </div>
          )}
          <div className="between" style={{marginTop: 28}}>
            <Btn variant="ghost" onClick={back}>← Cancel</Btn>
            <Btn variant="primary" size="lg" disabled={!ok} style={!ok ? {opacity: 0.5, pointerEvents: "none"} : null} onClick={build}>Build PSET →</Btn>
          </div>
        </div>
      </div>
    </React.Fragment>
  );
}

function BurnFlow({ back, go }) {
  const [amt, setAmt] = useState("");
  const [confirm, setConfirm] = useState("");
  const [phase, setPhase] = useState("form");
  const n = parseFloat(amt) || 0;
  const ok = n > 0 && n <= 50 && confirm.trim() === "DEPIX";

  const build = () => { setPhase("signing"); setTimeout(() => setPhase("done"), 1600); };

  if (phase === "done") {
    return (
      <React.Fragment>
        <Topbar title="Burn supply" sub="Done" right={<Btn variant="ghost" onClick={back}>← back</Btn>} />
        <div className="canvas">
          <Card style={{maxWidth: 640, margin: "40px auto", textAlign: "center", padding: "48px 32px"}}>
            <div className="big-check" style={{background: "var(--danger-soft)", color: "var(--danger-ink)"}}>△</div>
            <h1 className="h1" style={{marginBottom: 6}}>{n.toLocaleString()} DEPIX burned</h1>
            <p className="sub">Locked forever in an OP_RETURN output. New total supply: {(1000 - n).toLocaleString(undefined, { minimumFractionDigits: 2 })}.</p>
            <div className="row" style={{justifyContent: "center", marginTop: 22}}>
              <Btn variant="primary" size="lg" onClick={() => go("liquid")}>View in Liquid →</Btn>
              <Btn size="lg" onClick={back}>another operation</Btn>
            </div>
          </Card>
        </div>
      </React.Fragment>
    );
  }

  return (
    <React.Fragment>
      <Topbar title="Burn supply" sub="Permanently destroy supply" right={<Btn variant="ghost" onClick={back}>← cancel</Btn>} />
      <div className="canvas">
        <div style={{maxWidth: 720, margin: "0 auto"}}>
          <Card tone="danger" style={{marginBottom: 18}}>
            <strong>⚠ Irreversible</strong>
            <p className="sub" style={{margin: "4px 0 0"}}>
              Burning sends an OP_RETURN output that locks the asset away. Burned supply cannot be recovered, ever.
            </p>
          </Card>
          <Card>
            <Field label="Asset">
              <select className="input mono">
                <option>DEPIX · a09b2243…1f10 (your asset)</option>
              </select>
            </Field>
            <Field label="Amount to burn" hint={`New total supply will be ${(1000 - (n || 0)).toLocaleString(undefined, { minimumFractionDigits: 2 })} (you hold ${(50 - (n || 0)).toLocaleString()}).`}>
              <div className="input-row">
                <input className={`input mono ${amt === "" ? "" : n > 0 && n <= 50 ? "" : "input-err"}`} placeholder="0.00" value={amt} onChange={e => setAmt(e.target.value)} />
                <span className="input-affix">DEPIX</span>
                <Btn onClick={() => setAmt("50.00")}>burn all (50.00)</Btn>
              </div>
              {n > 50 && <div className="help" style={{color: "var(--danger-ink)"}}>You only hold 50.00 DEPIX.</div>}
            </Field>
            <Field label="Confirm by typing the ticker">
              <input
                className={`input mono ${confirm === "" ? "" : confirm.trim() === "DEPIX" ? "input-ok" : "input-err"}`}
                placeholder="DEPIX"
                value={confirm}
                onChange={e => setConfirm(e.target.value)}
              />
            </Field>
          </Card>
          {phase === "signing" && (
            <div className="row" style={{marginTop: 16, justifyContent: "center", color: "var(--ink-3)"}}>
              <span className="sign-anim"><i /><i /><i /></span>
              <span style={{fontSize: 13}}>building burn transaction…</span>
            </div>
          )}
          <div className="between" style={{marginTop: 28}}>
            <Btn variant="ghost" onClick={back}>← Cancel</Btn>
            <Btn variant="primary" size="lg" disabled={!ok} style={!ok ? {opacity: 0.5, pointerEvents: "none"} : null} onClick={build}>Build burn tx →</Btn>
          </div>
        </div>
      </div>
    </React.Fragment>
  );
}

function AssetsScreen({ go }) {
  const [op, setOp] = useState(window.FLOW.assetOp || null);
  useEffect(() => { window.FLOW.assetOp = null; }, []);

  const back = () => setOp(null);
  if (op === "issue")   return <IssueFlow back={back} go={go} />;
  if (op === "reissue") return <ReissueFlow back={back} go={go} />;
  if (op === "burn")    return <BurnFlow back={back} go={go} />;
  return <Chooser pick={setOp} go={go} />;
}

(window.WSCREENS = window.WSCREENS || {}).assets = AssetsScreen;
})();
