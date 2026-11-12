// 13 — Settings: wallets, network, security, appearance, fees, advanced, about.
(() => {
const { WALLETS } = window.WDATA;

const SECTIONS = [
  { id: "wallets",    t: "Wallets",          i: "▤" },
  { id: "network",    t: "Network & sync",   i: "⇄" },
  { id: "security",   t: "Security",         i: "◉" },
  { id: "appearance", t: "Appearance",       i: "◑" },
  { id: "fees",       t: "Fees defaults",    i: "⚡" },
  { id: "advanced",   t: "Advanced & debug", i: "{}" },
  { id: "about",      t: "About",            i: "ⓘ" },
];

const balCol = (w) =>
  w.watchOnly ? "watch" : w.lcad != null ? "12.5M LCAD" : `${w.btc.toFixed(5)} ₿`;

function WalletsSection({ go, setWalletId }) {
  const [list, setList] = useState(WALLETS.map(w => ({ ...w })));
  const [del, setDel] = useState(null);       // wallet pending delete
  const [wipe, setWipe] = useState(false);
  const [confirmText, setConfirmText] = useState("");

  return (
    <React.Fragment>
      <h2 className="h2" style={{marginTop: 0}}>Your wallets</h2>
      <Card tabular>
        <table className="table">
          <thead>
            <tr><th></th><th>Name</th><th>Type</th><th>Network</th><th style={{textAlign: "right"}}>Balance</th><th></th></tr>
          </thead>
          <tbody>
            {list.map(w => (
              <tr key={w.id}>
                <td className="mono dim" style={{width: 30}}>{w.kind === "Multisig" ? "⌘" : w.kind === "Air-gap QR" ? "▢" : "▭"}</td>
                <td><strong>{w.name}</strong></td>
                <td className="dim">{w.kind}</td>
                <td className="dim">{w.network}</td>
                <td className="num">{balCol(w)}</td>
                <td style={{textAlign: "right", whiteSpace: "nowrap"}}>
                  <Btn size="sm" onClick={() => { setWalletId(w.id); go("home"); window.toast?.(`Opened ${w.name}`); }}>open</Btn>{" "}
                  <Btn size="sm" variant="ghost" onClick={() => window.toast?.("Rename in Wallet info → Identity")}>edit</Btn>{" "}
                  <Btn size="sm" variant="ghost" onClick={() => { setConfirmText(""); setDel(w); }}>delete</Btn>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <div style={{padding: 14, textAlign: "center"}}>
          <Btn variant="primary" onClick={() => go("onboarding")}>+ Add wallet</Btn>
        </div>
      </Card>

      <Card tone="danger" style={{marginTop: 18}}>
        <strong>Danger zone</strong>
        <div className="set-row" style={{marginTop: 6}}>
          <div className="grow">
            <div className="t">Delete a wallet</div>
            <div className="d">Removes encrypted data from this machine. On-chain funds are unaffected.</div>
          </div>
          <Btn size="sm" variant="danger" onClick={() => { setConfirmText(""); setDel(list[0]); }}>delete…</Btn>
        </div>
        <div className="set-row">
          <div className="grow">
            <div className="t">Wipe everything</div>
            <div className="d">All wallets + settings — no recovery on this machine.</div>
          </div>
          <Btn size="sm" variant="danger" onClick={() => { setConfirmText(""); setWipe(true); }}>wipe…</Btn>
        </div>
      </Card>

      {del && (
        <Modal title={`Delete “${del.name}”?`} onClose={() => setDel(null)}
          foot={
            <React.Fragment>
              <Btn onClick={() => setDel(null)}>keep it</Btn>
              <Btn variant="danger"
                disabled={confirmText !== del.name}
                style={confirmText !== del.name ? {opacity: 0.5, pointerEvents: "none"} : null}
                onClick={() => { setList(l => l.filter(x => x.id !== del.id)); setDel(null); window.toast?.(`${del.name} deleted from this machine`); }}>
                delete forever
              </Btn>
            </React.Fragment>
          }>
          <Card tone="danger" tight style={{marginBottom: 12}}>
            Without the seed (or descriptors for watch-only), this wallet cannot be restored. Coins on-chain are untouched.
          </Card>
          <Field label={`Type the wallet name to confirm — ${del.name}`}>
            <input className="input" autoFocus value={confirmText} onChange={e => setConfirmText(e.target.value)} placeholder={del.name} />
          </Field>
        </Modal>
      )}

      {wipe && (
        <Modal title="Wipe everything?" onClose={() => setWipe(false)}
          foot={
            <React.Fragment>
              <Btn onClick={() => setWipe(false)}>cancel</Btn>
              <Btn variant="danger"
                disabled={confirmText !== "WIPE"}
                style={confirmText !== "WIPE" ? {opacity: 0.5, pointerEvents: "none"} : null}
                onClick={() => { setWipe(false); window.toast?.("Mockup spared your wallets", "☺"); }}>
                wipe this machine
              </Btn>
            </React.Fragment>
          }>
          <Card tone="danger" tight style={{marginBottom: 12}}>
            Deletes all {list.length} wallets and every setting on this machine. Only seeds written on paper survive this.
          </Card>
          <Field label="Type WIPE to confirm">
            <input className="input mono" autoFocus value={confirmText} onChange={e => setConfirmText(e.target.value)} placeholder="WIPE" />
          </Field>
        </Modal>
      )}
    </React.Fragment>
  );
}

function NetworkSection() {
  const [network, setNetwork] = useState("Testnet");
  const [btcUrl, setBtcUrl] = useState("ssl://electrum.blockstream.info:60002");
  const [lqUrl, setLqUrl] = useState("ssl://blockstream.info:465");
  const [auto, setAuto] = useState(true);
  const [every, setEvery] = useState("60");
  const [testing, setTesting] = useState(false);

  const test = () => {
    setTesting(true);
    setTimeout(() => { setTesting(false); window.toast?.("Both nodes reachable · 42 ms / 61 ms"); }, 1400);
  };

  return (
    <React.Fragment>
      <h2 className="h2" style={{marginTop: 0}}>Network & sync</h2>
      <Card>
        <Field label="Network" hint="Switching re-derives every address and triggers a full rescan.">
          <select className="input" value={network} onChange={e => { setNetwork(e.target.value); window.toast?.(`Network set to ${e.target.value} — rescan scheduled`); }}>
            <option>Testnet</option><option>Mainnet</option><option>Regtest</option>
          </select>
        </Field>
        <Field label="Bitcoin node URL">
          <input className="input mono" value={btcUrl} onChange={e => setBtcUrl(e.target.value)} />
        </Field>
        <Field label="Liquid node URL">
          <input className="input mono" value={lqUrl} onChange={e => setLqUrl(e.target.value)} />
        </Field>
        <div className="row" style={{marginTop: 12}}>
          <Btn size="sm" onClick={test}>{testing ? "testing…" : "test connection"}</Btn>
        </div>
      </Card>
      <Card style={{marginTop: 14}}>
        <div className="set-row" style={{paddingTop: 0}}>
          <div className="grow">
            <div className="t">Auto sync</div>
            <div className="d">Poll the nodes on a timer while the app is open.</div>
          </div>
          <Switch on={auto} onChange={setAuto} />
        </div>
        {auto && (
          <div className="set-row">
            <div className="grow"><div className="t">Every</div></div>
            <select className="input" style={{width: 130}} value={every} onChange={e => setEvery(e.target.value)}>
              <option value="30">30 s</option><option value="60">60 s</option><option value="300">5 min</option>
            </select>
          </div>
        )}
        <div className="set-row">
          <div className="grow">
            <div className="t">Route through Tor <Pill tone="violet" style={{marginLeft: 6}}>coming soon</Pill></div>
            <div className="d">Onion routing for node connections.</div>
          </div>
          <Switch on={false} disabled />
        </div>
      </Card>
    </React.Fragment>
  );
}

function SecuritySection() {
  const [pw, setPw] = useState(true);
  const [autolock, setAutolock] = useState("10");
  const [locked, setLocked] = useState(false);

  return (
    <React.Fragment>
      <h2 className="h2" style={{marginTop: 0}}>Security</h2>
      <Card>
        <div className="set-row" style={{paddingTop: 0}}>
          <div className="grow">
            <div className="t">Require password to log in</div>
            <div className="d">Wallet files stay encrypted either way; this gates the UI.</div>
          </div>
          <Switch on={pw} onChange={v => { setPw(v); window.toast?.(v ? "Password required at launch" : "Password prompt disabled"); }} />
        </div>
        <div className="set-row">
          <div className="grow">
            <div className="t">Auto-lock after</div>
            <div className="d">Idle time before the app locks itself.</div>
          </div>
          <select className="input" style={{width: 130}} value={autolock} onChange={e => setAutolock(e.target.value)}>
            <option value="5">5 min</option><option value="10">10 min</option><option value="30">30 min</option><option value="0">never</option>
          </select>
        </div>
        <div className="set-row">
          <div className="grow">
            <div className="t">Lock now</div>
            <div className="d">Immediately requires the password again.</div>
          </div>
          <Btn size="sm" onClick={() => setLocked(true)}>🔒 Lock app</Btn>
        </div>
      </Card>

      {locked && (
        <Modal title="Templar is locked" onClose={() => setLocked(false)}
          foot={<Btn variant="primary" fill onClick={() => { setLocked(false); window.toast?.("Unlocked"); }}>Unlock</Btn>}>
          <div style={{textAlign: "center", padding: "10px 0 4px"}}>
            <div style={{fontSize: 34, marginBottom: 10}}>🔒</div>
            <Field label="Password">
              <input className="input lg mono" type="password" autoFocus placeholder="••••••••" onKeyDown={e => { if (e.key === "Enter") { setLocked(false); window.toast?.("Unlocked"); } }} />
            </Field>
          </div>
        </Modal>
      )}
    </React.Fragment>
  );
}

function AppearanceSection({ theme, setTheme }) {
  const [fiat, setFiat] = useState("USD");
  const [lang, setLang] = useState("English");

  return (
    <React.Fragment>
      <h2 className="h2" style={{marginTop: 0}}>Appearance</h2>
      <Card>
        <span className="label" style={{marginTop: 0}}>Theme</span>
        <div className="g2" style={{maxWidth: 420}}>
          {["light", "dark"].map(t => (
            <Card key={t} tight className={theme === t ? "selected-card" : ""} style={{cursor: "pointer", textAlign: "center"}} onClick={() => setTheme(t)}>
              <div style={{
                height: 44, borderRadius: 6, marginBottom: 8, border: "1px solid var(--line)",
                background: t === "light" ? "linear-gradient(180deg,#F5F5F3 55%,#FFF 55%)" : "linear-gradient(180deg,#13131A 55%,#1C1C26 55%)",
              }} />
              <strong style={{textTransform: "capitalize"}}>{t}</strong>
            </Card>
          ))}
        </div>
        <Field label="Default fiat currency" hint="Used for the ≈ estimates across the app.">
          <select className="input" style={{maxWidth: 200}} value={fiat} onChange={e => { setFiat(e.target.value); window.toast?.(`Estimates now in ${e.target.value}`); }}>
            <option>USD</option><option>EUR</option><option>GBP</option><option>BRL</option><option>CHF</option>
          </select>
        </Field>
        <Field label="Language">
          <select className="input" style={{maxWidth: 200}} value={lang} onChange={e => setLang(e.target.value)}>
            <option>English</option><option>Italiano</option><option>Português</option><option>Español</option>
          </select>
        </Field>
      </Card>
    </React.Fragment>
  );
}

function FeesSection() {
  const [preset, setPreset] = useState("normal");
  const [custom, setCustom] = useState("3.4");
  const [rbf, setRbf] = useState(true);

  return (
    <React.Fragment>
      <h2 className="h2" style={{marginTop: 0}}>Fees defaults</h2>
      <Card>
        <span className="label" style={{marginTop: 0}}>Default fee preset</span>
        <div className="fee-row" style={{maxWidth: 480}}>
          {[
            { id: "slow", label: "Slow", r: "1.0" },
            { id: "normal", label: "Normal", r: "3.4" },
            { id: "fast", label: "Fast", r: "8.2" },
          ].map(f => (
            <button key={f.id} className={`fee-opt ${preset === f.id ? "on" : ""}`} onClick={() => setPreset(f.id)}>
              {f.label} <span className="r">{f.r} sat/vB</span>
            </button>
          ))}
        </div>
        <Field label="Custom fallback rate (sat/vB)" hint="Used when fee estimation is unavailable.">
          <input className="input mono" style={{maxWidth: 160}} value={custom} onChange={e => setCustom(e.target.value)} />
        </Field>
        <div className="set-row">
          <div className="grow">
            <div className="t">Signal RBF by default</div>
            <div className="d">Lets you bump the fee later if a tx gets stuck.</div>
          </div>
          <Switch on={rbf} onChange={setRbf} />
        </div>
      </Card>
    </React.Fragment>
  );
}

function AdvancedSection() {
  const dir = "~/Library/Application Support/TemplarWallet";
  const [verbose, setVerbose] = useState(false);

  return (
    <React.Fragment>
      <h2 className="h2" style={{marginTop: 0}}>Advanced & debug</h2>
      <Card>
        <span className="label" style={{marginTop: 0}}>Wallet storage directory</span>
        <div className="copy-row">
          <CodeBlock value={dir} showCopy={false} />
          <CopyBtn value={dir} label="Copy" />
        </div>
        <div className="set-row" style={{marginTop: 10}}>
          <div className="grow">
            <div className="t">Verbose logging</div>
            <div className="d">Writes sync + RPC traces to templar.log.</div>
          </div>
          <Switch on={verbose} onChange={setVerbose} />
        </div>
        <div className="set-row">
          <div className="grow">
            <div className="t">Export debug bundle</div>
            <div className="d">Logs + config, no keys. For bug reports.</div>
          </div>
          <Btn size="sm" onClick={() => { download("templar-debug.json", JSON.stringify({ version: "0.1.0", network: "testnet", height: 3041142 }, null, 2)); window.toast?.("Debug bundle exported"); }}>⇩ export</Btn>
        </div>
      </Card>
    </React.Fragment>
  );
}

function AboutSection() {
  return (
    <React.Fragment>
      <h2 className="h2" style={{marginTop: 0}}>About</h2>
      <Card style={{textAlign: "center", padding: "36px 24px"}}>
        <div className="sb-mark" style={{margin: "0 auto 12px", width: 44, height: 44}}>
          <svg width="22" height="22" viewBox="0 0 16 16" fill="none">
            <path d="M3 6 Q3 2 8 2 Q13 2 13 6 L13 9 Q12 9 11 10 Q10 9 9 10 Q8 9 7 10 Q6 9 5 10 Q4 9 3 9 Z" fill="#fff" />
            <circle cx="6" cy="6" r="0.9" fill="#534AB7" />
            <circle cx="10" cy="6" r="0.9" fill="#534AB7" />
            <path d="M3.5 10 L3 13 M5.5 10 L5.5 13 M7.5 10 L7.5 13.5 M9.5 10 L9.5 13 M11.5 10 L12 13" stroke="#fff" strokeWidth="0.9" strokeLinecap="round" />
          </svg>
        </div>
        <strong style={{fontSize: 16}}>Templar Wallet</strong>
        <div className="mono dim" style={{fontSize: 12.5, marginTop: 4}}>v0.1.0 · testnet build · rust core 1.78</div>
        <div className="row" style={{justifyContent: "center", marginTop: 18}}>
          <Btn onClick={() => window.toast?.("Would open GitHub docs", "↗")}>▤ Documentation</Btn>
          <Btn onClick={() => window.toast?.("Would open GitHub repo", "↗")}>⌥ Source code</Btn>
        </div>
        <p className="help" style={{marginTop: 16}}>MIT licensed. Keys never leave this machine.</p>
      </Card>
    </React.Fragment>
  );
}

function SettingsScreen({ go, setWalletId, theme, setTheme }) {
  const [sec, setSec] = useState("wallets");

  return (
    <React.Fragment>
      <Topbar title="Settings" sub="Manage wallets, network and app preferences" />
      <div className="canvas">
        <div className="set-shell">
          <div className="set-list">
            {SECTIONS.map(s => (
              <div key={s.id} className={`tile ${sec === s.id ? "active" : ""}`} onClick={() => setSec(s.id)}>
                <span className="mono" style={{width: 18, textAlign: "center", fontSize: 12}}>{s.i}</span>
                {s.t}
              </div>
            ))}
          </div>
          <div>
            {sec === "wallets" && <WalletsSection go={go} setWalletId={setWalletId} />}
            {sec === "network" && <NetworkSection />}
            {sec === "security" && <SecuritySection />}
            {sec === "appearance" && <AppearanceSection theme={theme} setTheme={setTheme} />}
            {sec === "fees" && <FeesSection />}
            {sec === "advanced" && <AdvancedSection />}
            {sec === "about" && <AboutSection />}
          </div>
        </div>
      </div>
    </React.Fragment>
  );
}

(window.WSCREENS = window.WSCREENS || {}).settings = SettingsScreen;
})();
