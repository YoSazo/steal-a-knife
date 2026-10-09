# Steal a Knife — Roblox / Luau

Approved Roblox title: `[MURDER] Steal a Knife`; inside the game: `Steal a Knife`.
The title rollout is still a PLAN item. Work on branch `main-eftg5w`; push only that branch.
Do not commit `.env` or create PRs unless requested.

## The One Loop
Steal a monster's coffin → place it in your pen → rounds unlock it → its character earns Cash →
Cash buys pen room → deliveries and rounds earn Speed → steal from deeper monsters.
Every feature and every player-facing cue must advance or explain this loop. Prefer icons, numbers
and one verb. One thing pulses at a time. Removed features are deleted, not disabled.

The owner says the game has zero players: no legacy profile migrations or refund work is required.
Payment receipt processing remains idempotent; retired product/pass receipt tables remain supported.

## Server authority
- Only DataService writes player profiles. Put changes in DataService.Update callbacks.
- Always add/remove knives through DataService.AddKnife / RemoveKnife so Plates stay aligned.
- Clients request actions; the server checks ownership, state, range, cooldown and valid inputs.
- DataService owns persistence, session locking and retrying UpdateAsync. Studio without API access
  uses temporary profiles. Item strings are Name|Mutation|Size.
- MapService builds the runway, eight pens and round maps. PenWalls builds the low fences;
  BaseMarkers still uses the internal VaultGate marker. Room grows from 10 to 20 slots by one.
- BaseService owns placement, character racks, income collection and RefreshWalkSpeed. Pending
  knife income is collected by entering your pen (or Auto Collect). Offline income is Cash.
- StealService validates stealing/carrying/placement. GuardService owns the creature chases.
  The safe line ends the chase glow; deeper creatures fling harder. Creature names are goals.
- RoundService chooses one Murderer and one Sheriff, disguises everyone, validates stab/throw/gun
  actions, runs bots, returns players home, and restocks the monster stashes after each round.
- Vaults, Murderer powers, Classic and Double Trouble are deleted. Every knife uses tap to stab,
  hold to throw. Rarity/colour determine the cosmetic kill burst.
- RoundProgress owns Speed: a frozen per-player round budget, banked steps, increasing kill
  rewards, shoe pickups and delivered-coffin rewards. Cash never pays directly from rounds.
  Intermission 70 seconds, round ladder 60 seconds; role reveal 3.6 seconds happens first.
  A ten-second hiding phase is ladder step 1. Both weapons arrive together at its end.
  Steps 10/20/35/50/60 seconds, parts 1/2/4/7/12. Dying keeps banked Speed; early deaths get a
  small participation amount. Per-zone shares in GameConfig.RoundPrize.ZoneShares; baseline
  delivery is one tenth of the round budget, reduced when farming shallower monsters.
- CoffinService owns sealed knives and their round/timer clock. Glass coffins show a silhouette;
  exact mutations stay server-side until the owner taps READY. Human display names include rarity
  and mutation, never size. The owner chose My Knives for the combined inventory. Winner's Luck applies at the READY tap and expires at
  the next round start. Fusing was removed at the owner's request; do not reintroduce it.
- MonetizationService handles passes/products and validates paid-random policy. FastWheel is the
  stable pass key, now labelled 2x Round Speed. SpeedUpgrade is retired. Potions use RoundSpeed.

## Layout and tools
- src/shared → ReplicatedStorage.Shared; src/server → ServerScriptService.Server;
  src/client → StarterPlayer.StarterPlayerScripts.Client; src/first contains loading UI.
- Rojo 7.7 via Rokit syncs source files into Studio. Edit files, not Studio script copies.
- GameConfig / Knives / Items contain tuning, the catalog and actual roll weights.
- UI modules share Ui / MenuTheme; client state comes from server attributes and remote effects.
- Models are native toy blocks / cached asset data. Blender scripts live in blender/scripts;
  exports are ignored. Uploaded asset IDs belong in shared Config files.
- Main.server starts services before DataService so PlayerLoaded listeners exist before spawning.

## Checks after changes
`selene src`; `stylua src`; `rojo sourcemap default.project.json -o sourcemap.json`, then
`luau-lsp analyze --defs=globalTypes.d.luau --sourcemap=sourcemap.json src`.
Test each PLAN step in Studio at desktop and the owner's 640×320 phone preset. Studio's actual
phone viewport is 640×300, with a 640×242 HUD safe area. DebugPhone=true forces touch UI and aim.
Use the device simulator skill for viewport changes. Record tests, findings and remaining work
in docs/PLAN.md Status after each item; make small commits with plain messages.

## Live Studio debugging
Command-bar requires get their own module copies. Reach live state through
`game.ServerStorage.Debug:Invoke(command, player, ...)`. Give a knife before a solo round.
DebugMinPlayers=1 / DebugSkip=true starts/skips a solo round; it bypasses join grace in Studio,
not the requirement to own a knife. DebugMinPlayers=100 temporarily holds rounds for steal tests.
Useful commands: Give, Cash, Speed, Data, Home, BossSteal, Carry, Coffin, BotRound, Analytics.
DebugService and its remotes are Studio-only; never use them for production admin commands.

## Approved remaining owner choices
- Featured paid coffin after the hatch layer: fixed Mythic Inferno character; mutation weights
  None/Gold/Diamond/Rainbow/Void 60/25/10/4/1; bundles 1/3/10 for 99/249/699 R$; immediately
  READY; real weekly rotation, permanently retired past features. Godly+ stay earned.
- Admin owner ID 1068989182 (R_F1ow), verified against the place creator. Saturday 15:00
  America/New_York, one hour, auto cycle Golden Round / Luck Storm / Speed Rush; one event at
  a time. Owner can start an extra one. Friday countdown. Do not add the cut role twists.
- Milestones govern Speed shares: Rare ~0.34h, Epic ~1.2h, Legendary ~4h, Mythic ~8h.
  Tune amounts with tools/pacing_sim.py; keep step timings and parts fixed.
