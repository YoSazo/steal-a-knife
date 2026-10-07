// "Come back" notifications (Roblox Experience Notifications). The game can't send one hours after
// a player leaves (its servers only exist while people are in them), so it hands us the plan:
//   - a player who was asked to opt in leaves  -> POST /api/notify { action: "schedule", ... }
//   - they come back before it's due           -> POST /api/notify { action: "cancel", user_id }
// and sendDue() (main.js, every few minutes) sends what's due through Open Cloud:
//   POST apis.roblox.com/cloud/v2/users/{id}/notifications (API key permission
//   user.user-notification:write). Roblox only delivers to players aged 13+ who opted in, at most
//   one per player per day per experience.
// Off until NOTIFY_MESSAGE_ID is set (the notification string's id from Creator Dashboard ->
// Engagement -> Notifications). Privacy: the only place we keep a raw UserId, and only for players
// the game asked; the row is deleted once it's sent or cancelled.
import { query } from "./db.js";

const MAX_AHEAD = 3 * 86400; // never schedule more than 3 days out

// Validates and stores (or cancels) one plan from the game. Returns a short status string.
export async function handleNotify(body) {
  const userId = Number(body?.user_id);
  if (!Number.isSafeInteger(userId) || userId <= 0) return "bad user";
  if (body.action === "cancel") {
    await query("delete from notify_queue where user_id = $1", [userId]);
    return "cancelled";
  }
  if (body.action !== "schedule") return "bad action";
  const now = Math.floor(Date.now() / 1000);
  const sendAt = Number(body.send_at);
  if (!Number.isFinite(sendAt) || sendAt < now || sendAt > now + MAX_AHEAD) return "bad time";
  const kind = String(body.kind || "comeback").slice(0, 30);
  const params = {};
  for (const [key, value] of Object.entries(body.params && typeof body.params === "object" ? body.params : {}).slice(0, 5)) {
    if (/^[a-zA-Z0-9_]{1,30}$/.test(key)) params[key] = String(value).slice(0, 60);
  }
  // one plan per player: a newer visit replaces the older plan
  await query(
    `insert into notify_queue (user_id, send_at, kind, params) values ($1, to_timestamp($2), $3, $4)
     on conflict (user_id) do update set send_at = excluded.send_at, kind = excluded.kind, params = excluded.params, created_at = now()`,
    [userId, sendAt, kind, JSON.stringify(params)],
  );
  return "scheduled";
}

// Sends every due notification (oldest first, a batch at a time). Failed sends are logged and
// dropped: a missed reminder is better than a duplicate one.
export async function sendDue({ rb, universeId, messageId, limit = 100 }) {
  const due = await query(
    "select user_id, kind, params from notify_queue where send_at <= now() order by send_at limit $1",
    [limit],
  );
  let sent = 0;
  let failed = 0;
  for (const row of due) {
    const params = typeof row.params === "string" ? JSON.parse(row.params) : row.params || {};
    let error = null;
    try {
      await rb.sendNotification({
        userId: String(row.user_id),
        universeId,
        messageId,
        parameters: params,
        launchData: `notify=${row.kind}`,
        category: row.kind,
      });
      sent++;
    } catch (err) {
      failed++;
      error = String(err.message).slice(0, 200);
      console.error("notify failed:", error);
    }
    await query("delete from notify_queue where user_id = $1", [row.user_id]);
    // (no user id in the log: just what was sent and whether it worked)
    await query("insert into notify_log (kind, ok, error) values ($1, $2, $3)", [row.kind, error === null, error]);
  }
  return { due: due.length, sent, failed };
}
