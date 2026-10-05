// POST /ingest: a batch from a Roblox server ({ batch: [{ event, player, session, server, ts, props }] }).
// Events go in as-is; session.start / client.device / heartbeat / session.end also keep the sessions and
// players tables current, so funnels can be split by device, source and A/B group with one join.
import { query } from "./db.js";

const MAX_EVENTS = 1000;

function text(value, max) {
  return typeof value === "string" && value.length > 0 ? value.slice(0, max) : null;
}

function int(value) {
  return typeof value === "number" && Number.isFinite(value) ? Math.round(value) : null;
}

function num(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

// utm_*, first_*, referred, followed_friend, launch, from_place -> the session's source
function sourceOf(props) {
  const source = {};
  for (const [key, value] of Object.entries(props)) {
    if (/^(first_)?(utm_\w+|referred|followed_friend|launch|from_place|ref)$/.test(key)) source[key] = value;
  }
  return source;
}

function abOf(props) {
  const ab = {};
  for (const [key, value] of Object.entries(props)) if (key.startsWith("ab_")) ab[key.slice(3)] = value;
  return ab;
}

export function clean(raw) {
  if (!raw || typeof raw !== "object") return null;
  const event = text(raw.event, 64);
  const player = text(raw.player, 32);
  if (!event || !player) return null;
  const parsed = Date.parse(raw.ts);
  // Clocks drift and batches wait: anything implausible gets the time it arrived
  const ts = Number.isFinite(parsed) && Math.abs(parsed - Date.now()) < 7 * 864e5 ? new Date(parsed) : new Date();
  const props = raw.props && typeof raw.props === "object" && !Array.isArray(raw.props) ? raw.props : {};
  return {
    event,
    player,
    session: text(raw.session, 40),
    server: text(raw.server, 16),
    ts,
    studio: raw.studio === true || props.studio === true,
    props,
  };
}

export async function ingest(body) {
  const batch = Array.isArray(body?.batch) ? body.batch.slice(0, MAX_EVENTS) : [];
  const rows = batch.map(clean).filter(Boolean);
  if (rows.length === 0) return 0;

  await query(
    `insert into events (ts, event, player, session, server, studio, props)
     select * from unnest($1::timestamptz[], $2::text[], $3::text[], $4::text[], $5::text[], $6::boolean[], $7::jsonb[])`,
    [
      rows.map((r) => r.ts.toISOString()),
      rows.map((r) => r.event),
      rows.map((r) => r.player),
      rows.map((r) => r.session),
      rows.map((r) => r.server),
      rows.map((r) => r.studio),
      rows.map((r) => JSON.stringify(r.props)),
    ],
  );

  for (const r of rows) {
    const p = r.props;
    if (r.event === "session.start" && r.session) {
      const source = sourceOf(p);
      await query(
        `insert into sessions (id, player, started_at, session_n, new_user, source, ab, place_version, studio)
         values ($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb, $8, $9)
         on conflict (id) do nothing`,
        [r.session, r.player, r.ts, int(p.session_n), p.new_user === true, JSON.stringify(source), JSON.stringify(abOf(p)), int(p.place_version), r.studio],
      );
      // First touch only counts on their first visit; everything after just bumps the totals
      await query(
        `insert into players (id, first_seen, last_seen, sessions, first_source, rebirths, studio)
         values ($1, $2, $2, 1, $3::jsonb, coalesce($4, 0), $5)
         on conflict (id) do update set
           last_seen = greatest(players.last_seen, excluded.last_seen),
           sessions = players.sessions + 1,
           rebirths = coalesce($4, players.rebirths)`,
        [r.player, r.ts, JSON.stringify(p.new_user === true ? source : {}), int(p.rebirths), r.studio],
      );
    } else if (r.event === "client.device" && r.session) {
      const platform = text(p.platform, 16);
      const device = {};
      for (const key of ["touch", "keyboard", "mouse", "gamepad", "vr", "phone", "screen_w", "screen_h", "quality", "locale"]) {
        if (p[key] !== undefined) device[key] = p[key];
      }
      await query(`update sessions set platform = $2, device = $3::jsonb where id = $1`, [r.session, platform, JSON.stringify(device)]);
      await query(`update players set first_platform = coalesce(first_platform, $2) where id = $1`, [r.player, platform]);
    } else if (r.event === "session.heartbeat") {
      await query(
        `update players set last_seen = greatest(last_seen, $2), robux_total = greatest(robux_total, coalesce($3, 0)),
           rebirths = coalesce($4, rebirths) where id = $1`,
        [r.player, r.ts, int(p.robux_total), int(p.rebirths)],
      );
    } else if (r.event === "session.end" && r.session) {
      await query(
        `update sessions set ended_at = $2, seconds = $3, last_event = $4, last_event_ago = $5, in_round_at_end = $6,
           earned = $7, spent = $8, robux = $9 where id = $1`,
        [r.session, r.ts, int(p.seconds), text(p.last_event, 64), int(p.last_event_ago), p.in_round === true, num(p.earned), num(p.spent), int(p.robux)],
      );
      await query(
        `update players set last_seen = greatest(last_seen, $2), robux_total = greatest(robux_total, coalesce($3, 0)),
           rebirths = coalesce($4, rebirths) where id = $1`,
        [r.player, r.ts, int(p.robux_total), int(p.rebirths)],
      );
    }
  }
  return rows.length;
}
