// Every number the dashboard shows. `days` = the window; Studio test data is always left out.
import { query } from "./db.js";

// DATA_SINCE remains a test override. Production reads the persistent reset from analytics_config.
const RESET_RAW = process.env.DATA_SINCE || "2026-10-10T05:00:00Z";
if (Number.isNaN(Date.parse(RESET_RAW))) throw new Error(`DATA_SINCE is not a time: ${RESET_RAW}`);
export let RESET = new Date(RESET_RAW).toISOString();
export let FUNNEL_VERSION = "coffin_loop_v2";
let RESET_TS = `'${RESET}'::timestamptz`;
let RESET_DAY = `((${RESET_TS} at time zone 'utc')::date + 1)`;
let SINCE = `greatest(now() - ($1::int * interval '1 day'), ${RESET_TS})`;

export async function loadAnalyticsConfig() {
  const rows = await query("select key, value from analytics_config where key in ('reporting_reset_at', 'funnel_version')");
  const config = Object.fromEntries(rows.map((row) => [row.key, row.value]));
  const raw = process.env.DATA_SINCE || config.reporting_reset_at || RESET_RAW;
  if (Number.isNaN(Date.parse(raw))) throw new Error(`Invalid reporting_reset_at: ${raw}`);
  RESET = new Date(raw).toISOString();
  FUNNEL_VERSION = config.funnel_version || FUNNEL_VERSION;
  RESET_TS = `'${RESET}'::timestamptz`;
  RESET_DAY = `((${RESET_TS} at time zone 'utc')::date + 1)`;
  SINCE = `greatest(now() - ($1::int * interval '1 day'), ${RESET_TS})`;
  return { reset: RESET, funnelVersion: FUNNEL_VERSION };
}

// The six steps are the current first-payoff path; optional engagement is measured separately.
export const FIRST_SESSION = [
  ["joined", "Joined the game"],
  ["spawned", "Loaded into the world"],
  ["steal_started", "Picked up a coffin"],
  ["knife_home", "Brought the coffin home"],
  ["coffin_opened", "Tapped READY and opened it"],
  ["cash_collected", "Collected Cash"],
];


export async function guidance(days) {
  const actions = await query(
    `select props->>'id' as action,
       count(*) filter (where event = 'guide.shown')::int as shown,
       count(*) filter (where event = 'guide.done')::int as completed,
       count(distinct player) filter (where event = 'guide.stuck')::int as stalled,
       round((percentile_cont(0.5) within group (order by (props->>'seconds')::float)
         filter (where event = 'guide.done'))::numeric) as median_s
     from events where ts >= ${SINCE} and not studio and event in ('guide.shown', 'guide.done', 'guide.stuck')
     group by 1 order by stalled desc, shown desc`, [days]);
  const definitions = [
    ["Round return → next coffin action", "e.event = 'round.end'", "n.event in ('steal.start', 'coffin.ready', 'coffin.open')"],
    ["2X round announced → player joins round", "e.event = 'round.bonus_shown' and e.props->>'multiplier' = '2'", "n.event = 'round.start' and n.props->>'bonus_multiplier' = '2'"],
  ];
  const transitions = [];
  for (const [label, start, finish] of definitions) {
    const [row] = await query(
      `select count(*)::int as started, count(next.ts)::int as followed,
         round((percentile_cont(0.5) within group (order by extract(epoch from next.ts - e.ts)))::numeric) as median_s
       from events e left join lateral (
         select n.ts from events n where n.player = e.player and n.session = e.session and not n.studio
           and n.ts > e.ts and n.ts <= e.ts + interval '10 minutes' and (${finish}) order by n.ts limit 1
       ) next on true
       where e.ts >= ${SINCE} and not e.studio and (${start})`, [days]);
    transitions.push({ label, ...row });
  }
  return { actions, transitions };
}

export async function overview(days) {
  const [row] = await query(
    `select
       (select count(*) from players where first_seen >= ${SINCE} and not studio)::int as new_players,
       (select count(*) from sessions where started_at >= ${SINCE} and not studio)::int as sessions,
       (select count(distinct player) from sessions where started_at >= ${SINCE} and not studio)::int as active_players,
       (select round((percentile_cont(0.5) within group (order by seconds) / 60.0)::numeric, 1)
          from sessions where started_at >= ${SINCE} and not studio and seconds is not null) as median_min,
       (select round((avg(seconds) / 60.0)::numeric, 1)
          from sessions where started_at >= ${SINCE} and not studio and seconds is not null) as avg_min,
       (select coalesce(sum(robux), 0) from sessions where started_at >= ${SINCE} and not studio)::int as robux,
       (select count(distinct player) from events where event like 'purchase.%' and ts >= ${SINCE} and not studio)::int as payers`,
    [days],
  );
  const retention = await query(
    `select
       count(*) filter (where d < (now() at time zone 'America/Chicago')::date)::int as d1_cohort,
       count(*) filter (where d < (now() at time zone 'America/Chicago')::date and back1)::int as d1,
       count(*) filter (where d <= (now() at time zone 'America/Chicago')::date - 7)::int as d7_cohort,
       count(*) filter (where d <= (now() at time zone 'America/Chicago')::date - 7 and back7)::int as d7
     from (
       select (p.first_seen at time zone 'America/Chicago')::date as d,
         exists (select 1 from sessions s where s.player = p.id
                 and (s.started_at at time zone 'America/Chicago')::date = (p.first_seen at time zone 'America/Chicago')::date + 1) as back1,
         exists (select 1 from sessions s where s.player = p.id
                 and (s.started_at at time zone 'America/Chicago')::date = (p.first_seen at time zone 'America/Chicago')::date + 7) as back7
       from players p
       where not p.studio and p.first_seen >= now() - (($1::int + 7) * interval '1 day')
         and p.first_seen >= ${RESET_TS}
     ) cohort`,
    [days],
  );
  return { ...row, ...retention[0] };
}

// New players in the window: how many reached each milestone, and how long it took them (play time)
export async function firstSession(days) {
  const rows = await query(
    `with cohort as (select id from players
       where first_seen >= ${SINCE} and not studio)
     select e.props->>'milestone' as step, count(distinct e.player)::int as players,
       round(percentile_cont(0.5) within group (order by (e.props->>'playtime_s')::float)::numeric) as median_s
     from events e join cohort c on c.id = e.player
     where e.ts >= ${SINCE} and not e.studio and e.event = 'milestone' and e.props->>'funnel_version' = $3
       and e.props->>'milestone' = any($2::text[])
     group by 1`,
    [days, FIRST_SESSION.map(([id]) => id), FUNNEL_VERSION],
  );
  const byStep = Object.fromEntries(rows.map((r) => [r.step, r]));
  const steps = FIRST_SESSION.map(([id, label], i) => {
    const players = byStep[id]?.players ?? 0;
    return { id, label, index: i, players, medianSeconds: byStep[id]?.median_s ?? null };
  });
  const start = steps[0].players || 0;
  let worst = null;
  steps.forEach((step, i) => {
    step.ofStart = start > 0 ? step.players / start : 0;
    if (i === 0) return;
    const prev = steps[i - 1].players;
    step.fromPrev = prev > 0 ? step.players / prev : null;
    step.lost = Math.max(0, prev - step.players);
    // The bottleneck: the step that loses the most people (with enough of them to mean something)
    if (prev >= 5 && (!worst || step.lost > worst.lost)) worst = step;
  });
  return { steps, worst };
}

// Why people stalled before `stepId`: they reached the step before it but never this one
export async function stalledAt(days, stepId) {
  const index = FIRST_SESSION.findIndex(([id]) => id === stepId);
  if (index <= 0) return null;
  const prevId = FIRST_SESSION[index - 1][0];
  const missed = `
    with cohort as (select id from players where first_seen >= ${SINCE} and not studio),
    missed as (
      select c.id from cohort c
       where exists (select 1 from events e where e.player = c.id and e.ts >= ${SINCE} and not e.studio and e.event = 'milestone' and e.props->>'funnel_version' = $4 and e.props->>'milestone' = any($2::text[]))
         and not exists (select 1 from events e where e.player = c.id and e.ts >= ${SINCE} and not e.studio and e.event = 'milestone' and e.props->>'funnel_version' = $4 and e.props->>'milestone' = any($3::text[]))
    )`;
  const params = [days, [prevId], [stepId], FUNNEL_VERSION];
  const [count] = await query(`${missed} select count(*)::int as n from missed`, params);
  const lastThing = await query(
    `${missed}
     select coalesce(s.last_event, '(still playing / no end)') as last_event, count(*)::int as players,
       round(avg(s.seconds) / 60.0, 1) as avg_min
     from missed m
     join lateral (select last_event, seconds from sessions where player = m.id and started_at >= ${SINCE} and not studio order by started_at desc limit 1) s on true
     group by 1 order by 2 desc limit 15`,
    params,
  );
  const messages = await query(
    `${missed}
     select e.props->>'message' as message, count(*)::int as times, count(distinct e.player)::int as players
     from events e join missed m on m.id = e.player
     where e.ts >= ${SINCE} and not e.studio and e.event = 'notify.bad' group by 1 order by 3 desc limit 15`,
    params,
  );
  const failed = await query(
    `${missed}
     select e.event, coalesce(e.props->>'kind', e.props->>'arg1', '') as what, coalesce(e.props->>'reply', '') as reply,
       count(*)::int as times, count(distinct e.player)::int as players
     from events e join missed m on m.id = e.player
     where e.ts >= ${SINCE} and not e.studio and (e.event like 'action.%' or e.event = 'upgrade') and e.props->>'ok' = 'false'
     group by 1, 2, 3 order by 5 desc limit 15`,
    params,
  );
  const platforms = await query(
    `${missed}
     select coalesce(p.first_platform, '?') as platform, count(*)::int as players
     from missed m join players p on p.id = m.id group by 1 order by 2 desc`,
    params,
  );
  const lastEvents = await query(
    `${missed}
     select e.event, count(*)::int as times, count(distinct m.id)::int as players
     from missed m
     join lateral (select event from events where player = m.id and ts >= ${SINCE} and not studio and event not in ('session.heartbeat', 'economy.flow', 'session.end', 'perf')
                   order by ts desc limit 5) e on true
     group by 1 order by 3 desc limit 15`,
    params,
  );
  return {
    step: FIRST_SESSION[index],
    prev: FIRST_SESSION[index - 1],
    players: count.n,
    lastThing,
    messages,
    failed,
    platforms,
    lastEvents,
  };
}

// The steal loop by zone: how each boss steal ended
export async function steals(days) {
  return query(
    `select coalesce((props->>'zone')::int, 0) as zone, event, count(*)::int as n,
       round(avg((props->>'seconds')::float)::numeric, 1) as avg_s
     from events
     where ts >= ${SINCE} and not studio and event like 'steal.%' and props->>'source' = 'boss'
     group by 1, 2 order by 1, 3 desc`,
    [days],
  );
}

export async function snatches(days) {
  return query(
    `select coalesce((props->>'zone')::int, 0) as zone, count(*)::int as snatches,
       count(*) filter (where props->>'too_slow' = 'true')::int as too_slow
     from events where ts >= ${SINCE} and not studio and event = 'boss.snatch'
     group by 1 order by 1`,
    [days],
  );
}

export async function holds(days) {
  return query(
    `select coalesce((props->>'zone')::int, 0) as zone, count(*)::int as holds
     from events where ts >= ${SINCE} and not studio and event = 'boss.hold' group by 1 order by 1`,
    [days],
  );
}

export async function rounds(days) {
  const byRole = await query(
    `select props->>'role' as role, count(*)::int as played,
       round(100.0 * avg(case when props->>'won' = 'true' then 1 else 0 end), 1) as won_pct,
       round(100.0 * avg(case when props->>'survived' = 'true' then 1 else 0 end), 1) as survived_pct,
       round(avg((props->>'kills')::float)::numeric, 2) as avg_kills,
       round(avg((props->>'knife_out_s')::float)::numeric) as knife_out_s
     from events where ts >= ${SINCE} and not studio and event = 'round.end'
     group by 1 order by 2 desc`,
    [days],
  );
  const [quits] = await query(
    `select count(*) filter (where in_round_at_end)::int as quit_mid_round, count(*)::int as sessions
     from sessions where started_at >= ${SINCE} and not studio and ended_at is not null`,
    [days],
  );
  const [started] = await query(
    `select count(*)::int as n from events where ts >= ${SINCE} and not studio and event = 'round.start'`,
    [days],
  );
  return { byRole, quits, started: started.n };
}

export async function engagement(days) {
  const [row] = await query(
    `select
       (select count(distinct player) from events where ts >= ${SINCE} and not studio and event = 'milestone' and props->>'funnel_version' = $2 and props->>'milestone' = 'coin_collected')::int as coin_players,
       (select coalesce(sum((props->>'n_coin_pickup')::int), 0) from events where ts >= ${SINCE} and not studio and event = 'session.heartbeat')::int as coin_pickups,
       (select count(*) from events where ts >= ${SINCE} and not studio and event = 'coffin.open')::int as coffin_opens,
       (select count(distinct player) from events where ts >= ${SINCE} and not studio and event = 'round.bonus_shown' and props->>'multiplier' = '2')::int as players_shown_2x,
       (select count(distinct s.player) from events s where s.ts >= ${SINCE} and not s.studio and s.event = 'round.start' and s.props->>'bonus_multiplier' = '2'
          and exists (select 1 from events b where b.player = s.player and not b.studio and b.event = 'round.bonus_shown' and b.props->>'multiplier' = '2' and b.props->>'round_id' = s.props->>'round_id'))::int as players_started_2x,
       (select count(distinct props->>'round_id') from events where ts >= ${SINCE} and not studio and event = 'round.end' and props->>'bonus_multiplier' = '2')::int as completed_2x_rounds`,
    [days, FUNNEL_VERSION],
  );
  return row;
}

export async function store(days) {
  return query(
    `select key,
       count(*) filter (where event = 'offer.shown')::int as shown,
       count(*) filter (where event = 'offer.blocked')::int as blocked,
       count(*) filter (where event = 'offer.click')::int as clicked,
       count(*) filter (where event = 'store.prompt')::int as prompts,
       count(*) filter (where event = 'store.result' and props->>'bought' = 'true')::int as bought,
       coalesce(sum((props->>'robux')::int) filter (where event like 'purchase.%'), 0)::int as robux
     from (select event, props, props->>'key' as key from events
           where ts >= ${SINCE} and not studio
             and event in ('offer.shown', 'offer.blocked', 'offer.click', 'store.prompt', 'store.result', 'purchase.product', 'purchase.pass')) x
     where key is not null
     group by key order by robux desc, prompts desc, shown desc`,
    [days],
  );
}

export async function economy(days) {
  return query(
    `select kv.key, sum(kv.value::float) as total
     from events e, jsonb_each_text(e.props) kv
     where e.ts >= ${SINCE} and not e.studio and e.event = 'economy.flow'
       and (kv.key like 'in\\_%' or kv.key like 'out\\_%')
     group by 1 order by 2 desc`,
    [days],
  );
}

export async function churn(days) {
  return query(
    `select coalesce(last_event, '?') as last_event, count(*)::int as sessions,
       count(*) filter (where session_n = 1)::int as first_visits,
       round(avg(seconds) / 60.0, 1) as avg_min
     from sessions where started_at >= ${SINCE} and not studio and ended_at is not null
     group by 1 order by 2 desc limit 20`,
    [days],
  );
}

export async function friction(days) {
  const messages = await query(
    `select props->>'message' as message, count(*)::int as times, count(distinct player)::int as players
     from events where ts >= ${SINCE} and not studio and event = 'notify.bad'
     group by 1 order by 3 desc limit 20`,
    [days],
  );
  const failed = await query(
    `select event, coalesce(props->>'kind', props->>'arg1', '') as what, coalesce(props->>'reply', '') as reply,
       count(*)::int as times, count(distinct player)::int as players
     from events where ts >= ${SINCE} and not studio
       and (event like 'action.%' or event = 'upgrade') and props->>'ok' = 'false'
     group by 1, 2, 3 order by 5 desc limit 20`,
    [days],
  );
  return { messages, failed };
}

export async function performance(days) {
  return query(
    `select coalesce(s.platform, '?') as platform,
       count(*) filter (where e.event = 'client.loaded')::int as loads,
       round(percentile_cont(0.5) within group (order by (e.props->>'seconds')::float)
         filter (where e.event = 'client.loaded' and (e.props->>'seconds')::float >= 0)::numeric, 1) as load_p50,
       round(percentile_cont(0.9) within group (order by (e.props->>'seconds')::float)
         filter (where e.event = 'client.loaded' and (e.props->>'seconds')::float >= 0)::numeric, 1) as load_p90,
       count(*) filter (where e.event = 'client.loaded' and (e.props->>'seconds')::float < 0)::int as load_gave_up,
       round(percentile_cont(0.5) within group (order by (e.props->>'fps')::float) filter (where e.event = 'perf')::numeric) as fps_p50,
       round(percentile_cont(0.1) within group (order by (e.props->>'fps_min')::float) filter (where e.event = 'perf')::numeric) as worst_fps_p10,
       round(percentile_cont(0.5) within group (order by (e.props->>'ping')::float) filter (where e.event = 'perf')::numeric) as ping_p50
     from events e left join sessions s on s.id = e.session
     where e.ts >= ${SINCE} and not e.studio and e.event in ('client.loaded', 'perf')
     group by 1 order by 2 desc`,
    [days],
  );
}

export async function cohorts() {
  return query(
    `select to_char(d, 'Mon DD') as day, count(*)::int as players,
       count(*) filter (where b1)::int as d1, count(*) filter (where b3)::int as d3, count(*) filter (where b7)::int as d7,
       (current_date - d) as age
     from (
       select (p.first_seen at time zone 'America/Chicago')::date as d,
         exists (select 1 from sessions s where s.player = p.id and (s.started_at at time zone 'America/Chicago')::date = (p.first_seen at time zone 'America/Chicago')::date + 1) as b1,
         exists (select 1 from sessions s where s.player = p.id and (s.started_at at time zone 'America/Chicago')::date = (p.first_seen at time zone 'America/Chicago')::date + 3) as b3,
         exists (select 1 from sessions s where s.player = p.id and (s.started_at at time zone 'America/Chicago')::date = (p.first_seen at time zone 'America/Chicago')::date + 7) as b7
       from players p where not p.studio and p.first_seen >= greatest((((${RESET_TS} at time zone 'America/Chicago')::date)::timestamp at time zone 'America/Chicago'), now() - interval '14 days', ${RESET_TS})
     ) x group by d order by d desc`,
  );
}

// Paid traffic: players per first-touch campaign, how well they stick, what they spend, what they cost
export async function campaigns(days) {
  const players = await query(
    `select coalesce(p.first_source->>'utm_campaign', '(organic)') as campaign,
       coalesce(p.first_source->>'utm_source', '') as source,
       count(*)::int as players,
       count(*) filter (where exists (select 1 from sessions s where s.player = p.id
         and (s.started_at at time zone 'America/Chicago')::date = (p.first_seen at time zone 'America/Chicago')::date + 1))::int as d1,
       count(*) filter (where (p.first_seen at time zone 'America/Chicago')::date < (now() at time zone 'America/Chicago')::date)::int as d1_cohort,
       coalesce(sum(p.robux_total), 0)::int as robux,
       round(avg((select sum(seconds) from sessions s where s.player = p.id)) / 60.0, 1) as avg_total_min
     from players p where not p.studio and p.first_seen >= ${SINCE}
     group by 1, 2 order by 3 desc`,
    [days],
  );
  const spend = await query(
    `select campaign, channel, sum(spend)::float as spend, sum(impressions)::int as impressions, sum(clicks)::int as clicks
     from ad_spend where day >= greatest(current_date - $1::int, ${RESET_DAY}) group by 1, 2`,
    [days],
  );
  return { players, spend };
}

// The explorer: every event name, then any event split by any of its fields (or by device / source)
export async function eventList(days) {
  return query(
    `select event, count(*)::int as n, count(distinct player)::int as players
     from events where ts >= ${SINCE} and not studio group by 1 order by 2 desc`,
    [days],
  );
}

export async function eventKeys(days, event) {
  return query(
    `select key, count(*)::int as n
     from (select props from events where ts >= ${SINCE} and not studio and event = $2 order by ts desc limit 5000) e,
       jsonb_object_keys(e.props) key
     group by 1 order by 1`,
    [days, event],
  );
}

const SESSION_SPLITS = {
  "@platform": "coalesce(s.platform, '?')",
  "@campaign": "coalesce(s.source->>'utm_campaign', s.source->>'first_utm_campaign', '(organic)')",
  "@new_user": "case when s.new_user then 'new' else 'returning' end",
  "@visit": "case when s.session_n >= 5 then '5+' else s.session_n::text end",
};

export async function eventSplit(days, event, by) {
  let value;
  const params = [days, event];
  if (SESSION_SPLITS[by]) value = SESSION_SPLITS[by];
  else if (by.startsWith("@ab:")) {
    params.push(by.slice(4));
    value = "coalesce(s.ab->>$3, '?')";
  } else {
    params.push(by);
    value = "coalesce(e.props->>$3, '(none)')";
  }
  const rows = await query(
    `select ${value} as value, count(*)::int as n, count(distinct e.player)::int as players
     from events e left join sessions s on s.id = e.session
     where e.ts >= ${SINCE} and not e.studio and e.event = $2
     group by 1 order by 2 desc limit 40`,
    params,
  );
  let numeric = null;
  if (!by.startsWith("@")) {
    [numeric] = await query(
      `select count(*)::int as n,
         percentile_cont(0.1) within group (order by (props->>$3)::float) as p10,
         percentile_cont(0.5) within group (order by (props->>$3)::float) as p50,
         percentile_cont(0.9) within group (order by (props->>$3)::float) as p90,
         avg((props->>$3)::float) as avg
       from events where ts >= ${SINCE} and not studio and event = $2 and jsonb_typeof(props->$3) = 'number'`,
      [days, event, by],
    );
    if (!numeric || numeric.n === 0) numeric = null;
  }
  return { rows, numeric };
}

export async function saveSpend(entry) {
  await query(
    `insert into ad_spend (day, channel, campaign, spend, impressions, clicks) values ($1, $2, $3, $4, $5, $6)
     on conflict (day, channel, campaign) do update set spend = excluded.spend, impressions = excluded.impressions, clicks = excluded.clicks`,
    [entry.day, entry.channel, entry.campaign, entry.spend, entry.impressions, entry.clicks],
  );
}

export async function spendList() {
  return query(`select to_char(day, 'YYYY-MM-DD') as day, channel, campaign, spend::float as spend, impressions, clicks
                from ad_spend order by day desc, channel, campaign limit 60`);
}

// Day by day: new players, how many came back the next day, and that day's ad spend (all channels).
// This is how ads without a per-player link (Roblox Ads Manager) get judged.
export async function daily(days) {
  return query(
    `with d as (select generate_series(greatest(((${RESET_TS} at time zone 'America/Chicago')::date), (now() at time zone 'America/Chicago')::date - ($1::int - 1)), (now() at time zone 'America/Chicago')::date, interval '1 day')::date as day)
     select to_char(d.day, 'Mon DD') as day, ((now() at time zone 'America/Chicago')::date - d.day) as age,
       (select count(*) from players p where not p.studio and p.first_seen >= ${RESET_TS} and (p.first_seen at time zone 'America/Chicago')::date = d.day)::int as new_players,
       (select count(*) from players p where not p.studio and p.first_seen >= ${RESET_TS} and (p.first_seen at time zone 'America/Chicago')::date = d.day
          and exists (select 1 from sessions s where s.player = p.id and (s.started_at at time zone 'America/Chicago')::date = d.day + 1))::int as d1,
       (select count(*) from sessions s where not s.studio and s.started_at >= ${RESET_TS} and (s.started_at at time zone 'America/Chicago')::date = d.day)::int as visits,
       (select coalesce(sum(robux), 0) from sessions s where not s.studio and s.started_at >= ${RESET_TS} and (s.started_at at time zone 'America/Chicago')::date = d.day)::int as robux,
       (select coalesce(sum(spend), 0) from ad_spend a where a.day = d.day)::float as spend,
       (select coalesce(sum(spend), 0) from ad_spend a where a.day = d.day and a.channel = 'roblox')::float as roblox_spend
     from d order by d.day desc`,
    [days],
  );
}

// Roblox's own numbers (src/sync.js) --------------------------------------------------------------

// Totals over the window: counts summed, rates averaged over the days that have them
export async function robloxSummary(days) {
  return query(
    `select metric,
       case when metric like 'UniqueUsers%' or metric in ('Visits', 'DailyRevenue', 'PayingUsers')
            then sum(v) else avg(v) end as v,
       count(*)::int as days, max(day) as last_day
     from roblox_metrics where dim = '' and day >= greatest(current_date - $1::int, ${RESET_DAY})
     group by metric`,
    [days],
  );
}

export async function robloxBy(days, dim) {
  return query(
    `select value, metric,
       case when metric like 'UniqueUsers%' then sum(v) else avg(v) end as v
     from roblox_metrics where dim = $2 and day >= greatest(current_date - $1::int, ${RESET_DAY})
     group by value, metric order by value`,
    [days, dim],
  );
}

export async function robloxDaily(days) {
  return query(
    `select to_char(day, 'Mon DD') as day, metric, v from roblox_metrics
     where dim = '' and day >= greatest(current_date - $1::int, ${RESET_DAY})
       and metric in ('UniqueUsersWithImpressions', 'UniqueUsersWithClicks', 'UniqueUsersWithPlaySessions', 'DailyActiveUsers')`,
    [days],
  );
}

export async function campaignList() {
  return query(
    `select id, name, status, delivery, reasons, budget_usd, budget_type, objective, start_time, duration_days, synced_at
     from ad_campaigns order by (status = 'ACTIVE') desc, updated_at desc nulls last limit 50`,
  );
}

export async function syncStatus() {
  return query(
    `select job, ok, detail, to_char(at, 'Mon DD HH24:MI') as at from sync_log
     where id in (select max(id) from sync_log group by job) order by ok, job limit 40`,
  );
}
