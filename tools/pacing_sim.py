"""Rough pacing simulation of a player's first day(s) in Steal and Murder.

Not a replay of the game: a sanity check on the numbers in GameConfig / Knives. A greedy player
trains Speed on their wheel, runs to the deepest biome they're fast enough for, mounts what they
bring back (after its coffin's murder-round wait), buys wheels / trails / floors when they can,
rebirths as soon as they're allowed, and gets pulled into a murder round every cycle (its prize
also adds Speed). It prints when each milestone happens (in hours of play) and flags long
stretches where nothing new unlocks.

Targets (Steal an Egg / Steal a Brainrot feel): Epic in the first hour, Legendary ~3h, Mythic by the
end of day one (~6h), Godly on day 2-3, Celestial in week one, Cosmic is the long-haul goal. (A
committed kid found the whole game "too easy" at this file's old numbers - the wheel/trail COST
columns were the main leak: a tier paid for itself in minutes of the income it was meant to take
hours to reach.)

Run:  python tools/pacing_sim.py [hours]
Numbers here mirror src/shared/Config (update both together).
"""

import random
import sys

RARITIES = ["Common", "Rare", "Epic", "Legendary", "Mythic", "Godly", "Celestial", "Cosmic"]
INCOME = {  # average of each rarity's three knives (Config/Knives)
    "Common": 115, "Rare": 1367, "Epic": 18000, "Legendary": 260000, "Mythic": 3.73e6,
    "Godly": 59.7e6, "Celestial": 1.05e9, "Cosmic": 18.7e9,
}
GUARD_SPEED = [12.5, 26, 47, 70, 82, 94, 104, 114]  # GameConfig.Zones[i].GuardSpeed
CARRY = 0.9  # GameConfig.CarrySpeedMultiplier
BASE_WALK, SPEED_CURVE, MAX_WALK = 16, 3.6, 135  # GameConfig.WalkSpeedFor
# Rate (Speed/step), Cost. Rescaled to Steal An Egg's own published ratios: rate grows ~2.4x a
# tier (was ~3.1x) and the top tier sits at the same rate-vs-hardest-zone ratio theirs does; cost
# escalates tier to tier like theirs (10x,12x,14x...), not a flat multiple (GameConfig.Treadmills).
WHEELS = [(10, 0), (25, 15000), (60, 180000), (150, 2.52e6), (350, 40.3e6), (850, 726e6),
          (2000, 14.5e9), (5000, 319e9), (12000, 7.66e12), (29000, 199e12), (70000, 5.58e15),
          (170000, 167e15), (400000, 5.36e18)]
TRAILS = [(1.5, 20000), (2, 250000), (3, 3e6), (4, 40e6), (6, 500e6), (8, 7e9), (12, 100e9), (16, 1.5e12),
          (17, 25e12), (20, 400e12)]  # multiplier, cost (kept through rebirth) - top trimmed, see GameConfig
STARTING_SLOTS, SLOTS_PER_FLOOR, MAX_SLOTS = 10, 10, 40
FLOOR_COSTS = [1.5e6, 2e10, 1e14]  # 2nd, 3rd, 4th floor
FLOOR_REBIRTHS = [0, 1, 3]  # rebirths needed for the 2nd, 3rd, 4th floor
REBIRTH_BASE, REBIRTH_GROWTH = 2e9, 6
REBIRTH_INCOME, REBIRTH_SPEED = 0.5, 0.3
REBIRTH_NEEDS = ["Mythic", "Godly", "Godly", "Celestial", "Celestial", "Cosmic"]  # then Cosmic (was Legendary first)
INTERMISSION, ROUND = 360, 150
# A stolen knife's income doesn't count until its coffin's murder-round wait is over
# (GameConfig.Coffins.Rounds; was 0/1/1/2/2/3/4/5).
COFFIN_ROUNDS = {"Common": 0, "Rare": 1, "Epic": 2, "Legendary": 4, "Mythic": 8,
                 "Godly": 14, "Celestial": 24, "Cosmic": 36}
STEP_SHARE, MIN_SPEED_PRIZE = 0.05, 300  # RoundPrize.StepShare / MinSpeed (was 0.2: see GameConfig)
WIN_CHANCE = 0.65  # rough share of rounds a player ends up on the winning side
ZONE_DEPTHS = [90, 130, 170, 210, 250, 290, 330, 370]
FIRST_BOSS_Z = 50
EXTRA_INCOME = 1.4  # survivor 2x boosts, mutations / sizes, friends, wheel cash: on average
CATCH_CHANCE = 0.25  # a run where the boss gets you (the knife goes back)


def speed_needed(zone):
    walk = GUARD_SPEED[zone] / CARRY
    return 0 if walk <= BASE_WALK else 500 * (2 ** ((walk - BASE_WALK) / SPEED_CURVE) - 1)


def run_time(zone):
    # Route estimate (not telemetry): cumulative distance, lateral lair approach and plaza walk.
    boss_z = FIRST_BOSS_Z if zone == 0 else sum(ZONE_DEPTHS[:zone]) + .6 * ZONE_DEPTHS[zone]
    walk = max(BASE_WALK, GUARD_SPEED[zone] / CARRY + .5)
    return 8 + 2 * (boss_z + 110 + 60) / walk


def simulate(hours, seed=1):
    rng = random.Random(seed)
    t, cash, speed = 0.0, 0.0, 0.0
    wheel, trail, slots, rebirths = 0, 0, STARTING_SLOTS, 0
    wall = []  # (income, rarity index, ready_at: when the coffin's murder-round wait is over)
    milestones, seen = [], set()

    def note(label):
        if label not in seen:
            seen.add(label)
            milestones.append((t, label))

    def income():
        ready = [k for k in wall if k[2] <= t]
        best = sorted(ready, reverse=True)[:slots]
        return sum(k[0] for k in best) * (1 + rebirths * REBIRTH_INCOME) * EXTRA_INCOME

    cycle = INTERMISSION + ROUND
    runs = 0
    while t < hours * 3600:
        if (t % cycle) >= INTERMISSION:  # in a murder round: the vault keeps paying
            cash += income() * ROUND
            if rng.random() < WIN_CHANCE:
                best_zone = max(i for i in range(len(RARITIES)) if speed >= speed_needed(i))
                if best_zone + 1 < len(RARITIES):
                    need, previous = speed_needed(best_zone + 1), speed_needed(best_zone)
                    speed += max(STEP_SHARE * (need - previous), MIN_SPEED_PRIZE)
                else:
                    speed += max(speed * 0.1, MIN_SPEED_PRIZE)
            t += ROUND
            continue
        # Rebirth?
        need = REBIRTH_NEEDS[min(rebirths, len(REBIRTH_NEEDS) - 1)]
        cost = REBIRTH_BASE * REBIRTH_GROWTH ** rebirths
        if cash >= cost and any(r >= RARITIES.index(need) for _, r, rt in wall if rt <= t):
            rebirths += 1
            note(f"REBIRTH {rebirths}")
            cash, speed, wheel, trail, slots, wall = 0, 0, 0, 0, STARTING_SLOTS, []
        # Shopping
        bought = True
        while bought:
            bought = False
            floor = slots // SLOTS_PER_FLOOR  # floors owned
            ready_now = [k for k in wall if k[2] <= t]
            if wheel + 1 < len(WHEELS) and cash >= WHEELS[wheel + 1][1]:
                cash -= WHEELS[wheel + 1][1]
                wheel += 1
                bought = True
            elif trail < len(TRAILS) and cash >= TRAILS[trail][1] * 1.5:
                cash -= TRAILS[trail][1]
                trail += 1
                bought = True
            elif (slots < MAX_SLOTS and len(ready_now) >= slots and cash >= FLOOR_COSTS[floor - 1]
                  and rebirths >= FLOOR_REBIRTHS[floor - 1]):
                cash -= FLOOR_COSTS[floor - 1]
                slots += SLOTS_PER_FLOOR
                bought = True
                note(f"floor {floor + 1}")
        best_zone = max(i for i in range(len(RARITIES)) if speed >= speed_needed(i))
        rarity = RARITIES[best_zone]
        note(f"can farm {rarity}")
        ready_now = [k for k in wall if k[2] <= t]
        worst = min(ready_now) if len(ready_now) >= slots else None
        last_zone = best_zone == len(RARITIES) - 1
        if worst is None or INCOME[rarity] > worst[0] * 1.05 or last_zone:
            dt = run_time(best_zone)
            runs += 1
            if runs % round(1 / CATCH_CHANCE) != 0:
                knife = (INCOME[rarity], best_zone, t + dt + COFFIN_ROUNDS[rarity] * cycle)
                if worst is not None:
                    wall.remove(worst)
                wall.append(knife)
                note(f"first {rarity} knife")
        else:
            dt = 60
            rate = WHEELS[wheel][0] * (TRAILS[trail - 1][0] if trail else 1) * (1 + rebirths * REBIRTH_SPEED)
            speed += rate * dt
        cash += income() * dt
        t += dt
    return milestones, income(), speed, rebirths


if __name__ == "__main__":
    hours = float(sys.argv[1]) if len(sys.argv) > 1 else 24
    print("Speed needed per biome:", ", ".join(f"{r} {speed_needed(i):.3g}" for i, r in enumerate(RARITIES)))
    milestones, income, speed, rebirths = simulate(hours)
    last = 0.0
    print(f"{'hours':>6}  milestone")
    for at, label in milestones:
        if label.startswith("can farm"):
            continue
        flag = "   <-- long gap" if at - last > 3 * 3600 else ""
        print(f"{at / 3600:6.2f}  {label}{flag}")
        last = at
    print(f"\nafter {hours:g}h: {income:,.0f}/s income, {speed:,.0f} Speed, {rebirths} rebirths")
