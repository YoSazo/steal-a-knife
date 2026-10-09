--!strict
-- One palette for the runway and murder maps.
local Floors: { [string]: Color3 } = {
	Common = Color3.fromRGB(48, 146, 30), -- the Courtyard: grass (same green as the plaza)
	Rare = Color3.fromRGB(26, 104, 30), -- the Gardens: deep grass
	Epic = Color3.fromRGB(96, 100, 120), -- the Crypts: grey stone
	Legendary = Color3.fromRGB(196, 158, 86), -- the Catacombs: sand
	Mythic = Color3.fromRGB(150, 48, 30), -- the Inferno: red rock
	Godly = Color3.fromRGB(200, 196, 180), -- Olympus: marble
	Celestial = Color3.fromRGB(150, 196, 230), -- the Heavens: cloud blue
	Cosmic = Color3.fromRGB(70, 46, 130), -- Space: purple
}
-- Walls change with the biome too, so going deeper looks deeper
local Walls: { [string]: Color3 } = {
	Common = Color3.fromRGB(214, 146, 78), -- dirt
	Rare = Color3.fromRGB(174, 119, 72), -- dark dirt
	Epic = Color3.fromRGB(110, 110, 118), -- stone
	Legendary = Color3.fromRGB(176, 140, 80), -- sandstone
	Mythic = Color3.fromRGB(90, 40, 34), -- dark basalt
	Godly = Color3.fromRGB(196, 186, 160), -- marble
	Celestial = Color3.fromRGB(200, 214, 230), -- cloud
	Cosmic = Color3.fromRGB(48, 36, 84), -- void
}

return { Floors = Floors, Walls = Walls }
