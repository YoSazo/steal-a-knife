// The "come back" notification plan: /api/notify (schedule, replace, cancel, bad input) and sendDue
// against a fake Open Cloud. Run: npm test
import { PGlite } from "@electric-sql/pglite";
import assert from "node:assert/strict";
import { connect, query } from "../src/db.js";

process.env.INGEST_KEY = "test-key";
process.env.DASH_PASSWORD = "test-pass";
const { createApp } = await import("../src/server.js");
const { sendDue } = await import("../src/notify.js");

await connect({ pglite: new PGlite() });
const app = createApp().listen(0);
const base = `http://127.0.0.1:${app.address().port}`;
const post = (body, key = "test-key") =>
  fetch(`${base}/api/notify`, { method: "POST", headers: { "X-Ingest-Key": key, "Content-Type": "application/json" }, body: JSON.stringify(body) }).then(async (r) => ({ status: r.status, body: r.status === 200 ? await r.json() : null }));
const now = Math.floor(Date.now() / 1000);

assert.equal((await post({ action: "schedule", user_id: 1, send_at: now + 60 }, "wrong")).status, 401);
assert.equal((await post({ action: "schedule", user_id: 1, send_at: now + 60 })).body.status, "scheduled");
assert.equal((await post({ action: "schedule", user_id: 1, send_at: now + 7200, params: { cash: "$1.2M" } })).body.status, "scheduled");
let rows = await query("select * from notify_queue");
assert.equal(rows.length, 1, "a newer plan replaces the older one");
assert.equal(rows[0].params.cash, "$1.2M");
assert.equal((await post({ action: "schedule", user_id: 2, send_at: now + 30 * 86400 })).body.status, "bad time");
assert.equal((await post({ action: "schedule", user_id: -5, send_at: now + 60 })).body.status, "bad user");
assert.equal((await post({ action: "cancel", user_id: 1 })).body.status, "cancelled");
assert.equal((await query("select * from notify_queue")).length, 0, "coming back cancels it");

// Due ones go out through Open Cloud with the right body, then leave the queue
await query("insert into notify_queue (user_id, send_at, kind, params) values (7, now() - interval '1 minute', 'comeback', '{\"cash\":\"$5K\"}'), (8, now() + interval '1 hour', 'comeback', '{}')");
const calls = [];
const rb = { sendNotification: async (args) => calls.push(args) };
const result = await sendDue({ rb, universeId: 99, messageId: "msg-1" });
assert.deepEqual(result, { due: 1, sent: 1, failed: 0 });
assert.equal(calls[0].userId, "7");
assert.equal(calls[0].parameters.cash, "$5K");
assert.equal(calls[0].messageId, "msg-1");
assert.equal(calls[0].launchData, "utm_source=notify&utm_campaign=comeback");
assert.deepEqual((await query("select user_id from notify_queue")).map((r) => Number(r.user_id)), [8], "not due yet stays");
const failing = { sendNotification: async () => { throw new Error("HTTP 403 not opted in"); } };
await query("update notify_queue set send_at = now() - interval '1 minute'");
assert.deepEqual(await sendDue({ rb: failing, universeId: 99, messageId: "msg-1" }), { due: 1, sent: 0, failed: 1 });
assert.equal((await query("select * from notify_queue")).length, 0, "a failed send is dropped, never retried into a duplicate");
const log = await query("select ok, error from notify_log order by id");
assert.deepEqual(log.map((r) => r.ok), [true, false]);

// A plan that's hours overdue is dropped, not sent
await query("insert into notify_queue (user_id, send_at) values (9, now() - interval '2 days')");
assert.deepEqual(await sendDue({ rb, universeId: 99, messageId: "msg-1" }), { due: 0, sent: 0, failed: 0 });
assert.equal((await query("select * from notify_queue")).length, 0);

// The Open Cloud request itself
const { client } = await import("../src/roblox.js");
let sentBody = null;
let sentUrl = "";
const fake = async (url, init) => {
  sentUrl = url;
  sentBody = JSON.parse(init.body);
  return new Response("{}", { status: 200 });
};
await client({ apiKey: "k", fetchImpl: fake }).sendNotification({ userId: "7", universeId: 99, messageId: "msg-1", parameters: { cash: "$5K" }, launchData: "notify=comeback", category: "comeback" });
assert.equal(sentUrl, "https://apis.roblox.com/cloud/v2/users/7/notifications");
assert.deepEqual(sentBody, {
  source: { universe: "universes/99" },
  payload: { message_id: "msg-1", type: "MOMENT", parameters: { cash: { string_value: "$5K" } } },
  join_experience: { launch_data: "notify=comeback" },
  analytics_data: { category: "comeback" },
});

app.close();
console.log("notify: all checks passed");
