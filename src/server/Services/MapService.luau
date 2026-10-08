--!strict
-- Builds the world in code so the whole layout lives in git. The hub is Blackwood Manor at night,
-- laid out like the big steal games: one long straight runway between tall stone walls, the
-- zones one after another down it, the vaults at the start. (Decoration lives in ManorDecor.)
-- Layout (top-down, +Z is "deeper"):
--
--   z = 1840+          the Manor
--   z = 1470..1840 ║ Cosmic     ║    Outer Space
--   z = 1140..1470 ║ Celestial  ║    The Heavens
--   z = 850..1140  ║ Godly      ║    Mount Olympus
--   z = 600..850   ║ Mythic     ║    The Inferno
--   z = 390..600   ║ Legendary  ║    runway: ArenaWidth (160) wide, cumulative depths;
--   z = 220..390   ║ Epic       ║    bosses chase all the way back to the plaza
--   z = 90..220    ║ Rare       ║
--   z = 0..90      ║ Common     ║
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
local BiomeSprites = require(script.Parent.BiomeSprites)
local RoundMaps = require(script.Parent.RoundMaps)
local VaultWalls = require(script.Parent.VaultWalls)
local PenWalls = require(script.Parent.PenWalls)
local PenMode = require(ReplicatedStorage.Shared.PenMode)
local SignTheme = require(ReplicatedStorage.Shared.SignTheme)
local WorldSignModel = require(ReplicatedStorage.Shared.WorldSignModel)
local Toy = require(ReplicatedStorage.Shared.Toy)
local WheelModel = require(ReplicatedStorage.Shared.WheelModel)
local VaultModel = require(ReplicatedStorage.Shared.VaultModel)

export type Bounds = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
export type BaseSite = {
	Index: number,
	Color: Color3, -- this vault's own colour (wall strip, gate glow)
	Folder: Folder,
	WallFolder: Folder, -- rebuilt by VaultWalls whenever the owner's wall tier changes
	Gate: Model,
	Blocker: Part, -- the invisible gate marker (attributes: Owner, OwnerName, Tier, Floors, PenDepth)
	SignPart: Part,
	Center: Vector3,
	Frame: CFrame, -- local +Z points out of the vault's open side, towards the plaza
	Bounds: Bounds,
	Spawn: CFrame,
	SlotCFrames: { CFrame }, -- where each knife floats, over its pedestal
	SlotPads: { BasePart }, -- each pedestal's stone (holds the prompts)
	SlotRims: { BasePart }, -- state proxy; VaultModel updates the octagon's individual glow blocks
	PlateArts: { ImageLabel }, -- retained artwork hooks, hidden on the native block-built plates
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
MapService.RoundLevels = 1 -- storeys in the current round map
MapService.RoundStorey = 15 -- floor-to-floor height in the current round map (scaled)
MapService.LobbySpawn = CFrame.new(0, 4, -110)
-- Biomes dressed by a Codex-built shell (src/shared/Assets/<Name>Shell): zone index -> module name.
-- Their old wall looks and ManorDecor's random props are switched off (ManorDecor reads this too).
local BIOME_SHELLS: { [number]: string } = {
	[1] = "CourtyardShell",
	[2] = "GardensShell",
	[3] = "CryptsShell",
	[4] = "CatacombsShell",
	[5] = "InfernoShell",
	[6] = "OlympusShell",
	[7] = "HeavensShell",
	[8] = "OuterSpaceShell",
}
MapService.BiomeShells = BIOME_SHELLS

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

function MapService.ZoneAt(position: Vector3): number?
	if math.abs(position.X) > GameConfig.ArenaWidth / 2 then
		return nil
	end
	return GameConfig.ZoneAtZ(position.Z)
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

-- A sunny afternoon, mid-sky (Steal An Egg style): a real sun angled enough that every wall gets a
-- lit face and a shaded face (not just overhead), everything throws a clear contact shadow, blue
-- sky all round (also below: the map floats), soft clouds.
-- (`Lighting.Technology` is gone from this Roblox version - `LightingStyle` replaced it and Studio
-- already defaults it to a shadow-capable style. Nothing to flip by hand any more. If shadows ever
-- look flat again in a Studio Play-test, check `settings():GetService("RenderSettings").QualityLevel`
-- first - Studio pins test sessions to its lowest tier, which silently drops shadows regardless of
-- Lighting.GlobalShadows. Not a issue for real players: their own Graphics setting controls this.)
local function buildLighting()
	-- Mid-afternoon, the sun ~35 degrees up in the north-west (Roblox north = -Z, west = -X): light
	-- falls toward the south-east at a real angle, so everything throws a readable shadow AND the
	-- runway's side walls (facing +-X) get a lit face and a shaded face instead of flat even light.
	-- (Found by searching ClockTime/latitude for GetSunDirection ~ (-0.57, 0.57, 0.59).)
	-- The tall boundary walls don't cast (Toy.DirtWall), or they'd shade half the arena.
	Lighting.ClockTime = 15
	Lighting.GeographicLatitude = 60
	-- A punchier sun now that it's doing real modelling work (shading + shadows), with ambient
	-- turned down from "flat and bright" to let that contrast actually read instead of washing out.
	Lighting.Brightness = 3.5
	Lighting.ExposureCompensation = 0
	-- Warm but no longer doing ALL the work: the sun now lights the walls directly (see above), so
	-- ambient only needs to keep the shaded side readable, not carry the whole wall on its own.
	-- The round maps' warm, neutral fill (rounds read clean and even), with the sun on top
	Lighting.Ambient = Color3.fromRGB(110, 105, 100)
	Lighting.OutdoorAmbient = Color3.fromRGB(115, 110, 105)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 252, 245)
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0
	-- Clients restore these after a round (client/Effects)
	Lighting:SetAttribute("HubAmbient", Lighting.Ambient)
	Lighting:SetAttribute("HubOutdoor", Lighting.OutdoorAmbient)
	-- Real shadows (with the sun overhead, just a small one under each character)
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.15 -- crisp enough to read
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") or child:IsA("PostEffect") or child:IsA("Sky") then
			child:Destroy()
		end
	end
	-- A soft, pale haze with distance (things far below or far away go lighter, close up stays crisp)
	local atmosphere = Instance.new("Atmosphere")
	-- Steal An Egg's sky: a natural warm-white sun haze, not a colour filter - it should look like
	-- real atmosphere, not like the whole world is underwater. (The old cyan version, kept until
	-- now, tinted every distant surface teal; every OTHER zone already had to hand-correct for it -
	-- see ZoneLighting's "fixes it reading cold under the cyan" comment on Inferno. This is that fix
	-- for the Courtyard/base look itself, not another zone papering over it.)
	atmosphere.Density = 0.22
	atmosphere.Offset = 0.3
	atmosphere.Color = Color3.fromRGB(255, 248, 235)
	atmosphere.Decay = Color3.fromRGB(220, 208, 192)
	atmosphere:SetAttribute("HubColor", atmosphere.Color)
	atmosphere:SetAttribute("HubDecay", atmosphere.Decay)
	atmosphere.Glare = 4 -- the big soft bloom of light around the sun
	atmosphere.Haze = 1.2 -- natural sun haze, not a cyan wash
	atmosphere.Parent = Lighting
	local sky = Instance.new("Sky")
	-- Roblox's own soft sky (the painted Textures.Day box read deep blue and flat next to Brainrot's)
	sky.StarCount = 0
	sky.CelestialBodiesShown = true -- the real sun, matching the shadows
	sky.SunAngularSize = 21
	sky.MoonAngularSize = 0
	sky.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 1 -- the sun glows; the threshold keeps the world itself crisp
	bloom.Size = 56
	bloom.Threshold = 1.6
	local rays = Instance.new("SunRaysEffect")
	-- Light streaming out of the sun (that lifelike glow you see looking up at it)
	rays.Intensity = 0.28
	rays.Spread = 0.85
	rays.Parent = Lighting
	bloom.Parent = Lighting
	local grade = Instance.new("ColorCorrectionEffect")
	-- Punchy and bright, like Tsunami: extra saturation and a little contrast (muted read gloomy)
	grade.Contrast = 0.1
	grade.Saturation = 0.12
	grade.TintColor = Color3.fromRGB(255, 253, 248)
	grade.Brightness = 0
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

local WALL_HEIGHT = 120 -- tall walls (Tsunami): a full 4-floor vault (~96) stays under; the sun stays in view
local WALL_THICK = 6
local STONE = Color3.fromRGB(98, 92, 150)
-- Tsunami's walls are a vivid orange-red brick, not dull dirt
local HUB_BRICK = Color3.fromRGB(232, 112, 62)

-- Runway walls take on a hint of the colour of the zone they're in
local function zoneTint(z: number): Color3
	local index = GameConfig.ZoneAtZ(z) or #GameConfig.Zones
	local floor = ZONE_FLOORS[GameConfig.Zones[index].Rarity] or STONE
	return floor:Lerp(Color3.new(0, 0, 0), 0.32)
end

-- The runway: zone floors one after another, tall walls with hideaway nooks cut into them
local function buildArena()
	local width = GameConfig.ArenaWidth
	local totalDepth = GameConfig.TotalZoneDepth()
	MapService.Arena = { MinX = -width / 2, MaxX = width / 2, MinZ = 0, MaxZ = totalDepth }

	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	arena.Parent = root

	for i, zone in GameConfig.Zones do
		local z0, depth = GameConfig.ZoneStart(i), GameConfig.ZoneDepthFor(i)
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
			local z0, depth = GameConfig.ZoneStart(i), GameConfig.ZoneDepthFor(i)
			local wall = block(
				"RunwayWall",
				Vector3.new(WALL_THICK, WALL_HEIGHT, depth),
				CFrame.new(x, WALL_HEIGHT / 2, z0 + depth / 2),
				zoneTint(z0 + depth / 2),
				arena
			)
			local cap = Toy.DirtWall(wall, ZONE_WALLS[GameConfig.Zones[i].Rarity])
			-- Biomes with a Codex shell (MapService.BuildBiomeShells) wear it instead: the wall stays
			-- (same size, place and collision), only its looks go. Early lawns keep plain visible walls.
			if BIOME_SHELLS[i] and i >= 3 then
				for _, part in { wall, cap } do
					part.Transparency = 1
					for _, d in part:GetDescendants() do
						if d:IsA("Decal") then -- (a Texture is a Decal too)
							(d :: Decal).Transparency = 1
						end
					end
				end
			end
		end
	end
	-- The far end, in the last zone's wall colour (it closes off that biome)
	local farWall = block(
		"RunwayEnd",
		Vector3.new(width + WALL_THICK * 2, WALL_HEIGHT, WALL_THICK),
		CFrame.new(0, WALL_HEIGHT / 2, totalDepth + WALL_THICK / 2),
		STONE,
		arena
	)
	Toy.DirtWall(farWall, ZONE_WALLS[GameConfig.Zones[#GameConfig.Zones].Rarity])

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
	local safeGui = SignTheme.face(paint, Enum.NormalId.Top, 20, 300)
	local safeText = Instance.new("TextLabel")
	safeText.Size = UDim2.fromScale(1, 1)
	safeText.BackgroundTransparency = 1
	safeText.Font = Enum.Font.FredokaOne
	safeText.TextScaled = true
	safeText.TextColor3 = Color3.new(1, 1, 1)
	safeText.TextTransparency = 0.15
	safeText.Text = "🛡 SAFE ZONE 🛡"
	safeText.Rotation = 180 -- reads the right way round walking up from the plaza
	safeText.Parent = safeGui
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
local VAULT_DECK = VaultModel.Deck
local HUB_HALF: number = GameConfig.ArenaWidth / 2 + VAULT_DEPTH + 0.5 -- the hub's outer wall (inner face), just behind the vaults
local COLUMN = 6 -- vaults down each side; 4 more across the back
local HUB_BACK: number = COLUMN * 40 + 44 -- the hub ends right behind the back row of vaults
-- (pens: where the side walls step in behind the front row - the back row has fewer pens, so its
-- outer corners would be empty grass)
local HUB_STEP: { X: number, Z: number }? = nil
local NAVY = Color3.fromRGB(40, 44, 90)
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
	-- Pens (Shared/PenMode): fewer, bigger, flat - 5 down each side, the back of the plaza left open
	local pens = PenMode.On()
	local penWidth = GameConfig.Pens.Width
	-- (a pen's full length, or a vault's depth: everything below is laid out from it)
	local DEPTH = if pens then GameConfig.Pens.Depth else VAULT_DEPTH
	-- Pens sit in a compact block right behind the safe zone (Steal an Egg: home is a few steps
	-- from the runway): 3 columns each side of the central walkway (monument, map vote, merchant),
	-- 2 rows deep, gates facing the runway. Numbered nearest-first, so players get the closest pen.
	local penCentres: { Vector3 } = {}
	if pens then
		local walkway = 24 -- (half-width: the vote boards and monument stand in it)
		local front = 48 -- (the strip behind the safe zone: shops, chest, the first row's wheels)
		local aisle = 24 -- (between the rows: the second row's wheels and signs)
		local cols = math.ceil(GameConfig.Pens.Count / 4)
		for row = 0, 1 do
			for col = 0, cols - 1 do
				for _, side in { -1, 1 } do
					local x = side * (walkway + 5 + penWidth / 2 + col * (penWidth + 10))
					local z = -(front + DEPTH / 2 + row * (DEPTH + aisle))
					table.insert(penCentres, Vector3.new(x, 0, z))
				end
			end
		end
		table.sort(penCentres, function(a, b)
			return a.Magnitude < b.Magnitude
		end)
		HUB_HALF = walkway + 5 + cols * (penWidth + 10)
		-- (just behind the back row: the merchant and the map vote stand in the walkway)
		HUB_BACK = front + 2 * DEPTH + aisle + 26
		-- the pens actually used (nearest first): the back row may not fill every column
		local backCols = math.ceil(math.max(0, GameConfig.Pens.Count - 2 * cols) / 2)
		if backCols < cols then
			HUB_STEP = { X = walkway + 5 + backCols * (penWidth + 10), Z = front + DEPTH + aisle / 2 }
		end
		MapService.LobbySpawn = CFrame.new(0, 4, -30)
	end
	if pens then
		MapService.MaxBases = GameConfig.Pens.Count
	end

	for i = 1, MapService.MaxBases do
		task.wait() -- (one vault a frame: never trips the script timeout)
		-- 1-6 down the left side, 7-12 down the right, 13-16 across the back of the plaza
		local center: Vector3, frame: CFrame
		local sideways = not pens and i <= COLUMN * 2
		if pens then
			center = penCentres[i]
			frame = CFrame.new(center) -- (local +Z, the gate side, faces the runway)
		elseif sideways then
			local side = if i <= COLUMN then -1 else 1
			local row = (i - 1) % COLUMN
			center = Vector3.new(side * (half + DEPTH / 2), 0, -20 - row * VAULT_SPACING)
			-- Rotate so local +Z faces the plaza (the left column faces +X, the right column -X)
			frame = CFrame.new(center) * CFrame.Angles(0, math.rad(if side < 0 then 90 else -90), 0)
		else
			local k = i - COLUMN * 2
			center =
				Vector3.new(-half + VAULT_WIDTH / 2 + (k - 1) * VAULT_WIDTH, 0, -COLUMN * VAULT_SPACING - DEPTH / 2)
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
		-- (a pen: a patch of bright grass inside its fence)
		if pens then
			local grass =
				block("Floor", Vector3.new(penWidth, 1, DEPTH), at(0, 0.1, 0), Color3.fromRGB(86, 196, 56), folder)
			Toy.Dress(grass, { Enum.NormalId.Top }, 1, 4)
		else
			block("Floor", Vector3.new(VAULT_WIDTH, 1, DEPTH), at(0, 0.1, 0), VAULT_DECK, folder)
		end
		-- Walls, gate towers and the gate itself depend on the owner's wall tier (VaultWalls)
		local wallFolder = Instance.new("Folder")
		wallFolder.Name = "Walls"
		wallFolder.Parent = folder
		local walls = if pens
			then PenWalls.Build(wallFolder, frame, color, 1)
			else VaultWalls.Build(wallFolder, frame, color, 1)
		-- The storeys. Each has its own folder so the vault can grow: decks with a hole at the back
		-- middle, a ladder up from the floor below, a glass rail along the open front, the walkway
		-- and ten plates (slots 1-10 ground, 11-20 next floor, ...)
		local deckColor = VAULT_DECK
		local floorFolders: { Folder } = {}
		local slotCFrames: { CFrame }, slotPads: { BasePart }, slotRims: { BasePart } = {}, {}, {}
		local cashPads: { BasePart }, cashLabels: { TextLabel } = {}, {}
		local plateArts: { ImageLabel } = {}
		local inner = VAULT_WIDTH / 2 - 0.5
		local back, front = -DEPTH / 2 + 0.5, DEPTH / 2 - 0.5
		if pens then
			-- No storeys or plates: invisible spots on the grass, one per knife (coffins wait on them,
			-- raid prompts hang on them; the knives themselves hop around - BaseService). Walking in
			-- collects your money, so every spot's "cash pad" is the spot itself.
			local levelFolder = Instance.new("Folder")
			levelFolder.Name = "Floor1"
			levelFolder.Parent = folder
			floorFolders[1] = levelFolder
			local cols, rows = 8, 5
			for slot = 1, cols * rows do
				local c, r = (slot - 1) % cols, (slot - 1) // cols
				local x = (c - (cols - 1) / 2) * ((penWidth - 10) / (cols - 1))
				local z = (r - (rows - 1) / 2) * ((DEPTH - 14) / (rows - 1)) - 2
				local spot = block(`Spot{slot}`, Vector3.new(3, 0.2, 3), at(x, 0.7, z), NAVY, levelFolder)
				spot.Transparency = 1
				spot.CanCollide, spot.CanQuery, spot.CanTouch = false, false, false
				spot.Name = `CashPad{slot}` -- (client/Places reads money waiting off these)
				slotPads[slot] = spot
				slotRims[slot] = spot
				cashPads[slot] = spot
				cashLabels[slot] = Instance.new("TextLabel") -- (unshown: money pops off the knives)
				slotCFrames[slot] = at(x, 4.2, z)
			end
		end
		for level = 1, if pens then 0 else FLOORS do
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
					block(
						"Deck",
						Vector3.new(maxX - minX, 1, maxZ - minZ),
						at((minX + maxX) / 2, y - 0.5, (minZ + maxZ) / 2),
						deckColor,
						levelFolder
					)
				end
				deck(-inner, inner, back, landing) -- the landing
				deck(-inner, inner, holeTo, front) -- the floor
				for _, deckSide in { -1, 1 } do
					local a, b = deckSide * LADDER_HOLE_HALF, deckSide * inner
					deck(math.min(a, b), math.max(a, b), landing, holeTo)
				end
				-- A slim navy edge along the open front (no glass rail, Tsunami style)
				block("RailCap", Vector3.new(inner * 2, 0.4, 0.6), at(0, y + 0.2, front - 0.2), NAVY, levelFolder)
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
				-- The visible block ladder is cosmetic; the original TrussPart stays climbable.
				VaultModel.BuildLadder(levelFolder, frame, bottom, landing + 1)
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
					local edge =
						block("HoleTrim", trim[1], at(trim[2].X, trim[2].Y, trim[2].Z), VaultModel.Cyan, levelFolder)
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
				Color3.fromRGB(206, 210, 226), -- grey walkway against the lavender floor
				levelFolder
			)
			walk.CanCollide = false
			walk.CanQuery = false
			VaultModel.BuildFloor(levelFolder, frame, surface)
			for index = 1, SLOTS_PER_FLOOR do
				local plateSide = if index <= #PLATE_Z then -1 else 1
				local x, z = plateSide * PLATE_X, PLATE_Z[(index - 1) % #PLATE_Z + 1]
				local slot = (level - 1) * SLOTS_PER_FLOOR + index
				local builtPlate = VaultModel.BuildPlate(levelFolder, at(x, surface, z), slot)
				slotPads[slot] = builtPlate.Pad
				slotRims[slot] = builtPlate.Rim
				VaultModel.SetPlateTier(builtPlate.Details, at(x, surface, z), 1)
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
				local padArt = block(
					`CashPadArt{slot}`,
					Vector3.new(2.6, 0.05, 5.6),
					cashPad.CFrame * CFrame.new(0, 0.04, 0),
					NAVY,
					levelFolder
				)
				padArt.CanCollide, padArt.CanTouch, padArt.CanQuery = false, false, false
				-- Tsunami: a simple green pill with the money in it (a Top-face canvas runs along Z)
				padArt.Transparency = 1
				local padText = SignTheme.cashPill(SignTheme.face(padArt, Enum.NormalId.Top, 60, 70))
				cashPads[slot] = cashPad
				cashLabels[slot] = padText
				-- The knife floats upright over the plate, a little tilted
				slotCFrames[slot] = at(x, surface + 4.2, z) * CFrame.Angles(0, 0, math.rad(KNIFE_TILT))
			end
			VaultModel.ApplyTier(levelFolder, 1)
		end

		-- The owner's sign rides on top of the frame (BaseService moves it as the vault grows)
		local signPart = block("Sign", Vector3.new(20, 5, 1), at(0, 18, -DEPTH / 2 + 1.5), NAVY, folder)
		signPart.Transparency = 1
		signPart.CanCollide = false
		signPart.CanQuery = false
		-- (no board on the back any more: the owner's name floats over the entrance and your own vault
		-- has the YOUR BASE house - client/BaseMarkers. The label stays, hidden, for BaseService.)
		local ownerGui = Instance.new("SurfaceGui")
		ownerGui.Name = "OwnerGui"
		ownerGui.Enabled = false
		ownerGui.Parent = signPart
		local sign = WorldSignModel.LiveText(ownerGui, "Owner", "Empty Vault", color)

		-- The Haunted Wheel: a giant iron wheel you run inside to train Speed (the plate at the bottom
		-- is what counts as "on it"). Clients spin it while its owner is training. It stands just
		-- outside the vault's gate, so the inside is nothing but knives.
		local wheelCenter = Vector3.new(-13, 6.6, DEPTH / 2 + 7.5)
		-- Tsunami / Steal An Egg signs (client/Hud fills them in for their owner): Upgrade Base on the
		-- other side of the gate (the next floor), Upgrade Wheel in front of the Haunted Wheel (the next
		-- wheel or trail, with a small Robux board under it: RobuxBoard)
		local function upgradeSignAt(signName: string, x: number, z: number, titleText: string): Model
			local upgradeSign = Instance.new("Model")
			upgradeSign.Name = signName
			-- Tsunami's Upgrade Base sign: a dark post and board (3D), the info flat on its face (2D):
			-- a white title over one bright green pill with a house, the price and the floor count
			local SIGN_DARK = Color3.fromRGB(26, 28, 38)
			block("Post", Vector3.new(0.7, 3, 0.7), at(x, 1.5, z), SIGN_DARK, upgradeSign)
			local signBoard = block(
				"Board",
				Vector3.new(7, 4, 0.35),
				-- Standing straight up (not leaning back) on top of the post, not sunk into it
				at(x, 5, z) * CFrame.Angles(0, math.pi, 0),
				SIGN_DARK,
				upgradeSign
			)
			local signGui = Instance.new("SurfaceGui")
			signGui.Name = "Gui"
			signGui.Face = Enum.NormalId.Front
			signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			signGui.PixelsPerStud = 60
			signGui.LightInfluence = 0
			signGui.MaxDistance = 80
			signGui.Parent = signBoard
			local function signText(
				name: string,
				parent: Instance,
				text: string,
				tint: Color3,
				font: Enum.Font
			): TextLabel
				local label = Instance.new("TextLabel")
				label.Name = name
				label.BackgroundTransparency = 1
				label.Font = font
				label.TextScaled = true
				label.TextColor3 = tint
				label.Text = text
				local stroke = Instance.new("UIStroke")
				stroke.Color, stroke.Thickness = Color3.fromRGB(14, 16, 24), 3
				stroke.Parent = label
				label.Parent = parent
				return label
			end
			local title = signText("Title", signGui, titleText, Color3.new(1, 1, 1), Enum.Font.FredokaOne)
			title.Position, title.Size = UDim2.fromScale(0.04, 0.04), UDim2.fromScale(0.8, 0.28) -- (clear of the "!")
			-- The same pill as the vault's cash pads (SignTheme.cashPill), a touch darker: mint with a
			-- violet edge and the big green number, the floor count under it
			local pillHolder = Instance.new("Frame")
			pillHolder.Name = "PillHolder"
			pillHolder.BackgroundTransparency = 1
			pillHolder.Position, pillHolder.Size = UDim2.fromScale(0.04, 0.34), UDim2.fromScale(0.92, 0.62)
			pillHolder.Parent = signGui
			local price = SignTheme.cashPill(pillHolder)
			price.Name = "Price"
			price.Position, price.Size = UDim2.fromScale(0.5, 0.4), UDim2.fromScale(0.9, 0.62)
			local pill = price.Parent :: Frame
			pill.Name = "Pill"
			pill.BackgroundColor3 = Color3.fromRGB(105, 185, 115)
			pill.BackgroundTransparency = 0.05
			local count = signText("Count", pill, "", Color3.fromRGB(30, 110, 30), Enum.Font.GothamBlack)
			count.AnchorPoint = Vector2.new(0.5, 0)
			count.Position, count.Size = UDim2.fromScale(0.5, 0.7), UDim2.fromScale(0.6, 0.26)
			local countStroke = count:FindFirstChildOfClass("UIStroke")
			if countStroke then
				countStroke.Thickness = 0
			end
			local alert = signText("Alert", signGui, "!", Color3.fromRGB(255, 60, 60), Enum.Font.LuckiestGuy)
			alert.Position, alert.Size = UDim2.fromScale(0.86, -0.08), UDim2.fromScale(0.14, 0.4)
			alert.Visible = false
			upgradeSign.Parent = folder
			return upgradeSign
		end
		upgradeSignAt("UpgradeSign", 13, DEPTH / 2 + 6, "Upgrade Base")
		local wheelUpgrade = upgradeSignAt("WheelUpgradeSign", -13, DEPTH / 2 + 15.5, "Upgrade Wheel")
		local robuxBoard = block(
			"RobuxBoard",
			Vector3.new(3.2, 1.2, 0.35),
			at(-13, 2.3, DEPTH / 2 + 16.1) * CFrame.Angles(0, math.pi, 0),
			Color3.fromRGB(0, 176, 111),
			wheelUpgrade
		)
		local robuxGui = Instance.new("SurfaceGui")
		robuxGui.Name = "Gui"
		robuxGui.Face = Enum.NormalId.Front
		robuxGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		robuxGui.PixelsPerStud = 60
		robuxGui.LightInfluence = 0
		robuxGui.MaxDistance = 80
		robuxGui.Parent = robuxBoard
		local robuxText = Instance.new("TextLabel")
		robuxText.Name = "Price"
		robuxText.Size = UDim2.fromScale(1, 1)
		robuxText.BackgroundTransparency = 1
		robuxText.Font = Enum.Font.FredokaOne
		robuxText.TextScaled = true
		robuxText.TextColor3 = Color3.new(1, 1, 1)
		robuxText.Text = ""
		robuxText.Parent = robuxGui
		local robuxStroke = Instance.new("UIStroke")
		robuxStroke.Thickness = 3
		robuxStroke.Color = Color3.fromRGB(10, 60, 40)
		robuxStroke.Parent = robuxText
		local builtWheel = WheelModel.Build(1, at(wheelCenter.X, wheelCenter.Y, wheelCenter.Z))
		local wheel = builtWheel.Rotor
		wheel:AddTag("HauntedWheel")
		wheel.Parent = folder
		builtWheel.Stand.Parent = folder
		-- The plate you stand on inside the bottom of the wheel
		local belt = block(
			"WheelFloor",
			Vector3.new(6, 0.4, 5),
			at(wheelCenter.X, 0.8, wheelCenter.Z),
			Color3.fromRGB(80, 228, 255),
			folder
		)
		belt.Transparency = 1 -- the tier's moving tread blocks are the visible running surface
		local wheelSign =
			block("WheelSign", Vector3.new(6, 2.4, 0.4), at(wheelCenter.X, 15.2, wheelCenter.Z), NAVY, folder)
		-- No board: the wheel's name just floats over it, like the shop stalls' titles
		wheelSign.Transparency = 1
		wheelSign.CanCollide, wheelSign.CanQuery, wheelSign.CanTouch = false, false, false
		local wheelTitle = Instance.new("BillboardGui")
		wheelTitle.Name = "TierGui"
		wheelTitle.Size = UDim2.fromScale(9, 1.8) -- studs: smaller with distance
		wheelTitle.MaxDistance = 90
		wheelTitle.LightInfluence = 0
		wheelTitle.Adornee = wheelSign
		wheelTitle.Parent = wheelSign
		local treadmillSign = Instance.new("TextLabel")
		treadmillSign.Name = "Tier"
		treadmillSign.Size = UDim2.fromScale(1, 1)
		treadmillSign.BackgroundTransparency = 1
		treadmillSign.Font = Enum.Font.FredokaOne
		treadmillSign.TextScaled = true
		treadmillSign.TextColor3 = Color3.new(1, 1, 1)
		treadmillSign.Text = "Creaky Wheel"
		treadmillSign.Parent = wheelTitle
		local titleGradient = Instance.new("UIGradient")
		titleGradient.Rotation = 90
		titleGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), color:Lerp(Color3.new(1, 1, 1), 0.35))
		titleGradient.Parent = treadmillSign
		local titleStroke = Instance.new("UIStroke")
		titleStroke.Thickness = 3
		titleStroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.65)
		titleStroke.Parent = treadmillSign

		-- Spawn just inside the door, facing out towards the plaza and the runway
		local spawnPos = (at(0, 4, DEPTH / 2 - 10)).Position
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
			Bounds = if pens
				then bounds(center, penWidth, DEPTH)
				elseif sideways then bounds(center, DEPTH, VAULT_WIDTH)
				else bounds(center, VAULT_WIDTH, DEPTH),
			Spawn = CFrame.lookAt(spawnPos, spawnPos + frame:VectorToWorldSpace(Vector3.zAxis)),
			SlotCFrames = slotCFrames,
			SlotPads = slotPads,
			SlotRims = slotRims,
			PlateArts = plateArts,
			FloorFolders = floorFolders,
			CashPads = cashPads,
			CashLabels = cashLabels,
			Treadmill = belt,
			TreadmillSign = treadmillSign,
			Wheel = wheel,
			Sign = sign,
		})
	end

	-- The plaza between the two columns of vaults, out to the hub's outer wall (pens: narrower
	-- behind the front row, where the walls step in)
	local step = HUB_STEP
	local plazas: { { number } } = if step
		then {
			{ HUB_HALF, 0, step.Z },
			{ step.X, step.Z, HUB_BACK },
		}
		else { { HUB_HALF, 0, HUB_BACK } }
	for _, piece in plazas do
		local halfWidth, fromZ, toZ = piece[1], piece[2], piece[3]
		local plaza = block(
			"Plaza",
			Vector3.new(halfWidth * 2, 1, toZ - fromZ),
			CFrame.new(0, -0.3, -(fromZ + toZ) / 2),
			Toy.Grass, -- the same grass as the runway: one place
			bases
		)
		Toy.Dress(plaza, nil, 1, 5)
	end
	-- No shadows anywhere in the vaults (decks, frames, roofs): the insides stay bright
	for _, d in bases:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = false
		end
	end
	-- One dirt wall all the way round the hub, so you can't wander off anywhere: the two sides,
	-- the back behind the plaza, and the shoulders joining them to the runway walls
	local wallX = HUB_HALF + WALL_THICK / 2
	local backHalf = if step then step.X else HUB_HALF
	for _, side in { -1, 1 } do
		if step then
			-- out at full width past the front row, then in round the empty back corner
			Toy.DirtWall(
				block(
					"HubWall",
					Vector3.new(WALL_THICK, WALL_HEIGHT, step.Z + WALL_THICK * 2),
					CFrame.new(side * wallX, WALL_HEIGHT / 2, -step.Z / 2),
					Toy.Dirt,
					bases
				)
			)
			Toy.DirtWall(
				block(
					"HubWall",
					Vector3.new(HUB_HALF - step.X + WALL_THICK, WALL_HEIGHT, WALL_THICK),
					CFrame.new(side * (HUB_HALF + step.X + WALL_THICK) / 2, WALL_HEIGHT / 2, -step.Z - WALL_THICK / 2),
					Toy.Dirt,
					bases
				)
			)
			Toy.DirtWall(
				block(
					"HubWall",
					Vector3.new(WALL_THICK, WALL_HEIGHT, HUB_BACK - step.Z + WALL_THICK),
					CFrame.new(
						side * (step.X + WALL_THICK / 2),
						WALL_HEIGHT / 2,
						-(step.Z + HUB_BACK) / 2 - WALL_THICK / 2
					),
					Toy.Dirt,
					bases
				)
			)
		else
			Toy.DirtWall(
				block(
					"HubWall",
					Vector3.new(WALL_THICK, WALL_HEIGHT, HUB_BACK + WALL_THICK * 2),
					CFrame.new(side * wallX, WALL_HEIGHT / 2, -HUB_BACK / 2),
					Toy.Dirt,
					bases
				)
			)
		end
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
			Vector3.new(backHalf * 2 + WALL_THICK * 2, WALL_HEIGHT, WALL_THICK),
			CFrame.new(0, WALL_HEIGHT / 2, -HUB_BACK - WALL_THICK / 2),
			Toy.Dirt,
			bases
		),
		HUB_BRICK
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
	local runwayEnd = GameConfig.TotalZoneDepth()
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
	-- (no clouds: a clear sky)
	local _ = cloud
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
		-- Clock hands turn about the "Center" they were built with; the scale moved the clocks,
		-- so put each centre back where its hand now starts (the hand's bottom end)
		for _, hand in folder:GetDescendants() do
			if hand:IsA("BasePart") and hand:HasTag("ClockHand") then
				hand:SetAttribute("Center", hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, 0))
			end
		end
		for i, spawn in built.Spawns do
			built.Spawns[i] = CFrame.new(center + (spawn.Position - center) * ROUND_SCALE) * spawn.Rotation
		end
		-- The rooms are lit by the sun shining through the ceiling (it casts no shadow). An upstairs
		-- - its floor, walls and furniture - would block that and leave the ground floor gloomy, so
		-- nothing at the ceiling's height or above casts a shadow either: same light as before.
		local ceilingY = center.Y + (RoundMaps.STOREY - 1) * ROUND_SCALE - 0.5
		for _, part in folder:GetDescendants() do
			if part:IsA("BasePart") and part.Position.Y > ceilingY then
				part.CastShadow = false
			end
		end
		built.Size *= ROUND_SCALE
	end
	MapService.RoundSpawns = built.Spawns
	MapService.RoundMapSize = built.Size
	MapService.RoundLevels = built.Levels or 1
	MapService.RoundStorey = RoundMaps.STOREY * ROUND_SCALE
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

-- Apply the physical finish to every storey, including unpurchased detached floors.
-- Keep each prompt anchor, artwork canvas and cash hitbox in place.
-- A pen at its current length (PenMode.Depth): the grass, the spots its knives / coffins sit on and
-- its bounds follow the fence (the gate side stays put, the back moves out as it grows)
function MapService.FitPen(base: BaseSite, depth: number)
	local width = GameConfig.Pens.Width
	local shift = GameConfig.Pens.Depth / 2 - depth / 2
	local function at(x: number, y: number, z: number): CFrame
		return base.Frame * CFrame.new(x, y, z + shift)
	end
	local floor = base.Folder:FindFirstChild("Floor") :: BasePart?
	if floor then
		floor.Size = Vector3.new(width, 1, depth)
		floor.CFrame = at(0, 0.1, 0)
	end
	local cols, rows = 8, 5
	for slot, pad in base.SlotPads do
		local c, r = (slot - 1) % cols, (slot - 1) // cols
		local x = (c - (cols - 1) / 2) * ((width - 8) / (cols - 1))
		local z = (r - (rows - 1) / 2) * ((depth - 8) / (rows - 1))
		pad.CFrame = at(x, 0.7, z)
		base.SlotCFrames[slot] = at(x, 4.2, z)
	end
	-- world bounds: the pen is turned 90 degrees, so its length runs along world X
	local centre = at(0, 0, 0).Position
	local worldX = math.abs(base.Frame.LookVector.X) > 0.5
	base.Bounds = if worldX then bounds(centre, depth, width) else bounds(centre, width, depth)
end

function MapService.SetVaultTier(base: BaseSite, level: number)
	if PenMode.On() then
		return -- (a pen's grass and fence don't change with the tier)
	end
	local palette = VaultModel.Style(level)
	local floor = base.Folder:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		floor.Color = palette.Deck
	end
	for _, levelFolder in base.FloorFolders do
		VaultModel.ApplyTier(levelFolder, level)
		for _, child in levelFolder:GetChildren() do
			if child:IsA("BasePart") and child.Name == "Deck" then
				child.Color = palette.Deck
			elseif child:IsA("BasePart") and child.Name == "RailCap" then
				child.Color = palette.Body
			elseif child:IsA("BasePart") and child.Name == "HoleTrim" then
				child.Color = palette.Inset
			elseif child:IsA("Model") and child.Name:match("^PlateDetails%d+$") then
				local slot = tonumber(child.Name:match("%d+"))
				local pad = slot and base.SlotPads[slot]
				if pad then
					VaultModel.SetPlateTier(child, pad.CFrame * CFrame.new(0, -0.15, 0), level)
				end
			end
		end
	end
end

-- Rebuild only when the tier changes, including rebirth and a newly claimed vault.
-- Preserve training state when an owner buys an upgrade while already running.
function MapService.SetWheelTier(base: BaseSite, level: number)
	level = math.clamp(math.floor(level), 1, #GameConfig.Treadmills)
	base.TreadmillSign.Text = GameConfig.Treadmills[level].Name
	if base.Wheel:GetAttribute("Tier") == level then
		return
	end
	local old = base.Wheel
	local pivot = old:GetAttribute("Pivot")
	assert(typeof(pivot) == "CFrame", "Wheel is missing its resting axle pivot")
	local built = WheelModel.Build(level, pivot)
	built.Rotor:SetAttribute("Spinning", old:GetAttribute("Spinning"))
	built.Rotor:SetAttribute("SpinRate", old:GetAttribute("SpinRate"))
	built.Rotor:AddTag("HauntedWheel")
	built.Rotor.Parent = base.Folder
	local oldStand = base.Folder:FindFirstChild("WheelDetails")
	if oldStand then
		oldStand:Destroy()
	end
	built.Stand.Parent = base.Folder
	base.Wheel = built.Rotor
	old:Destroy()
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
	spawn.Transparency = 1 -- only a fallback: everyone spawns at their own vault (BaseService)
	spawn.Duration = 0
	spawn.Parent = root

	-- A breath between the big steps: Roblox stops a script that runs ~10 s without yielding
	-- ("Script timeout"), and on a busy server the whole map can take that long
	buildLighting()
	buildArena()
	task.wait()
	buildBases()
	task.wait()
	buildIsland()
	task.wait()
	ManorDecor.ShellZones = BIOME_SHELLS
	ManorDecor.Build(root, MapService.Arena :: Bounds, MapService.Hideaways)
	task.wait()
	-- Nothing from the plaza decor in the way of the wheels outside the vault gates
	for _, base in MapService.Bases do
		ManorDecor.ClearArea((base.Wheel.PrimaryPart :: BasePart).Position, 9, 9)
		if PenMode.On() then
			-- (and nothing of the old plaza's lamps and props inside a pen)
			ManorDecor.ClearArea(base.Center, GameConfig.Pens.Width / 2 + 2, GameConfig.Pens.Depth / 2 + 2)
		end
		MapService.SetFloors(base, 1)
	end
	task.wait()
	MapService.BuildRoundMap("Office")
	noLights()
end

-- The biome shells: built after the boss lairs (GuardService) so nothing clears them, as cosmetic
-- siblings of the arena (never inside ManorDecor's Decor folder). Origin = the runway entrance.
function MapService.BuildBiomeShells()
	local map = workspace:FindFirstChild("Map") or workspace
	local folder = Instance.new("Folder")
	folder.Name = "BiomeShells"
	folder.Parent = map
	for index, name in BIOME_SHELLS do
		local module = ReplicatedStorage.Shared.Assets:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			local ok, err = pcall(function()
				local shell = (require(module) :: any).Build(folder, CFrame.new(0, 0, GameConfig.ZoneStart(index)))
				shell:SetAttribute("Zone", index)
				BiomeSprites.Dress(shell) -- (sparkles on water, embers off lava, twinkles on lights...)
			end)
			if not ok then
				warn(`[MapService] biome shell {name} failed: {err}`)
			end
		end
	end
end

return MapService
