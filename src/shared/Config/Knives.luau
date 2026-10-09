--!strict
-- Knife catalog. Stolen monster coffins unlock characters that earn Cash in pens.
-- Rarity controls the biome, appearance and cosmetic Murderer kill burst.
-- Mesh may reuse another knife's Blender mesh in this knife's colours.

export type Knife = {
	Name: string,
	DisplayName: string,
	Rarity: string,
	Income: number, -- cash per second on the rack
	Damage: number, -- per hit on a guard in the arena (throws do a bit more)
	BladeLength: number,
	BladeWidth: number,
	BladeColor: Color3,
	GuardColor: Color3,
	HandleColor: Color3,
	Neon: boolean?,
	Mesh: string?,
	AssetId: number?, -- filled in once the Blender mesh is uploaded (tools/upload_model.py)
}

local Rarities = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Godly", "Celestial", "Cosmic" }

local RarityColors: { [string]: Color3 } = {
	Common = Color3.fromRGB(200, 205, 215),
	Rare = Color3.fromRGB(70, 160, 255),
	Epic = Color3.fromRGB(170, 90, 255),
	Legendary = Color3.fromRGB(255, 190, 40),
	Mythic = Color3.fromRGB(255, 70, 50),
	Godly = Color3.fromRGB(255, 95, 185),
	Celestial = Color3.fromRGB(150, 240, 255),
	Cosmic = Color3.fromRGB(130, 80, 255),
}

local rgb = Color3.fromRGB

-- Name, display name, rarity, income/s, damage, blade length/width, colours, extras
local function knife(
	name: string,
	display: string,
	rarity: string,
	income: number,
	damage: number,
	length: number,
	width: number,
	blade: Color3,
	guard: Color3,
	handle: Color3,
	extra: { Mesh: string?, Neon: boolean? }?
): Knife
	return {
		Name = name,
		DisplayName = display,
		Rarity = rarity,
		Income = income,
		Damage = damage,
		BladeLength = length,
		BladeWidth = width,
		BladeColor = blade,
		GuardColor = guard,
		HandleColor = handle,
		Mesh = extra and extra.Mesh,
		Neon = extra and extra.Neon,
	}
end

local list: { Knife } = {
	-- Common: The Courtyard
	knife("RustyShank", "Steve", "Common", 75, 25, 1.6, 0.45, rgb(170, 110, 70), rgb(110, 90, 80), rgb(120, 75, 40)),
	knife("KitchenKnife", "Chris", "Common", 110, 30, 2.0, 0.6, rgb(225, 230, 235), rgb(40, 40, 45), rgb(35, 35, 40)),
	knife("PocketKnife", "Pete", "Common", 160, 35, 1.6, 0.4, rgb(210, 215, 220), rgb(170, 30, 30), rgb(200, 40, 40)),
	-- Rare: The Gardens
	knife("HunterBlade", "Gary", "Rare", 900, 50, 2.2, 0.55, rgb(200, 210, 220), rgb(190, 140, 60), rgb(110, 60, 25)),
	knife("Switchblade", "Ricky", "Rare", 1300, 55, 1.9, 0.4, rgb(120, 200, 255), rgb(30, 60, 120), rgb(40, 90, 170)),
	knife("ThornDagger", "Linda", "Rare", 1900, 62, 2.2, 0.5, rgb(120, 220, 110), rgb(60, 110, 40), rgb(70, 45, 25)),
	-- Epic: The Crypts
	knife("Cleaver", "Tony", "Epic", 12000, 90, 1.8, 1.2, rgb(210, 215, 225), rgb(60, 60, 70), rgb(150, 40, 40)),
	knife("Machete", "Chad", "Epic", 17000, 100, 2.8, 0.7, rgb(190, 120, 255), rgb(60, 30, 90), rgb(80, 160, 70)),
	knife("BoneCarver", "Kelly", "Epic", 25000, 112, 2.6, 0.6, rgb(235, 225, 200), rgb(120, 110, 95), rgb(70, 60, 55)),
	-- Legendary: The Catacombs
	knife(
		"GoldenDagger",
		"Doug",
		"Legendary",
		170000,
		160,
		2.4,
		0.5,
		rgb(255, 205, 50),
		rgb(230, 40, 60),
		rgb(60, 30, 15)
	),
	knife(
		"Katana",
		"Wendy",
		"Legendary",
		250000,
		180,
		3.2,
		0.45,
		rgb(255, 180, 210),
		rgb(255, 205, 50),
		rgb(40, 20, 40)
	),
	knife("Reaper", "Carl", "Legendary", 360000, 200, 2.8, 0.7, rgb(60, 60, 70), rgb(255, 200, 60), rgb(25, 20, 25)),
	-- Mythic: The Inferno
	knife(
		"InfernoFang",
		"Lenny",
		"Mythic",
		2400000,
		300,
		2.8,
		0.75,
		rgb(255, 110, 30),
		rgb(40, 20, 20),
		rgb(120, 20, 20),
		{ Neon = true }
	),
	knife(
		"MagmaCleaver",
		"Hank",
		"Mythic",
		3600000,
		330,
		1.9,
		1.25,
		rgb(255, 80, 20),
		rgb(50, 25, 20),
		rgb(30, 20, 20),
		{ Neon = true }
	),
	knife(
		"DemonHorn",
		"Nina",
		"Mythic",
		5200000,
		360,
		3.0,
		0.6,
		rgb(220, 20, 30),
		rgb(25, 10, 10),
		rgb(60, 0, 0),
		{ Neon = true }
	),
	-- Godly: Mount Olympus
	knife(
		"ZeusBolt",
		"Daisy",
		"Godly",
		38000000,
		500,
		3.2,
		0.45,
		rgb(255, 240, 90),
		rgb(240, 240, 255),
		rgb(90, 140, 255),
		{ Neon = true }
	),
	knife(
		"AthenaBlade",
		"Paul",
		"Godly",
		56000000,
		550,
		2.6,
		0.55,
		rgb(245, 245, 255),
		rgb(255, 205, 60),
		rgb(70, 110, 200),
		{ Neon = true }
	),
	knife(
		"OlympusEdge",
		"Quinn",
		"Godly",
		85000000,
		600,
		3.0,
		0.6,
		rgb(255, 120, 200),
		rgb(255, 215, 80),
		rgb(255, 250, 240),
		{ Neon = true }
	),
	-- Celestial: The Heavens
	knife(
		"HaloBlade",
		"Tina",
		"Celestial",
		650000000,
		850,
		3.0,
		0.5,
		rgb(255, 250, 220),
		rgb(255, 220, 90),
		rgb(240, 240, 255),
		{ Neon = true }
	),
	knife(
		"SeraphSword",
		"Uma",
		"Celestial",
		1000000000,
		950,
		3.2,
		0.6,
		rgb(160, 240, 255),
		rgb(255, 230, 140),
		rgb(255, 255, 255),
		{ Neon = true }
	),
	knife(
		"AngelFeather",
		"Vince",
		"Celestial",
		1500000000,
		1050,
		2.8,
		0.55,
		rgb(255, 255, 255),
		rgb(150, 230, 255),
		rgb(255, 215, 120),
		{ Neon = true }
	),
	-- Cosmic: Outer Space
	knife(
		"VoidEdge",
		"Bob",
		"Cosmic",
		11000000000,
		1500,
		3.0,
		0.6,
		rgb(150, 60, 255),
		rgb(20, 20, 30),
		rgb(60, 0, 110),
		{ Neon = true }
	),
	knife(
		"StarCleaver",
		"Yara",
		"Cosmic",
		17000000000,
		1700,
		2.0,
		1.3,
		rgb(90, 220, 255),
		rgb(30, 20, 60),
		rgb(255, 230, 120),
		{ Neon = true }
	),
	knife(
		"GalaxyKatana",
		"Zane",
		"Cosmic",
		28000000000,
		2000,
		3.4,
		0.45,
		rgb(255, 90, 230),
		rgb(60, 220, 255),
		rgb(20, 10, 40),
		{ Neon = true }
	),
}

local byName: { [string]: Knife } = {}
local byRarity: { [string]: { Knife } } = {}
for _, rarity in Rarities do
	byRarity[rarity] = {}
end
for _, entry in list do
	byName[entry.Name] = entry
	table.insert(byRarity[entry.Rarity], entry)
end

-- 1 for Common .. 8 for Cosmic
local function rank(rarity: string): number
	return table.find(Rarities, rarity) or 1
end

return {
	List = list,
	ByName = byName,
	ByRarity = byRarity,
	Rarities = Rarities,
	RarityColors = RarityColors,
	Rank = rank,
}
