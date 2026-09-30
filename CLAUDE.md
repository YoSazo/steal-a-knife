# Steal a Knife — Roblox game

"Steal a Brainrot"-style tycoon, but with knives. Players own a base with pedestals. Knives walk/slide
down a conveyor in the middle of the map; you buy one with cash, it goes on a pedestal and earns cash
per second. Other players can run into your base, grab a knife, and carry it back to theirs, so you
have to lock your base or chase them down. Rarer knives (Common → Mythic) earn more.

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

## Conventions
- Luau, `--!strict` where practical. Server is authoritative for cash, ownership, and stealing.
- Never commit `.env`.
