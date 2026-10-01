--!strict
-- Builds the world in code so the whole layout lives in git. The hub is Blackwood Manor at night,
-- laid out like the big steal games: one long straight runway between tall stone walls, the
-- zones one after another down it, the vaults at the start. (Decoration lives in ManorDecor.)
-- Layout (top-down, +Z is "deeper"):
--
--   z = 1100+          the Manor
--   z = 880..1100  ║ Godly      ║
--   z = 660..880   ║ Legendary  ║    runway: ArenaWidth wide, ZoneDepth per zone, guards inside,
--   z = 440..660   ║ Epic       ║    candlelit hideaways cut into both walls (guards can't follow)
--   z = 220..440   ║ Rare       ║
--   z = 0..220     ║ Common     ║
--   z = -170..0  [B1]  plaza  [B5]   four vaults on each side, opening onto the plaza
--                [B2]         [B6]
--                [B3]         [B7]
--                [B4] spawn   [B8]
--
--   round maps (indoor buildings, see RoundMaps) are built far away at x = 3000

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ManorDecor = require(script.Parent.ManorDecor)
local RoundMaps = require(script.Parent.RoundMaps)
local VaultWalls = require(script.Parent.VaultWalls)
local Props = require(ReplicatedStorage.Shared.Props)

export type Bounds = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
export type BaseSite = {
	Index: number,
	Color: Color3, -- this vault's own colour (wall strip, gate glow)
	Folder: Folder,
	WallFolder: Folder, -- rebuilt by VaultWalls whenever the owner's wall tier changes
	Gate: Model,
	Blocker: Part, -- the gate's hit / collision part (attributes: Owner, Health, MaxHealth, Open)
	SignPart: Part,
	Center: Vector3,
	Frame: CFrame, -- local +Z points out of the vault's open side, towards the plaza
	Bounds: Bounds,
	Spawn: CFrame,
	SlotCFrames: { CFrame }, -- where each knife floats, over its pedestal
	SlotPads: { BasePart }, -- each pedestal's stone (holds the prompts)
	SlotRims: { BasePart }, -- each pedestal's glowing top (the knife's colour when filled)
	Treadmill: Part, -- the floor inside the Haunted Wheel; standing on it trains Speed
	TreadmillSign: TextLabel,
	Wheel: Model,
	Sign: TextLabel,
}
export type Zone = { Index: number, Rarity: string, Bounds: Bounds }

local MapService = {}

MapService.MaxBases = 8
MapService.Arena = nil :: Bounds?
MapService.Zones = {} :: { Zone }
MapService.Hideaways = {} :: { Bounds }
MapService.Bases = {} :: { BaseSite }
MapService.RoundSpawns = {} :: { CFrame }
MapService.RoundCenter = Vector3.new(3000, 0, 0)
MapService.RoundMapSize = Vector2.new(150, 110)
MapService.LobbySpawn = CFrame.new(0, 4, -150)

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

-- offset is in world space, so a sign's text can sit in front of its board
local function label(adornee: BasePart, text: string, color: Color3, size: UDim2, offset: Vector3): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.AlwaysOnTop = false
	gui.MaxDistance = 400
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

-- Safe in one of the nooks cut into the runway walls
function MapService.IsInHideaway(pos: Vector3): boolean
	for _, hideaway in MapService.Hideaways do
		if MapService.InBounds(hideaway, pos) then
			return true
		end
	end
	return false
end

-- Warm ambient fill keeps the estate readable even between lamps and during teleports.
local function buildLighting()
	Lighting.ClockTime = 0
	Lighting.Brightness = 2.4
	Lighting.ExposureCompensation = 0.15
	Lighting.Ambient = Color3.fromRGB(128, 123, 117)
	Lighting.OutdoorAmbient = Color3.fromRGB(151, 146, 138)
	Lighting.EnvironmentDiffuseScale = 0.65
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") or child:IsA("PostEffect") then
			child:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.22
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(175, 160, 143)
	atmosphere.Decay = Color3.fromRGB(95, 88, 101)
	atmosphere:SetAttribute("HubColor", atmosphere.Color)
	atmosphere:SetAttribute("HubDecay", atmosphere.Decay)
	atmosphere.Glare = 0
	atmosphere.Haze = 0.8
	atmosphere.Parent = Lighting
	-- A huge full moon and plenty of stars
	for _, child in Lighting:GetChildren() do
		if child:IsA("Sky") then
			child:Destroy()
		end
	end
	local sky = Instance.new("Sky")
	sky.MoonAngularSize = 24
	sky.StarCount = 6000
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting
	Lighting.GeographicLatitude = 30
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 28
	bloom.Threshold = 1.4
	bloom.Parent = Lighting
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Contrast = 0.04
	grade.Saturation = 0.08
	grade.TintColor = Color3.fromRGB(255, 251, 241)
	grade.Parent = Lighting
end

local NIGHT = Color3.fromRGB(20, 18, 28)
-- Each zone gets its own ground so going deeper feels like moving through the estate
local ZONE_MATERIALS = {
	Enum.Material.Grass,
	Enum.Material.Cobblestone,
	Enum.Material.Slate,
	Enum.Material.Marble,
	Enum.Material.Basalt,
}

local WALL_HEIGHT = 34
local WALL_THICK = 6
local STONE = Color3.fromRGB(70, 66, 80)

-- Runway walls take on a hint of the colour of the zone they're in
local function zoneTint(z: number): Color3
	local index = math.clamp(math.floor(z / GameConfig.ZoneDepth) + 1, 1, #GameConfig.Zones)
	return STONE:Lerp(GameConfig.Zones[index].Color, 0.22)
end

-- The runway: zone floors one after another, tall walls with hideaway nooks cut into them
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
			zone.Color:Lerp(NIGHT, 0.72),
			arena
		)
		floor.Material = ZONE_MATERIALS[i] or Enum.Material.Grass
		table.insert(MapService.Zones, {
			Index = i,
			Rarity = zone.Rarity,
			Bounds = { MinX = -width / 2, MaxX = width / 2, MinZ = z0, MaxZ = z0 + depth },
		})
	end

	-- Walls down both sides, broken by hideaways: a 10-wide doorway into an 8-deep candlelit nook
	local spacing = GameConfig.HideawaySpacing
	local door = 10
	for _, side in { -1, 1 } do
		local x = side * (width / 2 + WALL_THICK / 2)
		local cursor = 0
		local index = 0
		local z = spacing * 0.6 + (if side > 0 then spacing / 2 else 0) -- staggered left / right
		while z + door / 2 < totalDepth do
			local wallLength = (z - door / 2) - cursor
			local wall = block(
				"RunwayWall",
				Vector3.new(WALL_THICK, WALL_HEIGHT, wallLength),
				CFrame.new(x, WALL_HEIGHT / 2, cursor + wallLength / 2),
				zoneTint(cursor + wallLength / 2),
				arena
			)
			wall.Material = Enum.Material.Cobblestone
			-- Lintel over the doorway
			block(
				"Lintel",
				Vector3.new(WALL_THICK, WALL_HEIGHT - 11, door),
				CFrame.new(x, 11 + (WALL_HEIGHT - 11) / 2, z),
				zoneTint(z),
				arena
			).Material =
				Enum.Material.Cobblestone
			-- The nook behind the doorway
			local nookX = side * (width / 2 + WALL_THICK + 4)
			for _, dz in { -door / 2 - 0.5, door / 2 + 0.5 } do
				block("NookSide", Vector3.new(8, 11, 1), CFrame.new(nookX, 5.5, z + dz), zoneTint(z), arena).Material =
					Enum.Material.Cobblestone
			end
			block(
				"NookBack",
				Vector3.new(1, 11, door + 2),
				CFrame.new(side * (width / 2 + WALL_THICK + 8.5), 5.5, z),
				STONE,
				arena
			).Material =
				Enum.Material.Cobblestone
			block("NookRoof", Vector3.new(9, 1, door + 2), CFrame.new(nookX, 11.5, z), STONE, arena).Material =
				Enum.Material.Slate
			table.insert(MapService.Hideaways, {
				MinX = math.min(side * (width / 2 + 0.5), side * (width / 2 + WALL_THICK + 8)),
				MaxX = math.max(side * (width / 2 + 0.5), side * (width / 2 + WALL_THICK + 8)),
				MinZ = z - door / 2,
				MaxZ = z + door / 2,
			})
			index += 1
			cursor = z + door / 2
			z += spacing
		end
		local last = totalDepth - cursor
		block(
			"RunwayWall",
			Vector3.new(WALL_THICK, WALL_HEIGHT, last),
			CFrame.new(x, WALL_HEIGHT / 2, cursor + last / 2),
			zoneTint(cursor + last / 2),
			arena
		).Material =
			Enum.Material.Cobblestone
	end
	-- The far end: the Manor's wall
	block(
		"RunwayEnd",
		Vector3.new(width + WALL_THICK * 2, WALL_HEIGHT, WALL_THICK),
		CFrame.new(0, WALL_HEIGHT / 2, totalDepth + WALL_THICK / 2),
		STONE,
		arena
	).Material =
		Enum.Material.Cobblestone

	-- A glowing line where the runway starts
	local line =
		block("EntranceLine", Vector3.new(width, 0.2, 2), CFrame.new(0, 0.3, 0), Color3.fromRGB(255, 80, 90), arena)
	line.Material = Enum.Material.Neon
	line.CanCollide = false
end

-- Vaults: four down each side of the plaza, each opening onto it. Built in each vault's own frame
-- (local +Z = the open side), so both columns share the same code.
local VAULT_WIDTH, VAULT_DEPTH, VAULT_SPACING = 40, 44, 40 -- vaults touch: no gaps to slip out through

local function buildBases()
	local bases = Instance.new("Folder")
	bases.Name = "Bases"
	bases.Parent = root
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
	local half = GameConfig.ArenaWidth / 2
	local perSide = MapService.MaxBases // 2

	for i = 1, MapService.MaxBases do
		local side = if i <= perSide then -1 else 1
		local row = (i - 1) % perSide
		local center = Vector3.new(side * (half + VAULT_DEPTH / 2), 0, -20 - row * VAULT_SPACING)
		-- Rotate so local +Z faces the plaza (the left column faces +X, the right column -X)
		local frame = CFrame.new(center) * CFrame.Angles(0, math.rad(if side < 0 then 90 else -90), 0)
		local function at(x: number, y: number, z: number): CFrame
			return frame * CFrame.new(x, y, z)
		end
		local color = palette[i]
		local folder = Instance.new("Folder")
		folder.Name = `Base{i}`
		folder.Parent = bases

		-- A hideout: dark plank floor tinted with the owner's colour, stone walls, and a neon strip
		-- along the top of each wall so you can spot your own from far away
		local floor =
			block("Floor", Vector3.new(VAULT_WIDTH, 1, VAULT_DEPTH), at(0, 0.1, 0), color:Lerp(NIGHT, 0.7), folder)
		floor.Material = Enum.Material.WoodPlanks
		-- Walls, gate towers and the gate itself depend on the owner's wall tier (VaultWalls)
		local wallFolder = Instance.new("Folder")
		wallFolder.Name = "Walls"
		wallFolder.Parent = folder
		local walls = VaultWalls.Build(wallFolder, frame, color, 1)
		-- Interior lighting: a Blender chandelier hanging from a crossbeam, candle sconces along the
		-- back wall, and a rug in the vault's colour between the door and the pedestals
		local beam = block(
			"Crossbeam",
			Vector3.new(VAULT_WIDTH - 2, 0.9, 0.9),
			at(0, 11.6, -4),
			Color3.fromRGB(60, 40, 28),
			folder
		)
		beam.Material = Enum.Material.Wood
		beam.CanCollide = false
		local chandelier = Props.Build("Chandelier", true)
		chandelier:PivotTo(at(0, 11.2, -4))
		chandelier.Parent = folder
		local flames = (chandelier:FindFirstChild("Flames") or chandelier.PrimaryPart) :: BasePart
		local candleLight = Instance.new("PointLight")
		candleLight.Color = Color3.fromRGB(255, 224, 184)
		candleLight.Range = 44
		candleLight.Brightness = 1.3
		candleLight.Shadows = false
		candleLight.Parent = flames
		for _, x in { -16, -8, 8, 16 } do
			local sconce = Props.Build("Sconce", true)
			-- Sticks out from the back wall into the room
			sconce:PivotTo(at(x, 7.5, -VAULT_DEPTH / 2 + 0.75) * CFrame.Angles(0, math.pi, 0))
			sconce.Parent = folder
			local flame = (sconce:FindFirstChild("Flame") or sconce.PrimaryPart) :: BasePart
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 213, 165)
			light.Range = 24
			light.Brightness = 1
			light.Parent = flame
		end
		local rug = block("Rug", Vector3.new(14, 0.08, 22), at(0, 0.64, 6), color:Lerp(NIGHT, 0.45), folder)
		rug.Material = Enum.Material.Fabric
		rug.CanCollide = false
		local rugBorder =
			block("RugBorder", Vector3.new(15, 0.06, 23), at(0, 0.62, 6), Color3.fromRGB(200, 160, 70), folder)
		rugBorder.Material = Enum.Material.Fabric
		rugBorder.CanCollide = false

		local signPart =
			block("Sign", Vector3.new(20, 5, 1), at(0, 17, -VAULT_DEPTH / 2), Color3.fromRGB(45, 30, 25), folder)
		signPart.Material = Enum.Material.WoodPlanks
		local sign = label(
			signPart,
			"Empty Vault",
			color,
			UDim2.fromScale(24, 5),
			frame:VectorToWorldSpace(Vector3.new(0, 0, 1.5))
		)

		-- Display floor: 3 rows x 4 pedestals in the back half of the vault, a knife floating and
		-- turning over each (Blender pedestal, see Props)
		local slotCFrames, slotPads, slotRims = {}, {}, {}
		for slot = 1, GameConfig.MaxSlots do
			local col = (slot - 1) % 4
			local pedestalRow = math.floor((slot - 1) / 4)
			local x, z = -14 + col * (28 / 3), -18.5 + pedestalRow * 5.5
			local pedestal = Props.Build("Pedestal", true)
			pedestal.Name = `Pedestal{slot}`
			pedestal:PivotTo(at(x, 0.6, z))
			for _, d in pedestal:GetDescendants() do
				if d:IsA("BasePart") then
					d.CanCollide = d.Name == "Stone"
					d.CanQuery = d.Name == "Stone"
				end
			end
			pedestal.Parent = folder
			local stone = (pedestal:FindFirstChild("Stone") or pedestal.PrimaryPart) :: BasePart
			local glow = (pedestal:FindFirstChild("Glow") or stone) :: BasePart
			table.insert(slotPads, stone)
			table.insert(slotRims, glow)
			-- The knife floats here, blade up, facing out of the vault
			table.insert(slotCFrames, at(x, 4.2, z))
		end

		-- The Haunted Wheel: a giant iron wheel you run inside to train Speed (the plate at the bottom
		-- is what counts as "on it"). Clients spin it while its owner is training.
		local wheelCenter = Vector3.new(-12, 6.6, 3)
		local wheel = Instance.new("Model")
		wheel.Name = "HauntedWheel"
		local hub = block(
			"Hub",
			Vector3.new(7.4, 1.2, 1.2),
			at(wheelCenter.X, wheelCenter.Y, wheelCenter.Z),
			Color3.fromRGB(50, 46, 58),
			wheel
		)
		hub.Shape = Enum.PartType.Cylinder
		hub.Material = Enum.Material.Metal
		hub.CanCollide = false
		hub.Transparency = 1 -- just the pivot; a bar here would go through the runner's head
		for _, x in { -3.9, 3.9 } do
			local cap = block(
				"AxleCap",
				Vector3.new(1.4, 1.2, 1.2),
				at(wheelCenter.X + x, wheelCenter.Y, wheelCenter.Z),
				Color3.fromRGB(50, 46, 58),
				wheel
			)
			cap.Shape = Enum.PartType.Cylinder
			cap.Material = Enum.Material.Metal
			cap.CanCollide = false
		end
		local iron = Color3.fromRGB(70, 64, 80)
		local radius, segments = 6, 20
		for k = 0, segments - 1 do
			local angle = k / segments * math.pi * 2
			local oy, oz = math.cos(angle) * radius, math.sin(angle) * radius
			for _, x in { -3.4, 3.4 } do
				local rim = block(
					"Rim",
					Vector3.new(0.5, 0.5, 2 * math.pi * radius / segments + 0.1),
					at(wheelCenter.X + x, wheelCenter.Y + oy, wheelCenter.Z + oz) * CFrame.Angles(angle, 0, 0),
					iron,
					wheel
				)
				rim.Material = Enum.Material.Metal
				rim.CanCollide = false
			end
			-- Rungs across the inside, like a hamster wheel
			local rung = block(
				"Rung",
				Vector3.new(6.8, 0.25, 0.4),
				at(wheelCenter.X, wheelCenter.Y + oy * 0.97, wheelCenter.Z + oz * 0.97) * CFrame.Angles(angle, 0, 0),
				Color3.fromRGB(90, 70, 50),
				wheel
			)
			rung.Material = Enum.Material.Wood
			rung.CanCollide = false
			if k % 5 == 0 then
				local spoke = block(
					"Spoke",
					Vector3.new(0.4, radius, 0.4),
					at(wheelCenter.X - 3.4, wheelCenter.Y + oy / 2, wheelCenter.Z + oz / 2) * CFrame.Angles(angle, 0, 0),
					iron,
					wheel
				)
				spoke.CanCollide = false
				-- Ghost lights riding the rim
				local wisp = block(
					"Wisp",
					Vector3.one * 0.8,
					at(wheelCenter.X + 3.4, wheelCenter.Y + oy, wheelCenter.Z + oz),
					color,
					wheel
				)
				wisp.Shape = Enum.PartType.Ball
				wisp.Material = Enum.Material.Neon
				wisp.CanCollide = false
				local wispLight = Instance.new("PointLight")
				wispLight.Color = color
				wispLight.Range = 10
				wispLight.Parent = wisp
			end
		end
		wheel.PrimaryPart = hub
		-- Streams in as one piece, and remembers its resting position so clients can spin it
		-- around the right spot even if they see the model before all its parts arrive
		wheel.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		wheel:SetAttribute("Pivot", hub.CFrame)
		wheel:AddTag("HauntedWheel")
		wheel.Parent = folder
		-- Stands holding the axle
		for _, x in { -4.4, 4.4 } do
			block("WheelStand", Vector3.new(0.8, 7, 1.2), at(wheelCenter.X + x, 3.5, wheelCenter.Z), iron, folder).Material =
				Enum.Material.Metal
		end
		-- The plate you stand on inside the bottom of the wheel
		local belt = block(
			"WheelFloor",
			Vector3.new(6, 0.4, 5),
			at(wheelCenter.X, 0.8, wheelCenter.Z),
			Color3.fromRGB(40, 36, 46),
			folder
		)
		belt.Material = Enum.Material.WoodPlanks
		local wheelSign = block(
			"WheelSign",
			Vector3.new(6, 1.6, 0.4),
			at(wheelCenter.X, 13.2, wheelCenter.Z),
			Color3.fromRGB(45, 30, 25),
			folder
		)
		wheelSign.Material = Enum.Material.WoodPlanks
		local treadmillSign = label(wheelSign, "Creaky Wheel", color, UDim2.fromScale(9, 2), Vector3.new(0, 0.2, 1)) -- under the vault's own sign

		-- Walking into the vault with a knife deposits it; this pad just shows where "home" is
		local deposit = block(
			"DepositPad",
			Vector3.new(14, 0.3, 6),
			at(0, 0.75, VAULT_DEPTH / 2 - 4),
			Color3.fromRGB(80, 255, 140),
			folder
		)
		deposit.Material = Enum.Material.Neon
		deposit.CanCollide = false

		-- Spawn just inside the door, facing out towards the plaza and the runway
		local spawnPos = (at(0, 4, VAULT_DEPTH / 2 - 10)).Position
		table.insert(MapService.Bases, {
			Index = i,
			Color = color,
			Folder = folder,
			WallFolder = wallFolder,
			Gate = walls.Gate,
			Blocker = walls.Blocker,
			SignPart = signPart,
			Center = center,
			Frame = frame,
			-- Rotated 90 degrees, so the world footprint swaps width and depth
			Bounds = bounds(center, VAULT_DEPTH, VAULT_WIDTH),
			Spawn = CFrame.lookAt(spawnPos, spawnPos + frame:VectorToWorldSpace(Vector3.zAxis)),
			SlotCFrames = slotCFrames,
			SlotPads = slotPads,
			SlotRims = slotRims,
			Treadmill = belt,
			TreadmillSign = treadmillSign,
			Wheel = wheel,
			Sign = sign,
		})
	end

	-- The plaza between the two columns of vaults
	local plaza = block(
		"Plaza",
		Vector3.new(GameConfig.ArenaWidth, 1, 190),
		CFrame.new(0, -0.3, -95),
		Color3.fromRGB(70, 68, 78),
		bases
	)
	plaza.Material = Enum.Material.Cobblestone
	-- Close the plaza between the last vaults and its back wall
	local lastEdge = -20 - (perSide - 1) * VAULT_SPACING - VAULT_WIDTH / 2
	for _, side in { -1, 1 } do
		local length = 194 + lastEdge
		block(
			"PlazaSideWall",
			Vector3.new(WALL_THICK, WALL_HEIGHT, -length),
			CFrame.new(side * (half + WALL_THICK / 2), WALL_HEIGHT / 2, lastEdge + length / 2),
			STONE,
			bases
		).Material =
			Enum.Material.Cobblestone
	end
end

-- Round maps are real buildings (RoundMaps); a random one is rebuilt at the start of each round
function MapService.BuildRoundMap(name: string?): RoundMaps.Built
	local built = RoundMaps.Build(root, MapService.RoundCenter, name)
	MapService.RoundSpawns = built.Spawns
	MapService.RoundMapSize = built.Size
	return built
end

function MapService.Init()
	-- Clear out the template place's baseplate and default spawn; the map below replaces them
	for _, child in workspace:GetChildren() do
		if child.Name == "Baseplate" or child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end
	root = Instance.new("Folder")
	root.Name = "Map"
	root.Parent = workspace

	local ground = block("Ground", Vector3.new(700, 2, 1700), CFrame.new(0, -1.5, 560), Color3.fromRGB(38, 50, 40))
	ground.Material = Enum.Material.Grass

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = MapService.LobbySpawn - Vector3.new(0, 3.3, 0)
	spawn.Color = Color3.fromRGB(62, 60, 72)
	spawn.Material = Enum.Material.Slate
	spawn.Duration = 0
	spawn.Parent = root

	buildLighting()
	buildArena()
	buildBases()
	ManorDecor.Build(root, MapService.Arena :: Bounds, MapService.Hideaways)
	MapService.BuildRoundMap("Office")
end

return MapService
