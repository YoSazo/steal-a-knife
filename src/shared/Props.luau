--!strict
-- Custom props made in Blender (blender/scripts/make_props.py), uploaded like the knives, and
-- turned into templates at startup (Preload, server). Everything else asks for a prop by name and
-- gets a Model whose PrimaryPart "Root" sits at the prop's origin. If a mesh isn't uploaded yet (or
-- fails to load), a part-built stand-in is used, so the game never breaks waiting on assets.
--   Props.Build("Skull") -> Model

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PropMeshes = require(script.Parent.Config.PropMeshes)

local Props = {}

local TEMPLATE_FOLDER = "PropTemplates"

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Parent = parent
	return p
end

local function weldAll(model: Model, root: BasePart)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = d
			weld.Parent = d
		end
	end
end

local function newModel(name: string): (Model, Part)
	local model = Instance.new("Model")
	model.Name = name
	local root = part(model, "Root", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), Color3.new())
	root.Transparency = 1
	model.PrimaryPart = root
	return model, root
end

-- Part-built stand-ins, roughly the same size and look as the meshes
local fallbacks: { [string]: (Model) -> () } = {
	SpeedCoin = function(m)
		local face = CFrame.Angles(0, math.rad(90), 0)
		local blue = part(m, "Blue", Vector3.new(0.36, 2.84, 2.84), face, Color3.fromRGB(30, 115, 245))
		blue.Shape = Enum.PartType.Cylinder
		for _, z in { -0.21, 0.21 } do
			local rim =
				part(m, "Rim", Vector3.new(0.08, 2.83, 2.83), CFrame.new(0, 0, z) * face, Color3.fromRGB(245, 250, 255))
			rim.Shape = Enum.PartType.Cylinder
			local inner = part(m, "Inset", Vector3.new(0.09, 2.58, 2.58), CFrame.new(0, 0, z * 1.2) * face, blue.Color)
			inner.Shape = Enum.PartType.Cylinder
			part(m, "Sole", Vector3.new(1.8, 0.18, 0.14), CFrame.new(0, -0.35, z * 1.5), Color3.new(1, 1, 1))
			part(
				m,
				"Sneaker",
				Vector3.new(1.7, 0.45, 0.16),
				CFrame.new(0, -0.06, z * 1.5),
				Color3.fromRGB(70, 225, 255)
			)
			part(m, "Heel", Vector3.new(0.65, 0.5, 0.16), CFrame.new(-0.5, 0.3, z * 1.5), Color3.fromRGB(70, 225, 255))
		end
	end,
	Coin = function(m)
		local face = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis along Z: the coin faces -Z
		local gold =
			part(m, "Gold", Vector3.new(0.3, 2.2, 2.2), face, Color3.fromRGB(255, 190, 40), Enum.Material.Metal)
		gold.Shape = Enum.PartType.Cylinder
		local emblem =
			part(m, "Emblem", Vector3.new(0.36, 1, 1), face, Color3.fromRGB(255, 225, 120), Enum.Material.Metal)
		emblem.Shape = Enum.PartType.Cylinder
	end,
	Pedestal = function(m)
		local stone = part(
			m,
			"Stone",
			Vector3.new(1.17, 3.5, 3.5),
			CFrame.new(0, 0.585, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(70, 64, 82),
			Enum.Material.Slate
		)
		stone.Shape = Enum.PartType.Cylinder
		local glow = part(
			m,
			"Glow",
			Vector3.new(0.08, 2.6, 2.6),
			CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(90, 220, 255),
			Enum.Material.Neon
		)
		glow.Shape = Enum.PartType.Cylinder
	end,
	LootSack = function(m)
		local sack = part(
			m,
			"Sack",
			Vector3.new(2.2, 2.4, 2.0),
			CFrame.new(0, 1.1, 0),
			Color3.fromRGB(150, 110, 70),
			Enum.Material.Fabric
		)
		sack.Shape = Enum.PartType.Ball
		part(
			m,
			"Tie",
			Vector3.new(0.7, 0.5, 0.7),
			CFrame.new(0, 2.4, 0),
			Color3.fromRGB(90, 60, 35),
			Enum.Material.Fabric
		)
	end,
	BurglarMask = function(m)
		part(
			m,
			"Mask",
			Vector3.new(1.3, 0.38, 0.12),
			CFrame.new(0, 0, 0),
			Color3.fromRGB(15, 15, 18),
			Enum.Material.Fabric
		)
	end,
	Skull = function(m)
		local bone = Color3.fromRGB(235, 228, 205)
		part(m, "Cranium", Vector3.new(1.3, 1.2, 1.3), CFrame.new(0, 0.1, 0), bone).Shape = Enum.PartType.Ball
		part(m, "Jaw", Vector3.new(0.9, 0.4, 0.8), CFrame.new(0, -0.5, -0.15), bone)
		for _, x in { -0.28, 0.28 } do
			part(
				m,
				"Eye",
				Vector3.new(0.32, 0.32, 0.2),
				CFrame.new(x, 0.12, -0.58),
				Color3.fromRGB(255, 40, 40),
				Enum.Material.Neon
			)
		end
	end,
	Crystal = function(m)
		part(
			m,
			"Crystal",
			Vector3.new(1.1, 2.6, 1.1),
			CFrame.new(0, 1.3, 0) * CFrame.Angles(0, math.rad(45), 0),
			Color3.fromRGB(170, 70, 255),
			Enum.Material.Neon
		)
	end,
	Chandelier = function(m)
		local iron = Color3.fromRGB(40, 36, 46)
		part(m, "Chain", Vector3.new(0.2, 3, 0.2), CFrame.new(0, 1.5, 0), iron, Enum.Material.Metal)
		local ring = part(
			m,
			"Ring",
			Vector3.new(0.4, 5, 5),
			CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90)),
			iron,
			Enum.Material.Metal
		)
		ring.Shape = Enum.PartType.Cylinder
		for i = 0, 5 do
			local a = i / 6 * math.pi * 2
			part(
				m,
				"Candle",
				Vector3.new(0.3, 0.8, 0.3),
				CFrame.new(math.cos(a) * 2.2, 0.6, math.sin(a) * 2.2),
				Color3.fromRGB(240, 230, 210)
			)
			part(
				m,
				"Flame",
				Vector3.new(0.25, 0.35, 0.25),
				CFrame.new(math.cos(a) * 2.2, 1.15, math.sin(a) * 2.2),
				Color3.fromRGB(255, 180, 70),
				Enum.Material.Neon
			)
		end
	end,
	Sconce = function(m)
		local iron = Color3.fromRGB(45, 40, 50)
		part(m, "Plate", Vector3.new(0.8, 1.4, 0.2), CFrame.new(0, 0, 0), iron, Enum.Material.Metal)
		part(m, "Arm", Vector3.new(0.25, 0.25, 0.9), CFrame.new(0, -0.2, -0.5), iron, Enum.Material.Metal)
		part(m, "Cup", Vector3.new(0.6, 0.4, 0.6), CFrame.new(0, 0, -0.95), iron, Enum.Material.Metal)
		part(
			m,
			"Flame",
			Vector3.new(0.3, 0.5, 0.3),
			CFrame.new(0, 0.4, -0.95),
			Color3.fromRGB(255, 170, 70),
			Enum.Material.Neon
		)
	end,
	Lantern = function(m)
		local iron = Color3.fromRGB(40, 36, 46)
		part(m, "Cap", Vector3.new(1.2, 0.3, 1.2), CFrame.new(0, 0.85, 0), iron, Enum.Material.Metal)
		part(
			m,
			"Glass",
			Vector3.new(0.9, 1.3, 0.9),
			CFrame.new(0, 0, 0),
			Color3.fromRGB(255, 200, 120),
			Enum.Material.Neon
		).Transparency =
			0.2
		part(m, "Base", Vector3.new(1.1, 0.25, 1.1), CFrame.new(0, -0.75, 0), iron, Enum.Material.Metal)
	end,
	Camera = function(m)
		part(m, "Body", Vector3.new(1, 0.65, 0.5), CFrame.new(), Color3.fromRGB(30, 30, 34), Enum.Material.Metal)
		local lens = part(
			m,
			"Lens",
			Vector3.new(0.4, 0.5, 0.5),
			CFrame.new(0, 0, -0.35) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(60, 60, 70),
			Enum.Material.Glass
		)
		lens.Shape = Enum.PartType.Cylinder
		part(
			m,
			"Bulb",
			Vector3.new(0.35, 0.2, 0.2),
			CFrame.new(0.25, 0.4, 0),
			Color3.fromRGB(255, 255, 220),
			Enum.Material.Neon
		)
	end,
}

-- Server only: make a template per prop from PropMeshes. Yields a little.
function Props.Preload()
	assert(RunService:IsServer(), "Props.Preload runs on the server")
	if ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER) then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = TEMPLATE_FOLDER
	folder.Parent = ReplicatedStorage -- (filled as meshes arrive; Build falls back to parts till then)
	local pending = 0
	for name, specs in PropMeshes do
		pending += 1
		task.spawn(function()
			local model, root = newModel(name)
			local ok, err = pcall(function()
				-- All of this prop's meshes download side by side, not one after another
				local meshes: { MeshPart? } = {}
				local failed: string? = nil
				local left = #specs
				for index, spec in specs do
					task.spawn(function()
						local fine, result =
							pcall(AssetService.CreateMeshPartAsync, AssetService, Content.fromUri(spec.MeshId))
						if fine then
							meshes[index] = result
						else
							failed = tostring(result)
						end
						left -= 1
					end)
				end
				while left > 0 do
					task.wait()
				end
				if failed then
					error(failed)
				end
				for index, spec in specs do
					local mesh = meshes[index] :: MeshPart
					mesh.Name = spec.Name
					mesh.Size = spec.Size
					mesh.CFrame = CFrame.new(spec.Offset)
					mesh.Color = spec.Color
					mesh.Material = (Enum.Material :: any)[spec.Material] or Enum.Material.SmoothPlastic
					mesh.CanCollide = false
					mesh.CanQuery = false
					mesh.CanTouch = false
					mesh.Massless = true
					mesh.Parent = model
				end
			end)
			if ok then
				weldAll(model, root)
				model.Parent = folder
			else
				warn(`[Props] mesh prop {name} failed, using parts: {err}`)
			end
			pending -= 1
		end)
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < 15 do
		task.wait(0.1)
	end
	folder:SetAttribute("Ready", true)
end

-- Waits (up to `timeout` s) until Props.Preload has finished: for things that should wear the
-- Blender meshes rather than the part fallbacks (the bosses' hair and hats)
function Props.WaitReady(timeout: number?)
	local started = os.clock()
	while os.clock() - started < (timeout or 20) do
		local folder = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER)
		if folder and folder:GetAttribute("Ready") then
			return
		end
		task.wait(0.2)
	end
end

-- Whether the Blender mesh version of a prop is loaded
function Props.Has(name: string): boolean
	local folder = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER)
	return folder ~= nil and folder:FindFirstChild(name) ~= nil
end

-- A fresh copy of a prop, unanchored and welded (anchor it yourself if it stays put)
function Props.Build(name: string, anchored: boolean?): Model
	local folder = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER)
	local template = folder and folder:FindFirstChild(name) :: Model?
	local model: Model
	if template then
		model = template:Clone()
	else
		local root
		model, root = newModel(name)
		local build = fallbacks[name]
		assert(build, `unknown prop {name}`)
		build(model)
		weldAll(model, root)
	end
	if anchored then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
	end
	return model
end

return Props
