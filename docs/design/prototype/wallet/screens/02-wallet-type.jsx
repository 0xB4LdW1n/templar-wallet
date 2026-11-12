// 02 — Restore / import an existing wallet: seed phrase, descriptor, or air-gap QR.
(() => {

const METHODS = [
  { id: "seed",       glyph: "✎", t: "Seed phrase", d: "Type a 12 or 24-word BIP39 mnemonic you already have on paper." },
  { id: "descriptor", glyph: "{ }", t: "Descriptor", d: "Paste an output descriptor from Sparrow, Specter or another Templar." },
  { id: "airgap",     glyph: "▢", t: "Air-gap QR", d: "Import a watch-only wallet by scanning an animated QR from a signer." },
];

function WalletTypeScreen({ go, setWalletId }) {
  const [method, setMethod] = useState("seed");
  const [phrase, setPhrase] = useState("");
  const [passphrase, setPassphrase] = useState("");
  const [desc, setDesc] = useState("");
  const [name, setName] = useState("Restored wallet");
  const [network, setNetwork] = useState("Testnet");
  const [scanning, setScanning] = useState(false);
  const [scanPct, setScanPct] = useState(0);
  const [done, setDone] = useState(false);

  const wordCount = phrase.trim() ? phrase.trim().split(/\s+/).length : 0;
  const seedOk = wordCount === 12 || wordCount === 24;
  const descOk = /^(wpkh|wsh|sh|tr|pkh|ct)\(/.test(desc.trim());
  const ready = method === "seed" ? seedOk : method === "descriptor" ? descOk : scanPct >= 100;

  // fake animated-QR scan progress
  useEffect(() => {
    if (!scanning) return;
    const t = setInterval(() => {
      setScanPct(p => {
        if (p >= 100) { clearInterval(t); setScanning(false); return 100; }
        return p + 7;
      });
    }, 180);
    return () => clearInterval(t);
  }, [scanning]);

  const finish = () => setDone(true);

  if (done) {
    return (
      <React.Fragment>
        <Topbar title="Restore / import" sub="Done" right={<Btn variant="ghost" onClick={() => { setDone(false); go("wallet-picker"); }}>Close</Btn>} />
        <div className="canvas">
          <Card style={{maxWidth: 640, margin: "40px auto", textAlign: "center", padding: "48px 32px"}}>
            <div className="big-check">✓</div>
            <h1 className="h1" style={{marginBottom: 6}}>{name} restored</h1>
            <p className="sub">
              {method === "airgap"
                ? "Watch-only wallet imported. You can build transactions here and sign them on the offline device."
                : "Wallet recovered. A full rescan of the chain is running in the background."}
            </p>
            <div className="row" style={{justifyContent: "center", marginTop: 22}}>
              <Btn variant="primary" size="lg" onClick={() => { setWalletId(method === "airgap" ? "cold" : "daily"); setDone(false); go("home"); window.toast?.("Wallet opened"); }}>
                Open wallet →
              </Btn>
              <Btn size="lg" onClick={() => { setDone(false); go("wallet-picker"); }}>Back to picker</Btn>
            </div>
          </Card>
        </div>
      </React.Fragment>
    );
  }

  return (
    <React.Fragment>
      <Topbar
        title="Restore / import"
        sub="Bring an existing wallet into Templar"
        right={<Btn variant="ghost" onClick={() => go("wallet-picker")}>Cancel</Btn>}
      />
      <div className="canvas">
        <div style={{maxWidth: 860, margin: "0 auto"}}>
          <h1 className="h1">How do you want to import?</h1>
          <p className="sub">All three end up as the same thing — a wallet Templar can watch and (if keys are present) sign with.</p>

          <div className="opt-grid" style={{marginTop: 22}}>
            {METHODS.map(m => (
              <div key={m.id} className={`opt-tile ${method === m.id ? "selected" : ""}`} onClick={() => setMethod(m.id)}>
                <div className="glyph">{m.glyph}</div>
                <div className="t">{m.t}</div>
                <div className="d">{m.d}</div>
                {m.id === "airgap" && <Pill tone="outline" className="tag">watch-only</Pill>}
              </div>
            ))}
          </div>

          <Card style={{marginTop: 18}}>
            <div className="g2">
              <Field label="Wallet name">
                <input className="input" value={name} onChange={e => setName(e.target.value)} />
              </Field>
              <Field label="Network">
                <select className="input" value={network} onChange={e => setNetwork(e.target.value)}>
                  <option>Testnet</option>
                  <option>Mainnet</option>
                  <option>Regtest</option>
                </select>
              </Field>
            </div>

            {method === "seed" && (
              <React.Fragment>
                <Field
                  label="Seed phrase"
                  hint={
                    phrase.trim() === ""
                      ? "Separate words with spaces. 12 or 24 words."
                      : seedOk
                        ? `✓ ${wordCount} words — looks like a valid BIP39 length`
                        : `${wordCount} word${wordCount === 1 ? "" : "s"} — need exactly 12 or 24`
                  }
                >
                  <textarea
                    className={`input mono ${phrase.trim() === "" ? "" : seedOk ? "input-ok" : "input-err"}`}
                    rows={3}
                    placeholder="ozone drill grab fiber …"
                    value={phrase}
                    onChange={e => setPhrase(e.target.value)}
                  />
                </Field>
                <Field label="BIP39 passphrase" optional hint="Only if the original wallet used one. Wrong passphrase = different (empty) wallet.">
                  <input className="input mono" type="password" placeholder="—" value={passphrase} onChange={e => setPassphrase(e.target.value)} />
                </Field>
              </React.Fragment>
            )}

            {method === "descriptor" && (
              <Field
                label="Output descriptor"
                hint={desc.trim() === "" ? "wpkh([fp/84'/1'/0']xpub…/<0;1>/*) — multipath accepted" : descOk ? "✓ parses as a descriptor" : "doesn't look like a descriptor yet"}
              >
                <textarea
                  className={`input mono ${desc.trim() === "" ? "" : descOk ? "input-ok" : "input-err"}`}
                  rows={4}
                  placeholder="wpkh([73c5a9f1/84'/1'/0']tpubDC2Q4xK4XH72J9p4QzPbN3vfvSgvxL8wKjMrgKZsJpZ7K3F2vqK4CkXrCQ2EhHzPHFw8RBmGS9/<0;1>/*)"
                  value={desc}
                  onChange={e => setDesc(e.target.value)}
                />
              </Field>
            )}

            {method === "airgap" && (
              <div style={{marginTop: 14}}>
                <div className="rowg4" style={{alignItems: "flex-start"}}>
                  <div className="qr" style={{width: 140, height: 140, flexShrink: 0, opacity: scanPct > 0 ? 1 : 0.4}} />
                  <div style={{flex: 1}}>
                    <strong>Scan the animated QR from your signer</strong>
                    <p className="sub" style={{margin: "6px 0 12px"}}>
                      On Jade / SeedSigner: Settings → Export xpub → animated QR. Hold it to your webcam.
                    </p>
                    {scanPct === 0 && <Btn variant="primary" onClick={() => { setScanPct(1); setScanning(true); }}>▣ Start camera</Btn>}
                    {scanPct > 0 && scanPct < 100 && (
                      <div>
                        <div style={{height: 8, background: "var(--surface-2)", borderRadius: 999, overflow: "hidden", maxWidth: 320}}>
                          <div style={{height: "100%", width: `${scanPct}%`, background: "var(--grad-violet)", transition: "width 160ms ease"}} />
                        </div>
                        <div className="help mono">receiving UR parts… {Math.min(scanPct, 99)}%</div>
                      </div>
                    )}
                    {scanPct >= 100 && (
                      <Pill tone="ok" dot>xpub received · 73c5a9f1 · m/84'/1'/0'</Pill>
                    )}
                  </div>
                </div>
              </div>
            )}
          </Card>

          <div className="between" style={{marginTop: 28}}>
            <Btn variant="ghost" onClick={() => go("wallet-picker")}>← Back to wallets</Btn>
            <Btn variant="primary" size="lg" disabled={!ready} style={!ready ? {opacity: 0.5, pointerEvents: "none"} : null} onClick={finish}>
              {method === "airgap" ? "Import watch-only →" : "Restore wallet →"}
            </Btn>
          </div>
        </div>
      </div>
    </React.Fragment>
  );
}

(window.WSCREENS = window.WSCREENS || {})["wallet-type"] = WalletTypeScreen;
})();
