// Shared UI primitives.
const { useState, useEffect, useRef, useMemo } = React;

// ---- Pill ----
function Pill({ tone = "default", dot = false, children, className = "", ...rest }) {
  const cls = `pill ${tone !== "default" ? tone : ""} ${dot ? "dot" : ""} ${className}`.trim();
  return <span className={cls} {...rest}>{children}</span>;
}

// ---- Button ----
function Btn({ variant, size, icon, fill, children, ...rest }) {
  const cls = [
    "btn",
    variant,
    size,
    icon ? "icon" : "",
    fill ? "fill" : "",
  ].filter(Boolean).join(" ");
  return <button className={cls} {...rest}>{children}</button>;
}

// ---- Card ----
function Card({ tone, tight, flat, tabular, className = "", style, children, ...rest }) {
  const cls = ["card", tone, tight && "tight", flat && "flat", tabular && "tabular", className]
    .filter(Boolean).join(" ");
  return <div className={cls} style={style} {...rest}>{children}</div>;
}

// ---- Copy button (toggles label briefly) ----
function CopyBtn({ value, size = "sm", label = "Copy", variant }) {
  const [done, setDone] = useState(false);
  return (
    <Btn
      size={size}
      variant={variant}
      onClick={(e) => {
        e.stopPropagation();
        navigator.clipboard?.writeText(value || "").catch(() => {});
        setDone(true);
        setTimeout(() => setDone(false), 1200);
      }}
      title={value}
    >
      <span className="mono" style={{fontSize: 12}}>{done ? "✓" : "⧉"}</span>
      <span>{done ? "Copied" : label}</span>
    </Btn>
  );
}

// ---- Code block (mono text in a tinted panel, with copy button on top-right) ----
function CodeBlock({ value, showCopy = true, height }) {
  return (
    <div className="code-block" style={height ? {minHeight: height} : null}>
      <div style={{paddingRight: showCopy ? 90 : 0}}>{value}</div>
      {showCopy && (
        <div className="copy-fab">
          <CopyBtn value={value} label="Copy" />
        </div>
      )}
    </div>
  );
}

// ---- Topbar (sits above each screen) ----
function Topbar({ title, sub, right }) {
  return (
    <div className="topbar">
      <div>
        <div className="tb-title">{title}</div>
        {sub && <div className="tb-sub">{sub}</div>}
      </div>
      <div className="tb-right">{right}</div>
    </div>
  );
}

// ---- Stepper ----
function Stepper({ steps, current = 0 }) {
  return (
    <div className="stepper">
      {steps.map((label, idx) => {
        const state = idx < current ? "done" : idx === current ? "active" : "";
        return (
          <React.Fragment key={idx}>
            {idx > 0 && <div className="sep" />}
            <div className={`step ${state}`}>
              <span className="n">{idx < current ? "✓" : idx + 1}</span>
              <span>{label}</span>
            </div>
          </React.Fragment>
        );
      })}
    </div>
  );
}

// ---- Section header ----
function SectionH({ children, right }) {
  return (
    <div className="between" style={{marginTop: 28, marginBottom: 12, gap: 16}}>
      <h2 className="h2" style={{margin: 0, whiteSpace: "nowrap"}}>{children}</h2>
      {right && <div className="row" style={{flexShrink: 0}}>{right}</div>}
    </div>
  );
}

// ---- Field (label + input) ----
function Field({ label, hint, optional, children }) {
  return (
    <div>
      <label className="label" style={{display: "flex", alignItems: "center", gap: 8}}>
        <span>{label}</span>
        {optional && <Pill tone="outline" style={{fontSize: 9, height: 16}}>optional</Pill>}
      </label>
      {children}
      {hint && <div className="help">{hint}</div>}
    </div>
  );
}

// ---- Tone chips ----
const chainPill = (chain) => chain === "LQ"
  ? <Pill tone="lq">L-BTC</Pill>
  : <Pill tone="btc">BTC</Pill>;

// ---- Logos ----
// BTC: orange disc with a ₿ glyph. Bitcoin's currency symbol is in Unicode (U+20BF).
function BtcLogo({ size = 24, ring = true }) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" style={{flexShrink: 0}}>
      <defs>
        <linearGradient id="btcg" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stopColor="#FFB458" />
          <stop offset="100%" stopColor="#F7931A" />
        </linearGradient>
      </defs>
      <circle cx="16" cy="16" r="15" fill="url(#btcg)" />
      {ring && <circle cx="16" cy="16" r="15" fill="none" stroke="rgba(255,255,255,0.25)" strokeWidth="0.6" />}
      <text x="16" y="22.5" textAnchor="middle"
        fontFamily="JetBrains Mono, monospace" fontWeight="700"
        fontSize="18" fill="#fff">₿</text>
    </svg>
  );
}

// Liquid: teal droplet with a horizontal wave-line inside.
function LiquidLogo({ size = 24 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" style={{flexShrink: 0}}>
      <defs>
        <linearGradient id="lqg" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stopColor="#4FB7AF" />
          <stop offset="100%" stopColor="#2E8F8A" />
        </linearGradient>
      </defs>
      {/* droplet shape */}
      <path d="M16 2 C10 11, 5 16, 5 21 a11 11 0 0 0 22 0 C27 16, 22 11, 16 2 Z"
        fill="url(#lqg)" />
      {/* wave */}
      <path d="M9 22 Q12 19, 15 22 T22 22"
        fill="none" stroke="#fff" strokeWidth="1.4" strokeLinecap="round"
        opacity="0.85" />
    </svg>
  );
}

// Asset glyph helper — picks the right logo per ticker.
function AssetGlyph({ ticker, size = 24 }) {
  if (ticker === "BTC") return <BtcLogo size={size} />;
  if (ticker === "L-BTC" || ticker === "LBTC") return <LiquidLogo size={size} />;
  if (ticker === "USDt") return (
    <div style={{
      width: size, height: size, borderRadius: "50%",
      background: "linear-gradient(135deg, #50AF95, #2E8F73)",
      display: "grid", placeItems: "center",
      color: "#fff", fontFamily: "var(--font-mono)", fontWeight: 700, fontSize: size * 0.42,
      flexShrink: 0,
    }}>$</div>
  );
  // generic "your token"
  return (
    <div style={{
      width: size, height: size, borderRadius: "50%",
      background: "var(--grad-violet)",
      display: "grid", placeItems: "center",
      color: "#fff", fontFamily: "var(--font-mono)", fontWeight: 700, fontSize: size * 0.42,
      flexShrink: 0,
    }}>{(ticker || "?")[0]}</div>
  );
}

// ---- Modal ----
function Modal({ title, onClose, wide, foot, children }) {
  useEffect(() => {
    const onKey = (e) => { if (e.key === "Escape") onClose?.(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);
  return (
    <div className="modal-veil" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose?.(); }}>
      <div className={`modal ${wide ? "wide" : ""}`}>
        <div className="modal-h">
          <div className="t">{title}</div>
          <button className="modal-x" onClick={onClose}>✕</button>
        </div>
        {children}
        {foot && <div className="modal-foot">{foot}</div>}
      </div>
    </div>
  );
}

// ---- Toast (global, imperative: toast("Copied")) ----
function ToastHost() {
  const [items, setItems] = useState([]);
  useEffect(() => {
    window.toast = (msg, icon = "✓") => {
      const id = Math.random().toString(36).slice(2);
      setItems(list => [...list, { id, msg, icon }]);
      setTimeout(() => setItems(list => list.filter(t => t.id !== id)), 2400);
    };
    return () => { window.toast = () => {}; };
  }, []);
  return (
    <div className="toast-wrap">
      {items.map(t => (
        <div key={t.id} className="toast"><span className="ic">{t.icon}</span>{t.msg}</div>
      ))}
    </div>
  );
}

// ---- Segmented control ----
function Seg({ options, value, onChange }) {
  return (
    <div className="seg">
      {options.map(o => {
        const opt = typeof o === "string" ? { id: o, label: o } : o;
        return (
          <button
            key={opt.id}
            className={`${value === opt.id ? "on" : ""} ${opt.tone || ""}`.trim()}
            onClick={() => onChange(opt.id)}
          >
            {opt.label}
            {opt.count != null && <span className="ct">({opt.count})</span>}
          </button>
        );
      })}
    </div>
  );
}

// ---- Asset selector tabs ----
function AssetTabs({ assets, value, onChange }) {
  return (
    <div className="atabs">
      {assets.map(a => (
        <button key={a.ticker} className={`atab ${value === a.ticker ? "on" : ""}`} onClick={() => onChange(a.ticker)}>
          <AssetGlyph ticker={a.ticker} size={22} />
          <span>{a.ticker}</span>
        </button>
      ))}
    </div>
  );
}

// ---- Toggle switch ----
function Switch({ on, onChange, disabled }) {
  return <button className={`switch ${on ? "on" : ""}`} disabled={disabled} onClick={() => onChange?.(!on)} />;
}

// ---- Download helper (real file downloads for export mocks) ----
function download(filename, text, type = "application/json") {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([text], { type }));
  a.download = filename;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 5000);
}

window.WUI = {
  Pill, Btn, Card, CopyBtn, CodeBlock, Topbar, Stepper, SectionH, Field, chainPill,
  BtcLogo, LiquidLogo, AssetGlyph,
  Modal, ToastHost, Seg, AssetTabs, Switch, download,
};
Object.assign(window, { Pill, Btn, Card, CopyBtn, CodeBlock, Topbar, Stepper, SectionH, Field, chainPill, BtcLogo, LiquidLogo, AssetGlyph, Modal, ToastHost, Seg, AssetTabs, Switch, download });
