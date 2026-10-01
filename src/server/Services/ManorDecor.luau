--!strict
-- The look of the hub: Blackwood Manor at night, laid out as one long runway. Each zone is its own
-- biome with a strong colour of its own - moonlit, but vivid and easy to read on a phone:
--   The Courtyard (green)  hedges, a fountain, benches, lanterns
--   The Gardens   (blue)   glowing flowers, a pond, a gazebo, topiary
--   The Crypts    (purple) gravestones, mausoleums, dead trees
--   The Catacombs (gold)   pillars, candelabras, torches, urns
--   The Manor Steps (red)  red carpet, braziers, statues, and the Manor's grand door
-- Plus wall sconces all the way down, a stone arch and title at every zone, the events board
-- over the entrance, the plaza and its giant Void Edge. Purely cosmetic: MapService owns gameplay.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Props = require(ReplicatedStorage.Shared.Props)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)

local ManorDecor = {}

export type Bounds = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }

local IRON = Color3.fromRGB(28, 28, 34)
local STONE = Color3.fromRGB(96, 92, 108)
local DARK_STONE = Color3.fromRGB(62, 60, 72)
local BARK = Color3.fromRGB(52, 42, 38)
local LAMP = Color3.fromRGB(255, 190, 110)
local WINDOW = Color3.fromRGB(255, 205, 120)

local folder: Folder
local rng = Random.new(1337)

local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end

-- Walk-through decoration (keeps the runway clear and saves physics work)
local function ghost(p: Part): Part
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function ball(p: Part): Part
	p.Shape = Enum.PartType.Ball
	return p
end

-- A cylinder standing upright (Roblox cylinders lie along X)
local function cylinderUp(p: Part): Part
	p.Shape = Enum.PartType.Cylinder
	p.CFrame = p.CFrame * CFrame.Angles(0, 0, math.rad(90))
	return p
end

local function glow(p: BasePart, color: Color3, range: number, brightness: number?)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness or 1.2
	light.Shadows = false
	light.Parent = p
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- Shared pieces -------------------------------------------------------------------------------

-- A lantern on an iron bracket, bolted to the runway wall (facing = -1 left wall, 1 right wall)
-- A Blender lantern hanging off an iron bracket on the runway wall, glowing in the zone's colour
local function prop(name: string, cframe: CFrame, scale: number?, recolor: { [string]: Color3 }?): Model
	local model = Props.Build(name, true)
	if scale then
		model:ScaleTo(scale)
	end
	model:PivotTo(cframe)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			if recolor and recolor[d.Name] then
				d.Color = recolor[d.Name]
			end
		end
	end
	model.Parent = folder
	return model
end

local function sconce(x: number, z: number, facing: number, color: Color3)
	block("SconceBracket", Vector3.new(2.2, 0.3, 0.3), at(x - facing * 1, 12.6, z), IRON, Enum.Material.Metal)
	local glassColor = color:Lerp(Color3.fromRGB(255, 220, 160), 0.35)
	local lantern = prop("Lantern", at(x - facing * 2, 11.2, z), 1.3, { Glass = glassColor })
	local glass = (lantern:FindFirstChild("Glass") or lantern.PrimaryPart) :: BasePart
	glow(glass, glassColor, 24, 1.4)
end

local function torch(position: Vector3, color: Color3?)
	block("TorchPost", Vector3.new(0.5, 4, 0.5), CFrame.new(position + Vector3.new(0, 2, 0)), BARK, Enum.Material.Wood)
	local head = ghost(
		block(
			"TorchHead",
			Vector3.new(0.8, 0.8, 0.8),
			CFrame.new(position + Vector3.new(0, 4.3, 0)),
			IRON,
			Enum.Material.Metal
		)
	)
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 6
	fire.Color = color or Color3.fromRGB(255, 140, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 60, 20)
	fire.Parent = head
	glow(head, color or Color3.fromRGB(255, 150, 70), 20, 1.5)
end

local function streetLamp(position: Vector3)
	block(
		"LampPost",
		Vector3.new(0.6, 11, 0.6),
		CFrame.new(position + Vector3.new(0, 5.5, 0)),
		IRON,
		Enum.Material.Metal
	)
	block(
		"LampCap",
		Vector3.new(1.8, 0.4, 1.8),
		CFrame.new(position + Vector3.new(0, 12.6, 0)),
		IRON,
		Enum.Material.Metal
	)
	-- An arm reaching out, with a Blender lantern hanging from it
	block(
		"LampArm",
		Vector3.new(2.6, 0.3, 0.3),
		CFrame.new(position + Vector3.new(1.1, 12.2, 0)),
		IRON,
		Enum.Material.Metal
	)
	local lantern = prop("Lantern", CFrame.new(position + Vector3.new(2.2, 10.9, 0)), 1.2)
	local glass = (lantern:FindFirstChild("Glass") or lantern.PrimaryPart) :: BasePart
	glow(glass, LAMP, 30, 1.5)
end

-- Fireflies drifting over a stretch of ground, and a low mist rolling along it
local function fireflies(center: Vector3, size: Vector3, color: Color3, rate: number)
	local field = ghost(block("Fireflies", size, CFrame.new(center), Color3.new(), Enum.Material.SmoothPlastic))
	field.Transparency = 1
	local flies = Instance.new("ParticleEmitter")
	flies.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	flies.Color = ColorSequence.new(color)
	flies.LightEmission = 1
	flies.Rate = rate
	flies.Lifetime = NumberRange.new(4, 7)
	flies.Speed = NumberRange.new(0.3, 1)
	flies.SpreadAngle = Vector2.new(180, 180)
	flies.RotSpeed = NumberRange.new(-30, 30)
	flies.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.35),
		NumberSequenceKeypoint.new(0.8, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	flies.Parent = field
end

local function mist(center: Vector3, size: Vector3, color: Color3)
	local field = ghost(block("Mist", size, CFrame.new(center), Color3.new(), Enum.Material.SmoothPlastic))
	field.Transparency = 1
	local fog = Instance.new("ParticleEmitter")
	fog.Texture = "rbxasset://textures/particles/smoke_main.dds"
	fog.Color = ColorSequence.new(color)
	fog.LightEmission = 0.2
	fog.Rate = 3
	fog.Lifetime = NumberRange.new(10, 14)
	fog.Speed = NumberRange.new(0.5, 1.5)
	fog.SpreadAngle = Vector2.new(180, 10)
	fog.Size = NumberSequence.new(10, 16)
	fog.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.88),
		NumberSequenceKeypoint.new(0.7, 0.88),
		NumberSequenceKeypoint.new(1, 1),
	})
	fog.Parent = field
end

-- The stone arch over the runway where each zone starts, with its title and colour
local function zoneArch(z: number, width: number, title: string, color: Color3)
	for _, x in { -width / 2 + 2, width / 2 - 2 } do
		block("ArchPillar", Vector3.new(4, 24, 4), at(x, 12, z), STONE, Enum.Material.Cobblestone)
		local cap = ghost(block("ArchLantern", Vector3.new(1.6, 2, 1.6), at(x, 25, z), color, Enum.Material.Neon))
		glow(cap, color, 30, 1.6)
	end
	local beam = block("ArchBeam", Vector3.new(width, 4, 4), at(0, 26, z), DARK_STONE, Enum.Material.Slate)
	ghost(block("ArchStrip", Vector3.new(width - 6, 1, 4.2), at(0, 25.4, z), color, Enum.Material.Neon))
	ghost(block("ZoneLine", Vector3.new(width, 0.25, 1.4), at(0, 0.3, z), color, Enum.Material.Neon))
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 25
		gui.LightInfluence = 0
		gui.Parent = beam
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.Creepster
		text.TextScaled = true
		text.TextColor3 = color
		text.TextStrokeTransparency = 0
		text.Text = title:upper()
		text.Parent = gui
	end
end

-- Biome props ---------------------------------------------------------------------------------

local function hedge(position: Vector3, length: number)
	block(
		"Hedge",
		Vector3.new(length, 3.6, 2.6),
		CFrame.new(position + Vector3.new(0, 1.8, 0)),
		Color3.fromRGB(46, 120, 60),
		Enum.Material.Grass
	)
end

local function fountain(position: Vector3)
	cylinderUp(
		block(
			"Basin",
			Vector3.new(1.6, 12, 12),
			CFrame.new(position + Vector3.new(0, 0.8, 0)),
			STONE,
			Enum.Material.Marble
		)
	)
	local water = cylinderUp(
		ghost(
			block(
				"Water",
				Vector3.new(0.2, 10.6, 10.6),
				CFrame.new(position + Vector3.new(0, 1.55, 0)),
				Color3.fromRGB(70, 150, 230),
				Enum.Material.Glass
			)
		)
	)
	water.Transparency = 0.3
	cylinderUp(
		block(
			"Column",
			Vector3.new(4, 1.4, 1.4),
			CFrame.new(position + Vector3.new(0, 3, 0)),
			STONE,
			Enum.Material.Marble
		)
	)
	local top = ball(
		ghost(
			block(
				"Spout",
				Vector3.one * 1.8,
				CFrame.new(position + Vector3.new(0, 5.2, 0)),
				Color3.fromRGB(150, 210, 255),
				Enum.Material.Neon
			)
		)
	)
	glow(top, Color3.fromRGB(130, 200, 255), 18, 1.4)
end

local function bench(position: Vector3, rotation: number)
	local cf = CFrame.new(position) * CFrame.Angles(0, rotation, 0)
	local wood = Color3.fromRGB(110, 70, 40)
	block("BenchSeat", Vector3.new(6, 0.4, 1.8), cf * CFrame.new(0, 1.6, 0), wood, Enum.Material.Wood)
	block("BenchBack", Vector3.new(6, 1.6, 0.3), cf * CFrame.new(0, 2.6, 0.8), wood, Enum.Material.Wood)
	for _, x in { -2.6, 2.6 } do
		block("BenchLeg", Vector3.new(0.3, 1.6, 1.6), cf * CFrame.new(x, 0.8, 0), IRON, Enum.Material.Metal)
	end
end

local function glowFlower(position: Vector3, color: Color3)
	ghost(
		block(
			"Stem",
			Vector3.new(0.2, 1.6, 0.2),
			CFrame.new(position + Vector3.new(0, 0.8, 0)),
			Color3.fromRGB(40, 110, 60)
		)
	)
	ball(
		ghost(
			block("Bloom", Vector3.one * 0.9, CFrame.new(position + Vector3.new(0, 1.8, 0)), color, Enum.Material.Neon)
		)
	)
end

local function topiary(position: Vector3)
	cylinderUp(
		block(
			"TopiaryPot",
			Vector3.new(1.6, 2.4, 2.4),
			CFrame.new(position + Vector3.new(0, 0.8, 0)),
			Color3.fromRGB(150, 85, 55)
		)
	)
	for i, size in { 3.6, 2.8, 1.8 } do
		ball(
			block(
				"Topiary",
				Vector3.one * size,
				CFrame.new(position + Vector3.new(0, 1 + i * 2.2, 0)),
				Color3.fromRGB(50, 130, 120),
				Enum.Material.Grass
			)
		)
	end
end

local function gazebo(position: Vector3)
	local white = Color3.fromRGB(225, 225, 235)
	cylinderUp(
		block(
			"GazeboFloor",
			Vector3.new(0.6, 16, 16),
			CFrame.new(position + Vector3.new(0, 0.3, 0)),
			white,
			Enum.Material.Marble
		)
	)
	for i = 0, 5 do
		local angle = i * math.pi / 3
		block(
			"GazeboPost",
			Vector3.new(0.6, 9, 0.6),
			CFrame.new(position + Vector3.new(math.cos(angle) * 7, 4.8, math.sin(angle) * 7)),
			white,
			Enum.Material.Marble
		)
	end
	for i = 1, 4 do
		local s = 18 - i * 3.6
		cylinderUp(
			block(
				"GazeboRoof",
				Vector3.new(1, s, s),
				CFrame.new(position + Vector3.new(0, 9 + i * 0.9, 0)),
				Color3.fromRGB(60, 110, 170),
				Enum.Material.Slate
			)
		)
	end
	local lamp = ball(
		ghost(
			block(
				"GazeboLamp",
				Vector3.one * 1.4,
				CFrame.new(position + Vector3.new(0, 7.5, 0)),
				Color3.fromRGB(140, 210, 255),
				Enum.Material.Neon
			)
		)
	)
	glow(lamp, Color3.fromRGB(120, 200, 255), 26, 1.6)
end

local function pond(position: Vector3, sizeX: number, sizeZ: number)
	local water = ghost(
		block(
			"Pond",
			Vector3.new(sizeX, 0.2, sizeZ),
			CFrame.new(position + Vector3.new(0, 0.15, 0)),
			Color3.fromRGB(40, 110, 200),
			Enum.Material.Glass
		)
	)
	water.Transparency = 0.2
	for _ = 1, 4 do
		local offset = Vector3.new(
			rng:NextNumber(-sizeX / 2 + 1, sizeX / 2 - 1),
			0.3,
			rng:NextNumber(-sizeZ / 2 + 1, sizeZ / 2 - 1)
		)
		cylinderUp(
			ghost(
				block("LilyPad", Vector3.new(0.1, 1.6, 1.6), CFrame.new(position + offset), Color3.fromRGB(70, 170, 90))
			)
		)
	end
end

local function gravestone(position: Vector3)
	local tilt = CFrame.Angles(rng:NextNumber(-0.12, 0.12), rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.1, 0.1))
	local base = CFrame.new(position) * tilt
	local color = Color3.fromRGB(120, 110, 140)
	block("Gravestone", Vector3.new(2.4, 3, 0.6), base * CFrame.new(0, 1.5, 0), color, Enum.Material.Slate)
	local top = block(
		"GravestoneTop",
		Vector3.new(0.6, 2.4, 2.4),
		base * CFrame.new(0, 3, 0) * CFrame.Angles(0, math.rad(90), 0),
		color,
		Enum.Material.Slate
	)
	top.Shape = Enum.PartType.Cylinder
end

local function mausoleum(position: Vector3, facing: number)
	local cf = CFrame.new(position) * CFrame.Angles(0, facing, 0)
	block(
		"Mausoleum",
		Vector3.new(10, 9, 10),
		cf * CFrame.new(0, 4.5, 0),
		Color3.fromRGB(90, 70, 120),
		Enum.Material.Slate
	)
	block("MausoleumRoof", Vector3.new(12, 1.5, 12), cf * CFrame.new(0, 9.75, 0), DARK_STONE, Enum.Material.Slate)
	block(
		"MausoleumDoor",
		Vector3.new(3.5, 6, 0.3),
		cf * CFrame.new(0, 3, -5.1),
		Color3.fromRGB(30, 20, 40),
		Enum.Material.Wood
	)
	local eye = ghost(
		block(
			"MausoleumLight",
			Vector3.new(4, 0.6, 0.3),
			cf * CFrame.new(0, 7, -5.15),
			Color3.fromRGB(190, 120, 255),
			Enum.Material.Neon
		)
	)
	glow(eye, Color3.fromRGB(180, 110, 255), 24, 1.6)
end

local function deadTree(position: Vector3)
	local height = rng:NextNumber(10, 15)
	local base = CFrame.new(position)
		* CFrame.Angles(rng:NextNumber(-0.1, 0.1), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.1, 0.1))
	block("Trunk", Vector3.new(1.4, height, 1.4), base * CFrame.new(0, height / 2, 0), BARK, Enum.Material.Wood)
	for i = 1, rng:NextInteger(3, 5) do
		local length = rng:NextNumber(3, 6)
		local branch = base
			* CFrame.new(0, height * rng:NextNumber(0.45, 0.95), 0)
			* CFrame.Angles(0, i * 2.1, 0)
			* CFrame.Angles(0, 0, math.rad(rng:NextNumber(35, 65)))
			* CFrame.new(0, length / 2, 0)
		ghost(block("Branch", Vector3.new(0.6, length, 0.6), branch, BARK, Enum.Material.Wood))
	end
end

local function pillar(position: Vector3)
	local gold = Color3.fromRGB(200, 160, 70)
	block(
		"Pillar",
		Vector3.new(3, 22, 3),
		CFrame.new(position + Vector3.new(0, 11, 0)),
		Color3.fromRGB(150, 130, 100),
		Enum.Material.Marble
	)
	block(
		"PillarBase",
		Vector3.new(4, 1.2, 4),
		CFrame.new(position + Vector3.new(0, 0.6, 0)),
		gold,
		Enum.Material.Metal
	)
	block("PillarCap", Vector3.new(4, 1.2, 4), CFrame.new(position + Vector3.new(0, 22, 0)), gold, Enum.Material.Metal)
end

local function candelabra(position: Vector3)
	local gold = Color3.fromRGB(230, 185, 70)
	block(
		"CandelabraStem",
		Vector3.new(0.5, 6, 0.5),
		CFrame.new(position + Vector3.new(0, 3, 0)),
		gold,
		Enum.Material.Metal
	)
	block(
		"CandelabraArm",
		Vector3.new(4, 0.4, 0.4),
		CFrame.new(position + Vector3.new(0, 5.5, 0)),
		gold,
		Enum.Material.Metal
	)
	for _, x in { -1.8, 0, 1.8 } do
		ghost(
			block(
				"Candle",
				Vector3.new(0.4, 1, 0.4),
				CFrame.new(position + Vector3.new(x, 6.3, 0)),
				Color3.fromRGB(250, 240, 220)
			)
		)
		ghost(
			block(
				"Flame",
				Vector3.new(0.3, 0.5, 0.3),
				CFrame.new(position + Vector3.new(x, 7, 0)),
				Color3.fromRGB(255, 200, 80),
				Enum.Material.Neon
			)
		)
	end
	local light = ghost(block("CandelabraLight", Vector3.one * 0.2, CFrame.new(position + Vector3.new(0, 7, 0)), gold))
	light.Transparency = 1
	glow(light, Color3.fromRGB(255, 200, 100), 24, 1.6)
end

local function urn(position: Vector3)
	local gold = Color3.fromRGB(210, 170, 70)
	ball(
		block(
			"Urn",
			Vector3.new(2.6, 3.2, 2.6),
			CFrame.new(position + Vector3.new(0, 1.8, 0)),
			gold,
			Enum.Material.Metal
		)
	)
	block("UrnNeck", Vector3.new(1.2, 1, 1.2), CFrame.new(position + Vector3.new(0, 3.6, 0)), gold, Enum.Material.Metal)
end

local function brazier(position: Vector3)
	block("BrazierStand", Vector3.new(1, 4, 1), CFrame.new(position + Vector3.new(0, 2, 0)), IRON, Enum.Material.Metal)
	local bowl = block(
		"BrazierBowl",
		Vector3.new(3, 1.2, 3),
		CFrame.new(position + Vector3.new(0, 4.4, 0)),
		IRON,
		Enum.Material.Metal
	)
	local fire = Instance.new("Fire")
	fire.Size = 6
	fire.Heat = 9
	fire.Color = Color3.fromRGB(255, 70, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 30, 60)
	fire.Parent = bowl
	glow(bowl, Color3.fromRGB(255, 70, 60), 30, 2)
end

local function statue(position: Vector3, facing: number)
	local cf = CFrame.new(position) * CFrame.Angles(0, facing, 0)
	local marble = Color3.fromRGB(200, 195, 205)
	block("StatuePlinth", Vector3.new(5, 3, 5), cf * CFrame.new(0, 1.5, 0), DARK_STONE, Enum.Material.Slate)
	block("StatueBody", Vector3.new(2.6, 5, 1.6), cf * CFrame.new(0, 5.5, 0), marble, Enum.Material.Marble)
	block("StatueHead", Vector3.new(1.8, 1.8, 1.8), cf * CFrame.new(0, 8.9, 0), marble, Enum.Material.Marble)
	-- holding a glowing knife up high
	block("StatueArm", Vector3.new(0.8, 3, 0.8), cf * CFrame.new(1.7, 8, 0), marble, Enum.Material.Marble)
	block(
		"StatueKnife",
		Vector3.new(0.3, 4, 1),
		cf * CFrame.new(1.7, 11.4, 0),
		Color3.fromRGB(255, 80, 90),
		Enum.Material.Neon
	)
end

-- The Manor at the end of the runway: a big dark house with lit windows and two towers
local function manor(center: Vector3)
	local wall = Color3.fromRGB(70, 50, 70)
	local roof = Color3.fromRGB(40, 28, 42)
	local W, H, D = 130, 40, 40
	block(
		"ManorBody",
		Vector3.new(W, H, D),
		CFrame.new(center + Vector3.new(0, H / 2, D / 2)),
		wall,
		Enum.Material.Brick
	)
	for _, side in { -1, 1 } do
		block(
			"ManorRoof",
			Vector3.new(W + 4, 1.5, D * 0.62),
			CFrame.new(center + Vector3.new(0, H + 7, D / 2 + side * D * 0.24))
				* CFrame.Angles(math.rad(side * -38), 0, 0),
			roof,
			Enum.Material.Slate
		)
	end
	for _, x in { -W / 2, W / 2 } do
		local tower = center + Vector3.new(x, 0, D / 2)
		block(
			"Tower",
			Vector3.new(16, H + 20, 16),
			CFrame.new(tower + Vector3.new(0, (H + 20) / 2, 0)),
			wall,
			Enum.Material.Brick
		)
		for i = 1, 5 do
			local s = 16 - i * 2.6
			block(
				"Spire",
				Vector3.new(s, 3, s),
				CFrame.new(tower + Vector3.new(0, H + 20 + i * 3, 0)),
				roof,
				Enum.Material.Slate
			)
		end
	end
	for row = 0, 2 do
		for i = 0, 10 do
			local x = -W / 2 + 10 + i * ((W - 20) / 10)
			if math.abs(x) < 10 and row == 0 then
				continue -- the door goes here
			end
			local lit = rng:NextNumber() < 0.7
			local window = ghost(
				block(
					"Window",
					Vector3.new(4, 6, 0.4),
					CFrame.new(center + Vector3.new(x, 8 + row * 11, -0.1)),
					if lit then WINDOW else Color3.fromRGB(25, 25, 35),
					if lit then Enum.Material.Neon else Enum.Material.Glass
				)
			)
			if lit and i % 3 == 0 then
				glow(window, WINDOW, 16, 0.8)
			end
		end
	end
	-- The grand door, glowing red: the deepest point of the runway
	block(
		"ManorDoor",
		Vector3.new(14, 18, 0.6),
		CFrame.new(center + Vector3.new(0, 9, -0.2)),
		Color3.fromRGB(90, 20, 30),
		Enum.Material.Wood
	)
	local doorGlow = ghost(
		block(
			"DoorGlow",
			Vector3.new(12, 1, 0.3),
			CFrame.new(center + Vector3.new(0, 18.5, -0.5)),
			Color3.fromRGB(255, 60, 70),
			Enum.Material.Neon
		)
	)
	glow(doorGlow, Color3.fromRGB(255, 60, 70), 40, 2)
end

-- The board over the runway entrance; the client fills in the countdowns (Hud)
local function eventBoard(z: number, width: number)
	for _, x in { -width / 2 + 3, width / 2 - 3 } do
		block("BoardChain", Vector3.new(0.4, 6, 0.4), at(x, 31, z), IRON, Enum.Material.Metal)
	end
	block(
		"EventBoardFrame",
		Vector3.new(width - 6, 11, 0.8),
		at(0, 25, z + 0.3),
		Color3.fromRGB(90, 60, 35),
		Enum.Material.Wood
	)
	local board =
		block("EventBoard", Vector3.new(width - 8, 10, 1), at(0, 25, z), Color3.fromRGB(25, 22, 32), Enum.Material.Wood)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = `Lines{face.Name}`
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.LightInfluence = 0
		gui.Parent = board
		local layout = Instance.new("UIListLayout")
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.Padding = UDim.new(0, 6)
		layout.Parent = gui
		for i = 1, 3 do
			local line = Instance.new("TextLabel")
			line.Name = `Line{i}`
			line.LayoutOrder = i
			line.Size = UDim2.fromScale(0.95, 0.26)
			line.BackgroundTransparency = 1
			line.Font = Enum.Font.FredokaOne
			line.TextScaled = true
			line.TextColor3 = Color3.new(1, 1, 1)
			line.TextStrokeTransparency = 0.3
			line.Text = ""
			line.Parent = gui
		end
	end
end

-- Build -----------------------------------------------------------------------------------------

function ManorDecor.Build(root: Instance, arena: Bounds, hideaways: { Bounds })
	folder = Instance.new("Folder")
	folder.Name = "Decor"
	folder.Parent = root
	local width = arena.MaxX - arena.MinX
	local depth = GameConfig.ZoneDepth
	local half = width / 2

	-- Every zone: arch + title at its start, sconces down both walls, its own biome inside
	for i, zone in GameConfig.Zones do
		local z0 = (i - 1) * depth
		local color: Color3 = zone.Color
		local need = (zone :: any).SpeedNeeded or 0
		local needText = if need <= 0
			then ""
			elseif need >= 1e6 then ` · {need / 1e6}M SPEED`
			else ` · {need // 1000}K SPEED`
		zoneArch(z0 + 3, width, ((zone :: any).Title or zone.Rarity) .. needText, color)
		-- Fireflies in the zone's colour, and mist creeping along the ground
		fireflies(
			Vector3.new(0, 5, z0 + depth / 2),
			Vector3.new(width - 6, 8, depth - 10),
			color:Lerp(Color3.fromRGB(230, 255, 150), 0.5),
			6
		)
		mist(Vector3.new(0, 1.5, z0 + depth / 2), Vector3.new(width - 4, 1, depth - 6), Color3.fromRGB(150, 140, 190))
		for z = z0 + 18, z0 + depth - 10, 35 do
			sconce(-half, z, -1, color)
			sconce(half, z, 1, color)
		end
		-- Somewhere off the middle of the runway, so the run home stays fairly clear
		local function spot(): Vector3
			local x = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(10, half - 5)
			return Vector3.new(x, 0, z0 + rng:NextNumber(20, depth - 15))
		end
		if zone.Rarity == "Common" then
			for z = z0 + 30, z0 + depth - 30, 45 do
				hedge(Vector3.new(-half + 6, 0, z), 14)
				hedge(Vector3.new(half - 6, 0, z + 20), 14)
			end
			fountain(Vector3.new(0, 0, z0 + depth * 0.5))
			for _ = 1, 4 do
				bench(spot(), rng:NextNumber(0, math.pi * 2))
			end
			for _ = 1, 4 do
				streetLamp(spot())
			end
		elseif zone.Rarity == "Rare" then
			gazebo(Vector3.new(-half + 14, 0, z0 + depth * 0.4))
			pond(Vector3.new(half - 14, 0, z0 + depth * 0.65), 18, 26)
			for _ = 1, 6 do
				topiary(spot())
			end
			local colors =
				{ Color3.fromRGB(90, 200, 255), Color3.fromRGB(150, 120, 255), Color3.fromRGB(255, 140, 220) }
			for _ = 1, 40 do
				glowFlower(spot() + Vector3.new(rng:NextNumber(-3, 3), 0, 0), colors[rng:NextInteger(1, #colors)])
			end
		elseif zone.Rarity == "Epic" then
			mausoleum(Vector3.new(-half + 9, 0, z0 + depth * 0.3), math.rad(-90))
			mausoleum(Vector3.new(half - 9, 0, z0 + depth * 0.7), math.rad(90))
			for _ = 1, 22 do
				gravestone(spot())
			end
			for _ = 1, 5 do
				deadTree(spot())
			end
		elseif zone.Rarity == "Legendary" then
			for z = z0 + 25, z0 + depth - 20, 40 do
				pillar(Vector3.new(-half + 6, 0, z))
				pillar(Vector3.new(half - 6, 0, z))
			end
			for _ = 1, 6 do
				candelabra(spot())
			end
			for _ = 1, 8 do
				urn(spot())
			end
			for _ = 1, 6 do
				torch(spot(), Color3.fromRGB(255, 190, 60))
			end
		elseif zone.Rarity == "Godly" then
			ghost(
				block(
					"RedCarpet",
					Vector3.new(12, 0.1, depth - 10),
					at(0, 0.25, z0 + depth / 2 + 5),
					Color3.fromRGB(150, 20, 35),
					Enum.Material.Fabric
				)
			)
			for z = z0 + 25, z0 + depth - 15, 32 do
				brazier(Vector3.new(-11, 0, z))
				brazier(Vector3.new(11, 0, z))
			end
			for z = z0 + 40, z0 + depth - 30, 60 do
				statue(Vector3.new(-half + 6, 0, z), math.rad(90))
				statue(Vector3.new(half - 6, 0, z), math.rad(-90))
			end
		end
	end

	-- Hideaways: a candle with a purple flame in each nook, so they're easy to spot from the runway
	for _, h in hideaways do
		local x = (h.MinX + h.MaxX) / 2 + (if h.MinX > 0 then 3 else -3)
		local z = (h.MinZ + h.MaxZ) / 2
		ghost(block("HideawayCandle", Vector3.new(0.5, 1.2, 0.5), at(x, 0.6, z), Color3.fromRGB(250, 240, 220)))
		local flame = ghost(
			block(
				"HideawayFlame",
				Vector3.new(0.4, 0.6, 0.4),
				at(x, 1.5, z),
				Color3.fromRGB(200, 140, 255),
				Enum.Material.Neon
			)
		)
		glow(flame, Color3.fromRGB(180, 120, 255), 14, 1.4)
	end

	-- The entrance: events board hanging over the start of the runway
	eventBoard(-4, width)

	-- The plaza: lamps along both sides, the giant Void Edge at the back, fireflies everywhere
	fireflies(Vector3.new(0, 6, -95), Vector3.new(width - 6, 10, 170), Color3.fromRGB(255, 230, 140), 10)
	for z = -30, -150, -40 do
		streetLamp(Vector3.new(-half + 4, 0, z))
		streetLamp(Vector3.new(half - 4, 0, z))
	end
	local plinth = block("Plinth", Vector3.new(10, 6, 10), at(0, 3, -178), DARK_STONE, Enum.Material.Slate)
	glow(plinth, Color3.fromRGB(170, 70, 255), 30, 2)
	local statueKnife = KnifeModel.Build("VoidEdge", true)
	statueKnife:ScaleTo(7)
	statueKnife:PivotTo(CFrame.new(0, 6 + 7 * 0.9, -178) * CFrame.Angles(0, math.rad(90), 0))
	statueKnife.Name = "Statue"
	statueKnife.Parent = folder
	for _, x in { -8, 8 } do
		torch(Vector3.new(x, 0, -172))
	end
	block("PlazaWall", Vector3.new(width + 12, 34, 6), at(0, 17, -191), STONE, Enum.Material.Cobblestone)

	manor(Vector3.new(0, 0, arena.MaxZ + 6))

	-- Dead trees peeking over the walls, outside the runway
	for z = -150, arena.MaxZ, 60 do
		for _, side in { -1, 1 } do
			deadTree(Vector3.new(side * rng:NextNumber(half + 60, half + 120), 0, z + rng:NextNumber(-20, 20)))
		end
	end
end

return ManorDecor
