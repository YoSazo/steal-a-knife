# Codex prompt: aura particle sprites (the "monstrosity" look)

## Context (read first)
Knives are becoming characters that hop around a Steal an Egg-style pen (docs/KNIFE_CHARACTERS_BRIEF.md).
Claude built the aura system in `src/shared/KnifeHaze.luau`: a big soft coloured glow at each knife's
core that catches the bloom ("the sun inside the creature"), plus layers stacked by rarity
(Common nothing ... Cosmic everything). It works, but it only has two plain sprites (a soft round
glow and a 4-point flare), so it reads as "glowing", not dramatic.

Steal an Egg's top creatures look like monstrosities because their auras are made of sprites with
PERSONALITY - slime dripping, spirals turning, lightning cracking, dark smoke curling - many at once.
That's what this task makes. **You make the sprites; Claude wires them into KnifeHaze** (don't edit
KnifeHaze or other game code).

References (look at these first):
- `assets/knife-characters/reference/steal-an-egg-auras-pen.webp` - slime drips, green spirals, purple
  lightning shards, dark smoke, a rainbow band over the top, all layered (circled in red)
- `assets/knife-characters/reference/steal-an-egg-aura-closeup.png` - a top-tier aura up close: bright
  core haze, light rays, twinkles
- `assets/knife-characters/reference/steal-an-egg-skyline.webp` - the overall effect from far away

## Technical rules (every sprite)
- **PNG, RGBA, white / grayscale only.** No colour - the game tints each sprite per rarity through
  ParticleEmitter.Color (Rare blue, Epic purple, Legendary gold, Mythic red, Godly gold-white,
  Celestial cyan, Cosmic violet). Brightest parts pure white, shading in greys, shape in the alpha.
- **Straight (not premultiplied) alpha, no dark fringes:** fill the RGB of every transparent or
  semi-transparent pixel with white, so edges never show a grey/black halo when tinted and blended.
- **Style:** our toy / cartoon look - bold, chunky, readable at small size, clean shapes, soft but not
  blurry edges. Not realistic, no photo textures, no text.
- **Size:** single sprites 256x256. Animated ones are **flipbooks**: 1024x1024 = a 4x4 grid of
  256x256 frames (16 frames), read left-to-right, top-to-bottom (Roblox ParticleEmitter
  FlipbookLayout Grid4x4). The 2x2 option: 512x512 = 4 frames of 256 (Grid2x2).
- **Each frame centred in its cell with ~8% empty padding**, same centre point in every frame, so
  nothing jitters. Loops must loop seamlessly (frame 16 -> frame 1).
- Keep the drawn shape filling most of the cell - Roblox particles are sized by the cell, so a tiny
  shape in a big empty cell looks weak.

## The sprites (names exact)
| # | Name | Kind | What it looks like | How the game uses it |
|---|---|---|---|---|
| 1 | `SlimeDrip` | Flipbook 4x4, loop | a glossy goo blob that wobbles, stretches a long tail downward, and a drop pinches off - cartoon slime with a white shine highlight | drips falling off Epic+ knives (Steal an Egg's green drips) |
| 2 | `Spiral` | Single 256 | a bold 2-3 turn spiral swirl, thick at the outside, thinning to the centre, slight glow edge | spirals orbiting and spinning around the knife (code rotates it) |
| 3 | `LightningShard` | Single 256 | a jagged crystal shard / lightning splinter: sharp angular facets, bright core edge | shards bursting out of Mythic+ knives (the purple shards) |
| 4 | `LightningBolt` | Flipbook 4x4, one-shot | a crackling zig-zag bolt: frames 1-4 flash in, 5-12 flicker/branch, 13-16 fade | lightning cracking around the top tiers |
| 5 | `SmokeWisp` | Flipbook 4x4, loop | a soft curling puff of smoke that billows and curls (grey shading for volume) | dark smoke around Mythic+ (tinted dark purple/green) |
| 6 | `Star` | Single 256 | a cute cartoon 4-point star with a soft round glow centre (chunkier than the existing flare) | twinkles around Epic+ |
| 7 | `Ember` | Flipbook 2x2, loop | a small flame tongue flickering | rising embers on Legendary+ |
| 8 | `RainbowArc` | Single 512x256 | a soft wide arc / band of light (white, the code tints it with a rainbow gradient) | the rainbow band over Cosmic knives |
| 9 | `ShockRing` | Single 256 | a ground shockwave ring: bright thin ring with soft inner/outer falloff, seen from above | the ground pulse when a huge knife lands from a hop |
| 10 | `LightRays` | Single 512 | soft god-rays fanning out from the centre (8-12 rays, uneven lengths) | behind Godly+ knives, slowly rotating |

## How to make them
- Image-generate each as a white-on-black (or white-on-transparent) graphic in the style above,
  then clean it with a script: background -> transparent alpha, desaturate to white/grey, remove
  stray pixels, fix fringes (rule above), pad and centre, assemble flipbooks into the exact grid.
  Put that script in `tools/make_aura_sprites.py` so they can be regenerated.
- Or generate procedurally in that script where it's cleaner (ShockRing, LightRays, Star).
- Save the finished PNGs to `assets/aura-sprites/<Name>.png`.

## Upload + config
- Upload with the same pipeline as our other textures (Studio upload_image from a local http server).
- Record them in `src/shared/Config/Textures.luau` as a new table:
```lua
AuraSprites = {
	SlimeDrip = { Id = "rbxassetid://...", Flipbook = "Grid4x4", Loop = true },
	Spiral = { Id = "rbxassetid://..." },
	LightningShard = { Id = "rbxassetid://..." },
	LightningBolt = { Id = "rbxassetid://...", Flipbook = "Grid4x4", Loop = false },
	SmokeWisp = { Id = "rbxassetid://...", Flipbook = "Grid4x4", Loop = true },
	Star = { Id = "rbxassetid://..." },
	Ember = { Id = "rbxassetid://...", Flipbook = "Grid2x2", Loop = true },
	RainbowArc = { Id = "rbxassetid://..." },
	ShockRing = { Id = "rbxassetid://..." },
	LightRays = { Id = "rbxassetid://..." },
},
```
(Don't change the existing `Glow` table - KnifeHaze uses it.)

## Check your work before handing back
1. A contact sheet `assets/aura-sprites/preview.png`: every sprite (flipbooks as their full grid)
   shown three ways - over black, over our grass green `(48,146,30)`, and tinted Cosmic violet
   `(195,55,255)` over grass. Edges must be clean on all three (no dark halos).
2. In Studio: put each one on a ParticleEmitter (flipbooks with their FlipbookLayout and
   FlipbookMode Loop / OneShot set) on a part, tinted, and screenshot them playing - confirm the
   frames line up and nothing jitters.
3. Studio is shared with Claude: check `get_studio_state` first and stop play when you're done.

## Hand back
The 10 PNGs, the preview sheet, the Textures.luau entries, `tools/make_aura_sprites.py`, and the
Studio screenshot. Commit only your own files (never .env). Claude then layers them into
KnifeHaze by rarity, with orbiting motion and the ground shock ring on landings.
