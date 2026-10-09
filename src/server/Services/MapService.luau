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
--   round maps (biome arenas, see BiomeRoundMaps) are built far away at x = 3000

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ManorDecor = require(script.Parent.ManorDecor)
local BiomeSprites = require(script.Parent.BiomeSprites)
local BiomeRoundMaps = require(script.Parent.BiomeRoundMaps)
local PenWalls = require(script.Parent.PenWalls)
local SignTheme = require(ReplicatedStorage.Shared.SignTheme)
local WorldSignModel = require(ReplicatedStorage.Shared.WorldSignModel)
local Toy = require(ReplicatedStorage.Shared.Toy)

export type Bounds = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
export type BaseSite = {
	Index: number,
	Color: Color3, -- this vault's own colour (wall strip, gate glow)
	Folder: Folder,
	WallFolder: Folder, -- the pen fence
	Gate: Model,
	Blocker: Part, -- the invisible gate marker (attributes: Owner, OwnerName, Tier, Floors, PenDepth)
	SignPart: Part,
	Center: Vector3,
	Frame: CFrame, -- local +Z points out of the vault's open side, towards the plaza
	Bounds: Bounds,
	Spawn: CFrame,
	SlotCFrames: { CFrame }, -- where each knife floats, over its pedestal
	SlotPads: { BasePart }, -- each pedestal's stone (holds the prompts)
	SlotRims: { BasePart }, -- invisible anchors on the grass
	CashPads: { BasePart }, -- the green pad beside each plate: walk on it to collect that knife's money
	CashLabels: { TextLabel }, -- the amount waiting, written on the pad
	Sign: TextLabel,
}
export type Zone = { Index: number, Rarity: string, Bounds: Bounds }

local MapService = {}

MapService.MaxBases = GameConfig.Pens.Count
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
MapService.LuckyWheelAt = nil :: Vector3? -- (pens: the far end of the hub lane, set by buildBases)
-- Biomes dressed by a Codex-built shell (src/shared/Assets/<Name>Shell): zone index -> module name.
-- Their old wall looks and ManorDecor's random props are switched off (ManorDecor reads this too).
-- The first two biomes keep their Codex shell (low studded borders, shrubs, a pond). The deeper
-- ones were custom architecture that hid the runway walls and read as a different game: every biome
-- is now the same dirt wall in its own colour (ZONE_WALLS) with its own floor and props (ManorDecor).
local BIOME_SHELLS: { [number]: string } = {
	[1] = "CourtyardShell",
	[2] = "GardensShell",
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

-- A sunny afternoon high in the sky (Steal An Egg style): a real sun, right overhead so it stays
-- in view over the tall boundary walls instead of grazing/ducking behind their top edge, blue sky
-- all round (also below: the map floats), soft clouds.
-- (`Lighting.Technology` is gone from this Roblox version - `LightingStyle` replaced it and Studio
-- already defaults it to a shadow-capable style. Nothing to flip by hand any more. If shadows ever
-- look flat again in a Studio Play-test, check `settings():GetService("RenderSettings").QualityLevel`
-- first - Studio pins test sessions to its lowest tier, which silently drops shadows regardless of
-- Lighting.GlobalShadows. Not a issue for real players: their own Graphics setting controls this.)
local function buildLighting()
	-- Early afternoon, the sun ~60 degrees up (Roblox north = -Z, west = -X): high enough to clear
	-- the walls and stay visible, low enough that everything still throws a real contact shadow.
	-- A lower, more raking angle (tried first) shaded the walls more dramatically, but ducked the
	-- sun behind the wall top edge from almost every normal camera angle AND threw a blown-out
	-- specular hotspot across the floor at some viewing angles - overhead reads better than either.
	-- (Found by searching ClockTime/latitude for GetSunDirection ~ (-0.36, 0.87, -0.35).)
	-- The tall boundary walls don't cast (Toy.DirtWall), or they'd shade half the arena.
	Lighting.ClockTime = 13.5
	Lighting.GeographicLatitude = 3
	-- Bright, colourful simulator light (picked side by side with Steal An Egg): a soft purple
	-- ambient, warm highlights from the sun, a little of the sky's own fill and reflection, and a
	-- saturation lift. The same everywhere in the hub (client/ZoneLighting keeps it on every biome).
	Lighting.Ambient = Color3.fromRGB(200, 160, 225)
	Lighting.OutdoorAmbient = Color3.fromRGB(125, 100, 150)
	Lighting.Brightness = 2.5
	Lighting.ExposureCompensation = 0
	Lighting.ColorShift_Top = Color3.fromRGB(215, 190, 135)
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.2
	-- A faint lavender fog far away instead of an Atmosphere
	Lighting.FogColor = Color3.fromRGB(200, 170, 250)
	Lighting.FogStart = 0
	Lighting.FogEnd = 2500
	-- Clients restore these after a round (client/Effects)
	Lighting:SetAttribute("HubAmbient", Lighting.Ambient)
	Lighting:SetAttribute("HubOutdoor", Lighting.OutdoorAmbient)
	Lighting:SetAttribute("HubShadows", Lighting.GlobalShadows)
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") or child:IsA("PostEffect") or child:IsA("Sky") then
			child:Destroy()
		end
	end
	-- "Sunless Blue Sky" (Creator Store asset 591067775 by Yourius: just a Sky, its six pictures)
	local sky = Instance.new("Sky")
	sky.SkyboxBk = "rbxassetid://591058823"
	sky.SkyboxDn = "rbxassetid://591059876"
	sky.SkyboxFt = "rbxassetid://591058104"
	sky.SkyboxLf = "rbxassetid://591057861"
	sky.SkyboxRt = "rbxassetid://591057625"
	sky.SkyboxUp = "rbxassetid://591059642"
	sky.StarCount = 0
	sky.MoonAngularSize = 0
	sky.Parent = Lighting
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Brightness = 0.05
	grade.Contrast = 0.1
	grade.Saturation = 0.15
	grade.TintColor = Color3.fromRGB(255, 255, 255)
	grade.Parent = Lighting
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		clouds:Destroy()
	end
end

-- Each zone is its own bright toy biome, so going deeper reads at a glance (Steal An Egg style)
local Palette = require(ReplicatedStorage.Shared.Config.BiomePalette)
local ZONE_FLOORS = Palette.Floors
local ZONE_WALLS = Palette.Walls

-- One wall height everywhere - the hub, the plain biomes and the far end - level with where the
-- Codex biome shells' walls top out (their spires reach SHELL_HEIGHT; most of each wall stops
-- around 35-40)
local WALL_HEIGHT = 36
local RUNWAY_WALL_HEIGHT = WALL_HEIGHT
local SHELL_HEIGHT = 48
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
				Vector3.new(WALL_THICK, RUNWAY_WALL_HEIGHT, depth),
				CFrame.new(x, RUNWAY_WALL_HEIGHT / 2, z0 + depth / 2),
				zoneTint(z0 + depth / 2),
				arena
			)
			Toy.DirtWall(wall, ZONE_WALLS[GameConfig.Zones[i].Rarity])
		end
	end
	-- The far end, in the last zone's wall colour (it closes off that biome)
	local farWall = block(
		"RunwayEnd",
		Vector3.new(width + WALL_THICK * 2, RUNWAY_WALL_HEIGHT, WALL_THICK),
		CFrame.new(0, RUNWAY_WALL_HEIGHT / 2, totalDepth + WALL_THICK / 2),
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
local HUB_HALF: number = GameConfig.ArenaWidth / 2
local HUB_BACK: number = 0
local HUB_STEP: { X: number, Z: number }? = nil
local NAVY = Color3.fromRGB(40, 44, 90)

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
	local penWidth = GameConfig.Pens.Width
	-- (a pen's full length, or a vault's depth: everything below is laid out from it)
	local DEPTH = GameConfig.Pens.Depth
	-- Pens wrap an open plaza in a "]" (Steal from the Rich): a row across the back wall facing the
	-- way in, and one on each side wall facing the middle (8 pens: 6 + 1 + 1). The middle stays open
	-- (the Lucky Wheel stands in it); each pen's upgrade sign stands in front of its gate.
	-- The hub is just big enough for that, gaps kept tight: open ground is walking with nothing to
	-- do. Numbered nearest-first, so players get the closest pen.
	local penCentres: { Vector3 } = {}
	local penFrames: { [Vector3]: CFrame } = {}
	local PEN_GAP = 8 -- (between neighbouring pens)
	local FRONT = 12 -- (the strip behind the safe line, before the side pens start)
	local PLAZA = 20 -- (between the side pens' ends and the back row: the outer back gates open here)
	local sideCount = math.min(2, GameConfig.Pens.Count)
	local backCount = GameConfig.Pens.Count - sideCount
	local rowWidth = backCount * penWidth + (backCount - 1) * PEN_GAP
	HUB_HALF = math.max(half, rowWidth / 2 + 4)
	local backZ = FRONT + penWidth + PLAZA + DEPTH / 2
	for k = 0, backCount - 1 do
		local centre = Vector3.new(-rowWidth / 2 + penWidth / 2 + k * (penWidth + PEN_GAP), 0, -backZ)
		table.insert(penCentres, centre)
		penFrames[centre] = CFrame.new(centre) -- (local +Z, the gate, faces the way in)
	end
	for k = 1, sideCount do
		local side = if k == 1 then -1 else 1
		local centre = Vector3.new(side * (HUB_HALF - 1 - DEPTH / 2), 0, -(FRONT + penWidth / 2))
		table.insert(penCentres, centre)
		-- (turned to face the middle: the left one +X, the right one -X)
		penFrames[centre] = CFrame.new(centre) * CFrame.Angles(0, math.rad(if side < 0 then 90 else -90), 0)
	end
	table.sort(penCentres, function(a, b)
		return a.Magnitude < b.Magnitude
	end)
	HUB_BACK = backZ + DEPTH / 2 + 2
	-- (the Lucky Wheel in the open middle, facing the way in)
	MapService.LuckyWheelAt = Vector3.new(0, 0, -(FRONT + penWidth * 0.6))
	MapService.LobbySpawn = CFrame.new(0, 4, -14)
	MapService.MaxBases = GameConfig.Pens.Count

	for i = 1, MapService.MaxBases do
		task.wait() -- (one vault a frame: never trips the script timeout)
		-- 1-6 down the left side, 7-12 down the right, 13-16 across the back of the plaza
		local center = penCentres[i]
		local frame = penFrames[center]
		local function at(x: number, y: number, z: number): CFrame
			return frame * CFrame.new(x, y, z)
		end
		local color = palette[i]
		local folder = Instance.new("Folder")
		folder.Name = `Base{i}`
		folder.Parent = bases

		-- An open platform (Tsunami style): a pale studded floor with a hint of the owner's colour
		-- (a pen: a patch of bright grass inside its fence)
		local grass =
			block("Floor", Vector3.new(penWidth, 1, DEPTH), at(0, 0.1, 0), Color3.fromRGB(86, 196, 56), folder)
		Toy.Dress(grass, { Enum.NormalId.Top }, 1, 4)
		-- The pen fence and its entrance marker.
		local wallFolder = Instance.new("Folder")
		wallFolder.Name = "Walls"
		wallFolder.Parent = folder
		local walls = PenWalls.Build(wallFolder, frame, color, 1)
		local slotCFrames: { CFrame }, slotPads: { BasePart }, slotRims: { BasePart } = {}, {}, {}
		local cashPads: { BasePart }, cashLabels: { TextLabel } = {}, {}
		-- No storeys or plates: invisible spots on the grass, one per knife (coffins wait on them,
		-- raid prompts hang on them; the knives themselves hop around - BaseService). Walking in
		-- collects your money, so every spot's "cash pad" is the spot itself.
		local levelFolder = Instance.new("Folder")
		levelFolder.Name = "Floor1"
		levelFolder.Parent = folder
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
		local sign = WorldSignModel.LiveText(ownerGui, "Owner", "Empty Pen", color)

		-- The Haunted Wheel: a giant iron wheel you run inside to train Speed (the plate at the bottom
		-- is what counts as "on it"). Clients spin it while its owner is training. It stands just
		-- outside the vault's gate, so the inside is nothing but knives.
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
		upgradeSignAt("UpgradeSign", 13, DEPTH / 2 + 6, "Upgrade Pen")

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
			-- (a turned pen's depth runs along world X)
			Bounds = if math.abs(frame.LookVector.X) > 0.5
				then bounds(center, DEPTH, penWidth)
				else bounds(center, penWidth, DEPTH),
			Spawn = CFrame.lookAt(spawnPos, spawnPos + frame:VectorToWorldSpace(Vector3.zAxis)),
			SlotCFrames = slotCFrames,
			SlotPads = slotPads,
			SlotRims = slotRims,
			CashPads = cashPads,
			CashLabels = cashLabels,
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

-- Round maps reuse the runway biomes; a random one is rebuilt at the start of each round
function MapService.RoundMapFolder(): Instance?
	return root and root:FindFirstChild("RoundMap")
end

function MapService.BuildRoundMap(name: string?): BiomeRoundMaps.Built
	local built = BiomeRoundMaps.Build(root, MapService.RoundCenter, name)
	MapService.RoundSpawns = built.Spawns
	MapService.RoundMapSize = built.Size
	MapService.RoundLevels = 1
	MapService.RoundStorey = 15
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

-- Rebuild only when the tier changes, including rebirth and a newly claimed vault.
-- Preserve training state when an owner buys an upgrade while already running.

-- Shows the vault's first `count` storeys (the rest wait out of the world until they're bought)

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
		-- (and nothing of the old plaza's lamps and props inside a pen)
		local b = base.Bounds
		ManorDecor.ClearArea(base.Center, (b.MaxX - b.MinX) / 2 + 2, (b.MaxZ - b.MinZ) / 2 + 2)
	end
	task.wait()
	MapService.BuildRoundMap("Courtyard")
	noLights()
end

-- The biome shells: built after the boss lairs (GuardService) so nothing clears them, as cosmetic
-- siblings of the arena (never inside ManorDecor's Decor folder). Origin = the runway entrance.
-- The Codex shells stand 150-175 studs tall: squashes one down to SHELL_HEIGHT, keeping everything at ground level (its
-- floor patterns, under SHELL_GROUND) exactly where it was and its silhouette (towers, arches) intact.
local SHELL_GROUND = 4
local function fitShellHeight(shell: Model)
	local top = 0
	for _, part in shell:GetDescendants() do
		if part:IsA("BasePart") then
			top = math.max(top, part.Position.Y + part.Size.Y / 2)
		end
	end
	if top <= SHELL_HEIGHT then
		return
	end
	local k = (SHELL_HEIGHT - SHELL_GROUND) / (top - SHELL_GROUND)
	local function squash(y: number): number
		return if y <= SHELL_GROUND then y else SHELL_GROUND + (y - SHELL_GROUND) * k
	end
	for _, part in shell:GetDescendants() do
		if part:IsA("BasePart") then
			local position = part.Position
			local bottom, ceiling = position.Y - part.Size.Y / 2, position.Y + part.Size.Y / 2
			local newBottom, newCeiling = squash(bottom), squash(ceiling)
			if newBottom ~= bottom or newCeiling ~= ceiling then
				local rotation = part.CFrame - position
				part.Size = Vector3.new(part.Size.X, math.max(0.05, newCeiling - newBottom), part.Size.Z)
				part.CFrame = CFrame.new(position.X, (newBottom + newCeiling) / 2, position.Z) * rotation
			end
		end
	end
end

-- The gate arches over the runway between biomes: gone (they read as a ceiling). Anything above
-- head height over the middle of the runway; the walls either side stay.
local function removeArches(shell: Model)
	for _, part in shell:GetDescendants() do
		if part:IsA("BasePart") and part.Position.Y - part.Size.Y / 2 > 7 and math.abs(part.Position.X) < 55 then
			part:Destroy()
		end
	end
end

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
				fitShellHeight(shell)
				removeArches(shell)
				BiomeSprites.Dress(shell) -- (sparkles on water, embers off lava, twinkles on lights...)
			end)
			if not ok then
				warn(`[MapService] biome shell {name} failed: {err}`)
			end
		end
	end
end

return MapService
