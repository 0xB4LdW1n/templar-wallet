// 09 — Wallet info: identity, backup state, descriptors, interop exports.
(() => {

const XPUB = "[73c5a9f1/84'/1'/0']tpubDC2Q4xK4XH72J9p4QzPbN3vfvSgvxL8wKjMrgKZsJpZ7K3F2vqK4CkXrCQ2EhHzPHFw8RBmGS9";
const RECV = `wpkh(${XPUB}/0/*)#5p6cz3xq`;
const CHNG = `wpkh(${XPUB}/1/*)#qx2y19fk`;
const MULTI = `wpkh(${XPUB}/<0;1>/*)#abcdef00`;
const CT = `ct(slip77(L77KrPb…),elwpkh(${XPUB}/<0;1>/*))`;
const BLIND = "L77KrPb6c3FjhVcAcb1ad03a4ce3a98e0a25c6f8d2b1e5a30f2c11d83b9e7a05";
const SEED = ["ozone","drill","grab","fiber","curtain","grace","pudding","thank","cruise","elder","eight","picnic"];

const bundleJson = (name) => JSON.stringify({
  label: name, blockheight: 3041142,
  descriptor: MULTI, fingerprint: "73c5a9f1", derivation: "m/84'/1'/0'",
}, null, 2);

function QrModal({ title, sub, onClose }) {
  const [frame, setFrame] = useState(1);
  useEffect(() => {
    const t = setInterval(() => setFrame(f => (f % 6) + 1), 600);
    return () => clearInterval(t);
  }, []);
  return (
    <Modal title={title} onClose={onClose} foot={<Btn variant="primary" onClick={onClose}>done</Btn>}>
      <div style={{textAlign: "center"}}>
        <div className="qr" style={{margin: "6px auto 12px", width: 220, height: 220, transform: `rotate(${frame % 2 ? 0 : 90}deg)`}} />
        <Pill tone="violet">frame {frame} / 6 · UR:CRYPTO-OUTPUT</Pill>
        <p className="help" style={{marginTop: 10}}>{sub}</p>
      </div>
    </Modal>
  );
}

function SeedModal({ onClose }) {
  const [sure, setSure] = useState(false);
  return (
    <Modal title="Reveal seed phrase" onClose={onClose}
      foot={<Btn variant="primary" onClick={onClose}>close</Btn>}>
      {!sure ? (
        <React.Fragment>
          <Card tone="danger" tight>
            Anyone who sees these 12 words can take everything in this wallet. Make sure nobody is watching your screen.
          </Card>
          <div className="modal-foot" style={{justifyContent: "center"}}>
            <Btn variant="danger" onClick={() => setSure(true)}>I understand — reveal</Btn>
          </div>
        </React.Fragment>
      ) : (
        <div className="seed-grid" style={{gridTemplateColumns: "repeat(3, 1fr)"}}>
          {SEED.map((w, i) => (
            <div key={i} className="seed-cell"><span className="seed-n">{i + 1}</span><span className="seed-w">{w}</span></div>
          ))}
        </div>
      )}
    </Modal>
  );
}

function DescRow({ label, value, hint }) {
  return (
    <div style={{marginBottom: 14}}>
      <span className="label" style={{margin: "0 0 6px"}}>{label}</span>
      <div className="copy-row">
        <CodeBlock value={value} showCopy={false} />
        <CopyBtn value={value} label="Copy" />
      </div>
      {hint && <div className="help">{hint}</div>}
    </div>
  );
}

function InfoScreen({ wallet }) {
  const [name, setName] = useState(wallet.name);
  const [editing, setEditing] = useState(false);
  const [zpub, setZpub] = useState(false);
  const [qr, setQr] = useState(null);        // { title, sub }
  const [seed, setSeed] = useState(false);
  const [passModal, setPassModal] = useState(false);
  const [backedUp, setBackedUp] = useState(false);

  const xpubShown = zpub ? XPUB.replace("]tpub", "]vpub") : XPUB;

  return (
    <React.Fragment>
      <Topbar
        title="Wallet info"
        sub="Everything other apps and cosigners need to recognize this wallet"
        right={
          <React.Fragment>
            <Btn onClick={() => { download("templar-wallet.json", bundleJson(name)); window.toast?.("Exported templar-wallet.json"); }}>⇩ Export .json</Btn>
            <Btn variant="primary" onClick={() => setQr({ title: "Animated wallet QR", sub: "Scan with Jade, SeedSigner or another Templar to import this wallet watch-only." })}>
              ▶ Show QR (animated)
            </Btn>
          </React.Fragment>
        }
      />
      <div className="canvas">
        <Card tone="ok" style={{marginBottom: 18}}>
          <div className="between" style={{flexWrap: "wrap", gap: 10}}>
            <Pill tone="ok" dot>multisig-ready</Pill>
            <div className="row">
              <Btn variant="primary" onClick={() => { navigator.clipboard?.writeText(`${name} · 73c5a9f1 · m/84'/1'/0'\n${XPUB}\n${MULTI}`).catch(() => {}); window.toast?.("Cosigner bundle copied"); }}>
                ⧉ Copy cosigner bundle
              </Btn>
              <Btn onClick={() => setQr({ title: "Cosigner QR", sub: "fingerprint + derivation + xpub, as an animated UR." })}>▶ animated QR</Btn>
            </div>
          </div>
          <h2 className="h2" style={{margin: "10px 0 4px"}}>Share this wallet for cosigning</h2>
          <p className="sub">
            Cosigners need three things: <strong style={{color: "var(--ink)"}}>fingerprint + derivation</strong>, the <strong style={{color: "var(--ink)"}}>xpub</strong>, and ideally the <strong style={{color: "var(--ink)"}}>multipath descriptor</strong>. Copy all three with one click.
          </p>
        </Card>

        <div className="g2" style={{alignItems: "start"}}>
          <Card>
            <div className="between">
              <strong>Identity</strong>
              <Pill tone="outline">{wallet.kind} · single-sig</Pill>
            </div>
            <table className="table" style={{marginTop: 8}}>
              <tbody>
                <tr>
                  <td className="dim" style={{width: 150}}>Name</td>
                  <td>
                    {editing
                      ? <input className="input" style={{height: 30}} autoFocus value={name} onChange={e => setName(e.target.value)}
                          onKeyDown={e => e.key === "Enter" && setEditing(false)} onBlur={() => setEditing(false)} />
                      : name}
                  </td>
                  <td style={{textAlign: "right", width: 70}}>
                    <Btn variant="ghost" size="sm" onClick={() => setEditing(true)}>edit</Btn>
                  </td>
                </tr>
                <tr><td className="dim">Network</td><td>{wallet.network}</td><td /></tr>
                <tr>
                  <td className="dim">Master fingerprint</td><td className="mono">73c5a9f1</td>
                  <td style={{textAlign: "right"}}><CopyBtn value="73c5a9f1" label="copy" /></td>
                </tr>
                <tr>
                  <td className="dim">Derivation</td><td className="mono">m/84'/1'/0'</td>
                  <td style={{textAlign: "right"}}><CopyBtn value="m/84'/1'/0'" label="copy" /></td>
                </tr>
                <tr><td className="dim">Script type</td><td className="mono">wpkh <span className="dim">(native segwit)</span></td><td /></tr>
              </tbody>
            </table>
          </Card>

          <Card tone="warn">
            <strong>Backup</strong>
            <table className="table" style={{marginTop: 8}}>
              <tbody>
                <tr>
                  <td className="dim" style={{width: 140}}>Seed</td>
                  <td>12 words · encrypted at rest</td>
                  <td style={{textAlign: "right", width: 110}}><Btn size="sm" onClick={() => setSeed(true)}>show…</Btn></td>
                </tr>
                <tr>
                  <td className="dim">Last backup</td>
                  <td className={backedUp ? "" : "dim"}>{backedUp ? "today" : "never"}</td>
                  <td style={{textAlign: "right"}}>
                    {!backedUp && <Btn size="sm" variant="primary" onClick={() => { setBackedUp(true); window.toast?.("Marked as backed up"); }}>back up now</Btn>}
                  </td>
                </tr>
                <tr>
                  <td className="dim">BIP39 passphrase</td>
                  <td className="dim">not set</td>
                  <td style={{textAlign: "right"}}><Btn size="sm" variant="ghost" onClick={() => setPassModal(true)}>set…</Btn></td>
                </tr>
              </tbody>
            </table>
          </Card>
        </div>

        <SectionH right={<Btn size="sm" onClick={() => { download("sparrow-import.json", bundleJson(name)); window.toast?.("Sparrow JSON exported"); }}>⇩ Export Sparrow JSON</Btn>}>
          <span className="pill btc" style={{marginRight: 8}}>BTC</span> Bitcoin descriptors
        </SectionH>
        <Card style={{borderLeft: "3px solid var(--btc)"}}>
          <DescRow label={zpub ? "zpub (SLIP-132)" : "xpub (for cosigners)"} value={xpubShown}
            hint="Always paired with fingerprint + derivation in the bracketed prefix." />
          <DescRow label="Receive descriptor" value={RECV} />
          <DescRow label="Change descriptor" value={CHNG} />
          <DescRow label="Multipath descriptor (BIP-389)" value={MULTI}
            hint="Cosigners that speak BIP-389 prefer this single string over the two above." />
          <div className="row" style={{flexWrap: "wrap"}}>
            <Btn variant="primary" size="sm" onClick={() => { navigator.clipboard?.writeText(MULTI).catch(() => {}); window.toast?.("Multipath descriptor copied"); }}>⧉ Copy multipath</Btn>
            <Btn size="sm" onClick={() => { navigator.clipboard?.writeText(RECV + "\n" + CHNG).catch(() => {}); window.toast?.("Both descriptors copied"); }}>⧉ Copy receive + change</Btn>
            <Btn size="sm" onClick={() => setQr({ title: "Animated UR QR", sub: "Multipart UR for air-gapped import into Jade / SeedSigner." })}>▶ Animated UR QR</Btn>
            <Btn size="sm" onClick={() => { setZpub(z => !z); window.toast?.(zpub ? "Showing xpub" : "Showing SLIP-132 zpub"); }}>{zpub ? "xpub" : "SLIP-132 zpub"}</Btn>
            <Btn size="sm" onClick={() => { download("descriptors.json", JSON.stringify({ receive: RECV, change: CHNG, multipath: MULTI }, null, 2)); window.toast?.("descriptors.json saved"); }}>⇩ JSON</Btn>
          </div>
        </Card>

        <SectionH>
          <span className="pill lq" style={{marginRight: 8}}>LQ</span> Liquid descriptors
        </SectionH>
        <Card style={{borderLeft: "3px solid var(--lq)"}}>
          <DescRow label="CT descriptor (confidential)" value={CT} />
          <DescRow label="Master blinding key (SLIP-77)" value={BLIND}
            hint="Sensitive — lets anyone unblind every amount in this wallet's history." />
          <div className="row">
            <Btn variant="primary" size="sm" onClick={() => { navigator.clipboard?.writeText(CT).catch(() => {}); window.toast?.("CT descriptor copied"); }}>⧉ Copy CT descriptor</Btn>
            <Btn size="sm" onClick={() => setQr({ title: "Liquid descriptor QR", sub: "CT descriptor incl. SLIP-77 blinding key." })}>▶ QR</Btn>
            <Btn size="sm" onClick={() => { download("liquid-descriptors.json", JSON.stringify({ ct: CT, blinding: BLIND }, null, 2)); window.toast?.("liquid-descriptors.json saved"); }}>⇩ JSON</Btn>
          </div>
        </Card>

        <SectionH>For other apps</SectionH>
        <div className="g3">
          <Card>
            <strong>Sparrow / Specter</strong>
            <p className="sub" style={{margin: "4px 0 12px"}}>JSON descriptor file</p>
            <Btn size="sm" onClick={() => { download("sparrow-import.json", bundleJson(name)); window.toast?.("Downloaded sparrow-import.json"); }}>Download .json</Btn>
          </Card>
          <Card>
            <strong>Jade / SeedSigner</strong>
            <p className="sub" style={{margin: "4px 0 12px"}}>Animated UR multipart QR</p>
            <Btn size="sm" onClick={() => setQr({ title: "Jade / SeedSigner QR", sub: "UR:CRYPTO-OUTPUT multipart, loops until scanned." })}>Show QR</Btn>
          </Card>
          <Card>
            <strong>BlueWallet</strong>
            <p className="sub" style={{margin: "4px 0 12px"}}>Watch-only zpub QR</p>
            <Btn size="sm" onClick={() => setQr({ title: "BlueWallet watch-only", sub: "Single static zpub QR." })}>Show QR</Btn>
          </Card>
        </div>
      </div>

      {qr && <QrModal title={qr.title} sub={qr.sub} onClose={() => setQr(null)} />}
      {seed && <SeedModal onClose={() => setSeed(false)} />}
      {passModal && (
        <Modal title="Set BIP39 passphrase" onClose={() => setPassModal(false)}
          foot={
            <React.Fragment>
              <Btn onClick={() => setPassModal(false)}>cancel</Btn>
              <Btn variant="primary" onClick={() => { setPassModal(false); window.toast?.("Passphrase set — this creates a different wallet", "!"); }}>set passphrase</Btn>
            </React.Fragment>
          }>
          <Card tone="warn" tight style={{marginBottom: 12}}>
            A passphrase creates a <strong>different wallet</strong> from the same seed. Forgetting it means losing those funds — it is not stored anywhere.
          </Card>
          <Field label="Passphrase">
            <input className="input mono" type="password" placeholder="…" />
          </Field>
        </Modal>
      )}
    </React.Fragment>
  );
}

(window.WSCREENS = window.WSCREENS || {}).info = InfoScreen;
})();
