# Codex prompt: polish the murder-round maps (Office + Mansion) and make the vote-board shots

Repo: `C:\Users\samat\StealAKnife` (Roblox, Luau, Rojo 7.7 syncing `src/` into Studio; Blender 4.5 for
props). Read `CLAUDE.md` first. Claude already built the layouts, stairs and voting. Your job is the
**art pass**: make both maps look like real, lived-in buildings, and replace the vote-board pictures
with proper shots. Do not change gameplay, layout, doors, spawns or sizes unless a step says so.

## Where things are

- `src/server/Services/RoundMapKit.luau`: the building kit. Walls with trim (`Kit.wall`), floors,
  `Kit.slab` (a slab with rectangular holes), `Kit.stairs` (solid steps + an invisible `Ramp` part
  that feet and bot pathfinding walk on; returns the stairwell hole), `Kit.railing`, `Kit.Level(n)`
  (build on storey n; `Kit.STOREY` = 15 studs), and ~70 furniture builders (desk, bookshelf,
  chandelier, fourPosterBed, ...). Furniture is built in a local frame: FRONT = local -Z; rotation
  0/180/-90/90 = against the north/south/west/east wall.
- `src/server/Services/RoundMaps.luau`: the two layouts.
  - **Office** (225 x 110 at 1x): ground = 12 rooms off a marble corridor (IT, open-plan office,
    staff lounge, meeting room, boss's office, cafeteria / stair hall, storage, office B, break room,
    reception, mail room). Upstairs over the west half (x -112.5..0): archives, conference hall,
    training room, game room, library, the stair landing.
  - **Mansion** (230 x 110): central hall + two wings each side (wine cellar, kitchen, dining room,
    grand stair hall / master bedroom, study, library, trophy room). Upstairs over the west wings
    and the hall (x -115..25): nursery, guest bedroom, gallery, card room, attic, landing.
- `src/server/Services/MapService.luau` `BuildRoundMap`: builds at 1x then `ScaleTo(1.5)`.
- `src/shared/Config/RoundMapInfo.luau`: name, colour, blurb and **Image** (the vote-board shot)
  per map. `src/server/Services/MapVote.luau` draws the boards at the back of the plaza.
- Props from Blender: `blender/scripts/make_props.py` -> upload -> `src/shared/Config/PropMeshes.luau`,
  built with `Props.Build(name)` (part fallbacks if a mesh is missing). Chandeliers and sconces
  already work this way.

## Hard rules (each one was a real bug)

1. **Everything is solid.** Nothing a player can walk through: in `RoundMapKit`, `deco()` parts
   collide (only `Rug` and `CeilingGrid` don't). New props must collide too (mesh CollisionFidelity
   Box or Hull is fine).
2. **No flicker (z-fighting).** Never put two visible faces in the same plane or within ~0.05 studs:
   no paper/paint layer laid flush on a wall, no stacked rugs or floors 0.02 apart. Shared walls
   are already two half-thickness slabs, one per room's paper; keep it that way. Floor layers
   stack with real gaps (see the upstairs slab: white ceiling slab, then carpet, then room floors).
3. **Keep doorways clear.** Every room keeps two ways out. Nothing within 4 studs of a door opening,
   on either side. (Three new doors were first blocked by a china cabinet, a counter and bookshelves.)
4. **Keep the stairs working.** Don't put anything over a stairwell, under a staircase's walking
   line, or in the 8 studs in front of the bottom step. The stairwell hole is 2 studs wider than
   the flight on purpose (bot pathfinding needs it). No ceiling detail across a stairwell.
5. **Spawns and coins.** Don't put furniture on a spawn point (`spawns` at the end of each builder).
   Coins land on parts named exactly `Floor`, so new floor pieces must be named `Floor`, and
   nothing tall should cover large areas of floor.
6. **One even light.** No `PointLight` / `SpotLight` / `SurfaceLight` anywhere (MapService strips
   them). Use Neon for anything that should look lit (bulbs, lampshades, windows).
7. **Keep it small for phones.** Part count matters on phones. The Office is ~10.8k parts after
   building; don't go above ~13k per map. Prefer one mesh over many little parts.

## What to do

### 1. Art pass, both maps
- Make every room read at a glance as what it is, from the doorway, in under a second. Add the 2-3
  hero props each room is missing (e.g. the cafeteria serving line and trays, server racks with
  blinking neon LEDs in the IT room, a pool table in the game room, a big map table in the study,
  cribs/rocking horse/toy blocks in the nursery, dust sheets over furniture and cobwebs in the attic,
  wine racks with bottles in the cellar, a hanging antler chandelier in the trophy room).
- The stairs: model a proper staircase in Blender for each map (the Office: a modern straight flight
  with a metal handrail; the Mansion: a grand wooden staircase with turned balusters and a newel post).
  Keep the exact footprint `Kit.stairs` uses (28 long x 8 wide x 15 high at 1x, bottom step at +Z)
  and keep the invisible `Ramp`; replace only the visible steps and rails.
- Upstairs landings: a proper balustrade round each stairwell (the current `Kit.railing` is a plain
  rail with thin balusters).
- Windows: show something outside (a simple night or sky backdrop beyond the glass) instead of nothing.
- Keep the look: blocky Roblox 2013 / The Mad Murderer style, toy-bright colours, readable shapes.

### 2. New vote-board shots (replace the current Studio screenshots)
The boards copy MM2's vote frames: a picture of the actual map. Make one shot per map:
- **Office**: the long ground-floor corridor, from the east end looking west (doors and signs down
  both sides, ceiling lights receding).
- **Mansion**: the grand hall from the front doors towards the fireplace (red runner, chandeliers).
- In Studio: build the map (Studio command bar, or a Studio bot round), hide all GUIs, point a
  Scriptable camera from about head height, FOV 70, and take the screenshot. Crop to **1.27:1**
  (e.g. 640 x 504). No characters, no UI, no text in the image (the board adds the map name).
- Save to `assets/map-shots/map_office.png` and `map_mansion.png`, upload (Studio upload_image or
  `tools/upload_model.py`'s Open Cloud key), and put the new `rbxassetid://` ids in
  `RoundMapInfo.luau` (`Image = ...`).

### 3. (Optional) A third map
If there's time: a third building in the same style (ideas: a hotel, a school, a museum) with an
upstairs, 14-18 rooms, every room with two exits, the stairs in a dedicated stair hall. Add it to
`RoundMaps.Builders` / `RoundMaps.Names`, give it an entry in `RoundMapInfo` (with a shot), and the
vote boards pick it up automatically (they lay out one board per entry).

## Checks before you hand back

1. `selene src`, `stylua src`, and luau-lsp (see CLAUDE.md "Checks"): 0 errors, 0 warnings.
2. **Reachability test** (run in Studio's server command bar while playing; must print an empty
   list for each map). It builds the map off to the side, scales it like the game does, and asks
   bot pathfinding to reach every spawn from the first:
   ```lua
   local RoundMaps = require(game.ServerScriptService.Server.Services.RoundMaps)
   local PFS = game:GetService("PathfindingService")
   for i, name in RoundMaps.Names do
     local center = Vector3.new(6000 + i * 600, 0, 0)
     local holder = Instance.new("Folder"); holder.Parent = workspace
     local built = RoundMaps.Build(holder, center, name)
     local folder = holder.RoundMap
     local model = Instance.new("Model")
     for _, c in folder:GetChildren() do c.Parent = model end
     model.WorldPivot = CFrame.new(center); model:ScaleTo(1.5)
     for _, c in model:GetChildren() do c.Parent = folder end
     task.wait(2)
     local fails = {}
     local first = center + (built.Spawns[1].Position - center) * 1.5
     for j = 2, #built.Spawns do
       local to = center + (built.Spawns[j].Position - center) * 1.5
       local path = PFS:CreatePath({ AgentRadius = 1.6, AgentHeight = 5, AgentCanJump = false })
       pcall(path.ComputeAsync, path, first, to)
       if path.Status ~= Enum.PathStatus.Success then table.insert(fails, j) end
     end
     print(name, #built.Spawns, "spawns, unreachable:", table.concat(fails, ","))
     holder:Destroy()
   end
   ```
3. Walk both maps yourself in Studio (Play): up and down every staircase, through every door, and
   orbit the camera in every room looking for flicker.
4. Count parts per built map (`#folder:GetDescendants()` BaseParts): under ~13k.

Hand back: a summary of what changed per room, the new asset ids, the reachability output and the
part counts.
