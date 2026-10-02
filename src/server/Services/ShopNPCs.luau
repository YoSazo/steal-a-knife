--!strict
-- The plaza's shopkeepers. Instead of a Shop button, you walk up and talk to someone:
--   Mortimer, the Knife Merchant: sealed knife cases (the Case Shop) and Health upgrades
--   Madame Vesper, the Mystic: Innocent Powers (buy, upgrade, equip)
-- Each stands at a little stall with a glowing ring on the floor in front: step onto it and the
-- client opens that shop panel (ShopRing tag, ShopPanel attribute); step off and it closes. Purchases still go
-- through the usual server remotes, so standing here grants nothing by itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local Props = require(ReplicatedStorage.Shared.Props)
local Toy = require(ReplicatedStorage.Shared.Toy)
local Disguises = require(script.Parent.Disguises)

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
	Wear: { { Prop: string, Color: Color3 } },
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
		Title = "Power Mystic",
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
	-- Local -Z is the front (where customers stand). Toy-style: studded wood, a striped awning
	local counter = block(folder, "Counter", Vector3.new(10, 3.4, 2.4), at(0, 1.7, -3), wood)
	Toy.Dress(counter, Toy.Sides, 1, 0)
	block(folder, "CounterTop", Vector3.new(10.6, 0.4, 3), at(0, 3.6, -3), wood:Lerp(Color3.new(0, 0, 0), 0.3))
	for _, x in { -5, 5 } do
		for _, z in { -4, 2.5 } do
			block(folder, "Post", Vector3.new(0.6, 10, 0.6), at(x, 5, z), wood)
		end
	end
	-- Striped awning, tilted towards the customers
	for i = 0, 5 do
		local stripe = block(
			folder,
			"Canopy",
			Vector3.new(11 / 6, 0.6, 8.4),
			at(-5.5 + 11 / 12 + i * 11 / 6, 10.2, -0.8) * CFrame.Angles(math.rad(-10), 0, 0),
			if i % 2 == 0 then spec.Color else Color3.fromRGB(245, 245, 245)
		)
		stripe.CanCollide = false
		Toy.Dress(stripe, { Enum.NormalId.Top }, 1, 0)
	end
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
	anchor.CanCollide = false
	anchor.CanQuery = false
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(280, 54)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Brightness = 0.85 -- full-bright signs, a touch softer than pure white
	gui.Adornee = anchor
	gui.Parent = anchor
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Text = spec.Title
	text.Parent = gui
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
		for i, rarity in { "Common", "Epic", "Godly" } do
			local case = KnifeModel.BuildCase(rarity, true)
			case:ScaleTo(0.6)
			case:PivotTo(at(-3.2 + (i - 1) * 3.2, 4.4, -3) * CFrame.Angles(0, math.rad(180 + (i - 2) * 15), 0))
			for _, d in case:GetDescendants() do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
				end
			end
			case.Parent = folder
		end
		-- Knives displayed on a board behind the merchant
		block(folder, "KnifeBoard", Vector3.new(8, 4.5, 0.4), at(0, 6, 2.3), wood, Enum.Material.WoodPlanks)
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
	else
		-- A glowing crystal ball on a stand, candles, floating sparkles
		block(folder, "BallStand", Vector3.new(1, 0.6, 1), at(0, 4.1, -3), rgb(200, 160, 70), Enum.Material.Metal)
		local ball = block(folder, "CrystalBall", Vector3.one * 1.8, at(0, 5.2, -3), spec.Color, Enum.Material.Glass)
		ball.Shape = Enum.PartType.Ball
		ball.Transparency = 0.25
		ball.CanCollide = false
		local light = Instance.new("PointLight")
		light.Color = spec.Color
		light.Range = 18
		light.Brightness = 2.5
		light.Parent = ball
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(spec.Color, Color3.new(1, 1, 1))
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new(0.3, 0)
		sparkles.Lifetime = NumberRange.new(1, 2)
		sparkles.Rate = 12
		sparkles.Speed = NumberRange.new(0.5, 1.5)
		sparkles.Parent = ball
		for _, x in { -3.6, 3.6 } do
			block(folder, "Candle", Vector3.new(0.4, 1, 0.4), at(x, 4.3, -3), rgb(245, 238, 220))
			local flame =
				block(folder, "Flame", Vector3.new(0.3, 0.45, 0.3), at(x, 5, -3), rgb(255, 190, 90), Enum.Material.Neon)
			flame.CanCollide = false
			flame:AddTag("Flicker")
		end
		local crystal = Props.Build("Crystal", true)
		crystal:ScaleTo(1.4)
		crystal:PivotTo(at(-4.2, 0, 1.5))
		crystal.Parent = folder
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
	rig:PivotTo(frame * CFrame.new(0, height, 0.2))
	local head = rig:FindFirstChild("Head") :: BasePart
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxassetid://126198856889552" -- Happy (tools/make_clothing.py faces)
	face.Parent = head
	for _, wear in spec.Wear do
		Disguises.AddHat(head, wear.Prop, wear.Color)
	end
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
