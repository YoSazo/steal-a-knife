--!strict
-- One biome for eight players. Every shed has two exits; open paths connect every spawn.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Palette = require(ReplicatedStorage.Shared.Config.BiomePalette)
local Toy = require(ReplicatedStorage.Shared.Toy)
local Dressing = require(script.Parent.ManorDecor)
local Maps = {}

export type Built = { Name: string, Folder: Folder, Spawns: { CFrame }, Size: Vector2 }
local names = { "Courtyard", "Gardens", "Crypts", "Catacombs", "Inferno", "Olympus", "Heavens", "Space" }
Maps.Names = names
local width, depth = 160, 140

function Maps.Build(parent: Instance, center: Vector3, requested: string?): Built
	local index = if requested then table.find(names, requested) else math.random(1, #names)
	assert(index, "Unknown biome map")
	local rarity = GameConfig.Zones[index].Rarity
	local previous = parent:FindFirstChild("RoundMap")
	if previous then
		previous:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "RoundMap"
	folder:SetAttribute("Biome", names[index])
	folder.Parent = parent
	local function block(name: string, size: Vector3, offset: Vector3, color: Color3): Part
		local part = Instance.new("Part")
		part.Name, part.Size, part.Position = name, size, center + offset
		part.Anchored, part.Color, part.CastShadow = true, color, false
		part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		part.Parent = folder
		if name ~= "RunwayWall" then
			Toy.Dress(part, if name == "Floor" then { Enum.NormalId.Top } else Toy.Sides, 1, 0)
		end
		return part
	end
	local floor = block("Floor", Vector3.new(width, 1, depth), Vector3.new(0, -0.5, 0), Palette.Floors[rarity])
	local walls: { BasePart } = {}
	for _, x in { -width / 2 - 3, width / 2 + 3 } do
		local wall = block("RunwayWall", Vector3.new(6, 36, depth + 12), Vector3.new(x, 18, 0), Palette.Walls[rarity])
		Toy.DirtWall(wall, Palette.Walls[rarity])
		table.insert(walls, wall)
	end
	for _, z in { -depth / 2 - 3, depth / 2 + 3 } do
		local wall = block("RunwayWall", Vector3.new(width, 36, 6), Vector3.new(0, 18, z), Palette.Walls[rarity])
		Toy.DirtWall(wall, Palette.Walls[rarity])
		table.insert(walls, wall)
	end
	local cover = Palette.Floors[rarity]:Lerp(Color3.new(0, 0, 0), 0.22)
	-- Staggered hedges break sightlines while keeping a central chase route and an outer loop.
	for _, offset in
		{ Vector3.new(-14, 3.5, -40), Vector3.new(14, 3.5, 40), Vector3.new(-20, 3.5, 16), Vector3.new(20, 3.5, -16) }
	do
		block("Hedge", Vector3.new(24, 7, 4), offset, cover)
	end
	for _, offset in { Vector3.new(-43, 0, 22), Vector3.new(43, 0, -22) } do
		local shed = Palette.Walls[rarity]:Lerp(Color3.new(1, 1, 1), 0.2)
		block("ShedWall", Vector3.new(2, 10, 24), offset + Vector3.new(-14, 5, 0), shed)
		block("ShedWall", Vector3.new(2, 10, 24), offset + Vector3.new(14, 5, 0), shed)
		for _, z in { -12, 12 } do
			for _, x in { -10, 10 } do
				block("ShedWall", Vector3.new(8, 10, 2), offset + Vector3.new(x, 5, z), shed)
			end
			block("ShedLintel", Vector3.new(12, 2, 2), offset + Vector3.new(0, 9, z), shed)
		end
		block("ShedRoof", Vector3.new(32, 1, 28), offset + Vector3.new(0, 10.5, 0), cover)
	end
	Dressing.DressRound(folder, floor, walls, rarity)
	local spawns = {}
	for _, offset in
		{
			Vector3.new(-65, 3.5, -54),
			Vector3.new(0, 3.5, -58),
			Vector3.new(65, 3.5, -54),
			Vector3.new(65, 3.5, 0),
			Vector3.new(65, 3.5, 54),
			Vector3.new(0, 3.5, 58),
			Vector3.new(-65, 3.5, 54),
			Vector3.new(-65, 3.5, 0),
		}
	do
		local position = center + offset
		table.insert(spawns, CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)))
	end
	return { Name = names[index], Folder = folder, Spawns = spawns, Size = Vector2.new(width, depth) }
end

return Maps
