"""Rough pacing simulation of a player's first hours in Steal a Knife.

Not a replay of the game, a sanity check on the numbers in GameConfig/Knives: a greedy player
who trains Speed on their wheel, runs to the best zone they're fast enough for, mounts what they
bring back, buys wheels / mounts when they can, and gets pulled into a round every cycle. It prints
when each milestone happens and flags long stretches where nothing new unlocks.

Run:  python tools/pacing_sim.py
Numbers here mirror src/shared/Config (update both together).
"""

INCOME = {  # avg of each rarity's pool
    "Common": 115, "Rare": 1367, "Epic": 18000, "Legendary": 260000, "Mythic": 3.73e6,
    "Godly": 59.7e6, "Celestial": 1.05e9, "Cosmic": 18.7e9,
}
ZONES = [  # rarity, SpeedNeeded
    ("Common", 0), ("Rare", 4000), ("Epic", 180000), ("Legendary", 10e6), ("Mythic", 80e6),
    ("Godly", 650e6), ("Celestial", 4e9), ("Cosmic", 31e9),
]
WHEELS = [(10, 0), (30, 15000), (80, 100000), (250, 600000), (800, 4e6), (2500, 30e6), (8000, 250e6),
          (25000, 2e9), (80000, 15e9), (250000, 120e9), (800000, 1e12), (2.5e6, 8e12), (8e6, 70e12)]
TRAILS = [(1.5, 20000), (2, 250000), (3, 3e6), (4, 40e6), (6, 500e6), (8, 7e9), (12, 100e9), (16, 1.5e12),
          (22, 25e12), (30, 400e12)]  # multiplier, cost
STARTING_SLOTS, MAX_SLOTS = 3, 24
REBIRTH_COST = 2e9
INTERMISSION, ROUND = 180, 150
SURVIVE = (7500, 45)  # Min, Seconds of income
COINS_PER_ROUND = 6
COIN = (300, 2)
SURVIVE_CHANCE = 0.5
MUTATION_BONUS = 1.15  # average income lift from mutations/sizes


def slot_cost(slots):
    return 2000 * 2.6 ** (slots - STARTING_SLOTS)


def pay(entry, income):
    return max(entry[0], income * entry[1])


def run_time(zone_index):
    return 45 + 12 * zone_index  # walk out, fight a watchman, carry the case home


def simulate(hours=4.0):
    t, cash, speed = 0.0, 0.0, 0.0
    wheel, slots, trail = 0, STARTING_SLOTS, 0
    wall = []  # incomes
    milestones = []
    seen = set()

    def note(label):
        if label not in seen:
            seen.add(label)
            milestones.append((t, label))

    def income():
        return sum(sorted(wall, reverse=True)[:slots])

    cycle = INTERMISSION + ROUND
    while t < hours * 3600:
        in_round = (t % cycle) >= INTERMISSION
        if in_round:
            dt = ROUND
            cash += income() * dt
            if SURVIVE_CHANCE > 0.5 or (int(t) // cycle) % 2 == 0:
                cash += pay(SURVIVE, income())
            cash += COINS_PER_ROUND * pay(COIN, income())
            t += dt
            continue
        # Shopping first
        bought = True
        while bought:
            bought = False
            if wheel + 1 < len(WHEELS) and cash >= WHEELS[wheel + 1][1]:
                cash -= WHEELS[wheel + 1][1]
                wheel += 1
                bought = True
                note(f"wheel tier {wheel + 1}")
            elif trail < len(TRAILS) and cash >= TRAILS[trail][1] and cash >= 3 * TRAILS[trail][1] / 2:
                cash -= TRAILS[trail][1]
                trail += 1
                bought = True
                note(f"trail x{TRAILS[trail - 1][0]}")
            elif slots < MAX_SLOTS and len(wall) >= slots and cash >= slot_cost(slots):
                cash -= slot_cost(slots)
                slots += 1
                bought = True
                note(f"{slots} mounts")
        best_zone = max(i for i, (_, need) in enumerate(ZONES) if speed >= need)
        rarity = ZONES[best_zone][0]
        note(f"can farm {rarity}")
        knife = INCOME[rarity] * MUTATION_BONUS
        worst = min(wall) if len(wall) >= slots else 0
        next_need = ZONES[best_zone + 1][1] if best_zone + 1 < len(ZONES) else None
        # Run if a new knife would improve the wall, else train toward the next zone
        if len(wall) < slots or knife > worst * 1.05 or next_need is None:
            dt = run_time(best_zone)
            cash += income() * dt
            if len(wall) >= slots:
                wall.remove(worst)
            wall.append(knife)
            note(f"first {rarity} knife")
        else:
            dt = 60
            cash += income() * dt
            speed += WHEELS[wheel][0] * (TRAILS[trail - 1][0] if trail else 1) * dt
        t += dt
        if cash >= REBIRTH_COST:
            note("could rebirth")
    return milestones, income(), speed


if __name__ == "__main__":
    milestones, income, speed = simulate()
    last = 0.0
    print(f"{'time':>7}  milestone")
    for at, label in milestones:
        gap = at - last
        flag = "   <-- long gap" if gap > 20 * 60 else ""
        print(f"{at / 60:6.1f}m  {label}{flag}")
        last = at
    print(f"\nafter 4h: {income:,.0f}/s income, {speed:,.0f} Speed")
