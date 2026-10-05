// Steal and Murder analytics server (Render web service + Neon Postgres).
//   POST /ingest      batches from Roblox game servers (header X-Ingest-Key = INGEST_KEY)
//   GET  /            the dashboard (basic auth: any user name, password = DASH_PASSWORD)
//   GET  /health      for Render's health check
// Env: DATABASE_URL, INGEST_KEY, DASH_PASSWORD, PORT (Render sets it).
import { createServer } from "node:http";
import { timingSafeEqual } from "node:crypto";
import { ingest } from "./ingest.js";
import * as Q from "./queries.js";
import { syncAll } from "./sync.js";
import { bar, card, esc, n, page, pct, secs, table } from "./views.js";

const INGEST_KEY = process.env.INGEST_KEY || "";
const DASH_PASSWORD = process.env.DASH_PASSWORD || "";
const MAX_BODY = 4 * 1024 * 1024;

function same(a, b) {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY) {
        reject(new Error("too large"));
        req.destroy();
      } else chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function send(res, status, body, type = "text/html; charset=utf-8", headers = {}) {
  res.writeHead(status, { "Content-Type": type, "Cache-Control": "no-store", ...headers });
  res.end(body);
}

function authorized(req) {
  if (!DASH_PASSWORD) return false; // no password set = dashboard closed
  const header = req.headers.authorization || "";
  if (!header.startsWith("Basic ")) return false;
  const decoded = Buffer.from(header.slice(6), "base64").toString("utf8");
  const password = decoded.slice(decoded.indexOf(":") + 1);
  return same(password, DASH_PASSWORD);
}

// Roblox reports rates either as fractions or as percentages: show both the same way
function rate(v) {
  if (v === null || v === undefined) return "–";
  const x = Number(v);
  return `${(x <= 1.0001 ? x * 100 : x).toFixed(1)}%`;
}

let robloxState = null; // { rb, universeId, running } when ROBLOX_API_KEY is set

async function robloxCard(days) {
  const rows = await Q.robloxSummary(days);
  if (!rows.length) {
    return card(
      "Before they join (Roblox)",
      `<p class="muted">${robloxState ? 'No Roblox analytics synced yet (it runs every 6 h; <a href="/sync">sync now</a>).' : "Set ROBLOX_API_KEY on the server to pull Roblox's impressions, clicks and plays."}</p>`,
    );
  }
  const m = Object.fromEntries(rows.map((r) => [r.metric, r.v]));
  const imp = m.UniqueUsersWithImpressions;
  const clk = m.UniqueUsersWithClicks;
  const play = m.UniqueUsersWithPlaySessions;
  const step = (label, value, of) =>
    `<tr><td>${label}</td><td>${n(value)}</td><td style="width:40%">${bar(imp ? (value || 0) / imp : 0)}</td><td>${of ? pct(value, of) : ""}</td></tr>`;
  const funnel = `<div class="scroll"><table class="funnel"><thead><tr><th>Step</th><th>People</th><th></th><th>From previous</th></tr></thead><tbody>
    ${step("Saw the game (impressions)", imp)}${step("Clicked it", clk, imp)}${step("Played", play, clk)}</tbody></table></div>`;
  const kpi = (value, label) => `<div class="kpi"><b>${value}</b><span>${label}</span></div>`;
  const kpis = `<div class="kpis" style="margin-top:12px">
    ${kpi(rate(m.ImpressionCVR), "impression → click")}
    ${kpi(rate(m.EndToEndCVR), "impression → play")}
    ${kpi(rate(m.RFYPlayThroughRate), "Recommended-for-you play-through")}
    ${kpi(rate(m.ForwardD1Retention), "Roblox D1")}
    ${kpi(rate(m.ForwardD7Retention), "Roblox D7")}
    ${kpi(m.AverageSessionLengthMinutes ? `${Number(m.AverageSessionLengthMinutes).toFixed(1)}m` : "–", "avg session (Roblox)")}
    ${kpi(n(m.PeakConcurrentPlayers), "peak players (avg/day)")}
    ${kpi(rate(m.ClientCrashRate15m), "crash rate")}
  </div>`;
  return card("Before they join (Roblox)", funnel + kpis, "Roblox's own numbers for the same window: everything that happens before our analytics can see a player.");
}

// ---------------------------------------------------------------------------------------------
// Pages

async function overviewPage(days) {
  const o = await Q.overview(days);
  const funnel = await Q.firstSession(days);
  const kpi = (value, label) => `<div class="kpi"><b>${value}</b><span>${label}</span></div>`;
  const kpis = `<div class="kpis">
    ${kpi(n(o.new_players), "new players")}
    ${kpi(n(o.active_players), "players active")}
    ${kpi(n(o.sessions), "visits")}
    ${kpi(`${o.median_min ?? "–"}m`, "median visit")}
    ${kpi(pct(o.d1, o.d1_cohort), `back next day (D1, n=${o.d1_cohort})`)}
    ${kpi(pct(o.d7, o.d7_cohort), `back on day 7 (D7, n=${o.d7_cohort})`)}
    ${kpi(n(o.payers), `payers (${pct(o.payers, o.active_players)})`)}
    ${kpi(`R$${n(o.robux)}`, "Robux spent")}
  </div>`;
  const worst = funnel.worst;
  const leak = worst
    ? card(
        "🚨 Biggest leak",
        `<p><b>${esc(funnel.steps[worst.index - 1].label)}</b> → <b>${esc(worst.label)}</b> loses
         <b class="bad">${n(worst.lost)}</b> new players (${pct(worst.lost, funnel.steps[worst.index - 1].players)} of those who got that far).</p>
         <p><a href="/stall/${esc(worst.id)}?days=${days}">See what those players did instead →</a></p>`,
      )
    : "";
  const rows = funnel.steps.map((s, i) => {
    const drop = i > 0 && s.fromPrev !== null ? 1 - s.fromPrev : 0;
    const tone = drop >= 0.3 ? "bad" : drop >= 0.15 ? "warn" : "accent";
    return `<tr class="${worst && worst.id === s.id ? "worst" : ""}">
      <td>${i > 0 ? `<a href="/stall/${esc(s.id)}?days=${days}">${esc(s.label)}</a>` : esc(s.label)}</td>
      <td>${n(s.players)}</td><td style="width:40%">${bar(s.ofStart, tone)}</td>
      <td>${pct(s.players, funnel.steps[0].players)}</td>
      <td class="${drop >= 0.3 ? "bad" : ""}">${i > 0 ? (s.fromPrev === null ? "–" : `−${(drop * 100).toFixed(0)}%`) : ""}</td>
      <td class="muted">${secs(s.medianSeconds)}</td></tr>`;
  });
  const funnelTable = `<div class="scroll"><table class="funnel"><thead><tr><th>Step</th><th>Players</th><th></th><th>Of joined</th><th>Lost here</th><th>Median time to reach</th></tr></thead><tbody>${rows.join("")}</tbody></table></div>`;
  return `<h1>Overview</h1>${kpis}${leak}${await robloxCard(days)}${card(
    "First-session funnel",
    funnelTable,
    "New players in this window. Click a step to see what the people who never reached it did instead.",
  )}`;
}

async function stallPage(days, step) {
  const s = await Q.stalledAt(days, step);
  if (!s) return `<h1>Unknown step</h1>`;
  const t = (rows, cols) => table(cols.map((c) => c[0]), rows.map((r) => cols.map((c) => c[1](r))));
  return `<h1>Stalled before “${esc(s.step[1])}”</h1>
  <p class="muted">${n(s.players)} new players reached “${esc(s.prev[1])}” but never “${esc(s.step[1])}”.</p>
  <div class="grid2">
  ${card("Last thing before they quit", t(s.lastThing, [["Last event", (r) => `<code>${esc(r.last_event)}</code>`], ["Players", (r) => n(r.players)], ["Avg visit", (r) => `${r.avg_min ?? "–"}m`]]), "From the end of their latest visit.")}
  ${card("Their final few actions", t(s.lastEvents, [["Event", (r) => `<a href="/explore?days=${days}&event=${encodeURIComponent(r.event)}"><code>${esc(r.event)}</code></a>`], ["Players", (r) => n(r.players)]]), "The last 5 meaningful events of each of them.")}
  ${card("Red messages they got", t(s.messages, [["Message", (r) => esc(r.message)], ["Players", (r) => n(r.players)], ["Times", (r) => n(r.times)]]))}
  ${card("Things they tried that failed", t(s.failed, [["Action", (r) => `<code>${esc(r.event)}</code> ${esc(r.what)}`], ["Server said", (r) => esc(r.reply)], ["Players", (r) => n(r.players)]]))}
  ${card("Their devices", t(s.platforms, [["Platform", (r) => esc(r.platform)], ["Players", (r) => n(r.players)]]))}
  </div>`;
}

async function loopsPage(days) {
  const [steals, snatches, holds, rounds, store, economy] = await Promise.all([
    Q.steals(days),
    Q.snatches(days),
    Q.holds(days),
    Q.rounds(days),
    Q.store(days),
    Q.economy(days),
  ]);
  // Steal loop: one row per zone
  const zones = new Map();
  const get = (z) => zones.get(z) || zones.set(z, { zone: z, outcomes: {}, holds: 0, snatches: 0, tooSlow: 0 }).get(z);
  for (const r of steals) get(r.zone).outcomes[r.event] = { n: r.n, avg: r.avg_s };
  for (const r of holds) get(r.zone).holds = r.holds;
  for (const r of snatches) Object.assign(get(r.zone), { snatches: r.snatches, tooSlow: r.too_slow });
  const outcomeNames = ["steal.home", "steal.caught", "steal.knocked", "steal.died", "steal.slipped", "steal.vault_full", "steal.moon", "steal.left"];
  const stealRows = [...zones.values()]
    .sort((a, b) => a.zone - b.zone)
    .map((z) => {
      const started = z.outcomes["steal.start"]?.n || 0;
      const home = z.outcomes["steal.home"]?.n || 0;
      return [
        `Zone ${z.zone}`,
        n(z.holds),
        n(started),
        `${pct(home, started)} ${bar(started ? home / started : 0, "good")}`,
        ...outcomeNames.slice(1).map((o) => n(z.outcomes[o]?.n || 0)),
        z.snatches ? `${pct(z.tooSlow, z.snatches)}` : "–",
        secs(z.outcomes["steal.home"]?.avg),
      ];
    });
  const stealTable = table(
    ["Zone", "Held E", "Grabbed", "Got home", "Caught", "Knocked", "Died", "Slipped", "Vault full", "Moon", "Left", "Caught while too slow", "Avg run"],
    stealRows,
  );
  const roundTable = table(
    ["Role", "Played", "Won", "Survived", "Avg kills", "Knife out after"],
    rounds.byRole.map((r) => [esc(r.role), n(r.played), `${r.won_pct}%`, `${r.survived_pct}%`, r.avg_kills ?? "–", secs(r.knife_out_s)]),
  );
  const storeTable = table(
    ["Product", "Offered", "Not shown", "Clicked", "Prompted", "Bought", "Robux", "Offer → buy"],
    store.map((r) => [esc(r.key), n(r.shown), n(r.blocked), n(r.clicked), n(r.prompts), n(r.bought), `R$${n(r.robux)}`, pct(r.bought, r.shown)]),
  );
  const flows = economy.filter((r) => r.key.startsWith("in_"));
  const sinks = economy.filter((r) => r.key.startsWith("out_"));
  const flowTable = (rows) => {
    const total = rows.reduce((a, r) => a + r.total, 0);
    return table(["Reason", "Amount", "Share"], rows.map((r) => [esc(r.key.slice(r.key.indexOf("_") + 1)), `$${n(r.total)}`, `${pct(r.total, total)} ${bar(total ? r.total / total : 0)}`]));
  };
  return `<h1>Game loops</h1>
  ${card("Steal loop (boss knives)", stealTable, "Every boss steal and how it ended, by zone. “Caught while too slow” = their Speed was below the zone's SpeedNeeded.")}
  <div class="grid2">
  ${card("Murder rounds", `${roundTable}<p class="muted">${n(rounds.started)} round starts · ${n(rounds.quits?.quit_mid_round)} visits ended mid-round (${pct(rounds.quits?.quit_mid_round, rounds.quits?.sessions)} of visits)</p>`)}
  ${card("Store & offers", storeTable, "Offered = the server showed an offer; Not shown = the client held it back (menu open, in a round, owned).")}
  ${card("Cash in", flowTable(flows))}
  ${card("Cash out", flowTable(sinks))}
  </div>`;
}

async function playersPage(days) {
  const [robloxDaily, bySource, adCampaigns, syncs] = await Promise.all([
    Q.robloxDaily(Math.min(days, 30)),
    Q.robloxBy(days, "AcquisitionSource"),
    Q.campaignList(),
    Q.syncStatus(),
  ]);
  const rd = {};
  for (const r of robloxDaily) (rd[r.day] ||= {})[r.metric] = r.v;
  const [daily, cohorts, campaigns, churn, friction, perf] = await Promise.all([
    Q.daily(Math.min(days, 30)),
    Q.cohorts(),
    Q.campaigns(days),
    Q.churn(days),
    Q.friction(days),
    Q.performance(days),
  ]);
  const cell = (part, whole, ready) => (ready ? `${pct(part, whole)}` : `<span class="muted">…</span>`);
  const cohortTable = table(
    ["First day", "New players", "D1", "D3", "D7"],
    cohorts.map((r) => [esc(r.day), n(r.players), cell(r.d1, r.players, r.age >= 1), cell(r.d3, r.players, r.age >= 3), cell(r.d7, r.players, r.age >= 7)]),
  );
  const spendBy = new Map();
  for (const s of campaigns.spend) {
    const row = spendBy.get(s.campaign) || { spend: 0, impressions: 0, clicks: 0, channels: [] };
    row.spend += s.spend;
    row.impressions += s.impressions || 0;
    row.clicks += s.clicks || 0;
    row.channels.push(s.channel);
    spendBy.set(s.campaign, row);
  }
  const campaignRows = campaigns.players.map((r) => {
    const s = spendBy.get(r.campaign);
    const retained = r.d1;
    return [
      `${esc(r.campaign)} <span class="muted">${esc(r.source)}</span>`,
      n(r.players),
      pct(r.d1, r.d1_cohort),
      `${r.avg_total_min ?? "–"}m`,
      `R$${n(r.robux)}`,
      s ? `$${s.spend.toFixed(2)}` : "–",
      s && r.players ? `$${(s.spend / r.players).toFixed(3)}` : "–",
      s && retained ? `$${(s.spend / retained).toFixed(2)}` : "–",
      s && s.clicks ? pct(s.clicks, s.impressions) : "–",
    ];
  });
  const campaignTable = table(
    ["Campaign", "Players", "D1", "Avg time played", "Robux", "Spend", "Cost / player", "Cost / D1 player", "Ad CTR"],
    campaignRows,
  );
  const churnTable = table(
    ["Last thing they did", "Visits ended", "First visits", "Avg visit"],
    churn.map((r) => [`<code>${esc(r.last_event)}</code>`, n(r.sessions), n(r.first_visits), `${r.avg_min ?? "–"}m`]),
  );
  const msgTable = table(["Red message", "Players", "Times"], friction.messages.map((r) => [esc(r.message), n(r.players), n(r.times)]));
  const failTable = table(
    ["Failed action", "Server said", "Players", "Times"],
    friction.failed.map((r) => [`<code>${esc(r.event)}</code> ${esc(r.what)}`, esc(r.reply), n(r.players), n(r.times)]),
  );
  const perfTable = table(
    ["Platform", "Loads", "Loading p50", "Loading p90", "Gave up loading", "FPS p50", "Worst-second FPS p10", "Ping p50"],
    perf.map((r) => [esc(r.platform), n(r.loads), secs(r.load_p50), secs(r.load_p90), n(r.load_gave_up), r.fps_p50 ?? "–", r.worst_fps_p10 ?? "–", r.ping_p50 ? `${r.ping_p50}ms` : "–"]),
  );
  const dailyTable = table(
    ["Day", "Roblox impressions", "Roblox plays", "New players", "Back next day", "Visits", "Robux", "Ad spend", "Cost / new player", "Cost / D1 player"],
    daily.map((r) => [
      esc(r.day),
      n(rd[r.day]?.UniqueUsersWithImpressions),
      n(rd[r.day]?.UniqueUsersWithPlaySessions),
      n(r.new_players),
      r.age >= 1 ? pct(r.d1, r.new_players) : `<span class="muted">…</span>`,
      n(r.visits),
      `R$${n(r.robux)}`,
      r.spend ? `$${r.spend.toFixed(2)}${r.roblox_spend ? ` <span class="muted">(Roblox $${r.roblox_spend.toFixed(2)})</span>` : ""}` : "–",
      r.spend && r.new_players ? `$${(r.spend / r.new_players).toFixed(3)}` : "–",
      r.spend && r.d1 ? `$${(r.spend / r.d1).toFixed(2)}` : "–",
    ]),
  );
  const sources = {};
  for (const r of bySource) (sources[r.value] ||= {})[r.metric] = r.v;
  const sourceTable = table(
    ["Where they came from", "Saw it", "Played", "Roblox D1"],
    Object.entries(sources)
      .sort((a, b) => (b[1].UniqueUsersWithPlaySessions || 0) - (a[1].UniqueUsersWithPlaySessions || 0))
      .map(([source, m]) => [esc(source), n(m.UniqueUsersWithImpressions), n(m.UniqueUsersWithPlaySessions), rate(m.ForwardD1Retention)]),
  );
  const campaignTable2 = table(
    ["Roblox campaign", "Status", "Delivery", "Budget", "Objective", "Why"],
    adCampaigns.map((c) => [
      esc(c.name),
      esc(c.status),
      `<span class="${c.delivery === "SERVING" ? "good" : c.delivery === "REJECTED" ? "bad" : ""}">${esc(c.delivery)}</span>`,
      c.budget_usd !== null ? `$${Number(c.budget_usd).toFixed(2)} ${esc((c.budget_type || "").toLowerCase())}` : "–",
      esc(c.objective),
      esc((c.reasons || []).join(", ")),
    ]),
  );
  const syncTable = table(
    ["Sync", "OK", "Detail", "When"],
    syncs.map((r) => [esc(r.job), r.ok ? `<span class="good">✓</span>` : `<span class="bad">✗</span>`, esc(r.detail), esc(r.at)]),
  );
  return `<h1>Players & ads</h1>
  ${card("Day by day", dailyTable, "Every new player that day against every dollar spent that day: the way to judge ads that can't tag players (Roblox Ads Manager).")}
  <div class="grid2">
  ${card("Retention by first day", cohortTable, "Share of each day's new players who came back exactly 1, 3 and 7 days later (UTC).")}
  ${card("Why visits end", churnTable, "The last thing that happened before a player left.")}
  </div>
  ${card("Campaigns (first touch)", campaignTable, "From launchData utm_* on the ad link. Spend comes from the Ad spend page.")}
  <div class="grid2">
  ${card("Red messages (friction)", msgTable)}
  ${card("Failed actions", failTable)}
  </div>
  ${card("Performance", perfTable)}
  <div class="grid2">
  ${card("Roblox: by acquisition source", sourceTable, "Home page, search, sponsored ads, friends...: Roblox's split, so you can see whether ad players stick.")}
  ${card("Roblox Ads Manager campaigns", campaignTable2, "Status from the Ads Manager API (Roblox doesn't report spend through it yet: enter spend on the Ad spend page).")}
  </div>
  ${card("Syncs", `${syncTable}<p><a href="/sync">Sync Roblox now</a></p>`)}`;
}

async function explorePage(days, event, by) {
  if (!event) {
    const list = await Q.eventList(days);
    return `<h1>Explorer</h1>${card(
      "Every event",
      table(["Event", "Count", "Players"], list.map((r) => [`<a href="/explore?days=${days}&event=${encodeURIComponent(r.event)}"><code>${esc(r.event)}</code></a>`, n(r.n), n(r.players)])),
      "Click an event, then split it by any of its fields, by device, by campaign or by A/B group.",
    )}`;
  }
  const keys = await Q.eventKeys(days, event);
  const splits = [["@platform", "device"], ["@campaign", "campaign"], ["@new_user", "new vs returning"], ["@visit", "visit #"], ...keys.map((k) => [k.key, k.key])];
  const link = (key, label) =>
    `<a class="tag" ${key === by ? 'style="outline:2px solid var(--accent)"' : ""} href="/explore?days=${days}&event=${encodeURIComponent(event)}&by=${encodeURIComponent(key)}">${esc(label)}</a>`;
  let result = `<p class="muted">Pick a field to split by.</p>`;
  if (by) {
    const split = await Q.eventSplit(days, event, by);
    const total = split.rows.reduce((a, r) => a + r.n, 0);
    result = table(["Value", "Count", "Players", "Share"], split.rows.map((r) => [esc(r.value), n(r.n), n(r.players), `${pct(r.n, total)} ${bar(total ? r.n / total : 0)}`]));
    if (split.numeric) {
      const m = split.numeric;
      result = `<p>p10 <b>${n(m.p10)}</b> · median <b>${n(m.p50)}</b> · p90 <b>${n(m.p90)}</b> · avg <b>${n(m.avg)}</b> <span class="muted">(n=${n(m.n)})</span></p>${result}`;
    }
  }
  return `<h1><code>${esc(event)}</code></h1><p><a href="/explore?days=${days}">← all events</a></p>
  ${card("Split by", splits.map(([k, l]) => link(k, l)).join(" "))}${card(by ? `By ${esc(by)}` : "Breakdown", result)}`;
}

async function spendPage(days, message = "") {
  const rows = await Q.spendList();
  const today = new Date().toISOString().slice(0, 10);
  const form = `<form method="post" action="/spend">
    <label>Day<input type="date" name="day" value="${today}" required></label>
    <label>Channel<select name="channel"><option>meta</option><option>roblox</option><option>tiktok</option><option>youtube</option><option>other</option></select></label>
    <label>Campaign (utm_campaign)<input name="campaign" required></label>
    <label>Spend ($)<input name="spend" type="number" step="0.01" required></label>
    <label>Impressions<input name="impressions" type="number"></label>
    <label>Clicks<input name="clicks" type="number"></label>
    <button>Save</button></form>`;
  return `<h1>Ad spend</h1>${message ? `<p class="good">${esc(message)}</p>` : ""}
  ${card("Add a day", form, "One row per day, channel and campaign (saving the same one again replaces it). The campaign must match the utm_campaign in that ad's launchData.")}
  ${card("Entered", table(["Day", "Channel", "Campaign", "Spend", "Impressions", "Clicks", "CTR"], rows.map((r) => [r.day, esc(r.channel), esc(r.campaign), `$${r.spend.toFixed(2)}`, n(r.impressions), n(r.clicks), pct(r.clicks, r.impressions)])))}`;
}

// ---------------------------------------------------------------------------------------------

async function handle(req, res) {
  const url = new URL(req.url, "http://x");
  const path = url.pathname;

  if (path === "/health") return send(res, 200, "ok", "text/plain");

  if (path === "/ingest" && req.method === "POST") {
    const key = req.headers["x-ingest-key"];
    if (!INGEST_KEY || typeof key !== "string" || !same(key, INGEST_KEY)) return send(res, 401, "no", "text/plain");
    let body;
    try {
      body = JSON.parse(await readBody(req));
    } catch {
      return send(res, 400, "bad json", "text/plain");
    }
    const count = await ingest(body);
    return send(res, 200, JSON.stringify({ ok: true, count }), "application/json");
  }

  // Ad spend from a sync job: { rows: [{ day, channel, campaign, spend, impressions?, clicks? }] }
  if (path === "/api/spend" && req.method === "POST") {
    const key = req.headers["x-ingest-key"];
    if (!INGEST_KEY || typeof key !== "string" || !same(key, INGEST_KEY)) return send(res, 401, "no", "text/plain");
    let body;
    try {
      body = JSON.parse(await readBody(req));
    } catch {
      return send(res, 400, "bad json", "text/plain");
    }
    let saved = 0;
    for (const row of Array.isArray(body?.rows) ? body.rows.slice(0, 1000) : []) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(row?.day) || typeof row.campaign !== "string" || !Number.isFinite(Number(row.spend))) continue;
      const int = (v) => (Number.isFinite(Number(v)) && v !== null && v !== undefined ? Math.round(Number(v)) : null);
      await Q.saveSpend({
        day: row.day,
        channel: String(row.channel || "other").slice(0, 20),
        campaign: row.campaign.slice(0, 60),
        spend: Number(row.spend),
        impressions: int(row.impressions),
        clicks: int(row.clicks),
      });
      saved++;
    }
    return send(res, 200, JSON.stringify({ ok: true, saved }), "application/json");
  }

  if (!authorized(req)) {
    return send(res, 401, "Login required", "text/plain", { "WWW-Authenticate": 'Basic realm="analytics"' });
  }

  const days = Math.max(1, Math.min(365, parseInt(url.searchParams.get("days") || "7", 10) || 7));
  let title = "Overview";
  let body;
  let extra = {};
  if (path === "/") body = await overviewPage(days);
  else if (path.startsWith("/stall/")) {
    title = "Stalled";
    body = await stallPage(days, decodeURIComponent(path.slice(7)));
  } else if (path === "/loops") {
    title = "Game loops";
    body = await loopsPage(days);
  } else if (path === "/players") {
    title = "Players & ads";
    body = await playersPage(days);
  } else if (path === "/explore") {
    title = "Explorer";
    const event = url.searchParams.get("event") || "";
    const by = url.searchParams.get("by") || "";
    if (event) extra.event = event;
    if (by) extra.by = by;
    body = await explorePage(days, event, by);
  } else if (path === "/sync") {
    title = "Sync";
    if (!robloxState) body = `<h1>Sync</h1><p>ROBLOX_API_KEY isn't set on this server.</p>`;
    else {
      if (!robloxState.running) {
        const state = robloxState;
        state.running = true;
        syncAll(state.rb, state.universeId)
          .catch((err) => console.error("sync", err))
          .finally(() => (state.running = false));
      }
      body = `<h1>Sync started</h1><p>Roblox's numbers take a minute or two (30 queries a minute). <a href="/players?days=${days}">Back</a></p>`;
    }
  } else if (path === "/spend") {
    title = "Ad spend";
    let message = "";
    if (req.method === "POST") {
      const form = new URLSearchParams(await readBody(req));
      const int = (k) => (form.get(k) ? parseInt(form.get(k), 10) : null);
      await Q.saveSpend({
        day: form.get("day"),
        channel: (form.get("channel") || "other").slice(0, 20),
        campaign: (form.get("campaign") || "").trim().slice(0, 60),
        spend: parseFloat(form.get("spend") || "0") || 0,
        impressions: int("impressions"),
        clicks: int("clicks"),
      });
      message = "Saved.";
    }
    body = await spendPage(days, message);
  } else return send(res, 404, "Not found", "text/plain");

  send(res, 200, page({ title, base: path, extra, days, body }));
}

export function createApp(options = {}) {
  robloxState = options.roblox || null;
  return createServer((req, res) => {
    handle(req, res).catch((err) => {
      console.error(err);
      if (!res.headersSent) send(res, 500, "Server error", "text/plain");
    });
  });
}
