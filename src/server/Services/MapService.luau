--!strict
-- Builds the world in code so the whole layout lives in git. The hub is Blackwood Manor at night,
-- laid out like the big steal games: one long straight runway between tall stone walls, the
-- zones one after another down it, the vaults at the start. (Decoration lives in ManorDecor.)
-- Layout (top-down, +Z is "deeper"):
--
--   z = 1760+          the Manor
--   z = 1540..1760 ║ Cosmic     ║    Outer Space
--   z = 1320..1540 ║ Celestial  ║    The Heavens
--   z = 1100..1320 ║ Godly      ║    Mount Olympus
--   z = 880..1100  ║ Mythic     ║    The Inferno
--   z = 660..880   ║ Legendary  ║    runway: ArenaWidth (160) wide, ZoneDepth per zone, guards inside;
--   z = 440..660   ║ Epic       ║    they chase you all the way back to the plaza
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
local Textures = require(ReplicatedStorage.Shared.Config.Textures)
local SignTheme = require(ReplicatedStorage.Shared.SignTheme)
local Toy = require(ReplicatedStorage.Shared.Toy)

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
	FloorFolders: { Folder }, -- each storey's decks, ladder and plates (SetFloors shows the owned ones)
	CashPads: { BasePart }, -- the green pad beside each plate: walk on it to collect that knife's money
	CashLabels: { TextLabel }, -- the amount waiting, written on the pad
	Treadmill: Part, -- the floor inside the Haunted Wheel; standing on it trains Speed
	TreadmillSign: TextLabel,
	Wheel: Model,
	Sign: TextLabel,
}
export type Zone = { Index: number, Rarity: string, Bounds: Bounds }

local MapService = {}

MapService.MaxBases = 16 -- 6 down each side of the plaza + 4 across the back (16-player servers)
MapService.Arena = nil :: Bounds?
MapService.Zones = {} :: { Zone }
MapService.Hideaways = {} :: { Bounds }
MapService.Bases = {} :: { BaseSite }
MapService.RoundSpawns = {} :: { CFrame }
MapService.RoundCenter = Vector3.new(3000, 0, 0)
MapService.RoundMapSize = Vector2.new(150, 110)
MapService.LobbySpawn = CFrame.new(0, 4, -110)

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
	gui:SetAttribute("LabelCategory", "Utility")
	gui:AddTag("ResponsiveWorldLabel")
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

-- A sunny afternoon high in the sky (Steal An Egg style): a real sun low enough that everything
-- throws a clear shadow, blue sky all the way round (also below: the map floats), soft clouds.
-- Set Lighting.Technology to Future (or ShadowMap) in Studio for crisp shadows.
local function buildLighting()
	-- Noon with the sun straight overhead (like Steal An Egg): at latitude 23.5 the noon sun is
	-- exactly vertical, so the tall runway walls throw no shadow across the boss lairs beside them
	Lighting.ClockTime = 12
	Lighting.GeographicLatitude = 23.5
	-- Flat and bright: a gentle sun (a strong one glares off the floors in bright patches) and
	-- strong, even fill light so nothing looks dim
	Lighting.Brightness = 4
	Lighting.ExposureCompensation = 0.1
	-- Warm and even, like Steal An Egg: the sun is overhead, so walls get no direct light - strong
	-- warm fill keeps them bright tan instead of murky. No sky-light bounce (it tinted everything blue).
	Lighting.Ambient = Color3.fromRGB(190, 188, 184)
	Lighting.OutdoorAmbient = Color3.fromRGB(222, 218, 210)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 252, 245)
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0
	-- Clients restore these after a round (client/Effects)
	Lighting:SetAttribute("HubAmbient", Lighting.Ambient)
	Lighting:SetAttribute("HubOutdoor", Lighting.OutdoorAmbient)
	-- Real shadows (with the sun overhead, just a small one under each character)
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.2
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") or child:IsA("PostEffect") or child:IsA("Sky") then
			child:Destroy()
		end
	end
	-- A soft, pale haze with distance (things far below or far away go lighter, close up stays crisp)
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.05
	atmosphere.Color = Color3.fromRGB(225, 232, 240)
	atmosphere.Decay = Color3.fromRGB(190, 210, 230)
	atmosphere:SetAttribute("HubColor", atmosphere.Color)
	atmosphere:SetAttribute("HubDecay", atmosphere.Decay)
	atmosphere.Glare = 0
	atmosphere.Haze = 1 -- the soft, sunny white haze down the runway (Steal An Egg)
	atmosphere.Parent = Lighting
	local sky = Instance.new("Sky")
	sky.SkyboxFt = Textures.Day.Ft
	sky.SkyboxBk = Textures.Day.Bk
	sky.SkyboxLf = Textures.Day.Lf
	sky.SkyboxRt = Textures.Day.Rt
	sky.SkyboxUp = Textures.Day.Up
	sky.SkyboxDn = Textures.Day.Dn
	sky.StarCount = 0
	sky.CelestialBodiesShown = true -- the real sun, matching the shadows
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 0
	sky.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.25
	bloom.Size = 20
	bloom.Threshold = 2
	bloom.Parent = Lighting
	local grade = Instance.new("ColorCorrectionEffect")
	-- Softer and a touch brighter, like Steal An Egg: slightly less saturation (the parts alone read
	-- neon) and a gentle lift
	grade.Contrast = -0.02
	grade.Saturation = -0.08
	grade.TintColor = Color3.fromRGB(255, 253, 248)
	grade.Brightness = 0.04
	grade.Parent = Lighting
	-- A clear sky (the few clouds are painted into the skybox)
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		clouds:Destroy()
	end
end

-- Each zone is its own bright toy biome, so going deeper reads at a glance (Steal An Egg style)
local ZONE_FLOORS: { [string]: Color3 } = {
	Common = Color3.fromRGB(48, 146, 30), -- the Courtyard: grass (same green as the plaza)
	Rare = Color3.fromRGB(26, 104, 30), -- the Gardens: deep grass
	Epic = Color3.fromRGB(96, 100, 120), -- the Crypts: grey stone
	Legendary = Color3.fromRGB(196, 158, 86), -- the Catacombs: sand
	Mythic = Color3.fromRGB(150, 48, 30), -- the Inferno: red rock
	Godly = Color3.fromRGB(200, 196, 180), -- Olympus: marble
	Celestial = Color3.fromRGB(150, 196, 230), -- the Heavens: cloud blue
	Cosmic = Color3.fromRGB(70, 46, 130), -- Space: purple
}
-- Walls change with the biome too, so going deeper looks deeper
local ZONE_WALLS: { [string]: Color3 } = {
	Common = Color3.fromRGB(214, 146, 78), -- dirt
	Rare = Color3.fromRGB(174, 119, 72), -- dark dirt
	Epic = Color3.fromRGB(110, 110, 118), -- stone
	Legendary = Color3.fromRGB(176, 140, 80), -- sandstone
	Mythic = Color3.fromRGB(90, 40, 34), -- dark basalt
	Godly = Color3.fromRGB(196, 186, 160), -- marble
	Celestial = Color3.fromRGB(200, 214, 230), -- cloud
	Cosmic = Color3.fromRGB(48, 36, 84), -- void
}

local WALL_HEIGHT = 40
local WALL_THICK = 6
local STONE = Color3.fromRGB(98, 92, 150)

-- Runway walls take on a hint of the colour of the zone they're in
local function zoneTint(z: number): Color3
	local index = math.clamp(math.floor(z / GameConfig.ZoneDepth) + 1, 1, #GameConfig.Zones)
	local floor = ZONE_FLOORS[GameConfig.Zones[index].Rarity] or STONE
	return floor:Lerp(Color3.new(0, 0, 0), 0.32)
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
			ZONE_FLOORS[zone.Rarity] or zone.Color,
			arena
		)
		Toy.Dress(floor, nil, 1, 5)
		table.insert(MapService.Zones, {
			Index = i,
			Rarity = zone.Rarity,
			Bounds = { MinX = -width / 2, MaxX = width / 2, MinZ = z0, MaxZ = z0 + depth },
		})
	end

	-- Solid walls down both sides, one segment per zone so each takes on that zone's tint. (The old
	-- hideaway nooks are gone: people sat in them throwing knives at guards that couldn't reach them.)
	for _, side in { -1, 1 } do
		local x = side * (width / 2 + WALL_THICK / 2)
		for i = 1, #GameConfig.Zones do
			local z0 = (i - 1) * depth
			local wall = block(
				"RunwayWall",
				Vector3.new(WALL_THICK, WALL_HEIGHT, depth),
				CFrame.new(x, WALL_HEIGHT / 2, z0 + depth / 2),
				zoneTint(z0 + depth / 2),
				arena
			)
			Toy.DirtWall(wall, ZONE_WALLS[GameConfig.Zones[i].Rarity])
		end
	end
	-- The far end: the Manor's wall
	local farWall = block(
		"RunwayEnd",
		Vector3.new(width + WALL_THICK * 2, WALL_HEIGHT, WALL_THICK),
		CFrame.new(0, WALL_HEIGHT / 2, totalDepth + WALL_THICK / 2),
		STONE,
		arena
	)
	Toy.DirtWall(farWall)

	-- A glowing line where the runway starts
	local line = block(
		"EntranceLine",
		Vector3.new(width, 0.4, 0.5),
		CFrame.new(0, 0.4, -0.25),
		Color3.fromRGB(235, 80, 95),
		arena
	)
	line.CanCollide = false
	line.CanQuery = false
	-- SAFE ZONE painted on the plaza floor: bosses give up the chase past the line
	local paint = block("SafeZone", Vector3.new(60, 0.05, 10), CFrame.new(0, 0.23, -12), Color3.new(), arena)
	paint.Transparency = 1
	paint.CanCollide = false
	paint.CanQuery = false
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Top
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 20
	surface.LightInfluence = 0
	surface.Brightness = 0.85 -- full-bright signs, a touch softer than pure white
	surface.Parent = paint
	local safeText = Instance.new("TextLabel")
	safeText.Size = UDim2.fromScale(1, 1)
	safeText.BackgroundTransparency = 1
	safeText.Font = Enum.Font.FredokaOne
	safeText.TextScaled = true
	safeText.TextColor3 = Color3.new(1, 1, 1)
	safeText.Text = "🛡 SAFE ZONE 🛡"
	safeText.Rotation = 180 -- reads the right way round walking up from the plaza
	safeText.Parent = surface
	local outline = Instance.new("UIStroke")
	outline.Thickness = 6
	outline.Color = Color3.fromRGB(30, 30, 40)
	outline.Parent = safeText
end

-- Vaults: four down each side of the plaza, each opening onto it. Built in each vault's own frame
-- (local +Z = the open side), so both columns share the same code.
local VAULT_WIDTH, VAULT_DEPTH, VAULT_SPACING = 40, 44, 40 -- vaults touch: no gaps to slip out through
-- Inside (vault-local; +Z is the open side), Tsunami style: every floor is a walkway down the middle
-- with a ladder at the back, and five big plates down each side. Floor 1 is the ground; each
-- upgrade shows the next storey (SetFloors).
local SLOTS_PER_FLOOR = GameConfig.SlotsPerFloor
local FLOORS = GameConfig.MaxSlots // SLOTS_PER_FLOOR
local FLOOR_HEIGHT = 22 -- tall Tsunami storeys: lots of air over the knives
local PLATE_X = 12 -- the two columns of plates, either side of the walkway
local PLATE_Z = { -17, -9, -1, 7, 15 } -- back to front
local WALK_HALF = 4
local LADDER_LANDING = 3.5 -- deck behind the ladder at the back, where you step off at the top
local LADDER_HOLE = 3 -- the slot in front of the ladder you climb up through
local LADDER_HOLE_HALF = 2.5
local PLATE_RADIUS = 3.4
local FLOOR_PINK = Color3.fromRGB(242, 238, 255) -- (lavender white, like Tsunami's floors)
local HUB_HALF = GameConfig.ArenaWidth / 2 + VAULT_DEPTH + 0.5 -- the hub's outer wall (inner face), just behind the vaults
local COLUMN = 6 -- vaults down each side; 4 more across the back
local HUB_BACK = COLUMN * 40 + 44 -- the hub ends right behind the back row of vaults
local NAVY = Color3.fromRGB(40, 44, 90)
local CYAN = Color3.fromRGB(80, 228, 255)
local KNIFE_TILT = 12 -- degrees
MapService.Floors = FLOORS
MapService.FloorHeight = FLOOR_HEIGHT
MapService.SlotsPerFloor = SLOTS_PER_FLOOR

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
		Color3.fromRGB(255, 160, 110),
		Color3.fromRGB(190, 240, 120),
		Color3.fromRGB(110, 240, 210),
		Color3.fromRGB(120, 170, 255),
		Color3.fromRGB(200, 120, 220),
		Color3.fromRGB(255, 200, 150),
		Color3.fromRGB(170, 255, 170),
		Color3.fromRGB(180, 200, 255),
	}
	local half = GameConfig.ArenaWidth / 2

	for i = 1, MapService.MaxBases do
		-- 1-6 down the left side, 7-12 down the right, 13-16 across the back of the plaza
		local center: Vector3, frame: CFrame
		local sideways = i <= COLUMN * 2
		if sideways then
			local side = if i <= COLUMN then -1 else 1
			local row = (i - 1) % COLUMN
			center = Vector3.new(side * (half + VAULT_DEPTH / 2), 0, -20 - row * VAULT_SPACING)
			-- Rotate so local +Z faces the plaza (the left column faces +X, the right column -X)
			frame = CFrame.new(center) * CFrame.Angles(0, math.rad(if side < 0 then 90 else -90), 0)
		else
			local k = i - COLUMN * 2
			center = Vector3.new(
				-half + VAULT_WIDTH / 2 + (k - 1) * VAULT_WIDTH,
				0,
				-COLUMN * VAULT_SPACING - VAULT_DEPTH / 2
			)
			frame = CFrame.new(center) -- local +Z already faces the plaza
		end
		local function at(x: number, y: number, z: number): CFrame
			return frame * CFrame.new(x, y, z)
		end
		local color = palette[i]
		local folder = Instance.new("Folder")
		folder.Name = `Base{i}`
		folder.Parent = bases

		-- An open platform (Tsunami style): a pale studded floor with a hint of the owner's colour
		local floor = block(
			"Floor",
			Vector3.new(VAULT_WIDTH, 1, VAULT_DEPTH),
			at(0, 0.1, 0),
			FLOOR_PINK:Lerp(color, 0.08),
			folder
		)
		Toy.Dress(floor, nil, 1, 4)
		-- Walls, gate towers and the gate itself depend on the owner's wall tier (VaultWalls)
		local wallFolder = Instance.new("Folder")
		wallFolder.Name = "Walls"
		wallFolder.Parent = folder
		local walls = VaultWalls.Build(wallFolder, frame, color, 1)
		-- The storeys. Each has its own folder so the vault can grow: decks with a hole at the back
		-- middle, a ladder up from the floor below, a glass rail along the open front, the walkway
		-- and ten plates (slots 1-10 ground, 11-20 next floor, ...)
		local deckColor = FLOOR_PINK:Lerp(color, 0.08)
		local floorFolders: { Folder } = {}
		local slotCFrames: { CFrame }, slotPads: { BasePart }, slotRims: { BasePart } = {}, {}, {}
		local cashPads: { BasePart }, cashLabels: { TextLabel } = {}, {}
		local inner = VAULT_WIDTH / 2 - 0.5
		local back, front = -VAULT_DEPTH / 2 + 0.5, VAULT_DEPTH / 2 - 0.5
		for level = 1, FLOORS do
			local levelFolder = Instance.new("Folder")
			levelFolder.Name = `Floor{level}`
			levelFolder.Parent = folder
			floorFolders[level] = levelFolder
			local y = (level - 1) * FLOOR_HEIGHT
			local surface = if level == 1 then 0.6 else y
			if level > 1 then
				-- The deck is whole except a slot in front of the ladder (where you climb through);
				-- behind the ladder is a small landing you step onto at the top, Roblox-ladder style
				local landing = back + LADDER_LANDING
				local holeTo = landing + 2 + LADDER_HOLE
				local function deck(minX: number, maxX: number, minZ: number, maxZ: number)
					local piece = block(
						"Deck",
						Vector3.new(maxX - minX, 1, maxZ - minZ),
						at((minX + maxX) / 2, y - 0.5, (minZ + maxZ) / 2),
						deckColor,
						levelFolder
					)
					Toy.Dress(piece, nil, 1, 4)
				end
				deck(-inner, inner, back, landing) -- the landing
				deck(-inner, inner, holeTo, front) -- the floor
				for _, deckSide in { -1, 1 } do
					local a, b = deckSide * LADDER_HOLE_HALF, deckSide * inner
					deck(math.min(a, b), math.max(a, b), landing, holeTo)
				end
				local glass = block(
					"RailGlass",
					Vector3.new(inner * 2, 3.5, 0.3),
					at(0, y + 1.75, front - 0.2),
					Color3.fromRGB(190, 240, 255),
					levelFolder
				)
				glass.Material = Enum.Material.Glass
				glass.Transparency = 0.6
				block("RailCap", Vector3.new(inner * 2, 0.4, 0.6), at(0, y + 3.6, front - 0.2), NAVY, levelFolder)
				-- The ladder from the floor below, poking up through the hole so you can step off
				local truss = Instance.new("TrussPart")
				truss.Name = "Ladder"
				truss.Anchored = true
				-- From the floor below up to just over this deck: climb, then keep pushing to step onto the
				-- landing behind it
				local bottom = if level == 2 then 0.6 else y - FLOOR_HEIGHT
				truss.Size = Vector3.new(2, FLOOR_HEIGHT, 2)
				truss.CFrame = at(0, bottom + FLOOR_HEIGHT / 2, landing + 1)
				truss.Transparency = 1 -- climbable, but the ladder you see is drawn below
				truss.Parent = levelFolder
				-- The ladder you see: two chunky navy rails and bright yellow rungs, and a yellow trim
				-- round the hole so it's easy to spot from across the vault
				local ladderZ = landing + 1
				for _, railSide in { -1, 1 } do
					local rail = block(
						"LadderRail",
						Vector3.new(0.45, FLOOR_HEIGHT + 2.5, 0.45),
						at(railSide * 1.15, bottom + (FLOOR_HEIGHT + 2.5) / 2, ladderZ + 0.7),
						NAVY,
						levelFolder
					)
					rail.CanCollide = false
					rail.CanQuery = false
					Toy.Dress(rail, Toy.Sides, 1, 0)
				end
				for rungY = bottom + 1, bottom + FLOOR_HEIGHT - 0.4, 1.6 do
					local rung = block(
						"LadderRung",
						Vector3.new(2.3, 0.3, 0.35),
						at(0, rungY, ladderZ + 0.7),
						Color3.fromRGB(255, 205, 40),
						levelFolder
					)
					rung.CanCollide = false
					rung.CanQuery = false
				end
				for _, trim in
					{
						{ Vector3.new(LADDER_HOLE_HALF * 2 + 0.6, 0.12, 0.3), Vector3.new(0, y + 0.06, holeTo) },
						{
							Vector3.new(0.3, 0.12, holeTo - landing),
							Vector3.new(-LADDER_HOLE_HALF, y + 0.06, (landing + holeTo) / 2),
						},
						{
							Vector3.new(0.3, 0.12, holeTo - landing),
							Vector3.new(LADDER_HOLE_HALF, y + 0.06, (landing + holeTo) / 2),
						},
					}
				do
					local edge = block(
						"HoleTrim",
						trim[1],
						at(trim[2].X, trim[2].Y, trim[2].Z),
						Color3.fromRGB(255, 205, 40),
						levelFolder
					)
					edge.CanCollide = false
					edge.CanQuery = false
				end
			end
			-- The walkway down the middle, from the gate to the ladder
			-- (it stops where the ladder hole starts, so the cut-out reads as a hole)
			local walkFrom = back + LADDER_LANDING + 2 + LADDER_HOLE
			local walk = block(
				"Walkway",
				Vector3.new(WALK_HALF * 2, 0.06, front - walkFrom),
				at(0, surface + 0.03, (front + walkFrom) / 2),
				Color3.fromRGB(226, 230, 242),
				levelFolder
			)
			walk.CanCollide = false
			walk.CanQuery = false
			Toy.Dress(walk, nil, 1, 0)
			for index = 1, SLOTS_PER_FLOOR do
				local plateSide = if index <= #PLATE_Z then -1 else 1
				local x, z = plateSide * PLATE_X, PLATE_Z[(index - 1) % #PLATE_Z + 1]
				local slot = (level - 1) * SLOTS_PER_FLOOR + index
				-- A plain flat plate on the floor (Tsunami style), nothing else
				local plate = block(
					`Pedestal{slot}`,
					Vector3.new(0.3, PLATE_RADIUS * 2, PLATE_RADIUS * 2),
					at(x, surface + 0.15, z) * CFrame.Angles(0, 0, math.rad(90)),
					CYAN,
					levelFolder
				)
				plate.Shape = Enum.PartType.Cylinder
				plate.CanCollide = false
				slotPads[slot] = plate
				slotRims[slot] = plate
				-- The money pad between the plate and the walkway (Tsunami style): the knife's
				-- earnings pile up here until its owner walks over it
				-- The panel's +Z faces the plate, so the text reads from the walkway.
				local padAt = at(plateSide * (WALK_HALF + 2.2), surface + 0.06, z).Position
				local towardPlate = frame:VectorToWorldSpace(Vector3.new(plateSide, 0, 0))
				local cashPad = block(
					`CashPad{slot}`,
					Vector3.new(3.8, 0.12, 5.2),
					-- (a SurfaceGui on a Top face runs along the part's Z: turned so it reads across)
					CFrame.lookAt(padAt, padAt - towardPlate) * CFrame.Angles(0, math.pi / 2, 0),
					Color3.fromRGB(150, 240, 160),
					levelFolder
				)
				cashPad.Transparency = 1
				cashPad.CanCollide = false
				cashPad.CanQuery = false
				local padGui = Instance.new("SurfaceGui")
				padGui.Face = Enum.NormalId.Top
				padGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				padGui.PixelsPerStud = 40
				padGui.LightInfluence = 0
				padGui.Brightness = 0.85 -- full-bright signs, a touch softer than pure white
				padGui.MaxDistance = 70
				padGui.Parent = cashPad
				local panel = Instance.new("Frame")
				panel.AnchorPoint = Vector2.new(0.5, 0.5)
				panel.Position = UDim2.fromScale(0.5, 0.5)
				panel.Size = UDim2.new(1, -12, 1, -12)
				panel.Parent = padGui
				SignTheme.surface(panel, SignTheme.Green)
				-- Steal An Egg pad: a small "COLLECT" over the money in huge chunky numbers
				SignTheme.cashIcon(panel, UDim2.fromScale(0.05, 0.04), UDim2.fromScale(0.2, 0.3))
				local collect = Instance.new("TextLabel")
				collect.Name = "Collect"
				collect.Position, collect.Size = UDim2.fromScale(0.26, 0.06), UDim2.fromScale(0.5, 0.24)
				collect.Text = "COLLECT"
				collect.Parent = panel
				SignTheme.text(collect, 30)
				local padText = Instance.new("TextLabel")
				padText.AnchorPoint = Vector2.new(0.5, 0.5)
				padText.Name = "Amount"
				padText.Position = UDim2.fromScale(0.5, 0.64)
				padText.Size = UDim2.fromScale(0.94, 0.6)
				padText.Text = ""
				padText.Parent = panel
				SignTheme.text(padText, 90, SignTheme.NumberFont)
				cashPads[slot] = cashPad
				cashLabels[slot] = padText
				-- The knife floats upright over the plate, a little tilted
				slotCFrames[slot] = at(x, surface + 4.2, z) * CFrame.Angles(0, 0, math.rad(KNIFE_TILT))
			end
		end

		-- The owner's sign rides on top of the frame (BaseService moves it as the vault grows)
		local signPart = block("Sign", Vector3.new(20, 5, 1), at(0, 18, -VAULT_DEPTH / 2 + 1.5), NAVY, folder)
		signPart.Transparency = 1
		signPart.CanCollide = false
		signPart.CanQuery = false
		local sign = label(
			signPart,
			"Empty Vault",
			color,
			UDim2.fromScale(24, 5),
			frame:VectorToWorldSpace(Vector3.new(0, 0, 1.5))
		);
		(sign.Parent :: BillboardGui).Enabled = false

		-- The Haunted Wheel: a giant iron wheel you run inside to train Speed (the plate at the bottom
		-- is what counts as "on it"). Clients spin it while its owner is training. It stands just
		-- outside the vault's gate, so the inside is nothing but knives.
		local wheelCenter = Vector3.new(-13, 6.6, VAULT_DEPTH / 2 + 7.5)
		-- The Upgrade Base sign on the other side of the gate (client/Hud fills it in for its owner)
		local upgradeSign = Instance.new("Model")
		upgradeSign.Name = "UpgradeSign"
		block("Post", Vector3.new(0.6, 4, 0.6), at(13, 2, VAULT_DEPTH / 2 + 6), Color3.fromRGB(70, 46, 28), upgradeSign)
		local signBoard = block(
			"Board",
			Vector3.new(7, 4, 0.5),
			at(13, 5.4, VAULT_DEPTH / 2 + 6) * CFrame.Angles(math.rad(-12), 0, 0),
			Color3.fromRGB(34, 26, 40),
			upgradeSign
		)
		local signGui = Instance.new("SurfaceGui")
		signGui.Name = "Gui"
		-- The board's front (-Z) looks into the vault; its back faces the plaza
		signGui.Face = Enum.NormalId.Back
		signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		signGui.PixelsPerStud = 40
		signGui.LightInfluence = 0
		signGui.Brightness = 0.85 -- full-bright signs, a touch softer than pure white
		signGui.MaxDistance = 80
		signGui.Parent = signBoard
		upgradeSign.Parent = folder
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
		local iron = NAVY
		local radius, segments = 6, 16
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
				Color3.new(1, 1, 1),
				wheel
			)
			rung.CanCollide = false
			if k % 4 == 0 then
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
		local belt = block("WheelFloor", Vector3.new(6, 0.4, 5), at(wheelCenter.X, 0.8, wheelCenter.Z), CYAN, folder)
		Toy.Dress(belt, nil, 1, 0)
		local wheelSign =
			block("WheelSign", Vector3.new(6, 1.6, 0.4), at(wheelCenter.X, 13.2, wheelCenter.Z), NAVY, folder)
		local treadmillSign = label(wheelSign, "Creaky Wheel", color, UDim2.fromScale(9, 2), Vector3.new(0, 0.2, 1)) -- under the vault's own sign

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
			Bounds = if sideways
				then bounds(center, VAULT_DEPTH, VAULT_WIDTH)
				else bounds(center, VAULT_WIDTH, VAULT_DEPTH),
			Spawn = CFrame.lookAt(spawnPos, spawnPos + frame:VectorToWorldSpace(Vector3.zAxis)),
			SlotCFrames = slotCFrames,
			SlotPads = slotPads,
			SlotRims = slotRims,
			FloorFolders = floorFolders,
			CashPads = cashPads,
			CashLabels = cashLabels,
			Treadmill = belt,
			TreadmillSign = treadmillSign,
			Wheel = wheel,
			Sign = sign,
		})
	end

	-- The plaza between the two columns of vaults, out to the hub's outer wall
	local plaza = block(
		"Plaza",
		Vector3.new(HUB_HALF * 2, 1, HUB_BACK),
		CFrame.new(0, -0.3, -HUB_BACK / 2),
		Toy.Grass, -- the same grass as the runway: one place
		bases
	)
	Toy.Dress(plaza, nil, 1, 5)
	-- One dirt wall all the way round the hub, so you can't wander off anywhere: the two sides,
	-- the back behind the plaza, and the shoulders joining them to the runway walls
	local wallX = HUB_HALF + WALL_THICK / 2
	for _, side in { -1, 1 } do
		Toy.DirtWall(
			block(
				"HubWall",
				Vector3.new(WALL_THICK, WALL_HEIGHT, HUB_BACK + WALL_THICK * 2),
				CFrame.new(side * wallX, WALL_HEIGHT / 2, -HUB_BACK / 2),
				Toy.Dirt,
				bases
			)
		)
		local from, to = half, HUB_HALF + WALL_THICK
		Toy.DirtWall(
			block(
				"HubWall",
				Vector3.new(to - from, WALL_HEIGHT, WALL_THICK),
				CFrame.new(side * (from + to) / 2, WALL_HEIGHT / 2, WALL_THICK / 2),
				Toy.Dirt,
				bases
			)
		)
	end
	Toy.DirtWall(
		block(
			"HubWall",
			Vector3.new(HUB_HALF * 2 + WALL_THICK * 2, WALL_HEIGHT, WALL_THICK),
			CFrame.new(0, WALL_HEIGHT / 2, -HUB_BACK - WALL_THICK / 2),
			Toy.Dirt,
			bases
		)
	)
end

-- The whole hub is a floating island in the sky: under every floor hangs a studded block of earth
-- that narrows in steps, and puffy clouds drift around and below. Cosmetic only: nothing here collides.
local function buildIsland()
	local island = Instance.new("Folder")
	island.Name = "Island"
	island.Parent = root
	local rng = Random.new(77)
	local function deco(name: string, size: Vector3, cframe: CFrame, color: Color3): Part
		local p = block(name, size, cframe, color, island)
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		return p
	end

	local half = GameConfig.ArenaWidth / 2
	local runwayEnd = GameConfig.ZoneDepth * #GameConfig.Zones
	local footprints = {
		{ -half - WALL_THICK, half + WALL_THICK, 0, runwayEnd + WALL_THICK }, -- the runway
		{ -HUB_HALF - WALL_THICK, HUB_HALF + WALL_THICK, -HUB_BACK - WALL_THICK, WALL_THICK }, -- plaza + vaults
		{ -72, 72, runwayEnd, runwayEnd + 52 }, -- the Manor
	}
	-- Earth under each floor: three layers, each narrower and darker, studs on the sides
	local layers = {
		{ Inset = 0, Height = 7, Color = Color3.fromRGB(160, 108, 62) },
		{ Inset = 10, Height = 12, Color = Color3.fromRGB(132, 88, 52) },
		{ Inset = 26, Height = 16, Color = Color3.fromRGB(104, 70, 46) },
	}
	local sides = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }
	for _, f in footprints do
		local minX, maxX, minZ, maxZ = f[1], f[2], f[3], f[4]
		local top = -0.8
		for _, layer in layers do
			local sizeX = maxX - minX - layer.Inset * 2
			local sizeZ = maxZ - minZ - layer.Inset * 2
			if sizeX > 4 and sizeZ > 4 then
				local slab = deco(
					"Earth",
					Vector3.new(sizeX, layer.Height, sizeZ),
					CFrame.new((minX + maxX) / 2, top - layer.Height / 2, (minZ + maxZ) / 2),
					layer.Color
				)
				Toy.Dress(slab, sides, 1, 4)
			end
			top -= layer.Height
		end
	end

	-- Puffy cartoon clouds: clusters of white balls around the island and drifting far below it
	local function cloud(at: Vector3, scale: number)
		for _ = 1, rng:NextInteger(4, 7) do
			local size = rng:NextNumber(10, 22) * scale
			local puff = deco(
				"Cloud",
				Vector3.new(size, size * 0.8, size),
				CFrame.new(
					at
						+ Vector3.new(
							rng:NextNumber(-1.6, 1.6) * size,
							rng:NextNumber(0, 0.4) * size,
							rng:NextNumber(-0.8, 0.8) * size
						)
				),
				Color3.fromRGB(250, 252, 255)
			)
			puff.Shape = Enum.PartType.Ball
		end
	end
	for _ = 1, 28 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		cloud(
			Vector3.new(side * rng:NextNumber(190, 480), rng:NextNumber(-90, 50), rng:NextNumber(-350, runwayEnd + 250)),
			rng:NextNumber(0.8, 1.6)
		)
	end
	for _ = 1, 16 do
		cloud(
			Vector3.new(rng:NextNumber(-260, 260), rng:NextNumber(-160, -80), rng:NextNumber(-300, runwayEnd + 200)),
			rng:NextNumber(1.2, 2)
		)
	end
	-- Overhead: drifting above the runway and plaza, high enough to never get in the way
	for _ = 1, 45 do
		cloud(
			Vector3.new(rng:NextNumber(-220, 220), rng:NextNumber(85, 150), rng:NextNumber(-350, runwayEnd + 150)),
			rng:NextNumber(1, 2.2)
		)
	end
	-- Just past the walls at eye level, so the sky around you is full of them
	for _ = 1, 30 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		cloud(
			Vector3.new(side * rng:NextNumber(150, 230), rng:NextNumber(20, 70), rng:NextNumber(-320, runwayEnd + 100)),
			rng:NextNumber(0.9, 1.6)
		)
	end
end

-- Round maps are real buildings (RoundMaps); a random one is rebuilt at the start of each round
function MapService.RoundMapFolder(): Instance?
	return root and root:FindFirstChild("RoundMap")
end

local ROUND_SCALE = 1.5 -- the buildings are built at 1x and scaled up: roomier, longer chases

function MapService.BuildRoundMap(name: string?): RoundMaps.Built
	local built = RoundMaps.Build(root, MapService.RoundCenter, name)
	local center = MapService.RoundCenter
	local folder = root:FindFirstChild("RoundMap")
	if folder then
		-- People stay the same size, so everything around them gets bigger
		local model = Instance.new("Model")
		for _, child in folder:GetChildren() do
			child.Parent = model
		end
		model.WorldPivot = CFrame.new(center)
		model:ScaleTo(ROUND_SCALE)
		for _, child in model:GetChildren() do
			child.Parent = folder
		end
		model:Destroy()
		for i, spawn in built.Spawns do
			built.Spawns[i] = CFrame.new(center + (spawn.Position - center) * ROUND_SCALE) * spawn.Rotation
		end
		built.Size *= ROUND_SCALE
	end
	MapService.RoundSpawns = built.Spawns
	MapService.RoundMapSize = built.Size
	return built
end

-- Sunny day everywhere: one even light, so lamps, torches, auras, glowing knives and the round
-- maps' room lamps carry no Light (neon and particles still glow).
local function noLights()
	local function check(instance: Instance)
		if instance:IsA("Light") then
			instance:Destroy()
		end
	end
	for _, d in workspace:GetDescendants() do
		check(d)
	end
	workspace.DescendantAdded:Connect(function(d)
		if d:IsA("Light") then
			task.defer(check, d)
		end
	end)
end

-- Shows the vault's first `count` storeys (the rest wait out of the world until they're bought)
function MapService.SetFloors(base: BaseSite, count: number)
	for level, levelFolder in base.FloorFolders do
		levelFolder.Parent = if level <= count then base.Folder else nil
	end
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
	buildIsland()
	ManorDecor.Build(root, MapService.Arena :: Bounds, MapService.Hideaways)
	-- Nothing from the plaza decor in the way of the wheels outside the vault gates
	for _, base in MapService.Bases do
		ManorDecor.ClearArea((base.Wheel.PrimaryPart :: BasePart).Position, 9, 9)
		MapService.SetFloors(base, 1)
	end
	MapService.BuildRoundMap("Office")
	noLights()
end

return MapService
