--!strict
-- The look of the hub: Blackwood Manor at night, laid out as one long runway. Each zone is its own
-- biome with a strong colour of its own - moonlit, but vivid and easy to read on a phone:
--   The Courtyard (green)  hedges, a fountain, benches, lanterns
--   The Gardens   (blue)   glowing flowers, a pond, a gazebo, topiary
--   The Crypts    (purple) gravestones, mausoleums, dead trees
--   The Catacombs (gold)   pillars, candelabras, torches, urns
--   The Inferno   (orange) lava pools, obsidian spires, fire vents
--   Mount Olympus (pink)   a marble temple, gold god statues, columns, braziers
--   The Heavens   (cyan)   clouds, angel statues, light shafts, the pearly gates
--   Outer Space   (violet) planets in the sky, asteroids, crystals, stars
-- Plus wall sconces all the way down, a stone arch and title at every zone, the events board
-- over the entrance, the plaza and its giant Void Edge. Purely cosmetic: MapService owns gameplay.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Props = require(ReplicatedStorage.Shared.Props)
local Toy = require(ReplicatedStorage.Shared.Toy)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)

local ManorDecor = {}

export type Bounds = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }

local IRON = Color3.fromRGB(28, 28, 34)
local DARK_STONE = Color3.fromRGB(62, 60, 72)
local BARK = Color3.fromRGB(52, 42, 38)
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

-- A blocky cartoon bush (Steal An Egg style): a couple of stacked stud-covered green blocks
local function bush(position: Vector3, scale: number?)
	local k = scale or 1
	local green = Toy.Grass:Lerp(Color3.new(0, 0, 0), 0.12 + rng:NextNumber(0, 0.08))
	local w = rng:NextNumber(5, 8) * k
	local d = rng:NextNumber(4, 6) * k
	local h = rng:NextNumber(3, 4) * k
	local turn = CFrame.Angles(0, math.rad(rng:NextInteger(0, 3) * 90), 0)
	local base = block("Bush", Vector3.new(w, h, d), CFrame.new(position + Vector3.new(0, h / 2, 0)) * turn, green)
	Toy.Dress(base, Toy.Sides, 1, 0)
	local top = block(
		"Bush",
		Vector3.new(w * 0.6, h * 0.8, d * 0.7),
		CFrame.new(position + Vector3.new(rng:NextNumber(-1, 1) * k, h + h * 0.4, 0)) * turn,
		green:Lerp(Color3.new(1, 1, 1), 0.05)
	)
	Toy.Dress(top, Toy.Sides, 1, 0)
end

local function sconce(_x: number, _z: number, _facing: number, _color: Color3)
	-- (daytime: no wall lanterns)
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
	bush(position)
end

-- Fireflies drifting over a stretch of ground, and a low mist rolling along it
local function fireflies(_center: Vector3, _size: Vector3, _color: Color3, _rate: number)
	-- (daytime: no fireflies)
end

local function mist(_center: Vector3, _size: Vector3, _color: Color3)
	-- (daytime: no mist)
end

-- Biome props ---------------------------------------------------------------------------------

local function hedge(position: Vector3, length: number)
	for x = -length / 2 + 3, length / 2 - 3, 7 do
		bush(position + Vector3.new(x, 0, 0), 0.9)
	end
end

local function fountain(position: Vector3)
	bush(position, 1.4)
end

local function bench(position: Vector3, _rotation: number)
	bush(position)
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

-- The Inferno ---------------------------------------------------------------------------------

local LAVA = Color3.fromRGB(255, 90, 20)
local OBSIDIAN = Color3.fromRGB(28, 18, 22)

-- A glowing lava pool sunk into the floor (walk over it: it's only scenery)
local function lavaPool(position: Vector3, sizeX: number, sizeZ: number)
	local rim = block(
		"LavaRim",
		Vector3.new(sizeX + 3, 0.6, sizeZ + 3),
		CFrame.new(position + Vector3.new(0, 0.3, 0)),
		OBSIDIAN,
		Enum.Material.Basalt
	)
	rim.CanCollide = false
	local lava = ghost(
		block(
			"Lava",
			Vector3.new(sizeX, 0.3, sizeZ),
			CFrame.new(position + Vector3.new(0, 0.55, 0)),
			LAVA,
			Enum.Material.Neon
		)
	)
	glow(lava, Color3.fromRGB(255, 110, 40), math.max(sizeX, sizeZ) + 14, 2.2)
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 60, 20))
	embers.LightEmission = 1
	embers.Size = NumberSequence.new(0.35, 0)
	embers.Lifetime = NumberRange.new(1.5, 3)
	embers.Rate = sizeX * sizeZ / 30
	embers.Speed = NumberRange.new(3, 7)
	embers.SpreadAngle = Vector2.new(20, 20)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Parent = lava
end

-- A jagged obsidian spire with glowing cracks
local function obsidianSpire(position: Vector3)
	local height = rng:NextNumber(8, 18)
	local cf = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-8, 8)))
	block("Spire", Vector3.new(4, height, 4), cf * CFrame.new(0, height / 2, 0), OBSIDIAN, Enum.Material.Basalt)
	block(
		"SpireTip",
		Vector3.new(2.4, height * 0.4, 2.4),
		cf * CFrame.new(0.4, height + height * 0.15, 0),
		OBSIDIAN,
		Enum.Material.Basalt
	)
	ghost(
		block(
			"SpireCrack",
			Vector3.new(0.3, height * 0.8, 4.1),
			cf * CFrame.new(0.6, height * 0.5, 0),
			LAVA,
			Enum.Material.Neon
		)
	)
end

-- A vent that coughs flames up out of the floor
local function fireVent(position: Vector3)
	local grate = block(
		"FireVent",
		Vector3.new(4, 0.5, 4),
		CFrame.new(position + Vector3.new(0, 0.25, 0)),
		IRON,
		Enum.Material.DiamondPlate
	)
	grate.CanCollide = false
	local fire = Instance.new("Fire")
	fire.Size = 8
	fire.Heat = 18
	fire.Color = Color3.fromRGB(255, 120, 30)
	fire.SecondaryColor = Color3.fromRGB(255, 40, 10)
	fire.Parent = grate
	glow(grate, Color3.fromRGB(255, 100, 40), 26, 2)
end

-- Mount Olympus ---------------------------------------------------------------------------------

local MARBLE = Color3.fromRGB(240, 236, 226)
local GOLD = Color3.fromRGB(255, 205, 70)

-- A tall white temple column with gold bands
local function olympusColumn(position: Vector3, height: number)
	cylinderUp(
		block(
			"Column",
			Vector3.new(height, 4, 4),
			CFrame.new(position + Vector3.new(0, height / 2, 0)),
			MARBLE,
			Enum.Material.Marble
		)
	)
	block(
		"ColumnBase",
		Vector3.new(5.5, 1.4, 5.5),
		CFrame.new(position + Vector3.new(0, 0.7, 0)),
		MARBLE,
		Enum.Material.Marble
	)
	block(
		"ColumnCap",
		Vector3.new(5.5, 1.4, 5.5),
		CFrame.new(position + Vector3.new(0, height, 0)),
		MARBLE,
		Enum.Material.Marble
	)
	ghost(
		block(
			"ColumnBand",
			Vector3.new(5.6, 0.4, 5.6),
			CFrame.new(position + Vector3.new(0, height - 1, 0)),
			GOLD,
			Enum.Material.Metal
		)
	)
	ghost(
		block(
			"ColumnBand",
			Vector3.new(5.6, 0.4, 5.6),
			CFrame.new(position + Vector3.new(0, 1.6, 0)),
			GOLD,
			Enum.Material.Metal
		)
	)
end

-- A ruined temple: a stepped plinth, a ring of columns, a gold roof edge
local function temple(position: Vector3)
	for i = 0, 2 do
		block(
			"TempleStep",
			Vector3.new(30 - i * 3, 1, 22 - i * 3),
			CFrame.new(position + Vector3.new(0, 0.5 + i, 0)),
			MARBLE,
			Enum.Material.Marble
		)
	end
	for _, x in { -11, -5.5, 0, 5.5, 11 } do
		for _, z in { -7, 7 } do
			olympusColumn(position + Vector3.new(x, 3, z), 16)
		end
	end
	block(
		"TempleRoof",
		Vector3.new(30, 2, 20),
		CFrame.new(position + Vector3.new(0, 20, 0)),
		MARBLE,
		Enum.Material.Marble
	)
	block(
		"TempleTrim",
		Vector3.new(30.4, 0.8, 20.4),
		CFrame.new(position + Vector3.new(0, 19, 0)),
		GOLD,
		Enum.Material.Metal
	)
	local wedge = Instance.new("WedgePart")
	wedge.Name = "Pediment"
	wedge.Anchored = true
	wedge.Size = Vector3.new(30, 5, 10)
	wedge.Color = MARBLE
	wedge.Material = Enum.Material.Marble
	wedge.CFrame = CFrame.new(position + Vector3.new(0, 23.5, -5))
	wedge.Parent = folder
	local back = wedge:Clone()
	back.CFrame = CFrame.new(position + Vector3.new(0, 23.5, 5)) * CFrame.Angles(0, math.pi, 0)
	back.Parent = folder
	-- A golden thunderbolt over the door
	local bolt = ghost(
		block(
			"Thunderbolt",
			Vector3.new(1, 6, 0.4),
			CFrame.new(position + Vector3.new(0, 15, -10.5)) * CFrame.Angles(0, 0, math.rad(20)),
			GOLD,
			Enum.Material.Neon
		)
	)
	glow(bolt, Color3.fromRGB(255, 230, 120), 30, 2)
end

-- A golden god statue on a marble plinth
local function godStatue(position: Vector3, facing: number)
	local cf = CFrame.new(position) * CFrame.Angles(0, facing, 0)
	block("GodPlinth", Vector3.new(6, 4, 6), cf * CFrame.new(0, 2, 0), MARBLE, Enum.Material.Marble)
	block("GodLegs", Vector3.new(2.6, 4, 1.6), cf * CFrame.new(0, 6, 0), GOLD, Enum.Material.Metal)
	block("GodBody", Vector3.new(3.4, 4, 2), cf * CFrame.new(0, 10, 0), GOLD, Enum.Material.Metal)
	block("GodHead", Vector3.new(2, 2, 2), cf * CFrame.new(0, 13, 0), GOLD, Enum.Material.Metal)
	block("GodArm", Vector3.new(0.9, 4, 0.9), cf * CFrame.new(2.2, 13, 0), GOLD, Enum.Material.Metal)
	local bolt = ghost(
		block(
			"GodBolt",
			Vector3.new(0.5, 5, 0.5),
			cf * CFrame.new(2.2, 17, 0) * CFrame.Angles(0, 0, math.rad(15)),
			Color3.fromRGB(255, 250, 150),
			Enum.Material.Neon
		)
	)
	glow(bolt, Color3.fromRGB(255, 240, 150), 22, 1.6)
end

-- The Heavens ----------------------------------------------------------------------------------

local CLOUD = Color3.fromRGB(250, 250, 255)

-- A puffy cloud: a few overlapping white balls
local function cloud(position: Vector3, scale: number)
	for _ = 1, 5 do
		local size = rng:NextNumber(5, 9) * scale
		local p = ghost(
			ball(
				block(
					"Cloud",
					Vector3.one * size,
					CFrame.new(
						position
							+ Vector3.new(
								rng:NextNumber(-6, 6) * scale,
								rng:NextNumber(-1, 2) * scale,
								rng:NextNumber(-4, 4) * scale
							)
					),
					CLOUD,
					Enum.Material.SmoothPlastic
				)
			)
		)
		p.Transparency = 0.15
		p.CastShadow = false
	end
end

-- An angel statue: white body, gold halo, two big wings
local function angelStatue(position: Vector3, facing: number)
	local cf = CFrame.new(position) * CFrame.Angles(0, facing, 0)
	block("AngelPlinth", Vector3.new(5, 3, 5), cf * CFrame.new(0, 1.5, 0), MARBLE, Enum.Material.Marble)
	block("AngelRobe", Vector3.new(2.8, 6, 1.8), cf * CFrame.new(0, 6, 0), MARBLE, Enum.Material.Marble)
	block("AngelHead", Vector3.new(1.8, 1.8, 1.8), cf * CFrame.new(0, 10, 0), MARBLE, Enum.Material.Marble)
	local halo = ghost(
		block(
			"Halo",
			Vector3.new(0.3, 2.4, 2.4),
			cf * CFrame.new(0, 11.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
			GOLD,
			Enum.Material.Neon
		)
	)
	halo.Shape = Enum.PartType.Cylinder
	glow(halo, Color3.fromRGB(255, 230, 140), 18, 1.5)
	for _, side in { -1, 1 } do
		for i = 0, 2 do
			block(
				"Wing",
				Vector3.new(0.4, 5 - i, 2.2),
				cf
					* CFrame.new(side * (2 + i * 1.3), 8 + i * 0.6, 1)
					* CFrame.Angles(0, 0, math.rad(side * (-25 - i * 15))),
				Color3.fromRGB(255, 255, 255),
				Enum.Material.SmoothPlastic
			)
		end
	end
end

-- A shaft of light falling from the sky
local function lightPillar(position: Vector3)
	local shaft = ghost(
		block(
			"LightShaft",
			Vector3.new(8, 60, 8),
			CFrame.new(position + Vector3.new(0, 30, 0)),
			Color3.fromRGB(255, 245, 200),
			Enum.Material.Neon
		)
	)
	shaft.Transparency = 0.85
	shaft.CastShadow = false
	glow(shaft, Color3.fromRGB(255, 240, 190), 30, 1.2)
end

-- Pearly gates: two gold-trimmed white pillars and an arch of bars
local function pearlyGates(position: Vector3)
	for _, x in { -14, 14 } do
		block(
			"GatePillar",
			Vector3.new(4, 20, 4),
			CFrame.new(position + Vector3.new(x, 10, 0)),
			MARBLE,
			Enum.Material.Marble
		)
		ghost(
			block("GateOrb", Vector3.one * 3, CFrame.new(position + Vector3.new(x, 21.5, 0)), GOLD, Enum.Material.Neon)
		).Shape =
			Enum.PartType.Ball
	end
	for x = -11, 11, 2.75 do
		local h = 16 + math.cos(x / 11 * math.pi / 2) * 4
		ghost(
			block(
				"GateBar",
				Vector3.new(0.5, h, 0.5),
				CFrame.new(position + Vector3.new(x, h / 2, 0)),
				GOLD,
				Enum.Material.Metal
			)
		)
	end
end

-- Outer Space ----------------------------------------------------------------------------------

-- A planet hanging in the sky over the runway (optionally ringed)
local function planet(position: Vector3, size: number, color: Color3, ringed: boolean)
	local body =
		ghost(ball(block("Planet", Vector3.one * size, CFrame.new(position), color, Enum.Material.SmoothPlastic)))
	body.CastShadow = false
	glow(body, color, size * 1.2, 0.8)
	if ringed then
		local ring = ghost(
			block(
				"PlanetRing",
				Vector3.new(0.4, size * 1.9, size * 1.9),
				CFrame.new(position) * CFrame.Angles(math.rad(20), 0, math.rad(90 - 15)),
				color:Lerp(Color3.new(1, 1, 1), 0.4),
				Enum.Material.Neon
			)
		)
		ring.Shape = Enum.PartType.Cylinder
		ring.Transparency = 0.5
		ring.CastShadow = false
	end
end

-- A lumpy asteroid sitting on the floor (solid: something to dodge around)
local function asteroid(position: Vector3)
	local size = rng:NextNumber(4, 9)
	local rock = Color3.fromRGB(70, 62, 80)
	ball(
		block(
			"Asteroid",
			Vector3.new(size, size * 0.8, size * 1.1),
			CFrame.new(position + Vector3.new(0, size * 0.35, 0)),
			rock,
			Enum.Material.Slate
		)
	)
	for _ = 1, 3 do
		ghost(
			ball(
				block(
					"AsteroidLump",
					Vector3.one * size * 0.45,
					CFrame.new(
						position
							+ Vector3.new(
								rng:NextNumber(-1, 1) * size * 0.4,
								size * 0.5,
								rng:NextNumber(-1, 1) * size * 0.4
							)
					),
					rock,
					Enum.Material.Slate
				)
			)
		)
	end
end

-- A twinkling field of stars low over the floor
local function starfield(center: Vector3, size: Vector3)
	local anchor = ghost(block("Stars", size, CFrame.new(center), Color3.new(), Enum.Material.SmoothPlastic))
	anchor.Transparency = 1
	local stars = Instance.new("ParticleEmitter")
	stars.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	stars.Color = ColorSequence.new(Color3.fromRGB(200, 220, 255), Color3.fromRGB(255, 160, 255))
	stars.LightEmission = 1
	stars.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	stars.Lifetime = NumberRange.new(3, 6)
	stars.Rate = 40
	stars.Speed = NumberRange.new(0, 0.5)
	stars.Shape = Enum.ParticleEmitterShape.Box
	stars.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	stars.Parent = anchor
end

-- A cluster of glowing space crystals (Blender Crystal prop)
local function spaceCrystals(position: Vector3, color: Color3)
	for _ = 1, 3 do
		prop(
			"Crystal",
			CFrame.new(position + Vector3.new(rng:NextNumber(-2.5, 2.5), 0, rng:NextNumber(-2.5, 2.5)))
				* CFrame.Angles(
					math.rad(rng:NextNumber(-15, 15)),
					rng:NextNumber(0, math.pi * 2),
					math.rad(rng:NextNumber(-15, 15))
				),
			rng:NextNumber(1.2, 2.4),
			{ Crystal = color }
		)
	end
	local light = ghost(block("CrystalLight", Vector3.one * 0.2, CFrame.new(position + Vector3.new(0, 3, 0)), color))
	light.Transparency = 1
	glow(light, color, 24, 1.8)
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
	local woodColor = Color3.fromRGB(104, 66, 38)
	-- A beam from wall to wall, the board hanging off it on two ropes
	local beam = block("BoardBeam", Vector3.new(width + 12, 2, 2), at(0, 36, z), woodColor)
	Toy.Dress(beam, Toy.Sides, 1, 0)
	local boardWidth, boardHeight = 52, 15
	for _, x in { -boardWidth / 2 + 3, boardWidth / 2 - 3 } do
		block("BoardRope", Vector3.new(0.4, 6, 0.4), at(x, 32, z), Color3.fromRGB(70, 46, 28))
	end
	local frameBlock = block(
		"EventBoardFrame",
		Vector3.new(boardWidth + 1.6, boardHeight + 1.6, 1.2),
		at(0, 29 - boardHeight / 2 + 0.8, z + 0.2),
		woodColor
	)
	Toy.Dress(frameBlock, Toy.Sides, 1, 0)
	local board = block(
		"EventBoard",
		Vector3.new(boardWidth, boardHeight, 1.4),
		at(0, 29 - boardHeight / 2 + 0.8, z),
		Color3.fromRGB(34, 22, 16)
	)
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
		layout.Padding = UDim.new(0, 4)
		layout.Parent = gui
		for i = 1, 4 do
			local line = Instance.new("TextLabel")
			line.Name = `Line{i}`
			line.LayoutOrder = i
			line.Size = UDim2.fromScale(0.94, 0.21)
			line.BackgroundTransparency = 1
			line.Font = Enum.Font.FredokaOne
			line.TextScaled = true
			line.RichText = true
			line.TextColor3 = Color3.new(1, 1, 1)
			line.Text = ""
			line.Parent = gui
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 3
			stroke.Color = Color3.fromRGB(20, 12, 8)
			stroke.Parent = line
		end
	end
end

-- Build -----------------------------------------------------------------------------------------

-- Clears decoration out of a rectangle (the boss lairs, built after the decor)
function ManorDecor.ClearArea(center: Vector3, halfX: number, halfZ: number)
	if not folder then
		return
	end
	for _, child in folder:GetChildren() do
		local position = if child:IsA("BasePart")
			then child.Position
			elseif child:IsA("Model") then child:GetPivot().Position
			else nil
		if
			position
			and math.abs(position.X - center.X) < halfX
			and math.abs(position.Z - center.Z) < halfZ
			and position.Y < 60
		then
			child:Destroy()
		end
	end
end

function ManorDecor.Build(root: Instance, arena: Bounds, _hideaways: { Bounds })
	folder = Instance.new("Folder")
	folder.Name = "Decor"
	folder.Parent = root
	local width = arena.MaxX - arena.MinX
	local depth = GameConfig.ZoneDepth
	local half = width / 2

	-- Every zone (its name pops up on screen as you walk in: client/Transitions): sconces down both walls, its own biome inside
	for i, zone in GameConfig.Zones do
		local z0 = (i - 1) * depth
		local color: Color3 = zone.Color
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
		-- (never on the boss's stage: GameConfig.BossLair, plus a margin to walk around it)
		local lair = GameConfig.BossLair
		local lairAt = GameConfig.BossLairCenter(i)
		local function spot(): Vector3
			for _ = 1, 12 do
				local x = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(10, half - 5)
				local z = z0 + rng:NextNumber(20, depth - 15)
				if math.abs(x - lairAt.X) > lair.Depth / 2 + 6 or math.abs(z - lairAt.Z) > lair.Width / 2 + 6 then
					return Vector3.new(x, 0, z)
				end
			end
			return Vector3.new(half - 8, 0, z0 + 20)
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
		elseif zone.Rarity == "Mythic" then
			for _ = 1, 7 do
				lavaPool(spot(), rng:NextNumber(10, 20), rng:NextNumber(10, 24))
			end
			for _ = 1, 12 do
				obsidianSpire(spot())
			end
			for _ = 1, 8 do
				fireVent(spot())
			end
			for z = z0 + 25, z0 + depth - 15, 40 do
				brazier(Vector3.new(-half + 6, 0, z))
				brazier(Vector3.new(half - 6, 0, z))
			end
		elseif zone.Rarity == "Godly" then
			temple(Vector3.new(-half + 24, 0, z0 + depth * 0.45))
			temple(Vector3.new(half - 24, 0, z0 + depth * 0.75))
			for z = z0 + 20, z0 + depth - 10, 30 do
				olympusColumn(Vector3.new(-half + 4, 0, z), 26)
				olympusColumn(Vector3.new(half - 4, 0, z), 26)
			end
			for z = z0 + 40, z0 + depth * 0.5, 55 do
				godStatue(Vector3.new(-14, 0, z), math.rad(90))
				godStatue(Vector3.new(14, 0, z), math.rad(-90))
			end
			for _ = 1, 6 do
				brazier(spot())
			end
			for _ = 1, 8 do
				cloud(
					Vector3.new(rng:NextNumber(-half, half), rng:NextNumber(36, 50), z0 + rng:NextNumber(0, depth)),
					2
				)
			end
		elseif zone.Rarity == "Celestial" then
			pearlyGates(Vector3.new(0, 0, z0 + 12))
			for _ = 1, 26 do
				local p = spot()
				cloud(p + Vector3.new(0, rng:NextNumber(1, 3), 0), rng:NextNumber(0.6, 1.1))
			end
			for _ = 1, 10 do
				cloud(
					Vector3.new(rng:NextNumber(-half, half), rng:NextNumber(30, 45), z0 + rng:NextNumber(0, depth)),
					2.5
				)
			end
			for z = z0 + 40, z0 + depth - 25, 45 do
				angelStatue(Vector3.new(-half + 8, 0, z), math.rad(90))
				angelStatue(Vector3.new(half - 8, 0, z + 20), math.rad(-90))
			end
			for _ = 1, 6 do
				lightPillar(spot())
			end
		elseif zone.Rarity == "Cosmic" then
			starfield(Vector3.new(0, 14, z0 + depth / 2), Vector3.new(width - 6, 24, depth - 6))
			for _ = 1, 14 do
				asteroid(spot())
			end
			local crystalColors =
				{ Color3.fromRGB(170, 80, 255), Color3.fromRGB(80, 220, 255), Color3.fromRGB(255, 90, 230) }
			for _ = 1, 10 do
				spaceCrystals(spot(), crystalColors[rng:NextInteger(1, #crystalColors)])
			end
			planet(Vector3.new(-half - 40, 70, z0 + depth * 0.3), 50, Color3.fromRGB(255, 120, 80), true)
			planet(Vector3.new(half + 30, 55, z0 + depth * 0.7), 30, Color3.fromRGB(90, 180, 255), false)
			planet(Vector3.new(0, 95, z0 + depth * 0.55), 18, Color3.fromRGB(190, 255, 140), true)
		end
	end

	-- The entrance: events board hanging over the start of the runway
	eventBoard(-4, width)

	-- The plaza: lamps along both sides, the giant Void Edge at the back, fireflies everywhere
	fireflies(Vector3.new(0, 6, -95), Vector3.new(width - 6, 10, 170), Color3.fromRGB(255, 230, 140), 10)
	for z = -10, -230, -32 do
		streetLamp(Vector3.new(-half + 4, 0, z))
		streetLamp(Vector3.new(half - 4, 0, z))
	end
	local plinth = block("Plinth", Vector3.new(10, 6, 10), at(0, 3, -205), DARK_STONE, Enum.Material.Slate)
	glow(plinth, Color3.fromRGB(170, 70, 255), 30, 2)
	local statueKnife = KnifeModel.Build("VoidEdge", true)
	statueKnife:ScaleTo(7)
	statueKnife:PivotTo(CFrame.new(0, 6 + 7 * 0.9, -205) * CFrame.Angles(0, math.rad(90), 0))
	statueKnife.Name = "Statue"
	statueKnife.Parent = folder
	for _, x in { -8, 8 } do
		torch(Vector3.new(x, 0, -199))
	end

	manor(Vector3.new(0, 0, arena.MaxZ + 6))
end

return ManorDecor
