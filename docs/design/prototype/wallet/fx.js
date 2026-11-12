// Templar Wallet — motion engine (vanilla JS, no framework).
// Auto-decorates the React-rendered DOM via MutationObserver, so screens stay clean:
//   spotlight + 3D tilt on cards · number tickers · staggered entrances ·
//   button ripples · confetti on success. Pure-CSS effects live in animations.css.
(() => {
  "use strict";

  const REDUCED = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (REDUCED) return;

  /* ---------------- decoration rules ---------------- */

  const SPOT_TILT = ".asset-card, .picker-card, .chooser .ch";
  const TILT_ONLY = ".banknote";
  const STAGGER   = ".asset-card, .picker-card, .tl-row, .chooser .ch, .banknote, .hero-chip";
  const TICKER    = ".hero-num, .asset-card .value-lg, .picker-card .value-lg";

  function decorate(root) {
    if (!(root instanceof Element)) return;
    const all = [root, ...root.querySelectorAll("*")];

    let i = 0;
    for (const el of all) {
      if (el.matches(SPOT_TILT) && !el.dataset.fx) {
        el.dataset.fx = "1";
        el.classList.add("fx-spot", "fx-tilt");
        el.dataset.tiltMax = "7";
      } else if (el.matches(TILT_ONLY) && !el.dataset.fx) {
        el.dataset.fx = "1";
        el.classList.add("fx-tilt");
        el.dataset.tiltMax = "3.5";
      }

      if (el.matches(STAGGER) && !el.dataset.fxIn) {
        el.dataset.fxIn = "1";
        el.style.setProperty("--fx-i", Math.min(i++, 14));
        el.classList.add("fx-in");
      }

      if (el.matches(TICKER) && !el.dataset.fxTick) {
        el.dataset.fxTick = "1";
        tick(el);
      }

      if (el.matches(".big-check") && !el.dataset.fxBoom) {
        el.dataset.fxBoom = "1";
        const r = el.getBoundingClientRect();
        confetti(r.left + r.width / 2, r.top + r.height / 2);
      }
    }
  }

  /* ---------------- number ticker ---------------- */

  function tick(el) {
    const raw = el.textContent;
    const m = raw.match(/([\d,]+(?:\.\d+)?)/);
    if (!m) return;
    const target = parseFloat(m[1].replace(/,/g, ""));
    if (!isFinite(target) || target === 0) return;
    const decimals = (m[1].split(".")[1] || "").length;
    const grouped = m[1].includes(",");
    const pre = raw.slice(0, m.index);
    const post = raw.slice(m.index + m[1].length);
    const t0 = performance.now();
    const DUR = 750;

    el.classList.add("fx-tick");
    function frame(t) {
      if (!el.isConnected) return;
      const p = Math.min((t - t0) / DUR, 1);
      const eased = 1 - Math.pow(1 - p, 3); // easeOutCubic
      let v = (target * eased).toFixed(decimals);
      if (grouped) v = Number(v).toLocaleString("en-US", { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
      el.textContent = pre + v + post;
      if (p < 1) requestAnimationFrame(frame);
      else el.textContent = raw; // restore exact original string
    }
    requestAnimationFrame(frame);
  }

  /* ---------------- spotlight + tilt (single delegated listener) ---------------- */

  let tilted = null;
  document.addEventListener("pointermove", (e) => {
    const spot = e.target.closest?.(".fx-spot");
    if (spot) {
      const r = spot.getBoundingClientRect();
      spot.style.setProperty("--mx", (e.clientX - r.left) + "px");
      spot.style.setProperty("--my", (e.clientY - r.top) + "px");
    }
    const t = e.target.closest?.(".fx-tilt");
    if (tilted && tilted !== t) untilt(tilted), (tilted = null);
    if (t) {
      tilted = t;
      const r = t.getBoundingClientRect();
      const max = parseFloat(t.dataset.tiltMax || "6");
      const ry = ((e.clientX - r.left) / r.width - 0.5) * 2 * max;
      const rx = -((e.clientY - r.top) / r.height - 0.5) * 2 * max;
      t.style.setProperty("--rx", rx.toFixed(2) + "deg");
      t.style.setProperty("--ry", ry.toFixed(2) + "deg");
    }
  }, { passive: true });

  document.addEventListener("pointerout", (e) => {
    if (tilted && !tilted.contains(e.relatedTarget)) untilt(tilted), (tilted = null);
  }, { passive: true });

  function untilt(el) {
    el.style.setProperty("--rx", "0deg");
    el.style.setProperty("--ry", "0deg");
  }

  /* ---------------- button ripple ---------------- */

  document.addEventListener("click", (e) => {
    const btn = e.target.closest?.(".btn");
    if (!btn) return;
    const r = btn.getBoundingClientRect();
    const d = Math.max(r.width, r.height);
    const s = document.createElement("span");
    s.className = "fx-ripple";
    s.style.width = s.style.height = d + "px";
    s.style.left = (e.clientX - r.left - d / 2) + "px";
    s.style.top = (e.clientY - r.top - d / 2) + "px";
    if (getComputedStyle(btn).position === "static") btn.style.position = "relative";
    btn.style.overflow = "hidden";
    btn.appendChild(s);
    setTimeout(() => s.remove(), 560);
  }, { passive: true });

  /* ---------------- confetti ---------------- */

  const COLORS = ["#7F77DD", "#534AB7", "#2E8F8A", "#F7931A", "#4FB7AF", "#E66860", "#FFB458"];

  function confetti(x, y) {
    const canvas = document.createElement("canvas");
    canvas.className = "fx-confetti";
    canvas.width = innerWidth;
    canvas.height = innerHeight;
    document.body.appendChild(canvas);
    const ctx = canvas.getContext("2d");

    const parts = Array.from({ length: 90 }, () => {
      const a = Math.random() * Math.PI * 2;
      const v = 4 + Math.random() * 8;
      return {
        x, y,
        vx: Math.cos(a) * v,
        vy: Math.sin(a) * v - 4,
        w: 5 + Math.random() * 6,
        h: 3 + Math.random() * 4,
        rot: Math.random() * Math.PI,
        vr: (Math.random() - 0.5) * 0.35,
        c: COLORS[(Math.random() * COLORS.length) | 0],
        life: 1,
      };
    });

    const t0 = performance.now();
    (function frame(t) {
      const dt = Math.min((t - t0) / 1600, 1);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      for (const p of parts) {
        p.vy += 0.22;               // gravity
        p.vx *= 0.985; p.vy *= 0.985;
        p.x += p.vx; p.y += p.vy;
        p.rot += p.vr;
        p.life = 1 - dt;
        ctx.save();
        ctx.translate(p.x, p.y);
        ctx.rotate(p.rot);
        ctx.globalAlpha = Math.max(p.life, 0);
        ctx.fillStyle = p.c;
        ctx.fillRect(-p.w / 2, -p.h / 2, p.w, p.h);
        ctx.restore();
      }
      if (dt < 1) requestAnimationFrame(frame);
      else canvas.remove();
    })(t0);
  }
  window.fxConfetti = confetti; // screens may trigger manually if they want

  /* ---------------- observe the React root ---------------- */

  new MutationObserver((muts) => {
    for (const m of muts) {
      for (const n of m.addedNodes) decorate(n);
    }
  }).observe(document.getElementById("root") || document.body, { childList: true, subtree: true });

  decorate(document.body);
})();
