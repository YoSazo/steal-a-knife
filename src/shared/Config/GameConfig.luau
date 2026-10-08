--!strict
-- Every tunable number in one place. Shared so the client can show prices; the server is the
-- only one that ever acts on them.

-- One day of the login streak: "Cash" (Seconds of income, at least Min), "Coffin" (Rarity) or
-- "Tickets" (Amount)
export type DailyReward = { Kind: string, Seconds: number?, Min: number?, Rarity: string?, Amount: number? }

local DAILY: { DailyReward } = {
	{ Kind = "Cash", Seconds = 120, Min = 20000 },
	{ Kind = "Coffin", Rarity = "Common" },
	{ Kind = "Cash", Seconds = 300, Min = 45000 },
	{ Kind = "Tickets", Amount = 2 },
	{ Kind = "Cash", Seconds = 600, Min = 110000 },
	{ Kind = "Coffin", Rarity = "Rare" },
	{ Kind = "Coffin", Rarity = "Epic" },
}

local GameConfig = {
	-- Economy / progression
	StartingCash = 0,
	-- Vaults grow a floor at a time (Tsunami style): 10 plates per floor, up to 4 floors
	SlotsPerFloor = 10,
	StartingSlots = 10,
	MaxSlots = 40,
	FloorCosts = { 1.5e6, 2e10, 1e14 }, -- the 2nd, 3rd and 4th floor
	FloorRebirths = { 0, 1, 3 }, -- rebirths needed before the 2nd, 3rd and 4th floor (Steal a Brainrot style)
	-- Speed -> walk speed: walk = BaseWalkSpeed + SpeedCurve * log2(1 + Speed / 500). Lower = every
	-- deeper biome needs a lot more Speed (the long climb; tools/pacing_sim.py checks the hours)
	SpeedCurve = 3.6,
	TicketCost = 30000, -- the floor; tickets cost TicketIncomeSeconds of your income (TicketPrice)
	TicketIncomeSeconds = 60,

	-- Reasons to come back: the vault keeps earning while you're away (a fraction, capped), and a
	-- 7-day login streak (miss a day and it starts over). Cash days pay seconds of your income.
	Offline = { Fraction = 0.5, MaxHours = 8, MinAway = 120 },
	-- "Come back" notifications (Roblox Experience Notifications, 13+ players who opt in, one a day):
	-- after AskAfterRounds rounds a player is shown the opt-in (client/NotifyOptIn); when they leave,
	-- NotifyService asks our analytics server to send "your vault filled up: $X waiting" SendAfterHours
	-- later (about the same time of day they played), cancelled if they're back first.
	-- To switch on: create the notification string on Creator Dashboard (Engagement -> Notifications,
	-- with a {cash} parameter), set NOTIFY_MESSAGE_ID on Render, give the API key
	-- user.user-notification:write, then Enabled = true.
	Notify = { Enabled = true, AskAfterRounds = 2, SendAfterHours = 22 },
	-- Coffins (Steal an Egg's egg): a stolen boss knife lands on its plate SEALED in a coffin and opens
	-- after HatchSeconds[rarity] - even while you're offline (come back to see it). Sealed = no income,
	-- no equip/sell. "Open now" = Robux product CoffinOpen. Off until Enabled (Studio: ReplicatedStorage
	-- attribute DebugCoffins = true). The tutorial's first knife never gets a coffin.
	-- Pens instead of vaults (Shared/PenMode): Count pens (5 down each side of the plaza), each Width
	-- along the row x Depth deep, holding up to MaxSlots knives (start StartingSlots; the upgrade adds
	-- SlotsPerFloor). Knife characters are drawn Scale[rarity] x their 2.4-stud size (Common ~5 studs,
	-- Cosmic ~48: over the hub walls, seen from spawn).
	Pens = {
		Enabled = "Split" :: boolean | string, -- false / true / "Split" (half the servers: the A/B launch)
		Count = 10,
		Width = 64,
		-- (10 studs of grass between neighbouring pens: each one its own plot - MapService)
		Depth = 60, -- an upgraded pen's length (the gate stays put, the back fence moves out)
		StartDepth = 42, -- a new pen's length
		MaxSlots = 20,
		PlaceAfter = 30, -- carrying something in your pen this long without tapping: it goes down anyway
		Bag = 10, -- with the pen full, this many more wait in your bag (Knives menu), never lost
		Scale = {
			Common = 2,
			Rare = 3.3,
			Epic = 5,
			Legendary = 7.5,
			Mythic = 10.5,
			Godly = 13.5,
			Celestial = 16.5,
			Cosmic = 20,
		},
	},
	-- The MURDER ROUNDS are the coffins' clock: a coffin opens after Rounds[rarity] rounds (a won
	-- round counts WinRounds), all together right after the results (the opening ceremony). Offline,
	-- each round still owed is OfflineSecondsPerRound of real time. A Common just takes CommonSeconds.
	Coffins = {
		Enabled = "WithPens" :: boolean | string, -- false / true / "WithPens" (on wherever pens are)
		Rounds = { Common = 0, Rare = 1, Epic = 1, Legendary = 2, Mythic = 2, Godly = 3, Celestial = 4, Cosmic = 5 },
		CommonSeconds = 20,
		TutorialSeconds = 6, -- a new player's first coffins: a short countdown, then it opens
		WinRounds = 2,
		OfflineSecondsPerRound = 900,
		AnnounceFrom = "Mythic", -- coffins of this rarity and up are announced to the server
	},
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

	-- Vault wall looks (profile.WallLevel; no longer sold: players keep the tier they bought while
	-- raids existed). The frame, pillars and trim of a vault (VaultWalls / VaultModel).
	Walls = {
		{
			Name = "Starter Lasers",
			Height = 16,
			Color = Color3.fromRGB(60, 64, 110),
			Material = Enum.Material.WoodPlanks,
			Trim = Color3.fromRGB(255, 170, 70),
		},
		{
			Name = "Twin Lasers",
			Height = 21,
			Color = Color3.fromRGB(60, 70, 120),
			Material = Enum.Material.Cobblestone,
			Trim = Color3.fromRGB(120, 200, 255),
		},
		{
			Name = "Iron Grid",
			Height = 26,
			Color = Color3.fromRGB(70, 74, 96),
			Material = Enum.Material.DiamondPlate,
			Trim = Color3.fromRGB(220, 230, 240),
		},
		{
			Name = "Red Alert",
			Height = 31,
			Color = Color3.fromRGB(80, 40, 70),
			Material = Enum.Material.Limestone,
			Trim = Color3.fromRGB(255, 70, 80),
		},
		{
			Name = "Plasma Wall",
			Height = 36,
			Color = Color3.fromRGB(60, 30, 100),
			Material = Enum.Material.Basalt,
			Trim = Color3.fromRGB(190, 90, 255),
		},
		{
			Name = "Void Field",
			Height = 41,
			Color = Color3.fromRGB(20, 30, 60),
			Material = Enum.Material.Glass,
			Trim = Color3.fromRGB(90, 255, 240),
		},
		{
			Name = "Golden Gate",
			Height = 46,
			Color = Color3.fromRGB(90, 80, 60),
			Material = Enum.Material.Marble,
			Trim = Color3.fromRGB(255, 215, 90),
		},
		{
			Name = "Star Shield",
			Height = 52,
			Color = Color3.fromRGB(40, 26, 90),
			Material = Enum.Material.Glass,
			Trim = Color3.fromRGB(255, 120, 240),
		},
	},

	-- Rebirth: start over (cash, knives, slots, Speed, wheel) for a permanent multiplier on
	-- income and Speed training, a title, and better coffin luck
	Rebirth = {
		BaseCost = 2e9,
		CostGrowth = 6,
		IncomeBonus = 0.5, -- +50% income per rebirth
		SpeedBonus = 0.3, -- +30% Speed training per rebirth
		LuckBonus = 0.15, -- +15% mutation / size luck per rebirth
		Max = 30,
		-- Steal a Brainrot style: each rebirth also needs a knife of this rarity on your plates
		-- (the last entry repeats for every rebirth after)
		Needs = { "Legendary", "Mythic", "Godly", "Godly", "Celestial", "Celestial", "Cosmic" },
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

	-- What a coffin is worth in cash: paid instead when one is won but there's no free plate for it
	-- (CoffinService.GiveOrCash)
	CoffinValue = {
		Common = 20000,
		Rare = 300000,
		Epic = 4e6,
		Legendary = 60e6,
		Mythic = 900e6,
		Godly = 14e9,
		Celestial = 220e9,
		Cosmic = 3.5e12,
	} :: { [string]: number },
	-- The Lucky Wheel (Gamble): a free spin a day, one per EarnEvery seconds played, Robux packs
	-- The round prize (Shared/RoundPrize): "Win the round: +X Speed", the same promise for everyone
	-- on the winning side, sized to the next boss you can't outrun yet
	RoundPrize = {
		-- of the step from the last boss's Speed to the next boss's: every win on the way is worth
		-- the same, ~5 wins = one boss (a tuning guess: compare with how fast players train on the wheel)
		StepShare = 0.2,
		PastLastShare = 0.1, -- past the last boss: of your Speed
		MinSpeed = 300,
		-- the cash choice (client/PrizePick): this many seconds of your income, at least MinCash
		CashSeconds = 300,
		MinCash = 5000,
		-- the pick card shows from PickFrom s before the round: leaving ramps up from ~240 s before a
		-- round (fewer leave in the first 2 min after one), so it lands just before most people go
		PickFrom = 240,
		PickUntil = 8, -- and stops this many seconds before it (no card as the round starts)
		JackpotChance = 0.1, -- a JACKPOT round: x3
		JackpotMultiplier = 3,
		AnnounceAt = 240, -- "Your prize if you win" shows this many seconds before the round (= PickFrom)
	},

	-- Surprise gifts (server SurpriseGifts): a present drops near you at random moments while you
	-- play in the hub. Gaps are seconds of hub play; prizes are weighted (Seconds = of income)
	SurpriseGift = {
		FirstMin = 90,
		FirstMax = 180,
		MinGap = 180,
		MaxGap = 540,
		Lifetime = 150, -- it waits at your vault this long (you might be out in the biomes)
		MinCash = 500,
		Prizes = {
			{ Kind = "Cash", Seconds = 60, Weight = 30 },
			{ Kind = "Cash", Seconds = 180, Weight = 20 },
			{ Kind = "Cash", Seconds = 600, Weight = 8 },
			{ Kind = "Spin", Count = 1, Weight = 16 },
			{ Kind = "Spin", Count = 3, Weight = 4 },
			{ Kind = "Cash", Seconds = 300, Weight = 8 },
			{ Kind = "Coffin", Rarity = "Rare", Weight = 8 },
			{ Kind = "Coffin", Rarity = "Epic", Weight = 4 },
			{ Kind = "Coffin", Rarity = "Legendary", Weight = 1.5, Announce = true },
			{ Kind = "Coffin", Rarity = "Mythic", Weight = 0.5, Announce = true },
		} :: { any },
	},
	Spin = {
		EarnEvery = 900,
		RevealDelay = 4.2, -- the wheel's spin on the client; the prize lands when it stops
		Prizes = {
			{ Kind = "Cash", Seconds = 60, Weight = 26, Label = "$ Cash" },
			{ Kind = "Spin", Count = 1, Weight = 14, Label = "+1 Spin" },
			{ Kind = "Cash", Seconds = 300, Weight = 18, Label = "$$ Cash" },
			{ Kind = "Cash", Seconds = 900, Weight = 12, Label = "$$ Cash" },
			{ Kind = "Coffin", Tier = "Rare", Weight = 12, Label = "Rare Coffin" },
			{ Kind = "Cash", Seconds = 1800, Weight = 7, Label = "$$$ CASH" },
			{ Kind = "Coffin", Tier = "Epic", Weight = 6, Label = "Epic Coffin" },
			{ Kind = "Coffin", Tier = "Legendary", Weight = 4.5, Label = "Legendary Coffin" },
			{ Kind = "Coffin", Tier = "Mythic", Weight = 0.5, Label = "MYTHIC COFFIN" },
		} :: { any },
	},
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
	PlayerHealth = 100, -- everyone's health in the hub (health levels were cut: caught means caught)

	RoundWalkSpeed = 16, -- upgrades don't carry into rounds so new players can still win
	MurdererWalkSpeed = 18.5,

	-- The hub is one long straight runway (like the big steal games): the vaults open onto a plaza
	-- at the start, and the zones run one after another down the runway, each rarer and nastier,
	-- all the way to the Manor. Each guard holds a knife from its zone's pool; kill it for the knife.
	ZoneDepth = 220, -- authored depth/fallback; live ranges use ZoneStart/ZoneEnd/ZoneDepthFor
	ArenaWidth = 160,
	CatchRadius = 5.5, -- (bosses are BossScale big: longer arms)
	BossScale = 1.6, -- bosses tower over players so they're easy to spot, phones included
	-- Each zone has one boss: a round character standing in front of a wall of knives. They leave you
	-- alone until you steal one; then they (or, if they're already busy, a shadow of them) chase you
	-- at GuardSpeed all the way to the plaza. Caught = they take the knife back (and Damage hurts).
	-- SpeedNeeded is the Speed at which someone carrying a knife just outruns that zone's boss.
	-- Health decides how long a hit staggers the chaser (better knives stagger longer).
	Zones = {
		{
			Rarity = "Common",
			Boss = "Frank", -- a round character (Disguises) guarding this biome's knife wall
			Depth = 90,
			BossAt = 50 / 90,
			BossTitle = "The Groundskeeper",
			BossWear = {}, -- Blender pieces worn on top of their usual outfit
			Restock = 30, -- seconds before a stolen slot on the wall refills
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
			Depth = 130,
			BossAt = 0.6,
			BossTitle = "The Gardener",
			BossWear = { "FlowerCrown" }, -- Blender pieces worn on top of their usual outfit
			Restock = 45, -- seconds before a stolen slot on the wall refills
			Title = "The Gardens",
			GuardSpeed = 26,
			SpeedNeeded = 5500,
			Health = 200,
			Damage = 12.5,
			Color = Color3.fromRGB(110, 190, 255),
		},
		{
			Rarity = "Epic",
			Boss = "Sam", -- a round character (Disguises) guarding this biome's knife wall
			Depth = 170,
			BossAt = 0.6,
			BossTitle = "The Gravedigger",
			BossWear = {}, -- Blender pieces worn on top of their usual outfit
			Restock = 60, -- seconds before a stolen slot on the wall refills
			Title = "The Crypts",
			GuardSpeed = 47,
			SpeedNeeded = 535000,
			Health = 450,
			Damage = 17.5,
			Throws = true,
			Color = Color3.fromRGB(190, 140, 255),
		},
		{
			Rarity = "Legendary",
			Boss = "Leo", -- a round character (Disguises) guarding this biome's knife wall
			Depth = 210,
			BossAt = 0.6,
			BossTitle = "The Collector",
			BossWear = { "Monocle" }, -- Blender pieces worn on top of their usual outfit
			Restock = 90, -- seconds before a stolen slot on the wall refills
			Title = "The Catacombs",
			GuardSpeed = 70,
			SpeedNeeded = 73e6,
			Health = 1000,
			Damage = 24,
			Throws = true,
			Color = Color3.fromRGB(255, 210, 90),
		},
		{
			Rarity = "Mythic",
			Boss = "Ruby", -- a round character (Disguises) guarding this biome's knife wall
			Depth = 250,
			BossAt = 0.6,
			BossTitle = "The Firestarter",
			BossWear = { "DevilHorns" }, -- Blender pieces worn on top of their usual outfit
			Restock = 120, -- seconds before a stolen slot on the wall refills
			Title = "The Inferno",
			GuardSpeed = 82,
			SpeedNeeded = 950e6,
			Health = 2000,
			Damage = 29,
			Throws = true,
			Color = Color3.fromRGB(255, 90, 40),
		},
		{
			Rarity = "Godly",
			Boss = "Kate", -- a round character (Disguises) guarding this biome's knife wall
			Depth = 290,
			BossAt = 0.6,
			BossTitle = "The Queen",
			BossWear = { "Crown" }, -- Blender pieces worn on top of their usual outfit
			Restock = 180, -- seconds before a stolen slot on the wall refills
			Title = "Mount Olympus",
			GuardSpeed = 94,
			SpeedNeeded = 12.5e9,
			Health = 3800,
			Damage = 33,
			Throws = true,
			Color = Color3.fromRGB(255, 120, 200),
		},
		{
			Rarity = "Celestial",
			Boss = "Zoe", -- a round character (Disguises) guarding this biome's knife wall
			Depth = 330,
			BossAt = 0.6,
			BossTitle = "The Angel",
			BossWear = { "Halo", "AngelWings" }, -- Blender pieces worn on top of their usual outfit
			Restock = 240, -- seconds before a stolen slot on the wall refills
			Title = "The Heavens",
			GuardSpeed = 104,
			SpeedNeeded = 106e9,
			Health = 6500,
			Damage = 37,
			Throws = true,
			Color = Color3.fromRGB(150, 240, 255),
		},
		{
			Rarity = "Cosmic",
			Boss = "Nick", -- a round character (Disguises) guarding this biome's knife wall
			Depth = 370,
			BossAt = 0.6,
			BossTitle = "The Void Walker",
			BossWear = { "SpaceHelmet" }, -- Blender pieces worn on top of their usual outfit
			Restock = 300, -- seconds before a stolen slot on the wall refills
			Title = "Outer Space",
			GuardSpeed = 114,
			SpeedNeeded = 900e9,
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
	BossLair = { At = 0.6, FirstAt = 0.6, Width = 42, Depth = 14 }, -- (FirstAt 0.3 put Frank behind the Courtyard shell's hedges - the shell art is built around 0.6)

	-- Rounds
	-- (was 180: the first real players reset out of 5 rounds within seconds - every ~3.5 min pulled
	-- them off the steal/vault loop they were enjoying. The hub is where progress happens.)
	IntermissionTime = 360,
	-- A first-time player's first knife home pulls the next round in to at most NewcomerRoundIn (s),
	-- but never to a hub break shorter than NewcomerMinBreak (s) for everyone else. (Were 100 / 240:
	-- new players landed their first knife ~1 min in and left ~2 min in, before any round - only 37%
	-- ever saw the murder half.)
	NewcomerRoundIn = 45,
	MapVoteWindow = 150, -- the vote card and the "vote for the map" line show this many seconds before a round
	FirstRoundMurdererUnder = 1200, -- a player's first round makes them the Murderer if they've played less than this (s)
	NewcomerSheriffRounds = 2, -- then their next rounds (2nd..this+1th) make them the Sheriff
	NewcomerMinBreak = 180,
	RoundJoinGrace = 90, -- nobody is pulled into a round in their first this many seconds in a server
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
	-- A full wipe also hands the Murderer a coffin: better in bigger lobbies (real players only)
	WipeCoffin = { Small = "Rare", Big = "Epic", BigLobby = 6 },

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
	RevolverRange = 2000, -- the bullet flies until it hits something

	-- Surviving a round doubles your rack income for a while, so rounds fuel stealing
	BoostDuration = 90,
	BoostMultiplier = 2,

	-- Coins scattered over the round map; innocents grab them while hiding
	RoundCoins = 24,
	CoinRespawn = 12,

	-- Guards shout "!" and hesitate this long before they start chasing (a chase picked back up)
	GuardAlertTime = 0.45,
	-- Taking a knife wakes the boss: eyes go red, they get out of the chair, THEN they chase (Steal An
	-- Egg's chicken). With the boss next to the stash and only the 0.45 s "!", 66% of first steals
	-- were caught, half of them within a second - before the player had even turned round.
	BossWake = {
		Time = 1.3,
		Newcomer = 2.2, -- until you own NewcomerKnives knives
		NewcomerKnives = 3,
	},
	-- How a boss gets out of / back into his chair: he hops out forward over his footstool and hops
	-- back in backwards. Shares of the wake time (client/Moves poses, GuardService flies the body):
	-- crouch from Crouch, in the air TakeOff..Land, back upright by Done. Back home the same hop plays
	-- backwards over SitTime seconds.
	BossHop = {
		Crouch = 0.38,
		TakeOff = 0.5,
		Land = 0.76,
		Done = 0.88,
		Distance = 5, -- studs forward: clears the footstool
		Height = 2.4,
		SitTime = 0.8,
	},
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
	HubThrow = { Cooldown = 0, Range = 2000, DamageMultiplier = 1.6 }, -- flies until it hits something
	-- Server-side floor between any two throws (hub or Murderer). Hold-to-throw already keeps real
	-- players slower than this; it stops exploit scripts firing hundreds a second.
	ThrowMinInterval = 0.3,
	DroppedKnifeLifetime = 30, -- a knife on the floor (from a dead guard or a dead carrier)
	-- Guards in zones with Throws = true stop, wind up (knife glows red) and throw a knife in a
	-- straight line at where you were. Never homing, so sidestepping dodges it.
	-- Boss knife throws lead the thief (Lead = how much of their run they predict) and curve gently
	-- after them in flight (TurnRate, radians/s): a sharp sidestep dodges, running straight doesn't
	GuardThrow = {
		-- OFF: bosses only catch you by touching you (Steal An Egg's one rule). Throws tripped you from
		-- a distance, which nobody could guess was a thing - it made running home two problems.
		Enabled = false,
		Windup = 0.6,
		Cooldown = 2.8,
		MinRange = 10,
		MaxRange = 220, -- far enough that a fast thief still gets thrown at (the knife outruns them)
		FlightRange = 900, -- flies until it hits something (or the thief), not giving up mid-chase
		SpeedOverTarget = 1.5, -- at least this times the target's walk speed
		Speed = 75,
		HitRadius = 2.5,
		Lead = 0.85,
		TurnRate = math.rad(55),
	},

	-- Selling a knife from the rack pays this many seconds of its income
	SellSeconds = 40,

	-- Robux consumables (Config/Monetization): each one takes away a friction you feel every session,
	-- so it's bought again. Timed boosts live in profile.Boosts (os.time until), charges in
	-- profile.Charges (counts). Hub only: nothing here helps win a murder round.
	Consumables = {
		SpeedMultiplier = 1.25, -- Speed Potion: walk speed in the hub (outrun a boss one zone deeper)
		CashMultiplier = 2, -- Cash Potion: vault income
		TrainingMultiplier = 3, -- Training Potion: Haunted Wheel training
		EscapeStun = 3, -- Escape Token: seconds the boss is stunned when you break free
		TrainingOfferAfter = 90, -- seconds on the wheel before the Training Potion is offered
		RestockOfferRange = 45, -- studs from a lair where an empty wall offers the restock
	},
	-- The Murderer meter (server ChanceMeter, profile.Luck): grows each round you aren't picked
	MurdererMeter = {
		PerRound = 2, -- for each round you weren't the Murderer
		Cap = 3, -- nobody's chance can be more than 3x the server average
	},

	-- Every so often a CLASSIC round: no Murderer power, just a knife and a Revolver - and
	-- everyone earns extra for it
	-- DOUBLE TROUBLE: two Murderers, two Sheriffs (always with this many players, else a chance)
	DoubleTrouble = { Always = 10, Chance = 0.2 },
	ClassicChance = 0.2,
	ClassicPay = 1.5,

	-- The Murderer's thrown knife (everyone's, whatever the perk)
	MurderThrow = { Range = 2000, Speed = 110 }, -- flies until it hits something

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
			DisplayName = "Sense",
			Description = "Reveal who's holding the Revolver (3 per round)",
			Uses = 3,
			Cooldown = 5,
			Duration = 4,
		},
		Bulletproof = {
			DisplayName = "Bulwark",
			Description = "Survive one Revolver shot",
			Passive = true,
		},
		ShapeShifter = {
			DisplayName = "Disguise",
			Description = "Turn into someone else (once per round)",
			Uses = 1,
			Cooldown = 3,
		},
		SpamKnife = {
			DisplayName = "Spam Knife",
			Description = "Q: for a few seconds every click throws a knife where you aim (twice a round)",
			Uses = 2,
			Cooldown = 10,
			Duration = 8,
			Interval = 0.25, -- server floor between two spam throws
			Range = 2000,
		},
		GhostKnife = {
			DisplayName = "Phantom",
			Description = "Thrown knives fly through up to 5 people",
			Passive = true,
			Pierce = 5,
		},
		Invisiknife = {
			DisplayName = "Shadow",
			Description = "Turn invisible for a few seconds after every kill",
			Passive = true,
			Duration = 4,
		},
		LaserKnife = {
			DisplayName = "Laser",
			Description = "Fully charged throws fly lightning fast",
			Passive = true,
			Speed = 480,
		},
		ExplodingKnife = {
			DisplayName = "Blast",
			Description = "Throw kills explode, taking out anyone close by",
			Passive = true,
			Radius = 9,
		},
		-- Murderer sides that only come on knives (docs/POWERS.md)
		Snare = {
			DisplayName = "Snare",
			Description = "Q: drop a hidden snare: the next innocent to step in is stuck",
			Uses = 2,
			Cooldown = 4,
			Duration = 2, -- seconds stuck
		},
		DecoyKnife = {
			DisplayName = "Decoy",
			Description = "Q: a fake you runs off - bait the Sheriff",
			Uses = 1,
			Cooldown = 10,
			Duration = 6,
		},
		FlashKnife = {
			DisplayName = "Flash",
			Description = "Q: blind the innocents in front of you",
			Uses = 2,
			Cooldown = 12,
			Duration = 1.4,
			Range = 24,
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

-- Shared cumulative layout. Interior ranges are [start, end); the final edge stays in the last zone.
function GameConfig.ZoneDepthFor(index: number): number
	local zone = GameConfig.Zones[index]
	assert(zone, `Invalid biome index {index}`)
	local depth = zone.Depth or GameConfig.ZoneDepth
	assert(depth > 0 and depth < math.huge, "Biome depth must be positive and finite")
	return depth
end

function GameConfig.ZoneStart(index: number): number
	assert(GameConfig.Zones[index], `Invalid biome index {index}`)
	local start = 0
	for i = 1, index - 1 do
		start += GameConfig.ZoneDepthFor(i)
	end
	return start
end

function GameConfig.ZoneEnd(index: number): number
	return GameConfig.ZoneStart(index) + GameConfig.ZoneDepthFor(index)
end

function GameConfig.TotalZoneDepth(): number
	return GameConfig.ZoneEnd(#GameConfig.Zones)
end

function GameConfig.ZoneAtZ(z: number): number?
	if z ~= z or z < 0 or z > GameConfig.TotalZoneDepth() then
		return nil
	end
	local finish = 0
	for i = 1, #GameConfig.Zones do
		finish += GameConfig.ZoneDepthFor(i)
		if z < finish or i == #GameConfig.Zones then
			return i
		end
	end
	return nil
end

-- Where zone `index`'s boss lair stands (on the floor, against its side wall)
function GameConfig.BossLairCenter(index: number): Vector3
	local lair = GameConfig.BossLair
	local side = if index % 2 == 1 then -1 else 1
	return Vector3.new(
		side * (GameConfig.ArenaWidth / 2 - lair.Depth / 2),
		0,
		GameConfig.ZoneStart(index) + GameConfig.ZoneDepthFor(index) * GameConfig.Zones[index].BossAt
	)
end

-- What the next floor costs for someone who has `slots` plates now
function GameConfig.SlotCost(slots: number): number
	local floors = math.max(1, math.ceil(slots / GameConfig.SlotsPerFloor))
	return GameConfig.FloorCosts[floors] or math.huge
end

-- The rarity a rebirth from `rebirths` needs on your plates
function GameConfig.RebirthNeeds(rebirths: number): string
	local needs = GameConfig.Rebirth.Needs
	return needs[math.min(rebirths + 1, #needs)]
end

-- Rebirths needed before buying the floor after `slots`
function GameConfig.FloorRebirthsFor(slots: number): number
	local floors = math.max(1, math.ceil(slots / GameConfig.SlotsPerFloor))
	return GameConfig.FloorRebirths[floors] or 0
end

-- The deepest biome's rarity your Speed can outrun (cash cases / blocks only go up to this)
function GameConfig.RarityReached(speed: number): string
	local reached = GameConfig.Zones[1].Rarity
	for _, zone in GameConfig.Zones do
		if speed >= (zone.SpeedNeeded or 0) then
			reached = zone.Rarity
		end
	end
	return reached
end

function GameConfig.FloorsFor(slots: number): number
	return math.clamp(math.ceil(slots / GameConfig.SlotsPerFloor), 1, GameConfig.MaxSlots // GameConfig.SlotsPerFloor)
end

-- Speed stat -> walk speed. Every doubling of Speed is worth +4.4 walk speed (16 at 0, ~30 at 4K,
-- ~54 at 180K, ~79 at 10M, ~105 at 650M, ~128 at 31B), up to MaxWalkSpeed.
function GameConfig.WalkSpeedFor(speed: number): number
	local walk = GameConfig.BaseWalkSpeed + GameConfig.SpeedCurve * math.log(1 + math.max(speed, 0) / 500, 2)
	return math.min(walk, GameConfig.MaxWalkSpeed)
end

-- Speed per second your wheel really trains (tier x rebirths x trail x Fast Wheel pass x Training
-- Potion): what the server adds, and what every number about the wheel shows (a kid read the bare
-- tier rate, "+20 speed", and thought upgrades were worthless)
function GameConfig.TrainRate(
	level: number,
	rebirths: number,
	trailLevel: number,
	phantom: boolean,
	fastWheel: boolean,
	training: boolean
): number
	local tier = GameConfig.Treadmills[math.clamp(level, 1, #GameConfig.Treadmills)]
	return tier.Rate
		* (1 + rebirths * GameConfig.Rebirth.SpeedBonus)
		* (if fastWheel then 2 else 1)
		* (if training then GameConfig.Consumables.TrainingMultiplier else 1)
		* GameConfig.TrailMultiplier(trailLevel, phantom)
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

-- The "Upgrade Wheel" sign by your Haunted Wheel (Steal An Egg's treadmill sign): one button, one
-- level number. Each press buys whichever is cheaper of the next wheel and the next knife trail, so
-- the economy is the same as buying both separately (the Upgrades menu is gone).
export type SpeedUpgrade = { Kind: string, Name: string, Cost: number, Level: number, MaxLevel: number }
function GameConfig.SpeedLevel(treadmillLevel: number, trailLevel: number): number
	return treadmillLevel + trailLevel
end
function GameConfig.NextSpeedUpgrade(treadmillLevel: number, trailLevel: number): SpeedUpgrade?
	local wheel = GameConfig.Treadmills[treadmillLevel + 1]
	local trail = GameConfig.Trails[trailLevel + 1]
	local level = GameConfig.SpeedLevel(treadmillLevel, trailLevel)
	local maxLevel = #GameConfig.Treadmills + #GameConfig.Trails
	if wheel and (not trail or wheel.Cost <= trail.Cost) then
		return { Kind = "Treadmill", Name = wheel.Name, Cost = wheel.Cost, Level = level, MaxLevel = maxLevel }
	elseif trail then
		return {
			Kind = "Trail",
			Name = `{trail.Name} (x{trail.Multiplier})`,
			Cost = trail.Cost,
			Level = level,
			MaxLevel = maxLevel,
		}
	end
	return nil
end

return GameConfig
