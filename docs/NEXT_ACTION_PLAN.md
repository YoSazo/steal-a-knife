# Plan (merged Claude + Codex): "Always something to do"

**North star:** a new player (think 5-year-old) has one obvious, truthful, achievable next
action when help is needed, then room to play independently as they learn. Keep the economy, prizes, rates, energy costs and combat rules;
change guidance, and fix the inconsistencies that make instructions wrong.

**Decided (owner):** your best power is used automatically (no equip step; Equip stays as an
optional override). The tutorial's Skip button is removed.

## Why (data, 431 new players / 3 days)

- 21% never grab a knife. Guide step 4 (wheel): 260 → 143 "finished", but 77 of the 117 pressed
  Skip there (counted as lost) - ~40 truly stall. Almost nobody reached a 2nd round. ~65 of ~400
  ever used a power.
- After the tutorial the arrows are destroyed (`Tutorial.finish`), and the only hint (`Hud.nextGoal`)
  shows 40% of the time, no arrow, usually a 9-minute wheel goal.

## 1. Architecture

- `client/Arrows.luau`: the tutorial's target ⬇, ring, glow and chevron trail shared with the guide.
  Routes straight to a stocked side knife; vault gates and upper-floor ladders are the remaining
  waypoints. A lair approach is a fallback while its knives stream in. Yellow arrows appear only
  within 18 studs, when the actual interaction object is visible, and point above that object.
- `shared/NextAction.luau` (pure): `Pick(state) -> Action { Id, Text, Short?, Target?, Zone?, Ui? }`.
  `shared/RoundGuidance.luau` resolves round actions. Both are unit-tested.
- `client/Guide.luau` (new): builds the state (attributes + tag/instance indexes, no full workspace
  scans), evaluates on relevant changes + 4 Hz fallback, keeps the current action until done /
  invalid / outranked (no jumping), owns Arrows + the DO line. Tutorial owns them while it runs and
  hands over in the same frame.
- **Two lanes:** DO line = the instruction only, never rotates, never replaced by notices. Status
  line (today's TopLine) = timer, prize/x2 pill, role objective, notices queue. Vote stays its card.
  Phones: DO line in `Ui.topStrip()`, else its own short row; text ≥ 14 px (shorten, don't shrink).
  One published top-content height for HudTop consumers.
- **Presentation ownership:** shared client state (welcome, role reel, power reveal/showcase,
  unbox, results, haul/prize cards, fades). While one is up the guide waits and resumes after.
- **Guidance: Auto / On / Off** under More, saved across visits. Auto retires routine stealing
  after three deliveries, and each control or upgrade lesson after demonstrated use. Between those
  stages, text and arrows fade once the player follows the route. New tiers get a brief unlock
  announcement. A long idle can restore help; movement dismisses it. How to play replays the tutorial.
- The floating yellow UI rectangle is removed. The actual target button pulses briefly.
- When a guided action opens a menu, highlight the real next button/row.
- Completion = server-confirmed state (placement serial, purchase, claim, power use). A green ✓ flash
  + Juice pop on completion.

## 2. Hub ladder (first match wins)

| # | State | DO line | Target |
|---|---|---|---|
| 0 | tutorial running | tutorial step | tutorial target |
| 1 | carrying, outside vault | "Run home with your knife!" | vault entrance |
| 2 | carrying, inside, free plate | "Put your knife here!" | nearest free plate, lowest floor |
| 3 | carrying a case | "Bring your case home!" | vault |
| 4 | vault full, next floor affordable | "Make your vault bigger!" | Bigger Vault sign |
| 5 | vault full, better knife reachable | "Make room for a better knife!" | lowest-income unprotected spare's SELL |
| 6 | out of a round early (Phase Round) | status: "Steal while they play!" + the normal ladder below | — |
| 7 | gift nearby, current task finished | "Open your gift!" | gift |
| 8 | newly fast enough for a tier | "Fast enough! Steal a RARE knife!" | a stocked pedestal in that lair |
| 9 | first Index reward unclaimed | "Index → free cash + Speed!" | Index → prominent CLAIM ALL |
| 10 | useful upgrade affordable | "Upgrade your wheel!" (matches the sign) | that sign |
| 11 | collecting makes it affordable | "Grab your money!" | biggest owned pad (skip with Auto Collect) |
| 12 | stocked reachable boss | **"Steal another COMMON knife!"** | highest reachable stocked lair (fallback: lower lairs) |
| 13 | otherwise / training | "Train for RARE knives - X Speed left" | your wheel |
| 14 | max progression | rebirth (opens its explanation), claims, collecting | — |

- Reachable = `Speed >= Zones[i].SpeedNeeded` (never "best owned rarity +1").
- Keep the chosen pedestal while valid; if taken, another in the same lair first.
- Sell suggestions never touch the protected knife and only when the replacement is better/new.
- After the tutorial: claim reward → collect if needed → buy the next Speed upgrade → steal again.
- Round in ≤ 10 s: status line pulses "Get ready!"; the DO line keeps the hub action.

## 3. Rounds (DO line; status keeps objective + prize)

| State | DO line |
|---|---|
| Murderer, weapon grace | "Find someone to surprise - knife in Xs" |
| Murderer, knife in backpack | "Pull out your knife!" (highlight the slot) |
| Murderer, knife out | device-correct stab / throw; passive power explained, never "press" |
| Sheriff, gun not drawn / drawn | "Pull out your gun!" / "Find the Murderer - tap to shoot" (+ reloading) |
| Innocent near a visible dropped gun | "Grab the gun to stop the Murderer!" (public cue) |
| Innocent, power needs coins | "Grab N coins to turn invisible!" (N from energy, cost, energy/coin) |
| Innocent, power ready | "Being chased? Tap VANISH!" (the power's benefit + its real control) |
| power used up / Classic / passive | "Collect coins and stay safe!" (USED shown) |
| Second Life triggers | "You got back up - RUN!" |
| out, back in the hub | the hub ladder; status "Steal while they play!" |
| spectating | "Back to stealing" → the camera exit |

Round cues only to nearby visible coins / public guns; no hidden-role information ever.

## 4. Powers: automatic best

- `BaseService.BestKnife(profile)`: explicit `Equipped` if set, else best power tier
  (`KnifePowers.TierRank`), then level, then damage. Used by `ProtectedItem` (BaseService:99),
  `CombatService.WieldedKnife` (49), `RoundService.murdererKnife` (365), `PowerService.publishKnifePower`
  (1166). Don't write `profile.Equipped`. Frozen while `InRound`.
- Moments (status-line notices with the power icon): new power placed ("✨ New power: SHADOW - you'll
  use it in the murder round"), new best ("Your best power is now HELLFIRE!"), last minute
  ("Your power: SHADOW").
- UI: menus say "knife powers" and show both role benefits; reel art reads `FightingKnife`; QuickBar
  "Equip Best"/"!" removed; PowersView "Equip" → "Use this one" (override), "Equipped" → "On"; stale
  notifies removed ("Auto-equip…", "Powers live on your knives now…").

## 5. Truthful state (server attributes)

`PendingCash`; lair `Stocked` + pedestal zone/slot/item; `BossCarry` (zone); Innocent power uses
left / unlimited; Murderer perk mode, uses, cooldown; `SecondLifeUsed`; `WeaponAt` (grace deadline);
Revolver ready. Cleared on round exit, reset at round start.

## 6. Failures and transitions

- Caught while under-speed: explain the need, pick the reachable steal/upgrade/train. Caught while
  fast enough: "Try again - run straight home!" to the same stash.
- Dropped knife: "Pick it up!" only while that item is still there.
- Invalid/unavailable target: resolve again immediately. Restored round carry wins first.
- Speed prize unlocking a tier: after the prize card, rule 8.

## 7. Interruptions

- No offers while carrying, in combat, ≤ 20 s to a round, in menus or presentations.
- Starter Pack: queued after the first round; shown after ≥ 15 s continuous wheel training,
  with client presentation/menu checks and retries if blocked. Remove the fixed timers.
- Server offer cooldowns only start when the client actually showed it.
- Power reveals use spaced rows and wait for other presentations. Level-up notifications queue
  behind those reveals. Successful Index claims clear the prompt and badge immediately; later
  rewards stay on the badge without repeating the lesson.
- First-visit welcome: the game's purpose + Continue; streak/shield details later.
- Tutorial: Skip removed; step 4 completes after 3 s in the wheel with a "+Speed!" float.

## 8. Measurement

- `guide.shown {id, source}` on change, `guide.done {id, seconds}`, `guide.stuck {id}` (same action
  > 60 s, no progress), authoritative `power.used` (successful only).
- Funnel: `tutorial_skipped` counts as finishing; new reads: tutorial → second knife, round return →
  next successful action, power ready → use, Speed prize → next-tier steal (prize.followup).

## Build order (commit each; only this work's files)

1. Truthful state + BestKnife unification (server)  2. Arrows extraction (tutorial unchanged)
3. NextAction + tests  4. Guide + DO/status lanes + presentation ownership + Arrows toggle
5. Hub ladder  6. Round ladder  7. Powers UI + moments  8. Interruptions + Skip removal
9. Telemetry + funnel.

## Verification

Lint / format / luau-lsp; resolver tests; `npm test` (analytics). Studio (coordinate the session
with the other worker): fresh player through tutorial → 2 rounds, logging the DO line every second
(never empty in the hub, never an unavailable action, one trail max, update ≤ 250 ms after state
replicates). Forced cases: full / max vault, upper floors, Auto Collect, gift, depleted stash,
under-speed catch, every power incl. exhausted / Classic / Second Life / Spam Knife, initial /
pickup / double Sheriff, death + respawn + spectate, queued haul/prize, Starter deferral. Screens:
640×300, 667×335, tablet, desktop, gamepad; top strip unavailable; jackpot/x2; open menus.
