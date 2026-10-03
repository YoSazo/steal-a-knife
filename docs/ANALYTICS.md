# Analytics: finding out when, and why

Everything here goes through Roblox's own `AnalyticsService` (server side, `src/server/Services/Analytics.luau`),
so it shows up in Creator Hub for the experience with no external server. Names of the dashboard sections
change as Roblox updates them: look under the experience's **Analytics** for Funnels and Custom events.

Turn on printing while testing in Studio: set `ReplicatedStorage` attribute `DebugAnalytics = true`
and every event is printed to Output as it is logged.

## 1. The first-session funnel (the "when")

Roblox's **onboarding funnel**: nine steps, each logged once per player *ever* (remembered in
`profile.Funnel`), in the order a new player normally meets them.

| # | Step | What triggered it |
|---|---|---|
| 1 | `joined` | the save loaded |
| 2 | `grabbed_knife` | they picked a knife up (boss, raid or case) |
| 3 | `placed_knife` | a knife landed on one of their vault plates |
| 4 | `collected_cash` | they walked over a cash pad |
| 5 | `trained_speed` | they started the Haunted Wheel |
| 6 | `entered_round` | their first Murder round |
| 7 | `finished_round` | their first round ended with them in it |
| 8 | `bought_upgrade` | their first cash purchase |
| 9 | `guide_finished` | the guide was finished or skipped |

Each step also logs a custom event, `ftue_step`, whose **value is the player's lifetime play time in
seconds** when they got there. That is the time-to-step: how long from joining to the first knife on a plate,
to the first round, and so on. The biggest drop between two steps is where to look first.

## 2. Events (the "what happened")

Every custom event has a name, an optional number, and up to three short labels (`CustomField01..03`).

| Event | Value | Label 1 | Label 2 | Label 3 |
|---|---|---|---|---|
| `session_start` | days since they last played (0 = first visit) | `new` / `returning` | `rebirthsN` | |
| `session_end` | seconds in the session | **last bad thing + how long before leaving**, e.g. `robbed_30s` (see below) | funnel steps reached, `5/9` | `roundsN` this session |
| `ftue_step` | lifetime play time (s) | step key | progress, `3/9` | |
| `steal` | | `started` / `caught` / `deposited` | `boss1`..`boss8` / `raid` / `case` | knife rarity |
| `round_result` | seconds in the round | `innocent` / `murderer` | `survived` / `died` / `won` / `lost` | `normal` / `classic` / `double` |
| `looted` | | `returned` / `kept` (a knife taken in a round) | | |
| `robbed` | | rarity of the knife taken | `wallsN` (their wall level) | |
| `upgrade` | | what they bought (`Treadmill`, `Walls`, `Slot`...) | | |
| `blocked_cash` | | what they tried to buy | how far off: `<2x` / `<10x` / `10x+` | |
| `offer_shown` | | offer key | the offer's text, numbers removed | |
| `robux_purchase` | Robux price | item key | `product` / `pass` | |
| `robux_cancelled` | Robux price | item key | `product` / `pass` | |
| `guide` | lifetime play time (s) | `Done` / `Skip` | | |

Telemetry is capped at 90 events per player per minute, never contains names or chat, and a failing call
is swallowed (one warning), so it cannot break the game.

## 3. The "why" is a handful of questions, answered with signals

A game cannot ask "is $49 too expensive". What it can do is watch the moment before someone stops, and
compare players who did a thing with players who did not. Each question below names the signal.

**Why did they leave?** `session_end` label 1 is the last bad event and how recently it happened.
`robbed_30s`, `died_round_30s`, `boss_caught_30s`, `short_cash_2m`, `looted_30s` are rage-quit or
frustration clues. Compare the share of sessions that end that way with the share of all sessions: if
`robbed_30s` is 4% of events but 25% of exits, robberies are driving churn. `none` means they left with
nothing bad recently (bored, interrupted, or done).

**Where do new players get lost?** The funnel, plus `ftue_step` time. A step with a long median time and a
big drop is confusion. A step with a short time and a big drop is a wall (cost, danger, a dead end).

**Is the pacing wrong?** `blocked_cash` label 2. Mostly `<2x` means they are almost there (fine, a short
grind). Mostly `10x+` means the next goal is out of sight, and that is where people stop.

**Is a boss or a zone too hard?** `steal` with `caught` against `deposited` per source (`boss3`...). A zone
where nearly everyone is `caught` and nobody is `deposited` is a spike. A zone nobody even `started`
is one they never reached or never wanted.

**Are rounds fun, or a punishment?** `round_result` seconds and result. Short rounds that end `died` are
people eliminated early with nothing to do; check what happens to their session after (`died_round_30s` in
`session_end`). If most exits follow a round, the round frequency or the loot-at-risk rule is the cause. If
retention is fine after rounds, the idea is working.

**Why did they not buy?** The offer funnel, per item:

1. `offer_shown` (what was shown and in what context, by the text)
2. `robux_cancelled` (they opened the Roblox prompt and closed it: the price or the moment said no)
3. `robux_purchase` (bought)

Shown but never cancelled and never bought = they did not want it or did not notice it. Cancelled a lot =
they wanted it and the price stopped them. Compare `robux_cancelled` before and after you change a price.
Note a Robux item whose `Id` is still 0 in `Config/Monetization.luau` cannot be bought at all.

## 4. What this cannot tell you, and what to do about it

Numbers say where and when, not what a player felt. To get the feeling:

- **Watch 5 to 10 strangers play in silence** and write down where they stop or look confused.
- Add a **one-tap question at a natural pause** (v2, needs client UI): after the first round, "How was
  that? 👍 / 👎" with one tap for the reason (too hard, confusing, boring, unfair, loved it). Ask once per
  player, never mid-action, always skippable. It is the in-game version of "is $49 too expensive".
- **Run a change as an experiment:** give half the players (by `UserId` parity) the new version, put the
  variant in a label, and compare day-1 return. Do not change two things at once.

## 5. Checking it

`python tools/analytics_smoke.py` runs the module's real code against stand-ins for Roblox's services
(needs the standalone `luau` binary on the PATH) and checks the funnel, events, rate limit and session-end
clue. `selene src`, `stylua --check src` and `luau-lsp analyze` stay clean.
