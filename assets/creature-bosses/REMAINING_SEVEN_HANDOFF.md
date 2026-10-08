# Zones 2–8 creature art

All seven native block models are ready for art review and Claude integration. The original hedge
hound is unchanged. No services, client logic, GameConfig wiring or game lighting were edited.

| Zone | Module / creature | Standing studs | Parts including Root |
|---|---|---|---|
| 2 | FlowerToad | 14 | 90 |
| 3 | BoneWolf | 15.5 | 89 |
| 4 | GoldScorpion | 17 | 80 |
| 5 | LavaSalamander | 18.5 | 93 |
| 6 | GoldenGriffin | 20 | 114 |
| 7 | SkyPegasus | 21.5 | 112 |
| 8 | VoidBeast | 23 | 100 |

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
