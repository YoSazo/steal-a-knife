"""Rough pacing simulation of a player's first hours in Steal a Knife.

Not a replay of the game, a sanity check on the numbers in GameConfig/Knives: a greedy player
who trains Speed on their wheel, runs to the best zone they're fast enough for, mounts what they
bring back, buys wheels / mounts when they can, and gets pulled into a round every cycle. It prints
when each milestone happens and flags long stretches where nothing new unlocks.

Run:  python tools/pacing_sim.py
Numbers here mirror src/shared/Config (update both together).
"""

INCOME = {"Common": 1.5, "Rare": 9, "Epic": 45, "Legendary": 225, "Godly": 1100}  # avg of each pool
ZONES = [  # rarity, SpeedNeeded
    ("Common", 0), ("Rare", 1000), ("Epic", 15000), ("Legendary", 200000), ("Godly", 3000000),
]
WHEELS = [(10, 0), (30, 200), (80, 1500), (200, 6000), (500, 25000), (1200, 80000),
          (3000, 250000), (8000, 800000), (20000, 2500000), (50000, 8000000)]
STARTING_SLOTS, MAX_SLOTS = 3, 12
REBIRTH_COST = 75000
INTERMISSION, ROUND = 180, 150
SURVIVE = (100, 45)  # Min, Seconds of income
COINS_PER_ROUND = 6
COIN = (5, 2)
SURVIVE_CHANCE = 0.5
MUTATION_BONUS = 1.15  # average income lift from mutations/sizes


def slot_cost(slots):
    return 150 * 2 ** (slots - STARTING_SLOTS)


def pay(entry, income):
    return max(entry[0], income * entry[1])


def run_time(zone_index):
    return 45 + 12 * zone_index  # walk out, fight a watchman, carry the case home


def simulate(hours=4.0):
    t, cash, speed = 0.0, 0.0, 0.0
    wheel, slots = 0, STARTING_SLOTS
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
            speed += WHEELS[wheel][0] * dt
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
