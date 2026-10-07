--!strict
-- Native chunky toy knives; all 24 silhouettes are reconstructed as individual cuboids.
-- The invisible Handle remains at the grip origin, Blade and Guard keep their aura contracts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Items = require(script.Parent.Items)
local KnifeIcons = require(script.Parent.Config.KnifeIcons)
local Props = require(script.Parent.Props)
local Knives = require(script.Parent.Config.Knives)
local KnifeAura = require(script.Parent.KnifeAura)

local ToyBlockModel = require(script.Parent.ToyBlockModel)

local KnifeModel = {}

local TEMPLATE_FOLDER = "KnifeTemplates"
local TOOL_LENGTH = 1.7 -- forearm length: reads as a knife in a Roblox hand (was 2.4)
local BLOCK_VERSION = 1

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

-- Server templates and client fallback use exactly the same native geometry.
function KnifeModel.Preload()
	assert(RunService:IsServer(), "KnifeModel.Preload runs on the server")
	local old = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER)
	if old and old:GetAttribute("ToyBlockVersion") == BLOCK_VERSION then
		return
	end
	if old then
		old:Destroy()
	end
	-- Building all 24 block knives up front kept every first player waiting on a fresh server: the
	-- folder goes up empty, each knife is built the first time it's needed (template below), and
	-- the rest are warmed in the background, one a frame
	local folder = Instance.new("Folder")
	folder.Name = TEMPLATE_FOLDER
	folder:SetAttribute("ToyBlockVersion", BLOCK_VERSION)
	folder.Parent = ReplicatedStorage
	task.spawn(function()
		for _, knife in Knives.List do
			if folder.Parent and not folder:FindFirstChild(knife.Name) then
				local model = ToyBlockModel.Build(knife.Name, false, "Handle")
				if folder:FindFirstChild(knife.Name) then
					model:Destroy() -- (built on demand meanwhile)
				else
					model.Parent = folder
				end
			end
			task.wait()
		end
	end)
end

local function template(name: string): Model?
	local folder = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER)
	if not folder or folder:GetAttribute("ToyBlockVersion") ~= BLOCK_VERSION then
		return nil
	end
	local found = folder:FindFirstChild(name) :: Model?
	if not found and RunService:IsServer() and Knives.ByName[name] then
		-- first time this knife is needed on this server: build it once, keep it
		local model = ToyBlockModel.Build(name, false, "Handle")
		model.Parent = folder
		found = model
	end
	return found
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

-- Mutations preserve the grip, the edge/body contrast and the raised detailing.
function KnifeModel.ApplyMutation(model: Model, mutation: string)
	if mutation == "" then
		return
	end
	local blade = (model:FindFirstChild("Blade") or model:FindFirstChild("Grip")) :: BasePart?
	for _, d in model:GetDescendants() do
		if not d:IsA("BasePart") or d.Transparency >= 1 then
			continue
		end
		local role = d:GetAttribute("KnifeRole")
		local isGrip = role == "Grip" or role == "GripDetail"
		local isBlade = role == "Blade" or role == "Tip"
		local isAccent = role == "Inlay" or role == "CuttingEdge" or role == "Extra"
		if mutation == "Gold" then
			d.Color = if isGrip
				then d.Color:Lerp(Color3.fromRGB(76, 40, 25), 0.45)
				else if isAccent
					then Color3.fromRGB(255, 232, 139)
					else if isBlade then Color3.fromRGB(211, 157, 42) else Color3.fromRGB(168, 109, 30)
			if not isGrip then
				d.Material = Enum.Material.Metal
				d.Reflectance = 0.08
			end
		elseif mutation == "Diamond" then
			d.Color = if isGrip
				then d.Color:Lerp(Color3.fromRGB(39, 89, 124), 0.55)
				else if isAccent
					then Color3.fromRGB(218, 253, 255)
					else if isBlade then Color3.fromRGB(96, 179, 205) else Color3.fromRGB(62, 118, 153)
			if not isGrip then
				d.Material = if isAccent then Enum.Material.Glass else Enum.Material.Metal
				d.Reflectance = 0.12
			end
		elseif mutation == "Rainbow" then
			if not isGrip then
				local value = if isAccent then 1 else if isBlade then 0.55 else 0.32
				d:SetAttribute("RainbowValue", value)
				d.Material = if isAccent then Enum.Material.Neon else Enum.Material.Metal
				d.Color = Color3.fromHSV(0.55, 0.65, value)
			end
		elseif mutation == "Void" then
			d.Color = if isAccent
				then Color3.fromRGB(180, 111, 255)
				else if isBlade then Color3.fromRGB(48, 29, 76) else Color3.fromRGB(24, 15, 37)
			if not isGrip then
				d.Material = if isAccent then Enum.Material.Neon else Enum.Material.Metal
			end
		end
	end
	if not blade then
		return
	end
	local glow = blade:FindFirstChild("BladeGlow") :: PointLight?
	if glow then
		glow.Color = Items.MutationById[mutation].Color
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
		light.Name = "MutationGlow"
		light.Range = 5
		light.Brightness = 0.6
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
	local model = if source then source:Clone() else ToyBlockModel.Build(name, false, "Handle")
	local root = model.PrimaryPart :: BasePart
	root.Massless = false
	addTrail(model, knife)
	KnifeModel.ApplyMutation(model, parsed.Mutation.Id)
	model:SetAttribute("Item", item)
	model:SetAttribute("Silhouette", name)
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
	local wood = Color3.fromRGB(110, 70, 40):Lerp(Color3.fromRGB(50, 28, 48), math.min((rank - 1) / 4, 1))
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

-- Mystery blocks are actual cuboid toys, shared by the Store's static viewport previews.
function KnifeModel.BuildLuckyBlock(rarity: string, anchored: boolean?): Model
	assert(Knives.RarityColors[rarity] and rarity ~= "Common", `Unknown Lucky Block tier {rarity}`)
	local model = ToyBlockModel.Build("Lucky" .. rarity, anchored, "Handle")
	model:SetAttribute("LuckyBlock", rarity)
	return model
end

-- Scales a knife so it is `length` studs from pommel to tip, whatever its catalog size
function KnifeModel.FitLength(model: Model, length: number)
	local _, size = model:GetBoundingBox()
	model:ScaleTo(model:GetScale() * length / math.max(size.X, size.Y, size.Z))
end

-- Size rolls still carry their bonuses and aura strength, not a different visual size.
function KnifeModel.FitItem(model: Model, _item: string, length: number)
	KnifeModel.FitLength(model, length)
end

-- Knife characters (Codex's art, Assets/KnifeCharacterAssets): the held knife IS the character,
-- held by its grip, blade up, with its FACE TURNED BACK TOWARD ITS OWNER - you see your buddy
-- while you hunt. (Measured in Studio: with a plain grip a knife's front points the way you face,
-- so the face would only ever show victims the back of its head.) Studio only until characters
-- ship: ReplicatedStorage attribute DebugCharacters = true. Returns false if this knife has no
-- character yet (then the normal model is used).
local function characterTool(tool: Tool, knifeName: string): boolean
	if not (RunService:IsStudio() and ReplicatedStorage:GetAttribute("DebugCharacters") == true) then
		return false
	end
	local shared = script.Parent
	local assetsFolder = shared:FindFirstChild("Assets")
	local assetsModule = assetsFolder and assetsFolder:FindFirstChild("KnifeCharacterAssets")
	local configModule = shared.Config:FindFirstChild("KnifeCharacters")
	if not assetsModule or not configModule then
		return false
	end
	local info = (require :: any)(configModule)[knifeName]
	if not info then
		return false
	end
	local model = (require :: any)(assetsModule).BuildCharacter(knifeName, nil, CFrame.identity, { Scale = 1 }) :: Model
	KnifeModel.FitLength(model, TOOL_LENGTH)
	local scale = model:GetScale()
	local handle = model.PrimaryPart :: BasePart -- (its origin: the floor point under the pommel)
	handle.Name = "Handle"
	for _, piece in model:GetDescendants() do
		if piece:IsA("BasePart") then
			piece.Anchored = false
			piece.CanCollide, piece.CanTouch, piece.CanQuery = false, false, false
			piece.Massless = piece ~= handle
			if piece ~= handle and not piece:FindFirstChildOfClass("WeldConstraint") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1 = handle, piece
				weld.Parent = piece
			end
		end
	end
	for _, child in model:GetChildren() do
		child.Parent = tool
	end
	model:Destroy()
	-- in the fist at its grip, then a half turn so the face looks back at you
	tool.Grip = CFrame.new((info.GripOffset :: Vector3) * scale) * CFrame.Angles(0, math.pi, 0)
	return true
end

-- Tool version, wielded in the hub and by the Murderer. The PrimaryPart is already called "Handle".
function KnifeModel.BuildTool(name: string): Tool
	local parsed = Items.Parse(name)
	assert(parsed, `unknown knife {name}`)
	local tool = Instance.new("Tool")
	tool.Name = Items.DisplayName(name)
	tool.ToolTip = Items.DisplayName(name)
	-- The knife's picture in the hotbar, not its name
	tool.TextureId = KnifeIcons[parsed.Knife.Name] or ""
	tool.CanBeDropped = false
	-- Clicks are handled by the client (tap = stab, hold = throw), which calls Activate() on a tap
	tool.ManualActivationOnly = true
	-- Held upright in the fist, MM2 style: tip pointing at the sky. (Measured in Studio: R15's
	-- RightGripAttachment is already turned -90 on X, so a plain grip stands the blade straight up.)
	tool.Grip = CFrame.new()
	if characterTool(tool, parsed.Knife.Name) then
		KnifeAura.Held(tool, name)
		return tool
	end
	local model = KnifeModel.Build(name, false)
	KnifeModel.FitLength(model, TOOL_LENGTH)
	for _, child in model:GetChildren() do
		child.Parent = tool
	end
	if model:HasTag("RainbowKnife") then
		tool:AddTag("RainbowKnife")
	end
	model:Destroy()
	KnifeAura.Held(tool, name) -- the flex: the knife's aura, in your hand
	return tool
end

return KnifeModel
