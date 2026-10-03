# Steal a Knife — Roblox game

Loop: knives earn cash -> cash buys Innocent Powers -> knives arm the Murderer, powers arm innocents -> rounds steal
and return knives. Steal-and-collect + Murder Mystery 2-style rounds. Players fight their way into an arena of NPC watchmen
(deeper zone = rarer knife, tougher guards), kill a guard to make it drop the knife it holds, carry
that knife home and mount it on their vault wall, which pays cash/s. They buy
Speed / rack Slots / Murderer tickets, and every few minutes everyone is pulled into a round with one
random Murderer (weighted by a luck meter + tickets) and a survival timer. No Sheriff, no PvP in the arena.
Rarities (one biome zone each): Common, Rare, Epic, Legendary, Mythic, Godly, Celestial, Cosmic (24 knives,
3 per rarity). Money is Steal An Egg-sized (starter knife $75/s, into the quintillions; `shared/Format` prints
K/M/B/T/Qd/Qn/Sx/...). Audience ~9-15, low-poly.
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
  Tags the client animates: "Flicker" (+ attribute Flame = soft waver), "ClockHand" (real time), "Coin",
  "ShopNPC" (shopkeeper fidgets).
- Murderer perks: Spam Knife is passive (every click throws at the cursor, no stab, Range 1000; client sends
  `Ability(aim, "Spam")`); Hellfire's Q sets player SpamUntil for the same click-throw mode with flaming knives.
  Stunned (Flash / trap: StunnedUntil) Murderers can't stab, throw or use perks. Perk icons are Blender renders
  (`blender/scripts/make_icons.py` -> Config/Textures.PerkIcons): ability button, perk card, knife cards.
- Raiders: damaging a gate marks you (player RaiderOf/RaiderUntil); the owner's knife then does real damage to you
  anywhere in the hub (RaidService playerTargets), like a guard - health levels decide how many hits you take.
- Round coins: the Blender "Coin" prop + invisible Hitbox (RoundService.spawnCoin); the client predicts the
  pickup (fly-in, streak chime) and the server pays.
- Hub layout (MapService): one long, wide runway (ArenaWidth 160 x ZoneDepth per zone, 8 zones, solid walls - the
  old hideaway nooks were removed because people farmed guards from them), vaults in two columns opening onto a
  plaza at the start, events board over the entrance, round maps far away at x = 3000. ManorDecor dresses each
  zone as its own biome (Courtyard, Gardens, Crypts, Catacombs, Inferno, Mount Olympus, Heavens, Outer Space).
- Vaults grow a floor at a time (Tsunami style, FLOOR_HEIGHT 16): each floor = a walkway down the middle, a ladder
  at the back middle (invisible TrussPart + drawn rails/rungs) up through a slot cut in the deck above, with a small
  landing behind it to step onto (Roblox trusses step you off in the direction you push), 5 flat cyan disc plates
  down each side (no vault sign; SAFE ZONE is painted on the plaza by the thin red line at the runway start) (GameConfig.SlotsPerFloor 10, up to
  4 floors = MaxSlots 40). The "Slot" upgrade / Mount product buys the next floor (+10, GameConfig.FloorCosts);
  MapService.SetFloors shows the owned storeys (BaseSite.FloorFolders) and VaultWalls.Build(..., floors) sizes the
  frame. The Haunted Wheel stands outside the gate. Burglars only rob the ground floor.
- Shopkeepers (`ShopNPCs`): Mortimer the Knife Merchant (cases + Health) and Madame Vesper the Mystic (Powers), side by
  side by the runway entrance (striped toy stalls, glowing floor ring, one gradient title); their "Talk" prompt (attribute ShopPanel) opens the panel client-side (Menus), walking away closes it.
- Health: profile HealthLevel (cash, GameConfig.Health), Titan pass (x2) and HealthBoost product; CombatService
  .ApplyHealth sets MaxHealth (rounds stay at 100). HUD draws its own health bar bottom centre (CoreGui Health off).
- Speed (Steal An Egg style): `profile.Speed` is trained by standing in your vault's Haunted Wheel (the code calls
  it the treadmill; tiers in `GameConfig.Treadmills`), turned into walk speed by `GameConfig.WalkSpeedFor`. Zones have
  `SpeedNeeded` and guards fast enough to catch anyone below it. No dash.
- `BaseService` vaults, wall mounts, the Haunted Wheel training tick, income tick, and the single `RefreshWalkSpeed`.
  Income is Tsunami style: every second each knife adds to profile.Pending[slot], shown on its green cash pad
  (BaseSite.CashPads/CashLabels) beside the plate; the owner walking over a pad collects it (CashBurst effect).
  Offline earnings still pay straight into cash. `client/Overheads` shows everyone's cash over their head (hub only).
- `StealService` dropped knives (tag + light beam + "Take" prompt), carrying (overhead), carrier speed check; a carrier
  who dies drops the knife where they fell. Knives are NOT auto-deposited: at home the next empty plate gets a "Place
  Knife" prompt (BaseService placePrompts, enabled while Carrying) -> StealService.Place (flying-knife "PlaceKnife"
  effect, then deposit). Cases still open on arrival. Equipping fires Effect "Equipped" (knife flies to your hand +
  banner) and the Draw clip. Each vault has an Upgrade Base sign by the gate (client/Hud fills it; prompt -> "Slot").
- Fuel (`Fuel` service, GameConfig.Fuel): 🔥 Heat 0-10 (profile.Heat) fills from boss steals, surviving rounds,
  Murderer wins; halves when you die in a round, -1 when a boss catches you; boosts vault income and power-roll luck.
  Murderer meter = profile.Luck (+2 per round not picked, +1 steal/survive, -1 death/caught, 0 when picked),
  capped at 3x the server average; no Robux way to raise it (MurdererLuck pass + Tickets product removed).
- Murderer powers are rare rolls on the ITEM, not the knife type: items are "Name|Mut|Size|Power" (Power "" none,
  "?" unrolled; 3-field old saves keep their knife type's power). Items.Powers odds (Spam Knife 1 in 1000);
  rolled in Fuel.RollPower when a knife reaches a vault (deposit / case open) with Heat, rarity, pity and revenge
  luck; "PowerRoll" reveal + server announce for rare ones. A Sheriff who shoots the Murderer steals the power onto
  their own fighting knife (RoundService.stealPower); the robbed Murderer gets RevengeUntil luck.
- Hotbar knives show an icon (Tool.TextureId from Config/KnifeIcons, rendered by blender/scripts/render_knife_icons.py).
- Rounds: one innocent power per round (Loadout[1], GameConfig.RoundPowerLevel for everyone); Spam Knife is always on (passive: click = throw all round, giveWeapon sets SpamUntil);
  ~20% CLASSIC rounds (no powers/perks, ClassicPay); Radar only finds a Murderer whose knife is out (KnifeOut), the
  Murderer's speed boost only applies with the knife out; HUD shows "Your chance to be the Murderer" (MurdererChance);
  end-of-round VS card (Effect "RoundCard" -> client/Transitions).
- `CombatService` the hub knife Tool (equipped or best owned, else the Rusty Shank): swing (Tool.Activated) and throw
  (Remotes.Ability outside rounds) - only guards take damage. Also every death: `Ragdoll` collapse + death cry.
- `GuardService` = the biome BOSSES (name kept: powers/combat/raids call its API: All, Stun, Lure, FromPart,
  InReach, Damage, RootHeight). One per zone (GameConfig.Zones Boss/BossTitle/BossWear/Restock): a round character
  (Disguises.BuildCharacter, e.g. Frank the Groundskeeper ... Nick the Void Walker) on a small lair stage against
  the runway's side wall (GameConfig.BossLair / BossLairCenter: odd zones left, even right) in front of a wall of BossWallSlots knives (Items.OpenCase rolls). Idle until you hold E on
  a knife ("BossSteal" prompt); then they chase you (a ForceField shadow clone if they're busy) at GuardSpeed to
  the plaza. Caught = StealService.ReturnToBoss puts it back + Damage x2; delivered = slot restocks after Restock s
  (rare mutations announced). Hub hits stagger a chaser (damage / zone Health, with immunity); Vanish makes them
  stop and search; Epic+ throw knives. StealService carries a `Boss` slot ref; OnBossCarryEnded hook.
- `PowerService` Innocent Powers (Vanish, Radar, Bear Trap, Shield, Decoy, Mimic): bought/upgraded with cash, equipped
  in a loadout (PowerSlots), usable in the arena vs guards (cooldowns) and in rounds vs the Murderer (uses per round).
  Contracts are attributes: player `Invisible`/`Mimic` (guards ignore), character `ShieldUntil` (guards + RoundService
  respect it), player `StunnedUntil` (walk speed 0). `Stealth` hides/restores characters for Vanish and Mimic.
- `InventoryService` equip / sell (vault wall prompts: E equip, hold F sell; also the Knives menu). `UpgradeService` also sells one-round items (Shield, Sneakers, Smoke).
- `Disguises` round outfits: classic Shirt/Pants templates (`tools/make_clothing.py`) + face decals
  (`tools/make_faces.py`, 12 faces, 4x supersampled) and Blender hair/hats/glasses from PropMeshes (part fallbacks).
  Hair is sculpted by `blender/scripts/hair.py` (a cap fitted to the R15 head down to a hairline that stays above the
  eyebrows + tapered locks; 8 styles); hats are worn 1.12x over hair; Wear.On puts pieces on the body (wings). `Shift` = ShapeShifter perk. `Revolver` the pickup/tool. `DebugService` Studio-only hook.
- Rounds: maps are built at 1x then scaled 1.5x (MapService.BuildRoundMap, ROUND_SCALE); doors are solid. A random
  innocent (player or bot) is the Sheriff from the start (giveRevolver / giveRevolverToBot); the floor Revolver only
  appears if nobody holds it. Bot Sheriffs aim + shoot once the Murderer's knife is out (botShoot, distance-based
  aim), other bots grab a dropped Revolver, the Murderer bot goes for the Sheriff first. Each innocent is shown the
  knife they'd lose (round.AtRisk, Effect "AtRisk" -> client/Transitions reel); lootKnife takes that one.
  Thrown knives start at CombatService.HandPosition (led by speed x ping).
- New players are told about both halves: top timer status "🔪 MURDER ROUND in" (RoundService.IntermissionStatus;
  RaidService compares it), first-visit welcome card "STEAL KNIVES ➜ BECOME THE MURDERER", a tutorial step on rounds,
  client/RoundIntro (10 s countdown card before your first round of the session), and a first-time player (attribute
  FirstVisit) pulls the next round in to GameConfig.NewcomerRoundIn (not during a Thief Moon). `src/first/LoadingScreen`
  covers the screen until character + HUD exist.
- Vault plates: profile.Plates[i] = the plate Knives[i] sits on; ALWAYS add/remove knives with
  DataService.AddKnife / RemoveKnife (never table.insert/remove on Knives). Any empty plate takes a carried knife
  ("Place Knife" on every free plate). One owner prompt per knife (Equip); selling is the thin Tsunami-style
  "SELL" sign by each plate (BaseService.sellSign, ClickDetector, precious knives need a second tap).
- Rule: a murder round never moves you in the hub. RoundService saves your spot (BaseService.SetReturnSpot) and
  the next TeleportHome (surviving, or respawning after dying in the round) puts you back there.
- Boss hits throw you like a ragdoll (Ragdoll.Tumble: server goes limp + sets player TumblePush/Tumbling, the
  owning client applies the fling in client/Tumble; the carry speed check skips Tumbling). Bosses are
  GameConfig.BossScale big, grab and throw without stopping, and search (not quit) when you Mimic/Vanish
  (MimicSpotRange). Mimic props move with you.
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
- Look: the toy style (Steal An Egg / Tsunami): bright flat colours + stud/checker Textures via `Shared/Toy`
  (`Toy.Dress(part, faces, studSize, checker)`, ids in `Textures.Toy`); zone floors in MapService ZONE_FLOORS,
  plaza in the same grass green as the first zone, navy vault frames. One `Toy.DirtWall` (tan dirt checker + grass cap, 40 tall)
  runs all the way round (runway sides, shoulders, hub sides + back: HubWall) and on lair backs. Zone names are not
  in the world: `client/Transitions` pops the title up on entering a zone and fades the screen on round teleports
  (server fires Effect "Fade" 0.35 s before moving people). Boss stash knives have
  NO labels (the knife speaks for itself; the prompt names it up close); vault labels are one compact block
  (rarity / name / $ per second). Sunny afternoon high in the sky (MapService.buildLighting: ClockTime 15.2, real
  sun, NO shadows and no Light instances anywhere (noLights strips them, round maps included) for one even light, day skybox from `tools/make_sky_day.py` -> `Textures.Day`, Terrain Clouds); the hub is a
  floating island (buildIsland: stepped studded earth under every floor, puffy cloud clusters around and below). No blood (hit bursts are yellow; the raid event is "Thief Moon" in text).
- Vaults: open Tsunami-style platforms (3 floors, 24 pedestals as navy/cyan plates). BaseService.RefreshRack: nameplate
  billboard, green floor money plaque (+$/s), light beam, aura (every knife: rising Money bills + a Swirl in its colour). Aura = `Items.AuraPower`: sparks/flames/crackle + dashed floor ring; non-owners inside it are
  slowed (RaidService.stepAuras -> player AuraSlow/AuraFrom). `VaultWalls` = open navy frame + glass rail + invisible
  walls, and a laser gate ("Pane" lasers, more lines per GameConfig.Walls tier) whose invisible Blocker is solid client-side for non-owners (client/Raid) and evicted server-side.
- Break-ins (`RaidService`): any time in Intermission. Gates have health (Targets registry: hub swings/throws hit
  gates at `Raid.PlayerGateDamage`, and knock down intruders/carriers), break, reforge, regen; the owner is alerted
  on the first hit with the attacker outlined, and can repair (R) or upgrade walls (hold G at their gate). Not while
  the owner is in a round, has the new-player shield, or was just robbed (`SealedUntil`, `Raid.RobbedSeal`). Steal
  from broken vaults (protected = the item you fight with); revenge window; the owner catching their thief gets the
  knife back (`StealService.Recover`) plus a bounty and sends them home. A Bear Trap set inside your own vault
  waits there. The "raid" is the Blood Moon event every `Raid.Every` intermissions: a few burglars, gates take more
  damage, bounties double, anyone not at home can be knocked down.
- Retention (`Rewards`): offline earnings (`GameConfig.Offline`, from profile `LastSeen`) and the 7-day login streak
  (`GameConfig.Daily`, `Remotes.ClaimDaily`), shown by `client/Welcome` on join (`Remotes.Welcome`). New-player
  shield: `DataService.IsNewPlayer` (PlayTime < `NewPlayerShield`, no rebirths) blocks break-ins, burglars and loot.
- Robux (`Config/Monetization.luau`, `MonetizationService`, client `Store`): 5 passes + products (cash packs scaled to
  income, Robux cases with odds shown, Starter Pack once, Mount, Tickets, Instant Repair, Server Luck, Chest Refill,
  Summon Blood Moon). Passes become player attributes `Pass_<Key>` that other services read; ProcessReceipt is
  idempotent (profile `Receipts`) and saves before granting. Ids are 0 until created on the dashboard; Studio fakes
  those purchases (`Remotes.StoreTest`). Contextual offers via `Offers.Show` (rate limited, never in rounds).
- `tools/pacing_sim.py`: rough simulation of a player's first hours (milestones and long gaps) from the config numbers.
- Powers in rounds cost Energy (coins refill it, PowerService.AddEnergy). New: Flash (blind, hooks via
  PowerService.OnFlash) and Barricade (`Obstacles` registry: guards/burglars/Murderer smash it).
- Rebirth (UpgradeService "Rebirth"), Index rewards + free plaza chest + leaderboards (`Rewards`), tutorial
  (client/Tutorial), knife trails (GameConfig.Trails bought via Purchase "Trail", profile.TrailLevel, Phantom Trail pass; drawn by client/KnifeTrails with the speed FOV/lines/wind/dust), music/heartbeat/raid sky/final kill (client/Atmosphere).
- Blender props: `blender/scripts/make_props.py` -> upload -> `Config/PropMeshes.luau`, built by `Props.Build(name)`
  (part fallbacks if missing). Textures: `blender/scripts/make_textures.py` -> Studio upload_image -> `Config/Textures`.
- Studio test buttons (left column): Bot rounds, Raid toggle, Epic case drop. Debug hook also has "Case", "Raid",
  "Walls", "Drop".
- Performance (`client/Lod`): picks a profile (High / Medium / Low from the graphics slider; phones max Medium,
  Low on Automatic) and every 0.2s keeps only nearby lights on (closest LightBudget) and nearby particles/fire;
  no bloom on Low. `Lod.Near(pos)` is the shared distance check: Moves skips far rigs, Effects skips far
  spinners/rainbows, KnifeTrails thins its stream. Rigs (guards, burglars, bots, shopkeepers) stream Atomic.
  Patrolling guards step at 20 Hz, chasing ones every frame. Avoid adding per-object lights where neon will do.
- Phones: `Ui.Phone` (touch, no keyboard) switches every HUD piece to a compact layout clear of Roblox's thumbstick
  (bottom left) and jump button (bottom right); `Ui.iconOnly` for menu buttons. Landscape is forced
  (PlayerGui.ScreenOrientation). Studio preview: ReplicatedStorage `DebugPhone = true` (draws touch-control ghosts).
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
