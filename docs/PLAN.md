# The plan (owner + Claude, 2026-10-08)

## LAUNCH NOW (owner, 2026-10-09): ship what's playable and start ads

The owner wants ads running on what's playable today. **Codex: do only this list, in order, then
stop adding features.** Everything else waits for real player data.

1. **Publish + live smoke test (not Studio):** publish to the real place; join on PC and on a
   phone (two accounts if possible). Full loop: first coffin steal → place → round (hide, ladder,
   weapons at 10 s) → READY tap → collect cash → buy room → a deeper steal. DataStores save across
   a rejoin. Console clean (F9 server + client). Fix only what breaks the loop.
2. **Robux:** every product/pass in the shop has a real id and buys on the live game (one cheap
   test buy). The Featured coffin stays hidden until its tile exists (fine to launch without it).
3. **Store page (owner):** title `[MURDER] Steal a Knife` and server size 8 are already set and verified via API. Owner supplies icon + 3 thumbnails
   (a monster chase, a murder round, a pen of glowing characters), age questionnaire done, public.
4. **Ads (owner):** Ads Manager sponsored-experience campaign on a small daily budget; judge it
   on D1 retention, average session length and CTR (analytics funnel, docs/ANALYTICS.md), not
   on visits.

**Local launch checks (Codex):** update10.bundle merged with 5def7cc, preserving the publish
settings. All 31 existing product/pass entries have valid Roblox IDs and matching default prices.
The three Featured IDs are still 0 and hidden from the shop. Live gameplay, persistence and an
actual payment remain unverified until performed; Studio tests do not count as live tests.

**After launch** (from the data, not before): the Featured coffin shop tile (item 21 server side
is done), the weekly drop (item 26: a new limited character each week, then one row in
`Config/Featured`; the first three weeks are already scheduled), the shared menu style + events
board (items 7-8), the rest of the text pass (28), cutting what nobody uses (23), and round-map
cover if rounds show few kills or the Murderer can't hide (see below).

**Round maps vs MM2 suspense (check in the first data):** the biome arenas are open 160x140-stud
arenas with four hedges and two sheds, in full daylight. MM2's suspense comes from breaking line
of sight (corners, rooms, doorways), so the Murderer can get close unseen and nobody knows who's
around the next corner. Watch kills per round, how often innocents win by the timer, and
how long until the first kill. If the first kill is slow or the Murderer gets spotted from
across the map, add more and taller cover (maze-like hedge rows, more sheds), not new maps.

**The filter:** every feature must make *steal → unlock → faster → steal deeper* better, or make the
murder round feed it. If it doesn't, cut it. Think 5-year-old: one obvious thing to do, no reading.

**The loop:** steal a locked knife from a monster → run home → murder rounds unlock it (and pay
Speed - the only Speed, item 30 - give Winner's Luck) → it earns cash → cash
buys pen upgrades → faster → steal deeper. The round is also the stage where you flex your best knife.

Test every step in Studio before starting the next.

## Status (cloud session, 2026-10-08): code done, first Studio pass below

Everything below was written in a cloud session with no Studio: it is type-checked (luau-lsp) and
formatted (StyLua). The first Studio pass is under "Studio test". **Desktop session: go over each one in Studio, on desktop AND on
phone sizes (the owner will give the phone dimensions), and refine what doesn't look or feel
right.** Each is its own commit on `main-eftg5w`, so a bad one can be reverted alone.

Done:
- **Item 2 (switch):** pens + coffins everywhere, Pens.Count = 8, both A/B tests gone (pens/vaults
  split, prize_pick). Dormant vault code deleted in the Codex continuation.
- **Item 3:** no knife loot / AtRisk / Insurance (leftover charges refunded once), Classic and
  Double Trouble off (code dormant), map vote gone (random map).
- **Item 1:** shells only for zones 1-2; deep biomes back to the dirt wall + ManorDecor props + floor
  dressing; ~71k lines of shell data deleted.
- **Item 5 + 8b:** creature labels (speed sign clear of the body, bigger, higher); plaza knife
  monument gone. The sleeping Z's rise out of the body, grow and fade on a loop at a fixed small
  screen size (client/CreatureIdle animates GuardService's "Z1".."Z3").
- **Item 29:** monster names (GameConfig `Monster`, `GameConfig.MonsterName`) on tags and every
  goal line ("outrun the FLOWER TOAD").
- **Item 28:** round moments shown in rounds (`Net.Notify(..., inRound)`), bigger top line /
  toasts, pen wording, rewrites. Not done: the two-line prize layout + moving the x2 pill.
- **Item 4:** Murderer powers and their dormant code deleted; rarity kill bursts added in the
  Codex continuation below.
- **Item 6 (HUD):** the guide's DO line is the big objective (36 px, phones 28); the core loop's
  line and red trail never retire (tests/GuidePolicy updated); Speed / Cash bigger, tap either to
  open the shop on its tab (`Ui.OpenShop`), a + badge on Cash.
- **Items 9 + 10 (the night):** a 10 s warning; a carried boss knife goes back when the round starts
  (`StealService.EndForRound`); everyone comes home to their pen; every stash re-rolls
  (`GuardService.RestockAll`, "NEW COFFINS!"); cycle 180 s + 120 s round with coffin rounds, offline
  seconds and the prize StepShare rescaled (pacing unchanged).
- **Item 11 (rebalance):** early wheel / trail tiers cost more (x8 / x5 / x3 / x2) so money gates
  the start; pens grow one slot at a time from a $1K first upgrade (`Pens.SlotCosts`,
  `PenMode.RoomUpgrade`; fixes Extra Room going past a pen's max); Epic coffins 2 rounds.
  pacing_sim (now models pens): Rare 0.34 h, Epic 1.2 h, Legendary 4.0 h, Mythic 8.2 h.
- **Hub ("]" shape, Steal from the Rich):** the pens wrap an open plaza: 6 across the back wall
  facing the way in, 1 on each side wall facing the middle; wheels and signs in front of each gate;
  the Lucky Wheel in the middle (`MapService.LuckyWheelAt`). About 432 x 188 studs.
- **Other fixes:** the red chase glow ends at the safe line; deeper monsters throw you further
  (x1 -> ~x2.3); torches / braziers / lava vents use the cartoon flame sprite (`Shared/SpriteFire`)
  instead of Roblox Fire. Every pen is the same full size (`PenMode.Depth` = `Pens.Depth`; the
  growing pen left a cut-off strip).

### Studio test (desktop session, phone at 640 x 320), 2026-10-08

Tested and working:
- **Hub:** all 8 pens at full size (6 along the back, 1 on each side), wheels and signs in front of
  each gate, the Lucky Wheel in the middle, the entrance board. Console clean.
- **The night:** a carried coffin goes back to its boss when the round starts, the role reveal
  shows, everyone comes home to their pen after the round, all 40 boss slots restock. (The Studio
  skip looked broken but wasn't: a test profile with no knife can't join a round, so it starts a
  new intermission.)
- **Sprite fire:** no Roblox Fire left in the deep biomes.
- **Pacing:** pacing_sim matches (Rare 0.34 h, Epic 1.2 h, Legendary 4.0 h, Mythic 8.2 h).

Fixed in Studio:
- **Zone pop-up cut off on phones** ("The Inferno🔥 · home of..." lost the monster). Now just the
  monster and the speed it needs: "🔥 LAVA SALAMANDER · Needs 950M 👟" (item 29).
- **Guide DO line clipped on phones** ("Tap the screen to draw your gun!" overflowed Roblox's
  ~280 px top bar). When it doesn't fit, it drops just below the bar at full screen width. The
  phone status line does the same.
- **Z's everywhere:** every sleeping monster down the runway showed screen-sized Z's out to
  260 studs. Now visible within 110 studs, matching the client's animation range.
- **Three messages at once on join:** the "Come back tomorrow" line is gone (not part of the loop).
- An unused `info` in `showKill` (lint).

Found and fixed in the continuation:
- **Minimum-Speed getaway:** creatures caught newcomers within 0.8 s of stealing. Their first
  three deliveries now get a 1.5 s wake-up instead of 0.25 s. At the advertised minimum Speed,
  zone 2 / 3 round trips brought coffins home with full health in 24.4 / 21.9 s on phone; a
  desktop zone 2 steal and placement completed in 24.9 s. Keep the owner's 70 s intermission.

Still to test on physical hardware: tapping Speed / Cash. Studio checks: chase glow reaches
transparency 1 at the safe line while still carrying; zone 1 / 8 fling velocity magnitudes
70.7 / 139.3; four deliveries cap learned delivery at 3 and still show all 44 red chevron parts.
The creature's speed sign is readable up close at 640 x 320.

### Codex Studio continuation, 2026-10-08

- **Phone shop fixed:** Speed / Cash rows clear the dynamic thumbstick's invisible 40%-width
  rectangle and the bottom backpack area; each whole row is a 44 px tap target. Opening a row
  keeps its Speed / Money tab (the visibility handler previously reset it to Featured).
  Tested both tabs through Studio input on desktop (1648 x 843) and the owner's 640 x 320 phone
  preset (live viewport 640 x 300, safe HUD 640 x 242). Selene, StyLua and luau-lsp pass.
  The rows now sit beside the centre view so they do not cover a monster's speed sign.
- **Item 2 deletion:** VaultModel / VaultWalls, all vault floors / ladders / plates and base
  layout branches, floor config, wall tiers and the pen-mode switch removed (~1,500 net lines).
  Pens retain their entrance marker for BaseMarkers. DataService preserves old knives in the bag
  and normalizes pen room to individual slots instead of whole floors. Placement, held knife,
  room purchases tested in Studio at phone and desktop sizes; console clean after fixing the
  dynamic KnifeModel pen-mode call. Selene, StyLua and luau-lsp pass. CLAUDE.md updated.
- **Item 4 deletion:** all Murderer perks, Spam / Hellfire / stun / traps / power reveal, Decoy,
  Stealth, Shift, perk catalog / icons / cards / button removed (~1,500 lines). Every knife uses
  tap to stab and hold to throw; higher rarities have larger coloured kill bursts. The later zero-player decision removed legacy four-field
  parsing and refunds. Studio desktop hold threw once and tap killed a bot;
  phone THROW button works repeatedly and tap killed a bot. Old Spam requests were rejected.
  Studio solo debugging bypasses join grace after giving a knife; empty profiles cannot join.
  Selene, StyLua and luau-lsp pass; no game script errors. CLAUDE.md updated.
- **Item 3 deletion:** Classic / Double Trouble config, partner views / outlines / messages,
  second Sheriff / gun paths and UI removed. Studio round setup had exactly one Murderer and one
  Revolver; role and round UI checked at phone and desktop sizes. Console had no game script
  errors. Selene, StyLua and luau-lsp pass.
- **Round lighting fixed:** neutral 210 / 210 / 200 ambient and no indoor shadows while in a
  round; hub ambient and shadows restore afterward. Visually checked Office in the phone preset
  and at desktop size after the role-reveal overlay faded. All three code checks pass. One
  restart hit an existing timeout loading wheel geometry; the next boot was clean.
- **Pen price cliff fixed:** slots 17-20 now cost 30B / 60B / 120B / 240B. pacing_sim gives
  slot 16 at 6.50 h, slot 17 at 7.92 h; Rare 0.34 h, Epic 1.18 h, Legendary 4.01 h. Later
  unique-slot milestones can still cross a rebirth, which resets the pen. Verified server purchases
  through slot 17 on phone and slot 18 at desktop size; Selene, StyLua and luau-lsp pass.
- **Owner chose item 30 option B:** IntermissionTime 70, RoundTime 60, warning 10. Survival
  steps at 10 / 20 / 35 / 50 / 60 s, weights 1 / 2 / 4 / 7 / 12, banked immediately.
  Delivered coffins pay a small share of the next zone gap, deeper zones pay more, about one
  tenth of full survival, with the same flying shoes. Rescale coffin round counts and offline
  seconds to preserve hatch minutes. Tune shares for Rare ~0.34 h, Epic ~1.2 h, Legendary ~4 h;
  preserve the cycle unless a zone 2-3 run cannot fit the ~60 s stealing window (then 80-90 s).
- **Owner choices for later:** paid featured coffin after items 13-17: fixed Mythic Inferno knife,
  weights None/Gold/Diamond/Rainbow/Void = 60/25/10/4/1, 1/3/10 bundles = 99/249/699 R$,
  immediately READY, a real weekly expiry, permanently retired old feature. Godly+ stay earned.
  Roblox title "[MURDER] Steal a Knife"; internal title "Steal a Knife".
  Owner-only admin events, automatic Saturday 15:00 America/New_York for one hour; cycle Golden
  Round (2x ladder), Luck Storm (boosted opening odds), Speed Rush (2x delivery Speed). One event
  and banner at a time; admin may start an extra event. Friday countdown on the events board.

- **Item 30 complete:** Haunted Wheel geometry, models, signs, training ticks, tutorial step,
  upgrades and UI deleted (~10,000 lines). Rounds bank Speed through DataService; shoe pickups
  pay Speed, never Cash; delivered coffins pay 1/10 of a baseline full ladder, reduced for
  shallower farming. Cosmetic trails remain a cash sink; their obsolete Speed multiplier is gone.
  2x Round Speed keeps the existing pass ID; the wheel upgrade product is retired. No profile
  migrations or refunds: the owner confirmed zero players. Payment receipts remain supported.
- **Hiding and ladder:** reveal 3.6 s, then hide 10 s. One shared server deadline controls the
  reveal, first bank and both weapons. Everyone, including Murderer, banks hiding step 1.
  Steps 10 / 20 / 35 / 50 / 60 s; parts 1 / 2 / 4 / 7 / 12. Desktop/phone HIDE line checked;
  full survival banked at 10.02 / 20.05 / 35.12 / 50.02 / 60.04 s. A death after step 3 kept
  the bank. Before hide ended no weapons; afterward both knife and revolver were present.
  Murderer stab banked its next kill reward; a shoe pickup added 21 Speed with Cash unchanged.
  Valid-knife rerun console clean. Selene, StyLua, sourcemap and luau-lsp pass.
- **Item 30 pacing:** `python tools/pacing_sim.py 12 --fit` solves the first four zone shares;
  the model includes the 3.6 s reveal and 8 s results, with estimated 65% survival and failed
  steals. These are modeled first-delivery times, not measured player telemetry.

  | Next zone | Full ladder share of zone gap | First coffin in sim |
  | --- | ---: | ---: |
  | 2 · Rare | 24.4545% | 0.33 h |
  | 3 · Epic | 5.81162% | 1.19 h |
  | 4 · Legendary | 1.63412% | 4.02 h |
  | 5 · Mythic | 1.38447% | 8.03 h |
  | 6 · Godly | 0.8% | 20.66 h |
  | 7 · Celestial | 0.6% | beyond 24 h |
  | 8 · Cosmic | 0.4% | beyond 24 h |

  `GameConfig.RoundPrize.ZoneShares` mirrors the simulator. The first four meet the owner's
  ~0.34 / 1.2 / 4 / 8 h targets. Coffin round counts ×30/13; OfflineSecondsPerRound 234
  preserves the old minute deadlines. Repeated minimum-Speed zone 2 / 3 deliveries with four
  owned knives took 24.85 / 20.87 s at full health; regular creature wake time is now 1.5 s too.
  Keep intermission 70 s, ladder 60 s, warning 10 s. Pen slots 16 / 17 occur at 5.90 / 7.36 h;
  later unique slot milestones cross rebirths, which reset the pen.

- **Item 13 complete:** native glass coffins with a visible rarity-coloured knife silhouette,
  matching carried/dropped/gift coffins. Diamond+ alone gets a white second glow and sparkles;
  the same mutation threshold controls monster-stash announcements, which keep the mutation
  hidden. Stash labels show the character and (since 10-09) its base $/s; they used to show `1 in 50 Rainbow roll`, calculated through the
  exact mutation weight function used by Items.Roll. Normal Rainbow 2%, Gold 12.5% verified.
  Fixed bloom that obscured the silhouette. Desktop and fresh 640×320 phone checked, console
  clean. A sealed `ThornDagger|Diamond|Huge` remained server-side; clients saw `ThornDagger`.
  Add/seal is atomic so its contents never briefly replicate before sealing. Luck upgrades
  preserve the original mutation rank. Selene, StyLua, sourcemap and luau-lsp pass.

- **Item 14 complete:** all 24 characters have distinct plain human names, checked against every
  boss/disguise name. Internal item IDs stay the same; art metadata and catalog names agree.
  All item display strings are `[Mutation] [Rarity] [Name]` with size omitted. Death flex now
  shows `Killed by` / `Rainbow Cosmic Bob`, tested on desktop and phone without clipping.
  Coffins use their character's name; Index and inventory read the same catalog. All code checks
  pass. Free Gift group ID confirmed by owner: 857947897, stored in GameConfig.

- **Item 15 + HUD fold complete:** timer/round/offline completion marks READY without opening.
  One `My Knives` button (owner's preferred name) contains waiting coffins and unlocked knives;
  READY entries sort first and the red badge counts READY only. Waiting entries can pay to become
  READY, then use the same free tap. Duplicate inventory/Coffins screens and their button removed.
  World clicks/prompts and menu taps are server-validated; only the first READY coffin bounces.
  Early, invalid and in-round requests rejected. A Common stayed sealed 35 s beyond its timer
  with no income; a phone tap unlocked it. Desktop tap revealed the exact saved Diamond mutation
  once, and income began only afterward. A fresh phone tutorial progressed carry/place → READY
  → tap → collect and finished. Code checks pass; no game script errors (Studio input emitted
  a CoreGUI-position warning while injecting test input).
  More's stats values are now only rebirths and wins; full UI-kit/grid migration remains item 7.

- **Item 16 complete:** round winners receive Winner's Luck through the
  following stealing break; the next round start clears it for everyone. A delayed surprise
  `🍀 WINNER'S LUCK x2!` banner follows results; the active bonus appears in My Knives. Luck now
  rolls at the READY tap (snapshot before the lid animation), preserving an existing stronger
  mutation/size. Paid roll entries bypass further luck changes so their shown odds can remain
  exact. Studio win attributes, phone bonus display, READY opening and next Reveal clearing
  tested; a Diamond coffin remained Diamond. Exact banner payload visually checked on desktop and phone. All code checks pass, including the removed unused menu import.

- **Announcement readability (item 28):** notices no longer shrink to the 14 px top-bar clock.
  Winner's Luck is a large 32/36 px line, checked at phone/desktop sizes; the hub objective yields
  while the notice is up. The redundant Murderer-chance line is deleted. Static checks pass.

- **Item 17 cut at the owner's request:** fusing removed completely, including its machine,
  UI, remotes, charge rewards, profile field and shared rules. This item is deferred and is no
  longer required for this launch. The completed round/hatch/luck work remains.

- **Owner split (starting now):** cloud owns items 22 (group gift), 25 (Saturday events/admin),
  26 (weekly drop/codes), and 27 (safe-zone PvP). Codex skips implementing those four, then
  applies the supplied bundle and tests them in Studio. Codex owns 18-21, 7-8, 24/28, and 9/23.
  Paid rotation/event-board integration will use the bundle's real weekly switch time.

- **Item 9 cleanup complete:** saved return spots, carry Suspend/Resume storage/loop and creature
  resume hooks deleted (~180 net lines). Boss carry returns to its stash at round start; a loose
  carried coffin drops on the ground. Every return/respawn uses the pen. Phone: actual zone 2
  boss steal lost its carry at Reveal and returned to the pen after the round. Desktop: loose
  coffin carry became exactly one ground drop; death returned to the pen. Static checks pass,
  no game script errors. PvP predicates preserved unchanged for the cloud-owned item 27.
  Announcement text yields briefly while the red floor trail remains active.

### Claude cloud continuation, 2026-10-09: items 22, 25, 26, 27 (CODEX: TEST THESE IN STUDIO)

Written in the cloud (no Studio): StyLua + luau-lsp pass, Selene couldn't run there. Codex, please
play-test each one on desktop and phone, fix what's off, and note the result here. Codex owns the
events board (item 8), so it reads the attributes below.

- **Item 27 (PvP):** owner's choice: coffins can be knocked loose **only on the runway** (on the way
  home); past the SAFE ZONE line (plaza, pens) nobody can, and the attacker sees "Can't attack in
  the safe zone!" (3 s throttle). `StealService.canHitCarrier`. Test: 2 players (Test → Clients
  and Servers); a carrier hit on the runway drops it, a carrier hit in the plaza doesn't.
- **Item 26 (codes):** More → **Codes** tile (the 2x2 is now Rebirth / Invite / Stats / Codes):
  type a code, REDEEM. `Config/Codes` (RELEASE = Speed + cash, MURDER = a Rare coffin),
  `Services/CodesService` (`Remotes.RedeemCode`, once per player via new profile field
  `Claimed` = "code:NAME", 1.5 s rate limit), `client/CodesView`. Rewards sized to the player by
  `Services/FreeRewards` (Speed = share of the gap to the next zone, Cash = seconds of income,
  Coffin = rarity). Test: both codes once each, a second try says "Already used!", a bad code.
  The weekly limited knife + shop tile need art / the shop rebuild: not done.
- **Item 22 (group gift):** after a round you WON (12 s after the card, after the favourite
  prompt; waits until you're out of the round), once a visit until claimed: `client/GiftCard`
  "Join our group = FREE Speed!" with JOIN (`GroupService:PromptJoinAsync`, claims by itself)
  and CLAIM. `Services/GiftService` checks the group live (`GetGroupsAsync`, group 857947897),
  pays `GameConfig.GroupGift` (Speed 0.25 of the gap) once ("gift:group" in `Claimed`; player
  attribute GiftClaimed). Test: win a bot round with an account not in the group (CLAIM says
  "Join the group first!"), then in the group.
- **Item 25 (events):** `Services/EventService` + `Config/Events`. Every Saturday 15:00
  America/New_York (DST worked out in code; checked: 2026-10-10 = 19:00 UTC, 2026-11-07 =
  20:00 UTC) for 60 min, every server on its own, cycling Golden (2x round ladder) → Luck Storm
  (2x coffin luck at opening) → Speed Rush (2x delivered-coffin Speed). 5-minute warning and
  start / end banners (`Net.Announce`). Owner chat command `/event golden 30`, `/event luck`,
  `/event speed`, `/event stop`, sent to every server with MessagingService.
  Admin: `Config/Events.AdminUserIds` = the owner's id 1068989182 (from CLAUDE.md).
  It sets the hooks Codex left: `RoundSpeedMultiplier`, `MutationLuckMultiplier`, and a new
  `DeliverySpeedMultiplier` (read in `RoundProgress.budget` for deliveries). For the board:
  ReplicatedStorage `EventKind` / `EventEndsAt` (os.time) while one runs, `NextEventKind` /
  `NextEventAt` for the countdown; titles in `Config/Events.Kinds[kind].Title`. Test (as the owner):
  `/event golden 2` in a Studio round (ladder amounts double), `/event stop`; set the system
  clock or temporarily change `Weekly` to a few minutes from now to see the automatic start.

### Codex tests of the cloud bundle, 2026-10-08 (local)

Bundle `update8.bundle` merged at 5626bd3 and pushed; both PLAN progress sections retained.
- **22:** before-win claims now rejected on the server. After a real win, the owner/member's
  phone CLAIM tap paid once; repeat returned Already claimed with unchanged Speed. A non-member
  simulated client with a real win returned Join the group first. Card/claim checked at phone
  and desktop sizes. Group lookup is rechecked after its async call, with an in-flight guard.
  The gift now waits for the native favourite prompt's completion instead of appearing behind
  it after 12 seconds. Pending join requests don't auto-claim. Touch controls pause in menus
  and restore on close. Native prompt dismissal is guarded by Roblox's completion event;
  the repeat-favourite path was used for automated claim UI testing.
- **25:** owner chat `/event speed 2` worked. Fixed integration that applied delivery Speed twice
  (4x); verified 535,000 → 771,833, about 2x baseline 118,416. Golden now applies live to ladder
  awards rather than being frozen into the round budget: next step 1,240 → 2,480 → 1,240 on
  start/stop. Shoe pickups retain their own amount. Luck Storm opening weight multiplier 1 → 2.
  DST schedule tested for October/November 2026 and March 2027 (19:00/20:00 UTC as appropriate).
  Scheduler tick tested just before start, at start, and at +1 h without changing the OS clock.
  Non-admin simulated user rejected. Event titles shortened and Luck text describes its actual
  mutation effect. Cross-server MessagingService propagation still needs a second live server;
  local commands, attributes and banners passed.
- **26 codes:** RELEASE matched case-insensitively and paid once; MURDER gave one Rare coffin;
  repeats and invalid codes rejected. Actual phone/desktop REDEEM button checked. The weekly
  limited character and shop tile remain to implement with the shop (not included in the bundle).
- **27:** two real simulated clients launched with StudioTestService. A runway stab knocked the
  coffin loose; safe-zone stab kept carry, health and ground-drop count unchanged, with the
  safe-zone message visible at phone/desktop sizes. Fixed the old two-stud allowance behind the
  painted line; an attacker at z=-1 is now blocked. Server-side authorization remains intact.
- Selene (0 errors/warnings), StyLua, sourcemap and luau-lsp pass. Temporary multi-client Studio
  sessions ended cleanly. No game script errors; tool input occasionally reported CoreGUI hits.

### Codex continuation, 2026-10-09

- **Item 18:** Secret sits above Cosmic. Otto (NightWhisper) rolls only from the Cosmic boss,
  at 1 in 2,000 restocks. A 100,000-roll Studio sample produced 52 Secret; 10,000 shallower
  boss rolls and 10,000 normal Cosmic coffin rolls produced none. Generic rarity rewards
  cannot grant Secret. The native character/knife uses charcoal and pale green.
  Unknown Index tile shows ??? and a black silhouette; after the owner taps READY it shows
  Otto and records discovery. Actual boss steal, sealed mutation masking and manual hatch
  checked. Desktop and 640x320 phone Index checked; added bottom scroll padding for Secret.
  Phone menu scaling still needs the item-7 pass; the Studio input tool also needs a 20px
  coordinate correction for the 58px simulated phone inset.
- **Pacing rerun:** `python tools/pacing_sim.py 168`: Rare 0.33h, Epic 1.19h, Legendary 4.02h,
  Mythic 8.03h, Cosmic 78.52h. This seed did not deliver a Secret within 168h; a rare roll is
  not a guaranteed milestone. The model does not scan restocks once the pen has equal-income
  Cosmic knives, so it is not a Secret waiting-time forecast. Selene, StyLua, sourcemap and
  luau-lsp pass.

- **Items 12/19 complete:** eight 160x140-stud biome arenas reuse the runway palette, studded
  dirt walls, floor patches and biome props. Four staggered cover walls, two sheds with two
  12-stud exits each, and eight spawns; no dead-end room. Removed the Office/Mansion builders,
  indoor kit, furniture/art modules and geometry (about 6,900 net lines). All eight maps passed
  10/10 no-jump paths from every spawn and both shed interiors to the centre. Fixed colliding
  decorative bushes/asteroids at spawn points; decor is walk-through, cover remains solid and
  queryable. Actual desktop walking into and out of a shed passed. Desktop/640x320 phone map
  views checked. A live round built a random biome, ran the ladder and spawned 25 round objects
  (shoes plus gun) on the usable floor. Selene, StyLua, sourcemap and luau-lsp pass.

### Claude cloud, 2026-10-09 (2): item 21 server side + in-game title (CODEX: BUILD THE TILE, TEST)

- **Item 21, featured paid coffin, server done; the shop tile is Codex's (item 20).**
  `Config/Featured`: dated weeks (InfernoFang / Lenny from Sat 2026-10-10 19:00 UTC, MagmaCleaver /
  Hank 10-17, DemonHorn / Nina 10-24 until 10-31), each on sale until the next row starts, never
  rerun; the owner adds a row a week (the weekly drop). Odds None/Gold/Diamond/Rainbow/Void =
  60/25/10/4/1, size always normal so those odds are the whole roll. `Shared/FeaturedCoffin`:
  `Current(os.time()) -> knife?, endsAt?` (nil = hide the tile), `Odds`, `Rarity`, `RollMutation`.
  Products `FeaturedCoffin1/3/10` (99/249/699 R$, `Featured = 1/3/10`, **Id 0: create them on the
  dashboard**, `Hidden = true` so the old grid doesn't list them). `Monetization.IsPaidRandom`
  now covers them, so restricted regions can't buy (client `Ui.Buy` refuses; the server pays the
  Mythic coffin value). Grant: `CoffinService.GivePaid` puts each in a free plate already READY
  and marked Paid (no luck re-roll at the tap, so the shown odds are exact); no free plate = that
  one's Mythic coffin value in cash.
  **For the tile:** character art + name (`Knives.ByName[knife].DisplayName`), the 5 odds lines,
  a real countdown to `endsAt`, three buttons `Ui.Buy("Product", "FeaturedCoffin1"|3|10)`, and a
  "needs N free spots" hint when the pen has fewer free plates than the bundle.
  Test: Studio StoreTest buys of 1/3/10 (READY at once, tap opens the rolled mutation), a full
  pen (cash instead), `PaidRandomRestricted = true` (refused / cash).
- **Title (item 24, in-game part):** loading screen "STEAL A KNIFE", console tags. The Roblox
  title "[MURDER] Steal a Knife" is set on the Creator Dashboard by the owner.

### Codex UI/art brief, 2026-10-09

- **Step 1:** one height scale on the HUD root and feedback root, `clamp(viewport.Y/720, 1, 1.5)`.
  Layout calculations use design pixels while rendered bounds stay inside the safe area. Desktop
  navigation uses a 120x46 design button (180x69 at 1080p); phone targets stay at least 44px.
  The complete Speed/Cash row is a sibling tap target, independent of the animated icon. Removed
  an old number text-size cap. Desktop 1920x1080 preset and fresh 640x320 phone checked for UI
  sizing; phone viewport 640x300, rows 176x44, both far-right number taps opened their correct
  shop tabs. Model/world verification is pending: Studio MCP currently captures a black 3D view
  behind the working GUI. New hub/pen/win changes from bcfc200 still need their full Studio pass.

### Claude cloud, 2026-10-09 (3): show, don't tell + a tighter hub (CODEX: CHECK IN STUDIO)

- **Hub:** pens 64x60 -> 52x50, FRONT 22 -> 12, PLAZA 40 -> 20 (MapService.buildBases, same 6+1+1
  "]"). The empty middle is about half what it was. Check: every pen's spots, characters hopping,
  upgrade signs, the outer back gates (they open into the 20-stud gap behind the side pens), the
  Lucky Wheel, the events board, the spawn, nothing overlapping. (4+2+2 was rejected: the outer
  back pens' gates would face the side pens' ends.)
- **Every gain flies in:** `Ui.FlyIn` (shoes / bills into the readout), Speed/Cash count up and
  punch, the SURVIVE line flashes green when a step banks, a coffin turning READY bursts, new pen
  spots burst "+1 🏠" (Effect RoomAdded from RefreshRack), "YOU'RE FAST ENOUGH! Steal from the X!"
  card for ANY Speed source (client/Transitions; the server's Outrun toasts are gone).
- **One message per moment:** cut toasts the screen already shows (boss-steal RUN HOME, Caught,
  coffin delivered, unlocked, Sheriff line, Tap = stab).
- **One meaning of "won":** the card's YOU WON, coffin clock, Winner's Luck, the win count and
  the jackpot all use it (a Murderer needs at least one kill).
- Art + sizing brief: `docs/CODEX_UI_ART_PROMPT.md`.

**Next:** featured shop tile and paid receipt validation, UI, board and cleanup.

---

## 1. Fix the foundation

1. **One wall everywhere.** Remove zones 3-8 from `BIOME_SHELLS` (MapService); keep 1-2. The runway
   walls come back (`MapService.luau` ~291 hides them when a shell exists) in their `ZONE_WALLS`
   colours, and ManorDecor's per-biome props return (`ManorDecor.luau` ~1419 skips shell zones).
   Run `floorDressing` on every zone floor, not just 1-2 + plaza. Check the boss lairs still read.
   Deletes the `ProgressiveBiomes` shell data (~1.4 MB). Each biome = same wall, new colour, new props.
2. **Remove both A/B tests.**
   - Pens vs vaults (`GameConfig.Pens.Enabled = "Split"`): set `true`, `Coffins.Enabled = true`;
     drop Split/WithPens in `shared/PenMode.luau`, the `PenServer` check in `client/PlaceTap.luau`,
     `ab_pens` in Analytics. Then delete the vault path: `shared/VaultModel.luau`,
     `server/Services/VaultWalls.luau`, MapService's 16-vault layout, BaseService's vault branches,
     FloorCosts/SlotsPerFloor/MaxSlots. Check first whether pens use `GameConfig.Walls` tiers and
     `client/BaseMarkers`. Reword or retire "Vault Floor" (ExtraFloor) / "Next Floor" (Mount).
   - `prize_pick`: everyone gets Speed-only. Delete `client/PrizePick.luau`, its remote, the
     experiment entry, `PrizePickOn`, RoundPrize's cash path.
   - Set `Pens.Count = 8` (8-player servers; the hub shrinks by itself). Server size is set on the
     Creator Dashboard (Places -> Server size).
3. **Round cuts (gain-or-no-gain).**
   - No knife loot: delete `lootKnife`, the AtRisk reel, the loot return/haul, the Insurance offer
     and the death card's insure button. Refund leftover Insurance charges once as cash
     (`shared/LegacyProgress.luau`), move Insurance3/10 to `Monetization.Retired`.
   - No Classic rounds (`ClassicChance`), then delete the code.
   - **No two-Murderer rounds** (`DoubleTrouble`, 20% of rounds: 2 Murderers + 2 Sheriffs in an
     8-player round is half the server in special roles). Keep it only as an admin event (item 25).
   - No map vote: delete `server/Services/MapVote.luau`, `RoundMapInfo`, the plaza boards.
4. **Cut Murderer powers.** Remove `GameConfig.Perks`, the `Perk` field in `Config/Knives`, perk logic
   in RoundService (throw variants, Stunned, SpamUntil, Hellfire...), the ability button / perk card
   in `client/Abilities`, `PowerShowcase`, Decoy, Stealth, Shift. One throw + one stab for every
   Murderer (decide the default throw feel first: Spam Knife's click-to-throw is on today). Old
   4-field items ignore their saved power. (Data: ~65 of ~400 new players ever used a power.)
5. **Creature boss labels.** 💤 Zzz above the creature's bounding box (`BossHeight` + margin,
   `StudsOffsetWorldSpace`), not offset from the synthetic Head (`GuardService` ~545). The
   speed-needed sign beside the creature (half its width + margin), not 7 studs from the chair spot
   (`GuardService` ~925).

## 2. Make it 5-year-old clear

6. **HUD.**
   - A giant objective line (STEAL A KNIFE -> RUN HOME -> PLACE IT; from `shared/NextAction.luau`).
   - The red floor trail always on (Guide's Auto mode retires it after three deliveries).
   - Big Speed / Cash bottom-left with a ➕ (opens the shop tab).
   - Fold the Coffins button into Knives.
   - Round countdown bottom-right with an icon ("🔪 in 1:32"). Fold "Murderer chance: 42%" into it
     or drop it.
7. **One UI kit.** Move `SimpleUi` / `KitUi` screens onto `MenuTheme`, grid layouts everywhere (the
   Index is the reference). Cut the More stats panel to rebirths + wins.
8. **Hub clutter.**
   - Redo the events board over the entrance (`ManorDecor.eventBoard`, `EventBoardGeometry`): the
     navy screen doesn't match the toy world. Big floating world text or a toy/studded sign instead.
   - Remove the giant Void Edge statue in the middle of the plaza (`ManorDecor.Build`, the
     `MONUMENT_Z` plinth, statue and torches).

## 3. Make the loop tight

9. **The round is the night.** A 10 s "get home!" warning (bottom-right countdown). When the round
   starts, anything you're carrying goes back to its boss (you saw the timer: one rule). After the
   round everyone returns to their pen (not their saved spot), every boss stash restocks at once
   with a "🔪 NEW KNIVES!" banner, READY coffins are waiting. Remove `BaseService.SetReturnSpot`'s
   use and the carry Suspend/resume; update the CLAUDE.md rule.
10. **Faster cycle.** ~3 min stealing + ~2 min round (`IntermissionTime` 360 -> ~180, `RoundTime`
    150 -> ~120). Rescale `Coffins.Rounds` so unlock times stay about the same. Re-run pacing_sim.
11. **Rebalance to Steal An Egg's shape** (their numbers: treadmill +2 .. +3,000, $15K .. $15Qa;
    12 biomes at 0/900/10K/40K/170K/700K/2.5M/17M/700M/2.5B/7B/20B; hatch 10-30 s Common, ~2 min Rare,
    ~8 min Epic, hours at the top; pen 7 -> 19 slots, first upgrade $1K).
    - Money gates again: the 2nd wheel should take ~10 min, not ~1 (our incomes are ~10-20x theirs
      for the same upgrade costs).
    - More, smaller speed gates: split the 8 biomes into ~12 (cheap with item 1), jumps ~3-10x not ~100x.
    - Shorter early unlocks: Rare on the next round or 2 min, Epic ~8 min; round clock from Legendary up.
    - A $1K first pen upgrade. Check pen upgrade costs (`SlotCost` still reads vault `FloorCosts`).
    - Update `tools/pacing_sim.py` to pens first (it still models vault floors).
12. **Faster check on round maps size** after 10: 8 players, ~one biome in size (see 18).
30. **Rounds are the Speed: cut the Haunted Wheel (treadmill).** Pens make Cash, rounds make
    Speed, one source each. Speed gates the zones, so every round pushes you deeper.
    - **Why:** the wheel is the worst tutorial step. Of 431 new players, 260 reached it and 143
      finished: 77 pressed Skip and ~40 got stuck (45% lost). Standing on a wheel is neither
      stealing nor murdering.
    - **The survival ladder.** One line on screen in a round: "⏱ 8s → +5% Speed". Each step is
      banked the moment you reach it (dying keeps what you banked), and steps get bigger the longer
      you last. Surviving to the end is the jackpot. E.g. a 90 s round: steps at 10 / 25 / 45 / 70 /
      90 s worth 1 / 2 / 4 / 7 / 12 parts. The whole ladder is a share of the gap to the next zone
      (like `RoundPrize.StepShare` today), so it works from 5.5K to 900B Speed.
    - **Murderer ladder:** every kill is a step (each bigger), a wipe is the jackpot. Sheriff who
      kills the Murderer gets the jackpot; everyone still alive banks the end step.
    - Round coins become 👟 shoes (+Speed), so the round has one prize. Round cash pay
      (`RoundPay`, `BotRoundPay`) goes. Losing a round is slower progress, never zero; an AFK
      survivor still banks the early steps.
    - **Show every step:** shoes fly into the Speed readout + a "+5% Speed" pop (both exist); after
      the round "You can outrun the FLOWER TOAD now!" when you crossed a zone's SpeedNeeded.
    - **Cycle:** a bit faster, not much (every round sends carried coffins home, steals need room):
      IntermissionTime 180 -> ~100-120, RoundTime 120 -> ~90. Rescale `Coffins.Rounds`,
      `OfflineSecondsPerRound`.
    - **Cut:** `GameConfig.Treadmills`, the wheels + WheelUpgradeSign in front of each pen gate
      (MapService), BaseService's training tick, `client/TreadmillLock`, the wheel tutorial step,
      UpgradeService's wheel upgrade, treadmill bits in Moves / Effects / KnifeTrails / Hud / Guide /
      StoreView / SurpriseGifts / DataService (grep `Treadmill`). Refund owned wheel tiers once as
      cash (`Shared/LegacyProgress`).
    - **Robux:** "2x Speed Training" becomes "2x Round Speed"; wheel-tier products to
      `Monetization.Retired`. Speed Packs stay.
    - **Money:** the wheel was a main cash sink (120K .. 80.6M). Pen rooms, trails and rebirth must
      soak up the cash instead; check it in pacing_sim.
    - **pacing_sim:** treadmill speed out, rounds/hour x ladder in. Keep the milestones (Rare
      0.34 h, Epic 1.2 h, Legendary 4.0 h).
    - Replaces RoundPrize's win-only "+X Speed" promise and the wheel half of item 11.

## 4. The hatch layer

13. **See-through coffin.** The knife inside glows in its rarity colour. Diamond+ knives get a second
    "special" glow + sparkles: the same threshold as `announceIfRare` (GuardService), so every
    sparkling coffin is announced to the server. The exact mutation stays hidden until it unlocks.
    Label: name + honest odds ("✨ 1 in 50 chance of RAINBOW"; "✨ SPECIAL Bob" for the sparkling
    ones), computed from `Items.Roll`'s real weights. Labels go back on the boss stash. Player text
    says "unlocks" not "opens". The existing luck roll at opening can stay (the knife is only a glow).
14. **Human names.** The 24 knives get plain human display names (Bob, Gary, Linda...), never a boss
    or disguise name (Frank, Ivy, Sam, Leo, Ruby, Kate, Zoe, Nick). Display = [Mutation] [Rarity]
    [Name], no size ("Rainbow Cosmic Bob"). Internal names stay (saves are safe). Round flex:
    "Killed by RAINBOW Cosmic Bob".
15. **Manual opening.** Coffins due become "READY! Tap to open" (glow, bounce, a ready badge on the
    Knives button) instead of popping in the ceremony (`CoffinService.RoundEnded` / `Open`).
16. **Winner's Luck.** A round win gives boosted mutation odds on coffins you open before the next
    round starts. A surprise banner ("🍀 WINNER'S LUCK x2!"), not part of the pre-round promise.
17. **DEFERRED — Fuse Machine** (owner cut it on 2026-10-08; no launch implementation). Original idea: 3 identical unlocked knives -> the same knife one mutation up
    (None -> Gold -> Diamond -> Rainbow -> Void). Each fuse costs one ⚡ charge, earned per round win
    (capped). Only `DataService.RemoveKnife` / `AddKnife`.
18. **Secret rarity** above Cosmic: a tiny roll from the Cosmic boss only, "???" + silhouette in the
    Index until owned. Re-run pacing_sim.

## 5. Maps, money, growth

19. **Murder maps** built from the biome pieces (same walls, floor, dressing, lighting), about one
    biome in size for 8 players, with hedges / sheds for cover. Replace Office/Mansion and delete the
    kit (`RoundMapKit`, `RoundMaps`, `RoundMapDressing`, `RoundMapArt`, ~3,700 lines).
20. **Shop rebuild.** A grid of art tiles like the Index: big number, big price, a 🎁 gift button,
    art that grows with the price (Blender renders). Side tabs Featured / Speed / Money. Hide owned
    passes. Keep the per-player speed math, show only the big number.
21. **Featured locked knife.** A limited-time paid coffin with its odds shown (required for paid
    random items), 1 / 3 / 10 bundles, a countdown, rotated weekly.
22. **Free Gift card** (Steal An Egg's): like / favourite / join the group for a one-time Speed
    reward sized to the next boss. The group join is verified (`IsInGroup`); like / favourite are
    arrow nudges + Roblox's favourite prompt (`client/Favorite.luau`). After the first round win.
    Judge the game on D1 retention and session length, not the like ratio.
23. **Data checks, cut what nobody uses.**
    - The Lucky Wheel (`PlazaWheel` / `Gamble`, its spins products and the Spin prizes in gifts):
      cut it if few players spin. Spins go through `Remotes.Gamble` (wrapped by `Analytics.Remote`).
    - Escape tokens, BossRestock, Tickets, potions: retire the ones with no sales.
24. **Name:** "Steal a Knife" + a [MURDER] tag. Lock it; test thumbnails, not names.
25. **Weekly admin events.** A server-checked admin command system (owner user id only; never open
    up the Studio-only `DebugService`), cross-server via `MessagingService`. Round twists (admin is
    the Murderer, everyone's a Sheriff, Murderer frenzy with 2 Murderers, golden round) and hub
    boosts (luck storm, Secret restock, speed rush). A fixed weekly slot, announced in-game and in
    the group.
26. **Weekly drop + codes.** One new limited knife + one shop tile a week; a codes system for the
    description and videos.
27. **PvP check.** Knock-loose hits (`Targets`, `pvp.knocked_loose`) can't land in the safe zone;
    "Can't attack in the safe zone!".

28. **Text pass (every string a player sees).** Rules: at most ~6 words, no %, no jargon, one
    message per line, big. Then:
    - **Round messages never show.** `client/Hud.luau` ~914 drops every `Net.Notify` while you're in
      a round. Lost: "A gun dropped somewhere. Find it!", "You got the gun!", "X shot the Murderer!",
      "You shot someone who WASN'T the Murderer...". Let the few that matter through as big centre
      text (the gun drop, the gun pickup, the Murderer shot).
    - **Sizes.** The top line is 20 px (18 on phones) and shrinks to 14 px to fit
      (`client/TopLine.luau` ~93-130); toasts are 21 px (`Hud.luau` ~834). Objective / top line 32+ px,
      toasts 28+ px, never shrink below ~22: split a long line into two instead.
    - **"Vault" and "plate" everywhere on a pen game.** `PenMode.Words` only rewrites notifications;
      HUD, menus and the store still say vault / plate / Wall: "Bigger Vault" (Hud), "{n}/{slots} in
      your vault", "Vault is max size" (QuickBar), "Your vault earned..." (Welcome), "Put your knife on
      the glowing plate!" / "Walk to a glowing plate" (NextAction / StealService), "Press E on the
      glowing plate" (Tutorial), "Wall 3/10 · Luck 4" (Hud ~588), shop descriptions ("your vault's
      income"), "Empty Vault", "Upgrade Base". Goes away with item 2 if every string is reworded.
    - **One name everywhere.** The loading screen says "STEAL AND MURDER", the welcome card
      "WELCOME TO BLACKWOOD!". Both say the item-24 name.
    - **Cut or reword:**
      - "Murderer chance: 42%" -> drop, or "🔪 You could be the Murderer!".
      - "Win the round: +26.4K Speed for EPIC knives" + an "x2 R$25" button in the same line -> line 1
        "WIN = +26K SPEED 👟", line 2 "unlocks EPIC knives"; the x2 button goes elsewhere.
      - Two speed numbers ("Speed" and "{n} walk speed", Hud ~586): show Speed only.
      - "Dmg 30" (knife preview), "Damage 30 · $110/s" (dropped knives): show $/s only.
      - "Best power: auto" / "Your pick: ON" (QuickBar): gone with item 4.
      - "🛡️ New-player shield: nobody can steal your knives for your first 5 minutes" (Welcome) and
        "Your safe time is over. Protect your vault!" (DataService ~738): cut (no loot any more).
      - "More → Rebirth: see what starting over gives you" -> "Rebirth = earn more forever!".
      - "Make room for a better knife - sell a spare!" -> "Pen full! Sell a knife!".
      - "Finish your run first" (Rebirth) -> "Get home first!".
      - "This isn't available where you are." (Store) -> "Can't buy that here!".
      - "+25% Speed, right now." (Speed Pack) -> "+25% SPEED"; shop descriptions shrink to the number
        (item 20).
      - "Your pen is full! {name} is waiting in your bag - sell one or get a bigger pen." -> "Pen full!
        It's in your bag."
      - "Caught at the last second? An Escape Token breaks you free WITH the knife." -> cut with
        Escape tokens, or "Escape with the knife!".
    - **Make bigger:** "THE BOSS IS COMING! RUN HOME!", "You got away!", "Caught! Your knife went
      back.", the "SPEED NEEDED / ✓ YOU'RE FAST ENOUGH" signs, the role reveal's one-line job
      ("GET EVERYONE!" / "SHOOT THE MURDERER!" / "SURVIVE!").
    - **Knife names exist already.** `shared/Config/KnifeCharacters.luau` names every knife (Rusty
      Steve, Chef Choppy, Pocket Pete, Bony Tony, Goldie Locks, Lava Lenny, Galaxy Gary...) but it's
      art metadata only: labels still say "Rusty Shank". Item 14 can use these (or their first names:
      "Steve", "Pete") instead of writing new ones. Watch the doubles with the rarity prefix
      ("Cosmic Cosmic Carl").

29. **Goals are monsters, not knife categories.** A kid doesn't want "EPIC knives"; they want to
    beat the next monster they can see. Three nouns only: the **MONSTER** (who you steal from), the
    **COFFIN** (what you steal, the glowing character inside), the **CHARACTER** by name (what comes
    out: "Rainbow Cosmic Bob"), plus SPEED and CASH. Rarity words stay as coloured labels on coffins
    and characters, never as a goal.
    - **Bosses are named after the creature,** not the old people: the hedge hound is tagged "Frank /
      The Groundskeeper" today (`GameConfig.Zones` Boss / BossTitle, the tag in GuardService ~371 /
      ~481, the 3D titles in `BossTitles` / `BossTitleModel`). -> HEDGE HOUND, FLOWER TOAD, BONE WOLF,
      GOLD SCORPION, LAVA SALAMANDER, GOLDEN GRIFFIN, SKY PEGASUS, VOID BEAST. (The disguise names for
      round characters can stay: they're people.)
    - **Every progress line points at the next monster, with its picture:**
      - Round prize (`Hud.luau` ~253-258, whose comment says "never a boss's name": reverse it now
        bosses are creatures): "WIN = +26K SPEED 👟" / "→ outrun the FLOWER TOAD!".
      - `RoundService` ~577-578: "Now you can steal {rarity} knives!" -> "You can outrun the FLOWER
        TOAD!"; "{n} more for {rarity} knives" -> "{n} more Speed to outrun the FLOWER TOAD".
      - `NextAction` ~145 / ~202 / ~217: "Fast enough! Steal a RARE knife!" -> "Fast enough! Steal from
        the FLOWER TOAD!"; "Keep running! X Speed to RARE knives" -> "X more Speed to outrun the FLOWER
        TOAD!"; "Steal another RARE coffin" -> "Steal another coffin from the FLOWER TOAD!".
      - `Guide.luau` ~701: "RARE knives unlocked!" -> "You can outrun the FLOWER TOAD!".
      - The speed sign at each lair: "SPEED NEEDED" + the monster's name.
      - The zone pop-up (`Transitions` ~77-81): the biome name + "Home of the FLOWER TOAD".
    - **Knife-focused wording -> coffin / character wording:** "Steal a knife from a boss and carry it
      home!" (QuickBar, LoadingScreen), "Steal knives off the bosses' walls on the runway..." (Menus
      ~259), "Every knife in your vault makes money!" (LoadingScreen), "Follow the arrows to Frank's
      knife / coffins!" (Tutorial ~120), "THE BOSS IS COMING!" (GuardService ~1292) -> "THE HEDGE HOUND
      IS COMING! RUN!!". The Knives menu / Index become "My Characters" / "Index" (characters, not
      blades); Coffins + Knives fold into one button (item 6).

Later, once likes and retention are healthy: stealing from other players' pens (the biggest
remaining difference from Steal An Egg / Steal a Brainrot; kept out while rounds are gain-only).

## Then: growth

- New thumbnail: one scene, a giant monster, a scared kid with a glowing knife, a "YOU!" arrow, one
  murder hint. Run 2-3 versions in Roblox's thumbnail test.
- A small ad burst to 250 highly engaged users (~$125-250 at <$1 each) for the all-ages unlock.
- Watch D1 retention, session length, rounds per session. Scale only when they hold.
