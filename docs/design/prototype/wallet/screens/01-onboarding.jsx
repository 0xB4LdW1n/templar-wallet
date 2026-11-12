// 01 — Create a new wallet: Type → Details → Backup (length / write / confirm) → Done.
(() => {

const WORDS_12 = ["ozone","drill","grab","fiber","curtain","grace","pudding","thank","cruise","elder","eight","picnic"];
const WORDS_24 = [...WORDS_12, "mercy","dice","empower","salad","famous","brick","tonight","valve","canal","sibling","royal","velvet"];

const TYPES = [
  { id: "software", glyph: "▭", t: "Software", d: "Keys live on this machine, encrypted at rest. The everyday choice.", tag: "recommended" },
  { id: "multisig", glyph: "⌘", t: "Multisig", d: "2-of-3 or custom quorum. Coordinate with hardware or other laptops." },
  { id: "airgap",   glyph: "▢", t: "Air-gap QR", d: "Watch-only here; keys stay on an offline device. Sign via QR codes." },
];

function OnboardingScreen({ wallet, go, setWalletId }) {
  const [step, setStep] = useState(0);            // 0 type · 1 details · 2 backup · 3 done
  const [sub, setSub] = useState("length");        // backup sub-step: length | words | confirm
  const [wtype, setWtype] = useState("software");
  const [name, setName] = useState("My everyday wallet");
  const [network, setNetwork] = useState("Testnet");
  const [len, setLen] = useState(12);
  const [revealed, setRevealed] = useState(false);
  const [answers, setAnswers] = useState(["", "", ""]);
  const [checked, setChecked] = useState(false);   // ran validation at least once

  const words = len === 12 ? WORDS_12 : WORDS_24;
  const ASK = len === 12 ? [3, 7, 11] : [5, 14, 22]; // 1-based word positions

  const stepLabel = ["Type", "Details", "Backup", "Done"][step];
  const wrong = (i) => answers[i].trim().toLowerCase() !== words[ASK[i] - 1];
  const allOk = [0, 1, 2].every(i => !wrong(i));

  const reset = () => { setStep(0); setSub("length"); setRevealed(false); setAnswers(["", "", ""]); setChecked(false); };
  const cancel = () => { reset(); go("wallet-picker"); };

  return (
    <React.Fragment>
      <Topbar
        title="Create a new wallet"
        sub={`Step ${step + 1} of 4 · ${stepLabel}`}
        right={
          <React.Fragment>
            <Pill tone="outline">step {step + 1} / 4</Pill>
            <Btn variant="ghost" onClick={cancel}>Cancel</Btn>
          </React.Fragment>
        }
      />
      <div className="canvas">
        <div style={{maxWidth: 860, margin: "0 auto"}}>
          <Stepper steps={["Type", "Details", "Backup", "Done"]} current={step} />

          {step === 0 && (
            <React.Fragment>
              <h1 className="h1">What kind of wallet?</h1>
              <p className="sub">You can add more wallets later — this only sets up the first one.</p>
              <div className="opt-grid" style={{marginTop: 22}}>
                {TYPES.map(t => (
                  <div key={t.id} className={`opt-tile ${wtype === t.id ? "selected" : ""}`} onClick={() => setWtype(t.id)}>
                    <div className="glyph">{t.glyph}</div>
                    <div className="t">{t.t}</div>
                    <div className="d">{t.d}</div>
                    {t.tag && <Pill tone="ok" className="tag">{t.tag}</Pill>}
                  </div>
                ))}
              </div>
              <div className="between" style={{marginTop: 28}}>
                <Btn variant="ghost" onClick={cancel}>← Back</Btn>
                <Btn variant="primary" size="lg" onClick={() => setStep(1)}>Next · Details →</Btn>
              </div>
            </React.Fragment>
          )}

          {step === 1 && (
            <React.Fragment>
              <h1 className="h1">Name it</h1>
              <p className="sub">Shown only on this machine. Pick the network it lives on.</p>
              <Card style={{marginTop: 22, maxWidth: 560}}>
                <Field label="Wallet name" hint="Something you'll recognise in the picker.">
                  <input className="input lg" value={name} onChange={e => setName(e.target.value)} placeholder="e.g. Daily" />
                </Field>
                <Field label="Network" hint="Testnet coins are worthless — perfect for trying things out.">
                  <select className="input" value={network} onChange={e => setNetwork(e.target.value)}>
                    <option>Testnet</option>
                    <option>Mainnet</option>
                    <option>Regtest</option>
                  </select>
                </Field>
              </Card>
              <div className="between" style={{marginTop: 28}}>
                <Btn variant="ghost" onClick={() => setStep(0)}>← Back</Btn>
                <Btn variant="primary" size="lg" disabled={!name.trim()} style={!name.trim() ? {opacity: 0.5, pointerEvents: "none"} : null}
                  onClick={() => setStep(2)}>Next · Backup →</Btn>
              </div>
            </React.Fragment>
          )}

          {step === 2 && sub === "length" && (
            <React.Fragment>
              <h1 className="h1">How long should the seed be?</h1>
              <p className="sub">BIP39 mnemonic. 24 words gives 256 bits of entropy and is the modern default; 12 words is shorter and still strong.</p>
              <div className="g2" style={{marginTop: 22}}>
                <Card className={len === 12 ? "selected-card" : ""} onClick={() => setLen(12)} style={{cursor: "pointer"}}>
                  <div className="between">
                    <strong style={{fontSize: 17}}>12 words</strong>
                    <Pill tone="outline">128-bit</Pill>
                  </div>
                  <p className="sub" style={{margin: "8px 0 10px"}}>Shorter to write down. Plenty of entropy for personal use.</p>
                  <span className="mono dim" style={{fontSize: 12}}>m / 84' / 1' / 0' · wpkh</span>
                </Card>
                <Card className={len === 24 ? "selected-card" : ""} onClick={() => setLen(24)} style={{cursor: "pointer"}}>
                  <div className="between">
                    <strong style={{fontSize: 17}}>24 words</strong>
                    <Pill tone="outline">256-bit</Pill>
                  </div>
                  <p className="sub" style={{margin: "8px 0 10px"}}>Maximum entropy. Standard for treasury / long-term cold storage.</p>
                  <span className="mono dim" style={{fontSize: 12}}>m / 84' / 1' / 0' · wpkh</span>
                </Card>
              </div>
              <div className="between" style={{marginTop: 28}}>
                <Btn variant="ghost" onClick={() => setStep(1)}>← Back</Btn>
                <Btn variant="primary" size="lg" onClick={() => { setRevealed(false); setSub("words"); }}>
                  Generate {len}-word seed →
                </Btn>
              </div>
            </React.Fragment>
          )}

          {step === 2 && sub === "words" && (
            <React.Fragment>
              <h1 className="h1">Write these {len} words down</h1>
              <p className="sub">
                On paper. In order. Anyone with these words controls your funds.{" "}
                <strong style={{color: "var(--ink)"}}>Never type or photograph them.</strong>
              </p>
              <Card style={{marginTop: 22, position: "relative"}}>
                <div className={`seed-grid ${revealed ? "" : "blurred"}`}>
                  {words.map((w, i) => (
                    <div key={i} className="seed-cell">
                      <span className="seed-n">{i + 1}</span>
                      <span className="seed-w">{w}</span>
                    </div>
                  ))}
                </div>
                {!revealed && (
                  <div className="seed-overlay">
                    <Btn variant="primary" onClick={() => setRevealed(true)}>👁 Reveal seed — make sure nobody is watching</Btn>
                  </div>
                )}
              </Card>
              <div className="between" style={{marginTop: 28}}>
                <Btn variant="ghost" onClick={() => setSub("length")}>← Back</Btn>
                <Btn variant="primary" size="lg" disabled={!revealed} style={!revealed ? {opacity: 0.5, pointerEvents: "none"} : null}
                  onClick={() => { setAnswers(["", "", ""]); setChecked(false); setSub("confirm"); }}>
                  I wrote them down · Verify →
                </Btn>
              </div>
            </React.Fragment>
          )}

          {step === 2 && sub === "confirm" && (
            <React.Fragment>
              <h1 className="h1">Confirm your seed</h1>
              <p className="sub">Type the requested words back. This is the only proof that your backup is correct.</p>
              <Card style={{marginTop: 22}}>
                <div className="g3">
                  {ASK.map((pos, i) => (
                    <Field key={pos} label={`Word #${pos}`}>
                      <input
                        className={`input mono ${checked ? (wrong(i) ? "input-err" : "input-ok") : ""}`}
                        placeholder="…"
                        value={answers[i]}
                        onChange={e => setAnswers(a => a.map((v, j) => j === i ? e.target.value : v))}
                      />
                    </Field>
                  ))}
                </div>
                <p className="help" style={{marginTop: 14}}>
                  Tip — we ask for 3 random positions, not the whole seed. This proves you wrote them correctly without typing them into the wallet.
                </p>
                {checked && !allOk && (
                  <Card tone="danger" tight style={{marginTop: 12}}>
                    One or more words don't match. Check your paper backup and try again — or go back and re-read the seed.
                  </Card>
                )}
              </Card>
              <div className="between" style={{marginTop: 28}}>
                <Btn variant="ghost" onClick={() => setSub("words")}>← See seed again</Btn>
                <Btn variant="primary" size="lg" onClick={() => { setChecked(true); if (allOk) setStep(3); }}>
                  Confirm & finish →
                </Btn>
              </div>
            </React.Fragment>
          )}

          {step === 3 && (
            <Card style={{marginTop: 10, textAlign: "center", padding: "48px 32px"}}>
              <div className="big-check">✓</div>
              <h1 className="h1" style={{marginBottom: 6}}>Welcome, {name}</h1>
              <p className="sub">
                Your <strong style={{color: "var(--ink)"}}>{TYPES.find(t => t.id === wtype).t}</strong> wallet is ready. Time to receive your first sats.
              </p>
              <div className="row" style={{justifyContent: "center", marginTop: 22}}>
                <Btn variant="primary" size="lg" onClick={() => { setWalletId("daily"); reset(); go("home"); window.toast?.("Wallet opened"); }}>
                  Open wallet →
                </Btn>
                <Btn size="lg" onClick={() => { setWalletId("daily"); reset(); go("receive"); }}>
                  ↓ Get receive address
                </Btn>
              </div>
            </Card>
          )}
        </div>
      </div>
    </React.Fragment>
  );
}

(window.WSCREENS = window.WSCREENS || {}).onboarding = OnboardingScreen;
})();
