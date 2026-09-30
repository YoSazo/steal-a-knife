--!strict
-- Knife catalog. AssetId gets filled in after `tools/upload_model.py` uploads the model.

export type Knife = {
	Name: string,
	Rarity: string,
	Price: number,
	IncomePerSecond: number,
	AssetId: number?,
}

local Knives: { Knife } = {
	{ Name = "RustyShank", Rarity = "Common", Price = 25, IncomePerSecond = 1 },
	{ Name = "KitchenKnife", Rarity = "Common", Price = 100, IncomePerSecond = 3 },
	{ Name = "HunterBlade", Rarity = "Rare", Price = 750, IncomePerSecond = 15 },
	{ Name = "Cleaver", Rarity = "Epic", Price = 5_000, IncomePerSecond = 80 },
	{ Name = "GoldenDagger", Rarity = "Legendary", Price = 50_000, IncomePerSecond = 600 },
	{ Name = "VoidEdge", Rarity = "Mythic", Price = 500_000, IncomePerSecond = 5_000 },
}

return Knives
