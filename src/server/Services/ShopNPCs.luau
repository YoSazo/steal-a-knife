--!strict
-- The plaza's shopkeepers. Instead of a Shop button, you walk up and talk to someone:
--   Mortimer, the Knife Merchant: sealed knife cases (the Case Shop) and Health upgrades
--   Madame Vesper, the Enchanter: knife powers (see yours and every power, re-roll a knife's power)
-- Each stands at a little stall with a glowing ring on the floor in front: step onto it and the
-- client opens that shop panel (ShopRing tag, ShopPanel attribute); step off and it closes. Purchases still go
-- through the usual server remotes, so standing here grants nothing by itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local ToyBlockModel = require(ReplicatedStorage.Shared.ToyBlockModel)
local Disguises = require(script.Parent.Disguises)
local CharacterFaces = require(script.Parent.CharacterFaces)
local CharacterDetails = require(script.Parent.CharacterDetails)

local ShopNPCs = {}

type Spec = {
	Name: string,
	Title: string,
	Panel: string, -- the client panel the Talk prompt opens
	Position: Vector3,
	Facing: number, -- yaw in degrees
	Color: Color3, -- stall canopy / sign
	Skin: Color3,
	Coat: Color3,
	Pants: Color3,
	Wear: { Disguises.Wear },
	Lines: { string }, -- greetings (the client picks one)
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local SPECS: { Spec } = {
	{
		Name = "Mortimer",
		Title = "Knife Merchant",
		Panel = "Shop",
		-- The two stalls stand either side of the runway entrance, facing the plaza
		Position = Vector3.new(-45, 0, -26),
		-- Turned in at an angle (front = local -Z): the two stalls' lines of sight cross like an X
		-- across the entrance
		Facing = -50,
		Color = rgb(70, 200, 90),
		Skin = rgb(234, 184, 146),
		Coat = rgb(70, 30, 40),
		Pants = rgb(30, 26, 30),
		Wear = { { Prop = "TopHat", Color = rgb(25, 22, 28) } },
		Lines = {
			"Fresh cases, sealed tight! What'll it be?",
			"Every case has a knife inside... maybe a Rainbow one!",
			"Getting hurt out there? I sell Health too.",
			"Mutations, sizes, Godly blades... step right up!",
		},
	},
	{
		Name = "Madame Vesper",
		Title = "The Enchanter",
		Panel = "Powers",
		Position = Vector3.new(45, 0, -26), -- across the entrance from Mortimer
		Facing = 50,
		Color = rgb(170, 90, 255),
		Skin = rgb(204, 142, 105),
		Coat = rgb(70, 40, 120),
		Pants = rgb(40, 24, 70),
		Wear = { { Prop = "HairLong", Color = rgb(30, 20, 40) }, { Prop = "RoundGlasses", Color = rgb(200, 160, 70) } },
		Lines = {
			"The spirits whisper... you need a power.",
			"Vanish, Flash, Shield... the Murderer fears them all.",
			"Coins in the round fuel your powers, child.",
			"Equip your powers wisely. The night is long.",
		},
	},
}

local function block(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- The stall: a counter in front of the shopkeeper, posts, a striped canopy, a hanging sign, and
-- wares on the counter (knives for the merchant, a crystal ball for the mystic)
local function buildStall(folder: Instance, spec: Spec, frame: CFrame)
	local wood = rgb(110, 72, 44)
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local shell = ToyBlockModel.Build(if spec.Panel == "Shop" then "ShopMortimer" else "ShopVesper", true)
	shell:PivotTo(frame)
	-- No board above the stall: the name floats on its own (below)
	local boardParts = {
		SignSide = true,
		SignRail = true,
		ShopSignBack = true,
		CrestBack = true,
		CrestBlade = true,
		CrestGuard = true,
		CrestGrip = true,
	}
	for _, d in shell:GetDescendants() do
		if d:IsA("BasePart") and boardParts[d.Name] then
			d:Destroy()
		end
	end
	shell.Parent = folder
	-- Retain the existing counter and keeper step as collision-only surfaces.
	local counter = block(folder, "Counter", Vector3.new(10, 3.4, 2.4), at(0, 1.7, -3), wood)
	counter.Transparency = 1
	local step = block(folder, "KeeperStep", Vector3.new(7, 0.45, 2.4), at(0, 0.225, 0.2), wood)
	step.Transparency = 1
	-- A soft glowing ring on the floor in front: "stand here"
	local ring = block(
		folder,
		"GlowRing",
		Vector3.new(0.1, 9, 9),
		at(0, 0.25, -8.8) * CFrame.Angles(0, 0, math.rad(90)),
		spec.Color:Lerp(Color3.new(1, 1, 1), 0.3),
		Enum.Material.Neon
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.55
	ring.CanCollide = false
	ring.CanQuery = false
	-- Standing on the ring opens the shop (client/Menus); walking off closes it
	ring:SetAttribute("ShopPanel", spec.Panel)
	ring:AddTag("ShopRing")
	-- One clean title floating over the stall (white fading into the stall's colour)
	local anchor = block(folder, "TitleAnchor", Vector3.one * 0.2, at(0, 12.5, -1), spec.Color)
	anchor.Transparency = 1
	anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = false, false, false
	local title = Instance.new("BillboardGui")
	title.Size = UDim2.fromOffset(280, 54)
	title:SetAttribute("LabelCategory", "Shop")
	title:AddTag("ResponsiveWorldLabel")
	title.MaxDistance = 140
	title.LightInfluence = 0
	title.Adornee = anchor
	title.Parent = anchor
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Text = spec.Title
	text.Parent = title
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), spec.Color:Lerp(Color3.new(1, 1, 1), 0.35))
	gradient.Parent = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = spec.Color:Lerp(Color3.new(0, 0, 0), 0.65)
	stroke.Parent = text
	-- Wares
	if spec.Panel == "Shop" then
		local casePositions = { -3.5, -1.8, 3.3 } -- leave the merchant's face clear in the middle
		for i, rarity in { "Common", "Epic", "Godly" } do
			local case = ToyBlockModel.Build("FreeChest", true)
			for _, p in case:GetChildren() do
				if p:IsA("BasePart") and p.Name == "Wood" then
					p.Color = if i == 1
						then rgb(203, 57, 57)
						else if i == 2 then rgb(77, 151, 98) else rgb(190, 78, 165)
				end
			end
			case:SetAttribute("Case", rarity)
			case:ScaleTo(0.5)
			case:PivotTo(at(casePositions[i], 4.4, -3) * CFrame.Angles(0, math.rad(180 + (i - 2) * 15), 0))
			for _, d in case:GetDescendants() do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
				end
			end
			case.Parent = folder
		end
		-- Knives displayed on a board behind the merchant
		for i, name in { "KitchenKnife", "Katana", "InfernoFang", "VoidEdge" } do
			local knife = KnifeModel.Build(name, true)
			KnifeModel.FitLength(knife, 2.6)
			knife:PivotTo(at(-3 + (i - 1) * 2, 6, 2) * CFrame.Angles(0, math.pi, math.rad(15)))
			for _, d in knife:GetDescendants() do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
				end
			end
			knife.Parent = folder
		end
	end
end

local function buildKeeper(folder: Instance, spec: Spec, frame: CFrame)
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = spec.Skin
	description.TorsoColor = spec.Coat
	description.LeftArmColor = spec.Coat
	description.RightArmColor = spec.Coat
	description.LeftLegColor = spec.Pants
	description.RightLegColor = spec.Pants
	local rig = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	rig.Name = spec.Name
	rig.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- streams in whole, never half a body
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = spec.Name
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.EvaluateStateMachine = false
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	rig.PrimaryPart = root
	local height = humanoid.HipHeight + root.Size.Y / 2
	-- Stands behind the counter (local +Z), facing the customers (-Z)
	rig:PivotTo(frame * CFrame.new(0, height + 0.45, 0.2))
	local head = rig:FindFirstChild("Head") :: BasePart
	head = CharacterFaces.Apply(
		head,
		if spec.Panel == "Shop" then "rbxassetid://93391310013128" else "rbxassetid://137483136763270"
	)
	Disguises.AddAccessories(head, spec.Wear)
	CharacterDetails.Apply(rig, spec.Name)
	rig:AddTag("ShopNPC") -- clients fidget them (Moves) on top of the idle animation
	rig.Parent = folder
	local animator: Animator = humanoid:FindFirstChildOfClass("Animator")
		or (function()
			local created = Instance.new("Animator")
			created.Parent = humanoid
			return created
		end)()
	local idle = Instance.new("Animation")
	idle.AnimationId = "rbxassetid://507766388" -- Roblox's standard R15 idle (guards use it too)
	local ok, track = pcall(animator.LoadAnimation, animator, idle)
	if ok then
		track.Looped = true
		track:Play()
	end
end

function ShopNPCs.Init()
	local map = workspace:FindFirstChild("Map")
	local folder = Instance.new("Folder")
	folder.Name = "Shops"
	folder.Parent = map or workspace
	for _, spec in SPECS do
		local frame = CFrame.new(spec.Position) * CFrame.Angles(0, math.rad(spec.Facing), 0)
		local stall = Instance.new("Model")
		stall.Name = `{spec.Name}Stall`
		stall.Parent = folder
		buildStall(stall, spec, frame)
		buildKeeper(stall, spec, frame)
	end
end

return ShopNPCs
