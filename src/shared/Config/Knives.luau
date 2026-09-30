--!strict
-- Knife catalog. Knives are stolen from the arena (never bought); each earns cash per second
-- while it sits on the owner's rack. Perk is used in rounds (not implemented yet - core loop first).

export type Knife = {
	Name: string,
	DisplayName: string,
	Rarity: string,
	Income: number, -- cash per second on the rack
	Perk: string,
	BladeLength: number,
	BladeWidth: number,
	BladeColor: Color3,
	GuardColor: Color3,
	HandleColor: Color3,
	Neon: boolean?,
	AssetId: number?, -- filled in once the Blender mesh is uploaded (tools/upload_model.py)
}

local Rarities = { "Common", "Rare", "Epic", "Legendary", "Godly" }

local RarityColors: { [string]: Color3 } = {
	Common = Color3.fromRGB(200, 205, 215),
	Rare = Color3.fromRGB(70, 160, 255),
	Epic = Color3.fromRGB(170, 90, 255),
	Legendary = Color3.fromRGB(255, 190, 40),
	Godly = Color3.fromRGB(255, 60, 90),
}

local list: { Knife } = {
	-- Common
	{
		Name = "RustyShank",
		DisplayName = "Rusty Shank",
		Rarity = "Common",
		Income = 1,
		Perk = "SpeedBurst",
		BladeLength = 1.6,
		BladeWidth = 0.45,
		BladeColor = Color3.fromRGB(170, 110, 70),
		GuardColor = Color3.fromRGB(110, 90, 80),
		HandleColor = Color3.fromRGB(120, 75, 40),
	},
	{
		Name = "KitchenKnife",
		DisplayName = "Kitchen Knife",
		Rarity = "Common",
		Income = 2,
		Perk = "SpeedBurst",
		BladeLength = 2.0,
		BladeWidth = 0.6,
		BladeColor = Color3.fromRGB(225, 230, 235),
		GuardColor = Color3.fromRGB(40, 40, 45),
		HandleColor = Color3.fromRGB(35, 35, 40),
	},
	-- Rare
	{
		Name = "HunterBlade",
		DisplayName = "Hunter Blade",
		Rarity = "Rare",
		Income = 8,
		Perk = "Dash",
		BladeLength = 2.2,
		BladeWidth = 0.55,
		BladeColor = Color3.fromRGB(200, 210, 220),
		GuardColor = Color3.fromRGB(190, 140, 60),
		HandleColor = Color3.fromRGB(110, 60, 25),
	},
	{
		Name = "Switchblade",
		DisplayName = "Switchblade",
		Rarity = "Rare",
		Income = 10,
		Perk = "Dash",
		BladeLength = 1.9,
		BladeWidth = 0.4,
		BladeColor = Color3.fromRGB(120, 200, 255),
		GuardColor = Color3.fromRGB(30, 60, 120),
		HandleColor = Color3.fromRGB(40, 90, 170),
	},
	-- Epic
	{
		Name = "Cleaver",
		DisplayName = "Cleaver",
		Rarity = "Epic",
		Income = 40,
		Perk = "Throw",
		BladeLength = 1.8,
		BladeWidth = 1.2,
		BladeColor = Color3.fromRGB(210, 215, 225),
		GuardColor = Color3.fromRGB(60, 60, 70),
		HandleColor = Color3.fromRGB(150, 40, 40),
	},
	{
		Name = "Machete",
		DisplayName = "Jungle Machete",
		Rarity = "Epic",
		Income = 50,
		Perk = "Throw",
		BladeLength = 2.8,
		BladeWidth = 0.7,
		BladeColor = Color3.fromRGB(190, 120, 255),
		GuardColor = Color3.fromRGB(60, 30, 90),
		HandleColor = Color3.fromRGB(80, 160, 70),
	},
	-- Legendary
	{
		Name = "GoldenDagger",
		DisplayName = "Golden Dagger",
		Rarity = "Legendary",
		Income = 200,
		Perk = "Invisibility",
		BladeLength = 2.4,
		BladeWidth = 0.5,
		BladeColor = Color3.fromRGB(255, 205, 50),
		GuardColor = Color3.fromRGB(230, 40, 60),
		HandleColor = Color3.fromRGB(60, 30, 15),
	},
	{
		Name = "Katana",
		DisplayName = "Sakura Katana",
		Rarity = "Legendary",
		Income = 250,
		Perk = "Invisibility",
		BladeLength = 3.2,
		BladeWidth = 0.45,
		BladeColor = Color3.fromRGB(255, 180, 210),
		GuardColor = Color3.fromRGB(255, 205, 50),
		HandleColor = Color3.fromRGB(40, 20, 40),
	},
	-- Godly
	{
		Name = "VoidEdge",
		DisplayName = "Void Edge",
		Rarity = "Godly",
		Income = 1000,
		Perk = "Blink",
		BladeLength = 3.0,
		BladeWidth = 0.6,
		BladeColor = Color3.fromRGB(150, 60, 255),
		GuardColor = Color3.fromRGB(20, 20, 30),
		HandleColor = Color3.fromRGB(60, 0, 110),
		Neon = true,
	},
	{
		Name = "InfernoFang",
		DisplayName = "Inferno Fang",
		Rarity = "Godly",
		Income = 1200,
		Perk = "Blink",
		BladeLength = 2.8,
		BladeWidth = 0.75,
		BladeColor = Color3.fromRGB(255, 110, 30),
		GuardColor = Color3.fromRGB(40, 20, 20),
		HandleColor = Color3.fromRGB(120, 20, 20),
		Neon = true,
	},
}

local byName: { [string]: Knife } = {}
local byRarity: { [string]: { Knife } } = {}
for _, rarity in Rarities do
	byRarity[rarity] = {}
end
for _, knife in list do
	byName[knife.Name] = knife
	table.insert(byRarity[knife.Rarity], knife)
end

return {
	List = list,
	ByName = byName,
	ByRarity = byRarity,
	Rarities = Rarities,
	RarityColors = RarityColors,
}
