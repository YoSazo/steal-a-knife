--!strict
-- Builds the world in code (bright, low-poly placeholder art) so the whole layout lives in git.
-- Layout (top-down, +Z is "deeper"):
--
--   z = 350  ┌──────── Godly ────────┐
--            │       Legendary       │   arena: 5 zones, ZoneDepth each, guards inside
--            │         Epic          │
--            │         Rare          │
--   z = 0    └──────── Common ───────┘
--   z = -50   [B1][B2][B3]...[B8]        player bases (safe zones)
--
--   round map lives far away at z = 2000

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

export type Bounds = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
export type BaseSite = {
	Index: number,
	Center: Vector3,
	Bounds: Bounds,
	Spawn: CFrame,
	SlotCFrames: { CFrame },
	SlotPads: { Part },
	Sign: TextLabel,
}
export type Zone = { Index: number, Rarity: string, Bounds: Bounds, Pedestals: { Part } }

local MapService = {}

MapService.MaxBases = 8
MapService.Arena = nil :: Bounds?
MapService.Zones = {} :: { Zone }
MapService.Bases = {} :: { BaseSite }
MapService.RoundSpawns = {} :: { CFrame }
MapService.RoundCenter = Vector3.new(0, 0, 2000)
MapService.LobbySpawn = CFrame.new(0, 4, -100)

local root: Folder

local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent or root
	return p
end

local function label(adornee: BasePart, text: string, color: Color3, size: UDim2, offset: Vector3): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffset = offset
	gui.AlwaysOnTop = false
	gui.MaxDistance = 250
	gui.Adornee = adornee
	gui.Parent = adornee
	local text_ = Instance.new("TextLabel")
	text_.Size = UDim2.fromScale(1, 1)
	text_.BackgroundTransparency = 1
	text_.Font = Enum.Font.FredokaOne
	text_.TextScaled = true
	text_.TextColor3 = color
	text_.TextStrokeTransparency = 0
	text_.Text = text
	text_.Parent = gui
	return text_
end

local function bounds(center: Vector3, sizeX: number, sizeZ: number): Bounds
	return {
		MinX = center.X - sizeX / 2,
		MaxX = center.X + sizeX / 2,
		MinZ = center.Z - sizeZ / 2,
		MaxZ = center.Z + sizeZ / 2,
	}
end

function MapService.InBounds(b: Bounds, pos: Vector3, margin: number?): boolean
	local m = margin or 0
	return pos.X >= b.MinX - m and pos.X <= b.MaxX + m and pos.Z >= b.MinZ - m and pos.Z <= b.MaxZ + m
end

local function buildLighting()
	Lighting.ClockTime = 14
	Lighting.Brightness = 2.5
	Lighting.Ambient = Color3.fromRGB(120, 120, 130)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 160)
	Lighting.GlobalShadows = true
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.25
		atmosphere.Color = Color3.fromRGB(200, 225, 255)
		atmosphere.Parent = Lighting
	end
end

local function buildArena()
	local width, depth = GameConfig.ArenaWidth, GameConfig.ZoneDepth
	local totalDepth = depth * #GameConfig.Zones
	MapService.Arena = { MinX = -width / 2, MaxX = width / 2, MinZ = 0, MaxZ = totalDepth }

	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	arena.Parent = root

	for i, zone in GameConfig.Zones do
		local z0 = (i - 1) * depth
		local center = Vector3.new(0, 0, z0 + depth / 2)
		local floor = block(
			`Zone{i}Floor`,
			Vector3.new(width, 1, depth),
			CFrame.new(center + Vector3.new(0, -0.3, 0)),
			zone.Color,
			arena
		)
		floor.Material = Enum.Material.Grass
		local signPost = block(`Zone{i}Sign`, Vector3.new(1, 1, 1), CFrame.new(0, 14, z0 + 2), zone.Color, arena)
		signPost.Transparency = 1
		signPost.CanCollide = false
		label(signPost, `{zone.Rarity:upper()} ZONE`, zone.Color, UDim2.fromOffset(300, 60), Vector3.zero)

		local pedestals = {}
		local rng = Random.new(i * 97)
		for p = 1, GameConfig.PedestalsPerZone do
			local x = -width / 2 + (p - 0.5) * width / GameConfig.PedestalsPerZone + rng:NextNumber(-10, 10)
			local z = z0 + depth * 0.5 + rng:NextNumber(-depth * 0.25, depth * 0.25)
			local pedestal = block(
				`Pedestal{i}_{p}`,
				Vector3.new(4, 3, 4),
				CFrame.new(x, 1.5, z),
				Color3.fromRGB(245, 245, 250),
				arena
			)
			pedestal.Material = Enum.Material.Marble
			block("Trim", Vector3.new(4.4, 0.4, 4.4), CFrame.new(x, 3.1, z), zone.Color, pedestal)
			table.insert(pedestals, pedestal)
		end
		table.insert(MapService.Zones, {
			Index = i,
			Rarity = zone.Rarity,
			Bounds = { MinX = -width / 2, MaxX = width / 2, MinZ = z0, MaxZ = z0 + depth },
			Pedestals = pedestals,
		})
	end

	-- Walls on three sides; the front (z = 0) is open towards the bases
	local wallColor = Color3.fromRGB(255, 140, 80)
	block("WallLeft", Vector3.new(2, 12, totalDepth), CFrame.new(-width / 2 - 1, 6, totalDepth / 2), wallColor, arena)
	block("WallRight", Vector3.new(2, 12, totalDepth), CFrame.new(width / 2 + 1, 6, totalDepth / 2), wallColor, arena)
	block("WallBack", Vector3.new(width + 4, 12, 2), CFrame.new(0, 6, totalDepth + 1), wallColor, arena)
	-- A striped line marking the arena entrance
	block("EntranceLine", Vector3.new(width, 0.2, 2), CFrame.new(0, 0.3, 0), Color3.fromRGB(255, 255, 255), arena)
end

local function buildBases()
	local bases = Instance.new("Folder")
	bases.Name = "Bases"
	bases.Parent = root
	local sizeX, sizeZ, spacing = 54, 36, 62
	local palette = {
		Color3.fromRGB(255, 120, 120),
		Color3.fromRGB(255, 190, 90),
		Color3.fromRGB(255, 240, 110),
		Color3.fromRGB(130, 230, 130),
		Color3.fromRGB(110, 210, 255),
		Color3.fromRGB(150, 150, 255),
		Color3.fromRGB(220, 140, 255),
		Color3.fromRGB(255, 150, 210),
	}

	for i = 1, MapService.MaxBases do
		local center = Vector3.new((i - (MapService.MaxBases + 1) / 2) * spacing, 0, -50)
		local color = palette[i]
		local folder = Instance.new("Folder")
		folder.Name = `Base{i}`
		folder.Parent = bases

		block("Floor", Vector3.new(sizeX, 1, sizeZ), CFrame.new(center + Vector3.new(0, 0.1, 0)), color, folder)
		block(
			"BackWall",
			Vector3.new(sizeX, 8, 1.5),
			CFrame.new(center + Vector3.new(0, 4.5, -sizeZ / 2)),
			color:Lerp(Color3.new(1, 1, 1), 0.4),
			folder
		)
		block(
			"SideWallL",
			Vector3.new(1.5, 5, sizeZ),
			CFrame.new(center + Vector3.new(-sizeX / 2, 3, 0)),
			color:Lerp(Color3.new(1, 1, 1), 0.4),
			folder
		)
		block(
			"SideWallR",
			Vector3.new(1.5, 5, sizeZ),
			CFrame.new(center + Vector3.new(sizeX / 2, 3, 0)),
			color:Lerp(Color3.new(1, 1, 1), 0.4),
			folder
		)

		local signPart = block(
			"Sign",
			Vector3.new(20, 5, 1),
			CFrame.new(center + Vector3.new(0, 11, -sizeZ / 2)),
			Color3.fromRGB(255, 255, 255),
			folder
		)
		local sign = label(signPart, "Empty Vault", color, UDim2.fromOffset(320, 70), Vector3.new(0, 0, 0))

		-- Rack: 2 rows x 6 slots along the back wall
		local slotCFrames, slotPads = {}, {}
		for s = 1, GameConfig.MaxSlots do
			local col = (s - 1) % 6
			local row = math.floor((s - 1) / 6)
			local pos = center + Vector3.new(-18 + col * 7.2, 0.7, -sizeZ / 2 + 4 + row * 6)
			local pad = block(`Slot{s}`, Vector3.new(4, 0.4, 4), CFrame.new(pos), Color3.fromRGB(70, 70, 80), folder)
			table.insert(slotPads, pad)
			table.insert(
				slotCFrames,
				CFrame.new(pos + Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, math.rad(90), math.rad(-20))
			)
		end

		-- Walking onto the base with a knife deposits it; this pad just shows where "home" is
		local deposit = block(
			"DepositPad",
			Vector3.new(14, 0.3, 6),
			CFrame.new(center + Vector3.new(0, 0.75, sizeZ / 2 - 4)),
			Color3.fromRGB(80, 255, 140),
			folder
		)
		deposit.Material = Enum.Material.Neon
		deposit.CanCollide = false

		table.insert(MapService.Bases, {
			Index = i,
			Center = center,
			Bounds = bounds(center, sizeX, sizeZ),
			Spawn = CFrame.new(center + Vector3.new(0, 4, 4)) * CFrame.Angles(0, math.pi, 0), -- face the arena
			SlotCFrames = slotCFrames,
			SlotPads = slotPads,
			Sign = sign,
		})
	end
end

local function buildRoundMap()
	local folder = Instance.new("Folder")
	folder.Name = "RoundMap"
	folder.Parent = root
	local c = MapService.RoundCenter
	local size = 220
	local floor = block(
		"Floor",
		Vector3.new(size, 1, size),
		CFrame.new(c + Vector3.new(0, -0.4, 0)),
		Color3.fromRGB(245, 230, 200),
		folder
	)
	floor.Material = Enum.Material.WoodPlanks
	local wallColor = Color3.fromRGB(120, 200, 255)
	for _, spec in
		{
			{ Vector3.new(size, 24, 2), Vector3.new(0, 12, size / 2) },
			{ Vector3.new(size, 24, 2), Vector3.new(0, 12, -size / 2) },
			{ Vector3.new(2, 24, size), Vector3.new(size / 2, 12, 0) },
			{ Vector3.new(2, 24, size), Vector3.new(-size / 2, 12, 0) },
		}
	do
		block("Wall", spec[1], CFrame.new(c + spec[2]), wallColor, folder)
	end

	-- Crates and walls to hide behind (fixed seed so the map is the same every round)
	local rng = Random.new(7)
	local colors = {
		Color3.fromRGB(255, 120, 120),
		Color3.fromRGB(255, 200, 90),
		Color3.fromRGB(130, 220, 130),
		Color3.fromRGB(170, 130, 255),
	}
	for i = 1, 40 do
		local w, h, d = rng:NextNumber(6, 18), rng:NextNumber(5, 12), rng:NextNumber(4, 10)
		local x, z = rng:NextNumber(-95, 95), rng:NextNumber(-95, 95)
		if math.abs(x) < 20 and math.abs(z) < 20 then
			continue -- keep the middle open
		end
		block(
			`Cover{i}`,
			Vector3.new(w, h, d),
			CFrame.new(c + Vector3.new(x, h / 2, z)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			colors[rng:NextInteger(1, #colors)],
			folder
		)
	end

	for i = 1, 16 do
		local angle = (i / 16) * math.pi * 2
		local pos = c + Vector3.new(math.cos(angle) * 85, 4, math.sin(angle) * 85)
		table.insert(MapService.RoundSpawns, CFrame.lookAt(pos, Vector3.new(c.X, 4, c.Z)))
	end
end

function MapService.Init()
	local existing = workspace:FindFirstChild("Baseplate")
	if existing then
		existing:Destroy()
	end
	root = Instance.new("Folder")
	root.Name = "Map"
	root.Parent = workspace

	local ground = block("Ground", Vector3.new(800, 2, 700), CFrame.new(0, -1.5, 120), Color3.fromRGB(110, 200, 90))
	ground.Material = Enum.Material.Grass

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = MapService.LobbySpawn - Vector3.new(0, 3.5, 0)
	spawn.Color = Color3.fromRGB(255, 255, 255)
	spawn.Duration = 0
	spawn.Parent = root

	buildLighting()
	buildArena()
	buildBases()
	buildRoundMap()
end

return MapService
