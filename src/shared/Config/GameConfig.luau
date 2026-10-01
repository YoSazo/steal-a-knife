--!strict
-- Every tunable number in one place. Shared so the client can show prices; the server is the
-- only one that ever acts on them.

-- One day of the login streak: "Cash" (Seconds of income, at least Min), "Case" (Rarity) or
-- "Tickets" (Amount)
export type DailyReward = { Kind: string, Seconds: number?, Min: number?, Rarity: string?, Amount: number? }

local DAILY: { DailyReward } = {
	{ Kind = "Cash", Seconds = 120, Min = 250 },
	{ Kind = "Case", Rarity = "Common" },
	{ Kind = "Cash", Seconds = 300, Min = 600 },
	{ Kind = "Tickets", Amount = 2 },
	{ Kind = "Cash", Seconds = 600, Min = 1500 },
	{ Kind = "Case", Rarity = "Rare" },
	{ Kind = "Case", Rarity = "Epic" },
}

local GameConfig = {
	-- Economy / progression
	StartingCash = 0,
	StartingSlots = 3,
	MaxSlots = 12,
	TicketCost = 500, -- the floor; tickets cost TicketIncomeSeconds of your income (TicketPrice)
	TicketIncomeSeconds = 60,

	-- Reasons to come back: the vault keeps earning while you're away (a fraction, capped), and a
	-- 7-day login streak (miss a day and it starts over). Cash days pay seconds of your income.
	Offline = { Fraction = 0.5, MaxHours = 8, MinAway = 120 },
	Daily = DAILY,
	-- New players can't lose knives (vault break-ins, burglars, Murderer loot) until they've played
	-- this long, so nobody gets robbed in their first few minutes
	NewPlayerShield = 1200,
	MaxTickets = 5,
	TicketWeight = 3, -- one ticket spent in a round = this much extra Murderer weight

	-- Movement. Speed is a big number trained by running in your vault's Haunted Wheel; it turns
	-- into running speed on a curve (WalkSpeedFor). Each zone needs a certain Speed: there's no
	-- barrier, but below it that zone's guards will run you down on the way home.
	BaseWalkSpeed = 16,
	MaxWalkSpeed = 80,
	CarrySpeedMultiplier = 0.9,
	-- Haunted Wheel tiers (the code calls it the treadmill): Rate = Speed per second while running
	-- in it; Cost to buy that tier
	Treadmills = {
		{ Name = "Creaky Wheel", Rate = 10, Cost = 0 },
		{ Name = "Iron Wheel", Rate = 30, Cost = 200 },
		{ Name = "Steam Wheel", Rate = 80, Cost = 1500 },
		{ Name = "Haunted Wheel", Rate = 200, Cost = 6000 },
		{ Name = "Cursed Wheel", Rate = 500, Cost = 25000 },
		{ Name = "Bone Wheel", Rate = 1200, Cost = 80000 },
		{ Name = "Blood Moon Wheel", Rate = 3000, Cost = 250000 },
		{ Name = "Phantom Wheel", Rate = 8000, Cost = 800000 },
		{ Name = "Infernal Wheel", Rate = 20000, Cost = 2500000 },
		{ Name = "Void Wheel", Rate = 50000, Cost = 8000000 },
	},
	-- Vault walls: the better your walls, the taller and scarier your vault (everyone walks past
	-- them on the plaza) and the longer its gate holds out in a raid. Raiders chip the gate with
	-- knife hits and throws; it can always be broken, it just takes better knives or more friends.
	Walls = {
		{
			Name = "Wooden Palisade",
			Height = 11,
			GateHealth = 400,
			Cost = 0,
			Color = Color3.fromRGB(120, 82, 52),
			Material = Enum.Material.WoodPlanks,
			Trim = Color3.fromRGB(70, 50, 34),
		},
		{
			Name = "Stone Keep",
			Height = 14,
			GateHealth = 1100,
			Cost = 2500,
			Color = Color3.fromRGB(112, 108, 118),
			Material = Enum.Material.Cobblestone,
			Trim = Color3.fromRGB(80, 76, 86),
		},
		{
			Name = "Iron Bastion",
			Height = 17,
			GateHealth = 2800,
			Cost = 25000,
			Color = Color3.fromRGB(78, 82, 92),
			Material = Enum.Material.DiamondPlate,
			Trim = Color3.fromRGB(150, 150, 160),
		},
		{
			Name = "Bone Fortress",
			Height = 20,
			GateHealth = 7000,
			Cost = 220000,
			Color = Color3.fromRGB(222, 212, 186),
			Material = Enum.Material.Limestone,
			Trim = Color3.fromRGB(120, 30, 30),
		},
		{
			Name = "Cursed Citadel",
			Height = 23,
			GateHealth = 16000,
			Cost = 1800000,
			Color = Color3.fromRGB(42, 30, 54),
			Material = Enum.Material.Basalt,
			Trim = Color3.fromRGB(170, 70, 255),
		},
		{
			Name = "Void Sanctum",
			Height = 27,
			GateHealth = 38000,
			Cost = 15000000,
			Color = Color3.fromRGB(14, 10, 22),
			Material = Enum.Material.Glass,
			Trim = Color3.fromRGB(120, 255, 240),
		},
	},

	-- Raids: a server-wide event near the end of every intermission. Gates can be broken, players
	-- can knock each other down (no dying in the hub - you drop what you carry), broken vaults can
	-- be robbed, and burglar NPCs come for everyone's knives so even a quiet server gets a raid.
	Raid = {
		Duration = 120,
		StartBefore = 140, -- starts this many seconds before the murder round (ends ~20s before it)
		MinPlayers = 1, -- burglars make a raid fun on your own
		GateRegenDelay = 6, -- a gate nobody has hit for this long starts repairing itself
		GateRegen = 0.03, -- fraction of its max health per second
		BrokenTime = 22, -- a broken gate stays open this long, then reforges at half health
		RepairTime = 1.2, -- owner hold-to-repair
		RepairAmount = 0.2, -- of max health per repair
		RepairCooldown = 4,
		StealTime = 1.6, -- hold to lift a knife off someone's wall
		KnockdownTime = 2.2,
		KnockImmunity = 3.5, -- after getting up, no knocking you straight back down
		RevengeTime = 60, -- robbed? their vault is open to you (and only you) for this long
		ThrowGateMultiplier = 1.25, -- thrown knives hit gates a bit harder than swings
		Burglars = 3,
		BurglarHealth = 160,
		BurglarSpeed = 17,
		BurglarCarrySpeed = 13,
		BurglarReward = 60,
		BurglarGateDamage = 35, -- per bash
	},

	-- Rebirth: start over (cash, knives, slots, Speed, wheel, walls) for a permanent multiplier on
	-- income and Speed training, a title, and better luck in cases
	Rebirth = {
		BaseCost = 75000,
		CostGrowth = 5,
		IncomeBonus = 0.5, -- +50% income per rebirth
		SpeedBonus = 0.3, -- +30% Speed training per rebirth
		LuckBonus = 0.15, -- +15% mutation / size luck per rebirth
		Max = 30,
		Titles = {
			"Pickpocket",
			"Cutpurse",
			"Burglar",
			"Night Thief",
			"Shadow",
			"Phantom Thief",
			"Master Thief",
			"Blackwood Legend",
			"Lord of Knives",
			"The Untouchable",
		},
	},

	TutorialReward = 150,

	-- The Case Shop: sealed cases for cash, opened on the spot (same odds as watchmen's cases)
	CaseShop = {
		{ Rarity = "Common", Cost = 250 },
		{ Rarity = "Rare", Cost = 3500 },
		{ Rarity = "Epic", Cost = 45000 },
		{ Rarity = "Legendary", Cost = 600000 },
		{ Rarity = "Godly", Cost = 9000000 },
	},

	-- A free chest on the plaza every so often: cash (scaled to what you earn) or a case
	FreeChest = { Cooldown = 600, MinCash = 150, IncomeSeconds = 90, CaseChance = 0.4 },

	-- The Index pays out once for every knife you've ever owned
	IndexRewards = {
		Common = { Cash = 150, Speed = 100 },
		Rare = { Cash = 1500, Speed = 1500 },
		Epic = { Cash = 20000, Speed = 20000 },
		Legendary = { Cash = 250000, Speed = 250000 },
		Godly = { Cash = 3000000, Speed = 3000000 },
	},

	-- Rounds: innocents power their abilities with coins. Each power costs Energy; you start every
	-- round with a little and every coin you grab adds more.
	StartEnergy = 3,
	MaxEnergy = 8,
	EnergyPerCoin = 1,

	RoundWalkSpeed = 16, -- upgrades don't carry into rounds so new players can still win
	MurdererWalkSpeed = 17,

	-- The hub is one long straight runway (like the big steal games): the vaults open onto a plaza
	-- at the start, and the zones run one after another down the runway, each rarer and nastier,
	-- all the way to the Manor. Each guard holds a knife from its zone's pool; kill it for the knife.
	ZoneDepth = 220,
	ArenaWidth = 70,
	HideawaySpacing = 70, -- candlelit nooks in the walls every this many studs; guards can't follow
	CatchRadius = 4.5,
	Zones = {
		-- Speeds are tuned against carry speed (16 * 0.9 = 14.4 with no upgrades). Health is tuned
		-- against knife Damage: a Rusty Shank (25) takes 3 hits on a Common guard.
		{
			Rarity = "Common",
			Title = "The Courtyard",
			Guards = 5,
			GuardSpeed = 10,
			SpeedNeeded = 0,
			Detect = 14, -- the runway is narrow; easy zones only notice you up close
			Health = 75,
			Damage = 8,
			Reward = 5,
			Respawn = 10,
			Color = Color3.fromRGB(130, 220, 120),
		},
		{
			Rarity = "Rare",
			Title = "The Gardens",
			Guards = 5,
			GuardSpeed = 19,
			SpeedNeeded = 1000,
			Detect = 20,
			Health = 200,
			Damage = 18,
			Reward = 15,
			Respawn = 15,
			Color = Color3.fromRGB(110, 190, 255),
		},
		{
			Rarity = "Epic",
			Title = "The Crypts",
			Guards = 5,
			GuardSpeed = 28,
			SpeedNeeded = 15000,
			Detect = 32,
			Health = 450,
			Damage = 25,
			Reward = 40,
			Respawn = 20,
			Throws = true,
			Color = Color3.fromRGB(190, 140, 255),
		},
		{
			Rarity = "Legendary",
			Title = "The Catacombs",
			Guards = 5,
			GuardSpeed = 37,
			SpeedNeeded = 200000,
			Detect = 36,
			Health = 1000,
			Damage = 34,
			Reward = 120,
			Respawn = 30,
			Throws = true,
			Color = Color3.fromRGB(255, 210, 90),
		},
		{
			Rarity = "Godly",
			Title = "The Manor Steps",
			Guards = 4,
			GuardSpeed = 47,
			SpeedNeeded = 3000000,
			Detect = 40,
			Health = 2200,
			Damage = 45,
			Reward = 400,
			Respawn = 45,
			Throws = true,
			Color = Color3.fromRGB(255, 110, 130),
		},
	},
	GuardPatrolSpeed = 7,

	-- Rounds
	IntermissionTime = 180,
	RoundTime = 150,
	ResultsTime = 8,
	MurdererGrace = 10, -- seconds before the Murderer gets their knife (same as the classic)
	MinPlayers = 2,
	AttackRange = 7,
	StabLagSlack = 4, -- extra reach when the Murderer's screen showed the target in range (lag)
	MurdererThrowCooldown = 0, -- hold-click throw, every Murderer has it (the knife perk is extra); the wind-up is the only limit
	AttackCooldown = 0.9,

	-- Round rewards scale with what your vault earns (Seconds of your income per second), never
	-- below Min, so a round is worth playing at every stage (GameConfig.Pay)
	RoundPay = {
		Coin = { Min = 5, Seconds = 2 },
		Survive = { Min = 100, Seconds = 45 },
		LastAlive = { Min = 150, Seconds = 45 }, -- extra for survivors when only a few made it
		Kill = { Min = 40, Seconds = 15 },
		Hero = { Min = 250, Seconds = 90 },
		TeamWin = { Min = 40, Seconds = 20 }, -- innocents who died, but their side won
		Wipe = { Min = 200, Seconds = 30 }, -- the Murderer got everyone...
		WipePerVictim = { Min = 75, Seconds = 15 }, -- ...plus this for every real player they got
	},
	BotRoundPay = 0.5, -- rounds with fewer than two real players pay this fraction (no bot farming)
	BotKillPay = 0.5, -- a bot kill pays this fraction of a player kill
	LastAliveFraction = 0.3,
	-- A full wipe also hands the Murderer a sealed case: better in bigger lobbies (real players only)
	WipeCase = { Small = "Rare", Big = "Epic", BigLobby = 6 },

	-- Live servers: bots top every round up to this many people, so a round can start as soon as one
	-- real player is around. With one real player, a bot is sometimes the Murderer.
	BotFill = { Size = 5, MinHumans = 1 },

	-- Murderer loot: every kill takes one random knife off the victim's rack. The Murderer keeps
	-- the loot unless an innocent shoots them with the Revolver, which sends it all back.
	LootPerKill = 1,

	-- The Revolver drops somewhere in the building partway through the round. Any innocent can
	-- grab it; shooting an innocent by mistake costs the shooter their life too.
	RevolverTime = 35,
	RevolverCooldown = 2.5,
	RevolverRange = 250,

	-- Surviving a round doubles your rack income for a while, so rounds fuel stealing
	BoostDuration = 90,
	BoostMultiplier = 2,

	-- Coins scattered over the round map; innocents grab them while hiding
	RoundCoins = 24,
	CoinRespawn = 12,

	-- Guards shout "!" and hesitate this long before they start chasing
	GuardAlertTime = 0.7,
	GuardAttackCooldown = 1.1, -- seconds between a guard's melee hits
	GuardAttackRange = 5,
	-- Picking up a knife alerts every guard in that zone and the zone in front of it (your way home)
	AlertZonesBehind = 1,

	-- Hub combat: everyone carries their equipped knife (or the free Rusty Shank)
	StarterKnife = "RustyShank",
	SwingCooldown = 0.45,
	SwingRange = 7.5,
	-- Hold to crank back; a full charge (AnimLibrary.ChargeTime) flies faster and hits this much harder
	-- No cooldown: throw as fast as you can hold-and-release.
	HubThrow = { Cooldown = 0, Range = 400, DamageMultiplier = 1.6 }, -- flies until it hits something
	DroppedKnifeLifetime = 30, -- a knife on the floor (from a dead guard or a dead carrier)
	-- Guards in zones with Throws = true stop, wind up (knife glows red) and throw a knife in a
	-- straight line at where you were. Never homing, so sidestepping dodges it.
	GuardThrow = { Windup = 0.6, Cooldown = 3.5, MinRange = 10, MaxRange = 45, Speed = 60, HitRadius = 2.5 },

	-- Selling a knife from the rack pays this many seconds of its income
	SellSeconds = 40,

	-- Innocent Powers: bought for good with cash (your knives' income), upgraded to level 3, and
	-- equipped in a loadout. They work in the hub against guards (on a cooldown) and in rounds
	-- against the Murderer (a few uses per round; the Murderer can't use them). Per-level values
	-- are indexed by power level 1..3.
	PowerSlots = 2,
	MaxPowerSlots = 3,
	PowerSlotCost = 6000,
	Powers = {
		{
			Id = "Vanish",
			DisplayName = "Vanish",
			Description = "Turn invisible. Guards and the Murderer lose you.",
			Cost = 400,
			Color = Color3.fromRGB(150, 120, 255),
			Duration = { 4, 5, 6 },
			Energy = { 3, 3, 2 }, -- round cost per level (coins refill Energy)
			Cooldown = 20,
		},
		{
			Id = "Radar",
			DisplayName = "Radar",
			Description = "See through walls: the Murderer in rounds, every guard and its knife in the arena.",
			Cost = 300,
			Color = Color3.fromRGB(80, 220, 160),
			Duration = { 3, 4, 5 },
			Energy = { 2, 2, 1 }, -- round cost per level (coins refill Energy)
			Cooldown = 12,
		},
		{
			Id = "Trap",
			DisplayName = "Bear Trap",
			Description = "Drop a trap. The next guard or Murderer to step in is stuck.",
			Cost = 600,
			Color = Color3.fromRGB(170, 170, 180),
			Duration = { 2, 2.5, 3 }, -- how long it holds them
			Energy = { 2, 2, 1 }, -- round cost per level (coins refill Energy)
			Cooldown = 15,
		},
		{
			Id = "Shield",
			DisplayName = "Shield",
			Description = "Blocks the next stab that would hit you.",
			Cost = 700,
			Color = Color3.fromRGB(90, 180, 255),
			Duration = { 8, 10, 12 }, -- how long the bubble lasts in the arena
			Energy = { 4, 3, 3 }, -- round cost per level (coins refill Energy)
			Cooldown = 30,
		},
		{
			Id = "Decoy",
			DisplayName = "Decoy",
			Description = "A fake you runs off. Whoever was chasing you follows it instead.",
			Cost = 900,
			Color = Color3.fromRGB(255, 190, 90),
			Duration = { 5, 6, 8 },
			Energy = { 3, 2, 2 }, -- round cost per level (coins refill Energy)
			Cooldown = 18,
		},
		{
			Id = "Flash",
			DisplayName = "Flash",
			Description = "A blinding camera flash. Whoever's in front of you can't see or move for a moment.",
			Cost = 800,
			Color = Color3.fromRGB(255, 250, 200),
			Duration = { 1.6, 2.1, 2.7 }, -- how long they're blinded
			Energy = { 3, 3, 2 },
			Cooldown = 16,
		},
		{
			Id = "Barricade",
			DisplayName = "Barricade",
			Description = "Slam down a wooden barricade. Blocks the Murderer, guards and raiders until it's smashed.",
			Cost = 1100,
			Color = Color3.fromRGB(200, 140, 80),
			Duration = { 10, 13, 16 }, -- how long it stands (if nobody smashes it)
			Energy = { 2, 2, 2 },
			Hits = { 2, 3, 4 }, -- stabs it takes to smash
			Cooldown = 18,
		},
		{
			Id = "Mimic",
			DisplayName = "Mimic",
			Description = "Become furniture! Stay still and nobody knows it's you.",
			Cost = 1500,
			Color = Color3.fromRGB(255, 120, 180),
			Duration = { 8, 12, 16 },
			Energy = { 3, 3, 2 }, -- round cost per level (coins refill Energy)
			Cooldown = 25,
		},
	},
	PowerMaxLevel = 3,

	-- The Murderer's thrown knife (everyone's, whatever the perk)
	MurderThrow = { Range = 400, Speed = 110 }, -- flies until it hits something

	-- Knife perks (The Mad Murderer's classics): the Murderer's equipped knife gives them one.
	-- Active perks go on Q / the ability button; passive ones just work.
	Perks = {
		Fury = {
			DisplayName = "Fury",
			Description = "Every kill makes your throws faster",
			Passive = true,
			PerKill = 0.2, -- +20% throw speed per kill
		},
		Identifier = {
			DisplayName = "Identifier",
			Description = "Reveal who's holding the Revolver (3 per round)",
			Uses = 3,
			Cooldown = 5,
			Duration = 4,
		},
		Bulletproof = {
			DisplayName = "Bulletproof",
			Description = "Survive one Revolver shot",
			Passive = true,
		},
		ShapeShifter = {
			DisplayName = "Shape Shifter",
			Description = "Turn into someone else (once per round)",
			Uses = 1,
			Cooldown = 3,
		},
		SpamKnife = {
			DisplayName = "Spam Knife",
			Description = "3 seconds of rapid-fire knife throws",
			Cooldown = 18,
			Duration = 3,
			Interval = 0.12,
		},
		GhostKnife = {
			DisplayName = "Ghost Knife",
			Description = "Thrown knives fly through up to 5 people",
			Passive = true,
			Pierce = 5,
		},
		Invisiknife = {
			DisplayName = "Invisiknife",
			Description = "Turn invisible for a few seconds after every kill",
			Passive = true,
			Duration = 4,
		},
		LaserKnife = {
			DisplayName = "Laser Knife",
			Description = "Fully charged throws fly lightning fast",
			Passive = true,
			Speed = 480,
		},
		ExplodingKnife = {
			DisplayName = "Exploding Knife",
			Description = "Throw kills explode, taking out anyone close by",
			Passive = true,
			Radius = 9,
		},
		Hellfire = {
			DisplayName = "Hellfire",
			Description = "A volley of flaming knives that explode on every kill",
			Cooldown = 22,
			Duration = 2.5,
			Interval = 0.15,
			Radius = 7,
		},
	} :: { [string]: any },

	-- Anti-cheat
	SpeedTolerance = 1.6, -- carriers moving faster than walkspeed * this drop their knife
}

-- A RoundPay entry for someone earning `income` per second
function GameConfig.Pay(entry: { Min: number, Seconds: number }, income: number): number
	return math.max(entry.Min, math.floor(income * entry.Seconds))
end

function GameConfig.TicketPrice(income: number): number
	return math.max(GameConfig.TicketCost, math.floor(income * GameConfig.TicketIncomeSeconds))
end

function GameConfig.RebirthCost(rebirths: number): number
	return math.floor(GameConfig.Rebirth.BaseCost * GameConfig.Rebirth.CostGrowth ^ rebirths)
end

function GameConfig.RebirthTitle(rebirths: number): string?
	if rebirths <= 0 then
		return nil
	end
	local titles = GameConfig.Rebirth.Titles
	return titles[math.min(rebirths, #titles)]
end

function GameConfig.SlotCost(slots: number): number
	return math.floor(150 * 2 ^ (slots - GameConfig.StartingSlots))
end

-- Unlock costs the power's Cost; each upgrade after that doubles
function GameConfig.PowerCost(cost: number, currentLevel: number): number
	return cost * 2 ^ currentLevel
end

-- Trained Speed -> walk speed: 16 at 0, ~23 at 1K, ~34 at 15K, ~45 at 200K, ~57 at 3M
function GameConfig.WalkSpeedFor(speed: number): number
	local walk = GameConfig.BaseWalkSpeed + 3 * math.log(1 + math.max(speed, 0) / 250, 2)
	return math.min(walk, GameConfig.MaxWalkSpeed)
end

return GameConfig
