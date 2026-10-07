# Complete eight-rarity toy coffin family

Added `src/shared/Config/ToyGeometry/Coffin_{Rare,Epic,Legendary,Mythic,Godly,Celestial}.luau` and a self-contained `src/shared/Assets/CoffinAssets.luau` builder. The approved Common/Cosmic files are retained unchanged and included with the family. `tools/build_coffin_assets.py` regenerates the six middle variants without rewriting Common/Cosmic or knife characters. Source geometry/metadata is in `assets/coffins/geometry.json`; approved family references are under `references/`.

| Rarity | Base length | Total BaseParts incl. Root | Lid / Glow / Crack |
| --- | ---: | ---: | --- |
| Common | 3 | 127 | 40 / 8 / 1 |
| Rare | 4 | 127 | 40 / 8 / 1 |
| Epic | 5.2 | 127 | 40 / 8 / 1 |
| Legendary | 6.6 | 125 | 38 / 8 / 1 |
| Mythic | 8.2 | 125 | 38 / 8 / 1 |
| Godly | 10 | 125 | 38 / 8 / 1 |
| Celestial | 12 | 125 | 38 / 8 / 1 |
| Cosmic | 14 | 145 | 58 / 8 / 1 |

Lengths are body baselines; handles/trim extend actual bounds slightly (about 4.3%). Origin/pivot is bottom centre at local 0,0,0; front is local -Z. Shape matches the original stepped, studded family with a hollow body, friendly pixel skulls for low tiers and star emblems for higher tiers. Colours progress brown → blue → purple → gold → red → pink/gold → cyan/white → violet/cyan. Glowing trim increases with rarity. No lights, prompts, physics or gameplay code were added.

Claude can call `Shared.Assets.CoffinAssets.BuildCoffin(rarity,parent,frame,{Scale=1,Peek=false})`. `Peek=true` exposes the optional built-in eye pieces for previews; gameplay can add its own eyes at the Crack face. `SetCoffinOpen(model,degrees)` moves all Lid parts about the stored `LidHinge`; 105 is the open angle and 0 restores closed. Glow/Pulse and Crack roles, RestOffset/RestSize attributes, BaseLength, Rarity and FrontAxis are preserved. Every part is anchored, non-collidable, non-touching and non-querying.

`studio-all-eight.png` is the actual Studio shot, Common through Cosmic left-to-right, smallest to biggest. Optional peek eyes are shown. The native view uses current game lighting without adjustments. `tools/stage_coffin_review.py` exports a temporary review fixture with contract checks; it is not runtime integration.

All eight passed Studio checks: expected part/role counts, exact base length, floor-centre pivot, hollow body construction, lid-only movement, body/Crack stability, reopening/closing and scaling. Selene, StyLua, Luau type analysis, Python compilation, deterministic regeneration and Rojo build passed. Common/Cosmic hashes remained unchanged. Temporary review objects were removed, camera restored and Play stopped.

No mesh/image upload is needed: these are native part data modules. Claude wires them into the coffin system. Art commit is scoped to the aura/coffin deliverables; unrelated gameplay changes remain with their author.
