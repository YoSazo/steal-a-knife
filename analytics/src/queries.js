// Every number the dashboard shows. `days` = the window; Studio test data is always left out.
import { query } from "./db.js";

const SINCE = "now() - ($1::int * interval '1 day')";

// The first-session funnel: milestones (Analytics.Milestone), in the order a new player meets them.
// Keep in step with ONBOARDING in src/server/Services/Analytics.luau. Rebuilt 2026-10-06 for the
// 4-step guide + the first round as the Murderer; FUNNEL_SINCE starts the count over from then
// (players who joined under the old guide would muddle the new steps).
export const FIRST_SESSION = [
  ["joined", "Joined"],
  ["spawned", "Spawned (loading done)"],
  ["tutorial_1", "Guide 1: go to Frank"],
  ["steal_started", "Grabbed a knife"],
  ["tutorial_2", "Guide 2: run home"],
  ["knife_home", "Got a knife home"],
  ["tutorial_3", "Guide 3: cash pad"],
  ["cash_collected", "Collected cash"],
  ["tutorial_4", "Guide 4: the wheel"],
  ["wheel_trained", "Trained on the wheel"],
  ["tutorial_done", "Finished the guide"],
  ["round_played", "Played a murder round"],
  ["second_round", "Stayed for a 2nd round"],
  ["second_knife_home", "Second knife home"],
  ["first_upgrade", "Bought an upgrade"],
  ["zone_2", "Reached zone 2"],
  ["session_2", "Came back (2nd visit)"],
];
export const FUNNEL_SINCE = process.env.FUNNEL_SINCE || "2026-10-06T23:00:00Z";

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
       count(*) filter (where d <= current_date - 1)::int as d1_cohort,
       count(*) filter (where d <= current_date - 1 and back1)::int as d1,
       count(*) filter (where d <= current_date - 7)::int as d7_cohort,
       count(*) filter (where d <= current_date - 7 and back7)::int as d7
     from (
       select (p.first_seen at time zone 'utc')::date as d,
         exists (select 1 from sessions s where s.player = p.id
                 and (s.started_at at time zone 'utc')::date = (p.first_seen at time zone 'utc')::date + 1) as back1,
         exists (select 1 from sessions s where s.player = p.id
                 and (s.started_at at time zone 'utc')::date = (p.first_seen at time zone 'utc')::date + 7) as back7
       from players p
       where not p.studio and p.first_seen >= now() - (($1::int + 7) * interval '1 day')
     ) cohort`,
    [days],
  );
  return { ...row, ...retention[0] };
}

// New players in the window: how many reached each milestone, and how long it took them (play time)
export async function firstSession(days) {
  const rows = await query(
    `with cohort as (select id from players
       where first_seen >= ${SINCE} and first_seen >= $3::timestamptz and not studio)
     select e.props->>'milestone' as step, count(distinct e.player)::int as players,
       round(percentile_cont(0.5) within group (order by (e.props->>'playtime_s')::float)::numeric) as median_s
     from events e join cohort c on c.id = e.player
     where e.event = 'milestone' and e.props->>'milestone' = any($2::text[])
     group by 1`,
    [days, FIRST_SESSION.map(([id]) => id), FUNNEL_SINCE],
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
      where exists (select 1 from events e where e.player = c.id and e.event = 'milestone' and e.props->>'milestone' = $2)
        and not exists (select 1 from events e where e.player = c.id and e.event = 'milestone' and e.props->>'milestone' = $3)
    )`;
  const params = [days, prevId, stepId];
  const [count] = await query(`${missed} select count(*)::int as n from missed`, params);
  const lastThing = await query(
    `${missed}
     select coalesce(s.last_event, '(still playing / no end)') as last_event, count(*)::int as players,
       round(avg(s.seconds) / 60.0, 1) as avg_min
     from missed m
     join lateral (select last_event, seconds from sessions where player = m.id order by started_at desc limit 1) s on true
     group by 1 order by 2 desc limit 15`,
    params,
  );
  const messages = await query(
    `${missed}
     select e.props->>'message' as message, count(*)::int as times, count(distinct e.player)::int as players
     from events e join missed m on m.id = e.player
     where e.event = 'notify.bad' group by 1 order by 3 desc limit 15`,
    params,
  );
  const failed = await query(
    `${missed}
     select e.event, coalesce(e.props->>'kind', e.props->>'arg1', '') as what, coalesce(e.props->>'reply', '') as reply,
       count(*)::int as times, count(distinct e.player)::int as players
     from events e join missed m on m.id = e.player
     where (e.event like 'action.%' or e.event = 'upgrade') and e.props->>'ok' = 'false'
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
     join lateral (select event from events where player = m.id and event not in ('session.heartbeat', 'economy.flow', 'session.end', 'perf')
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
       select (p.first_seen at time zone 'utc')::date as d,
         exists (select 1 from sessions s where s.player = p.id and (s.started_at at time zone 'utc')::date = (p.first_seen at time zone 'utc')::date + 1) as b1,
         exists (select 1 from sessions s where s.player = p.id and (s.started_at at time zone 'utc')::date = (p.first_seen at time zone 'utc')::date + 3) as b3,
         exists (select 1 from sessions s where s.player = p.id and (s.started_at at time zone 'utc')::date = (p.first_seen at time zone 'utc')::date + 7) as b7
       from players p where not p.studio and p.first_seen >= current_date - 14
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
         and (s.started_at at time zone 'utc')::date = (p.first_seen at time zone 'utc')::date + 1))::int as d1,
       count(*) filter (where (p.first_seen at time zone 'utc')::date <= current_date - 1)::int as d1_cohort,
       coalesce(sum(p.robux_total), 0)::int as robux,
       round(avg((select sum(seconds) from sessions s where s.player = p.id)) / 60.0, 1) as avg_total_min
     from players p where not p.studio and p.first_seen >= ${SINCE}
     group by 1, 2 order by 3 desc`,
    [days],
  );
  const spend = await query(
    `select campaign, channel, sum(spend)::float as spend, sum(impressions)::int as impressions, sum(clicks)::int as clicks
     from ad_spend where day >= current_date - $1::int group by 1, 2`,
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
    `with d as (select generate_series(current_date - ($1::int - 1), current_date, interval '1 day')::date as day)
     select to_char(d.day, 'Mon DD') as day, (current_date - d.day) as age,
       (select count(*) from players p where not p.studio and (p.first_seen at time zone 'utc')::date = d.day)::int as new_players,
       (select count(*) from players p where not p.studio and (p.first_seen at time zone 'utc')::date = d.day
          and exists (select 1 from sessions s where s.player = p.id and (s.started_at at time zone 'utc')::date = d.day + 1))::int as d1,
       (select count(*) from sessions s where not s.studio and (s.started_at at time zone 'utc')::date = d.day)::int as visits,
       (select coalesce(sum(robux), 0) from sessions s where not s.studio and (s.started_at at time zone 'utc')::date = d.day)::int as robux,
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
     from roblox_metrics where dim = '' and day >= current_date - $1::int
     group by metric`,
    [days],
  );
}

export async function robloxBy(days, dim) {
  return query(
    `select value, metric,
       case when metric like 'UniqueUsers%' then sum(v) else avg(v) end as v
     from roblox_metrics where dim = $2 and day >= current_date - $1::int
     group by value, metric order by value`,
    [days, dim],
  );
}

export async function robloxDaily(days) {
  return query(
    `select to_char(day, 'Mon DD') as day, metric, v from roblox_metrics
     where dim = '' and day >= current_date - $1::int
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
