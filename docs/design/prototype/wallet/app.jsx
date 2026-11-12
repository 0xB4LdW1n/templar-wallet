// Main app: sidebar + screen router.
const { WALLETS, NAV, CHANGE_WALLET } = window.WDATA;

const ALL_SCREEN_IDS = new Set([
  ...NAV.flatMap(g => g.items.map(i => i.id)),
  ...CHANGE_WALLET.map(c => c.id),
]);

function SyncIndicator() {
  const [state, setState] = useState("idle"); // idle | btc | lq
  const [lastSyncMs, setLastSyncMs] = useState(() => Date.now() - 2 * 60 * 1000);
  const [, force] = useState(0);

  // re-render every 30s so "x min ago" stays fresh
  useEffect(() => {
    const t = setInterval(() => force(n => n + 1), 30_000);
    return () => clearInterval(t);
  }, []);

  const trigger = () => {
    if (state !== "idle") return;
    setState("btc");
    setTimeout(() => setState("lq"), 1400);
    setTimeout(() => { setState("idle"); setLastSyncMs(Date.now()); }, 2800);
  };

  const ago = (() => {
    const s = Math.round((Date.now() - lastSyncMs) / 1000);
    if (s < 5) return "just now";
    if (s < 60) return `${s}s ago`;
    const m = Math.round(s / 60);
    if (m < 60) return `${m}m ago`;
    const h = Math.round(m / 60);
    return `${h}h ago`;
  })();

  let label = `synced · ${ago}`;
  if (state === "btc") label = "syncing Bitcoin…";
  if (state === "lq")  label = "syncing Liquid…";

  return (
    <button className={`sb-sync state-${state}`} onClick={trigger} title="Click to sync · BTC + Liquid">
      <span className="sb-sync-ring">
        <span className="sb-sync-dot" />
      </span>
      <span className="sb-sync-label">{label}</span>
    </button>
  );
}
function Sidebar({ current, onPick, wallet, onSwitch, theme, setTheme }) {
  return (
    <aside className="sb">
      <div className="sb-head">
        <div className="sb-mark">
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
            <path d="M3 6 Q3 2 8 2 Q13 2 13 6 L13 9 Q12 9 11 10 Q10 9 9 10 Q8 9 7 10 Q6 9 5 10 Q4 9 3 9 Z"
              fill="#fff" />
            <circle cx="6" cy="6" r="0.9" fill="#534AB7" />
            <circle cx="10" cy="6" r="0.9" fill="#534AB7" />
            <path d="M3.5 10 L3 13 M5.5 10 L5.5 13 M7.5 10 L7.5 13.5 M9.5 10 L9.5 13 M11.5 10 L12 13" stroke="#fff" strokeWidth="0.9" strokeLinecap="round" />
          </svg>
        </div>
        <div className="sb-brand">
          <span className="sb-brand-name">Templar<span className="sb-brand-dot">.</span></span>
          <small>WALLET</small>
        </div>
      </div>

      <div className="sb-switcher" onClick={onSwitch} title="Open wallet picker">
        <div className="sb-switcher-icon">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
            <rect x="3" y="6" width="18" height="14" rx="2.5" stroke="currentColor" strokeWidth="1.7" />
            <path d="M3 9 H21 M3 9 V6 a2 2 0 0 1 2 -2 H17 a2 2 0 0 1 2 2 V6" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
            <circle cx="17" cy="14" r="1.3" fill="currentColor" />
          </svg>
        </div>
        <div className="sb-switcher-body">
          <div className="sb-switcher-row">
            <span className="sb-switcher-name">{wallet.name}</span>
            <span className="sb-switcher-chev">▾</span>
          </div>
          <div className="sb-switcher-meta">
            <span>{wallet.kind}</span>
            <span>·</span>
            <span>{wallet.network}</span>
          </div>
        </div>
      </div>

      <nav className="sb-nav">
        {NAV.map(group => (
          <div key={group.group}>
            <div className="sb-group">{group.group}</div>
            {group.items.map(item => (
              <div
                key={item.id}
                className={`sb-item ${current === item.id ? "active" : ""}`}
                onClick={() => onPick(item.id)}
              >
                <span className="sb-i">{item.i}</span>
                <span>{item.t}</span>
                <span className="sb-num">{item.n}</span>
              </div>
            ))}
          </div>
        ))}
      </nav>

      <div className="sb-change">
        <div className="sb-change-h">Change wallet</div>
        {CHANGE_WALLET.map(c => (
          <button key={c.id} className="sb-change-btn" onClick={() => onPick(c.id)}>
            <span className="ic">{c.i}</span>
            <span>{c.t}</span>
          </button>
        ))}
      </div>

      <div className="sb-foot">
        <SyncIndicator />
        <button
          className="sb-theme-toggle"
          style={{marginLeft: "auto"}}
          title={theme === "dark" ? "Switch to light" : "Switch to dark"}
          onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
        >
          {theme === "dark" ? "☀" : "☾"}
        </button>
        <span>v0.1</span>
      </div>
    </aside>
  );
}

function App() {
  // Start on Home for a meaningful first view.
  const [screen, setScreen] = useState("home");
  const [walletId, setWalletId] = useState("daily");
  const [theme, setTheme] = useState(() => {
    return localStorage.getItem("templar-theme") || "light";
  });
  const wallet = WALLETS.find(w => w.id === walletId) || WALLETS[0];

  const SCREENS = window.WSCREENS || {};

  // Apply theme to <html data-theme>
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    localStorage.setItem("templar-theme", theme);
  }, [theme]);

  // Sync URL hash for direct linking & inspection
  useEffect(() => {
    const h = window.location.hash.slice(1);
    if (h && ALL_SCREEN_IDS.has(h)) setScreen(h);
    const onHash = () => {
      const next = window.location.hash.slice(1);
      if (next && ALL_SCREEN_IDS.has(next)) setScreen(next);
    };
    window.addEventListener("hashchange", onHash);
    return () => window.removeEventListener("hashchange", onHash);
  }, []);

  useEffect(() => {
    if (window.location.hash.slice(1) !== screen) {
      history.replaceState(null, "", "#" + screen);
    }
  }, [screen]);

  const Screen = SCREENS[screen] || (() => <div style={{padding: 40}}>Screen <code>{screen}</code> not yet built.</div>);

  return (
    <div className="app">
      <Sidebar
        current={screen}
        onPick={setScreen}
        wallet={wallet}
        onSwitch={() => setScreen("wallet-picker")}
        theme={theme}
        setTheme={setTheme}
      />
      <main className="main fx-page" key={screen}>
        <Screen
          wallet={wallet}
          go={setScreen}
          setWalletId={setWalletId}
          theme={theme}
          setTheme={setTheme}
        />
      </main>
      <ToastHost />
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
