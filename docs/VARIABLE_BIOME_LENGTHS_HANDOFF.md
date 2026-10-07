# Variable biome lengths — implementation brief for Claude

Prepared 2026-10-06. Planning only: no gameplay, configuration, shell geometry or Studio changes
have been made for this request. Finish the current guide work before starting this migration.

## Intended result

Make the first boss steal quicker to reach and quicker to bring home, then increase biome lengths
with progression. Keep the eight bosses, rarities, visual themes, central lane, plaza, vaults,
existing guide artwork and prompts. This is a layout migration; leave economy, guard speeds,
power odds, rewards, round timing and saves unchanged in the first pass.

The supplied analytics report says 21% of new users never grab a knife and the median first grab
takes 30 seconds. Those are reported inputs, not independently verified live metrics in this
review. Measure the new first-steal funnel before concluding that the layout improved retention.

## Proposed layout

All coordinates below are world Z. The runway still begins at Z=0 and is 160 studs wide.
Lengths are the user's proposed sequence. Derive starts and ends cumulatively.

| Zone | Biome / boss | Depth | Start | End | Boss Z at current 0.6 fraction |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 | Courtyard / Frank | 90 | 0 | 90 | 54 |
| 2 | Gardens / Ivy | 130 | 90 | 220 | 168 |
| 3 | Crypts / Sam | 170 | 220 | 390 | 322 |
| 4 | Catacombs / Leo | 210 | 390 | 600 | 516 |
| 5 | Inferno / Ruby | 250 | 600 | 850 | 750 |
| 6 | Mount Olympus / Kate | 290 | 850 | 1140 | 1024 |
| 7 | Heavens / Zoe | 330 | 1140 | 1470 | 1338 |
| 8 | Outer Space / Nick | 370 | 1470 | 1840 | 1692 |

Current total: 8×220=1760. Proposed total: 1840 (+80, ~4.5%). Move the far wall, Manor and island
backing to the derived end; do not force these lengths into the old total.

Important pacing distinction: biome lengths increase, but most boss positions are closer to the
plaza than today. Nick moves from Z=1672 to Z=1692, only 20 studs farther. Do not describe this as
making every deep return run longer than the current game. It mainly compresses early travel.

**Recommended first-boss adjustment:** use an explicit zone-one local boss Z of 50, with the other
bosses at 0.6×their own depth. At Z=54, the existing ±27-stud lair reserve reaches Z=81. An unchanged
12-stud exit pylon placed flush with the new boundary occupies Z=78..90, overlapping the reserve.
At Z=50, the reserve is Z=23..77 and the stage is Z=29..71, leaving the exit clear. Preview this
placement before treating it as final. Keep the actual stage size; shortening it is not the fix.

Frank's current local/world Z is 132. This change removes 78–82 studs of forward travel, but the
plaza walk, lateral approach, holding E and player navigation still take time. A short biome does
not guarantee an instant or impossible-to-fail first steal.

## One shared source of layout truth

Suggested implementation: a pure shared `src/shared/ZoneLayout.luau` helper, reading per-zone
`Depth` from GameConfig.Zones. Its API should provide:

- `Depth(index)`, `Start(index)`, `Finish(index)`, `Center(index)` and `TotalDepth()`.
- `IndexAtZ(z)`: one boundary policy shared by server/client. Use [start,end) for interior zones,
  exact final end belonging to the last zone, and nil outside the runway. Callers retain their
  current X bounds and hub/round checks.

Keep `GameConfig.ZoneDepth=220` temporarily as a fallback for a zone without an explicit Depth,
and as the old art's authored depth. It must no longer determine live origins or totals. Validate
finite, positive depths and valid indices. Avoid a GameConfig↔ZoneLayout require cycle: either
compute boss positions in the layout helper and let GameConfig use it safely via a deliberately
one-way dependency, or put the cumulative helper functions directly in GameConfig instead.
Choose one approach and use it consistently; do not leave two independent implementations.

Keep zone indices and rarity order stable. No persistent save field or new remote is necessary.

## Code impact inventory

References are symbols and current approximate line locations; Claude's ongoing edits can move them.

| File / entry point | Required change |
| --- | --- |
| `src/shared/Config/GameConfig.luau` — ZoneDepth (~371), Zones, BossLairCenter (~936) | Per-zone depths; cumulative boss position; optional first-boss local override. Preserve odd-left/even-right X and lair dimensions. |
| `src/server/Services/MapService.luau` — zoneTint (~238), buildArena (~245) | Floors, bounds, wall lengths/centres and runway end use each zone's range. Keep floor names, thickness, collision and attributes. |
| MapService — buildIsland (~814) | Earth/cloud/manor footprint follows TotalDepth. |
| MapService — BuildBiomeShells (~1045) | Mount each shell at Start(index), pass the intended depth/art metadata. The shell registry is `BIOME_SHELLS` inside MapService; there is no current Config/BiomeShells module. |
| `src/server/Services/ManorDecor.luau` — Build (~1117) | Per-zone origin/depth for ambient volumes and fallback decor. Manor already uses arena.MaxZ; verify it still aligns with the island backing. |
| `src/client/Transitions.luau` — zone detection (~92) | Replace floor(Z/220) with shared lookup; preserve titles and HUD. |
| `src/client/ZoneLighting.luau` — moodHere (~270) | Shared lookup, blend against that zone's Finish. Cap blend length at min(60, depth/3) so most of the short first zone retains its own mood. |
| `src/client/BiomeShells.luau` — shell midpoint (~45) | Use each mounted shell's actual GroundDepth; preserve LOD, water flow and tags. |
| `src/server/Services/StealService.luau` — zoneIndexAt (~69) | Already reads MapService.Zones bounds. Verify revised boundaries; do not replace it with another fixed-depth formula. |
| `src/server/Services/Analytics.luau` — zoneOf (~501) | Already reads bounds. Keep telemetry's zone classification consistent at exact seams. |
| `src/server/Services/GuardService.luau` — buildLair, return/home positions, debug placement | Already calls BossLairCenter. Audit all those consumers and boss chase/return bounds; preserve prompts, chairs, sleeping faces and attributes. |
| `src/client/Places.luau` — LairSpot/LairKnife (~221) | Already calls BossLairCenter and tracks live prompts. Regression-check tutorial and post-tutorial guide targets; preserve the UI. |
| `src/shared/NextAction.luau`, `src/client/Guide.luau`, Tutorial | No new UI design. Verify reachable-zone selection and arrows still point to the actual knife/plate/sign after moving bosses. |
| `tools/pacing_sim.py` | Its travel approximation and copied timings are not authoritative. Update to use proposed cumulative distances and current config before using it to judge progression. |

Search again for ZoneDepth and arithmetic deriving zone positions after implementation. Numeric
220 values in colours, effect radii, UI sizes and asset ids are unrelated; do not mass-replace them.

## Shell work — preserve shapes, rebuild spacing

Current live shells are native cuboids built from authored geometry. Blender files/renders are the
review/export pipeline; this migration does not require uploading replacement mesh assets for
these shells. Author changes in the source builders and regenerate the geometry/review assets.

- Builders: `tools/build_courtyard_shell.py`, `build_gardens_shell.py`, `build_crypts_shell.py`,
  `build_catacombs_shell.py`, `build_inferno_shell.py`, `build_olympus_shell.py`,
  `build_heavens_shell.py`, `build_outer_space_shell.py`.
- Runtime: `src/shared/Assets/{Courtyard,Gardens,Crypts,Catacombs,Inferno,Olympus,Heavens,OuterSpace}Shell.luau`.
- Data: `src/shared/Config/ToyGeometry/*ShellData.luau` plus each shell's grouped block modules;
  mirrors and gallery assets under `assets/biome-shells/`.

Do **not** call Model:ScaleTo(depth/220): that also shrinks width, height, arches and boss clearance.
Do not stretch every block's Z size either; it distorts trees/hero props and shrinks the reserved
stage space. Use these layout rules:

1. Keep entrance/exit gate profiles' X/Y dimensions and structural thicknesses. Entrance remains
   pinned to local Z=0; exit remains pinned to local Z=Depth. Retain the intended 3-stud seam collar.
2. Resize continuous floor strips, water channels and wall runs to cover the new length.
3. Re-space repeated piers, trees and lamps, keeping each object's dimensions. Remove repetitions
   in short zones; avoid filling long zones with excessive extra parts.
4. Move boss bay architecture and themed trim as a unit to the new local boss centre. Keep the
   stage 42 studs along Z ×14 along X, with the existing ~54-stud Z clearance and 32-stud clear height.
5. Place major standalone landmarks by available space. Courtyard needs a compact layout for its
   fountain and garden details; preserving every old feature at full size may not fit 90 studs.
6. Regenerate bounds, origins, clear-lane ranges, ReservedLair, seam metadata, GroundDepth,
   group pivots and gallery camera positions. Default shell origins must agree with the new starts.
7. Keep names/tags and Build/StepWater/SetDetailVisible hooks, non-colliding shell behaviour,
   colour palette, water texture scale, glow and lighting unchanged.

Regenerate **in zone order**, because each entrance copies the preceding exit profile. Prefixes
include GardenExit_, CryptExit_, CatacombExit_, InfernoExit_, OlympusExit_, HeavensExit_, OuterSpaceExit_.
Do not independently remap the two halves of a seam and hope they still meet.

Target ≤1500 full / ≤800 low-detail parts per rebuilt shell. Record existing counts first:
Courtyard's current data reports 2428/1321, so it is an existing outlier, not a passing baseline.
The compact Courtyard is the best opportunity to reduce that count while keeping its identity.

## Implementation sequence

1. Save baseline geometry/part counts and analytics definitions; avoid overwriting Claude's guide edits.
2. Add/test the shared layout math with all eight depths still 220; this should reproduce existing origins,
   boss positions and total exactly. Migrate consumers before switching lengths.
3. Prepare all eight resized shell sources/metadata for the proposed lengths. Keep runtime geometry and
   collision layout on the same version; do not publish shortened floors with old 220-stud shells.
4. Enable the proposed lengths and first-boss placement locally. Check Courtyard first, then all seven seams.
5. Finish Studio regression/phone reviews, checks and galleries. Publish only the complete coherent layout.

## Acceptance checks for Claude

- Pure layout checks: exact cumulative starts/ends and total 1840; every boundary at ±0.01 studs;
  outside runway, hub, final edge, invalid depths, and a hypothetical ninth zone.
- Studio geometry: no floor/wall/island gaps; Manor at the actual runway end; all shell entrances
  match previous exits; no seam flicker; no decoration inside the lane or full-sized lair reserves.
- Confirm every boss's pad, stage, chair, title, return point and prompt are together and face correctly.
- Fresh-user tutorial: spawn → arrows to Frank → hold E → chase → place → collect → upgrade → equip.
  Repeat completed-tutorial guide, carrying state, full vault and insufficient cash states.
- Test first grab/run home from front, middle and rear vaults, on phone and desktop. Keep the plaza
  unchanged for this pass; measure the full spawn-to-grab journey rather than only Frank's Z.
- Verify all eight zone titles, lighting transitions, analytics zone.enter and drop/carry zone attribution.
- Steal/caught/return in every biome at existing SpeedNeeded; confirm changes in exposure time without
  silently changing the guard speed thresholds. Do not claim an impossible-to-fail first run.
- Round starts mid-carry: suspend/return to the same position, resume the correct boss chase.
- Low-detail LOD, shell midpoint distance culling, water flow and part budgets.
- Selene, StyLua, Luau-LSP and Rojo build; inspect Studio client/server errors.
- Deliver updated overview/per-biome galleries, exact bounds and boss positions, part counts,
  test results and any remaining art compromises.

## How to evaluate it after release

Use existing events (`boss.hold`, `boss.snatch`, `steal.start`, `steal.home`, `knife.mounted`,
`steal.caught`, `guide.shown`, zone.enter) to compare first-grab and first-home rates/times, repeat
steals, first upgrade, first-round exposure and session retention. Compare like-for-like cohorts
by device/new-user/source and mark the layout version so old/new sessions are distinguishable.
Treat faster movement as an implementation result and retention improvement as a measurement.
