# SkyPegasus: zone 7, Zoe — The Angel

Art only. Native Block parts; no mesh/texture uploads needed. 112 BaseParts including Root.
Standing native GetExtentsSize height: 21.5 studs. Authored at world size; do not apply the old
person-boss 1.6x scale. Front -Z. Root at floor centre below the torso; visible feet touch y=0,
invisible Root extends 0.025 studs below the floor due to Roblox's minimum Part size.

## Files and placement

- `src/shared/Assets/SkyPegasus.luau`: Build(parent, frame, pose), SetPose, SetRunPhase.
- `src/shared/Config/ToyGeometry/SkyPegasus.luau`: Blocks and awake/asleep joint pivots.
- `tools/build_sky_pegasus.py`: regenerate this creature (delegates to build_creature_bosses.py).
- `reference.png`: image-generated design reference; geometry is a native block interpretation.
- `gallery.png`: front and three-quarter, awake/asleep, beside a five-stud block player.
- `geometry.json`: part dimensions, offsets, palette, roles, groups and animation notes.

Claude: mount at zone 7's existing guardian origin. Register `SkyPegasus` in CREATURE_MODULES
and GameConfig.Zones[7].Creature when ready. This task does not perform that registration.

## Contract and poses

Same builder/pose implementation as the approved hedge hound. PrimaryPart is Root. Model
attributes: FrontAxis=-Z, StandHeight=21.5, Zone=7, ArtOnly=true, WalkPivot.
Parts carry Role, JointGroup, RestOffset, RestSize, RestAngle and PoseVisibility. Offsets are
relative to the named joint pivot, not directly to Root. Keep four exact leg groups:
LegFrontLeft, LegFrontRight, LegBackLeft, LegBackRight.

HeadCore exists and belongs to Head. GuardService currently creates its synthetic invisible
Head anchor from HeadCore; preserve that working path. The asset does not create a competing
Head anchor. EyeLeft/EyeRight include awake Neon eyes/highlights and sleeping dark lids.
Closed metadata follows SetPose; use SetPose to switch actual visibility.

Build defaults to Asleep. Waking accepts a 0..1 blend; eyes switch halfway through. SetPose
restores local sizes/offsets from attributes without drift and respects Model:ScaleTo.
SetRunPhase is an optional diagonal trot pose sampler, not an autonomous animation.

- WingLeft/WingRight have folded sleep pivots; flap around local Z. Ground trot remains four legs. Halo is a separate group and may bob with Head.

No scripts, Humanoid, lights, particles, meshes or physics inside the model. All parts anchored,
non-colliding, non-queryable and non-touching. Claude owns hitboxes, procedural gait and foot lift.
Chase/catch integration and clearance against the graveyard are not tested by the art fixture.

## Verification

Native Studio checks passed: count, standing extents, floor contact, required roles/HeadCore,
closed sleep eyes, waking blend, pose restoration, torso stability during trot, and 1.5x scaling.
Neutral ViewportFrame previews only; global game lighting was not changed. Selene, StyLua, Luau
type analysis and Rojo build checked separately for the pack. Temporary Client fixture removed.
