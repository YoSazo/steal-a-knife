--!strict
-- A vault's frame and laser gate for its wall tier (GameConfig.Walls). Vaults are open platforms
-- (like the Tsunami steal games): navy corner posts and beams, a low glass rail, and invisible walls
-- around it, so the whole plaza can see what everyone has. Better tiers get more laser lines, a
-- brighter accent colour and fancier post tops, so the plaza still shows off who's doing well.
-- Everything is built in the vault's own frame (local +Z = the open side facing the plaza). The
-- gate's invisible "Blocker" is what raiders hit and what clients make solid for everyone but the
-- owner (see client/Raid, which also fades the "Pane" lasers as the gate loses health). Gate state
-- lives in attributes on the Blocker: Owner, Health, MaxHealth, Open, Tier.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Props = require(ReplicatedStorage.Shared.Props)
local Toy = require(ReplicatedStorage.Shared.Toy)

local VaultWalls = {}

local HALF_W, HALF_D = 20, 22 -- vault is 40 wide, 44 deep
local T = 1 -- rail thickness
local POST = 1.8
local GATE_HALF = 8 -- gate opening is 16 wide
local GATE_H = 11
local FLOOR_H = 16 -- MapService.FloorHeight
local RAIL_H = 3.5
-- The front's invisible wall stops just under the first deck: too high to jump in from the plaza,
-- but from the upper floors you can jump out over the rail (the sides stay full height, so you
-- can't walk into the next vault)
local FRONT_H = 15
local NAVY = Color3.fromRGB(40, 44, 90)
local GLASS = Color3.fromRGB(190, 240, 255)

export type Built = {
	Gate: Model,
	Blocker: Part,
	Height: number,
	BackHeight: number,
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

local function deco(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = block(parent, name, size, cframe, color, material)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- Builds (or rebuilds) a vault's frame into `folder`. `color` is the vault's own colour (the strip
-- along the base and the gate's health bar), `tierIndex` its wall tier.
function VaultWalls.Build(folder: Folder, frame: CFrame, color: Color3, tierIndex: number, floors: number?): Built
	folder:ClearAllChildren()
	-- The frame rises with the vault: up past the top floor's railing
	local floorCount = floors or 1
	local FRAME_H = floorCount * FLOOR_H + 4
	local WALL_H = math.max(44, FRAME_H + 16) -- the invisible walls: nobody climbs or jumps out over them
	local tier = GameConfig.Walls[math.clamp(tierIndex, 1, #GameConfig.Walls)]
	local accent = tier.Trim
	local frameColor = NAVY:Lerp(tier.Color, 0.25)
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end

	-- Invisible walls on every side but the gate: you can see in, you can't walk in
	local function invisible(name: string, size: Vector3, cframe: CFrame)
		local p = block(folder, name, size, cframe, Color3.new(), nil)
		p.Transparency = 1
		p.CastShadow = false
		p.CanTouch = false
	end
	invisible("BackWall", Vector3.new(HALF_W * 2, WALL_H, T), at(0, WALL_H / 2, -HALF_D + T / 2))
	for _, side in { -1, 1 } do
		invisible("SideWall", Vector3.new(T, WALL_H, HALF_D * 2), at(side * (HALF_W - T / 2), WALL_H / 2, 0))
		local frontLength = HALF_W - GATE_HALF
		invisible(
			"FrontWall",
			Vector3.new(frontLength, FRONT_H, T),
			at(side * (GATE_HALF + frontLength / 2), FRONT_H / 2, HALF_D - T / 2)
		)
	end
	invisible(
		"Lintel",
		Vector3.new(GATE_HALF * 2, FRONT_H - GATE_H, T),
		at(0, GATE_H + (FRONT_H - GATE_H) / 2, HALF_D - T / 2)
	)

	-- The low glass rail and its navy cap all the way round (gate excluded)
	local function rail(from: Vector3, to: Vector3)
		local mid = (from + to) / 2
		local length = (to - from).Magnitude
		local cf = frame * CFrame.lookAt(mid, to)
		local glass = deco(
			folder,
			"Rail",
			Vector3.new(0.4, RAIL_H, length),
			cf * CFrame.new(0, RAIL_H / 2 + 0.6, 0),
			GLASS,
			Enum.Material.Glass
		)
		glass.Transparency = 0.6
		glass.CastShadow = false
		deco(folder, "RailCap", Vector3.new(0.8, 0.5, length), cf * CFrame.new(0, RAIL_H + 0.85, 0), frameColor)
		-- The owner's colour along the bottom, so you can spot your own vault
		deco(folder, "Strip", Vector3.new(0.9, 0.4, length), cf * CFrame.new(0, 0.85, 0), color)
	end
	local inX, inZ = HALF_W - T / 2, HALF_D - T / 2
	rail(Vector3.new(-inX, 0, -inZ), Vector3.new(inX, 0, -inZ))
	for _, side in { -1, 1 } do
		rail(Vector3.new(side * inX, 0, -inZ), Vector3.new(side * inX, 0, inZ))
		rail(Vector3.new(side * (GATE_HALF + POST), 0, inZ), Vector3.new(side * inX, 0, inZ))
	end

	-- Navy corner posts and beams at each floor level: an open shelf you can see straight into
	local posts: { CFrame } = {}
	for _, x in { -inX, inX } do
		for _, z in { -inZ, inZ } do
			local cf = at(x, FRAME_H / 2, z)
			local post = deco(folder, "Post", Vector3.new(POST, FRAME_H, POST), cf, frameColor)
			Toy.Dress(post, Toy.Sides, 1, 0)
			table.insert(posts, cf * CFrame.new(0, FRAME_H / 2, 0))
		end
	end
	local levels: { number } = {}
	for k = 1, floorCount - 1 do
		table.insert(levels, k * FLOOR_H)
	end
	table.insert(levels, FRAME_H)
	for _, y in levels do
		for _, side in { -1, 1 } do
			deco(folder, "Beam", Vector3.new(POST * 0.7, 1, HALF_D * 2), at(side * inX, y - 0.5, 0), frameColor)
		end
		deco(folder, "Beam", Vector3.new(HALF_W * 2, 1, POST * 0.7), at(0, y - 0.5, -inZ), frameColor)
		if y == FRAME_H then
			deco(folder, "Beam", Vector3.new(HALF_W * 2, 1, POST * 0.7), at(0, y - 0.5, inZ), frameColor)
		end
	end
	-- Post tops: plain caps, glowing caps from tier 3, spinning crystals from tier 5
	for _, cf in posts do
		local cap = deco(
			folder,
			"PostCap",
			Vector3.new(POST + 0.6, 0.8, POST + 0.6),
			cf * CFrame.new(0, 0.4, 0),
			if tierIndex >= 3 then accent else Color3.new(1, 1, 1),
			if tierIndex >= 3 then Enum.Material.Neon else Enum.Material.SmoothPlastic
		)
		if tierIndex >= 5 then
			local crystal = Props.Build("Crystal", true)
			crystal:ScaleTo(1.2)
			crystal:PivotTo(cap.CFrame * CFrame.new(0, 0.4, 0))
			for _, d in crystal:GetDescendants() do
				if d:IsA("BasePart") then
					d.Color = accent
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
				end
			end
			crystal:AddTag("Spin")
			crystal.Parent = folder
		end
		if tierIndex >= 7 then
			local sparkle = Instance.new("ParticleEmitter")
			sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sparkle.Color = ColorSequence.new(accent, Color3.new(1, 1, 1))
			sparkle.LightEmission = 1
			sparkle.Rate = 4
			sparkle.Lifetime = NumberRange.new(1, 1.6)
			sparkle.Speed = NumberRange.new(1, 2)
			sparkle.SpreadAngle = Vector2.new(180, 180)
			sparkle.Size = NumberSequence.new(0.6, 0)
			sparkle.Parent = cap
		end
	end

	-- The gate: two posts with laser emitters and lines of light across the opening (more lines on
	-- better tiers). Broken gates switch the lasers off (SetOpen).
	local gate = Instance.new("Model")
	gate.Name = "Gate"
	local gateZ = HALF_D - T / 2
	for _, side in { -1, 1 } do
		local post = deco(
			gate,
			"GatePost",
			Vector3.new(POST, GATE_H + 1, POST),
			at(side * (GATE_HALF + POST / 2), (GATE_H + 1) / 2, gateZ),
			frameColor
		)
		Toy.Dress(post, Toy.Sides, 1, 0)
		post:SetAttribute("Keep", true)
		deco(
			gate,
			"GateTop",
			Vector3.new(POST + 0.5, 0.8, POST + 0.5),
			at(side * (GATE_HALF + POST / 2), GATE_H + 1.4, gateZ),
			accent,
			Enum.Material.Neon
		):SetAttribute("Keep", true)
	end
	local lines = math.clamp(tierIndex + 2, 3, 10)
	for i = 1, lines do
		local y = 0.9 + (i - 1) * (GATE_H - 1.4) / (lines - 1)
		local laser =
			deco(gate, "Pane", Vector3.new(GATE_HALF * 2, 0.22, 0.22), at(0, y, gateZ), accent, Enum.Material.Neon)
		laser.Transparency = 0.15
	end
	-- What actually blocks (on clients) and what raiders hit
	local blocker =
		block(gate, "Blocker", Vector3.new(GATE_HALF * 2, GATE_H, 1.2), at(0, GATE_H / 2, gateZ), Color3.new(), nil)
	blocker.Transparency = 1
	blocker.CanCollide = false -- each client decides (the owner walks through, everyone else bumps)
	blocker.CanQuery = true
	blocker.CanTouch = false
	blocker:AddTag("VaultGate")
	for _, d in gate:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("BaseTransparency", d.Transparency)
		end
	end
	-- Health bar, shown during raids
	local gui = Instance.new("BillboardGui")
	gui.Name = "GateHealth"
	gui.Size = UDim2.fromOffset(200, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, GATE_H / 2 + 2.6, 0)
	gui.MaxDistance = 160
	gui.Enabled = false
	gui.Adornee = blocker
	gui.Parent = blocker
	local name = Instance.new("TextLabel")
	name.Name = "Title"
	name.Size = UDim2.new(1, 0, 0, 20)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0
	name.Text = tier.Name
	name.Parent = gui
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Position = UDim2.fromOffset(0, 24)
	back.Size = UDim2.new(1, 0, 0, 16)
	back.BackgroundColor3 = Color3.fromRGB(30, 20, 30)
	back.BorderSizePixel = 0
	back.Parent = gui
	Instance.new("UICorner").Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	Instance.new("UICorner").Parent = fill
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(20, 16, 24)
	stroke.Parent = back
	gate.PrimaryPart = blocker
	gate.Parent = folder

	blocker:SetAttribute("Tier", tierIndex)
	blocker:SetAttribute("MaxHealth", tier.GateHealth)
	blocker:SetAttribute("Health", tier.GateHealth)
	blocker:SetAttribute("Floors", floorCount)
	return { Gate = gate, Blocker = blocker, Height = FRAME_H, BackHeight = FRAME_H }
end

-- Broken gates: the lasers switch off (and come back when it reforges); the posts stay
function VaultWalls.SetOpen(gate: Model, open: boolean)
	for _, d in gate:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Blocker" and not d:GetAttribute("Keep") then
			local base = d:GetAttribute("BaseTransparency")
			d.Transparency = if open then 1 else (if type(base) == "number" then base else 0)
		end
	end
	local blocker = gate:FindFirstChild("Blocker")
	if blocker then
		blocker:SetAttribute("Open", open or nil)
	end
end

return VaultWalls
