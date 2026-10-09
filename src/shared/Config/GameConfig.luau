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
	CommunityGroupId = 857947897,
	-- The free gift for joining that group (once ever, server/Services/GiftService): a share of the
	-- way to the next monster you can't outrun yet
	GroupGift = { Speed = 0.25 },
	-- Pickup Speed by biome depth; the safe zone uses Common.
	CoinSpeed = { 1, 25, 600, 8000, 80000, 600000, 3200000, 27000000 },
	Secret = { Chance = 0.0005, Knife = "NightWhisper" }, -- 1 in 2,000 Cosmic-boss restocks only
	-- Pens start with ten individual plates.
	StartingSlots = 10,
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
	-- Each pen holds sealed coffins and unlocked characters. Room grows by one slot.
	-- Characters grow with rarity; the glass coffins fit individual plates.
	Pens = {
		Count = 6, -- one pen per player: 6-player servers (Creator Dashboard -> Places -> Server size)
		Width = 52, -- (was 64 x 60: the plaza between the pens was a big empty field)
		-- (10 studs of grass between neighbouring pens: each one its own plot - MapService)
		Depth = 50, -- every pen's length (all the same size)
		MaxSlots = 20,
		-- Steal An Egg's pen: room grows one knife at a time, the first upgrade nearly free (an
		-- instant first purchase), then steeper. Cost of the upgrade from 10, 11, ... 19 slots.
		-- (Was one +10 jump at the vault's 2nd-floor price, $1.5M.)
		SlotCosts = { 1e3, 2.5e5, 5e6, 7.5e7, 1e9, 1.5e10, 3e10, 6e10, 1.2e11, 2.4e11 },
		PassRoom = 3, -- the Extra Room pass (Monetization ExtraFloor) adds this many on pens
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
			Secret = 24,
		},
	},
	-- Round progress and offline elapsed time make coffins READY; the owner taps to unlock.
	-- Winners count twice. Common/tutorial timers are short onboarding waits.
	Coffins = {
		Enabled = true, -- (coffins go with pens)
		-- Fast hatches (owner 2026-10-09): a win counts as two rounds, so early knives open quickly.
		Rounds = {
			Common = 0,
			Rare = 1,
			Epic = 2,
			Legendary = 3,
			Mythic = 4,
			Godly = 6,
			Celestial = 8,
			Cosmic = 10,
			Secret = 12,
		},
		CommonSeconds = 20,
		TutorialSeconds = 6, -- a new player's first coffins: a short countdown, then it opens
		WinRounds = 2,
		OfflineSecondsPerRound = 142, -- one current cycle (70 + 3.6 + 60 + 8), rounded
		WinnerLuck = 2, -- mutation roll weight boost until the next round starts
		AnnounceFrom = "Mythic", -- coffins of this rarity and up are announced to the server
	},
	Daily = DAILY,
	-- New players can't lose knives (vault break-ins, burglars, Murderer loot) until they've played
	-- this long, so nobody gets robbed in their first few minutes
	NewPlayerShield = 300,
	MaxTickets = 5,
	TicketWeight = 3, -- one ticket spent in a round = this much extra Murderer weight

	-- Movement. Banked round and delivery Speed turns
	-- into running speed on a curve (WalkSpeedFor). Each zone needs a certain Speed: there's no
	-- barrier, but below it that zone's guards will run you down on the way home.
	BaseWalkSpeed = 16,
	MaxWalkSpeed = 135,
	CarrySpeedMultiplier = 0.9,
	-- Cosmetic knife trails, bought with Cash and retained through rebirth.
	Trails = {
		{
			Name = "Rusty Trail",
			Knife = "RustyShank",

			Cost = 160000,
			Color = Color3.fromRGB(190, 150, 120),
		},
		{
			Name = "Kitchen Trail",
			Knife = "KitchenKnife",

			Cost = 1.25e6,
			Color = Color3.fromRGB(200, 225, 255),
		},
		{
			Name = "Hunter Trail",
			Knife = "HunterBlade",

			Cost = 9e6,
			Color = Color3.fromRGB(110, 230, 140),
		},
		{
			Name = "Thorn Trail",
			Knife = "ThornDagger",

			Cost = 80e6,
			Color = Color3.fromRGB(120, 220, 110),
		},
		{
			Name = "Cleaver Trail",
			Knife = "Cleaver",

			Cost = 500e6,
			Color = Color3.fromRGB(190, 110, 255),
		},
		{
			Name = "Golden Trail",
			Knife = "GoldenDagger",

			Cost = 7e9,
			Color = Color3.fromRGB(255, 205, 60),
		},
		{
			Name = "Inferno Trail",
			Knife = "InfernoFang",

			Cost = 100e9,
			Color = Color3.fromRGB(255, 110, 30),
		},
		{
			Name = "Olympus Trail",
			Knife = "ZeusBolt",

			Cost = 1.5e12,
			Color = Color3.fromRGB(255, 240, 90),
		},
		{
			Name = "Halo Trail",
			Knife = "HaloBlade",

			Cost = 25e12,
			Color = Color3.fromRGB(255, 250, 220),
		},
		{
			Name = "Galaxy Trail",
			Knife = "GalaxyKatana",

			Cost = 400e12,
			Color = Color3.fromRGB(255, 90, 230),
		},
	},
	-- The Robux trail (Monetization pass "PhantomTrail"): void knives and a x10 multiplier
	PhantomTrail = { Name = "Phantom Trail", Knife = "VoidEdge", Color = Color3.fromRGB(170, 70, 255) },

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
		-- (the last entry repeats for every rebirth after). First rebirth needs Mythic, not
		-- Legendary: the old Legendary gate was clearing in under 3 hours.
		Needs = { "Mythic", "Godly", "Godly", "Celestial", "Celestial", "Cosmic" },
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
		Secret = 12e12,
	} :: { [string]: number },
	-- The full bankable survival budget is a fixed share of the next zone's Speed gap.
	RoundPrize = {
		StepShare = 0.01,
		ZoneShares = {
			[2] = 0.1620700,
			[3] = 0.0483677,
			[4] = 0.0168899,
			[5] = 0.0110595,
			[6] = 0.0080000,
			[7] = 0.0060000,
			[8] = 0.0040000,
		},
		PastLastShare = 0.03, -- past the last boss: of your Speed
		MinSpeed = 300,
		-- "Win the round: +X Speed" shows this many seconds before the round (leaving ramps up from
		-- ~240 s before a round, so it lands just before most people go)
		AnnounceAt = 240,
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
			{ Kind = "Cash", Seconds = 60, Weight = 16 },
			{ Kind = "Cash", Seconds = 180, Weight = 4 },
			{ Kind = "Cash", Seconds = 300, Weight = 8 },
			{ Kind = "Coffin", Rarity = "Rare", Weight = 8 },
			{ Kind = "Coffin", Rarity = "Epic", Weight = 4 },
			{ Kind = "Coffin", Rarity = "Legendary", Weight = 1.5, Announce = true },
			{ Kind = "Coffin", Rarity = "Mythic", Weight = 0.5, Announce = true },
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
		Secret = { Cash = 5e12, Speed = 20e9 },
	},

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
	-- Creature bosses are GIANT (the thumbnail's monster): zone 1's stands CreatureHeight.First studs
	-- tall (a player is ~5), each zone deeper Step more, the deepest just under the 36-stud walls.
	-- Their reach grows with them (GuardService).
	CreatureHeight = { First = 24, Step = 1.5 },
	-- Each zone has one boss: a round character standing in front of a wall of knives. They leave you
	-- alone until you steal one; then they (or, if they're already busy, a shadow of them) chase you
	-- at GuardSpeed all the way to the plaza. Caught = they take the knife back (and Damage hurts).
	-- SpeedNeeded is the Speed at which someone carrying a knife just outruns that zone's boss.
	-- Health decides how long a hit staggers the chaser (better knives stagger longer).
	Zones = {
		{
			Rarity = "Common",
			Boss = "Frank", -- the name on the boss's tag (and this zone's round outfit)
			-- The first thing a new player meets is a giant monster (what the thumbnail promises)
			Creature = "HedgeHound" :: string?,
			Monster = "Hedge Hound", -- what players see: its tag, the goals ("outrun the HEDGE HOUND")
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
			Boss = "Ivy", -- the name on the boss's tag (and this zone's round outfit)
			Creature = "FlowerToad" :: string?, -- the giant creature guarding this biome
			Monster = "Flower Toad", -- what players see: its tag, the goals ("outrun the FLOWER TOAD")
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
			Boss = "Sam", -- the name on the boss's tag (and this zone's round outfit)
			Creature = "BoneWolf" :: string?, -- the giant creature guarding this biome
			Monster = "Bone Wolf", -- what players see: its tag, the goals ("outrun the BONE WOLF")
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
			Boss = "Leo", -- the name on the boss's tag (and this zone's round outfit)
			Creature = "GoldScorpion" :: string?, -- the giant creature guarding this biome
			Monster = "Gold Scorpion", -- what players see: its tag, the goals ("outrun the GOLD SCORPION")
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
			Boss = "Ruby", -- the name on the boss's tag (and this zone's round outfit)
			Creature = "LavaSalamander" :: string?, -- the giant creature guarding this biome
			Monster = "Lava Salamander", -- what players see: its tag, the goals ("outrun the LAVA SALAMANDER")
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
			Boss = "Kate", -- the name on the boss's tag (and this zone's round outfit)
			Creature = "GoldenGriffin" :: string?, -- the giant creature guarding this biome
			Monster = "Golden Griffin", -- what players see: its tag, the goals ("outrun the GOLDEN GRIFFIN")
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
			Boss = "Zoe", -- the name on the boss's tag (and this zone's round outfit)
			Creature = "SkyPegasus" :: string?, -- the giant creature guarding this biome
			Monster = "Sky Pegasus", -- what players see: its tag, the goals ("outrun the SKY PEGASUS")
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
			Boss = "Nick", -- the name on the boss's tag (and this zone's round outfit)
			Creature = "VoidBeast" :: string?, -- the giant creature guarding this biome
			Monster = "Void Beast", -- what players see: its tag, the goals ("outrun the VOID BEAST")
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
	-- The cycle is Steal An Egg's heartbeat now (their ~5 min day + night): the round IS the night -
	-- carried boss knives go back, everyone comes home, every stash restocks - and rounds are pure
	-- gain (they unlock coffins and pay Speed), so they can come often. (Was 360 / 150: a round
	-- every ~8.5 min, back when a round could cost you a knife.)
	IntermissionTime = 70,
	NightWarning = 10, -- "Murder round in 10!" - a carried boss knife goes back when it starts
	-- A first-time player's first knife home pulls the next round in to at most NewcomerRoundIn (s),
	-- but never to a hub break shorter than NewcomerMinBreak (s) for everyone else. (Were 100 / 240:
	-- new players landed their first knife ~1 min in and left ~2 min in, before any round - only 37%
	-- ever saw the murder half.)
	NewcomerRoundIn = 45,
	FirstRoundMurdererUnder = 1200, -- a player's first round makes them the Murderer if they've played less than this (s)
	NewcomerSheriffRounds = 2, -- then their next rounds (2nd..this+1th) make them the Sheriff
	NewcomerMinBreak = 70, -- (was 180: the whole break is 180 now)
	RoundJoinGrace = 60, -- nobody is pulled into a round in their first this many seconds in a server
	RoundTime = 60,
	DoubleSpeedRoundChance = 0.25, -- selected once when the intermission begins
	ResultsTime = 8,
	RoleRevealSeconds = 3.6,
	MurdererGrace = 10, -- seconds before the Murderer gets their knife (same as the classic)
	MinPlayers = 2,
	AttackRange = 7,
	StabLagSlack = 4, -- extra reach when the Murderer's screen showed the target in range (lag)
	MurdererThrowCooldown = 0, -- hold-click throw, every Murderer has it (the knife perk is extra); the wind-up is the only limit
	AttackCooldown = 0.9,

	-- Round rewards scale with what your vault earns (Seconds of your income per second), never
	-- below Min, so a round is worth playing at every stage (GameConfig.Pay)
	LastAliveFraction = 0.3,
	-- A full wipe also hands the Murderer a coffin: better in bigger lobbies (real players only)

	-- Live servers: bots top every round up to this many people, so a round can start as soon as one
	-- real player is around. With one real player, a bot is sometimes the Murderer.
	BotFill = { Size = 8, MinHumans = 1 }, -- quiet servers still get a busy round (16-player servers fill up with people)

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
		-- Steal An Egg: the guardian is up and running almost the instant you grab one - no long
		-- get-up to wait through. How fair a chase is comes from the boss's run speed, not a head start.
		Time = 1.5,
		Newcomer = 1.5, -- let the first three deliveries clear the creature before its chase
		NewcomerKnives = 3,
		HoundTime = 1.5,
		HoundNewcomer = 1.5,
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
		RoundSpeedMultiplier = 3, -- banked round Speed
		EscapeStun = 3, -- Escape Token: seconds the boss is stunned when you break free
		RestockOfferRange = 45, -- studs from a lair where an empty wall offers the restock
	},
	-- The Murderer meter (server ChanceMeter, profile.Luck): grows each round you aren't picked
	MurdererMeter = {
		PerRound = 2, -- for each round you weren't the Murderer
		Cap = 3, -- nobody's chance can be more than 3x the server average
	},

	-- The Murderer's thrown knife (everyone's, whatever the perk)
	MurderThrow = { Range = 2000, Speed = 110 }, -- flies until it hits something

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
-- The name players see for zone `index`'s boss: the creature ("Hedge Hound"), else the person
function GameConfig.MonsterName(index: number): string
	local zone = (GameConfig.Zones :: any)[index]
	return if zone then (zone.Monster or zone.Boss) :: string else "boss"
end

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

-- The rarity a rebirth from `rebirths` needs on your plates
function GameConfig.RebirthNeeds(rebirths: number): string
	local needs = GameConfig.Rebirth.Needs
	return needs[math.min(rebirths + 1, #needs)]
end

-- Rebirths needed before buying the floor after `slots`

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

-- Speed stat -> walk speed. Every doubling of Speed is worth +4.4 walk speed (16 at 0, ~30 at 4K,
-- ~54 at 180K, ~79 at 10M, ~105 at 650M, ~128 at 31B), up to MaxWalkSpeed.
function GameConfig.WalkSpeedFor(speed: number): number
	local walk = GameConfig.BaseWalkSpeed + GameConfig.SpeedCurve * math.log(1 + math.max(speed, 0) / 500, 2)
	return math.min(walk, GameConfig.MaxWalkSpeed)
end

return GameConfig
