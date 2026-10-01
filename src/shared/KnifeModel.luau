--!strict
-- Builds knife models. Two flavours:
--   * Mesh knives from Blender (Config/KnifeMeshes). The server turns the mesh ids into template
--     models once at startup (Preload) and parks them in ReplicatedStorage.KnifeTemplates, so both
--     server and client just clone them.
--   * Part-built knives (bright, low-poly), used until the templates exist or if meshes fail.
-- Either way the knife stands along +Y from a grip at the origin, and the model's PrimaryPart is
-- an invisible "Handle" part at the grip, so pivots, welds and Tool grips work the same.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Items = require(script.Parent.Items)
local Props = require(script.Parent.Props)
local Knives = require(script.Parent.Config.Knives)
local KnifeMeshes = require(script.Parent.Config.KnifeMeshes)

local KnifeModel = {}

local MESH_SCALE = 1.35 -- Blender units -> studs, tuned to match the part knives' size
-- Mesh frame (blade along -X, spine +Y) -> knife frame (blade along +Y)
local MESH_TO_KNIFE = CFrame.Angles(0, 0, -math.pi / 2)
local TEMPLATE_FOLDER = "KnifeTemplates"
local TOOL_LENGTH = 2.4 -- studs, pommel to tip, for the knife the Murderer holds

local function part(parent: Instance, name: string, size: Vector3, offset: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = offset
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Parent = parent
	return p
end

local function weldAll(parent: Instance, root: BasePart)
	for _, child in parent:GetChildren() do
		if child:IsA("BasePart") and child ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = child
			weld.Parent = child
		end
	end
end

local function assembleParts(parent: Instance, knife: Knives.Knife): BasePart
	local length, width = knife.BladeLength, knife.BladeWidth
	local handle = part(parent, "Handle", Vector3.new(0.35, 1.1, 0.35), CFrame.new(), knife.HandleColor)
	local pommel = part(parent, "Pommel", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, -0.65, 0), knife.GuardColor)
	pommel.Shape = Enum.PartType.Ball
	part(parent, "Guard", Vector3.new(0.3, 0.2, width + 0.6), CFrame.new(0, 0.65, 0), knife.GuardColor)
	local blade = part(
		parent,
		"Blade",
		Vector3.new(0.12, length * 0.8, width),
		CFrame.new(0, 0.75 + length * 0.4, 0),
		knife.BladeColor
	)

	local tip = Instance.new("WedgePart")
	tip.Name = "Tip"
	tip.Size = Vector3.new(0.12, length * 0.25, width)
	tip.CFrame = CFrame.new(0, 0.75 + length * 0.8 + length * 0.125, 0)
	tip.Color = knife.BladeColor
	tip.CanCollide, tip.CanQuery, tip.CanTouch, tip.Massless = false, false, false, true
	tip.Parent = parent

	if knife.Neon then
		blade.Material = Enum.Material.Neon
		tip.Material = Enum.Material.Neon
		local light = Instance.new("PointLight")
		light.Color = knife.BladeColor
		light.Range = 10
		light.Parent = blade
	end
	weldAll(parent, handle)
	return handle
end

local function colorFor(knife: Knives.Knife, partName: string): Color3
	if partName == "Blade" then
		return knife.BladeColor
	elseif partName == "Handle" then
		return knife.HandleColor
	elseif partName == "Extra" then
		-- gems, crystals and flames glow in the blade colour; rivets/rings match the guard
		return if knife.Rarity == "Godly" or knife.Name == "GoldenDagger" then knife.BladeColor else knife.GuardColor
	end
	return knife.GuardColor
end

-- Server only: create one template per knife from the mesh ids. Yields (a few seconds).
function KnifeModel.Preload()
	assert(RunService:IsServer(), "KnifeModel.Preload runs on the server")
	if ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER) then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = TEMPLATE_FOLDER
	local pending = 0
	for name, specs in KnifeMeshes do
		local knife = Knives.ByName[name]
		if not knife then
			continue
		end
		pending += 1
		task.spawn(function()
			local model = Instance.new("Model")
			model.Name = name
			local root = part(model, "Handle", Vector3.new(0.3, 1, 0.3), CFrame.new(), Color3.new())
			root.Transparency = 1
			local ok, err = pcall(function()
				for _, spec in specs do
					local mesh = AssetService:CreateMeshPartAsync(Content.fromUri(spec.MeshId))
					mesh.Name = if spec.Name == "Handle" then "Grip" else spec.Name
					mesh.Size = spec.Size * MESH_SCALE
					mesh.CFrame = MESH_TO_KNIFE * CFrame.new(spec.Offset * MESH_SCALE)
					mesh.Color = colorFor(knife, spec.Name)
					mesh.Material = Enum.Material.SmoothPlastic
					mesh.CanCollide = false
					mesh.CanQuery = false
					mesh.CanTouch = false
					mesh.Massless = true
					mesh.CastShadow = spec.Name ~= "Extra"
					if spec.Name == "Blade" then
						mesh.Reflectance = 0.12
					end
					if knife.Neon and (spec.Name == "Blade" or spec.Name == "Extra") then
						mesh.Material = Enum.Material.Neon
					end
					mesh.Parent = model
				end
			end)
			if ok then
				if knife.Neon then
					local light = Instance.new("PointLight")
					light.Color = knife.BladeColor
					light.Range = 10
					light.Parent = model:FindFirstChild("Blade")
				end
				weldAll(model, root)
				model.PrimaryPart = root
				model.Parent = folder
			else
				warn(`[KnifeModel] mesh knife {name} failed, using parts: {err}`)
			end
			pending -= 1
		end)
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < 20 do
		task.wait(0.1)
	end
	folder.Parent = ReplicatedStorage
end

local function template(name: string): Model?
	local folder = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER)
	return folder and folder:FindFirstChild(name) :: Model?
end

-- A motion trail along the blade, off by default; the client's animation engine (Moves) turns it
-- on for the part of a swing where the knife is moving
local function addTrail(model: Model, knife: Knives.Knife)
	local blade = model:FindFirstChild("Blade") :: BasePart?
	local root = model.PrimaryPart
	if not blade or not root then
		return
	end
	local length = math.max(blade.Size.X, blade.Size.Y, blade.Size.Z)
	local up = root.CFrame.UpVector
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailBase"
	a0.Position = blade.CFrame:PointToObjectSpace(blade.Position - up * length * 0.35)
	a0.Parent = blade
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailTip"
	a1.Position = blade.CFrame:PointToObjectSpace(blade.Position + up * length * 0.5)
	a1.Parent = blade
	local trail = Instance.new("Trail")
	trail.Name = "KnifeTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.16
	trail.MinLength = 0.02
	trail.LightEmission = 0.7
	trail.FaceCamera = false
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), Knives.RarityColors[knife.Rarity])
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Enabled = false
	trail.Parent = blade
end

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local function sparkles(parent: BasePart, color: ColorSequence, rate: number, size: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "MutationSparkles"
	emitter.Texture = SPARKLE
	emitter.Color = color
	emitter.LightEmission = 1
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.Speed = NumberRange.new(0.3, 1.2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = parent
end

-- Mutations restyle the whole knife. Rainbow cycles its colours on clients (Effects, tag "RainbowKnife").
function KnifeModel.ApplyMutation(model: Model, mutation: string)
	if mutation == "" then
		return
	end
	local blade = (model:FindFirstChild("Blade") or model:FindFirstChild("Grip")) :: BasePart?
	for _, d in model:GetDescendants() do
		if not d:IsA("BasePart") or d.Transparency >= 1 then
			continue
		end
		local isBlade = d.Name == "Blade" or d.Name == "Tip" or d.Name == "Extra"
		if mutation == "Gold" then
			d.Color = if isBlade then Color3.fromRGB(255, 214, 70) else Color3.fromRGB(205, 150, 30)
			d.Material = Enum.Material.Metal
			d.Reflectance = 0.25
		elseif mutation == "Diamond" then
			if isBlade then
				d.Color = Color3.fromRGB(170, 240, 255)
				d.Material = Enum.Material.Glass
				d.Transparency = 0.15
				d.Reflectance = 0.45
			else
				d.Color = Color3.fromRGB(225, 245, 255)
				d.Material = Enum.Material.Ice
			end
		elseif mutation == "Rainbow" then
			d.Material = if isBlade then Enum.Material.Neon else Enum.Material.SmoothPlastic
			d.Color = Color3.fromHSV(math.random(), 0.8, 1)
		elseif mutation == "Void" then
			d.Color = if isBlade then Color3.fromRGB(130, 40, 255) else Color3.fromRGB(14, 8, 24)
			d.Material = if isBlade then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
	if not blade then
		return
	end
	if mutation == "Gold" then
		sparkles(blade, ColorSequence.new(Color3.fromRGB(255, 230, 120)), 4, 0.35)
	elseif mutation == "Diamond" then
		sparkles(blade, ColorSequence.new(Color3.fromRGB(200, 250, 255)), 7, 0.4)
	elseif mutation == "Rainbow" then
		sparkles(
			blade,
			ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 240, 80)),
				ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 220, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
			}),
			10,
			0.45
		)
		model:AddTag("RainbowKnife")
	elseif mutation == "Void" then
		sparkles(blade, ColorSequence.new(Color3.fromRGB(170, 90, 255), Color3.fromRGB(20, 0, 40)), 9, 0.55)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(140, 60, 255)
		light.Range = 12
		light.Brightness = 2
		light.Parent = blade
	end
end

-- Static display model (pedestals, racks, carried over the head, menus). Takes a knife name or an
-- item string ("Katana|Gold|Huge"); mutations restyle it, sizes are applied by FitItem.
function KnifeModel.Build(item: string, anchored: boolean?): Model
	local parsed = Items.Parse(item)
	assert(parsed, `unknown knife {item}`)
	local name, knife = parsed.Name, parsed.Knife
	local source = template(name)
	local model: Model
	if source then
		model = source:Clone()
	else
		model = Instance.new("Model")
		model.Name = name
		model.PrimaryPart = assembleParts(model, knife)
	end
	local root = model.PrimaryPart :: BasePart
	root.Massless = false
	addTrail(model, knife)
	KnifeModel.ApplyMutation(model, parsed.Mutation.Id)
	model:SetAttribute("Item", item)
	if anchored then
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = true
			end
		end
	end
	return model
end

-- Rarity flourishes shared by both chest builds: chains on Epic+, embers and sparkles, a glow
function KnifeModel.DressCase(model: Model, seam: BasePart, color: Color3, rank: number)
	if rank >= 3 then
		for _, x in { -0.55, 0.55 } do
			local chain =
				part(model, "Chain", Vector3.new(0.14, 0.14, 2.3), CFrame.new(x, 1.3, 0), Color3.fromRGB(110, 110, 120))
			chain.Material = Enum.Material.DiamondPlate
		end
	end
	if rank >= 5 then
		-- Godly: a ring of embers around it
		sparkles(seam, ColorSequence.new(color, Color3.fromRGB(255, 200, 120)), 12, 0.5)
	elseif rank >= 2 then
		sparkles(seam, ColorSequence.new(color), 3 * rank, 0.35)
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 8 + rank * 2
	light.Brightness = 1.5
	light.Parent = seam
end

-- A sealed case: what a watchman drops. Iron-banded crate with a glowing seam and lock in its
-- rarity's colour; better cases get gold trim, chains and a floating sigil. Opened (with a reveal)
-- once you carry it home. PrimaryPart "Handle" sits at its centre.
function KnifeModel.BuildCase(rarity: string, anchored: boolean?): Model
	local color = Knives.RarityColors[rarity] or Color3.new(1, 1, 1)
	local rank = table.find(Knives.Rarities, rarity) or 1
	local wood = Color3.fromRGB(110, 70, 40):Lerp(Color3.fromRGB(50, 28, 48), (rank - 1) / 4)
	local trim = if rank >= 4 then Color3.fromRGB(230, 180, 60) else Color3.fromRGB(70, 66, 78)
	if Props.Has("Chest") then
		-- The Blender chest, recoloured for its rarity
		local model = Props.Build("Chest", false)
		model.Name = `Case_{rarity}`
		local root = model.PrimaryPart :: BasePart
		root.Name = "Handle"
		root.Massless = false
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= root then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Massless = true
				if d.Name == "Lock" or d.Name == "Seam" then
					d.Color = color
					d.Material = Enum.Material.Neon
				elseif d.Name == "Wood" then
					d.Color = wood
				elseif d.Name == "Iron" then
					d.Color = trim
				end
			end
		end
		local seam = model:FindFirstChild("Seam") :: BasePart
		local sigil = part(
			model,
			"Sigil",
			Vector3.new(0.5, 0.5, 0.12),
			CFrame.new(0, 1.75, 0) * CFrame.Angles(0, 0, math.rad(45)),
			color
		)
		sigil.Material = Enum.Material.Neon
		KnifeModel.DressCase(model, seam, color, rank)
		weldAll(model, root)
		model:SetAttribute("Case", rarity)
		if anchored then
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
				end
			end
		end
		return model
	end
	local model = Instance.new("Model")
	model.Name = `Case_{rarity}`
	local root = part(model, "Handle", Vector3.new(0.4, 0.4, 0.4), CFrame.new(), Color3.new())
	root.Transparency = 1
	root.Massless = false
	local body = part(model, "Body", Vector3.new(2.8, 1.45, 1.9), CFrame.new(0, -0.2, 0), wood)
	body.Material = Enum.Material.WoodPlanks
	local lid =
		part(model, "Lid", Vector3.new(2.95, 0.55, 2.02), CFrame.new(0, 0.82, 0), wood:Lerp(Color3.new(1, 1, 1), 0.08))
	lid.Material = Enum.Material.WoodPlanks
	-- Glowing seam all the way round where the lid meets the box
	local seam = part(model, "Seam", Vector3.new(2.9, 0.09, 1.98), CFrame.new(0, 0.53, 0), color)
	seam.Material = Enum.Material.Neon
	-- Iron (or gold) straps and corner caps
	for _, x in { -0.95, 0.95 } do
		local band = part(model, "Band", Vector3.new(0.26, 2.12, 2.06), CFrame.new(x, 0.1, 0), trim)
		band.Material = Enum.Material.Metal
	end
	for _, x in { -1.42, 1.42 } do
		for _, y in { -0.88, 1.05 } do
			for _, z in { -0.96, 0.96 } do
				local cap = part(model, "Corner", Vector3.new(0.22, 0.22, 0.22), CFrame.new(x, y, z), trim)
				cap.Material = Enum.Material.Metal
			end
		end
	end
	-- The lock on the front, glowing, with a dark keyhole
	local lock = part(model, "Lock", Vector3.new(0.62, 0.7, 0.16), CFrame.new(0, 0.4, -1.04), color)
	lock.Material = Enum.Material.Neon
	part(model, "Keyhole", Vector3.new(0.12, 0.28, 0.05), CFrame.new(0, 0.36, -1.13), Color3.fromRGB(15, 10, 20))
	-- A rarity sigil hovering over the lid
	local sigil = part(
		model,
		"Sigil",
		Vector3.new(0.5, 0.5, 0.12),
		CFrame.new(0, 1.55, 0) * CFrame.Angles(0, 0, math.rad(45)),
		color
	)
	sigil.Material = Enum.Material.Neon
	KnifeModel.DressCase(model, seam, color, rank)
	weldAll(model, root)
	model.PrimaryPart = root
	model:SetAttribute("Case", rarity)
	if anchored then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
	end
	return model
end

-- Scales a knife so it is `length` studs from pommel to tip, whatever its catalog size
function KnifeModel.FitLength(model: Model, length: number)
	local _, size = model:GetBoundingBox()
	model:ScaleTo(model:GetScale() * length / math.max(size.X, size.Y, size.Z))
end

-- Like FitLength, but a Big / Huge / Colossal item comes out that much bigger
function KnifeModel.FitItem(model: Model, item: string, length: number)
	local parsed = Items.Parse(item)
	KnifeModel.FitLength(model, length * (if parsed then parsed.Size.Scale else 1))
end

-- Tool version, wielded in the hub and by the Murderer. The PrimaryPart is already called "Handle".
function KnifeModel.BuildTool(name: string): Tool
	local parsed = Items.Parse(name)
	assert(parsed, `unknown knife {name}`)
	local tool = Instance.new("Tool")
	tool.Name = Items.DisplayName(name)
	tool.CanBeDropped = false
	-- Clicks are handled by the client (tap = stab, hold = throw), which calls Activate() on a tap
	tool.ManualActivationOnly = true
	-- Held upright in the fist, MM2 style: tip pointing at the sky. (Measured in Studio: R15's
	-- RightGripAttachment is already turned -90 on X, so a plain grip stands the blade straight up.)
	tool.Grip = CFrame.new()
	local model = KnifeModel.Build(name, false)
	-- In the hand every knife is about the same small size, like the classic murder games (a
	-- Colossal one is a little bigger); the big versions are for racks and menus
	KnifeModel.FitLength(model, TOOL_LENGTH * (1 + (parsed.Size.Scale - 1) * 0.35))
	for _, child in model:GetChildren() do
		child.Parent = tool
	end
	model:Destroy()
	return tool
end

return KnifeModel
