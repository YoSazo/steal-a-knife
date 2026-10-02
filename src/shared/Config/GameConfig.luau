--!strict
-- Every tunable number in one place. Shared so the client can show prices; the server is the
-- only one that ever acts on them.

-- One day of the login streak: "Cash" (Seconds of income, at least Min), "Case" (Rarity) or
-- "Tickets" (Amount)
export type DailyReward = { Kind: string, Seconds: number?, Min: number?, Rarity: string?, Amount: number? }

local DAILY: { DailyReward } = {
	{ Kind = "Cash", Seconds = 120, Min = 20000 },
	{ Kind = "Case", Rarity = "Common" },
	{ Kind = "Cash", Seconds = 300, Min = 45000 },
	{ Kind = "Tickets", Amount = 2 },
	{ Kind = "Cash", Seconds = 600, Min = 110000 },
	{ Kind = "Case", Rarity = "Rare" },
	{ Kind = "Case", Rarity = "Epic" },
}

local GameConfig = {
	-- Economy / progression
	StartingCash = 0,
	-- Vaults grow a floor at a time (Tsunami style): 10 plates per floor, up to 4 floors
	SlotsPerFloor = 10,
	StartingSlots = 10,
	MaxSlots = 40,
	FloorCosts = { 1.5e6, 2e10, 1e14 }, -- the 2nd, 3rd and 4th floor
	TicketCost = 30000, -- the floor; tickets cost TicketIncomeSeconds of your income (TicketPrice)
	TicketIncomeSeconds = 60,

	-- Reasons to come back: the vault keeps earning while you're away (a fraction, capped), and a
	-- 7-day login streak (miss a day and it starts over). Cash days pay seconds of your income.
	Offline = { Fraction = 0.5, MaxHours = 8, MinAway = 120 },
	Daily = DAILY,
	-- New players can't lose knives (vault break-ins, burglars, Murderer loot) until they've played
	-- this long, so nobody gets robbed in their first few minutes
	NewPlayerShield = 300,
	MaxTickets = 5,
	TicketWeight = 3, -- one ticket spent in a round = this much extra Murderer weight

	-- Movement. Speed is a big number trained by running in your vault's Haunted Wheel; it turns
	-- into running speed on a curve (WalkSpeedFor). Each zone needs a certain Speed: there's no
	-- barrier, but below it that zone's guards will run you down on the way home.
	BaseWalkSpeed = 16,
	MaxWalkSpeed = 135,
	CarrySpeedMultiplier = 0.9,
	-- Haunted Wheel tiers (the code calls it the treadmill): Rate = Speed per second while running
	-- in it; Cost to buy that tier
	Treadmills = {
		{ Name = "Creaky Wheel", Rate = 10, Cost = 0 },
		{ Name = "Iron Wheel", Rate = 30, Cost = 15000 },
		{ Name = "Steam Wheel", Rate = 80, Cost = 100000 },
		{ Name = "Haunted Wheel", Rate = 250, Cost = 600000 },
		{ Name = "Cursed Wheel", Rate = 800, Cost = 4e6 },
		{ Name = "Bone Wheel", Rate = 2500, Cost = 30e6 },
		{ Name = "Thief Moon Wheel", Rate = 8000, Cost = 250e6 },
		{ Name = "Phantom Wheel", Rate = 25000, Cost = 2e9 },
		{ Name = "Infernal Wheel", Rate = 80000, Cost = 15e9 },
		{ Name = "Olympian Wheel", Rate = 250000, Cost = 120e9 },
		{ Name = "Angelic Wheel", Rate = 800000, Cost = 1e12 },
		{ Name = "Celestial Wheel", Rate = 2.5e6, Cost = 8e12 },
		{ Name = "Cosmic Wheel", Rate = 8e6, Cost = 70e12 },
	},
	-- Knife Trails (Steal An Egg style): bought with cash, each one multiplies the Speed your wheel
	-- trains and sends a stream of that knife spinning off behind you when you run
	Trails = {
		{
			Name = "Rusty Trail",
			Knife = "RustyShank",
			Multiplier = 1.5,
			Cost = 20000,
			Color = Color3.fromRGB(190, 150, 120),
		},
		{
			Name = "Kitchen Trail",
			Knife = "KitchenKnife",
			Multiplier = 2,
			Cost = 250000,
			Color = Color3.fromRGB(200, 225, 255),
		},
		{
			Name = "Hunter Trail",
			Knife = "HunterBlade",
			Multiplier = 3,
			Cost = 3e6,
			Color = Color3.fromRGB(110, 230, 140),
		},
		{
			Name = "Thorn Trail",
			Knife = "ThornDagger",
			Multiplier = 4,
			Cost = 40e6,
			Color = Color3.fromRGB(120, 220, 110),
		},
		{
			Name = "Cleaver Trail",
			Knife = "Cleaver",
			Multiplier = 6,
			Cost = 500e6,
			Color = Color3.fromRGB(190, 110, 255),
		},
		{
			Name = "Golden Trail",
			Knife = "GoldenDagger",
			Multiplier = 8,
			Cost = 7e9,
			Color = Color3.fromRGB(255, 205, 60),
		},
		{
			Name = "Inferno Trail",
			Knife = "InfernoFang",
			Multiplier = 12,
			Cost = 100e9,
			Color = Color3.fromRGB(255, 110, 30),
		},
		{
			Name = "Olympus Trail",
			Knife = "ZeusBolt",
			Multiplier = 16,
			Cost = 1.5e12,
			Color = Color3.fromRGB(255, 240, 90),
		},
		{
			Name = "Halo Trail",
			Knife = "HaloBlade",
			Multiplier = 22,
			Cost = 25e12,
			Color = Color3.fromRGB(255, 250, 220),
		},
		{
			Name = "Galaxy Trail",
			Knife = "GalaxyKatana",
			Multiplier = 30,
			Cost = 400e12,
			Color = Color3.fromRGB(255, 90, 230),
		},
	},
	-- The Robux trail (Monetization pass "PhantomTrail"): void knives and a x10 multiplier
	PhantomTrail = { Name = "Phantom Trail", Knife = "VoidEdge", Multiplier = 10, Color = Color3.fromRGB(170, 70, 255) },

	-- Vault walls: the better your walls, the taller and scarier your vault (everyone walks past
	-- them on the plaza) and the longer its gate holds out in a raid. Raiders chip the gate with
	-- knife hits and throws; it can always be broken, it just takes better knives or more friends.
	Walls = {
		{
			Name = "Starter Lasers",
			Height = 16,
			GateHealth = 400,
			Cost = 0,
			Color = Color3.fromRGB(60, 64, 110),
			Material = Enum.Material.WoodPlanks,
			Trim = Color3.fromRGB(255, 170, 70),
		},
		{
			Name = "Twin Lasers",
			Height = 21,
			GateHealth = 1500,
			Cost = 150000,
			Color = Color3.fromRGB(60, 70, 120),
			Material = Enum.Material.Cobblestone,
			Trim = Color3.fromRGB(120, 200, 255),
		},
		{
			Name = "Iron Grid",
			Height = 26,
			GateHealth = 5000,
			Cost = 2e6,
			Color = Color3.fromRGB(70, 74, 96),
			Material = Enum.Material.DiamondPlate,
			Trim = Color3.fromRGB(220, 230, 240),
		},
		{
			Name = "Red Alert",
			Height = 31,
			GateHealth = 15000,
			Cost = 25e6,
			Color = Color3.fromRGB(80, 40, 70),
			Material = Enum.Material.Limestone,
			Trim = Color3.fromRGB(255, 70, 80),
		},
		{
			Name = "Plasma Wall",
			Height = 36,
			GateHealth = 40000,
			Cost = 400e6,
			Color = Color3.fromRGB(60, 30, 100),
			Material = Enum.Material.Basalt,
			Trim = Color3.fromRGB(190, 90, 255),
		},
		{
			Name = "Void Field",
			Height = 41,
			GateHealth = 100000,
			Cost = 6e9,
			Color = Color3.fromRGB(20, 30, 60),
			Material = Enum.Material.Glass,
			Trim = Color3.fromRGB(90, 255, 240),
		},
		{
			Name = "Golden Gate",
			Height = 46,
			GateHealth = 250000,
			Cost = 100e9,
			Color = Color3.fromRGB(90, 80, 60),
			Material = Enum.Material.Marble,
			Trim = Color3.fromRGB(255, 215, 90),
		},
		{
			Name = "Star Shield",
			Height = 52,
			GateHealth = 600000,
			Cost = 1.5e12,
			Color = Color3.fromRGB(40, 26, 90),
			Material = Enum.Material.Glass,
			Trim = Color3.fromRGB(255, 120, 240),
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
		RaiderMarkTime = 90, -- hit a gate: its owner can hunt you down (real damage) for this long
		ThrowGateMultiplier = 1.25, -- thrown knives hit gates a bit harder than swings
		Burglars = 5, -- per Thief Moon, arriving in waves through the first half of it
		BurglarHealth = 160,
		BurglarSpeed = 20, -- a bit quicker than a fresh player; catchable once you've trained
		BurglarCarrySpeed = 16,
		BurglarSwing = 1.2, -- seconds between crowbar hits on a gate
		BurglarStealsPerVault = 1, -- knives burglars can take from one vault per Thief Moon
		BurglarsPerGate = 2, -- at most this many at one gate; the rest go for other vaults
		BurglarReward = { Min = 4500, Seconds = 20 }, -- bounty for stopping one (GameConfig.Pay)
		BurglarGateDamage = 15, -- per bash, flat: strong walls really do keep them out

		-- Break-ins happen any time outside a round. Players' knives do this fraction of their
		-- damage to gates (a starter knife needs ~15s on a Tier 1 gate; walls scale it up).
		PlayerGateDamage = 0.5,
		RobbedSeal = 180, -- after a knife is stolen, that vault can't be broken into for this long
		CatchBounty = { Min = 7500, Seconds = 60 }, -- of the knife's income, for catching your thief
		IntruderBounty = { Min = 3750, Seconds = 10 }, -- of your income, for knocking out an intruder
		-- Every few intermissions the Thief Moon rises: burglars come, gates take more damage,
		-- bounties double and anyone outside their own vault can be knocked down
		Every = 3,
		BloodMoonGateDamage = 1.5,
		BloodMoonBounty = 2,
	},

	-- Rebirth: start over (cash, knives, slots, Speed, wheel, walls) for a permanent multiplier on
	-- income and Speed training, a title, and better luck in cases
	Rebirth = {
		BaseCost = 2e9,
		CostGrowth = 6,
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

	TutorialReward = 10000,

	-- The Case Shop: sealed cases for cash, opened on the spot (same odds as watchmen's cases)
	CaseShop = {
		{ Rarity = "Common", Cost = 20000 },
		{ Rarity = "Rare", Cost = 300000 },
		{ Rarity = "Epic", Cost = 4e6 },
		{ Rarity = "Legendary", Cost = 60e6 },
		{ Rarity = "Mythic", Cost = 900e6 },
		{ Rarity = "Godly", Cost = 14e9 },
		{ Rarity = "Celestial", Cost = 220e9 },
		{ Rarity = "Cosmic", Cost = 3.5e12 },
	},

	-- A free chest on the plaza every so often: cash (scaled to what you earn) or a case
	FreeChest = { Cooldown = 600, MinCash = 10000, IncomeSeconds = 90, CaseChance = 0.4 },

	-- The Index pays out once for every knife you've ever owned
	IndexRewards = {
		Common = { Cash = 10000, Speed = 500 },
		Rare = { Cash = 130000, Speed = 3000 },
		Epic = { Cash = 1.7e6, Speed = 50000 },
		Legendary = { Cash = 25e6, Speed = 2e6 },
		Mythic = { Cash = 360e6, Speed = 20e6 },
		Godly = { Cash = 5.6e9, Speed = 150e6 },
		Celestial = { Cash = 100e9, Speed = 1e9 },
		Cosmic = { Cash = 1.7e12, Speed = 8e9 },
	},

	-- Health: bought with cash at the Knife Merchant (and boosted with Robux). Every level is more
	-- max health, so guards, raiders' defenders and the Murderer's helpers need more hits on you.
	Health = { Base = 100, PerLevel = 25, MaxLevel = 20, BaseCost = 25000, CostGrowth = 2.6 },

	-- Rounds: innocents power their abilities with coins. Each power costs Energy; you start every
	-- round with a little and every coin you grab adds more.
	StartEnergy = 1,
	MaxEnergy = 6,
	EnergyPerCoin = 1,

	RoundWalkSpeed = 16, -- upgrades don't carry into rounds so new players can still win
	MurdererWalkSpeed = 18.5,

	-- The hub is one long straight runway (like the big steal games): the vaults open onto a plaza
	-- at the start, and the zones run one after another down the runway, each rarer and nastier,
	-- all the way to the Manor. Each guard holds a knife from its zone's pool; kill it for the knife.
	ZoneDepth = 220,
	ArenaWidth = 160,
	CatchRadius = 4.5,
	-- Each zone has one boss: a round character standing in front of a wall of knives. They leave you
	-- alone until you steal one; then they (or, if they're already busy, a shadow of them) chase you
	-- at GuardSpeed all the way to the plaza. Caught = they take the knife back (and Damage hurts).
	-- SpeedNeeded is the Speed at which someone carrying a knife just outruns that zone's boss.
	-- Health decides how long a hit staggers the chaser (better knives stagger longer).
	Zones = {
		{
			Rarity = "Common",
			Boss = "Frank", -- a round character (Disguises) guarding this biome's knife wall
			BossTitle = "The Groundskeeper",
			BossWear = {}, -- Blender pieces worn on top of their usual outfit
			Restock = 25, -- seconds before a stolen slot on the wall refills
			Title = "The Courtyard",
			GuardSpeed = 12.5,
			SpeedNeeded = 0,
			Health = 75,
			Damage = 5.5,
			Color = Color3.fromRGB(130, 220, 120),
		},
		{
			Rarity = "Rare",
			Boss = "Ivy", -- a round character (Disguises) guarding this biome's knife wall
			BossTitle = "The Gardener",
			BossWear = { "FlowerCrown" }, -- Blender pieces worn on top of their usual outfit
			Restock = 30, -- seconds before a stolen slot on the wall refills
			Title = "The Gardens",
			GuardSpeed = 26,
			SpeedNeeded = 4000,
			Health = 200,
			Damage = 12.5,
			Color = Color3.fromRGB(110, 190, 255),
		},
		{
			Rarity = "Epic",
			Boss = "Sam", -- a round character (Disguises) guarding this biome's knife wall
			BossTitle = "The Gravedigger",
			BossWear = {}, -- Blender pieces worn on top of their usual outfit
			Restock = 40, -- seconds before a stolen slot on the wall refills
			Title = "The Crypts",
			GuardSpeed = 47,
			SpeedNeeded = 180000,
			Health = 450,
			Damage = 17.5,
			Throws = true,
			Color = Color3.fromRGB(190, 140, 255),
		},
		{
			Rarity = "Legendary",
			Boss = "Leo", -- a round character (Disguises) guarding this biome's knife wall
			BossTitle = "The Collector",
			BossWear = { "Monocle" }, -- Blender pieces worn on top of their usual outfit
			Restock = 50, -- seconds before a stolen slot on the wall refills
			Title = "The Catacombs",
			GuardSpeed = 70,
			SpeedNeeded = 10e6,
			Health = 1000,
			Damage = 24,
			Throws = true,
			Color = Color3.fromRGB(255, 210, 90),
		},
		{
			Rarity = "Mythic",
			Boss = "Ruby", -- a round character (Disguises) guarding this biome's knife wall
			BossTitle = "The Firestarter",
			BossWear = { "DevilHorns" }, -- Blender pieces worn on top of their usual outfit
			Restock = 60, -- seconds before a stolen slot on the wall refills
			Title = "The Inferno",
			GuardSpeed = 82,
			SpeedNeeded = 80e6,
			Health = 2000,
			Damage = 29,
			Throws = true,
			Color = Color3.fromRGB(255, 90, 40),
		},
		{
			Rarity = "Godly",
			Boss = "Kate", -- a round character (Disguises) guarding this biome's knife wall
			BossTitle = "The Queen",
			BossWear = { "Crown" }, -- Blender pieces worn on top of their usual outfit
			Restock = 70, -- seconds before a stolen slot on the wall refills
			Title = "Mount Olympus",
			GuardSpeed = 94,
			SpeedNeeded = 650e6,
			Health = 3800,
			Damage = 33,
			Throws = true,
			Color = Color3.fromRGB(255, 120, 200),
		},
		{
			Rarity = "Celestial",
			Boss = "Zoe", -- a round character (Disguises) guarding this biome's knife wall
			BossTitle = "The Angel",
			BossWear = { "Halo", "AngelWings" }, -- Blender pieces worn on top of their usual outfit
			Restock = 80, -- seconds before a stolen slot on the wall refills
			Title = "The Heavens",
			GuardSpeed = 104,
			SpeedNeeded = 4e9,
			Health = 6500,
			Damage = 37,
			Throws = true,
			Color = Color3.fromRGB(150, 240, 255),
		},
		{
			Rarity = "Cosmic",
			Boss = "Nick", -- a round character (Disguises) guarding this biome's knife wall
			BossTitle = "The Void Walker",
			BossWear = { "SpaceHelmet" }, -- Blender pieces worn on top of their usual outfit
			Restock = 90, -- seconds before a stolen slot on the wall refills
			Title = "Outer Space",
			GuardSpeed = 114,
			SpeedNeeded = 31e9,
			Health = 11000,
			Damage = 41,
			Throws = true,
			Color = Color3.fromRGB(140, 90, 255),
		},
	},
	GuardPatrolSpeed = 7,
	BossWallSlots = 5, -- knives on each boss's wall
	-- Lairs stand against the runway's side walls (odd zones left, even zones right) so the run down
	-- the middle stays clear: centre (fraction into its zone), Width along the wall, Depth out from it
	BossLair = { At = 0.6, Width = 42, Depth = 14 },

	-- Rounds
	IntermissionTime = 180,
	NewcomerRoundIn = 100, -- a first-time player joining pulls the next round in to at most this (s)
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
		Coin = { Min = 300, Seconds = 2 },
		Survive = { Min = 7500, Seconds = 45 },
		LastAlive = { Min = 11000, Seconds = 45 }, -- extra for survivors when only a few made it
		Kill = { Min = 3000, Seconds = 15 },
		Hero = { Min = 19000, Seconds = 90 },
		TeamWin = { Min = 3000, Seconds = 20 }, -- innocents who died, but their side won
		Wipe = { Min = 15000, Seconds = 30 }, -- the Murderer got everyone...
		WipePerVictim = { Min = 5600, Seconds = 15 }, -- ...plus this for every real player they got
	},
	BotRoundPay = 0.5, -- rounds with fewer than two real players pay this fraction (no bot farming)
	BotKillPay = 0.5, -- a bot kill pays this fraction of a player kill
	LastAliveFraction = 0.3,
	-- A full wipe also hands the Murderer a sealed case: better in bigger lobbies (real players only)
	WipeCase = { Small = "Rare", Big = "Epic", BigLobby = 6 },

	-- Live servers: bots top every round up to this many people, so a round can start as soon as one
	-- real player is around. With one real player, a bot is sometimes the Murderer.
	BotFill = { Size = 8, MinHumans = 1 }, -- quiet servers still get a busy round (16-player servers fill up with people)

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
	-- Hitting a guard or picking up its case alerts every guard in that zone and the zone in front
	-- of it (your way home); they chase you all the way to the plaza (the safe point)
	AlertZonesBehind = 1,

	-- Hub combat: everyone carries their equipped knife (or the free Rusty Shank)
	StarterKnife = "RustyShank",
	SwingCooldown = 0.45,
	SwingRange = 7.5,
	-- Hold to crank back; a full charge (AnimLibrary.ChargeTime) flies faster and hits this much harder
	-- No cooldown: throw as fast as you can hold-and-release.
	HubThrow = { Cooldown = 0, Range = 400, DamageMultiplier = 1.6 }, -- flies until it hits something
	-- Server-side floor between any two throws (hub or Murderer). Hold-to-throw already keeps real
	-- players slower than this; it stops exploit scripts firing hundreds a second.
	ThrowMinInterval = 0.3,
	DroppedKnifeLifetime = 30, -- a knife on the floor (from a dead guard or a dead carrier)
	-- Guards in zones with Throws = true stop, wind up (knife glows red) and throw a knife in a
	-- straight line at where you were. Never homing, so sidestepping dodges it.
	-- Boss knife throws lead the thief (Lead = how much of their run they predict) and curve gently
	-- after them in flight (TurnRate, radians/s): a sharp sidestep dodges, running straight doesn't
	GuardThrow = {
		Windup = 0.6,
		Cooldown = 2.8,
		MinRange = 10,
		MaxRange = 80,
		FlightRange = 140,
		Speed = 75,
		HitRadius = 2.5,
		Lead = 0.85,
		TurnRate = math.rad(55),
	},

	-- Selling a knife from the rack pays this many seconds of its income
	SellSeconds = 40,

	-- Innocent Powers: bought for good with cash (your knives' income), upgraded to level 3, and
	-- equipped in a loadout. They work in the hub against guards (on a cooldown) and in rounds
	-- against the Murderer (a few uses per round; the Murderer can't use them). Per-level values
	-- are indexed by power level 1..3.
	PowerSlots = 2,
	MaxPowerSlots = 3,
	PowerSlotCost = 450000,
	Powers = {
		{
			Id = "Vanish",
			DisplayName = "Vanish",
			Description = "Turn invisible. A boss chasing you loses sight of you, and so does the Murderer.",
			Cost = 30000,
			Color = Color3.fromRGB(150, 120, 255),
			Duration = { 4, 5, 6 }, -- in the arena; rounds use RoundDuration
			RoundDuration = { 2, 2.5, 3 }, -- short in rounds, and the Murderer still sees a shimmer
			Energy = { 5, 5, 4 }, -- round cost per level (coins refill Energy)
			RoundUses = 1, -- once per round
			Cooldown = 20,
		},
		{
			Id = "Radar",
			DisplayName = "Radar",
			Description = "See through walls: the Murderer in rounds, every guard and its knife in the arena.",
			Cost = 22000,
			Color = Color3.fromRGB(80, 220, 160),
			Duration = { 3, 4, 5 },
			Energy = { 2, 2, 1 }, -- round cost per level (coins refill Energy)
			Cooldown = 12,
		},
		{
			Id = "Trap",
			DisplayName = "Bear Trap",
			Description = "Drop a trap. The next guard or Murderer to step in is stuck.",
			Cost = 45000,
			Color = Color3.fromRGB(170, 170, 180),
			Duration = { 2, 2.5, 3 }, -- how long it holds them
			Energy = { 2, 2, 1 }, -- round cost per level (coins refill Energy)
			Cooldown = 15,
		},
		{
			Id = "Shield",
			DisplayName = "Shield",
			Description = "Blocks the next stab that would hit you.",
			Cost = 52000,
			Color = Color3.fromRGB(90, 180, 255),
			Duration = { 8, 10, 12 }, -- how long the bubble lasts in the arena
			RoundDuration = { 6, 6, 6 },
			Energy = { 4, 3, 3 }, -- round cost per level (coins refill Energy)
			RoundUses = 1, -- once per round
			Cooldown = 30,
		},
		{
			Id = "Decoy",
			DisplayName = "Decoy",
			Description = "A fake you runs off. Whoever was chasing you follows it instead.",
			Cost = 68000,
			Color = Color3.fromRGB(255, 190, 90),
			Duration = { 5, 6, 8 },
			Energy = { 3, 2, 2 }, -- round cost per level (coins refill Energy)
			Cooldown = 18,
		},
		{
			Id = "Flash",
			DisplayName = "Flash",
			Description = "A blinding camera flash. Whoever's in front of you can't see or move for a moment.",
			Cost = 60000,
			Color = Color3.fromRGB(255, 250, 200),
			Duration = { 1.6, 2.1, 2.7 }, -- how long they're blinded
			Energy = { 3, 3, 2 },
			Cooldown = 16,
		},
		{
			Id = "Barricade",
			DisplayName = "Barricade",
			Description = "Slam down a wooden barricade. Blocks the Murderer, bosses and raiders until it's smashed.",
			Cost = 82000,
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
			Cost = 110000,
			Color = Color3.fromRGB(255, 120, 180),
			Duration = { 8, 12, 16 },
			Energy = { 3, 3, 2 }, -- round cost per level (coins refill Energy)
			Cooldown = 25,
		},
	} :: { any },
	PowerMaxLevel = 3,
	-- The fuel between the two games (server Fuel): Heat and the Murderer meter
	Fuel = {
		MaxHeat = 10,
		HeatIncome = 0.2, -- +20% vault income per Heat (10 Heat = 3x)
		HeatLuck = 0.5, -- +50% power-roll luck per Heat (10 Heat = 6x)
		RarityLuck = 0.15, -- deeper-zone knives roll powers more often (+15% per rarity step)
		PityPer = 50, -- bad-luck protection: every 50 knives without a power = +1x luck
		RevengeLuck = 3, -- after a Sheriff steals your power: 3x luck...
		RevengeTime = 1800, -- ...for 30 minutes
		MeterPerRound = 2, -- Murderer meter for each round you weren't the Murderer
		MeterCap = 3, -- nobody's chance can be more than 3x the server average
	},

	-- Rounds stay fair (MM2 style): an innocent brings ONE power - the first in their loadout - and
	-- it works at level 1 for everyone. Levels only matter in the hub, against bosses.
	RoundPowerLevel = 1,
	-- Every so often a CLASSIC round: no powers, no knife perks, just a knife and a Revolver - and
	-- everyone earns extra for it
	-- DOUBLE TROUBLE: two Murderers, two Sheriffs (always with this many players, else a chance)
	DoubleTrouble = { Always = 10, Chance = 0.2 },
	ClassicChance = 0.2,
	ClassicPay = 1.5,

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
			Description = "Q: for a few seconds every click throws a knife where you aim",
			Cooldown = 18,
			Duration = 3,
			Interval = 0.15, -- server floor between two spam throws
			Range = 400,
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
			Description = "Q: for a few seconds every click throws a flaming knife that explodes on a kill",
			Cooldown = 22,
			Duration = 4,
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

-- Where zone `index`'s boss lair stands (on the floor, against its side wall)
function GameConfig.BossLairCenter(index: number): Vector3
	local lair = GameConfig.BossLair
	local side = if index % 2 == 1 then -1 else 1
	return Vector3.new(
		side * (GameConfig.ArenaWidth / 2 - lair.Depth / 2),
		0,
		(index - 1) * GameConfig.ZoneDepth + GameConfig.ZoneDepth * lair.At
	)
end

-- What the next floor costs for someone who has `slots` plates now
function GameConfig.SlotCost(slots: number): number
	local floors = math.max(1, math.ceil(slots / GameConfig.SlotsPerFloor))
	return GameConfig.FloorCosts[floors] or math.huge
end

function GameConfig.FloorsFor(slots: number): number
	return math.clamp(math.ceil(slots / GameConfig.SlotsPerFloor), 1, GameConfig.MaxSlots // GameConfig.SlotsPerFloor)
end

-- Max health at a Health level, and the price of the next level
function GameConfig.MaxHealthFor(level: number, multiplier: number?): number
	local h = GameConfig.Health
	return math.floor((h.Base + h.PerLevel * level) * (multiplier or 1))
end

function GameConfig.HealthCost(level: number): number
	local h = GameConfig.Health
	return math.floor(h.BaseCost * h.CostGrowth ^ level)
end

-- Unlock costs the power's Cost; each upgrade after that doubles
function GameConfig.PowerCost(cost: number, currentLevel: number): number
	return cost * 2 ^ currentLevel
end

-- Speed stat -> walk speed. Every doubling of Speed is worth +4.4 walk speed (16 at 0, ~30 at 4K,
-- ~54 at 180K, ~79 at 10M, ~105 at 650M, ~128 at 31B), up to MaxWalkSpeed.
function GameConfig.WalkSpeedFor(speed: number): number
	local walk = GameConfig.BaseWalkSpeed + 4.4 * math.log(1 + math.max(speed, 0) / 500, 2)
	return math.min(walk, GameConfig.MaxWalkSpeed)
end

-- Speed training multiplier from your knife trail (and the Phantom Trail pass)
function GameConfig.TrailMultiplier(level: number, phantom: boolean?): number
	local trail = GameConfig.Trails[level]
	local multiplier = if trail then trail.Multiplier else 1
	if phantom then
		multiplier = math.max(multiplier, GameConfig.PhantomTrail.Multiplier)
	end
	return multiplier
end

return GameConfig
