# Knife powers — draft for sign-off (Phase 2)

One power system: every knife rolls a power when it lands in your vault. Each power has a
**Murderer side** and an **Innocent side**, so your equipped knife matters every round (the Sheriff
uses the Innocent side). **Rarity decides which power you roll; grinding decides how strong it
is** — power level 1 → 100 in tiny steps (~1–2 levels a day, 100 ≈ 2–3 months). The Murderer side
grows a lot (the power fantasy); the Innocent side grows a little (≤ +20%, it's the majority).
Levels belong to the power, not the knife. Classic rounds (~20%) still have no powers.

Counterplay always survives: the Sheriff one-shots, thrown knives can be dodged, Lv 100 makes a
Murderer scary, not unbeatable.

## Tiers (roll odds before Heat / rarity luck)

| Tier | Roll chance | Powers |
|---|---|---|
| Common | ~60% | Shadow, Sense, Snare |
| Rare | ~28% | Decoy, Flash, Disguise |
| Epic | ~9% | Bulwark, Phantom, Fury |
| Legendary | ~2.5% | Laser, Blast |
| Mythic | ~0.5% | Spam Knife, Hellfire |

Deeper-biome knives and Heat shift the odds up a tier; the ultra-rare ones stay ultra-rare.

## The table

| Power | Murderer side (Lv 1 → Lv 100) | Innocent side (Lv 1 → Lv 100) | Built from |
|---|---|---|---|
| **Shadow** | Invisible for 1.5 s after a kill → 4 s | Vanish 2 s → 2.4 s | Invisiknife / Vanish |
| **Sense** | See the Sheriff's outline 2 s, once → 5 s, 3 uses | See the Murderer (knife out) 3 s → 3.6 s | Identifier / Radar |
| **Snare** | Drop a snare that slows an innocent 1 s → 3 s, 2 snares | Bear Trap holds 2 s → 2.4 s | new / Bear Trap |
| **Decoy** | A fake Murderer runs off (baits the Sheriff) 3 s → 8 s | A fake you runs off 5 s → 6 s | new / Decoy |
| **Flash** | Blind innocents in front 0.8 s → 2 s | Blind the Murderer 1.6 s → 1.9 s | new / Flash |
| **Disguise** | Become another player once → twice, longer | Become furniture 6 s → 7.2 s | Shape Shifter / Mimic |
| **Bulwark** | Survive one Revolver shot, once → and +1 s speed burst | Block one stab 6 s window → 7.2 s | Bulletproof / Shield |
| **Phantom** | Throws pierce 1 person → 5 | Barricade takes 2 hits → 2.4 | Ghost Knife / Barricade |
| **Fury** | +5% throw speed per kill → +20% | +5% run speed per coin streak, capped → +6% | Fury / new |
| **Laser** | Full charge throws 1.5× faster → instant laser | Dash 8 studs → 9.6 studs | Laser Knife / new |
| **Blast** | Throw kills explode, radius 3 → 9 | Smoke burst pushes the Murderer back 4 → 4.8 studs | Exploding Knife / new |
| **Spam Knife** | One 4 s burst per round, 2 throws/s → the whole round, 6/s (Mad Murderer) | **Second Life**: once per round, a killing hit knocks you down instead; you get back up invisible for 1.5 s → 1.8 s | Spam Knife / new |
| **Hellfire** | Q: 2 s of flaming throws, 30 s cooldown → 6 s, 15 s | **Phoenix Wall**: a wall of fire the Murderer can't cross, 2 s → 2.4 s | Hellfire / new |

New abilities to build: Snare (M), Decoy (M), Flash (M), Fury (I), Laser/Dash (I), Blast/Smoke (I),
Second Life (I), Phoenix Wall (I). Everything else reuses today's code with the level as a multiplier.

## Levels

- Power XP from: steals (boss / Blood Moon), rounds survived, kills as Murderer, Heat.
- Every level: a small popup. Lv 25 / 50 / 75 / 100: a big server announcement.
- Shown everywhere: knife cards, the kill card, the reveal banner and the end-of-round card
  ("SPAM KNIFE Lv 87").
- Never sold for Robux. A "2x Power XP (30 min)" potion is the one paid shortcut.

## Losing it

- Murderer loot can't take your equipped knife (keeps your main power safe).
- A Sheriff who shoots the Murderer steals the power off their knife (the hero moment) — the
  level stays with the Murderer's account, so only the knife's power is lost, not the grind.

## Migration

- Cash-bought Innocent powers are refunded (their total cost back as cash, once).
- Existing knives with a Murderer power keep it; knives without one roll on next login.
- Madame Vesper becomes the Enchanter: re-roll a knife's power for cash (scales with rarity),
  or with Robux Reroll Tokens.

## Decisions (were open questions)

1. **Mythic Innocent sides are flashy.** Spam Knife's Innocent side is **Second Life** (once per
   round, a killing hit knocks you down instead and you get back up invisible), Hellfire's is
   **Phoenix Wall**. Deflect was too quiet for a mythic: rolling one has to feel huge on both
   sides.
2. **Every knife always has a power.** Innocents always have something to do (the "walk simulator"
   fix), and Common knives just roll Common-tier powers most of the time.
3. **Lv 100 Spam Knife is the dream: whole round, 6 throws/s.** Guardrails so it stays fair:
   spam knives fly at ~70% of a charged throw's speed (dodgeable), the Murderer still dies to one
   Revolver shot, Second Life / Bulwark / Shield still save innocents, Classic rounds (~20%) have
   no powers, and Lv 100 takes ~3 months of daily play.
