--!strict
-- Furniture only. Positions are at 1x; RoundMaps owns the unchanged walls, doors and spawns.
local Kit = require(script.Parent.RoundMapKit)
type Prop = { string | number }
local scenes: { [string]: { Prop } } = {
	Office = {
		{ "IT", 0, "ServerRack", -104, 18, -90 },
		{ "IT", 0, "ServerRack", -104, 30, -90 },
		{ "IT", 0, "ServerRack", -104, 42, -90 },
		{ "Open office", 0, "PlanCabinet", -43, 49, 0 },
		{ "Open office", 0, "CoffeeStation", -69, 49, 0 },
		{ "Lounge", 0, "MagazineStand", -9, 42, 0 },
		{ "Lounge", 0, "CoffeeStation", -29, 49, 0 },
		{ "Meeting", 0, "PlanCabinet", 5, 17, 180 },
		{ "Meeting", 0, "CoffeeStation", 32, 48, 0 },
		{ "Boss office", 0, "TrophyCase", 42, 48, 0 },
		{ "Boss office", 0, "PlanCabinet", 69, 48, 0 },
		{ "Cafeteria", 0, "ServingLine", 94, 47, 0 },
		{ "Cafeteria", 0, "TrayStack", 105, 50, 0 },
		{ "Storage", 0, "ParcelTrolley", -57, -48, 0 },
		{ "Storage", 0, "PlanCabinet", -43, -45, 90 },
		{ "Office B", 0, "PlanCabinet", -32, -49, 180 },
		{ "Office B", 0, "CoffeeStation", -7, -49, 180 },
		{ "Break room", 0, "CoffeeStation", 6, -43, 180 },
		{ "Break room", 0, "TrayStack", 27, -43, 0 },
		{ "Reception", 0, "MagazineStand", 43, -26, 90 },
		{ "Reception", 0, "Luggage", 68, -49, 180 },
		{ "Mail room", 0, "ParcelTrolley", 102, -46, 180 },
		{ "Mail room", 0, "ParcelTrolley", 82, -36, -90 },
		{ "Archives", 1, "PlanCabinet", -79, 48, 0 },
		{ "Archives", 1, "ParcelTrolley", -91, 13, 180 },
		{ "Conference", 1, "PlanCabinet", -69, 48, 0 },
		{ "Conference", 1, "CoffeeStation", -42, 48, 0 },
		{ "Training", 1, "TrophyCase", -33, 46, 0 },
		{ "Training", 1, "PlanCabinet", -4, 48, 0 },
		{ "Game room", 1, "PoolTable", -56, -30, 0 },
		{ "Game room", 1, "MagazineStand", -43, -14, 0 },
		{ "Library", 1, "MagazineStand", -16, -44, 180 },
		{ "Library", 1, "PlanCabinet", -33, -16, -90 },
	},
	Mansion = {
		{ "Wine cellar", 0, "WineRack", -111, 14, -90 },
		{ "Wine cellar", 0, "WineRack", -111, 28, -90 },
		{ "Wine cellar", 0, "WineRack", -111, 42, -90 },
		{ "Kitchen", 0, "TrayStack", -38, 43, 0 },
		{ "Kitchen", 0, "CoffeeStation", -33, 32, 90 },
		{ "Dining", 0, "ServingLine", -47, -49, 180 },
		{ "Dining", 0, "TrayStack", -31, -36, 90 },
		{ "Master bedroom", 0, "Luggage", 32, 29, -90 },
		{ "Master bedroom", 0, "MagazineStand", 64, 19, 0 },
		{ "Library", 0, "MagazineStand", 32, -27, -90 },
		{ "Library", 0, "PlanCabinet", 66, -47, 180 },
		{ "Study", 0, "MapTable", 95, 29, 0 },
		{ "Study", 0, "PlanCabinet", 82, 47, 0 },
		{ "Trophy room", 0, "TrophyCase", 84, -20, -90 },
		{ "Trophy room", 0, "AntlerChandelier", 95, -27.5, 0, 10 },
		{ "Nursery", 1, "Crib", -104, 44, 0 },
		{ "Nursery", 1, "ToyBlocks", -84, 20, 0 },
		{ "Nursery", 1, "RockingHorse", -84, 44, 0 },
		{ "Guest bedroom", 1, "Luggage", -34, 46, 0 },
		{ "Guest bedroom", 1, "MagazineStand", -69, 18, -90 },
		{ "Gallery", 1, "TrophyCase", 18, 44, 0 },
		{ "Gallery", 1, "TrophyCase", -18, 44, 0 },
		{ "Card room", 1, "MagazineStand", -63, -44, 180 },
		{ "Card room", 1, "Luggage", -68, -18, -90 },
		{ "Attic", 1, "DustSheet", 8, -17, 0 },
		{ "Attic", 1, "DustSheet", -14, -30, -90 },
		{ "Attic", 1, "Cobweb", 15, -53, 180, 10 },
		{ "Attic", 1, "Cobweb", -20, -52, 180, 10 },
	},
}

local Dressing = {}
function Dressing.Build(name: string)
	local rows: { Prop } = scenes[name] or {}
	for _, row in rows do
		Kit.Level(row[2] :: number)
		local height: number? = if type(row[7]) == "number" then row[7] :: number else nil
		local model = Kit.hero(row[3] :: string, row[4] :: number, row[5] :: number, row[6] :: number, height)
		model:SetAttribute("Room", row[1] :: string)
	end
	Kit.Level(0)
end
return Dressing
