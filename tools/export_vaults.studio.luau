--!strict
-- Build detached preview scenes using the actual shared geometry, then export their transforms.
local V = require(script.Parent.VaultModel)
local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local scenes = {}
local function export(folder: Instance, name: string, height: number)
	local rows = {}
	for _, p in folder:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			table.insert(rows, {
				Name = p.Name,
				Group = p.Parent and p.Parent.Name,
				Size = { p.Size.X, p.Size.Y, p.Size.Z },
				CFrame = { p.CFrame:GetComponents() },
				Color = { p.Color.R, p.Color.G, p.Color.B },
				Neon = p.Material == Enum.Material.Neon,
			})
		end
	end
	table.insert(scenes, { Name = name, Height = height, Parts = rows })
	folder:Destroy()
end
local function build(tier: number, floors: number)
	local folder = Instance.new("Folder")
	V.BuildFrame(folder, CFrame.new(), V.Cyan, GameConfig.Walls[tier].Color, floors, tier)
	for floor = 1, floors do
		local surface = if floor == 1 then 0.6 else (floor - 1) * 22
		local function deck(a: number, b: number, c: number, d: number)
			local root = Instance.new("Part")
			root.Name = "DeckCollisionPreview"
			root.Size = Vector3.new(b - a, 1, d - c)
			root.CFrame = CFrame.new((a + b) / 2, if floor == 1 then 0.1 else surface - 0.5, (c + d) / 2)
			root.Color = V.Style(tier).Deck
			root.Parent = folder
		end
		if floor == 1 then
			deck(-20, 20, -22, 22)
		else
			deck(-19.5, 19.5, -21.5, -18)
			deck(-19.5, 19.5, -13, 21.5)
			deck(-19.5, -2.5, -18, -13)
			deck(2.5, 19.5, -18, -13)
		end
		V.BuildFloor(folder, CFrame.new(), surface)
		if floor > 1 then
			V.BuildLadder(folder, CFrame.new(), if floor == 2 then 0.6 else surface - 22, -17)
		end
		for index = 1, 10 do
			local side = if index <= 5 then -1 else 1
			local z = -17 + (index - 1) % 5 * 8
			local slot = (floor - 1) * 10 + index
			local at = CFrame.new(side * 12, surface, z)
			local p = V.BuildPlate(folder, at, slot)
			V.SetPlateTier(p.Details, at, tier)
			local padAt = Vector3.new(side * 6.2, surface + 0.06, z)
			local cashAt = CFrame.lookAt(padAt, padAt - Vector3.new(side, 0, 0)) * CFrame.Angles(0, math.pi / 2, 0)
			V.BuildCollectTray(folder, cashAt * CFrame.new(0, 0.04, 0), slot)
		end
	end
	V.ApplyTier(folder, tier)
	export(folder, GameConfig.Walls[tier].Name .. (if floors > 1 then ` ({floors} floors)` else ""), floors * 22 + 4)
end
for tier = 1, #GameConfig.Walls do
	build(tier, 1)
end
build(2, 2)
build(8, 4)
local plate = Instance.new("Folder")
local built = V.BuildPlate(plate, CFrame.new(), 1)
V.SetPlateTier(built.Details, CFrame.new(), 2)
V.ApplyTier(plate, 2)
export(plate, "Plate closeup", 0.35)
return { Scenes = scenes }
