// Server-rendered HTML for the dashboard. No client JS needed: every drill-down is a link.

export function esc(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

export function n(value) {
  if (value === null || value === undefined || value === "") return "–";
  const x = Number(value);
  if (!Number.isFinite(x)) return esc(value);
  const abs = Math.abs(x);
  const units = [
    [1e18, "Qn"],
    [1e15, "Qd"],
    [1e12, "T"],
    [1e9, "B"],
    [1e6, "M"],
    [1e3, "K"],
  ];
  for (const [size, suffix] of units) if (abs >= size) return `${(x / size).toFixed(abs / size >= 100 ? 0 : 1)}${suffix}`;
  return Number.isInteger(x) ? String(x) : x.toFixed(1);
}

export function pct(part, whole) {
  if (!whole) return "–";
  return `${((100 * part) / whole).toFixed(1)}%`;
}

export function secs(value) {
  if (value === null || value === undefined) return "–";
  const s = Number(value);
  if (s < 90) return `${Math.round(s)}s`;
  if (s < 5400) return `${(s / 60).toFixed(1)}m`;
  return `${(s / 3600).toFixed(1)}h`;
}

export function bar(ratio, tone = "accent") {
  const width = Math.max(0, Math.min(1, ratio || 0)) * 100;
  return `<div class="bar"><div class="fill ${tone}" style="width:${width.toFixed(1)}%"></div></div>`;
}

export function table(headers, rows) {
  if (!rows.length) return `<p class="empty">No data yet.</p>`;
  return `<div class="scroll"><table><thead><tr>${headers.map((h) => `<th>${h}</th>`).join("")}</tr></thead>
    <tbody>${rows.map((r) => `<tr>${r.map((c) => `<td>${c}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`;
}

export function card(title, body, note = "") {
  return `<section class="card"><h2>${title}</h2>${note ? `<p class="note">${note}</p>` : ""}${body}</section>`;
}

const NAV = [
  ["/", "Overview"],
  ["/loops", "Game loops"],
  ["/players", "Players & ads"],
  ["/explore", "Explorer"],
  ["/spend", "Ad spend"],
];

// base = the page's path, extra = its other query params (kept when switching the date range)
export function page({ title, base, extra = {}, days, body }) {
  const path = base;
  const ranges = [1, 7, 30, 90]
    .map((d) => {
      const href = `${base}?${new URLSearchParams({ ...extra, days: String(d) })}`;
      return `<a class="chip ${d === days ? "on" : ""}" href="${esc(href)}">${d === 1 ? "24h" : `${d}d`}</a>`;
    })
    .join("");
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)} · Steal a Knife</title><style>${CSS}</style></head><body>
<header><div class="brand">🔪 Steal a Knife <span>analytics</span></div>
<nav>${NAV.map(([href, label]) => `<a href="${href}?days=${days}" class="${path.split("?")[0] === href ? "on" : ""}">${label}</a>`).join("")}</nav>
<div class="ranges">${ranges}</div></header>
<main>${body}</main></body></html>`;
}

const CSS = `
:root{--bg:#f6f5fb;--panel:#fff;--ink:#17141f;--muted:#6d6880;--line:#e6e3ef;--accent:#7b3fe4;--good:#14a35f;--bad:#e0413a;--warn:#e69a12;--track:#ece9f5}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#0f0d15;--panel:#1a1723;--ink:#f1eef8;--muted:#a19bb3;--line:#2c2838;--accent:#a77bff;--good:#3ccf8a;--bad:#ff6b63;--warn:#ffb340;--track:#2a2636}}
:root[data-theme="dark"]{--bg:#0f0d15;--panel:#1a1723;--ink:#f1eef8;--muted:#a19bb3;--line:#2c2838;--accent:#a77bff;--good:#3ccf8a;--bad:#ff6b63;--warn:#ffb340;--track:#2a2636}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.45 system-ui,-apple-system,Segoe UI,sans-serif}
header{display:flex;flex-wrap:wrap;gap:12px 20px;align-items:center;padding:14px 16px;border-bottom:1px solid var(--line);background:var(--panel);position:sticky;top:0;z-index:2}
.brand{font-weight:800}.brand span{color:var(--muted);font-weight:500}
nav{display:flex;gap:4px;flex-wrap:wrap}nav a,.chip{color:var(--muted);text-decoration:none;padding:6px 10px;border-radius:8px}
nav a.on,.chip.on{background:var(--track);color:var(--ink);font-weight:600}.ranges{margin-left:auto;display:flex;gap:2px}
main{max-width:1180px;margin:0 auto;padding:16px;display:grid;gap:16px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:16px;min-width:0}
h1{font-size:22px;margin:4px 0}h2{font-size:16px;margin:0 0 10px}.note{color:var(--muted);margin:-4px 0 12px;font-size:13px}
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:10px}
.kpi{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:12px}.kpi b{display:block;font-size:24px}.kpi span{color:var(--muted);font-size:13px}
.leak{border-color:var(--bad);border-width:2px}.leak h2{color:var(--bad)}
.grid2{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,460px),1fr));gap:16px}
.scroll{overflow-x:auto}table{width:100%;border-collapse:collapse;font-size:14px}th{text-align:left;color:var(--muted);font-weight:600;font-size:12px;text-transform:uppercase;letter-spacing:.03em}
th,td{padding:7px 8px;border-bottom:1px solid var(--line);vertical-align:middle}td{font-variant-numeric:tabular-nums}
.bar{height:10px;background:var(--track);border-radius:6px;min-width:80px;overflow:hidden}.fill{height:100%;border-radius:6px}
.fill.accent{background:var(--accent)}.fill.bad{background:var(--bad)}.fill.good{background:var(--good)}.fill.warn{background:var(--warn)}
.funnel td:first-child{min-width:190px}.funnel tr.worst td{background:color-mix(in srgb,var(--bad) 10%,transparent)}
a{color:var(--accent)}.bad{color:var(--bad)}.good{color:var(--good)}.muted{color:var(--muted)}.empty{color:var(--muted)}
.tag{display:inline-block;padding:1px 7px;border-radius:999px;background:var(--track);font-size:12px;margin:2px}
form{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:8px;align-items:end}
input,select,button{font:inherit;padding:8px;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--ink)}button{background:var(--accent);color:#fff;border:0;font-weight:600;cursor:pointer}
code{background:var(--track);padding:1px 5px;border-radius:5px}
`;
