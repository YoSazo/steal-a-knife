# Office + Mansion art pass

Completed 2026-10-06. Integrated into the existing round-map builders. The original building sizes,
floors, stairwell holes, invisible Ramp geometry, doors and spawns are unchanged. The Office storage
shelf at (-73.5, -32) moved along the same wall to (-73.5, -42) after physical traversal found that
it blocked the side door to the stairs.

## Room changes

All windows now have a night-blue backdrop, a small skyline and a square moon behind separated
glass layers. Existing room furniture, wall finishes and recognizable landmarks remain.

| Office room | Art added or replaced |
| --- | --- |
| IT | Three server racks, stacked drawers, vents and neon status indicators replace generic wall shelves. |
| Open office | Plan cabinet and coffee station supplement the cubicle desks. |
| Staff lounge | Magazine stand and coffee station beside the sofas. |
| Meeting room | Plan cabinet and coffee station support the existing meeting table/projector. |
| Boss office | Trophy cabinet and plan drawers. |
| Cafeteria | Serving line with food pans, overhead shelf and tray stack. |
| Stair hall / landing | Uploaded Blender metal staircase and matching metal landing balustrades. |
| Storage | Parcel trolley and plan cabinet; existing shelf moved clear of the side door. |
| Office B | Plan cabinet and coffee station. |
| Break room | Coffee station and tray stack. |
| Reception | Magazine stand and luggage. |
| Mail room | Two loaded parcel trolleys. |
| Archives | Plan cabinet and parcel trolley. |
| Conference hall | Coffee station and plan cabinet. |
| Training room | Trophy cabinet and plan cabinet. |
| Game room | Pool table with cushions, balls and cue; magazine stand. |
| Library | Magazine stand and plan cabinet. |

| Mansion room | Art added or replaced |
| --- | --- |
| Grand hall | Existing red runner, fireplace, piano and chandeliers retained; windows gain outside scenes. |
| Wine cellar | Three bottle-filled wine racks replace generic shelving. |
| Kitchen | Coffee station and tray stack. |
| Dining room | Serving line and tray stack. |
| Stair hall / landing | Uploaded Blender wooden stairs with turned balusters/newels, gold caps and matching landing balustrades. |
| Master bedroom | Luggage and magazine stand. |
| Study | Large raised map table and plan cabinet. |
| Library | Magazine stand and plan cabinet. |
| Trophy room | Trophy cabinet and hanging antler chandelier replace the generic chandelier. |
| Nursery | Crib, rocking horse and bright toy blocks replace the generic bed/crates. |
| Guest bedroom | Luggage and magazine stand. |
| Gallery | Two trophy cabinets. |
| Card room | Magazine stand and luggage. |
| Attic | Two covered furniture pieces and two raised cobweb models. |

## Files and hooks

- `src/server/Services/RoundMapDressing.luau`: map/room/floor placements; called by RoundMaps.Build.
- `src/shared/Config/ToyGeometry/RoundMapArt.luau`: 22 measured, solid native prop builders' geometry.
- `src/shared/Assets/RoundMapArt.luau`: standalone Build/Preload, mesh templates and matching native fallback.
- `src/shared/Config/RoundMapArtMeshes.luau`: uploaded mesh ids, verified sizes, offsets and colours.
- `src/server/Services/RoundMapKit.luau`: art mounting, preserved Ramp, themed landing rails,
  separated window scenery, solid visible props/signs, no local Light instances.
- `src/server/Services/RoundMaps.luau`: art calls and the storage shelf clearance correction.
- `src/shared/Config/RoundMapInfo.luau`: only the two Image values changed.
- `tools/build_round_map_art.py`: regenerate measured native geometry.
- `blender/scripts/build_round_map_art.py`: export the four stair/landing models and review renders.
- `tools/package_round_map_art.py`: validate imported mesh bounds and package config/gallery.
- `tools/package_map_shots.py`, `tools/package_room_review.py`: crop/package actual Studio screenshots.
- `tests/RoundMapArt.studio.luau`, `tests/RoundMapWalk.studio.luau`: isolated Studio regression probes.

All native models have a floor pivot and face -Z unless used as a wall/hanging decoration.
Stair flight: 8 studs wide, 28 deep, rises 15; bottom at +Z, climbing toward -Z. Rails extend above
the 15-stud flight. Landing art is an 8-stud section stretched to each original railing segment.
Left/right stair rails are separate collision meshes, keeping the walking corridor open.

## Uploaded assets

| Asset | Model id | Model BaseParts, including invisible origin |
| --- | ---: | ---: |
| Office stairs | 93782231220180 | 6 |
| Mansion stairs | 122703709070393 | 8 |
| Office balustrade | 107077352853490 | 3 |
| Mansion balustrade | 74548422958197 | 3 |

Underlying mesh ids are in RoundMapArtMeshes. Flat colours use native tinting; no texture required.
The FBX importer reflects these symmetric models in X; the config preserves verified imported
coordinates and names rails by their final side.

| Vote photo | Image id used in config | Uploaded decal id |
| --- | ---: | ---: |
| Office | 123212136782613 | 77617794151872 |
| Mansion | 73665715137680 | 74761371919674 |

Both images loaded and rendered successfully in a Studio ImageLabel check. Source PNGs are
`assets/map-shots/map_office.png` and `map_mansion.png`, 640×504. Actual Studio camera, FOV 70,
head-height framing, no characters/UI/text overlays. Room-name glyphs were hidden only on temporary
review geometry for the Office photo; the game's signs retain their words. Office looks west from
the east corridor; Mansion looks from the front doors toward the fireplace.

## Verification

Final maps built in Server during Play and scaled 1.5× exactly as the game does:

```text
Office 32 spawns, unreachable:
Mansion 26 spawns, unreachable:
```

Pathfinding used AgentRadius=1.6, AgentHeight=5, AgentCanJump=false. Every spawn is reachable
from the first; both failure lists are empty. No new prop intersects a spawn or the four-stud
doorway clearance area. Comparison against the original baseline confirms exact door, ramp and
spawn data. New art stays clear of the stair flight and its approach.

| Map | Final BaseParts | Spawns | Lights | Unexpected non-solid visible parts |
| --- | ---: | ---: | ---: | ---: |
| Office | 11,138 | 32 | 0 | 0 |
| Mansion | 4,672 | 26 | 0 | 0 |

Physical R15 probe (no jumping): all 58 doorways crossed in both directions, 116/116 passes.
Both staircases ascended and descended successfully; probe root height went from ~3.34 to ~25.69
studs and back on each map. Results are in `assets/round-map-art/door-walk-final.json` and
`stair-walk-final.json`. Two camera angles per room/landing were inspected; no visible z-fighting
was found in those views. This is a Studio visual/traversal check, not a phone FPS benchmark.

Selene: zero errors/warnings. StyLua formatting/check passed. Luau-LSP: zero source diagnostics
(its usual command-line didChangeWatchedFiles capability notice remains). Rojo build passed,
output `.cache/round-map-art/StealAKnife-art-check.rbxl`. Git whitespace check passed.

Temporary review maps/rigs and capture UI were removed; Studio returned to Edit.

## Review gallery

- `assets/round-map-art/vote-gallery.png`: final vote-board crops.
- `assets/round-map-art/stairs-gallery.png`: Blender stair and balustrade renders.
- `assets/round-map-art/mansion-stair-studio.png`: actual in-game stair view.
- `assets/round-map-art/office-rooms-1.png` through `office-rooms-3.png`.
- `assets/round-map-art/mansion-rooms-1.png` through `mansion-rooms-3.png`.
- `assets/round-map-art/room-shots/`: all 64 individual room views.

No further gameplay wiring is needed. Existing map voting and RoundMaps.Build now use these assets.
