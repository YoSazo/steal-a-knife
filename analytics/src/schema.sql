-- Steal and Murder analytics. Idempotent: runs on every server start.

-- Reporting boundary and funnel version are stored with the database so a Render restart cannot
-- silently restore an old DATA_SINCE value. Raw events remain intact for audit/debugging.
create table if not exists analytics_config (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

-- Every event the game sends (src/server/Services/Analytics.luau, src/client/Telemetry.luau)
create table if not exists events (
  id bigserial primary key,
  ts timestamptz not null,
  received_at timestamptz not null default now(),
  event text not null,
  player text not null,           -- salted hash of the UserId
  session text,
  server text,                    -- first 8 chars of the Roblox JobId
  studio boolean not null default false,
  props jsonb not null default '{}'
);
create index if not exists events_event_ts on events (event, ts);
create index if not exists events_session on events (session);
create index if not exists events_player_ts on events (player, ts);
create index if not exists events_milestone on events ((props->>'milestone')) where event = 'milestone';

insert into analytics_config (key, value)
values ('reporting_reset_at', '2026-10-10T05:00:00.000Z'), ('funnel_version', 'coffin_loop_v2')
on conflict (key) do nothing;

-- One row per visit: device and source live here (events only carry a compact core)
create table if not exists sessions (
  id text primary key,
  player text not null,
  started_at timestamptz not null,
  ended_at timestamptz,
  seconds integer,
  session_n integer,
  new_user boolean,
  platform text,
  device jsonb not null default '{}',
  source jsonb not null default '{}',
  ab jsonb not null default '{}',
  last_event text,
  last_event_ago integer,
  in_round_at_end boolean,
  earned double precision,
  spent double precision,
  robux integer,
  place_version integer,
  studio boolean not null default false
);
create index if not exists sessions_player on sessions (player, started_at);
create index if not exists sessions_started on sessions (started_at);

-- One row per player: first touch, totals
create table if not exists players (
  id text primary key,
  first_seen timestamptz not null,
  last_seen timestamptz not null,
  sessions integer not null default 0,
  first_platform text,
  first_source jsonb not null default '{}',
  robux_total integer not null default 0,
  rebirths integer not null default 0,
  studio boolean not null default false
);
create index if not exists players_first_seen on players (first_seen);

-- Paid traffic, entered on /spend (Meta, Roblox Ads...): joins to players.first_source utm_campaign
create table if not exists ad_spend (
  day date not null,
  channel text not null,
  campaign text not null,
  spend numeric not null default 0,
  impressions integer,
  clicks integer,
  primary key (day, channel, campaign)
);

-- Roblox's own analytics (Analytics Query API), synced by src/sync.js. dim/value = the breakdown
-- (e.g. AcquisitionSource / "Sponsored"); '' = the total.
create table if not exists roblox_metrics (
  day date not null,
  metric text not null,
  dim text not null default '',
  value text not null default '',
  v double precision not null,
  synced_at timestamptz not null default now(),
  primary key (day, metric, dim, value)
);

-- Ads Manager campaigns (status only: Roblox has no spend reporting in the API yet)
create table if not exists ad_campaigns (
  id text primary key,
  name text not null default '',
  status text,
  delivery text,
  reasons jsonb not null default '[]',
  budget_usd double precision,
  budget_type text,
  objective text,
  universe_id text,
  start_time timestamptz,
  duration_days integer,
  targeting jsonb not null default '{}',
  updated_at timestamptz,
  synced_at timestamptz not null default now()
);

create table if not exists sync_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  job text not null,
  ok boolean not null,
  detail text
);

-- "Come back" notifications the game planned (src/notify.js): one row per player, deleted once
-- sent or cancelled. The only raw Roblox UserIds we keep, and only for players the game asked.
create table if not exists notify_queue (
  user_id bigint primary key,
  send_at timestamptz not null,
  kind text not null default 'comeback',
  params jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists notify_queue_due on notify_queue (send_at);

-- What was sent (no user ids): kind, worked or not, Roblox's error
create table if not exists notify_log (
  id bigserial primary key,
  sent_at timestamptz not null default now(),
  kind text not null,
  ok boolean not null,
  error text
);
