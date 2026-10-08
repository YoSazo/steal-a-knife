--!strict
-- Knife powers: every knife carries a Murderer power (GameConfig.Perks[Id]), used when you're the
-- Murderer: its knife type's (Config/Knives Perk), or one set on the item (Items). Tier says how
-- strong it is (the auto-picked fighting knife prefers higher tiers; colours).
--
-- Ids are the old Murderer perk ids so existing knives ("Name|Mut|Size|Power") keep working; Name is
-- what players see.

export type KnifePower = {
	Id: string,
	Name: string,
	Tier: string, -- Common, Rare, Epic, Legendary, Mythic
}

local KnifePowers = {}

KnifePowers.Tiers = {
	{ Id = "Common", Color = Color3.fromRGB(200, 200, 210) },
	{ Id = "Rare", Color = Color3.fromRGB(80, 170, 255) },
	{ Id = "Epic", Color = Color3.fromRGB(180, 90, 255) },
	{ Id = "Legendary", Color = Color3.fromRGB(255, 180, 40) },
	{ Id = "Mythic", Color = Color3.fromRGB(255, 70, 90) },
}

KnifePowers.List = {
	{
		Id = "Invisiknife",
		Name = "Shadow",
		Tier = "Common",
	},
	{ Id = "Identifier", Name = "Sense", Tier = "Common" },
	{ Id = "Snare", Name = "Snare", Tier = "Common" },
	{ Id = "ShapeShifter", Name = "Disguise", Tier = "Rare" },
	{ Id = "DecoyKnife", Name = "Decoy", Tier = "Rare" },
	{ Id = "FlashKnife", Name = "Flash", Tier = "Rare" },
	{ Id = "Bulletproof", Name = "Bulwark", Tier = "Epic" },
	{
		Id = "GhostKnife",
		Name = "Phantom",
		Tier = "Epic",
	},
	{
		Id = "Fury",
		Name = "Fury",
		Tier = "Epic",
	},
	{
		Id = "LaserKnife",
		Name = "Laser",
		Tier = "Legendary",
	},
	{
		Id = "ExplodingKnife",
		Name = "Blast",
		Tier = "Legendary",
	},
	{
		Id = "SpamKnife",
		Name = "Spam Knife",
		Tier = "Mythic",
	},
	{
		Id = "Hellfire",
		Name = "Hellfire",
		Tier = "Mythic",
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

local tierById: { [string]: { Id: string, Color: Color3 } } = {}
local tierRank: { [string]: number } = {}
for i, tier in KnifePowers.Tiers do
	tierById[tier.Id] = tier
	tierRank[tier.Id] = i
end
KnifePowers.TierById = tierById

function KnifePowers.TierRank(tier: string): number
	return tierRank[tier] or 1
end

return KnifePowers
