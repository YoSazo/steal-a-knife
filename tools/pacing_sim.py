"""Rough pacing model for Steal a Knife, not a replay or player telemetry.

Models a free player's delivered coffins, banked survival ladder, cash income,
pen room and rebirths. Targets: Rare 0.34h, Epic 1.2h, Legendary 4h, Mythic 8h.
The seed makes tuning reproducible; survival, pickups and failed steals are estimates.
Run: python tools/pacing_sim.py [hours] [--fit]
--fit solves the first four per-zone shares and prints the GameConfig table.
Numbers mirror src/shared/Config; update both together.
"""

import random
import sys

RARITIES = ["Common", "Rare", "Epic", "Legendary", "Mythic", "Godly", "Celestial", "Cosmic"]
INCOME = {  # average of each rarity's three knives (Config/Knives)
    "Common": 115, "Rare": 1367, "Epic": 18000, "Legendary": 260000, "Mythic": 3.73e6,
    "Godly": 59.7e6, "Celestial": 1.05e9, "Cosmic": 18.7e9, "Secret": 50e9,
}
GUARD_SPEED = [12.5, 26, 47, 70, 82, 94, 104, 114]  # GameConfig.Zones[i].GuardSpeed
CARRY = 0.9  # GameConfig.CarrySpeedMultiplier
BASE_WALK, SPEED_CURVE, MAX_WALK = 16, 3.6, 135  # GameConfig.WalkSpeedFor
TRAILS = [(1.5, 160000), (2, 1.25e6), (3, 9e6), (4, 80e6), (6, 500e6), (8, 7e9), (12, 100e9), (16, 1.5e12),
          (17, 25e12), (20, 400e12)]  # multiplier, cost (kept through rebirth) - top trimmed, see GameConfig
# Pens (GameConfig.Pens): room grows one knife at a time, 10 -> 20 (Pens.SlotCosts)
STARTING_SLOTS, MAX_SLOTS = 10, 20
PEN_COSTS = [1e3, 2.5e5, 5e6, 7.5e7, 1e9, 1.5e10, 3e10, 6e10, 1.2e11, 2.4e11]
REBIRTH_BASE, REBIRTH_GROWTH = 2e9, 6
REBIRTH_INCOME, REBIRTH_SPEED = 0.5, 0.3
REBIRTH_NEEDS = ["Mythic", "Godly", "Godly", "Celestial", "Celestial", "Cosmic"]  # then Cosmic (was Legendary first)
INTERMISSION, REVEAL, ROUND, RESULTS = 70, 3.6, 60, 8
DOUBLE_ROUND_CHANCE = .25
# A stolen knife's income doesn't count until its coffin's murder-round wait is over
# (GameConfig.Coffins.Rounds; was 0/1/1/2/2/3/4/5).
COFFIN_ROUNDS = {"Common": 0, "Rare": 1, "Epic": 2, "Legendary": 3, "Mythic": 4,
                 "Godly": 6, "Celestial": 8, "Cosmic": 10, "Secret": 12}
COIN_SPEED = [1, 25, 600, 8000, 80000, 600000, 3200000, 27000000]
SHARES = [0, 0.16207, 0.0483677, 0.0168899, 0.0110595, 0.008, 0.006, 0.004]
MIN_SPEED_PRIZE = 300  # GameConfig.RoundPrize.MinSpeed
WIN_CHANCE = 0.65  # rough share of rounds a player ends up on the winning side
ZONE_DEPTHS = [90, 130, 170, 210, 250, 290, 330, 370]
FIRST_BOSS_Z = 50
EXTRA_INCOME = 1.4  # estimated mutations, sizes and friends
SECRET_CHANCE = .0005  # Cosmic-boss restocks only, GameConfig.Secret
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
    rng=random.Random(seed)
    t=cash=speed=0.0
    slots,trail,rebirths=STARTING_SLOTS,0,0
    wall=[] # income, rarity, ready time
    milestones=[]
    seen=set()
    def note(label, at=None):
        if label not in seen:
            seen.add(label); milestones.append((t if at is None else at,label))
    def income():
        return sum(k[0] for k in wall if k[2]<=t)*(1+rebirths*REBIRTH_INCOME)*EXTRA_INCOME
    def budget():
        zone=max(i for i in range(8) if speed>=speed_needed(i))
        if zone==7: return max(MIN_SPEED_PRIZE,speed*.03)
        return max(MIN_SPEED_PRIZE,(speed_needed(zone+1)-speed_needed(zone))*SHARES[zone+1])*(1+rebirths*REBIRTH_SPEED)
    cycle=INTERMISSION+REVEAL+ROUND+RESULTS
    runs=0
    iterations=0
    while t<hours*3600:
        iterations+=1
        if iterations>100000:
            raise RuntimeError(f"Simulation stuck at {t}, shares {SHARES}")
        cycle_start=int((t+1e-7)//cycle)*cycle
        if t-cycle_start>=INTERMISSION-1e-7:
            full=budget()
            survived=rng.random()<WIN_CHANCE
            elapsed=60 if survived else rng.uniform(5,55)
            parts=sum(p for at,p in zip([10,20,35,50,60],[1,2,4,7,12]) if at<=elapsed)
            multiplier=2 if rng.random()<DOUBLE_ROUND_CHANCE else 1
            speed+=full*max(1,parts)/26*multiplier
            speed+=3*multiplier # typical round coins: each is exactly +1 Speed
            cash+=income()*(REVEAL+ROUND+RESULTS)
            t+=REVEAL+ROUND+RESULTS
            if survived:
                # Winners advance one extra hatch round (GameConfig.Coffins.WinRounds = 2).
                wall=[(pay, rarity, max(t, ready-cycle)) if ready>t else (pay,rarity,ready) for pay,rarity,ready in wall]
            continue
        cost=REBIRTH_BASE*REBIRTH_GROWTH**rebirths
        need=REBIRTH_NEEDS[min(rebirths,len(REBIRTH_NEEDS)-1)]
        if cash>=cost and any(r>=RARITIES.index(need) and ready<=t for _,r,ready in wall):
            rebirths+=1; note(f"REBIRTH {rebirths}")
            cash=speed=0.0; slots=STARTING_SLOTS; wall=[]
        while slots<MAX_SLOTS and len(wall)>=slots and cash>=PEN_COSTS[slots-STARTING_SLOTS]:
            cash-=PEN_COSTS[slots-STARTING_SLOTS]; slots+=1; note(f"pen {slots}")
        if trail<len(TRAILS) and cash>=TRAILS[trail][1]*1.5:
            cash-=TRAILS[trail][1]; trail+=1
        zone=max(i for i in range(8) if speed>=speed_needed(i))
        rarity=RARITIES[zone]
        note(f"can farm {rarity}")
        boundary=cycle_start+INTERMISSION
        dt=min(run_time(zone),max(0,boundary-t))
        if dt<=0: t=boundary; continue
        ready=[k for k in wall if k[2]<=t]
        worst=min(ready) if ready else None
        full=len(wall)>=slots
        can_steal=(not full) or (worst is not None and INCOME[rarity]>worst[0]*1.05)
        if can_steal and dt>=run_time(zone):
            runs+=1
            if runs==1 or rng.random()>=CATCH_CHANCE:
                speed+=budget()*.1
                if full: wall.remove(worst)
                stolen = "Secret" if zone == 7 and rng.random() < SECRET_CHANCE else rarity
                wall.append((INCOME[stolen],zone,t+dt+COFFIN_ROUNDS[stolen]*cycle))
                speed+=2*COIN_SPEED[zone] # typical coins picked up along this biome run
                note(f"first {stolen} knife",t+dt)
        else:
            dt=min(10,max(0,boundary-t))
        cash+=income()*dt
        t+=dt
    return milestones,income(),speed,rebirths


def fit_shares():
    targets = [("Rare", .34), ("Epic", 1.2), ("Legendary", 4), ("Mythic", 8)]
    # Tune shallow to deep: earlier shares determine the starting time of later goals.
    for zone, (rarity, target) in enumerate(targets, start=1):
        def error(share):
            SHARES[zone] = round(share, 7)
            marks, *_ = simulate(12)
            reached = next((at/3600 for at, label in marks if label == f"first {rarity} knife"), 12)
            return abs(reached-target)
        low, high = (0.15, 0.3) if zone == 1 else (0.001, SHARES[zone-1])
        best = SHARES[zone]
        for _ in range(4):
            values = [low+(high-low)*i/80 for i in range(81)]
            best = min(values, key=error)
            width = (high-low)/80
            low, high = max(.0001, best-width), best+width
        SHARES[zone] = round(best, 7)
    print("ZoneShares = { " + ", ".join(f"[{i+1}] = {share:.7f}" for i,share in enumerate(SHARES) if i) + " },")


if __name__ == "__main__":
    args = [arg for arg in sys.argv[1:] if arg != "--fit"]
    hours = float(args[0]) if args else 24
    if "--fit" in sys.argv:
        fit_shares()
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
