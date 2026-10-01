# Steal a Knife — Roblox game

Loop: knives earn cash -> cash buys Innocent Powers -> knives arm the Murderer, powers arm innocents -> rounds steal
and return knives. Steal-and-collect + Murder Mystery 2-style rounds. Players fight their way into an arena of NPC watchmen
(deeper zone = rarer knife, tougher guards), kill a guard to make it drop the knife it holds, carry
that knife home and mount it on their vault wall, which pays cash/s. They buy
Speed / rack Slots / Murderer tickets, and every few minutes everyone is pulled into a round with one
random Murderer (weighted by a luck meter + tickets) and a survival timer. No Sheriff, no PvP in the arena.
Rarities: Common, Rare, Epic, Legendary, Godly. Audience ~9-15, low-poly.
Look: dark murder-mystery theme. The hub is "Blackwood Manor" at night (fences, lamps, dead trees,
the Manor behind the arena); rounds are The Mad Murderer-style indoor maps (Office, Mansion) with
disguises (named pre-made characters), bodies that stay, and a Revolver innocents can grab.
The loop feeds itself: the equipped knife = the Murderer's perk; kills loot a random knife off the
victim's rack (returned if the Murderer is shot); survivors get 2x vault income for a while.

## Architecture (server-authoritative, assume exploiters)
- `src/server/Main.server.luau`: `CharacterAutoLoads` is off; `KnifeModel.Preload()` (mesh knives), then Map → Base → Steal →
  Guard → Upgrade → Inventory → Combat → Round → Debug → Data (last, so everyone is listening for PlayerLoaded), then
  characters load. CombatService respawns people after death.
- `DataService` UpdateAsync + retries + session lock; the only writer of player data. In Studio without API access it runs on temporary data.
- `MapService` builds the gameplay layout in code (arena zones, pedestals, 8 vaults); `ManorDecor` is
  the cosmetic hub; `RoundMaps` lays out the indoor round maps (random one per round) from `RoundMapKit`
  (walls with trim and per-face wallpaper, windows, lights, furniture; furniture front = local -Z, rotation
  0/180/-90/90 for north/south/west/east walls). Anything named "Floor" is where coins/Revolver land.
  Tags the client animates: "Flicker" (+ attribute Flame = soft waver), "ClockHand" (real time), "Coin".
- Round coins: the Blender "Coin" prop + invisible Hitbox (RoundService.spawnCoin); the client predicts the
  pickup (fly-in, streak chime) and the server pays.
- Hub layout (MapService): one long runway (ArenaWidth x ZoneDepth per zone) with hideaway nooks in the walls
  (guards ignore players inside), vaults in two columns opening onto a plaza at the start, events board over the
  entrance, round maps far away at x = 3000. ManorDecor dresses each zone as its own biome.
- Speed (Steal An Egg style): `profile.Speed` is trained by standing in your vault's Haunted Wheel (the code calls
  it the treadmill; tiers in `GameConfig.Treadmills`), turned into walk speed by `GameConfig.WalkSpeedFor`. Zones have
  `SpeedNeeded` and guards fast enough to catch anyone below it. No dash.
- `BaseService` vaults, wall mounts, the Haunted Wheel training tick, income tick, and the single `RefreshWalkSpeed`.
- `StealService` dropped knives (tag + light beam + "Take" prompt), carrying, deposit on the server's view of position,
  carrier speed check; a carrier who dies drops the knife where they fell.
- `CombatService` the hub knife Tool (equipped or best owned, else the Rusty Shank): swing (Tool.Activated) and throw
  (Remotes.Ability outside rounds) - only guards take damage. Also every death: `Ragdoll` collapse + death cry.
- `GuardService` R15 night watchmen (named, animated) but anchored and moved on Heartbeat. Health/damage per zone,
  each holds a knife from its zone pool (the loot), attacks players near it in its zone, fights back when hit;
  picking up a knife alerts the zone + the one in front; Epic+ throw knives; death = ragdoll, drop, respawn.
- `PowerService` Innocent Powers (Vanish, Radar, Bear Trap, Shield, Decoy, Mimic): bought/upgraded with cash, equipped
  in a loadout (PowerSlots), usable in the arena vs guards (cooldowns) and in rounds vs the Murderer (uses per round).
  Contracts are attributes: player `Invisible`/`Mimic` (guards ignore), character `ShieldUntil` (guards + RoundService
  respect it), player `StunnedUntil` (walk speed 0). `Stealth` hides/restores characters for Vanish and Mimic.
- `InventoryService` equip / sell (vault wall prompts: E equip, hold F sell; also the Knives menu). `UpgradeService` also sells one-round items (Shield, Sneakers, Smoke).
- `Disguises` round outfits: classic Shirt/Pants templates + face decals (`tools/make_clothing.py`, uploaded image ids
  inline) and Blender hair/hats/glasses from PropMeshes (part fallbacks). `Shift` = ShapeShifter perk. `Revolver` the pickup/tool. `DebugService` Studio-only hook.
- `RoundService` phase loop; state is attributes on ReplicatedStorage (Phase, PhaseEndsAt, Status, Alive, MapName,
  Revolver, Loot). Melee from `Tool.Activated`; perks via `Remotes.Ability`, gun via `Remotes.Shoot` - all validated server-side.
- Client modules (`src/client`): Ui, Hud, Menus (Knives/Shop panels), Abilities (knife input: click combo,
  hold RMB/Q/LT/button to charge a throw), Effects (cosmetic `Remotes.Effect`), Moves (animation engine).
- Animations are procedural, no uploaded assets: clips live in `src/shared/AnimLibrary.luau` as keyframes of joint
  angles (degrees; see its header for axes). `Moves` layers them on top of the Animator every PreSimulation by
  multiplying joint `Transform`s (works on AnimationConstraint rigs, which is what R15 uses now - not Motor6D).
  Server triggers clips with `Net.Animate(model, clip, exceptPlayer)`; held states come from attributes
  (character `ChargeStart`/`ChargeTime`, player `Carrying`, a held Revolver) and guards tagged `Guard`.
  Damage waits for a clip's `Impact`, thrown knives leave the hand at `Release`.
  The HUD reads player attributes; clients only send requests.
- Tunables: `src/shared/Config/GameConfig.luau`. Knife catalog: `Config/Knives.luau`. Sound ids: `Config/Sounds.luau`.
- Knives: Blender meshes (`Config/KnifeMeshes.luau`, generated from the uploaded models) turned into templates at
  startup by `KnifeModel.Preload`; part-built fallback if meshes fail. Held knives are normalised to 2.4 studs.
- Bots fill every round up to `GameConfig.BotFill.Size` (live too), so one real player can start a round; alone with
  bots, a bot is sometimes the Murderer. Rounds with fewer than 2 real players pay `BotRoundPay`. Studio "Bot Round:
  Murderer / Innocent" buttons (or `Debug:Invoke("BotRound", player, role)`) force a 3-bot round now. Brains live in
  RoundService (wander, flee, hunt); `Round.Murderer` is nil when the Murderer is a bot (`Round.MurdererBot`).
- Murderer melee: the client sends who it swung at (`Remotes.Stab`); the server accepts it within
  AttackRange + StabLagSlack with no "Wall" in between, else falls back to its own closest-in-front check.
  The knife arrives unequipped in the hotbar; pulling it out is the reveal.
- Round pay scales with income (`GameConfig.RoundPay`, `GameConfig.Pay`): coins, survive, kill, hero, team win
  (dead innocents on the winning side), wipe (+ per real victim + a sealed case).
- Items (`src/shared/Items.luau`): owned knives are strings `"Name|Mutation|Size"` (plain `"Katana"` still valid).
  Mutations Gold/Diamond/Rainbow/Void and sizes Tiny..Colossal multiply income/damage. Watchmen drop sealed CASES
  (`StealService.DropCase`); `StealService.OpenCase` rolls the item (rebirth luck) and fires the client reel
  (`client/Unbox`). The Case Shop (`Rewards.BuyCase`, Purchase "Case:<Rarity>") uses the same path.
- Vaults: knives float over 12 Blender pedestals (MapService slots, BaseService.RefreshRack: nameplate billboard,
  light beam, aura). Aura = `Items.AuraPower`: sparks/flames/crackle + dashed floor ring; non-owners inside it are
  slowed (RaidService.stepAuras -> player AuraSlow/AuraFrom). Walls per tier (`VaultWalls`, GameConfig.Walls) with a
  gate whose invisible Blocker is solid client-side for non-owners (client/Raid) and evicted server-side.
- Break-ins (`RaidService`): any time in Intermission, gates have health (Targets registry: hub swings/throws hit
  gates and knock players down), break, reforge, regen; the owner is alerted on the first hit and can repair (R).
  Not while the owner is in a round or has the new-player shield. Steal from broken vaults (protected = the item
  you fight with, `BaseService.ProtectedItem`); revenge window; the owner's hit sends a thief home (player
  `StolenFrom`). The Raid is now an event: burglar NPCs (max 1 knife per vault per raid) + anyone knockable.
- Retention (`Rewards`): offline earnings (`GameConfig.Offline`, from profile `LastSeen`) and the 7-day login streak
  (`GameConfig.Daily`, `Remotes.ClaimDaily`), shown by `client/Welcome` on join (`Remotes.Welcome`). New-player
  shield: `DataService.IsNewPlayer` (PlayTime < `NewPlayerShield`, no rebirths) blocks break-ins, burglars and loot.
- `tools/pacing_sim.py`: rough simulation of a player's first hours (milestones and long gaps) from the config numbers.
- Powers in rounds cost Energy (coins refill it, PowerService.AddEnergy). New: Flash (blind, hooks via
  PowerService.OnFlash) and Barricade (`Obstacles` registry: guards/burglars/Murderer smash it).
- Rebirth (UpgradeService "Rebirth"), Index rewards + free plaza chest + leaderboards (`Rewards`), tutorial
  (client/Tutorial), speed trails (BaseService.updateTrail), music/heartbeat/raid sky/final kill (client/Atmosphere).
- Blender props: `blender/scripts/make_props.py` -> upload -> `Config/PropMeshes.luau`, built by `Props.Build(name)`
  (part fallbacks if missing). Textures: `blender/scripts/make_textures.py` -> Studio upload_image -> `Config/Textures`.
- Studio test buttons (left column): Bot rounds, Raid toggle, Epic case drop. Debug hook also has "Case", "Raid",
  "Walls", "Drop".
- Lighting.Technology can't be set from scripts: set it to Future in Studio's Properties.
- Studio testing: `ReplicatedStorage:SetAttribute("DebugMinPlayers", 1)` + `SetAttribute("DebugSkip", true)` starts a
  solo round; `game.ServerStorage.Debug:Invoke("Give", player, {"Katana"})` / `("Cash", player, n)`. Command-bar code
  gets its own module copies, so go through that hook for live state.

## Toolchain (all installed)
- **Roblox Studio** with its built-in MCP server (`Roblox_Studio` in `.mcp.json`). You need Studio open
  with a place loaded, and Assistant → … → Manage MCP Servers → "Enable Studio as MCP server" on.
- **Rojo 7.7** (via Rokit, `rokit.toml`): `rojo serve` syncs `src/` into Studio. Code lives in files,
  not in Studio. Selene (lint) + StyLua (format) are pinned too.
- **Blender 4.5** + MCP for Blender (`blender` in `.mcp.json`). In Blender: N panel → "MCP for Blender" → Connect.
- **Open Cloud upload**: `python tools/upload_model.py <file.fbx> "<Name>"` uploads to Roblox with the
  API key in `.env` and prints `ASSET_ID=...`; ids are logged in `blender/uploaded_assets.json`.

## Layout
- `src/shared` → ReplicatedStorage.Shared (config, shared modules)
- `src/server` → ServerScriptService.Server
- `src/client` → StarterPlayer.StarterPlayerScripts.Client
- `blender/scripts/*.py` procedural model builders (run headless: `blender -b --factory-startup --python <script>`)
- `blender/exports/*.fbx` export output (gitignored, regenerate from scripts); `blender/previews/` renders

## Model pipeline
1. Build/modify in Blender (script in `blender/scripts/`, or live through Blender MCP).
2. Export FBX: separate meshes per part, origin at the grip, low poly.
3. `python tools/upload_model.py blender/exports/X.fbx "X"` (ids logged in `blender/uploaded_assets.json`).
4. Insert the model in Studio (MCP `insert_asset`), read each MeshPart's MeshId/Size/offset from the Handle, and paste
   into `Config/KnifeMeshes.luau`. Colours come from `Knives.luau` at runtime (FBX colours don't carry over).

## Checks (run after changes)
- `selene src` · `stylua src` · `rojo sourcemap default.project.json -o sourcemap.json && luau-lsp analyze --defs=globalTypes.d.luau --sourcemap=sourcemap.json src`
- `globalTypes.d.luau` is gitignored; fetch from https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau
- Solo play starts bot-filled rounds; for real PvP use Studio Test → Clients and Servers with 2 players.

## Conventions
- Luau, `--!strict` where practical. Server is authoritative for cash, ownership, and stealing.
- Never commit `.env`.
