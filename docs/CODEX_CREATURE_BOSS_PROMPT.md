# Codex prompt: the first creature boss (Courtyard / zone 1)

## Context (read first)

Every zone's "boss" is currently a round character (a person in a chair - Frank the Groundskeeper
guards zone 1) in front of a graveyard of coffins, Steal an Egg style. We're swapping the bosses for
actual creatures, like Steal an Egg's guardians (its Chicken, Swan, Yeti, Cerberus, T-Rex...), because
our ad is already showing a big dramatic chaser and the real game should match it.

**Start with ONE creature: the Courtyard (zone 1, Common rarity).** Every new player meets this one
in their first minute - it's the only creature that matters for the ad and for first impressions.
The other seven zones (Gardens/Rare, Crypts/Epic, Catacombs/Legendary, Inferno/Mythic,
Mount Olympus/Godly, Heavens/Celestial, Outer Space/Cosmic) come later, once this one is proven in
Studio.

**You make the creature; Claude wires it into the boss system** (waking, chasing, catching, stunning,
throwing - all of that logic stays exactly as it is, it's the body that changes). Don't touch game
code; just build the creature and hand off its model + a pivot/pose spec (below).

## What the creature replaces

Right now zone 1's boss folder has: a round character sitting in a chair (idle), knives on its wall
(now: coffins on the grass in front of it), a name title ("Frank - The Groundskeeper"). The creature
takes the person's place exactly: same spot, same scale reference point, same "sleeping until
disturbed" idea.

## Direction: a big hedge hound

Zone 1 is the Courtyard: hedges, a fountain, benches, lanterns, bright green grass. The creature
should look like it belongs there and like it's "yours" at the start of the game - cute-scary, not
purely cute (it still has to feel like a real threat once awake), low-poly toy-block style (like
every other model in this game - flat colours, chunky simple shapes, NOT a smooth/organic mesh look).

**A big dog-like hedge guardian:** body built from the same clipped-hedge greens as the Courtyard's
hedges, with a few bright flowers worked into its fur as highlights (daisies, the same flower props
already in the Gardens). Stocky, four-legged, a thick neck and a blunt head (think a bulldog /
mastiff silhouette, not a wolf), small rounded ears, a short tail. Sleeping pose: curled up or lying
flat with its head down, eyes shut (a closed-eye block shape, matching how our knife characters
blink). Awake pose: head up, ears up, mouth open with blunt toy-block teeth, eyes a bright solid
colour (glowing).

Reference feel: Steal an Egg's guardians (Chicken, Swan, Scorpion, Tiger) are all instantly readable
toy-block animals, roughly 2-4x the height of the player character. This one should read the same
way from across the plaza.

## Size and reference

- **Height standing: about 2.5x a player character** (a player is ~5 studs tall; this creature
  should be roughly 12-13 studs at the shoulder/head when standing, since GameConfig.BossScale for
  the current person-boss is 1.6x and this needs to feel bigger and more dramatic than that).
- Build it at a scale where `Model:GetExtentsSize()` gives you that height, so it drops in without
  rescaling.
- Low poly: aim for roughly the same part count as one of your knife characters x3-4 (it's a bigger,
  simpler shape, not a highly detailed one) - a few hundred parts at most, not thousands. This has
  to run fine on phones.

## Required parts and attributes (so Claude can wire it up)

Build it as a `Model` with these tagged parts (attribute `Role` on each part, matching the pattern
you already use for knife characters and coffins):

| Role | What it is |
|---|---|
| `Root` | An invisible part at floor level, centre of the model (the pivot). This is what gets placed/moved by the boss system. |
| `Body` | The main torso/body blocks. |
| `Head` | The head block(s) - needs to turn/nod slightly when it wakes and when it chases. |
| `LegFrontLeft`, `LegFrontRight`, `LegBackLeft`, `LegBackRight` | Each leg as its own part or small group, so they can animate (a walk/run cycle). |
| `Tail` | Optional, if it has one. |
| `EyeLeft`, `EyeRight` | The eye blocks. Give them a `Closed` attribute = true/false state Claude can toggle (sleeping = closed/hidden, awake = showing, a bright solid colour, Neon material). |
| `Mouth` | Optional separate part for an open mouth once awake (can be hidden while asleep). |

Model attributes (set these in your build script, like `CoffinModel`/`KnifeCharacterAssets` already
do):
- `FrontAxis` = `"-Z"` (matches every other model's convention here).
- `StandHeight` = the standing height in studs (a number), so Claude can scale/verify it.
- `WalkPivot` = roughly where the front-back weight shifts (not critical, a reasonable guess is fine
  - Claude's animation system works off joint rotation, not IK).

## Poses to build (as separate named children or a simple attribute toggle - your call, whatever is
cleanest for you to produce and for Claude to read back)

1. **Asleep**: curled/lying down, eyes closed (hidden or a flat "closed-eye" line, matching the
   knife-character blink style), still.
2. **Waking** (optional, nice-to-have, skip if it adds too much time): head lifting, eyes opening.
3. **Awake / alert**: standing, head up, ears up, eyes lit.
4. **A simple run cycle reference**: doesn't need to be a full animation - just the four leg parts
   separated cleanly enough that Claude can drive a walk/run cycle procedurally (the same way our
   knife characters hop and our round characters walk - see `src/shared/AnimLibrary.luau` if you
   want to see the style: everything here is procedural joint rotation, no imported animations).

## Colour and style rules (same as every other model in this game)

- Flat, bright, saturated toy colours - no gradients, no realistic shading, no textures beyond the
  simple stud/checker pattern already used elsewhere (`Shared/Toy`) if you want to dress any part of
  it.
- No smooth/sculpted organic surfaces. Blocky, chunky, Lego-adjacent. Every part a simple
  Block/Wedge/Ball/Cylinder, no custom meshes unless there's no other way to read the silhouette
  (and if so, keep it very low-poly, the way `blender/scripts/make_props.py` output stays simple).
- Eyes are the main expressive feature (asleep = closed, awake = bright glowing colour) - same
  language as the knife characters' faces.
- No blood, nothing gory. This is a "big friendly guard dog that means business," not a monster.

## Deliverable

1. The model (export however you've been delivering knife characters/coffins - geometry data file +
   a `Build` function, following the same pattern as `Assets/KnifeCharacterAssets.luau` /
   `Assets/CoffinAssets.luau`, OR a Blender build script under `blender/scripts/` if that's easier
   for a four-legged rig - your call on which pipeline fits this better).
2. A short note on where `Root` sits relative to the ground and the standing height in studs.
3. A render or two (front + three-quarter) in the asleep and awake poses so we can sanity-check scale
   and readability before wiring it in.

Once this one is approved in Studio, we'll do the other seven zones' creatures, each matching its
biome and rarity (ice/stone/lava/gold/cloud/void themes, following the existing zone palette in
`GameConfig.Zones[i].Color`).
