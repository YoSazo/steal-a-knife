# The plan (owner + Claude, 2026-10-08)

**The filter:** every feature must make *steal → unlock → faster → steal deeper* better, or make the
murder round feed it. If it doesn't, cut it. Think 5-year-old: one obvious thing to do, no reading.

**The loop:** steal a locked knife from a monster → run home → murder rounds unlock it (and pay
Speed, give Winner's Luck, give a fuse charge) → it earns cash → cash buys wheel/pen upgrades →
faster → steal deeper. The round is also the stage where you flex your best knife.

Test every step in Studio before starting the next (nothing here was tested yet).

---

## 1. Fix the foundation

1. **One wall everywhere.** Remove zones 3-8 from `BIOME_SHELLS` (MapService); keep 1-2. The runway
   walls come back (`MapService.luau` ~291 hides them when a shell exists) in their `ZONE_WALLS`
   colours, and ManorDecor's per-biome props return (`ManorDecor.luau` ~1419 skips shell zones).
   Run `floorDressing` on every zone floor, not just 1-2 + plaza. Check the boss lairs still read.
   Deletes the `ProgressiveBiomes` shell data (~1.4 MB). Each biome = same wall, new colour, new props.
2. **Remove both A/B tests.**
   - Pens vs vaults (`GameConfig.Pens.Enabled = "Split"`): set `true`, `Coffins.Enabled = true`;
     drop Split/WithPens in `shared/PenMode.luau`, the `PenServer` check in `client/PlaceTap.luau`,
     `ab_pens` in Analytics. Then delete the vault path: `shared/VaultModel.luau`,
     `server/Services/VaultWalls.luau`, MapService's 16-vault layout, BaseService's vault branches,
     FloorCosts/SlotsPerFloor/MaxSlots. Check first whether pens use `GameConfig.Walls` tiers and
     `client/BaseMarkers`. Reword or retire "Vault Floor" (ExtraFloor) / "Next Floor" (Mount).
   - `prize_pick`: everyone gets Speed-only. Delete `client/PrizePick.luau`, its remote, the
     experiment entry, `PrizePickOn`, RoundPrize's cash path.
   - Set `Pens.Count = 8` (8-player servers; the hub shrinks by itself). Server size is set on the
     Creator Dashboard (Places -> Server size).
3. **Round cuts (gain-or-no-gain).**
   - No knife loot: delete `lootKnife`, the AtRisk reel, the loot return/haul, the Insurance offer
     and the death card's insure button. Refund leftover Insurance charges once as cash
     (`shared/LegacyProgress.luau`), move Insurance3/10 to `Monetization.Retired`.
   - No Classic rounds (`ClassicChance`), then delete the code.
   - **No two-Murderer rounds** (`DoubleTrouble`, 20% of rounds: 2 Murderers + 2 Sheriffs in an
     8-player round is half the server in special roles). Keep it only as an admin event (item 25).
   - No map vote: delete `server/Services/MapVote.luau`, `RoundMapInfo`, the plaza boards.
4. **Cut Murderer powers.** Remove `GameConfig.Perks`, the `Perk` field in `Config/Knives`, perk logic
   in RoundService (throw variants, Stunned, SpamUntil, Hellfire...), the ability button / perk card
   in `client/Abilities`, `PowerShowcase`, Decoy, Stealth, Shift. One throw + one stab for every
   Murderer (decide the default throw feel first: Spam Knife's click-to-throw is on today). Old
   4-field items ignore their saved power. (Data: ~65 of ~400 new players ever used a power.)
5. **Creature boss labels.** 💤 Zzz above the creature's bounding box (`BossHeight` + margin,
   `StudsOffsetWorldSpace`), not offset from the synthetic Head (`GuardService` ~545). The
   speed-needed sign beside the creature (half its width + margin), not 7 studs from the chair spot
   (`GuardService` ~925).

## 2. Make it 5-year-old clear

6. **HUD.**
   - A giant objective line (STEAL A KNIFE -> RUN HOME -> PLACE IT; from `shared/NextAction.luau`).
   - The red floor trail always on (Guide's Auto mode retires it after three deliveries).
   - Big Speed / Cash bottom-left with a ➕ (opens the shop tab).
   - Fold the Coffins button into Knives.
   - Round countdown bottom-right with an icon ("🔪 in 1:32"). Fold "Murderer chance: 42%" into it
     or drop it.
7. **One UI kit.** Move `SimpleUi` / `KitUi` screens onto `MenuTheme`, grid layouts everywhere (the
   Index is the reference). Cut the More stats panel to rebirths + wins.
8. **Hub clutter.**
   - Redo the events board over the entrance (`ManorDecor.eventBoard`, `EventBoardGeometry`): the
     navy screen doesn't match the toy world. Big floating world text or a toy/studded sign instead.
   - Remove the giant Void Edge statue in the middle of the plaza (`ManorDecor.Build`, the
     `MONUMENT_Z` plinth, statue and torches).

## 3. Make the loop tight

9. **The round is the night.** A 10 s "get home!" warning (bottom-right countdown). When the round
   starts, anything you're carrying goes back to its boss (you saw the timer: one rule). After the
   round everyone returns to their pen (not their saved spot), every boss stash restocks at once
   with a "🔪 NEW KNIVES!" banner, READY coffins are waiting. Remove `BaseService.SetReturnSpot`'s
   use and the carry Suspend/resume; update the CLAUDE.md rule.
10. **Faster cycle.** ~3 min stealing + ~2 min round (`IntermissionTime` 360 -> ~180, `RoundTime`
    150 -> ~120). Rescale `Coffins.Rounds` so unlock times stay about the same. Re-run pacing_sim.
11. **Rebalance to Steal An Egg's shape** (their numbers: treadmill +2 .. +3,000, $15K .. $15Qa;
    12 biomes at 0/900/10K/40K/170K/700K/2.5M/17M/700M/2.5B/7B/20B; hatch 10-30 s Common, ~2 min Rare,
    ~8 min Epic, hours at the top; pen 7 -> 19 slots, first upgrade $1K).
    - Money gates again: the 2nd wheel should take ~10 min, not ~1 (our incomes are ~10-20x theirs
      for the same upgrade costs).
    - More, smaller speed gates: split the 8 biomes into ~12 (cheap with item 1), jumps ~3-10x not ~100x.
    - Shorter early unlocks: Rare on the next round or 2 min, Epic ~8 min; round clock from Legendary up.
    - A $1K first pen upgrade. Check pen upgrade costs (`SlotCost` still reads vault `FloorCosts`).
    - Update `tools/pacing_sim.py` to pens first (it still models vault floors).
12. **Faster check on round maps size** after 10: 8 players, ~one biome in size (see 18).

## 4. The hatch layer

13. **See-through coffin.** The knife inside glows in its rarity colour. Diamond+ knives get a second
    "special" glow + sparkles: the same threshold as `announceIfRare` (GuardService), so every
    sparkling coffin is announced to the server. The exact mutation stays hidden until it unlocks.
    Label: name + honest odds ("✨ 1 in 50 chance of RAINBOW"; "✨ SPECIAL Bob" for the sparkling
    ones), computed from `Items.Roll`'s real weights. Labels go back on the boss stash. Player text
    says "unlocks" not "opens". The existing luck roll at opening can stay (the knife is only a glow).
14. **Human names.** The 24 knives get plain human display names (Bob, Gary, Linda...), never a boss
    or disguise name (Frank, Ivy, Sam, Leo, Ruby, Kate, Zoe, Nick). Display = [Mutation] [Rarity]
    [Name], no size ("Rainbow Cosmic Bob"). Internal names stay (saves are safe). Round flex:
    "Killed by RAINBOW Cosmic Bob".
15. **Manual opening.** Coffins due become "READY! Tap to open" (glow, bounce, a ready badge on the
    Knives button) instead of popping in the ceremony (`CoffinService.RoundEnded` / `Open`).
16. **Winner's Luck.** A round win gives boosted mutation odds on coffins you open before the next
    round starts. A surprise banner ("🍀 WINNER'S LUCK x2!"), not part of the pre-round promise.
17. **Fuse Machine** (in your pen). 3 identical unlocked knives -> the same knife one mutation up
    (None -> Gold -> Diamond -> Rainbow -> Void). Each fuse costs one ⚡ charge, earned per round win
    (capped). Only `DataService.RemoveKnife` / `AddKnife`.
18. **Secret rarity** above Cosmic: a tiny roll from the Cosmic boss only, "???" + silhouette in the
    Index until owned. Re-run pacing_sim.

## 5. Maps, money, growth

19. **Murder maps** built from the biome pieces (same walls, floor, dressing, lighting), about one
    biome in size for 8 players, with hedges / sheds for cover. Replace Office/Mansion and delete the
    kit (`RoundMapKit`, `RoundMaps`, `RoundMapDressing`, `RoundMapArt`, ~3,700 lines).
20. **Shop rebuild.** A grid of art tiles like the Index: big number, big price, a 🎁 gift button,
    art that grows with the price (Blender renders). Side tabs Featured / Speed / Money. Hide owned
    passes. Keep the per-player speed math, show only the big number.
21. **Featured locked knife.** A limited-time paid coffin with its odds shown (required for paid
    random items), 1 / 3 / 10 bundles, a countdown, rotated weekly.
22. **Free Gift card** (Steal An Egg's): like / favourite / join the group for a one-time Speed
    reward sized to the next boss. The group join is verified (`IsInGroup`); like / favourite are
    arrow nudges + Roblox's favourite prompt (`client/Favorite.luau`). After the first round win.
    Judge the game on D1 retention and session length, not the like ratio.
23. **Data checks, cut what nobody uses.**
    - The Lucky Wheel (`PlazaWheel` / `Gamble`, its spins products and the Spin prizes in gifts):
      cut it if few players spin. Spins go through `Remotes.Gamble` (wrapped by `Analytics.Remote`).
    - Escape tokens, BossRestock, Tickets, potions: retire the ones with no sales.
24. **Name:** "Steal a Knife" + a [MURDER] tag. Lock it; test thumbnails, not names.
25. **Weekly admin events.** A server-checked admin command system (owner user id only; never open
    up the Studio-only `DebugService`), cross-server via `MessagingService`. Round twists (admin is
    the Murderer, everyone's a Sheriff, Murderer frenzy with 2 Murderers, golden round) and hub
    boosts (luck storm, Secret restock, speed rush). A fixed weekly slot, announced in-game and in
    the group.
26. **Weekly drop + codes.** One new limited knife + one shop tile a week; a codes system for the
    description and videos.
27. **PvP check.** Knock-loose hits (`Targets`, `pvp.knocked_loose`) can't land in the safe zone;
    "Can't attack in the safe zone!".

Later, once likes and retention are healthy: stealing from other players' pens (the biggest
remaining difference from Steal An Egg / Steal a Brainrot; kept out while rounds are gain-only).

## Then: growth

- New thumbnail: one scene, a giant monster, a scared kid with a glowing knife, a "YOU!" arrow, one
  murder hint. Run 2-3 versions in Roblox's thumbnail test.
- A small ad burst to 250 highly engaged users (~$125-250 at <$1 each) for the all-ages unlock.
- Watch D1 retention, session length, rounds per session. Scale only when they hold.
