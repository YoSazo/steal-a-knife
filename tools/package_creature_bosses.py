"""Package per-creature handoffs and a native Studio review sheet."""
from pathlib import Path
from PIL import Image,ImageDraw
import json
from build_creature_bosses import INFO
R=Path(__file__).resolve().parents[1];OUT=R/'assets/creature-bosses'
sheet=Image.new('RGB',(1648,1560),(32,39,37));draw=ImageDraw.Draw(sheet)
draw.text((24,12),'ZONES 2-8: NATIVE STUDIO MODELS / AWAKE THREE-QUARTER',fill='white')
summary=[]
for i,(name,zone,height,boss,title)in enumerate(INFO):
 folder=OUT/name;d=json.loads((folder/'geometry.json').read_text());im=Image.open(folder/'gallery.png').convert('RGB');w,h=im.size
 panel=im.crop((w//2,0,w,h//2)).resize((800,350));x=24+(i%2)*824;y=42+(i//2)*378;sheet.paste(panel,(x,y))
 snake=''.join('_'+ch.lower()if ch.isupper()and k else ch.lower()for k,ch in enumerate(name))
 draw.text((x,y+354),f'Zone {zone}: {name} / {height} studs / {d["PartCount"]} parts',fill='white')
 notes='\n'.join('- '+s for s in d['AnimationNotes'])or '- Four-leg diagonal trot and Tail wag use the existing contract.'
 handoff=f'''# {name}: zone {zone}, {boss} — {title}

Art only. Native Block parts; no mesh/texture uploads needed. {d['PartCount']} BaseParts including Root.
Standing native GetExtentsSize height: {height} studs. Authored at world size; do not apply the old
person-boss 1.6x scale. Front -Z. Root at floor centre below the torso; visible feet touch y=0,
invisible Root extends 0.025 studs below the floor due to Roblox's minimum Part size.

## Files and placement

- `src/shared/Assets/{name}.luau`: Build(parent, frame, pose), SetPose, SetRunPhase.
- `src/shared/Config/ToyGeometry/{name}.luau`: Blocks and awake/asleep joint pivots.
- `tools/build_{snake}.py`: regenerate this creature (delegates to build_creature_bosses.py).
- `reference.png`: image-generated design reference; geometry is a native block interpretation.
- `gallery.png`: front and three-quarter, awake/asleep, beside a five-stud block player.
- `geometry.json`: part dimensions, offsets, palette, roles, groups and animation notes.

Claude: mount at zone {zone}'s existing guardian origin. Register `{name}` in CREATURE_MODULES
and GameConfig.Zones[{zone}].Creature when ready. This task does not perform that registration.

## Contract and poses

Same builder/pose implementation as the approved hedge hound. PrimaryPart is Root. Model
attributes: FrontAxis=-Z, StandHeight={height}, Zone={zone}, ArtOnly=true, WalkPivot.
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

{notes}

No scripts, Humanoid, lights, particles, meshes or physics inside the model. All parts anchored,
non-colliding, non-queryable and non-touching. Claude owns hitboxes, procedural gait and foot lift.
Chase/catch integration and clearance against the graveyard are not tested by the art fixture.

## Verification

Native Studio checks passed: count, standing extents, floor contact, required roles/HeadCore,
closed sleep eyes, waking blend, pose restoration, torso stability during trot, and 1.5x scaling.
Neutral ViewportFrame previews only; global game lighting was not changed. Selene, StyLua, Luau
type analysis and Rojo build checked separately for the pack. Temporary Client fixture removed.
'''
 (folder/'HANDOFF.md').write_text(handoff)
 summary.append({k:d[k]for k in ['Name','Zone','Boss','StandHeight','PartCount','AnimationNotes']})
sheet.save(OUT/'remaining-seven-gallery.png');(OUT/'remaining-seven-manifest.json').write_text(json.dumps(summary,indent=2))
rows='\n'.join(f'| {d["Zone"]} | {d["Name"]} | {d["StandHeight"]} | {d["PartCount"]} |'for d in summary)
(OUT/'REMAINING_SEVEN_HANDOFF.md').write_text(f'''# Zones 2–8 creature art

All seven native block models are ready for art review and Claude integration. The original hedge
hound is unchanged. No services, client logic, GameConfig wiring or game lighting were edited.

| Zone | Module / creature | Standing studs | Parts including Root |
|---|---|---|---|
{rows}

Each name has its own Assets/<Name>.luau builder, Config/ToyGeometry/<Name>.luau data, build_<snake>.py
entry point and assets/creature-bosses/<Name>/ folder with reference, native four-view gallery,
geometry JSON and HANDOFF.md. Shared generator: tools/build_creature_bosses.py.
Native review fixture: tools/stage_creature_boss_review.py <Name> (Client-only; no boss registration).
Packager: tools/package_creature_bosses.py. Preview: remaining-seven-gallery.png.

Register the modules in GuardService.CREATURE_MODULES and corresponding GameConfig.Zones[i].Creature
only when approved. Preserve HeadCore: the current service constructs its own Head billboard anchor.
The existing four-leg trot contract is retained. GoldScorpion pairs eight visible legs into those
four groups; ClawLeft/ClawRight are separate. Griffin/Pegasus wings fold behind the body in sleep;
WingLeft/WingRight may flap around local Z. Pegasus Halo and toad Bloom are optional bob/sway groups.
FlowerToad has no Tail. VoidBeast has six eyes, all closed by the same pose switch.

Heights include the invisible Root's 0.025-stud lower half. Model origins are at floor level, under
the torso, facing -Z. Authored at full world size: do not multiply by the old person-boss scale.
Gait, foot clearance, graveyard clearance and chase/catch playtests remain Claude's integration work.

All seven pass native Studio contract checks. The pack has no external asset dependencies or upload
requirements. Preview illumination is local to the ViewportFrames; no global lighting changes.
Temporary review instances were removed and the already-running Play session left running.
''')
print('Seven handoffs and native gallery packaged')
