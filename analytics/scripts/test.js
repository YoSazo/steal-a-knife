// End-to-end check without Neon: an in-memory Postgres (PGlite), the real schema, a few hundred
// simulated players sent through POST /ingest exactly like a Roblox server would, then every
// dashboard page rendered. Run: npm test
import { PGlite } from "@electric-sql/pglite";
import { connect, query } from "../src/db.js";

process.env.INGEST_KEY = "test-key";
process.env.DASH_PASSWORD = "test-pass";
process.env.FUNNEL_SINCE = "2000-01-01T00:00:00Z"; // (the test data is dated in the past)
const { createApp } = await import("../src/server.js");
const { client } = await import("../src/roblox.js");
const { syncAll } = await import("../src/sync.js");

await connect({ pglite: new PGlite() });
const app = createApp().listen(0);
const port = app.address().port;
const base = `http://127.0.0.1:${port}`;

let seed = 7;
const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
const pick = (list) => list[Math.floor(rand() * list.length)];

// Simulated players: each first visit walks the funnel and drops out somewhere; some come back
const FUNNEL = ["joined", "spawned", "tutorial_1", "steal_started", "tutorial_2", "knife_home", "tutorial_3", "cash_collected", "tutorial_4", "wheel_trained", "tutorial_done", "round_played", "second_round"];
const events = [];
const DAY = 864e5;
for (let i = 0; i < 300; i++) {
  const player = `p${i.toString(16).padStart(6, "0")}`;
  const firstDay = Math.floor(rand() * 6);
  const campaign = rand() < 0.5 ? "test1" : rand() < 0.5 ? "test2" : null;
  const platform = pick(["phone", "phone", "pc", "tablet"]);
  const visits = rand() < 0.35 ? 2 : 1;
  for (let v = 0; v < visits; v++) {
    const start = Date.now() - (firstDay - v) * DAY - 3600e3;
    if (start > Date.now()) continue;
    const session = `${player}-${v}`;
    let t = start;
    const ev = (event, props = {}) => {
      t += 4000 + rand() * 20000;
      events.push({ event, player, session, server: "abc12345", ts: new Date(Math.min(t, Date.now())).toISOString(), props });
    };
    ev("session.start", { new_user: v === 0, session_n: v + 1, place_version: 12, ...(campaign && v === 0 ? { utm_source: "meta", utm_campaign: campaign } : {}), ab_test: pick(["A", "B"]) });
    ev("client.device", { touch: platform !== "pc", keyboard: platform === "pc", phone: platform === "phone", platform, screen_w: 800, screen_h: 400, quality: 5 });
    ev("client.loaded", { seconds: 4 + rand() * (platform === "phone" ? 30 : 10) });
    let last = "client.loaded";
    if (v === 0) {
      const reach = Math.floor(rand() * FUNNEL.length * 1.3);
      for (let s = 0; s < Math.min(reach, FUNNEL.length); s++) {
        ev("milestone", { milestone: FUNNEL[s], playtime_s: s * 30 });
        if (FUNNEL[s] === "steal_started") {
          ev("boss.hold", { zone: 1 });
          ev("steal.start", { source: "boss", zone: 1, knife: "Rusty", rarity: "Common", seconds: 0 });
          if (rand() < 0.3) {
            ev("boss.snatch", { zone: 1, too_slow: true });
            ev("steal.caught", { source: "boss", zone: 1, seconds: 6 });
            ev("notify.bad", { message: "Frank caught you and took the Rusty back!" });
            last = "steal.caught";
          }
        }
        if (FUNNEL[s] === "knife_home") ev("steal.home", { source: "boss", zone: 1, seconds: 11 });
        if (FUNNEL[s] === "tutorial_5") {
          ev("upgrade", { kind: "Treadmill", ok: rand() < 0.6, reply: "Not enough cash" });
          ev("offer.shown", { key: "CashPotion", reason: "Short on cash" });
          if (rand() < 0.3) {
            ev("offer.click", { key: "CashPotion" });
            ev("store.prompt", { kind: "Product", key: "CashPotion", source: "offer" });
            const bought = rand() < 0.4;
            ev("store.result", { kind: "Product", key: "CashPotion", bought });
            if (bought) ev("purchase.product", { key: "CashPotion", robux: 49 });
          }
        }
        if (FUNNEL[s] === "round_played") {
          const role = pick(["innocent", "innocent", "murderer", "sheriff"]);
          ev("round.start", { round_id: "r1", role });
          ev("round.end", { round_id: "r1", role, won: rand() < 0.5, survived: rand() < 0.5, kills: role === "murderer" ? 3 : undefined, knife_out_s: 30 });
        }
        last = FUNNEL[s] === "round_played" ? "round.end" : last;
      }
    } else {
      ev("milestone", { milestone: "session_2", playtime_s: 600 });
    }
    ev("ui.menu", { menu: "Store" });
    ev("ui.click", { button: "StoreButton", menu: "hud" });
    ev("perf", { fps: 40 + rand() * 20, fps_min: 10 + rand() * 20, ping: 80 + rand() * 100 });
    ev("economy.flow", { in_income: 1000 * rand(), in_round_pay: 300, out_upgrade_wheel: 500 });
    ev("session.heartbeat", { robux_total: 0, rebirths: 0 });
    ev("session.end", { seconds: Math.round((t - start) / 1000), last_event: last, last_event_ago: 5, in_round: rand() < 0.05, earned: 5000, spent: 2000, robux: 0, robux_total: 0, rebirths: 0 });
  }
}

const post = (body, key = "test-key") =>
  fetch(`${base}/ingest`, { method: "POST", headers: { "Content-Type": "application/json", "X-Ingest-Key": key }, body: JSON.stringify(body) });

const failures = [];
const check = (ok, what) => (ok ? null : failures.push(what));

// Wrong key, bad body
check((await post({ batch: [] }, "nope")).status === 401, "wrong key accepted");
check((await fetch(`${base}/ingest`, { method: "POST", headers: { "X-Ingest-Key": "test-key" }, body: "{" })).status === 400, "bad json not 400");

// The data, in batches of 250 like the game server sends
for (let i = 0; i < events.length; i += 250) {
  const res = await post({ batch: events.slice(i, i + 250) });
  check(res.status === 200, `batch ${i} -> ${res.status}`);
}
const [{ count }] = await query("select count(*)::int as count from events");
check(count === events.length, `stored ${count} of ${events.length}`);
await fetch(`${base}/spend`, {
  method: "POST",
  headers: { Authorization: `Basic ${Buffer.from("x:test-pass").toString("base64")}`, "Content-Type": "application/x-www-form-urlencoded" },
  body: new URLSearchParams({ day: new Date().toISOString().slice(0, 10), channel: "meta", campaign: "test1", spend: "20", impressions: "40000", clicks: "500" }),
});

// Spend from a sync job (Roblox Ads Manager)
const spendRes = await fetch(`${base}/api/spend`, {
  method: "POST",
  headers: { "Content-Type": "application/json", "X-Ingest-Key": "test-key" },
  body: JSON.stringify({ rows: [{ day: new Date().toISOString().slice(0, 10), channel: "roblox", campaign: "sponsor-1", spend: 20, impressions: 50000, clicks: 900 }, { day: "bad" }] }),
});
check(spendRes.status === 200 && (await spendRes.json()).saved === 1, "api/spend");

// Roblox sync against a fake Open Cloud that answers in the spec's shapes (incl. a pending
// operation that has to be polled, and one metric that fails)
const fakeCalls = [];
const fakeFetch = async (url, init = {}) => {
  const u = new URL(url);
  fakeCalls.push(`${init.method || "GET"} ${u.pathname}`);
  const json = (status, body) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
  if (init.headers?.["x-api-key"] !== "rbx") return json(401, { errorMessage: "bad key" });
  if (u.pathname.endsWith("/metrics") && init.method === "POST") {
    const body = JSON.parse(init.body);
    if (body.metric === "ClientFpsP10") return json(400, { errorMessage: "metric not available" });
    return json(202, { path: `universes/42/operations/metrics/op-${body.metric}-${(body.breakdown || []).join("")}`, done: false });
  }
  if (u.pathname.includes("/operations/metrics/")) {
    const op = u.pathname.split("/").pop();
    const metric = op.split("-")[1];
    const by = op.split("-")[2];
    const days = [0, 1, 2].map((d) => new Date(Date.now() - d * 864e5).toISOString().slice(0, 10) + "T00:00:00Z");
    const base = { UniqueUsersWithImpressions: 40000, UniqueUsersWithClicks: 1400, UniqueUsersWithPlaySessions: 1100 }[metric] ?? 0.31;
    const series = (by ? ["HomePage", "Sponsored"] : [null]).map((value, i) => ({
      breakdowns: value ? [{ dimension: by, value }] : [],
      dataPoints: days.map((time) => ({ time, value: base * (i ? 0.4 : 1) })),
    }));
    return json(200, { path: op, done: true, response: { values: series } });
  }
  if (u.pathname === "/ads-management/v1/campaigns") {
    return json(200, {
      campaigns: [
        { id: "c1", name: "Sponsor test 1", status: "ACTIVE", deliveryStatus: "SERVING", budget: { amountMicros: "20000000", type: "DAILY" }, objective: "PLAYS" },
        { id: "c2", name: "Sponsor test 2", status: "PAUSED", deliveryStatus: "NOT_SERVING", deliveryStatusReasons: ["PAUSED_BY_USER"], budget: { amountMicros: "5000000", type: "DAILY" }, objective: "PLAYS" },
      ],
    });
  }
  return json(404, { errorMessage: "not faked: " + u.pathname });
};
const rb = client({ apiKey: "rbx", fetchImpl: fakeFetch });
const synced = await syncAll(rb, 42, { pace: 0 });
check(synced.failed === 1 && synced.rows > 50 && synced.campaigns === 2, `sync result ${JSON.stringify(synced)}`);
const [{ metrics }] = await query("select count(distinct metric)::int as metrics from roblox_metrics");
check(metrics === 22, `roblox metrics stored: ${metrics}`);
const [{ bad }] = await query("select count(*)::int as bad from sync_log where not ok");
check(bad === 2, `sync_log failures ${bad}`);

// Every page
const auth = { Authorization: `Basic ${Buffer.from("x:test-pass").toString("base64")}` };
check((await fetch(`${base}/`)).status === 401, "dashboard open without a password");
const pages = ["/players?days=7", "/", "/?days=1", "/stall/knife_home", "/stall/tutorial_done", "/loops", "/players", "/explore", "/explore?event=steal.start&by=zone", "/explore?event=client.loaded&by=seconds", "/explore?event=milestone&by=@platform", "/explore?event=session.start&by=@campaign", "/explore?event=milestone&by=@ab:test", "/spend"];
for (const path of pages) {
  const res = await fetch(base + path, { headers: auth });
  const html = await res.text();
  check(res.status === 200, `${path} -> ${res.status}`);
  check(!html.includes("undefined") && !html.includes("NaN"), `${path} shows undefined/NaN`);
  if (path === "/players?days=7") {
    check(html.includes("Sponsor test 1") && html.includes("Sponsored") && html.includes("metric ClientFpsP10"), "players page misses Roblox data");
  }
  if (path === "/") {
    check(html.includes("Biggest leak"), "no leak card");
    const match = html.match(/Biggest leak[\s\S]*?<\/section>/);
    console.log((match ? match[0] : "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim());
    check(html.includes("Saw the game") && html.includes("Clicked it"), "no Roblox funnel on the overview");
  }
}

app.close();
if (failures.length) {
  console.error("FAILED:\n" + failures.join("\n"));
  process.exit(1);
}
console.log(`ok: ${events.length} events, ${pages.length} pages`);
