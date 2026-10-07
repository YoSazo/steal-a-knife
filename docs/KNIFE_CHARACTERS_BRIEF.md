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

### The face: ONE static face, done really well (no animation)
Changed 2026-10-07: faces do NOT animate (no blinking, no expressions, no separate lids / brows /
mouth variants). Steal an Egg's creatures have one simple face that never changes; the MOVEMENT
(hopping around the pen) is what makes them feel alive. Put all the effort into one great face.

- **Steal an Egg's Golden Dog is the reference:** two BIG glossy eyes set wide apart, each a dark
  rounded block with a bold white shine block in the upper corner (the shine is what makes it
  cute), a thin dark outline / lid line along the top of each eye, and a SMALL simple mouth (or
  none). Eyes are the face - they should take up most of the face area.
- **Big:** the face fills at least half the blade's width and reads clearly from 30+ studs away at
  1x scale. No tiny details: every face block at least ~0.08 studs at 1x (it'll be scaled up 2-9x).
- **Simple:** about 6-12 blocks per face. Fewer, bigger, cleaner blocks beat many small ones.
- **One expression per knife that matches its personality** (derpy Common: eyes a bit uneven,
  tongue out; smug Legendary: half-lidded eyes; unhinged Cosmic: huge eyes with star shines).
- Tag face blocks `Role = "Face"` (one role, nothing animates them). Drop Lid, Pupil, Brow,
  Mouth_*, Tear, SleepSize/SleepOffset and the eye "Follow" welds.

### What they DO in the pen (design for it)
- **Hop on their handle** around the pen (pogo-hop): the pommel is the foot, keep it flat and
  sturdy-looking; a Common hops clumsily, a Cosmic stomps.
- That's all they do (Steal an Egg's creatures just move around): no chopping or work targets.

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
- A low fence segment (`PenFence`, ~2 studs tall, tileable 8-stud lengths) and corner post -
  Steal an Egg's look: orange-brown studded rails in an X between dark studded posts.
- An entrance arch/gate post pair (`PenGate`) - the owner's face billboard goes on it.
- Ground: flat, the game uses the existing toy grass; optional pen floor tile `PenFloor`.

## Hand-off
Same as the knife redesign: reference images + comparisons in `assets/knife-characters/`, the
Python design sources, generated `Config/ToyGeometry/*.luau`, and a Studio test placing one of each.
Start with 3 knives (Rusty Shank, Katana, one Cosmic) + Coffin_Common + Coffin_Cosmic so the systems
can be built against real art; then the rest.
