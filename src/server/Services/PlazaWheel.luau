--!strict
-- The Lucky Wheel on the plaza (it was a HUD button): standing on the glowing ring in front of it
-- opens the spin panel (ShopRing tag, ShopPanel "Spin"; client/Menus + client/GambleUi). Spinning
-- still goes through the Gamble remote, so standing here grants nothing by itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MapService = require(script.Parent.MapService)

local PlazaWheel = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- The Lucky Wheel: a big wheel standing on the plaza (it was a HUD button). Standing on its ring opens
-- the spin panel; the badge over it (filled in by client/GambleUi) says how many free spins you have.
-- (the far end of the plaza)
local LUCKY_WHEEL = { Position = Vector3.new(-45, 0, -198), Facing = -130, Color = rgb(255, 90, 190) }
-- (the same wedge picture as the panel's wheel, client/GambleUi)
local WEDGE_IMAGE = "rbxassetid://136440766940606"

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
local function floatingTitle(anchor: BasePart, text: string, color: Color3)
	local title = Instance.new("BillboardGui")
	title.Size = UDim2.fromScale(11, 2.1) -- (studs: shrinks with distance)
	title:SetAttribute("LabelCategory", "Shop")
	title:AddTag("ResponsiveWorldLabel")
	title.MaxDistance = 140
	title.LightInfluence = 0
	title.Adornee = anchor
	title.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	label.Parent = title
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), color:Lerp(Color3.new(1, 1, 1), 0.35))
	gradient.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.65)
	stroke.Parent = label
end

-- The Lucky Wheel on the plaza: two posts, the wheel face (the panel's own wedges and prize names on
-- a round board, turned slowly by client/GambleUi: tag LuckyWheelFace), a pointer at the top,
-- a glowing ring in front (ShopPanel "Spin") and a free-spins badge over it (LuckyWheelBadge)
local function buildLuckyWheel(folder: Instance)
	local spec = LUCKY_WHEEL
	-- (the pen hub: at the far end of the lane, facing back down it towards the safe line)
	local laneEnd = MapService.LuckyWheelAt
	local frame = if laneEnd
		then CFrame.new(laneEnd) * CFrame.Angles(0, math.rad(180), 0)
		else CFrame.new(spec.Position) * CFrame.Angles(0, math.rad(spec.Facing), 0)
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local navy = rgb(32, 36, 60)
	local radius = 6
	local hubY = radius + 2.2
	for _, x in { -radius - 0.6, radius + 0.6 } do
		block(folder, "Post", Vector3.new(1, hubY + 1, 1), at(x, (hubY + 1) / 2, 0.8), navy)
	end
	block(folder, "Axle", Vector3.new(2 * radius + 2.2, 0.8, 0.8), at(0, hubY, 0.8), navy)
	block(folder, "Base", Vector3.new(2 * radius + 4, 0.6, 4), at(0, 0.3, 0.8), navy)
	-- The face: a thin disc (cylinder along local Z), the wedges drawn on its front
	local face = block(
		folder,
		"WheelFace",
		Vector3.new(0.5, 2 * radius, 2 * radius),
		at(0, hubY, 0) * CFrame.Angles(0, math.rad(90), 0),
		Color3.new(1, 1, 1)
	)
	face.Shape = Enum.PartType.Cylinder
	face.CanCollide = false
	local board = block(folder, "WheelBoard", Vector3.new(2 * radius, 2 * radius, 0.05), at(0, hubY, -0.3), navy)
	board.Transparency = 1
	board.CanCollide, board.CanQuery, board.CanTouch = false, false, false
	board:AddTag("LuckyWheelFace")
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.Parent = board
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(1, 1)
	disc.BackgroundColor3 = navy
	disc.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = disc
	local rim = Instance.new("UIStroke")
	rim.Thickness = 10
	rim.Color = rgb(255, 215, 70)
	rim.Parent = disc
	local prizes = GameConfig.Spin.Prizes
	local step = 360 / #prizes
	local colors = { rgb(255, 90, 190), rgb(80, 200, 255), rgb(255, 200, 60), rgb(120, 230, 110) }
	for i, prize in prizes do
		local layer = Instance.new("Frame")
		layer.AnchorPoint = Vector2.new(0.5, 0.5)
		layer.Position = UDim2.fromScale(0.5, 0.5)
		layer.Size = UDim2.fromScale(1, 1)
		layer.Rotation = (i - 1) * step
		layer.BackgroundTransparency = 1
		layer.Parent = disc
		local slice = Instance.new("ImageLabel")
		slice.AnchorPoint = Vector2.new(0.5, 1)
		slice.Position = UDim2.fromScale(0.5, 0.5)
		slice.Size = UDim2.fromScale(2 * 0.48 * math.tan(math.rad(step / 2)), 0.48)
		slice.BackgroundTransparency = 1
		slice.Image = WEDGE_IMAGE
		slice.ImageColor3 = colors[(i - 1) % #colors + 1]
		slice.ScaleType = Enum.ScaleType.Stretch
		slice.Parent = layer
		local text = Instance.new("TextLabel")
		text.AnchorPoint = Vector2.new(0.5, 0)
		text.Position = UDim2.new(0.5, 0, 0, 8)
		text.Size = UDim2.fromScale(0.86, 0.42)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.FredokaOne
		text.TextScaled = true
		text.TextColor3 = Color3.new(1, 1, 1)
		text.Text = prize.Label
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = text
		text.Parent = slice
	end
	local hub = Instance.new("Frame")
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromScale(0.16, 0.16)
	hub.BackgroundColor3 = rgb(255, 215, 70)
	hub.Parent = disc
	local hubCorner = Instance.new("UICorner")
	hubCorner.CornerRadius = UDim.new(0.5, 0)
	hubCorner.Parent = hub
	-- The pointer at the top
	local pointer = block(
		folder,
		"Pointer",
		Vector3.new(1.2, 1.6, 0.8),
		at(0, hubY + radius + 0.4, -0.5) * CFrame.Angles(0, 0, math.rad(45)),
		rgb(255, 60, 60),
		Enum.Material.Neon
	)
	pointer.CanCollide = false
	-- Stand here to spin
	local ring = block(
		folder,
		"GlowRing",
		Vector3.new(0.1, 9, 9),
		at(0, 0.25, -6.5) * CFrame.Angles(0, 0, math.rad(90)),
		spec.Color:Lerp(Color3.new(1, 1, 1), 0.3),
		Enum.Material.Neon
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.55
	ring.CanCollide = false
	ring.CanQuery = false
	ring:SetAttribute("ShopPanel", "Spin")
	ring:AddTag("ShopRing")
	local anchor = block(folder, "TitleAnchor", Vector3.one * 0.2, at(0, hubY + radius + 4.4, 0), spec.Color)
	anchor.Transparency = 1
	anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = false, false, false
	floatingTitle(anchor, "Lucky Wheel", spec.Color)
	-- "🎁 2 FREE SPINS!" low in front of the wheel, clear of the floating titles (client/GambleUi)
	local badgeAnchor = block(folder, "BadgeAnchor", Vector3.one * 0.2, at(0, 2.6, -2.6), spec.Color)
	badgeAnchor.Transparency = 1
	badgeAnchor.CanCollide, badgeAnchor.CanQuery, badgeAnchor.CanTouch = false, false, false
	badgeAnchor:AddTag("LuckyWheelBadge")
end

function PlazaWheel.Init()
	local map = workspace:FindFirstChild("Map")
	local folder = Instance.new("Folder")
	folder.Name = "Shops"
	folder.Parent = map or workspace
	local wheel = Instance.new("Model")
	wheel.Name = "LuckyWheel"
	wheel.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	wheel.Parent = folder
	buildLuckyWheel(wheel)
end

return PlazaWheel
