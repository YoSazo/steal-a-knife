// One command, everything wired: `npm run setup` (or `npm run setup -- --check` to only look).
// Reads the repo's root .env (see .env.example). Safe to run again: it only fills in what's missing.
//
//   1. Roblox: finds the universe from ROBLOX_PLACE_ID
//   2. Database: checks DATABASE_URL (the Render service creates the tables on start)
//   3. Ingest server: /health + a test event signed with INGEST_KEY (flagged as Studio, so it never
//      shows up in the numbers)
//   4. Game: points Analytics.luau at INGEST_URL
//   5. Roblox secret "ingest_key" (what the game signs its batches with), locked to that domain
//   6. Robux: creates every pass and developer product in Config/Monetization.luau that doesn't exist
//      yet (matched by name) and writes the real ids into the file
//   7. Roblox Analytics Query API and Ads Manager API: checks the key can read them
import { readFileSync, writeFileSync } from "node:fs";
import { resolve, sep } from "node:path";
import { pathToFileURL } from "node:url";
import sodium from "libsodium-wrappers";
import { neon } from "@neondatabase/serverless";
import { env } from "../src/env.js";
import { client } from "../src/roblox.js";

const CHECK_ONLY = process.argv.includes("--check");
// SETUP_ROOT: a copy of the repo to work on (scripts/test-setup.js)
const ROOT = env("SETUP_ROOT") ? pathToFileURL(resolve(env("SETUP_ROOT")) + sep) : new URL("../../", import.meta.url);
const MONETIZATION = new URL("src/shared/Config/Monetization.luau", ROOT);
const ANALYTICS_LUAU = new URL("src/server/Services/Analytics.luau", ROOT);

const results = [];
const icon = { ok: "✓", warn: "!", fail: "✗", skip: "–" };
function report(status, what, detail = "") {
  results.push({ status, what });
  console.log(`${icon[status]} ${what}${detail ? `\n    ${detail.replaceAll("\n", "\n    ")}` : ""}`);
}
const need = (name, why) => {
  const value = env(name);
  if (!value) report("fail", `${name} is not set`, why);
  return value;
};

console.log(`Steal and Murder setup${CHECK_ONLY ? " (check only, nothing changes)" : ""}\n`);

// 1. Roblox --------------------------------------------------------------------------------------
const apiKey = need("ROBLOX_API_KEY", "Creator Hub > Open Cloud > API Keys (see .env.example for the permissions)");
const placeId = env("ROBLOX_PLACE_ID", "119376992331481");
const rb = apiKey ? client({ apiKey }) : null;
let universeId = env("ROBLOX_UNIVERSE_ID");
if (rb && !universeId) {
  try {
    universeId = String(await rb.universeOf(placeId));
    report("ok", `Universe ${universeId} (place ${placeId})`);
  } catch (err) {
    report("fail", "Couldn't find the universe for ROBLOX_PLACE_ID", err.message);
  }
}

// 2. Database ------------------------------------------------------------------------------------
const databaseUrl = need("DATABASE_URL", "Neon > your project > Connection string");
if (databaseUrl) {
  // Over HTTPS (Neon's serverless driver): works even where Postgres' own port is blocked. The
  // server creates the tables itself on start (src/schema.sql), so this only checks.
  try {
    const sql = neon(databaseUrl);
    const [{ ready }] = await sql.query("select to_regclass('events') is not null as ready");
    const count = ready ? (await sql.query("select count(*)::int as n from events where not studio"))[0].n : 0;
    report(ready ? "ok" : "warn", `Database ready (${count} real events so far)`, ready ? "" : "no tables yet: deploy the Render service (it creates them on start)");
  } catch (err) {
    report("fail", "Can't use DATABASE_URL", err.message);
  }
}

// 3. Ingest server -------------------------------------------------------------------------------
let ingestUrl = need("INGEST_URL", "Your Render service's address, e.g. https://stats.yourdomain.com");
const ingestKey = need("INGEST_KEY", "Render > the service > Environment > INGEST_KEY (copy it here)");
if (ingestUrl) ingestUrl = ingestUrl.replace(/\/+$/, "").replace(/\/ingest$/, "");
if (ingestUrl && ingestKey) {
  try {
    const health = await fetch(`${ingestUrl}/health`);
    if (!health.ok) throw new Error(`/health answered ${health.status}`);
    const res = await fetch(`${ingestUrl}/ingest`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Ingest-Key": ingestKey },
      body: JSON.stringify({ batch: [{ event: "setup.ping", player: "setup", studio: true, ts: new Date().toISOString(), props: { studio: true } }] }),
    });
    if (res.status === 401) throw new Error("the server rejected INGEST_KEY: it must match Render's INGEST_KEY exactly");
    if (!res.ok) throw new Error(`/ingest answered ${res.status}: ${(await res.text()).slice(0, 200)}`);
    report("ok", `Ingest server answers at ${ingestUrl}`);
  } catch (err) {
    report("fail", `Ingest server at ${ingestUrl}`, err.message);
  }
}

// 4. Game: where to send events ------------------------------------------------------------------
if (ingestUrl) {
  const source = readFileSync(ANALYTICS_LUAU, "utf8");
  const wanted = `local URL = "${ingestUrl}/ingest"`;
  if (source.includes(wanted)) report("ok", "Analytics.luau already points at the ingest server");
  else if (CHECK_ONLY) report("warn", "Analytics.luau doesn't point at INGEST_URL yet");
  else {
    const updated = source.replace(/^local URL = ".*"$/m, wanted);
    if (updated === source) report("fail", "Couldn't find `local URL = ...` in Analytics.luau");
    else {
      writeFileSync(ANALYTICS_LUAU, updated);
      report("ok", `Analytics.luau now sends to ${ingestUrl}/ingest`);
    }
  }
}

// 5. Roblox secret: the key the game signs with --------------------------------------------------
if (rb && universeId && ingestKey && ingestUrl) {
  try {
    const domain = new URL(ingestUrl).hostname;
    const { data: list } = await rb.listSecrets(universeId);
    const existing = (list.secrets || []).find((s) => s.id === "ingest_key");
    if (CHECK_ONLY) report(existing ? "ok" : "warn", existing ? "Roblox secret ingest_key exists" : "Roblox secret ingest_key not created yet");
    else {
      await sodium.ready;
      const { data: publicKey } = await rb.secretsPublicKey(universeId);
      // Roblox wants a libsodium sealed box against the universe's public key, as plain base64
      let key;
      try {
        key = sodium.from_base64(publicKey.secret, sodium.base64_variants.ORIGINAL);
      } catch {
        key = sodium.from_base64(publicKey.secret, sodium.base64_variants.URLSAFE);
      }
      const sealed = sodium.crypto_box_seal(sodium.from_string(ingestKey), key);
      const body = { id: "ingest_key", secret: sodium.to_base64(sealed, sodium.base64_variants.ORIGINAL), key_id: publicKey.key_id, domain };
      if (existing) await rb.updateSecret(universeId, "ingest_key", body);
      else await rb.createSecret(universeId, body);
      report("ok", `Roblox secret ingest_key ${existing ? "updated" : "created"} (only usable with ${domain})`);
    }
  } catch (err) {
    report("fail", "Roblox secret ingest_key", `${err.message}\nThe API key needs universe.secret:read + write for this experience.`);
  }
}

// 6. Robux products and passes -------------------------------------------------------------------
function readCatalog() {
  const text = readFileSync(MONETIZATION, "utf8");
  const productsAt = text.indexOf("Monetization.Products = {");
  const entry = /Key = "(\w+)",\s*Id = (\d+),\s*Price = (\d+),\s*Name = "((?:[^"\\]|\\.)*)",\s*Description = "((?:[^"\\]|\\.)*)",/g;
  const items = [];
  for (const m of text.matchAll(entry)) {
    const unescape = (s) => s.replace(/\\(.)/g, "$1");
    items.push({
      kind: m.index > productsAt ? "product" : "pass",
      key: m[1],
      id: Number(m[2]),
      price: Number(m[3]),
      name: unescape(m[4]),
      description: unescape(m[5]),
    });
  }
  const keys = (text.match(/Key = "/g) || []).length;
  return { text, items, keys };
}

if (rb && universeId) {
  const { items, keys } = readCatalog();
  if (items.length !== keys) report("warn", `Read ${items.length} of ${keys} store entries from Monetization.luau (the rest need Key/Id/Price/Name/Description in that order)`);
  try {
    const [products, passes] = await Promise.all([rb.listProducts(universeId), rb.listPasses(universeId)]);
    const byName = { product: new Map(products.map((p) => [p.name, p.productId])), pass: new Map(passes.map((p) => [p.name, p.gamePassId])) };
    const ids = {};
    let created = 0;
    let linked = 0;
    const failures = [];
    for (const item of items) {
      if (item.id > 0) continue; // already wired
      const found = byName[item.kind].get(item.name);
      if (found) {
        ids[item.key] = found;
        linked++;
        continue;
      }
      if (CHECK_ONLY) continue;
      try {
        const form = { name: item.name, price: item.price, isForSale: true };
        if (item.kind === "product") {
          const { data } = await rb.createProduct(universeId, form);
          ids[item.key] = data.productId;
          await rb.updateProduct(universeId, data.productId, { description: item.description }).catch(() => {});
        } else {
          const { data } = await rb.createPass(universeId, form);
          ids[item.key] = data.gamePassId;
          await rb.updatePass(universeId, data.gamePassId, { description: item.description }).catch(() => {});
        }
        created++;
      } catch (err) {
        failures.push(`${item.key} (${item.name}): ${err.message}`);
      }
    }
    const missing = items.filter((i) => i.id === 0 && !ids[i.key]).length;
    if (Object.keys(ids).length) {
      let text = readFileSync(MONETIZATION, "utf8");
      for (const [key, id] of Object.entries(ids)) text = text.replace(new RegExp(`(Key = "${key}",\\s*Id = )0,`), `$1${id},`);
      writeFileSync(MONETIZATION, text);
    }
    const status = failures.length ? "fail" : missing ? (CHECK_ONLY ? "warn" : "fail") : "ok";
    report(
      status,
      `Robux store: ${items.length - missing} of ${items.length} wired (${created} created, ${linked} matched by name${CHECK_ONLY ? `, ${missing} still to create` : ""})`,
      failures.join("\n") + (failures.length ? "\nThe API key needs developer-product read+write and game-pass read+write for this experience." : ""),
    );
  } catch (err) {
    report("fail", "Robux store", `${err.message}\nThe API key needs developer-product read+write and game-pass read+write for this experience.`);
  }
}

// 7. Roblox analytics + ads ----------------------------------------------------------------------
if (rb && universeId) {
  try {
    const series = await rb.metric(universeId, "DailyActiveUsers", { days: 3 });
    const points = series.flatMap((s) => s.dataPoints || []);
    report("ok", `Roblox Analytics API works (${points.length} days of DailyActiveUsers)`);
  } catch (err) {
    report("fail", "Roblox Analytics API", `${err.message}\nThe API key needs universe.analytics:read for this experience.`);
  }
  try {
    const campaigns = await rb.listCampaigns();
    report("ok", `Roblox Ads Manager API works (${campaigns.length} campaigns)`);
  } catch (err) {
    report("warn", "Roblox Ads Manager API (optional)", `${err.message}\nNeeds ad.campaign:read on a key owned by you (not a group). Everything else works without it.`);
  }
}

// ------------------------------------------------------------------------------------------------
const failed = results.filter((r) => r.status === "fail").length;
const warned = results.filter((r) => r.status === "warn").length;
console.log(`\n${failed ? `${failed} to fix` : "All set"}${warned ? `, ${warned} warning(s)` : ""}.`);
if (!failed) {
  console.log(`Left for you in Studio: Game Settings > Security > Allow HTTP Requests = on, then publish.
Render: set ROBLOX_API_KEY (and ROBLOX_PLACE_ID) there too, so it syncs Roblox's numbers every 6 h.`);
}
process.exit(failed ? 1 : 0);
