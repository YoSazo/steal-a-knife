# Analytics

Analytics records the current player loop and keeps the raw event history in Neon. The dashboard applies a persistent reporting cutoff, so resetting a funnel never deletes events or edits player saves.

## Current funnel

The `coffin_loop_v2` first-payoff funnel is:

1. Joined the game
2. Loaded into the world
3. Picked up a coffin
4. Brought the coffin home
5. Tapped READY and opened it
6. Collected Cash

The same six milestones are logged to the Roblox custom funnel named `coffin_loop_v2`. Its funnel session ID is a stable salted player hash, so progress can continue if a player returns later. Milestones are stored under versioned profile keys, so an old profile can record its first actions for this version without clearing its history. Optional engagement is reported separately: Speed coin pickups, coffin opens, and players who saw or started a random 2X Speed round.

The funnel definitions live in `src/server/Services/Analytics.luau` and `analytics/src/queries.js`. Keep both aligned when changing the gameplay sequence. The loop dashboard also tracks context tips, after-round follow-through, steals, round outcomes, the shop, and cash flows.

## Reset behavior

`analytics_config.reporting_reset_at` is the authoritative reporting boundary. It is currently **2026-10-10 00:00 America/Chicago** (`2026-10-10T05:00:00Z`). Events, sessions, player rows, spend, and Roblox daily metrics from before the cutoff stay stored but are excluded from current reports. Roblox's own metrics are daily, so their reports begin with the first complete UTC day after the cutoff. `DATA_SINCE` can override the cutoff for local tests; production loads the database value on startup.

To reset again, update the `reporting_reset_at` row in `analytics_config`, choose a new `funnel_version`, and update the matching version in the game service and dashboard. Do not truncate events or clear player profiles to reset analytics.

## Data path and checks

- Server events: `src/server/Services/Analytics.luau`; client events: `src/client/Telemetry.luau`, validated and rate limited by the server.
- Events are batched to the Render ingest endpoint and stored in Neon (`analytics/src/schema.sql`). No player names, chat, or raw UserIds are stored in event rows.
- Dashboard pages: Overview, Game loops, Players & ads, and Explorer. Studio events are excluded from reports.
- Run `cd analytics; npm test` for the local PGlite schema, ingestion, query, sync, and page checks.

Before launch, verify that the live dashboard shows the cutoff and `coffin_loop_v2`, and that a published server records the six milestones, coin pickups, and the bonus round's `round_id` and multiplier. The first real player counts will remain empty until new sessions happen after the cutoff.
