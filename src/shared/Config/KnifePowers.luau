--!strict
-- Knife powers: every knife carries a Murderer power (GameConfig.Perks[Id]), used when you're the
-- Murderer. Rarity (Tier) decides which power a knife rolls; power level (GameConfig.PowerLevelFor,
-- profile.PowerXP) decides how strong it is.
--
-- Ids are the old Murderer perk ids so existing knives ("Name|Mut|Size|Power") keep working; Name is
-- what players see. Ready = it works in the game (only Ready powers are rolled).

export type KnifePower = {
	Id: string,
	Name: string,
	Tier: string, -- Common, Rare, Epic, Legendary, Mythic
	Ready: boolean,
}

local KnifePowers = {}

KnifePowers.Tiers = {
	{ Id = "Common", Weight = 62, Color = Color3.fromRGB(200, 200, 210) },
	{ Id = "Rare", Weight = 27, Color = Color3.fromRGB(80, 170, 255) },
	{ Id = "Epic", Weight = 8.5, Color = Color3.fromRGB(180, 90, 255) },
	{ Id = "Legendary", Weight = 2.4, Color = Color3.fromRGB(255, 180, 40) },
	{ Id = "Mythic", Weight = 0.1, Color = Color3.fromRGB(255, 70, 90) },
}

KnifePowers.List = {
	{
		Id = "Invisiknife",
		Name = "Shadow",
		Tier = "Common",
		Ready = true,
	},
	{ Id = "Identifier", Name = "Sense", Tier = "Common", Ready = true },
	{ Id = "Snare", Name = "Snare", Tier = "Common", Ready = true },
	{ Id = "ShapeShifter", Name = "Disguise", Tier = "Rare", Ready = true },
	{ Id = "DecoyKnife", Name = "Decoy", Tier = "Rare", Ready = true },
	{ Id = "FlashKnife", Name = "Flash", Tier = "Rare", Ready = true },
	{ Id = "Bulletproof", Name = "Bulwark", Tier = "Epic", Ready = true },
	{
		Id = "GhostKnife",
		Name = "Phantom",
		Tier = "Epic",
		Ready = true,
	},
	{
		Id = "Fury",
		Name = "Fury",
		Tier = "Epic",
		Ready = true,
	},
	{
		Id = "LaserKnife",
		Name = "Laser",
		Tier = "Legendary",
		Ready = true,
	},
	{
		Id = "ExplodingKnife",
		Name = "Blast",
		Tier = "Legendary",
		Ready = true,
	},
	{
		Id = "SpamKnife",
		Name = "Spam Knife",
		Tier = "Mythic",
		Ready = true,
	},
	{
		Id = "Hellfire",
		Name = "Hellfire",
		Tier = "Mythic",
		Ready = true,
	},
} :: { KnifePower }

-- A few kid-simple words each: { what it does for the Murderer } (menus, the tutorial showcase;
-- the long descriptions live in GameConfig.Perks)
KnifePowers.Short = {
	Invisiknife = { "Vanish after every kill" },
	Identifier = { "See who has the gun" },
	Snare = { "Hide a trap" },
	ShapeShifter = { "Look like someone else" },
	DecoyKnife = { "A fake you runs off" },
	FlashKnife = { "Blind them!" },
	Bulletproof = { "Survive one shot" },
	GhostKnife = { "Knives fly through people" },
	Fury = { "Faster throws every kill" },
	LaserKnife = { "Lightning-fast throws" },
	ExplodingKnife = { "Kills explode!" },
	SpamKnife = { "Throw knives nonstop!" },
	Hellfire = { "Flaming knives!" },
}

-- The power every new player's first (tutorial) knife gets: simple and fair for everyone
KnifePowers.Starter = "Invisiknife"

local byId: { [string]: KnifePower } = {}
for _, power in KnifePowers.List do
	byId[power.Id] = power
end
KnifePowers.ById = byId

local tierById: { [string]: { Id: string, Weight: number, Color: Color3 } } = {}
local tierRank: { [string]: number } = {}
for i, tier in KnifePowers.Tiers do
	tierById[tier.Id] = tier
	tierRank[tier.Id] = i
end
KnifePowers.TierById = tierById

function KnifePowers.TierRank(tier: string): number
	return tierRank[tier] or 1
end

-- The chance (0..1) a roll at 1x luck lands on this power
function KnifePowers.Chance(id: string): number
	local power = byId[id]
	if not power or not power.Ready then
		return 0
	end
	local total = 0
	for _, tier in KnifePowers.Tiers do
		total += tier.Weight
	end
	local inTier = 0
	for _, other in KnifePowers.List do
		if other.Ready and other.Tier == power.Tier then
			inTier += 1
		end
	end
	return tierById[power.Tier].Weight / total / math.max(1, inTier)
end

-- Every roll gives a power. luck (>= 1) multiplies every tier's weight above Common.
function KnifePowers.Roll(rng: Random, luck: number?): string
	local boost = math.max(1, luck or 1)
	local weights: { [string]: number } = {}
	local total = 0
	for i, tier in KnifePowers.Tiers do
		local weight = tier.Weight * (if i > 1 then boost else 1)
		weights[tier.Id] = weight
		total += weight
	end
	local pick = rng:NextNumber() * total
	local chosen = KnifePowers.Tiers[1].Id
	for _, tier in KnifePowers.Tiers do
		pick -= weights[tier.Id]
		if pick <= 0 then
			chosen = tier.Id
			break
		end
	end
	local pool = {}
	for _, power in KnifePowers.List do
		if power.Ready and power.Tier == chosen then
			table.insert(pool, power.Id)
		end
	end
	if #pool == 0 then
		for _, power in KnifePowers.List do
			if power.Ready and power.Tier == "Common" then
				table.insert(pool, power.Id)
			end
		end
	end
	return pool[rng:NextInteger(1, #pool)]
end

return KnifePowers
