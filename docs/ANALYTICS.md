# Analytics

Our own product analytics, SaaS style: every action a player takes is an event, and every event
carries the player's whole state at that moment, so any funnel can be broken down by any variable.

- Server: `src/server/Services/Analytics.luau` (`Track`, `Milestone`, `Cash`, `Count`, `Remote`, `Variant`)
- Client: `src/client/Telemetry.luau` (device, loading, menus, every button, store prompts, fps/ping) →
  `Remotes.Track`, whitelisted + rate limited by the server (`CLIENT_EVENTS`)
- Transport: batched every 10 s as JSON to our own server (`analytics/`, Render) → Neon Postgres.
  Body `{ batch: [{ event, player, session, server, ts, props }] }`, header `X-Ingest-Key`.
- Storage (`analytics/src/schema.sql`): `events` (everything), `sessions` (device, source, A/B, how the
  visit ended), `players` (first touch, totals), `ad_spend` (entered on the dashboard).
- Dashboard (same server, password): Overview (KPIs, D1/D7, **biggest leak**, first-session funnel; click a
  step to see what the people who stalled there did instead), Game loops (steals by zone, rounds, store,
  cash in/out), Players & ads (retention cohorts, campaigns with cost per D1 player, churn, friction,
  loading/fps by device), Explorer (any event split by any field, device, campaign, visit # or A/B group).
- Backup: the onboarding milestones also go to Roblox's own funnel (Creator Dashboard → Analytics → Funnels).
- Privacy: no names, no chat, no raw UserIds. `player` = salted hash of the UserId (`Analytics.IdOf`).

## Turning it on (once)
Everything reads one file: the repo's root `.env` (template: `.env.example`, which also lists the API-key
permissions). Then:

1. **Render** → New → Blueprint → this repo (`render.yaml`, one $7 Starter service). Fill in
   `DATABASE_URL` (Neon, pooled), `DASH_PASSWORD`, `ROBLOX_API_KEY`; `INGEST_KEY` is generated. Optional:
   a custom domain (e.g. `stats.yourdomain.com`).
2. **`.env`**: `ROBLOX_API_KEY`, `DATABASE_URL`, `INGEST_URL` (the Render address), `INGEST_KEY` (copied
   from Render).
3. **`cd analytics && npm install && npm run setup`** (`-- --check` to only look). It:
   finds the universe, creates the tables, checks the ingest server with a signed test event, points
   `Analytics.luau` at it, stores the `ingest_key` Roblox secret (locked to that domain), creates every
   pass / developer product in `Monetization.luau` that doesn't exist yet and writes the real ids in, and
   checks the Analytics + Ads Manager APIs. Safe to re-run.
4. **Studio**: Game Settings → Security → Allow HTTP Requests on → publish.

Then Render pulls Roblox's own numbers every 6 h (`src/sync.js`: impressions → clicks → plays, Recommended
For You, Roblox D1/D7, revenue, crash rate, by acquisition source and platform; Ads Manager campaign status)
and shows them next to ours. `/sync` on the dashboard runs it now.

- Studio playtests stay out of the data (`SEND_IN_STUDIO = false`). Watch events live in Studio:
  `ReplicatedStorage:SetAttribute("DebugAnalytics", true)`, or `ServerStorage.Debug:Invoke("Analytics", player, 50)`
  (`..., 50, true` = the exact JSON body the server would get).
- Claude queries the live data directly: `cd analytics && npm run q -- "select ..."`.
- `npm test`: schema, ingest, the Roblox sync (fake Open Cloud) and every page on an in-memory Postgres,
  plus `npm run setup` end to end against a fake Roblox.
- Spend: the dashboard's Ad spend page, or `POST /api/spend` (header `X-Ingest-Key`,
  `{ rows: [{ day: "YYYY-MM-DD", channel, campaign, spend, impressions, clicks }] }`). Roblox's Ads API has
  no spend reporting yet, so Roblox ads are judged on Players & ads → Day by day.
- Ad links: `roblox.com/games/start?placeId=119376992331481&launchData=utm_source%3Dmeta%26utm_campaign%3D<name>`.

## Every event carries (context)
session: `$session_id`, `session_s`, `session_n`, `days_since_first`, `playtime_min` · device: `platform`
(pc/phone/tablet/console/vr), `device_*` · source: `utm_*` / `first_utm_*` (from launchData), `referred`,
`followed_friend` · progress: `rebirths`, `cash`, `cash_mag` (10^n), `income`, `income_mag`, `knives`, `slots`,
`best_rarity`, `speed`, `speed_reach`, `heat`, `luck`, `health_level`, `trail_level`, `power`, `power_level`,
`cases_opened`, `kills_total`, `wins_total`, `daily_streak`, `tutorial_done`, `tutorial_step` · money:
`robux_total`, `robux_session`, `payer` · now: `zone` (0 hub, 1-8 biome, -1 round), `phase`, `in_round`,
`carrying`, `training`, `shielded` · server: `server`, `server_players`, `place_version` · `ab_<test>`.

## Event tree (main → sub)
- **session**: `session.start` (new_user, hours_away) · `session.heartbeat` (every 60 s; `n_*` counters:
  shots, stabs, coins, pad_walks, boss_hits_*) · `session.end` (seconds, earned, spent, robux, knives_home,
  `time_zone_*` per zone, **last_event** + last_event_ago = what they did right before leaving)
- **milestone** (once per player ever, with `playtime_s`): joined, spawned, tutorial_1..6, tutorial_done /
  tutorial_skipped, steal_started, knife_home, cash_collected, wheel_trained, first_upgrade, upgrade_<kind>,
  round_played, round_survived, first_murderer, first_sheriff, murderer_win, hero_shot, first_caught,
  second_knife_home, zone_N, boss_steal_zone_N, boss_steal_home_zone_N, vault_steal_home, case_opened,
  discovered_<Rarity>, power_lv_10/25/50/100, rebirth_N, first_purchase, session_2, session_5
- **tutorial**: `tutorial.step` (step) · `tutorial.done` · `tutorial.skip` · `tip.shown`
- **steal**: `steal.start` → `steal.home` | `steal.caught` | `steal.knocked` | `steal.died` | `steal.slipped`
  (anti-cheat) | `steal.vault_full` | `steal.moon` | `steal.recovered` | `steal.left` | `steal.forced` |
  `steal.suspended` (a round pulled them in) — all with source (boss/vault/ground/case), zone, knife, rarity,
  mutation, size, value, helpers, seconds
- **boss**: `boss.hold` (started holding E) · `boss.chase` (walk_speed vs boss_speed) · `boss.snatch`
  (speed vs speed_needed, too_slow) · `boss.escaped` · `boss.shield_saved` · `boss.escape_token`
- **knife**: `knife.mounted` (power, power_one_in, new) · `knife.sold` · `case.open` / `case.lucky_block`
  (upgraded, hype, paid) · `action.Equip`
- **wheel**: `wheel.session` (seconds, speed_after)
- **upgrade**: `upgrade` (kind, ok, reply = the server's answer) · `rebirth` (cash_lost)
- **power**: `power.rolled` (tier, one_in, pity, luck) · `power.level_up` · `power.enchant` (cash/token,
  from → to) · `power.use` · `action.Power`
- **round**: `round.server_start` · `round.start` (role, chance, at_risk) · `round.knife_out` · `round.perk` ·
  `round.kill` (victim player/bot/murderer_bot) · `round.death` (by, was) · `round.revolver_pickup` ·
  `round.hero` · `round.knife_lost` / `round.knife_looted` · `round.insured_save` · `round.end` (won,
  survived, kills, knife_out_s, loot) — all with round_id, role, map, classic, double, alive, bots
- **moon** (Blood Moon): `moon.start` / `moon.end` (server) · `moon.seen` · `moon.robbed` · `moon.recovered` ·
  `moon.summon` · `pvp.knocked_loose`
- **economy**: `economy.flow` (every 60 s: `in_<source>` / `out_<sink>`: income, round_pay, offline, daily,
  free_chest, index, sell, wheel, tutorial, robux_*, upgrade_*, case_shop, enchant, lucky_block, merchant…)
- **store**: `offer.shown` (server: key, reason) → `offer.blocked` (client didn't show it: owned / round /
  menu) | `offer.click` | `offer.close` (no_thanks / timeout / menu / replaced) → `store.prompt` (source
  offer/store, menu) → `store.result` (bought, seconds) → `purchase.product` / `purchase.pass` (robux)
- **rewards**: `reward.welcome` (offline, away_h, streak_day) · `action.ClaimDaily` · `action.ClaimIndex` ·
  `action.ClaimFreeChest` · `action.Gamble` · `action.Trade`
- **ui**: `ui.menu` (open; close with seconds) · `ui.click` (button label, menu) · `client.device` ·
  `client.loaded` (loading-screen seconds) · `perf` (fps, fps_min, ping, memory, quality)
- **friction**: `notify.bad` (every red message, numbers stripped so they group) + any `action.*` /
  `upgrade` with `ok = false` (`reply` says why) · `death` (hub/round) · `setting.slow` · `social.teamup`

## The funnels to watch first
1. **First session**: joined → spawned → tutorial_1 → steal_started → knife_home → cash_collected →
   tutorial_4..6 → tutorial_done → first_upgrade → round_played → round_survived → session_2
2. **Steal loop**: boss.hold → steal.start → steal.home (vs caught/knocked/slipped), by zone and too_slow
3. **Round**: round.start → round.knife_out → round.end, by role; who leaves mid-round (session.end with
   in_round = true)
4. **Store**: offer.shown → offer.click → store.prompt → store.result(bought) → purchase.*, by key
5. **Churn**: session.end `last_event` grouped: the last thing people did before quitting

## "Come back" notifications
Roblox Experience Notifications, sent by the analytics server because game servers don't exist
after everyone leaves. Game: `client/NotifyOptIn` shows Roblox's opt-in after a player's
`GameConfig.Notify.AskAfterRounds`-th round (event `notify.prompt`; profile `NotifyAsked`);
`NotifyService` POSTs `/api/notify` (schedule on leave: "your vault filled up: {cash} waiting",
`SendAfterHours` later; cancel on join). Server: `analytics/src/notify.js` keeps one plan per player
in `notify_queue` (raw UserIds, only for asked players, deleted once sent/cancelled) and every 5 min
sends what's due through Open Cloud (`notify_log`: kind / ok / error, no ids). Only 13+ players who
opted in get it, max one a day. Off until `NOTIFY_MESSAGE_ID` (Render) and `GameConfig.Notify.Enabled`.
