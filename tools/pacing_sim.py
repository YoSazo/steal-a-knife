"""Rough pacing simulation of a player's first day(s) in Steal a Knife.

Not a replay of the game: a sanity check on the numbers in GameConfig / Knives. A greedy player
trains Speed on their wheel, runs to the deepest biome they're fast enough for, mounts what they
bring back, buys wheels / trails / floors when they can, rebirths as soon as they're allowed, and
gets pulled into a murder round every cycle. It prints when each milestone happens (in hours of
play) and flags long stretches where nothing new unlocks.

Targets (Steal an Egg / Steal a Brainrot feel): Epic in the first hour, Legendary ~3h, Mythic by the
end of day one (~6h), Godly on day 2-3, Celestial in week one, Cosmic is the long-haul goal.

Run:  python tools/pacing_sim.py [hours]
Numbers here mirror src/shared/Config (update both together).
"""

import math
import sys

RARITIES = ["Common", "Rare", "Epic", "Legendary", "Mythic", "Godly", "Celestial", "Cosmic"]
INCOME = {  # average of each rarity's three knives (Config/Knives)
    "Common": 115, "Rare": 1367, "Epic": 18000, "Legendary": 260000, "Mythic": 3.73e6,
    "Godly": 59.7e6, "Celestial": 1.05e9, "Cosmic": 18.7e9,
}
GUARD_SPEED = [12.5, 26, 47, 70, 82, 94, 104, 114]  # GameConfig.Zones[i].GuardSpeed
CARRY = 0.9  # GameConfig.CarrySpeedMultiplier
BASE_WALK, SPEED_CURVE, MAX_WALK = 16, 3.6, 135  # GameConfig.WalkSpeedFor
WHEELS = [(10, 0), (30, 15000), (80, 100000), (250, 600000), (800, 4e6), (2500, 30e6), (8000, 250e6),
          (25000, 2e9), (80000, 15e9), (250000, 120e9), (800000, 1e12), (2.5e6, 8e12), (8e6, 70e12)]
TRAILS = [(1.5, 20000), (2, 250000), (3, 3e6), (4, 40e6), (6, 500e6), (8, 7e9), (12, 100e9), (16, 1.5e12),
          (22, 25e12), (30, 400e12)]  # multiplier, cost (kept through rebirth)
STARTING_SLOTS, SLOTS_PER_FLOOR, MAX_SLOTS = 10, 10, 40
FLOOR_COSTS = [1.5e6, 2e10, 1e14]  # 2nd, 3rd, 4th floor
FLOOR_REBIRTHS = [0, 1, 3]  # rebirths needed for the 2nd, 3rd, 4th floor
REBIRTH_BASE, REBIRTH_GROWTH = 2e9, 6
REBIRTH_INCOME, REBIRTH_SPEED = 0.5, 0.3
REBIRTH_NEEDS = ["Legendary", "Mythic", "Godly", "Godly", "Celestial", "Celestial", "Cosmic"]  # then Cosmic
INTERMISSION, ROUND = 180, 150
EXTRA_INCOME = 1.4  # Heat, survivor 2x boosts, mutations / sizes, friends, wheel cash: on average
CATCH_CHANCE = 0.25  # a run where the boss gets you (the knife goes back)


def speed_needed(zone):
    walk = GUARD_SPEED[zone] / CARRY
    return 0 if walk <= BASE_WALK else 500 * (2 ** ((walk - BASE_WALK) / SPEED_CURVE) - 1)


def run_time(zone):
    return 45 + 12 * zone  # walk out, steal, run the knife home


def simulate(hours):
    t, cash, speed = 0.0, 0.0, 0.0
    wheel, trail, slots, rebirths = 0, 0, STARTING_SLOTS, 0
    wall = []  # (income, rarity index)
    milestones, seen = [], set()

    def note(label):
        if label not in seen:
            seen.add(label)
            milestones.append((t, label))

    def income():
        best = sorted(wall, reverse=True)[:slots]
        return sum(k[0] for k in best) * (1 + rebirths * REBIRTH_INCOME) * EXTRA_INCOME

    cycle = INTERMISSION + ROUND
    runs = 0
    while t < hours * 3600:
        if (t % cycle) >= INTERMISSION:  # in a murder round: the vault keeps paying
            cash += income() * ROUND
            t += ROUND
            continue
        # Rebirth?
        need = REBIRTH_NEEDS[min(rebirths, len(REBIRTH_NEEDS) - 1)]
        cost = REBIRTH_BASE * REBIRTH_GROWTH ** rebirths
        if cash >= cost and any(r >= RARITIES.index(need) for _, r in wall):
            rebirths += 1
            note(f"REBIRTH {rebirths}")
            cash, speed, wheel, slots, wall = 0, 0, 0, STARTING_SLOTS, []
        # Shopping
        bought = True
        while bought:
            bought = False
            floor = slots // SLOTS_PER_FLOOR  # floors owned
            if wheel + 1 < len(WHEELS) and cash >= WHEELS[wheel + 1][1]:
                cash -= WHEELS[wheel + 1][1]
                wheel += 1
                bought = True
            elif trail < len(TRAILS) and cash >= TRAILS[trail][1] * 1.5:
                cash -= TRAILS[trail][1]
                trail += 1
                bought = True
            elif (slots < MAX_SLOTS and len(wall) >= slots and cash >= FLOOR_COSTS[floor - 1]
                  and rebirths >= FLOOR_REBIRTHS[floor - 1]):
                cash -= FLOOR_COSTS[floor - 1]
                slots += SLOTS_PER_FLOOR
                bought = True
                note(f"floor {floor + 1}")
        best_zone = max(i for i in range(len(RARITIES)) if speed >= speed_needed(i))
        rarity = RARITIES[best_zone]
        note(f"can farm {rarity}")
        knife = (INCOME[rarity], best_zone)
        worst = min(wall) if len(wall) >= slots else None
        last_zone = best_zone == len(RARITIES) - 1
        if worst is None or knife[0] > worst[0] * 1.05 or last_zone:
            dt = run_time(best_zone)
            runs += 1
            if runs % round(1 / CATCH_CHANCE) != 0:
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
