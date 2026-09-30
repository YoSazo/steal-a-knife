--!strict
-- Every tunable number in one place. Shared so the client can show prices; the server is the
-- only one that ever acts on them.

local GameConfig = {
	-- Economy / progression
	StartingCash = 0,
	StartingSlots = 3,
	MaxSlots = 12,
	MaxSpeedLevel = 10,
	TicketCost = 500,
	MaxTickets = 5,
	TicketWeight = 3, -- one ticket spent in a round = this much extra Murderer weight

	-- Movement
	BaseWalkSpeed = 16,
	SpeedPerLevel = 1.5,
	CarrySpeedMultiplier = 0.9,
	RoundWalkSpeed = 16, -- upgrades don't carry into rounds so new players can still win
	MurdererWalkSpeed = 17,

	-- Arena
	ZoneDepth = 70,
	ArenaWidth = 240,
	PedestalsPerZone = 4,
	KnifeRespawnTime = 20,
	StealHoldDuration = 0.6,
	CatchRadius = 4.5,
	Zones = {
		-- Guard speeds are tuned against carry speed: 16 * 0.9 = 14.4 with no upgrades
		{ Rarity = "Common", Guards = 2, GuardSpeed = 11, Detect = 26, Color = Color3.fromRGB(130, 220, 120) },
		{ Rarity = "Rare", Guards = 2, GuardSpeed = 13.5, Detect = 30, Color = Color3.fromRGB(110, 190, 255) },
		{ Rarity = "Epic", Guards = 3, GuardSpeed = 15.5, Detect = 34, Color = Color3.fromRGB(190, 140, 255) },
		{ Rarity = "Legendary", Guards = 3, GuardSpeed = 18, Detect = 38, Color = Color3.fromRGB(255, 210, 90) },
		{ Rarity = "Godly", Guards = 3, GuardSpeed = 21, Detect = 42, Color = Color3.fromRGB(255, 110, 130) },
	},
	GuardPatrolSpeed = 7,

	-- Rounds
	IntermissionTime = 180,
	RoundTime = 150,
	ResultsTime = 8,
	MurdererGrace = 5, -- seconds before the Murderer gets their knife
	MinPlayers = 2,
	AttackRange = 7,
	AttackCooldown = 0.9,

	-- Round rewards
	SurviveReward = 100,
	LastAliveBonus = 150, -- extra for survivors when only a few made it
	LastAliveFraction = 0.3,
	KillReward = 40,
	WipeBonus = 300,

	-- Anti-cheat
	SpeedTolerance = 1.6, -- carriers moving faster than walkspeed * this drop their knife
}

function GameConfig.SpeedCost(level: number): number
	return math.floor(60 * 1.8 ^ level)
end

function GameConfig.SlotCost(slots: number): number
	return math.floor(150 * 2 ^ (slots - GameConfig.StartingSlots))
end

function GameConfig.WalkSpeed(level: number): number
	return GameConfig.BaseWalkSpeed + level * GameConfig.SpeedPerLevel
end

return GameConfig
