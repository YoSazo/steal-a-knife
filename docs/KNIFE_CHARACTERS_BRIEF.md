# Brief for Codex: knife characters, coffins, pen props

Goal: Steal an Egg's formula in our theme. Knives become **characters** (faces, personality, meme
names), stolen as **coffins** that open on a timer, shown in an open **pen** where the best ones
tower over everything. Codex makes the art with its usual pipeline (generate the image -> build it
block by block -> ToyGeometry). Claude builds the systems (timers, hatching, Robux skip, stealing,
sizing, reactions, A/B test, notifications). Nothing ships until the current prize A/B test ends.

## 1. The 24 knife characters
Same 24 knives (`Config/Knives.luau`), same `Config/ToyGeometry/<Name>.luau` cuboid format,
same toy style (bright flat colours, chunky blocks). Each one gets a face on the blade.

- **Stance:** standing upright on its pommel, blade up, like a little creature standing in the
  pen. Root/origin at the bottom of the pommel (the floor point). Front (the face) = local -Z.
- **Size:** ~2.4 studs tall at scale 1 (as now). The game scales it up by value: a Cosmic will
  be drawn 6-10x bigger, so details must read when huge and still when small.
- **Face on the blade**, big and expressive, Steal an Egg style (see their Golden Dog: huge eyes
  with white highlights, simple mouth).
- **Personality by rarity:** Common = derpy, sleepy, lopsided; Rare = cheerful; Epic = cool;
  Legendary = smug (sunglasses OK); Mythic = fierce; Godly = royal/glowing; Celestial = serene,
  halo; Cosmic = unhinged, starry eyes.
- **A meme name** for each (display only; the real name stays for saves). E.g. Rusty Shank ->
  "Rusty Steve", Katana -> "Sir Slicealot". Put them in a table: `Config/KnifeCharacters.luau`
  `{ [knifeName] = { Display = "Rusty Steve", Personality = "derpy" } }`.

### Face parts (the contract - the game finds and animates these by Role)
| Role | What | The game does |
|---|---|---|
| `EyeWhite` | each eye's white (2 parts) | - |
| `Pupil` | each pupil (2 parts), in front of its white | wobbles, looks at the nearest player |
| `Lid` | each eyelid (2 parts), above the eye | lowered while asleep in the coffin / sleeping |
| `Mouth_Happy` | the default mouth | shown normally |
| `Mouth_Scared` | open "AAAH" mouth | shown while being carried / chased |
| `Mouth_Sad` | crying mouth | shown when the boss takes it back |
| `Mouth_Smug` | grin | shown when pulled out as the Murderer |
| `Tear` (optional) | tear drops | shown with Mouth_Sad |

Only one `Mouth_*` is visible at a time (the game toggles Transparency), so they can overlap.
Keep the existing roles (`Grip`, `Guard`, `Blade`...) on the rest - auras and trails use them.

## 2. Coffins (the "egg")
One per rarity: `Config/ToyGeometry/Coffin_<Rarity>.luau`. You steal it from the boss; it sits in
your pen with a timer; the knife character climbs out when it opens.

- Size grows with rarity: Common ~3 studs long, Cosmic ~14 (huge, glowing, visible from afar).
- Toy-cute, not scary (audience 9-15): rounded cartoon coffin, rarity colours, studs, a skull or
  star emblem. Origin at the bottom centre, front = -Z, lying on its back or standing up - your
  call, whatever reads best from a high camera.
- Roles: `Lid` (all lid parts - the game swings/pops it open), `Glow` (parts that pulse while it
  grows), `Crack` (where eyes peek out while it rattles; the game puts two glowing eyes there).

## 3. Pen props
- A low fence segment (`PenFence`, ~2 studs tall, tileable 8-stud lengths) and corner post.
- An entrance arch/gate post pair (`PenGate`) - the owner's face billboard goes on it.
- Ground: flat, the game uses the existing toy grass; optional pen floor tile `PenFloor`.

## Hand-off
Same as the knife redesign: reference images + comparisons in `assets/knife-characters/`, the
Python design sources, generated `Config/ToyGeometry/*.luau`, and a Studio test placing one of each.
Start with 3 knives (Rusty Shank, Katana, one Cosmic) + Coffin_Common + Coffin_Cosmic so the systems
can be built against real art; then the rest.
