// Test double for scripts/test-setup.js: replaces fetch with a fake apis.roblox.com + ingest server
// (node --import ./scripts/fake-roblox.js scripts/setup.js). Every request is appended to FAKE_LOG.
import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";

const LOG = process.env.FAKE_LOG;
const STATE = process.env.FAKE_STATE; // created products/passes survive between runs (idempotency test)
const state = existsSync(STATE) ? JSON.parse(readFileSync(STATE, "utf8")) : { products: [], passes: [{ name: "VIP", gamePassId: 999 }], secrets: [], next: 1000 };
const save = () => writeFileSync(STATE, JSON.stringify(state));

const json = (status, body) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

globalThis.fetch = async (url, init = {}) => {
  const u = new URL(url);
  const method = init.method || "GET";
  let body = null;
  if (init.body instanceof FormData) body = Object.fromEntries(init.body.entries());
  else if (typeof init.body === "string") body = JSON.parse(init.body);
  appendFileSync(LOG, JSON.stringify({ method, host: u.host, path: u.pathname, body, key: init.headers?.["x-api-key"] || init.headers?.["X-Ingest-Key"] }) + "\n");

  if (u.host === "stats.example.com") {
    if (u.pathname === "/health") return new Response("ok");
    if (u.pathname === "/ingest") return init.headers["X-Ingest-Key"] === "secret123" ? json(200, { ok: true, count: 1 }) : json(401, {});
  }
  if (u.host !== "apis.roblox.com") return json(404, {});
  if (u.pathname === "/universes/v1/places/119376992331481/universe") return json(200, { universeId: 42 });
  if (init.headers?.["x-api-key"] !== "rbx") return json(401, { errors: [{ message: "bad key" }] });
  const p = u.pathname;
  if (p === "/developer-products/v2/universes/42/developer-products/creator") return json(200, { developerProducts: state.products, nextPageToken: "" });
  if (p === "/game-passes/v1/universes/42/game-passes/creator") return json(200, { gamePasses: state.passes, nextPageToken: "" });
  if (p === "/developer-products/v2/universes/42/developer-products" && method === "POST") {
    if (!body.name || !body.price) return json(400, { errorMessage: "name and price" });
    const product = { productId: state.next++, name: body.name, price: Number(body.price) };
    state.products.push(product);
    save();
    return json(200, product);
  }
  if (p === "/game-passes/v1/universes/42/game-passes" && method === "POST") {
    if (body.description !== undefined) return json(400, { errorMessage: "description isn't a create field" });
    const pass = { gamePassId: state.next++, name: body.name };
    state.passes.push(pass);
    save();
    return json(200, pass);
  }
  if (/\/(developer-products|game-passes)\/\d+$/.test(p) && method === "PATCH") return json(200, {});
  if (p === "/cloud/v2/universes/42/secrets/public-key") return json(200, { secret: process.env.FAKE_PK, key_id: "kid-1" });
  if (p === "/cloud/v2/universes/42/secrets" && method === "GET") return json(200, { secrets: state.secrets.map((s) => ({ id: s.id })) });
  if (p === "/cloud/v2/universes/42/secrets" && method === "POST") {
    state.secrets.push(body);
    save();
    return json(201, { id: body.id });
  }
  if (p === "/cloud/v2/universes/42/secrets/ingest_key" && method === "PATCH") {
    state.secrets = state.secrets.filter((s) => s.id !== "ingest_key").concat(body);
    save();
    return json(200, { id: body.id });
  }
  if (p === "/analytics-query-api/v1/universes/42/metrics") return json(200, { done: true, response: { values: [{ dataPoints: [{ time: "2026-10-04T00:00:00Z", value: 12 }] }] } });
  if (p === "/ads-management/v1/campaigns") return json(403, { errors: [{ message: "Scope not authorized." }] });
  return json(404, { errorMessage: `not faked: ${method} ${p}` });
};
