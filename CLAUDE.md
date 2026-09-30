# Steal a Knife — Roblox game

Steal-and-collect + Murder Mystery 2-style rounds. Players steal knives from an arena guarded by NPCs
(deeper zone = rarer knife, faster guards), carry them home to a vault rack that pays cash/s, buy
Speed / rack Slots / Murderer tickets, and every few minutes everyone is pulled into a round with one
random Murderer (weighted by a luck meter + tickets) and a survival timer. No Sheriff, no PvP in the arena.
Rarities: Common, Rare, Epic, Legendary, Godly. Audience ~9-15: bright, low-poly, cartoony.

## Architecture (server-authoritative, assume exploiters)
- `src/server/Main.server.luau` inits services in order: Map → Base → Steal → Guard → Upgrade → Round → Data (last, so everyone is listening for PlayerLoaded).
- `DataService` UpdateAsync + retries + session lock; the only writer of player data. In Studio without API access it runs on temporary data.
- `MapService` builds the whole world in code (arena zones, 8 bases, round map at z=2000).
- `BaseService` vaults, rack, income tick, and the single `RefreshWalkSpeed`.
- `StealService` pedestals/ProximityPrompts, carrying, deposit on the server's view of position, carrier speed check.
- `GuardService` anchored NPCs moved on Heartbeat; chase carriers, leash to their zone, never enter bases.
- `RoundService` phase loop; state is attributes on ReplicatedStorage (Phase, PhaseEndsAt, Status, Alive). Hits are validated server-side from `Tool.Activated`.
- Clients only fire `Remotes.Purchase(kind)`; everything shown in the HUD comes from player attributes.
- Tunables: `src/shared/Config/GameConfig.luau`. Knife catalog: `src/shared/Config/Knives.luau`. Knives are Part-built in `src/shared/KnifeModel.luau` (swap to MeshParts there).
- Not built yet: knife perks, pre-round shop, equip menu, console-specific polish beyond D-pad shortcuts.

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
3. `python tools/upload_model.py blender/exports/X.fbx "X"`, then insert the asset id in Studio via Studio MCP `insert_asset`.
4. Apply part colors from `blender/knives.json` in Studio (FBX material colors don't carry over reliably).

## Checks (run after changes)
- `selene src` · `stylua src` · `rojo sourcemap default.project.json -o sourcemap.json && luau-lsp analyze --defs=globalTypes.d.luau --sourcemap=sourcemap.json src`
- `globalTypes.d.luau` is gitignored; fetch from https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau
- Solo play won't start a round (MinPlayers = 2): use Studio Test → Clients and Servers with 2 players.

## Conventions
- Luau, `--!strict` where practical. Server is authoritative for cash, ownership, and stealing.
- Never commit `.env`.
