--!strict
-- Building blocks for the round maps (RoundMaps): walls with real trim (baseboards, crown
-- moulding, wainscoting, door casings), floors, windows with moonlight, lights, wall clutter and a
-- catalogue of furniture. Everything is Parts on purpose - the blocky 2013 look is the point -
-- apart from a few Blender props (chandeliers, sconces).
--
-- Positions are studs from the map centre. Furniture is built in a local frame and rotated as a
-- whole; its FRONT is local -Z. Rotation for something standing against a wall, facing the room:
--   north wall (+Z) 0, south wall (-Z) 180, west wall (-X) -90, east wall (+X) 90.
-- Visible props are solid; only rugs and ceiling-grid lines are non-solid.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldSignModel = require(ReplicatedStorage.Shared.WorldSignModel)

local Props = require(ReplicatedStorage.Shared.Props)
local RoundArt = require(ReplicatedStorage.Shared.Assets.RoundMapArt)
local Textures = require(ReplicatedStorage.Shared.Config.Textures)

local Kit = {}

Kit.WALL_HEIGHT = 14
Kit.DOOR_WIDTH = 7
Kit.DOOR_HEIGHT = 9.5
local WALL_HEIGHT = Kit.WALL_HEIGHT
local DOOR_WIDTH = Kit.DOOR_WIDTH
local DOOR_HEIGHT = Kit.DOOR_HEIGHT
local T = 1 -- wall thickness

Kit.STOREY = Kit.WALL_HEIGHT + 1 -- floor to floor: the walls plus the slab between storeys

local folder: Folder
local origin: Vector3
local groundOrigin: Vector3

function Kit.Begin(into: Folder, center: Vector3)
	folder = into
	origin = center
	groundOrigin = center
end

function Kit.PreloadArtwork()
	RoundArt.Preload()
end

-- Build on storey `n` (0 = ground, 1 = upstairs): everything after this call sits n storeys up,
-- so the same walls and furniture work on every floor
function Kit.Level(n: number)
	origin = groundOrigin + Vector3.new(0, n * Kit.STOREY, 0)
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
Kit.rgb = rgb

local function darker(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount)
end

local function lighter(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end

-- Primitives ---------------------------------------------------------------------------------

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
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
Kit.part = part

-- Detail parts (trim, clutter, lights): solid - nothing in a map can be walked through - but
-- raycasts ignore them (the camera, coin drops). Only rugs stay flat and non-solid, so they
-- aren't little steps to trip over.
local function deco(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = part(name, size, cframe, color, material)
	p.CanCollide = name ~= "Rug" and name ~= "CeilingGrid"
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(origin + Vector3.new(x, y, z))
end
Kit.at = at

local function frame(x: number, z: number, rotation: number?, y: number?): CFrame
	return at(x, y or 0, z) * CFrame.Angles(0, math.rad(rotation or 0), 0)
end
Kit.frame = frame

local function piece(
	base: CFrame,
	name: string,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	material: Enum.Material?
): Part
	return part(name, size, base * CFrame.new(offset), color, material)
end

local function bit(
	base: CFrame,
	name: string,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	material: Enum.Material?
): Part
	return deco(name, size, base * CFrame.new(offset), color, material)
end

local function cylinder(p: Part, axis: "X" | "Y" | "Z"?): Part
	p.Shape = Enum.PartType.Cylinder
	-- Roblox cylinders run along X; turn them to stand up (Y) or face forward (Z)
	if axis == "Y" then
		p.Size = Vector3.new(p.Size.Y, p.Size.X, p.Size.Z)
		p.CFrame = p.CFrame * CFrame.Angles(0, 0, math.rad(90))
	elseif axis == "Z" then
		p.Size = Vector3.new(p.Size.Z, p.Size.Y, p.Size.X)
		p.CFrame = p.CFrame * CFrame.Angles(0, math.rad(90), 0)
	end
	return p
end

local function ball(p: Part): Part
	p.Shape = Enum.PartType.Ball
	return p
end

local function light(_parent: Instance, _color: Color3, _range: number, _brightness: number)
	-- One even game light. Visible lamp geometry is Neon; no per-prop Light instances.
end

function Kit.hero(name: string, x: number, z: number, rotation: number?, y: number?): Model
	return RoundArt.Build(name, folder, frame(x, z, rotation, y))
end

-- Text on the front (-Z) face of a part
local function label(p: BasePart, text: string, color: Color3, _font: Enum.Font?, face: Enum.NormalId?, glow: boolean?)
	WorldSignModel.Letters(p, text, color, face)
	local letters = p:FindFirstChild("VoxelLetters")
	if letters then
		for _, glyph in letters:GetChildren() do
			if glyph:IsA("BasePart") then
				glyph.CanCollide = true
				if glow then
					glyph.Material = Enum.Material.Neon
				end
			end
		end
	end
end

-- Walls --------------------------------------------------------------------------------------

export type WallStyle = {
	Color: Color3,
	Material: Enum.Material?,
	Base: Color3?, -- baseboard (default: a darker shade of the wall)
	Crown: Color3?, -- crown moulding at the ceiling (default: off-white)
	Wainscot: Color3?, -- lower wood panelling with a chair rail (mansion rooms)
	Door: Color3?, -- door casings and leaves
}

-- A strip running along a wall on one face (side = +1 / -1)
local function strip(
	alongX: boolean,
	fixed: number,
	from: number,
	to: number,
	y: number,
	height: number,
	depth: number,
	side: number,
	color: Color3,
	material: Enum.Material?
)
	local len = to - from
	if len < 0.05 then
		return
	end
	local mid = (from + to) / 2
	local off = fixed + side * (T / 2 + depth / 2)
	local size = if alongX then Vector3.new(len, height, depth) else Vector3.new(depth, height, len)
	local cf = if alongX then at(mid, y, off) else at(off, y, mid)
	deco("Trim", size, cf, color, material)
end

-- An axis-aligned wall from (x1, z1) to (x2, z2) with doorways cut at the given offsets along it.
-- `style` dresses the +X / +Z face, `back` the -X / -Z face (same as `style` if left out), so a
-- wall between two rooms can wear each room's wallpaper.
function Kit.wall(
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	style: WallStyle,
	doors: { number }?,
	back: WallStyle?
)
	local alongX = z1 == z2
	local a, b =
		math.min(if alongX then x1 else z1, if alongX then x2 else z2),
		math.max(if alongX then x1 else z1, if alongX then x2 else z2)
	local fixed = if alongX then z1 else x1
	local gaps: { number } = table.clone(doors or {})
	table.sort(gaps)
	local doorColor = style.Door or rgb(110, 70, 40)
	local sides: { [number]: WallStyle } = { [1] = style, [-1] = back or style }

	local function segment(from: number, to: number, y0: number, y1: number)
		if to - from < 0.05 then
			return
		end
		local mid, len = (from + to) / 2, to - from
		local backStyle = sides[-1]
		if backStyle.Color ~= style.Color or backStyle.Material ~= style.Material then
			-- Two rooms' wallpapers: two half-thickness slabs, each in its own room's paper. (A thin
			-- layer laid over one face z-fought with the wall and flickered as the camera moved.)
			for _, side in { -1, 1 } do
				local s = sides[side]
				local offset = fixed + side * T / 4
				local half = if alongX then Vector3.new(len, y1 - y0, T / 2) else Vector3.new(T / 2, y1 - y0, len)
				local hcf = if alongX then at(mid, (y0 + y1) / 2, offset) else at(offset, (y0 + y1) / 2, mid)
				part("Wall", half, hcf, s.Color, s.Material)
			end
		else
			local size = if alongX then Vector3.new(len, y1 - y0, T) else Vector3.new(T, y1 - y0, len)
			local cf = if alongX then at(mid, (y0 + y1) / 2, fixed) else at(fixed, (y0 + y1) / 2, mid)
			part("Wall", size, cf, style.Color, style.Material)
		end
		for _, side in { -1, 1 } do
			local s = sides[side]
			strip(alongX, fixed, from, to, WALL_HEIGHT - 0.35, 0.7, 0.35, side, s.Crown or rgb(245, 243, 236))
			if y0 == 0 then
				if s.Wainscot then
					local wood = s.Wainscot
					strip(alongX, fixed, from, to, 2.25, 4.5, 0.12, side, wood, Enum.Material.Wood)
					strip(alongX, fixed, from, to, 4.6, 0.3, 0.3, side, darker(wood, 0.2), Enum.Material.Wood)
					-- raised panel stiles every few studs
					local n = math.floor(len / 5)
					for i = 1, n do
						local stile = from + i * len / (n + 1)
						strip(
							alongX,
							fixed,
							stile - 0.2,
							stile + 0.2,
							2.4,
							3.6,
							0.2,
							side,
							darker(wood, 0.12),
							Enum.Material.Wood
						)
					end
				end
				strip(alongX, fixed, from, to, 0.4, 0.8, 0.22, side, s.Base or darker(s.Color, 0.45))
			end
		end
	end

	local cursor = a
	for _, center in gaps do
		local d0, d1 = center - DOOR_WIDTH / 2, center + DOOR_WIDTH / 2
		segment(cursor, d0, 0, WALL_HEIGHT)
		segment(d0, d1, DOOR_HEIGHT, WALL_HEIGHT) -- lintel
		-- Casing: two posts and a header on both faces, an open door leaf and its knob
		for _, edge in { d0, d1 } do
			local size = if alongX
				then Vector3.new(0.5, DOOR_HEIGHT, T + 0.3)
				else Vector3.new(T + 0.3, DOOR_HEIGHT, 0.5)
			part(
				"DoorFrame",
				size,
				if alongX then at(edge, DOOR_HEIGHT / 2, fixed) else at(fixed, DOOR_HEIGHT / 2, edge),
				doorColor
			)
		end
		local header = if alongX
			then Vector3.new(DOOR_WIDTH + 1, 0.6, T + 0.3)
			else Vector3.new(T + 0.3, 0.6, DOOR_WIDTH + 1)
		deco(
			"DoorFrame",
			header,
			if alongX then at(center, DOOR_HEIGHT + 0.3, fixed) else at(fixed, DOOR_HEIGHT + 0.3, center),
			doorColor
		)
		local leafSize = if alongX
			then Vector3.new(0.35, DOOR_HEIGHT - 0.3, DOOR_WIDTH - 0.6)
			else Vector3.new(DOOR_WIDTH - 0.6, DOOR_HEIGHT - 0.3, 0.35)
		-- Doors swing away from the middle of the building, so they open into rooms, not corridors
		local swing = if fixed < 0 then -1 else 1
		local leafCf = if alongX
			then at(d0 + 0.3, DOOR_HEIGHT / 2, fixed + swing * DOOR_WIDTH / 2)
			else at(fixed + swing * DOOR_WIDTH / 2, DOOR_HEIGHT / 2, d0 + 0.3)
		local leaf = deco("Door", leafSize, leafCf, darker(doorColor, 0.1), Enum.Material.Wood)
		-- two recessed panels on each side of the leaf
		for _, y in { -2, 2 } do
			local panel = if alongX
				then Vector3.new(0.45, 3, DOOR_WIDTH - 2.2)
				else Vector3.new(DOOR_WIDTH - 2.2, 3, 0.45)
			deco("DoorPanel", panel, leafCf * CFrame.new(0, y, 0), darker(doorColor, 0.25), Enum.Material.Wood)
		end
		local knobOffset = if alongX
			then Vector3.new(0, -0.4, DOOR_WIDTH / 2 - 1)
			else Vector3.new(DOOR_WIDTH / 2 - 1, -0.4, 0)
		ball(deco("Knob", Vector3.one * 0.45, leafCf * CFrame.new(knobOffset), rgb(212, 175, 80), Enum.Material.Metal))
		leaf.CanCollide = true -- an open door you bump into, not walk through
		leaf.CanQuery = true -- and thrown knives stick in it
		cursor = d1
	end
	segment(cursor, b, 0, WALL_HEIGHT)
end

-- Floors and ceilings ------------------------------------------------------------------------

-- The base slab. Coins and the Revolver land on anything called "Floor".
function Kit.floor(x: number, z: number, sizeX: number, sizeZ: number, color: Color3, material: Enum.Material)
	part("Floor", Vector3.new(sizeX, 1, sizeZ), at(x, -0.5, z), color, material)
end

-- A room's own floor laid on top of the slab (carpet tiles, parquet, concrete...)
function Kit.roomFloor(x: number, z: number, sizeX: number, sizeZ: number, color: Color3, material: Enum.Material)
	part("Floor", Vector3.new(sizeX, 0.1, sizeZ), at(x, 0.05, z), color, material)
end

-- Checkerboard tiles (kitchens, bathrooms)
function Kit.checker(x: number, z: number, sizeX: number, sizeZ: number, tile: number, c1: Color3, c2: Color3)
	local nx, nz = math.floor(sizeX / tile), math.floor(sizeZ / tile)
	local tx, tz = sizeX / nx, sizeZ / nz
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			part(
				"Floor",
				Vector3.new(tx, 0.1, tz),
				at(x - sizeX / 2 + (i + 0.5) * tx, 0.05, z - sizeZ / 2 + (j + 0.5) * tz),
				if (i + j) % 2 == 0 then c1 else c2,
				Enum.Material.CeramicTiles
			)
		end
	end
end

-- Rugs sit on the floor; no collision and no queries so coins still land "on" them
function Kit.rug(x: number, z: number, sizeX: number, sizeZ: number, color: Color3, border: Color3?)
	if border then
		deco("Rug", Vector3.new(sizeX, 0.1, sizeZ), at(x, 0.12, z), border, Enum.Material.Fabric)
		deco("Rug", Vector3.new(sizeX - 1.6, 0.1, sizeZ - 1.6), at(x, 0.19, z), color, Enum.Material.Fabric)
		deco(
			"Rug",
			Vector3.new(sizeX - 3.4, 0.1, sizeZ - 3.4),
			at(x, 0.26, z),
			darker(color, 0.15),
			Enum.Material.Fabric
		)
		deco("Rug", Vector3.new(sizeX - 4.2, 0.1, sizeZ - 4.2), at(x, 0.33, z), color, Enum.Material.Fabric)
	else
		deco("Rug", Vector3.new(sizeX, 0.1, sizeZ), at(x, 0.12, z), color, Enum.Material.Fabric)
	end
end

function Kit.ceiling(sizeX: number, sizeZ: number, color: Color3)
	local p = part("Ceiling", Vector3.new(sizeX + 2, 1, sizeZ + 2), at(0, WALL_HEIGHT + 0.5, 0), color)
	-- Solid and queryable: the camera bumps into it instead of poking out above the rooms.
	-- (Coins and spawns raycast from below it.)
	p.CastShadow = false
end

export type Rect = { X: number, Z: number, W: number, D: number } -- centre + size, studs

-- A 1-stud slab over a rectangle with rectangular holes cut out (a stairwell, the upstairs
-- footprint above a ceiling): split along every hole edge into cells, keep the cells outside the
-- holes. `y` is the slab's centre height on the current storey.
function Kit.slab(
	name: string,
	y: number,
	area: Rect,
	holes: { Rect },
	color: Color3,
	material: Enum.Material?,
	thickness: number?
)
	local xs = { area.X - area.W / 2, area.X + area.W / 2 }
	local zs = { area.Z - area.D / 2, area.Z + area.D / 2 }
	for _, h in holes do
		table.insert(xs, math.clamp(h.X - h.W / 2, xs[1], xs[2]))
		table.insert(xs, math.clamp(h.X + h.W / 2, xs[1], xs[2]))
		table.insert(zs, math.clamp(h.Z - h.D / 2, zs[1], zs[2]))
		table.insert(zs, math.clamp(h.Z + h.D / 2, zs[1], zs[2]))
	end
	table.sort(xs)
	table.sort(zs)
	local function inHole(x: number, z: number): boolean
		for _, h in holes do
			if math.abs(x - h.X) < h.W / 2 and math.abs(z - h.Z) < h.D / 2 then
				return true
			end
		end
		return false
	end
	for i = 1, #xs - 1 do
		-- merge the kept cells of this column into runs along Z (fewer parts)
		local runStart: number? = nil
		local x0, x1 = xs[i], xs[i + 1]
		if x1 - x0 < 0.05 then
			continue
		end
		for j = 1, #zs do
			local keep = j < #zs and zs[j + 1] - zs[j] >= 0.05 and not inHole((x0 + x1) / 2, (zs[j] + zs[j + 1]) / 2)
			if keep and not runStart then
				runStart = zs[j]
			elseif not keep and runStart then
				local z0, z1 = runStart, zs[j]
				local p = part(
					name,
					Vector3.new(x1 - x0, thickness or 1, z1 - z0),
					at((x0 + x1) / 2, y, (z0 + z1) / 2),
					color,
					material
				)
				p.CastShadow = false
				runStart = nil
			end
		end
	end
end

-- A straight flight of stairs up one storey. Built in a local frame like furniture: the bottom
-- step at local +Z, climbing towards local -Z (rotation 0 climbs towards -Z, 180 towards +Z), `width`
-- across. Visible steps are solid blocks; an invisible ramp over their noses is what feet (and
-- the bots' pathfinding) walk on. Returns the hole the floor above needs, as a Rect.
Kit.STAIR_RUN = 28
function Kit.stairs(
	x: number,
	z: number,
	rotation: number,
	width: number,
	color: Color3,
	rail: Color3?,
	artwork: string?
): Rect
	local b = frame(x, z, rotation)
	local L, H, n = Kit.STAIR_RUN, Kit.STOREY, 20
	local rise, run = H / n, L / n
	if artwork then
		RoundArt.Build(artwork, folder, b)
	else
		for i = 0, n - 1 do
			local top = (i + 1) * rise
			local step = piece(
				b,
				"Step",
				Vector3.new(width, top, run),
				Vector3.new(0, top / 2, L / 2 - (i + 0.5) * run),
				color,
				Enum.Material.Wood
			)
			step.CanQuery = false
			bit(
				b,
				"StepNose",
				Vector3.new(width + 0.1, 0.18, 0.3),
				Vector3.new(0, top - 0.09, L / 2 - i * run - 0.15),
				darker(color, 0.25),
				Enum.Material.Wood
			)
		end
	end
	-- the walking surface: through every step's front-top corner, starting on the floor one
	-- step-length in front of the first step (a lip at step height can't be walked onto)
	local z0, y0 = L / 2 + run, 0
	local z1, y1 = -L / 2 + run, H
	local length = math.sqrt((z0 - z1) ^ 2 + (y1 - y0) ^ 2)
	local ramp = Instance.new("Part")
	ramp.Name = "Ramp"
	ramp.Anchored = true
	ramp.Size = Vector3.new(width, 0.4, length)
	ramp.CFrame = b
		* CFrame.new(0, (y0 + y1) / 2 - 0.2, (z0 + z1) / 2)
		* CFrame.Angles(math.atan2(y1 - y0, z0 - z1), 0, 0)
	ramp.Transparency = 1
	ramp.CanQuery = false
	ramp.Parent = folder
	-- handrails on both sides: posts every few steps and a sloped rail
	if not artwork then
		local railColor = rail or darker(color, 0.35)
		for _, side in { -1, 1 } do
			local sx = side * (width / 2 - 0.2)
			for i = 0, n - 1, 4 do
				local top = (i + 1) * rise
				bit(
					b,
					"RailPost",
					Vector3.new(0.3, 3.2, 0.3),
					Vector3.new(sx, top + 1.6, L / 2 - (i + 0.5) * run),
					railColor,
					Enum.Material.Wood
				)
			end
			local rp = bit(b, "Handrail", Vector3.new(0.35, 0.3, length), Vector3.zero, railColor, Enum.Material.Wood)
			rp.CFrame = b
				* CFrame.new(sx, (y0 + y1) / 2 + 3.1, (z0 + z1) / 2)
				* CFrame.Angles(math.atan2(y1 - y0, z0 - z1), 0, 0)
		end
	end
	-- the hole above, in map coordinates (rotation 0/180 keep it along Z, 90/-90 along X)
	-- (2 studs wider than the flight each side: bot pathfinding works on a coarse grid and read a
	-- hole exactly the stairs' width as no headroom)
	local alongX = math.abs(rotation) % 180 == 90
	return { X = x, Z = z, W = if alongX then L else width + 4, D = if alongX then width + 4 else L }
end

-- A waist-high railing (collides) along a straight line on the current storey - round a stairwell
function Kit.railing(x1: number, z1: number, x2: number, z2: number, color: Color3, artwork: string?)
	local mid = Vector3.new((x1 + x2) / 2, 0, (z1 + z2) / 2)
	local len = math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
	local alongX = math.abs(x2 - x1) > math.abs(z2 - z1)
	local guard = part(
		"Railing",
		if alongX then Vector3.new(len, 3.4, 0.3) else Vector3.new(0.3, 3.4, len),
		at(mid.X, 1.7, mid.Z),
		color,
		Enum.Material.Wood
	)
	guard.Transparency = 1 -- invisible stop; the rail and balusters below are what you see
	if artwork then
		local model = RoundArt.Build(artwork)
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and p.Name ~= "Origin" then
				local isCylinder = p:IsA("Part") and p.Shape == Enum.PartType.Cylinder
				local scale = if isCylinder then Vector3.new(1, len / 8, 1) else Vector3.new(len / 8, 1, 1)
				p.Size *= scale
				p.CFrame = CFrame.new(p.Position.X * len / 8, p.Position.Y, p.Position.Z) * p.CFrame.Rotation
			end
		end
		model:PivotTo(at(mid.X, 0, mid.Z) * CFrame.Angles(0, if alongX then 0 else math.pi / 2, 0))
		model.Parent = folder
		return
	end
	deco(
		"Handrail",
		if alongX then Vector3.new(len, 0.35, 0.45) else Vector3.new(0.45, 0.35, len),
		at(mid.X, 3.4, mid.Z),
		color,
		Enum.Material.Wood
	)
	local count = math.max(2, math.floor(len / 1.6))
	for i = 0, count do
		local t = i / count
		deco(
			"Baluster",
			Vector3.new(0.22, 3.2, 0.22),
			at(x1 + (x2 - x1) * t, 1.6, z1 + (z2 - z1) * t),
			lighter(color, 0.15),
			Enum.Material.Wood
		)
	end
end

-- Drop-ceiling grid lines (offices)
function Kit.ceilingGrid(x: number, z: number, sizeX: number, sizeZ: number, spacing: number, color: Color3)
	for gx = x - sizeX / 2 + spacing, x + sizeX / 2 - 0.1, spacing do
		deco("CeilingGrid", Vector3.new(0.18, 0.1, sizeZ), at(gx, WALL_HEIGHT - 0.05, z), color)
	end
	for gz = z - sizeZ / 2 + spacing, z + sizeZ / 2 - 0.1, spacing do
		deco("CeilingGrid", Vector3.new(sizeX, 0.1, 0.18), at(x, WALL_HEIGHT - 0.05, gz), color)
	end
end

-- Lights ---------------------------------------------------------------------------------------
-- About one light in four flickers (Atmosphere animates anything tagged "Flicker").

local function maybeFlicker(p: BasePart, chance: number?)
	if math.random() < (chance or 0.25) then
		p:AddTag("Flicker")
	end
end

-- Candle and fire light: wavers softly instead of cutting out
local function flame(p: BasePart)
	p:SetAttribute("Flame", true)
	p:AddTag("Flicker")
end

-- Office strip light: a housing with a glowing lens, cool white
function Kit.fluorescent(x: number, z: number, rotation: number?, flicker: number?)
	local b = frame(x, z, rotation, WALL_HEIGHT)
	bit(b, "LightHousing", Vector3.new(2.6, 0.3, 6.4), Vector3.new(0, -0.15, 0), rgb(225, 225, 228))
	local lens =
		bit(b, "Lamp", Vector3.new(2, 0.1, 5.8), Vector3.new(0, -0.33, 0), rgb(235, 242, 255), Enum.Material.Neon)
	light(lens, rgb(225, 238, 255), 22, 0.55)
	maybeFlicker(lens, flicker)
end

-- A bare bulb on a cord (storage rooms)
function Kit.pendant(x: number, z: number, drop: number?, flicker: number?)
	local d = drop or 3
	local b = frame(x, z, 0, WALL_HEIGHT)
	bit(b, "Cord", Vector3.new(0.08, d, 0.08), Vector3.new(0, -d / 2, 0), rgb(20, 20, 20))
	local shade = cylinder(
		bit(b, "Shade", Vector3.new(1.6, 0.5, 1.6), Vector3.new(0, -d - 0.1, 0), rgb(60, 70, 60), Enum.Material.Metal),
		"Y"
	)
	local _ = shade
	local bulb =
		ball(bit(b, "Lamp", Vector3.one * 0.6, Vector3.new(0, -d - 0.45, 0), rgb(255, 225, 160), Enum.Material.Neon))
	light(bulb, rgb(255, 200, 130), 18, 0.6)
	maybeFlicker(bulb, flicker)
end

-- Round recessed downlight (corridors)
function Kit.downlight(x: number, z: number, color: Color3?, flicker: number?)
	local b = frame(x, z, 0, WALL_HEIGHT)
	cylinder(bit(b, "LightRing", Vector3.new(1.8, 0.12, 1.8), Vector3.new(0, -0.05, 0), rgb(200, 200, 205)), "Y")
	local lens = cylinder(
		bit(b, "Lamp", Vector3.new(1.3, 0.14, 1.3), Vector3.new(0, -0.07, 0), rgb(255, 245, 225), Enum.Material.Neon),
		"Y"
	)
	light(lens, color or rgb(255, 240, 220), 20, 0.55)
	maybeFlicker(lens, flicker)
end

local function solidProp(name: string): Model
	local model = Props.Build(name, true)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			p.CanCollide = true
		end
	end
	return model
end

-- The Blender chandelier hanging from the ceiling; neon candles use the game's even lighting.
function Kit.chandelier(x: number, z: number)
	local model = solidProp("Chandelier")
	model:PivotTo(at(x, WALL_HEIGHT, z))
	model.Parent = folder
	local glow = deco("Lamp", Vector3.one * 0.3, at(x, WALL_HEIGHT - 3, z), rgb(255, 190, 110))
	glow.Transparency = 1
	light(glow, rgb(255, 190, 120), 30, 0.85)
	flame(glow)
end

-- The Blender wall sconce (a candle on an iron arm). `outward` points away from the wall.
function Kit.sconce(x: number, y: number, z: number, outward: Vector3)
	local pos = origin + Vector3.new(x, y, z)
	local model = solidProp("Sconce")
	model:PivotTo(CFrame.lookAt(pos, pos + outward))
	model.Parent = folder
	local glow =
		deco("Lamp", Vector3.one * 0.2, CFrame.new(pos + outward * 1.1 + Vector3.new(0, 0.4, 0)), rgb(255, 200, 120))
	glow.Transparency = 1
	light(glow, rgb(255, 180, 100), 12, 0.7)
	flame(glow)
end

-- Windows ------------------------------------------------------------------------------------

export type WindowOptions = {
	Width: number?,
	Height: number?,
	Sill: number?, -- height of the bottom edge
	Frame: Color3?,
	Curtains: Color3?,
}

-- A window on a wall face looking out at the night (x, z on the face; rotation as for furniture,
-- e.g. 0 on the north wall). Moonlight falls into the room.
function Kit.window(x: number, z: number, rotation: number, options: WindowOptions?)
	local o: WindowOptions = options or {}
	local w, h = o.Width or 6, o.Height or 6.5
	local sill = o.Sill or 3.8
	local frameColor = o.Frame or rgb(240, 240, 235)
	local b = frame(x, z, rotation, sill + h / 2)
	local sky = bit(b, "Window", Vector3.new(w, h, 0.1), Vector3.new(0, 0, -0.05), rgb(28, 42, 82), Enum.Material.Neon)
	sky:AddTag("Window")
	-- A shallow night scene behind the glazing, separated by real depth to avoid flicker.
	for i = 1, 3 do
		local height = h * (0.24 + i * 0.09)
		bit(
			b,
			"OutsideBuilding",
			Vector3.new(w * 0.27, height, 0.10),
			Vector3.new((i - 2) * w * 0.29, -h / 2 + height / 2, -0.26),
			rgb(15, 24, 45)
		)
	end
	bit(
		b,
		"OutsideMoon",
		Vector3.new(0.55, 0.55, 0.08),
		Vector3.new(w * 0.25, h * 0.27, -0.42),
		rgb(223, 234, 255),
		Enum.Material.Neon
	)
	local glass =
		bit(b, "Glass", Vector3.new(w, h, 0.06), Vector3.new(0, 0, -0.60), rgb(190, 215, 240), Enum.Material.Glass)
	glass.Transparency = 0.75
	glass.Reflectance = 0.2
	-- frame and mullions
	bit(b, "WindowFrame", Vector3.new(w + 0.8, 0.4, 0.45), Vector3.new(0, h / 2 + 0.2, -0.65), frameColor)
	bit(b, "WindowFrame", Vector3.new(w + 0.8, 0.4, 0.45), Vector3.new(0, -h / 2 - 0.2, -0.65), frameColor)
	for _, sx in { -1, 1 } do
		bit(b, "WindowFrame", Vector3.new(0.4, h, 0.45), Vector3.new(sx * (w / 2 + 0.2), 0, -0.65), frameColor)
	end
	bit(b, "Mullion", Vector3.new(0.22, h, 0.18), Vector3.new(0, 0, -0.78), frameColor)
	bit(b, "Mullion", Vector3.new(w, 0.22, 0.18), Vector3.new(0, h * 0.12, -0.78), frameColor)
	bit(b, "Sill", Vector3.new(w + 1.4, 0.3, 0.9), Vector3.new(0, -h / 2 - 0.45, -0.45), frameColor)
	if o.Curtains then
		local c = o.Curtains
		bit(
			b,
			"CurtainRod",
			Vector3.new(w + 3.2, 0.18, 0.18),
			Vector3.new(0, h / 2 + 1, -0.7),
			rgb(200, 165, 70),
			Enum.Material.Metal
		)
		for _, sx in { -1, 1 } do
			bit(
				b,
				"Curtain",
				Vector3.new(1.6, h + 2.4, 0.3),
				Vector3.new(sx * (w / 2 + 0.6), -0.3, -0.75),
				c,
				Enum.Material.Fabric
			)
			bit(
				b,
				"CurtainTie",
				Vector3.new(1.75, 0.25, 0.4),
				Vector3.new(sx * (w / 2 + 0.6), -0.8, -0.75),
				rgb(200, 165, 70),
				Enum.Material.Fabric
			)
		end
		bit(
			b,
			"Valance",
			Vector3.new(w + 3, 1.1, 0.45),
			Vector3.new(0, h / 2 + 1.1, -0.8),
			darker(c, 0.15),
			Enum.Material.Fabric
		)
	end
end

-- Wall clutter -------------------------------------------------------------------------------
-- (x, y, z) is the spot on the wall face; rotation as for furniture.

export type ArtKind = "Landscape" | "Portrait" | "Abstract" | "Sea"

function Kit.picture(
	x: number,
	y: number,
	z: number,
	rotation: number,
	kind: ArtKind,
	frameColor: Color3?,
	scale: number?
)
	local s = scale or 1
	local b = frame(x, z, rotation, y)
	local fc = frameColor or rgb(90, 60, 30)
	local w, h = 4.4 * s, 3.4 * s
	if kind == "Portrait" then
		w, h = 3.2 * s, 4.2 * s
	end
	bit(b, "PictureFrame", Vector3.new(w + 0.5, h + 0.5, 0.25), Vector3.new(0, 0, -0.13), fc, Enum.Material.Wood)
	local function paint(name: string, size: Vector3, offset: Vector2, color: Color3, depth: number)
		bit(
			b,
			name,
			Vector3.new(size.X * s, size.Y * s, 0.06),
			Vector3.new(offset.X * s, offset.Y * s, -0.27 - depth * 0.01),
			color
		)
	end
	if kind == "Landscape" then
		paint("Canvas", Vector3.new(4.4, 3.4, 0), Vector2.zero, rgb(120, 170, 220), 0)
		paint("Hill", Vector3.new(4.4, 1.4, 0), Vector2.new(0, -1), rgb(80, 140, 70), 1)
		paint("Hill", Vector3.new(2.2, 1.2, 0), Vector2.new(-1, -0.4), rgb(100, 160, 80), 2)
		paint("Sun", Vector3.new(0.7, 0.7, 0), Vector2.new(1.3, 0.9), rgb(255, 220, 90), 1)
	elseif kind == "Sea" then
		paint("Canvas", Vector3.new(4.4, 3.4, 0), Vector2.zero, rgb(240, 170, 110), 0)
		paint("Sea", Vector3.new(4.4, 1.5, 0), Vector2.new(0, -0.95), rgb(40, 80, 140), 1)
		paint("Sun", Vector3.new(1.1, 0.55, 0), Vector2.new(0, -0.05), rgb(255, 210, 90), 1)
		paint("Boat", Vector3.new(0.6, 0.25, 0), Vector2.new(-1.1, -0.6), rgb(40, 30, 25), 2)
	elseif kind == "Portrait" then
		-- an old, slightly unsettling ancestor
		paint("Canvas", Vector3.new(3.2, 4.2, 0), Vector2.zero, rgb(45, 35, 30), 0)
		paint("Shoulders", Vector3.new(2.4, 1.2, 0), Vector2.new(0, -1.5), rgb(25, 25, 30), 1)
		paint("Collar", Vector3.new(0.7, 0.5, 0), Vector2.new(0, -1.05), rgb(230, 225, 210), 2)
		paint("Face", Vector3.new(1.2, 1.5, 0), Vector2.new(0, -0.05), rgb(225, 190, 160), 2)
		paint("Hair", Vector3.new(1.4, 0.5, 0), Vector2.new(0, 0.75), rgb(70, 60, 55), 3)
		for _, ex in { -0.25, 0.25 } do
			paint("Eye", Vector3.new(0.16, 0.12, 0), Vector2.new(ex, 0.1), rgb(20, 20, 20), 3)
		end
		paint("Mouth", Vector3.new(0.4, 0.07, 0), Vector2.new(0, -0.45), rgb(120, 60, 60), 3)
	else
		paint("Canvas", Vector3.new(4.4, 3.4, 0), Vector2.zero, rgb(240, 236, 225), 0)
		paint("Block", Vector3.new(1.6, 2.2, 0), Vector2.new(-1, 0.3), rgb(200, 50, 50), 1)
		paint("Block", Vector3.new(1.8, 1, 0), Vector2.new(0.9, 0.9), rgb(40, 80, 170), 1)
		paint("Block", Vector3.new(1.2, 1.2, 0), Vector2.new(1, -0.8), rgb(240, 200, 50), 1)
		paint("Line", Vector3.new(4.4, 0.12, 0), Vector2.new(0, -0.1), rgb(20, 20, 20), 2)
		paint("Line", Vector3.new(0.12, 3.4, 0), Vector2.new(0.05, 0), rgb(20, 20, 20), 2)
	end
end

-- A wall clock whose hands really turn (Atmosphere drives anything tagged "ClockHand")
function Kit.clock(x: number, y: number, z: number, rotation: number, face: Color3?, rim: Color3?)
	local b = frame(x, z, rotation, y)
	cylinder(bit(b, "ClockRim", Vector3.new(2.6, 2.6, 0.3), Vector3.new(0, 0, -0.15), rim or rgb(40, 40, 45)), "Z")
	cylinder(bit(b, "ClockFace", Vector3.new(2.2, 2.2, 0.1), Vector3.new(0, 0, -0.3), face or rgb(245, 245, 240)), "Z")
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local long = i % 3 == 0
		bit(
			b,
			"ClockTick",
			Vector3.new(0.08, if long then 0.3 else 0.18, 0.05),
			Vector3.new(math.sin(a) * 0.9, math.cos(a) * 0.9, -0.37),
			rgb(30, 30, 30)
		).CFrame = b
			* CFrame.new(math.sin(a) * 0.9, math.cos(a) * 0.9, -0.37)
			* CFrame.Angles(0, 0, -a)
	end
	local center = b * CFrame.new(0, 0, -0.42)
	local hands: { { Kind: string, Length: number, Width: number } } = {
		{ Kind = "Hour", Length = 0.55, Width = 0.12 },
		{ Kind = "Minute", Length = 0.85, Width = 0.08 },
		{ Kind = "Second", Length = 0.9, Width = 0.04 },
	}
	for _, hand in hands do
		local kind, length, width = hand.Kind, hand.Length, hand.Width
		local p = deco(
			"ClockHand",
			Vector3.new(width, length, 0.04),
			center * CFrame.new(0, length / 2, 0),
			if kind == "Second" then rgb(200, 30, 30) else rgb(20, 20, 20)
		)
		p:SetAttribute("Hand", kind)
		p:SetAttribute("Center", center)
		p:AddTag("ClockHand")
	end
	ball(deco("ClockPin", Vector3.one * 0.15, center, rgb(20, 20, 20)))
end

export type SignOptions = { Glow: boolean?, Font: Enum.Font?, Material: Enum.Material? }

-- A glowing sign with text (exit signs, door plates, company logos...)
function Kit.sign(
	x: number,
	y: number,
	z: number,
	rotation: number,
	text: string,
	size: Vector2,
	background: Color3,
	textColor: Color3,
	options: SignOptions?
)
	local o: SignOptions = options or {}
	local b = frame(x, z, rotation, y)
	local p = bit(b, "Sign", Vector3.new(size.X, size.Y, 0.2), Vector3.new(0, 0, -0.1), background, o.Material)
	label(p, text, textColor, o.Font, nil, o.Glow)
	if o.Glow then
		light(p, background:Lerp(textColor, 0.3), 8, 0.6)
	end
end

function Kit.exitSign(x: number, y: number, z: number, rotation: number)
	local b = frame(x, z, rotation, y)
	bit(b, "SignBox", Vector3.new(2.8, 1.1, 0.5), Vector3.new(0, 0, -0.25), rgb(235, 235, 235))
	local panel =
		bit(b, "Sign", Vector3.new(2.5, 0.85, 0.06), Vector3.new(0, 0, -0.53), rgb(40, 200, 90), Enum.Material.Neon)
	label(panel, "EXIT", rgb(255, 255, 255), Enum.Font.GothamBlack, nil, true)
	light(panel, rgb(60, 255, 120), 7, 0.5)
end

function Kit.lightSwitch(x: number, y: number, z: number, rotation: number)
	local b = frame(x, z, rotation, y)
	bit(b, "Switch", Vector3.new(0.5, 0.8, 0.08), Vector3.new(0, 0, -0.04), rgb(245, 245, 240))
	bit(b, "Toggle", Vector3.new(0.12, 0.25, 0.1), Vector3.new(0, 0.05, -0.1), rgb(230, 230, 225))
end

function Kit.extinguisher(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation, 0)
	bit(b, "Bracket", Vector3.new(0.9, 0.3, 0.3), Vector3.new(0, 4, -0.15), rgb(60, 60, 60), Enum.Material.Metal)
	cylinder(
		bit(
			b,
			"Extinguisher",
			Vector3.new(0.75, 2.2, 0.75),
			Vector3.new(0, 3.4, -0.55),
			rgb(200, 25, 25),
			Enum.Material.Metal
		),
		"Y"
	)
	bit(b, "Nozzle", Vector3.new(0.25, 0.5, 0.25), Vector3.new(0, 4.7, -0.55), rgb(30, 30, 30))
	bit(b, "Hose", Vector3.new(0.15, 1.4, 0.15), Vector3.new(0.35, 3.8, -0.85), rgb(25, 25, 25))
	local sign = bit(b, "Sign", Vector3.new(1.2, 1.2, 0.05), Vector3.new(0, 6, -0.03), rgb(200, 25, 25))
	label(sign, "FIRE", rgb(255, 255, 255), Enum.Font.GothamBlack)
end

-- Corkboard with pinned notes and a "MISSING" flyer
function Kit.corkboard(x: number, y: number, z: number, rotation: number, flyer: string?)
	local b = frame(x, z, rotation, y)
	bit(b, "BoardFrame", Vector3.new(6.4, 4.2, 0.2), Vector3.new(0, 0, -0.1), rgb(110, 75, 45), Enum.Material.Wood)
	bit(b, "Cork", Vector3.new(6, 3.8, 0.06), Vector3.new(0, 0, -0.22), rgb(190, 145, 95), Enum.Material.Fabric)
	local rng = Random.new(math.floor(x * 31 + z * 17))
	local colors = { rgb(255, 245, 140), rgb(255, 255, 255), rgb(170, 220, 255), rgb(255, 180, 200) }
	for _ = 1, 5 do
		local px, py = rng:NextNumber(0.6, 2.6), rng:NextNumber(-1.3, 1.3)
		local note =
			bit(b, "Note", Vector3.new(0.9, 0.9, 0.03), Vector3.new(px, py, -0.26), colors[rng:NextInteger(1, #colors)])
		note.CFrame = note.CFrame * CFrame.Angles(0, 0, rng:NextNumber(-0.2, 0.2))
		ball(bit(b, "Pin", Vector3.one * 0.12, Vector3.new(px, py + 0.35, -0.3), rgb(220, 40, 40)))
	end
	local poster = bit(b, "Poster", Vector3.new(2.2, 3, 0.03), Vector3.new(-1.6, 0, -0.26), rgb(250, 250, 245))
	label(
		poster,
		flyer or "MISSING\n\nHave you seen this person?\n\nLast seen near the Manor",
		rgb(30, 30, 30),
		Enum.Font.SourceSansBold
	)
	ball(bit(b, "Pin", Vector3.one * 0.12, Vector3.new(-1.6, 1.35, -0.3), rgb(40, 90, 220)))
end

function Kit.whiteboard(x: number, y: number, z: number, rotation: number, text: string)
	local b = frame(x, z, rotation, y)
	bit(b, "BoardFrame", Vector3.new(8.4, 4.4, 0.2), Vector3.new(0, 0, -0.1), rgb(190, 190, 195), Enum.Material.Metal)
	local board = bit(b, "Whiteboard", Vector3.new(8, 4, 0.06), Vector3.new(0, 0, -0.22), rgb(250, 250, 250))
	label(board, text, rgb(30, 60, 160), Enum.Font.PatrickHand)
	bit(b, "Tray", Vector3.new(6, 0.2, 0.5), Vector3.new(0, -2.25, -0.3), rgb(190, 190, 195), Enum.Material.Metal)
	for i, c in { rgb(30, 60, 160), rgb(200, 40, 40), rgb(30, 140, 60) } do
		cylinder(bit(b, "Marker", Vector3.new(0.6, 0.15, 0.15), Vector3.new(-2 + i * 0.8, -2.08, -0.35), c))
	end
end

-- Furniture: offices --------------------------------------------------------------------------

local WOOD = rgb(125, 85, 50)
local DARK_WOOD = rgb(70, 42, 28)
local DARK = rgb(35, 35, 40)
local STEEL = rgb(165, 168, 175)
Kit.WOOD = WOOD
Kit.DARK_WOOD = DARK_WOOD

local SCREENS = { rgb(80, 150, 230), rgb(60, 180, 120), rgb(230, 230, 240), rgb(40, 60, 120) }

function Kit.desk(x: number, z: number, rotation: number, color: Color3?)
	local b = frame(x, z, rotation)
	local c = color or WOOD
	piece(b, "DeskTop", Vector3.new(7, 0.4, 3.4), Vector3.new(0, 3, 0), c, Enum.Material.Wood)
	for _, sx in { -3.2, 3.2 } do
		piece(b, "DeskSide", Vector3.new(0.4, 2.8, 3.2), Vector3.new(sx, 1.4, 0), c, Enum.Material.Wood)
	end
	bit(b, "ModestyPanel", Vector3.new(6, 1.8, 0.2), Vector3.new(0, 1.9, 1.4), darker(c, 0.1), Enum.Material.Wood)
	bit(b, "Drawers", Vector3.new(1.8, 2.6, 2.8), Vector3.new(-2.1, 1.5, 0), darker(c, 0.05), Enum.Material.Wood)
	for i = 0, 2 do
		bit(
			b,
			"Handle",
			Vector3.new(0.6, 0.12, 0.1),
			Vector3.new(-2.1, 0.6 + i * 0.85, -1.45),
			STEEL,
			Enum.Material.Metal
		)
	end
	bit(b, "Monitor", Vector3.new(2.6, 1.8, 0.25), Vector3.new(0.5, 4.3, 0.8), DARK)
	local rng = Random.new(math.floor(x * 13 + z * 7))
	local screen = SCREENS[rng:NextInteger(1, #SCREENS)]
	bit(b, "Screen", Vector3.new(2.3, 1.5, 0.05), Vector3.new(0.5, 4.3, 0.64), screen, Enum.Material.Neon)
	bit(b, "Stand", Vector3.new(0.3, 0.6, 0.3), Vector3.new(0.5, 3.4, 0.8), DARK)
	bit(b, "StandFoot", Vector3.new(1, 0.08, 0.7), Vector3.new(0.5, 3.24, 0.8), DARK)
	bit(b, "Keyboard", Vector3.new(2, 0.12, 0.7), Vector3.new(0.5, 3.26, -0.3), rgb(220, 220, 220))
	bit(b, "Mouse", Vector3.new(0.3, 0.12, 0.45), Vector3.new(2, 3.26, -0.3), rgb(220, 220, 220))
	bit(b, "Papers", Vector3.new(1.1, 0.3, 1.5), Vector3.new(-2.3, 3.35, 0.2), rgb(250, 250, 250))
	if rng:NextNumber() < 0.6 then
		cylinder(
			bit(
				b,
				"Mug",
				Vector3.new(0.35, 0.45, 0.35),
				Vector3.new(-1.2, 3.42, -0.6),
				rng:NextInteger(1, 2) == 1 and rgb(200, 50, 50) or rgb(240, 240, 240)
			),
			"Y"
		)
	end
	if rng:NextNumber() < 0.4 then
		bit(b, "Photo", Vector3.new(0.5, 0.6, 0.08), Vector3.new(2.6, 3.5, 0.6), DARK).CFrame = b
			* CFrame.new(2.6, 3.5, 0.6)
			* CFrame.Angles(math.rad(-15), math.rad(-20), 0)
	end
	-- Office chair: seat, back, gas lift and a five-star base
	local chair = b * CFrame.new(0.5, 0, -2.4) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0)
	piece(chair, "ChairSeat", Vector3.new(2.2, 0.4, 2.2), Vector3.new(0, 1.9, 0), DARK, Enum.Material.Fabric)
	piece(chair, "ChairBack", Vector3.new(2.2, 2.4, 0.35), Vector3.new(0, 3.3, -1), DARK, Enum.Material.Fabric)
	bit(chair, "ChairPole", Vector3.new(0.3, 1.5, 0.3), Vector3.new(0, 1, 0), STEEL, Enum.Material.Metal)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		bit(chair, "ChairLeg", Vector3.new(0.18, 0.18, 1.1), Vector3.zero, DARK).CFrame = chair
			* CFrame.Angles(0, a, 0)
			* CFrame.new(0, 0.25, -0.55)
	end
end

-- Low fabric partition between desk rows
function Kit.cubicle(x: number, z: number, length: number, rotation: number, color: Color3?)
	local b = frame(x, z, rotation)
	local c = color or rgb(120, 130, 150)
	piece(b, "Partition", Vector3.new(length, 4.6, 0.4), Vector3.new(0, 2.3, 0), c, Enum.Material.Fabric)
	bit(b, "PartitionCap", Vector3.new(length, 0.15, 0.5), Vector3.new(0, 4.65, 0), STEEL, Enum.Material.Metal)
end

function Kit.filingCabinet(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	piece(b, "Cabinet", Vector3.new(2, 5.2, 2.4), Vector3.new(0, 2.6, 0), rgb(150, 155, 160), Enum.Material.Metal)
	for i = 0, 3 do
		local y = 0.75 + i * 1.25
		bit(b, "Drawer", Vector3.new(1.8, 1.1, 0.06), Vector3.new(0, y, -1.22), rgb(160, 165, 170), Enum.Material.Metal)
		bit(
			b,
			"Handle",
			Vector3.new(0.7, 0.12, 0.12),
			Vector3.new(0, y + 0.2, -1.3),
			rgb(80, 80, 85),
			Enum.Material.Metal
		)
		bit(b, "LabelCard", Vector3.new(0.5, 0.25, 0.04), Vector3.new(0, y - 0.15, -1.27), rgb(245, 240, 220))
	end
end

function Kit.printer(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	piece(b, "PrinterStand", Vector3.new(3, 2.6, 2.4), Vector3.new(0, 1.3, 0), rgb(60, 60, 65))
	piece(b, "Printer", Vector3.new(2.8, 1.6, 2.2), Vector3.new(0, 3.4, 0), rgb(230, 230, 228))
	bit(b, "PaperTray", Vector3.new(1.8, 0.1, 1), Vector3.new(0, 3.1, -1.4), rgb(210, 210, 208))
	bit(b, "Paper", Vector3.new(1.4, 0.15, 0.9), Vector3.new(0, 3.2, -1.4), rgb(255, 255, 255))
	bit(b, "Panel", Vector3.new(0.9, 0.5, 0.06), Vector3.new(0.8, 3.9, -1.12), rgb(40, 40, 45))
	bit(b, "Led", Vector3.new(0.12, 0.12, 0.05), Vector3.new(0.5, 3.9, -1.16), rgb(60, 255, 120), Enum.Material.Neon)
end

-- A glowing snack / soda machine
function Kit.vending(x: number, z: number, rotation: number, color: Color3)
	local b = frame(x, z, rotation)
	piece(b, "Vending", Vector3.new(4, 8, 3), Vector3.new(0, 4, 0), color, Enum.Material.Metal)
	local window = bit(
		b,
		"VendingGlass",
		Vector3.new(2.6, 5.4, 0.1),
		Vector3.new(-0.5, 4.6, -1.52),
		rgb(220, 240, 255),
		Enum.Material.Glass
	)
	window.Transparency = 0.5
	bit(
		b,
		"VendingBack",
		Vector3.new(2.6, 5.4, 0.1),
		Vector3.new(-0.5, 4.6, -1.3),
		rgb(250, 250, 250),
		Enum.Material.Neon
	)
	local snack = { rgb(220, 40, 40), rgb(255, 200, 40), rgb(40, 140, 220), rgb(60, 180, 70), rgb(240, 120, 30) }
	for row = 0, 4 do
		bit(
			b,
			"Shelf",
			Vector3.new(2.5, 0.08, 0.6),
			Vector3.new(-0.5, 2.3 + row * 1.1, -1.4),
			STEEL,
			Enum.Material.Metal
		)
		for col = 0, 3 do
			bit(
				b,
				"Snack",
				Vector3.new(0.45, 0.7, 0.25),
				Vector3.new(-1.45 + col * 0.63, 2.7 + row * 1.1, -1.42),
				snack[(row + col) % #snack + 1]
			)
		end
	end
	bit(b, "Keypad", Vector3.new(0.8, 1.4, 0.08), Vector3.new(1.35, 5, -1.52), DARK)
	bit(b, "CoinSlot", Vector3.new(0.25, 0.4, 0.08), Vector3.new(1.35, 4, -1.52), STEEL, Enum.Material.Metal)
	bit(b, "Flap", Vector3.new(2.6, 0.8, 0.08), Vector3.new(-0.5, 1.2, -1.52), DARK)
	local logo =
		bit(b, "Logo", Vector3.new(3.6, 0.9, 0.06), Vector3.new(0, 7.4, -1.52), lighter(color, 0.2), Enum.Material.Neon)
	label(logo, "SNACKS", rgb(255, 255, 255), Enum.Font.GothamBlack, nil, true)
	light(logo, lighter(color, 0.4), 10, 0.5)
end

function Kit.trashBin(x: number, z: number, color: Color3?)
	local b = frame(x, z, 0)
	cylinder(
		piece(b, "Bin", Vector3.new(1.3, 2, 1.3), Vector3.new(0, 1, 0), color or rgb(70, 75, 80), Enum.Material.Metal),
		"Y"
	)
	cylinder(bit(b, "BinBag", Vector3.new(1.2, 0.1, 1.2), Vector3.new(0, 2.02, 0), rgb(25, 25, 28)), "Y")
	ball(bit(b, "Paper", Vector3.one * 0.5, Vector3.new(0.2, 2.1, 0.1), rgb(245, 245, 240)))
end

-- Wire shelving loaded with boxes and paint cans
function Kit.shelfUnit(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	for _, sx in { -2.9, 2.9 } do
		for _, sz in { -0.9, 0.9 } do
			bit(b, "ShelfPost", Vector3.new(0.2, 8, 0.2), Vector3.new(sx, 4, sz), STEEL, Enum.Material.Metal)
		end
	end
	local rng = Random.new(math.floor(x * 11 + z * 3))
	for row = 0, 3 do
		local y = 0.4 + row * 2.4
		piece(b, "Shelf", Vector3.new(6, 0.15, 2), Vector3.new(0, y, 0), STEEL, Enum.Material.DiamondPlate)
		local cursor = -2.7
		while cursor < 2.3 do
			local w = rng:NextNumber(0.9, 1.8)
			local h = rng:NextNumber(0.8, 1.7)
			if rng:NextNumber() < 0.25 then
				cylinder(
					bit(
						b,
						"PaintCan",
						Vector3.new(0.7, 0.8, 0.7),
						Vector3.new(cursor + 0.35, y + 0.48, 0),
						rgb(200, 200, 205),
						Enum.Material.Metal
					),
					"Y"
				)
				w = 0.8
			else
				bit(
					b,
					"Box",
					Vector3.new(w, h, 1.5),
					Vector3.new(cursor + w / 2, y + 0.07 + h / 2, rng:NextNumber(-0.15, 0.15)),
					rgb(185, 145, 95):Lerp(rgb(150, 110, 70), rng:NextNumber()),
					Enum.Material.Cardboard
				)
			end
			cursor += w + 0.15
		end
	end
end

-- Three crates on the floor and a fourth stacked on the biggest
function Kit.crates(x: number, z: number)
	local rng = Random.new(math.floor(x * 3 + z * 5))
	local base: Part? = nil
	for i = 1, 4 do
		local s = rng:NextNumber(3, 4.5)
		local cf
		if i == 4 and base then
			cf = CFrame.new(base.Position + Vector3.new(0, base.Size.Y / 2 + s / 2, 0))
				* CFrame.Angles(0, rng:NextNumber(0, 1), 0)
		else
			cf = at(x + rng:NextNumber(-3, 3), s / 2, z + rng:NextNumber(-3, 3))
				* CFrame.Angles(0, rng:NextNumber(0, 1), 0)
		end
		local p = part("Crate", Vector3.one * s, cf, rgb(170, 120, 70), Enum.Material.WoodPlanks)
		if not base or s > base.Size.Y then
			base = p
		end
		-- dark corner battens so they read as crates, not blocks
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				deco(
					"Batten",
					Vector3.new(s + 0.06, 0.3, 0.3),
					p.CFrame * CFrame.new(0, sy * (s / 2 - 0.15), sx * (s / 2 - 0.15)),
					rgb(110, 75, 40),
					Enum.Material.Wood
				)
			end
		end
	end
end

function Kit.mopBucket(x: number, z: number)
	local b = frame(x, z, 25)
	piece(b, "Bucket", Vector3.new(1.8, 1.4, 1.4), Vector3.new(0, 0.9, 0), rgb(240, 200, 30))
	bit(b, "Water", Vector3.new(1.5, 0.1, 1.1), Vector3.new(0, 1.55, 0), rgb(110, 120, 90))
	bit(b, "MopHandle", Vector3.new(0.15, 5, 0.15), Vector3.new(0.3, 3.4, 0.2), rgb(150, 110, 60)).CFrame = b
		* CFrame.new(0.3, 3.4, 0.2)
		* CFrame.Angles(0.2, 0, 0.15)
	local sign = bit(b, "WetFloor", Vector3.new(1.4, 2.4, 0.1), Vector3.new(2, 1.2, 0), rgb(255, 215, 0))
	sign.CFrame = b * CFrame.new(2, 1.2, 0) * CFrame.Angles(math.rad(12), math.rad(-30), 0)
	label(sign, "CAUTION\nWET FLOOR", rgb(20, 20, 20), Enum.Font.GothamBlack)
end

function Kit.waterCooler(x: number, z: number)
	local b = frame(x, z, 0)
	piece(b, "CoolerBase", Vector3.new(1.6, 3, 1.6), Vector3.new(0, 1.5, 0), rgb(235, 235, 235))
	bit(b, "Tap", Vector3.new(0.2, 0.25, 0.3), Vector3.new(-0.3, 2.4, -0.9), rgb(40, 90, 220))
	bit(b, "Tap", Vector3.new(0.2, 0.25, 0.3), Vector3.new(0.3, 2.4, -0.9), rgb(220, 40, 40))
	local bottle = cylinder(
		bit(b, "Bottle", Vector3.new(1.5, 2.2, 1.5), Vector3.new(0, 4.1, 0), rgb(120, 190, 255), Enum.Material.Glass),
		"Y"
	)
	bottle.Transparency = 0.3
	cylinder(bit(b, "Cups", Vector3.new(0.4, 1.2, 0.4), Vector3.new(0.95, 2.2, 0), rgb(250, 250, 250)), "Y")
end

export type CounterOptions = {
	Sink: number?, -- positions along the counter
	Coffee: number?,
	Microwave: number?,
	KnifeBlock: number?,
	Top: Color3?,
	Body: Color3?,
}

-- Counter run with cabinet doors; options add a sink, a coffee machine, a microwave or a stove gap
function Kit.counter(x: number, z: number, length: number, rotation: number, options: CounterOptions?)
	local o: CounterOptions = options or {}
	local b = frame(x, z, rotation)
	local body = o.Body or rgb(240, 240, 235)
	piece(b, "Cabinet", Vector3.new(length, 3, 2.6), Vector3.new(0, 1.5, 0), body)
	bit(b, "Kick", Vector3.new(length, 0.4, 0.1), Vector3.new(0, 0.2, -1.2), darker(body, 0.4))
	piece(
		b,
		"Countertop",
		Vector3.new(length + 0.2, 0.3, 2.9),
		Vector3.new(0, 3.15, 0),
		o.Top or rgb(60, 60, 65),
		Enum.Material.Granite
	)
	local doors = math.max(1, math.floor(length / 2.6))
	local dw = length / doors
	for i = 0, doors - 1 do
		local cx = -length / 2 + (i + 0.5) * dw
		bit(b, "CabinetDoor", Vector3.new(dw - 0.25, 2.3, 0.08), Vector3.new(cx, 1.6, -1.33), lighter(body, 0.05))
		bit(
			b,
			"Handle",
			Vector3.new(0.12, 0.7, 0.12),
			Vector3.new(cx + (if i % 2 == 0 then dw / 2 - 0.45 else -dw / 2 + 0.45), 2.2, -1.42),
			STEEL,
			Enum.Material.Metal
		)
	end
	if o.Sink then
		bit(
			b,
			"Sink",
			Vector3.new(2.6, 0.12, 1.7),
			Vector3.new(o.Sink, 3.32, 0),
			rgb(190, 195, 200),
			Enum.Material.Metal
		)
		bit(
			b,
			"SinkBasin",
			Vector3.new(2.2, 0.1, 1.3),
			Vector3.new(o.Sink, 3.36, 0),
			rgb(120, 125, 130),
			Enum.Material.Metal
		)
		bit(b, "Faucet", Vector3.new(0.2, 1.2, 0.2), Vector3.new(o.Sink, 3.9, 0.9), STEEL, Enum.Material.Metal)
		bit(b, "FaucetSpout", Vector3.new(0.2, 0.2, 0.9), Vector3.new(o.Sink, 4.45, 0.5), STEEL, Enum.Material.Metal)
	end
	if o.Coffee then
		bit(b, "CoffeeMachine", Vector3.new(1.4, 2, 1.4), Vector3.new(o.Coffee, 4.3, 0.3), rgb(30, 30, 32))
		bit(b, "CoffeeTop", Vector3.new(1.4, 0.4, 1.8), Vector3.new(o.Coffee, 5.1, 0.1), rgb(30, 30, 32))
		cylinder(
			bit(
				b,
				"CoffeePot",
				Vector3.new(0.8, 0.9, 0.8),
				Vector3.new(o.Coffee, 3.75, -0.25),
				rgb(60, 35, 20),
				Enum.Material.Glass
			),
			"Y"
		)
		bit(
			b,
			"Led",
			Vector3.new(0.12, 0.12, 0.05),
			Vector3.new(o.Coffee + 0.4, 4.9, -0.43),
			rgb(255, 60, 40),
			Enum.Material.Neon
		)
	end
	if o.Microwave then
		bit(b, "Microwave", Vector3.new(2.2, 1.3, 1.5), Vector3.new(o.Microwave, 3.95, 0.2), rgb(230, 230, 232))
		bit(
			b,
			"MicrowaveDoor",
			Vector3.new(1.4, 0.9, 0.05),
			Vector3.new(o.Microwave - 0.3, 3.95, -0.57),
			rgb(30, 30, 35),
			Enum.Material.Glass
		)
		bit(b, "Panel", Vector3.new(0.4, 0.9, 0.05), Vector3.new(o.Microwave + 0.75, 3.95, -0.57), rgb(60, 60, 65))
		bit(
			b,
			"Clock",
			Vector3.new(0.3, 0.12, 0.05),
			Vector3.new(o.Microwave + 0.75, 4.25, -0.6),
			rgb(80, 255, 120),
			Enum.Material.Neon
		)
	end
	if o.KnifeBlock then
		local kb = b * CFrame.new(o.KnifeBlock, 3.9, 0.5) * CFrame.Angles(math.rad(-20), 0, 0)
		deco("KnifeBlock", Vector3.new(0.9, 1.2, 0.8), kb, DARK_WOOD, Enum.Material.Wood)
		for i = 0, 3 do
			deco("KnifeHandle", Vector3.new(0.12, 0.5, 0.18), kb * CFrame.new(-0.3 + i * 0.2, 0.8, 0), rgb(20, 20, 22))
		end
	end
end

function Kit.fridge(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	piece(b, "Fridge", Vector3.new(3.4, 7.5, 3), Vector3.new(0, 3.75, 0), rgb(235, 240, 245), Enum.Material.Metal)
	bit(b, "FridgeSeam", Vector3.new(3.4, 0.08, 0.06), Vector3.new(0, 5.2, -1.52), rgb(160, 165, 170))
	bit(b, "FridgeHandle", Vector3.new(0.2, 1.4, 0.2), Vector3.new(1.3, 6, -1.6), STEEL, Enum.Material.Metal)
	bit(b, "FridgeHandle", Vector3.new(0.2, 2.4, 0.2), Vector3.new(1.3, 3.8, -1.6), STEEL, Enum.Material.Metal)
	local colors = { rgb(255, 80, 80), rgb(80, 160, 255), rgb(255, 210, 60) }
	for i, c in colors do
		bit(b, "Magnet", Vector3.new(0.35, 0.35, 0.06), Vector3.new(-0.9 + i * 0.4, 6.3 - i * 0.25, -1.53), c)
	end
	bit(b, "Drawing", Vector3.new(1, 1.2, 0.04), Vector3.new(-0.6, 3.8, -1.52), rgb(250, 250, 250))
end

function Kit.tv(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	piece(b, "TVStand", Vector3.new(7, 2.2, 2.2), Vector3.new(0, 1.1, 0), darker(WOOD, 0.4), Enum.Material.Wood)
	bit(b, "TV", Vector3.new(6.4, 3.6, 0.35), Vector3.new(0, 4.2, 0.3), DARK)
	local screen =
		bit(b, "TVScreen", Vector3.new(6, 3.2, 0.05), Vector3.new(0, 4.2, 0.1), rgb(40, 70, 110), Enum.Material.Neon)
	light(screen, rgb(120, 160, 255), 12, 0.4)
	screen:AddTag("Flicker")
	bit(b, "Console", Vector3.new(1.8, 0.4, 1.2), Vector3.new(-1.8, 2.4, -0.2), rgb(25, 25, 28))
	bit(b, "Remote", Vector3.new(0.3, 0.12, 0.9), Vector3.new(1.6, 2.26, -0.4), rgb(20, 20, 20))
end

-- A boxy arcade cabinet in the staff lounge
function Kit.arcade(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	piece(b, "Arcade", Vector3.new(3, 7, 3), Vector3.new(0, 3.5, 0.3), rgb(40, 30, 90))
	bit(b, "ArcadeSide", Vector3.new(0.12, 7, 3.2), Vector3.new(-1.56, 3.5, 0.3), rgb(255, 60, 160))
	bit(b, "ArcadeSide", Vector3.new(0.12, 7, 3.2), Vector3.new(1.56, 3.5, 0.3), rgb(255, 60, 160))
	local screen = bit(
		b,
		"ArcadeScreen",
		Vector3.new(2.4, 2, 0.1),
		Vector3.new(0, 4.6, -1.25),
		rgb(20, 220, 140),
		Enum.Material.Neon
	)
	label(screen, "KNIFE\nRUN", rgb(10, 40, 30), Enum.Font.Arcade, nil, true)
	light(screen, rgb(60, 255, 180), 8, 0.5)
	bit(b, "ControlPanel", Vector3.new(3, 0.3, 1.2), Vector3.new(0, 3.2, -1.6), rgb(30, 30, 35))
	bit(b, "Joystick", Vector3.new(0.15, 0.5, 0.15), Vector3.new(-0.6, 3.6, -1.6), rgb(20, 20, 20))
	ball(bit(b, "JoystickBall", Vector3.one * 0.35, Vector3.new(-0.6, 3.9, -1.6), rgb(230, 30, 30)))
	for i, c in { rgb(255, 220, 40), rgb(40, 140, 255) } do
		cylinder(
			bit(
				b,
				"Button",
				Vector3.new(0.35, 0.12, 0.35),
				Vector3.new(0.2 + i * 0.5, 3.4, -1.6),
				c,
				Enum.Material.Neon
			),
			"Y"
		)
	end
	local marquee =
		bit(b, "Marquee", Vector3.new(3, 0.9, 0.1), Vector3.new(0, 6.4, -1.25), rgb(255, 200, 60), Enum.Material.Neon)
	label(marquee, "ARCADE", rgb(80, 20, 20), Enum.Font.Arcade, nil, true)
end

function Kit.bench(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	piece(b, "BenchSeat", Vector3.new(6, 0.35, 1.8), Vector3.new(0, 1.8, 0), WOOD, Enum.Material.Wood)
	bit(b, "BenchBack", Vector3.new(6, 1.4, 0.3), Vector3.new(0, 2.9, 0.75), WOOD, Enum.Material.Wood)
	for _, sx in { -2.6, 2.6 } do
		bit(b, "BenchLeg", Vector3.new(0.3, 1.7, 1.6), Vector3.new(sx, 0.85, 0), rgb(40, 40, 45), Enum.Material.Metal)
	end
end

-- Steel lift doors at a corridor end, with call buttons and a floor readout
function Kit.elevator(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	bit(
		b,
		"ElevatorFrame",
		Vector3.new(8.4, 10.4, 0.4),
		Vector3.new(0, 5.2, -0.2),
		rgb(120, 120, 125),
		Enum.Material.Metal
	)
	for _, sx in { -1.8, 1.8 } do
		bit(
			b,
			"ElevatorDoor",
			Vector3.new(3.5, 9.2, 0.15),
			Vector3.new(sx, 4.6, -0.45),
			rgb(190, 195, 200),
			Enum.Material.DiamondPlate
		)
	end
	bit(b, "ElevatorGap", Vector3.new(0.08, 9.2, 0.16), Vector3.new(0, 4.6, -0.46), rgb(30, 30, 30))
	local display = bit(b, "FloorDisplay", Vector3.new(1.8, 0.8, 0.1), Vector3.new(0, 9.9, -0.45), rgb(20, 10, 10))
	label(display, "13", rgb(255, 60, 40), Enum.Font.Code, nil, true)
	bit(b, "CallPanel", Vector3.new(0.7, 1.6, 0.1), Vector3.new(5, 4.5, -0.05), STEEL, Enum.Material.Metal)
	for i, c in { rgb(255, 255, 255), rgb(255, 170, 40) } do
		cylinder(
			bit(
				b,
				"CallButton",
				Vector3.new(0.35, 0.35, 0.1),
				Vector3.new(5, 4.1 + i * 0.5, -0.12),
				c,
				Enum.Material.Neon
			),
			"Z"
		)
	end
end

-- Glass front doors with push bars (decor: the outer wall stays solid behind them)
function Kit.glassDoors(x: number, z: number, rotation: number, text: string?)
	local b = frame(x, z, rotation)
	bit(b, "DoorFrame", Vector3.new(9, 10, 0.3), Vector3.new(0, 5, -0.15), rgb(60, 60, 65), Enum.Material.Metal)
	for _, sx in { -2.1, 2.1 } do
		local outside = bit(
			b,
			"Outside",
			Vector3.new(3.8, 8.8, 0.06),
			Vector3.new(sx, 4.6, -0.32),
			rgb(14, 20, 40),
			Enum.Material.Neon
		)
		outside:AddTag("Window")
		local g = bit(
			b,
			"Glass",
			Vector3.new(3.8, 8.8, 0.06),
			Vector3.new(sx, 4.6, -0.4),
			rgb(200, 225, 245),
			Enum.Material.Glass
		)
		g.Transparency = 0.7
		g.Reflectance = 0.25
		bit(b, "PushBar", Vector3.new(3, 0.2, 0.25), Vector3.new(sx, 4, -0.55), STEEL, Enum.Material.Metal)
	end
	if text then
		local sticker = bit(b, "Sticker", Vector3.new(3, 0.6, 0.03), Vector3.new(-2.1, 6.8, -0.44), rgb(255, 255, 255))
		sticker.Transparency = 1
		label(sticker, text, rgb(240, 240, 240), Enum.Font.GothamBold)
	end
	bit(b, "Mat", Vector3.new(7, 0.1, 3), Vector3.new(0, 0.1, -2), rgb(60, 50, 45), Enum.Material.Fabric)
end

function Kit.receptionDesk(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	piece(b, "Reception", Vector3.new(14, 4, 2), Vector3.new(0, 2, 0), rgb(240, 240, 240))
	bit(b, "ReceptionStripe", Vector3.new(14.05, 0.6, 2.05), Vector3.new(0, 2.6, 0), rgb(150, 30, 40))
	piece(
		b,
		"ReceptionTop",
		Vector3.new(14.4, 0.3, 2.6),
		Vector3.new(0, 4.15, 0),
		rgb(60, 60, 65),
		Enum.Material.Marble
	)
	piece(b, "ReceptionWork", Vector3.new(14, 3, 2), Vector3.new(0, 1.5, 2.4), rgb(225, 225, 225))
	bit(b, "Bell", Vector3.new(0.5, 0.3, 0.5), Vector3.new(-4, 4.45, -0.3), rgb(212, 175, 80), Enum.Material.Metal)
	bit(b, "Monitor", Vector3.new(2.4, 1.6, 0.2), Vector3.new(2, 4.3, 2.6), DARK)
	bit(b, "Screen", Vector3.new(2.1, 1.3, 0.05), Vector3.new(2, 4.3, 2.48), rgb(80, 150, 230), Enum.Material.Neon).CFrame = b
		* CFrame.new(2, 4.3, 2.72)
	bit(b, "Phone", Vector3.new(0.9, 0.35, 0.7), Vector3.new(4.5, 3.2, 2.4), DARK)
	cylinder(
		bit(b, "Vase", Vector3.new(0.6, 1, 0.6), Vector3.new(5.8, 4.8, 0), rgb(240, 240, 255), Enum.Material.Glass),
		"Y"
	)
	for i = 0, 2 do
		ball(bit(b, "Flower", Vector3.one * 0.4, Vector3.new(5.6 + i * 0.2, 5.5 + (i % 2) * 0.2, 0), rgb(230, 60, 90)))
	end
	-- chair behind it
	local chair = b * CFrame.new(0, 0, 4.4) * CFrame.Angles(0, math.pi, 0)
	piece(chair, "ChairSeat", Vector3.new(2.2, 0.4, 2.2), Vector3.new(0, 1.9, 0), DARK, Enum.Material.Fabric)
	piece(chair, "ChairBack", Vector3.new(2.2, 2.4, 0.35), Vector3.new(0, 3.3, -1), DARK, Enum.Material.Fabric)
	bit(chair, "ChairPole", Vector3.new(0.3, 1.5, 0.3), Vector3.new(0, 1, 0), STEEL, Enum.Material.Metal)
end

-- Big wood desk, leather chair, a lamp and a nameplate
function Kit.executiveDesk(x: number, z: number, rotation: number, name: string)
	local b = frame(x, z, rotation)
	piece(b, "DeskTop", Vector3.new(10, 0.5, 4.4), Vector3.new(0, 3.2, 0), DARK_WOOD, Enum.Material.Wood)
	piece(
		b,
		"DeskFront",
		Vector3.new(10, 2.95, 0.4),
		Vector3.new(0, 1.5, -2),
		darker(DARK_WOOD, 0.1),
		Enum.Material.Wood
	)
	for _, sx in { -4.4, 4.4 } do
		piece(b, "DeskSide", Vector3.new(1.2, 2.95, 4.2), Vector3.new(sx, 1.5, 0), DARK_WOOD, Enum.Material.Wood)
	end
	bit(b, "Blotter", Vector3.new(4, 0.06, 2.2), Vector3.new(0, 3.48, 0.2), rgb(30, 70, 50), Enum.Material.Fabric)
	local plate = bit(
		b,
		"Nameplate",
		Vector3.new(2.2, 0.5, 0.4),
		Vector3.new(0, 3.7, -1.6),
		rgb(212, 175, 80),
		Enum.Material.Metal
	)
	label(plate, name, rgb(40, 30, 10), Enum.Font.Garamond)
	-- banker's lamp
	bit(b, "LampBase", Vector3.new(0.8, 0.2, 0.6), Vector3.new(3.6, 3.55, 0.8), rgb(212, 175, 80), Enum.Material.Metal)
	bit(
		b,
		"LampStem",
		Vector3.new(0.12, 0.9, 0.12),
		Vector3.new(3.6, 4.05, 0.8),
		rgb(212, 175, 80),
		Enum.Material.Metal
	)
	local shade = bit(
		b,
		"LampShade",
		Vector3.new(1.6, 0.4, 0.7),
		Vector3.new(3.6, 4.55, 0.6),
		rgb(30, 110, 60),
		Enum.Material.Glass
	)
	light(shade, rgb(255, 220, 160), 10, 0.6)
	bit(b, "Laptop", Vector3.new(2, 0.1, 1.4), Vector3.new(-1.5, 3.5, 0.3), rgb(180, 180, 185), Enum.Material.Metal)
	bit(b, "LaptopScreen", Vector3.new(2, 1.3, 0.1), Vector3.new(-1.5, 4.15, 1), rgb(60, 120, 200), Enum.Material.Neon)
	bit(b, "Cigar", Vector3.new(0.12, 0.12, 0.6), Vector3.new(-3.6, 3.55, -0.5), rgb(110, 70, 40))
	-- high-backed leather chair
	local chair = b * CFrame.new(0, 0, 3.5) * CFrame.Angles(0, math.pi, 0)
	local leather = rgb(90, 30, 25)
	piece(chair, "ChairSeat", Vector3.new(2.8, 0.7, 2.6), Vector3.new(0, 2, 0), leather, Enum.Material.Leather)
	piece(chair, "ChairBack", Vector3.new(2.8, 3.8, 0.6), Vector3.new(0, 4, 1.2), leather, Enum.Material.Leather)
	for _, sx in { -1.5, 1.5 } do
		bit(chair, "ChairArm", Vector3.new(0.4, 0.9, 2.4), Vector3.new(sx, 2.7, 0), leather, Enum.Material.Leather)
	end
	bit(chair, "ChairPole", Vector3.new(0.35, 1.6, 0.35), Vector3.new(0, 0.9, 0), DARK, Enum.Material.Metal)
end

function Kit.safe(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	piece(b, "Safe", Vector3.new(3, 3.6, 2.8), Vector3.new(0, 1.8, 0), rgb(50, 55, 60), Enum.Material.Metal)
	bit(b, "SafeDoor", Vector3.new(2.5, 3.1, 0.1), Vector3.new(0, 1.8, -1.42), rgb(60, 66, 72), Enum.Material.Metal)
	cylinder(
		bit(b, "Dial", Vector3.new(0.9, 0.9, 0.15), Vector3.new(0, 2.2, -1.5), rgb(212, 175, 80), Enum.Material.Metal),
		"Z"
	)
	bit(
		b,
		"SafeHandle",
		Vector3.new(0.9, 0.15, 0.2),
		Vector3.new(0, 1.2, -1.52),
		rgb(212, 175, 80),
		Enum.Material.Metal
	)
end

-- Pull-down screen with a chart projected on it
function Kit.projectorScreen(x: number, y: number, z: number, rotation: number)
	local b = frame(x, z, rotation, y)
	bit(b, "ScreenCase", Vector3.new(11, 0.5, 0.5), Vector3.new(0, 3.3, -0.3), rgb(40, 40, 45))
	local screen = bit(b, "ProjectorScreen", Vector3.new(10, 6, 0.05), Vector3.new(0, 0, -0.3), rgb(250, 250, 248))
	local art = WorldSignModel.Attach("ProjectorScreen", screen, Enum.NormalId.Front)
	for _, p in art:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			p.CanCollide = true
		end
	end
end

-- Furniture: homes ---------------------------------------------------------------------------

function Kit.sofa(x: number, z: number, rotation: number, color: Color3, length: number?)
	local b = frame(x, z, rotation)
	local l = length or 8
	piece(b, "SofaSeat", Vector3.new(l, 1.6, 3.2), Vector3.new(0, 0.8, 0), color, Enum.Material.Fabric)
	piece(b, "SofaBack", Vector3.new(l, 2.6, 0.9), Vector3.new(0, 2.1, 1.2), color, Enum.Material.Fabric)
	for _, sx in { -(l / 2 - 0.45), l / 2 - 0.45 } do
		piece(b, "SofaArm", Vector3.new(0.9, 2.3, 3.2), Vector3.new(sx, 1.15, 0), color, Enum.Material.Fabric)
	end
	-- separate seat cushions with a gap between them, plus a couple of throw pillows
	local n = math.max(2, math.floor((l - 1.8) / 3))
	local cw = (l - 1.8) / n
	for i = 0, n - 1 do
		bit(
			b,
			"Cushion",
			Vector3.new(cw - 0.12, 0.45, 2.3),
			Vector3.new(-l / 2 + 0.9 + (i + 0.5) * cw, 1.82, -0.25),
			lighter(color, 0.12),
			Enum.Material.Fabric
		)
	end
	for _, sx in { -(l / 2 - 1.6), l / 2 - 1.6 } do
		bit(
			b,
			"Pillow",
			Vector3.new(1.4, 1.4, 0.45),
			Vector3.new(sx, 2.6, 0.5),
			lighter(color, 0.35),
			Enum.Material.Fabric
		).CFrame = b
			* CFrame.new(sx, 2.6, 0.5)
			* CFrame.Angles(math.rad(-15), 0, math.rad(if sx > 0 then -12 else 12))
	end
	for _, sx in { -(l / 2 - 0.5), l / 2 - 0.5 } do
		for _, sz in { -1.3, 1.3 } do
			bit(b, "SofaFoot", Vector3.new(0.3, 0.25, 0.3), Vector3.new(sx, -0.1, sz), DARK_WOOD)
		end
	end
end

function Kit.armchair(x: number, z: number, rotation: number, color: Color3)
	local b = frame(x, z, rotation)
	piece(b, "ArmchairSeat", Vector3.new(3.2, 1.6, 3.2), Vector3.new(0, 0.9, 0), color, Enum.Material.Fabric)
	piece(b, "ArmchairBack", Vector3.new(3.2, 3.6, 0.8), Vector3.new(0, 2.6, 1.2), color, Enum.Material.Fabric)
	for _, sx in { -1.45, 1.45 } do
		piece(
			b,
			"ArmchairArm",
			Vector3.new(0.6, 2.4, 3.2),
			Vector3.new(sx, 1.4, 0),
			darker(color, 0.08),
			Enum.Material.Fabric
		)
	end
	bit(
		b,
		"Cushion",
		Vector3.new(2.2, 0.4, 2.3),
		Vector3.new(0, 1.9, -0.25),
		lighter(color, 0.12),
		Enum.Material.Fabric
	)
	for _, sx in { -1.4, 1.4 } do
		for _, sz in { -1.4, 1.4 } do
			bit(b, "Foot", Vector3.new(0.3, 0.3, 0.3), Vector3.new(sx, 0, sz), DARK_WOOD)
		end
	end
end

local LEAF = rgb(60, 150, 60)

function Kit.plant(x: number, z: number, kind: ("Bush" | "Tall" | "Fern")?)
	local b = frame(x, z, 0)
	local pot = cylinder(piece(b, "Pot", Vector3.new(2.2, 2, 2.2), Vector3.new(0, 1, 0), rgb(170, 95, 60)), "Y")
	local _ = pot
	cylinder(bit(b, "PotRim", Vector3.new(2.5, 0.3, 2.5), Vector3.new(0, 1.9, 0), rgb(150, 80, 50)), "Y")
	cylinder(bit(b, "Soil", Vector3.new(2, 0.1, 2), Vector3.new(0, 2.02, 0), rgb(60, 40, 25)), "Y")
	if kind == "Tall" then
		bit(b, "Trunk", Vector3.new(0.3, 5, 0.3), Vector3.new(0, 4.5, 0), rgb(100, 70, 40), Enum.Material.Wood)
		for i, offset in
			{
				Vector3.new(0, 7.2, 0),
				Vector3.new(0.9, 6.3, 0.4),
				Vector3.new(-0.8, 6.6, -0.5),
				Vector3.new(0.2, 5.5, -0.9),
			}
		do
			ball(bit(b, "Leaves", Vector3.one * (2.4 - i * 0.2), offset, darker(LEAF, i * 0.05), Enum.Material.Grass))
		end
	elseif kind == "Fern" then
		for i = 0, 6 do
			local a = i / 7 * math.pi * 2
			bit(b, "Frond", Vector3.new(0.5, 0.12, 2.6), Vector3.zero, LEAF, Enum.Material.Grass).CFrame = b
				* CFrame.new(0, 2.4, 0)
				* CFrame.Angles(0, a, 0)
				* CFrame.Angles(math.rad(25), 0, 0)
				* CFrame.new(0, 0, -1.1)
		end
	else
		for i, offset in
			{
				Vector3.new(0, 3.2, 0),
				Vector3.new(0.6, 4.2, 0.3),
				Vector3.new(-0.5, 4.6, -0.4),
				Vector3.new(0.1, 5.3, 0.1),
			}
		do
			ball(bit(b, "Leaves", Vector3.one * (2.6 - i * 0.3), offset, darker(LEAF, i * 0.04), Enum.Material.Grass))
		end
	end
end

function Kit.floorLamp(x: number, z: number, color: Color3?)
	local b = frame(x, z, 0)
	cylinder(
		bit(b, "LampBase", Vector3.new(1.4, 0.2, 1.4), Vector3.new(0, 0.1, 0), rgb(40, 40, 40), Enum.Material.Metal),
		"Y"
	)
	bit(b, "LampPole", Vector3.new(0.15, 6, 0.15), Vector3.new(0, 3.1, 0), rgb(40, 40, 40), Enum.Material.Metal)
	local shade = cylinder(
		bit(
			b,
			"LampShade",
			Vector3.new(1.8, 1.4, 1.8),
			Vector3.new(0, 6.6, 0),
			color or rgb(240, 225, 190),
			Enum.Material.Fabric
		),
		"Y"
	)
	light(shade, rgb(255, 210, 150), 14, 0.7)
end

function Kit.coffeeTable(x: number, z: number, sizeX: number, sizeZ: number, rotation: number?)
	local b = frame(x, z, rotation)
	piece(b, "CoffeeTable", Vector3.new(sizeX, 0.35, sizeZ), Vector3.new(0, 1.6, 0), DARK_WOOD, Enum.Material.Wood)
	bit(b, "Shelf", Vector3.new(sizeX - 0.6, 0.2, sizeZ - 0.6), Vector3.new(0, 0.5, 0), DARK_WOOD, Enum.Material.Wood)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			bit(
				b,
				"Leg",
				Vector3.new(0.3, 1.45, 0.3),
				Vector3.new(sx * (sizeX / 2 - 0.3), 0.72, sz * (sizeZ / 2 - 0.3)),
				DARK_WOOD
			)
		end
	end
	bit(b, "Magazine", Vector3.new(1, 0.06, 1.3), Vector3.new(-sizeX / 4, 1.8, 0), rgb(220, 60, 60)).CFrame = b
		* CFrame.new(-sizeX / 4, 1.8, 0)
		* CFrame.Angles(0, 0.3, 0)
	cylinder(bit(b, "Mug", Vector3.new(0.35, 0.45, 0.35), Vector3.new(sizeX / 4, 2, 0.2), rgb(240, 240, 240)), "Y")
end

function Kit.tableWithChairs(x: number, z: number, sizeX: number, sizeZ: number, color: Color3?)
	local b = frame(x, z, 0)
	local c = color or WOOD
	piece(b, "Table", Vector3.new(sizeX, 0.5, sizeZ), Vector3.new(0, 3, 0), c, Enum.Material.Wood)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			piece(
				b,
				"TableLeg",
				Vector3.new(0.5, 2.8, 0.5),
				Vector3.new(sx * (sizeX / 2 - 0.6), 1.4, sz * (sizeZ / 2 - 0.6)),
				c
			)
		end
	end
	local chairs = math.max(1, math.floor(sizeX / 4))
	for i = 1, chairs do
		local cx = -sizeX / 2 + (i - 0.5) * sizeX / chairs
		for _, side in { -1, 1 } do
			local chair = b
				* CFrame.new(cx, 0, side * (sizeZ / 2 + 1.4))
				* CFrame.Angles(0, if side > 0 then 0 else math.pi, 0)
			piece(chair, "ChairSeat", Vector3.new(2, 0.35, 2), Vector3.new(0, 1.9, 0), c)
			piece(chair, "ChairBack", Vector3.new(2, 2.4, 0.3), Vector3.new(0, 3.2, 0.9), c)
			for _, lx in { -0.8, 0.8 } do
				for _, lz in { -0.8, 0.8 } do
					bit(chair, "ChairLeg", Vector3.new(0.25, 1.75, 0.25), Vector3.new(lx, 0.88, lz), darker(c, 0.3))
				end
			end
		end
	end
end

-- Candle holder with three lit candles (one warm light for all of them)
local function candelabra(base: CFrame, y: number)
	local gold = rgb(212, 175, 80)
	local b = base * CFrame.new(0, y, 0)
	cylinder(deco("Candelabra", Vector3.new(0.9, 0.2, 0.9), b * CFrame.new(0, 0.1, 0), gold, Enum.Material.Metal), "Y")
	deco("Candelabra", Vector3.new(0.15, 1.4, 0.15), b * CFrame.new(0, 0.8, 0), gold, Enum.Material.Metal)
	deco("Candelabra", Vector3.new(1.8, 0.12, 0.12), b * CFrame.new(0, 1.4, 0), gold, Enum.Material.Metal)
	local first: Part? = nil
	for _, sx in { -0.85, 0, 0.85 } do
		local h = if sx == 0 then 0.9 else 0.7
		cylinder(
			deco("Candle", Vector3.new(0.22, h, 0.22), b * CFrame.new(sx, 1.5 + h / 2, 0), rgb(245, 240, 225)),
			"Y"
		)
		local f = ball(
			deco(
				"Flame",
				Vector3.new(0.18, 0.3, 0.18),
				b * CFrame.new(sx, 1.65 + h, 0),
				rgb(255, 190, 80),
				Enum.Material.Neon
			)
		)
		first = first or f
	end
	if first then
		light(first, rgb(255, 180, 90), 12, 0.6)
		flame(first)
	end
end

-- A long dining table in a white cloth, chairs down both long sides, places set
function Kit.diningTable(x: number, z: number, length: number, width: number, chairColor: Color3)
	local b = frame(x, z, 0)
	piece(b, "Table", Vector3.new(length, 0.5, width), Vector3.new(0, 3, 0), DARK_WOOD, Enum.Material.Wood)
	bit(
		b,
		"Tablecloth",
		Vector3.new(length + 0.4, 0.08, width - 1.2),
		Vector3.new(0, 3.28, 0),
		rgb(245, 242, 235),
		Enum.Material.Fabric
	)
	bit(
		b,
		"Runner",
		Vector3.new(length - 2, 0.06, 1.2),
		Vector3.new(0, 3.33, 0),
		rgb(150, 25, 35),
		Enum.Material.Fabric
	)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			piece(
				b,
				"TableLeg",
				Vector3.new(0.6, 2.8, 0.6),
				Vector3.new(sx * (length / 2 - 0.8), 1.4, sz * (width / 2 - 0.6)),
				DARK_WOOD,
				Enum.Material.Wood
			)
		end
	end
	local seats = math.max(1, math.floor(length / 3.6))
	for i = 1, seats do
		local cx = -length / 2 + (i - 0.5) * length / seats
		for _, side in { -1, 1 } do
			-- plate, glass and cutlery
			local place = b * CFrame.new(cx, 3.33, side * (width / 2 - 1.1))
			cylinder(deco("Plate", Vector3.new(1.2, 0.08, 1.2), place, rgb(250, 250, 250)), "Y")
			cylinder(
				deco(
					"Glass",
					Vector3.new(0.3, 0.6, 0.3),
					place * CFrame.new(0.8, 0.3, -side * 0.5),
					rgb(220, 240, 255),
					Enum.Material.Glass
				),
				"Y"
			).Transparency =
				0.4
			deco(
				"Fork",
				Vector3.new(0.08, 0.04, 0.8),
				place * CFrame.new(-0.85, 0.02, 0),
				rgb(200, 200, 205),
				Enum.Material.Metal
			)
			deco(
				"Knife",
				Vector3.new(0.08, 0.04, 0.9),
				place * CFrame.new(0.85, 0.02, 0),
				rgb(200, 200, 205),
				Enum.Material.Metal
			)
			local chair = b
				* CFrame.new(cx, 0, side * (width / 2 + 1.3))
				* CFrame.Angles(0, if side > 0 then 0 else math.pi, 0)
			piece(chair, "ChairSeat", Vector3.new(2.1, 0.4, 2), Vector3.new(0, 1.9, 0), DARK_WOOD, Enum.Material.Wood)
			bit(
				chair,
				"ChairPad",
				Vector3.new(1.8, 0.2, 1.7),
				Vector3.new(0, 2.15, 0),
				chairColor,
				Enum.Material.Fabric
			)
			piece(
				chair,
				"ChairBack",
				Vector3.new(2.1, 3.6, 0.3),
				Vector3.new(0, 3.8, 0.9),
				DARK_WOOD,
				Enum.Material.Wood
			)
			bit(
				chair,
				"ChairBackPad",
				Vector3.new(1.5, 2.2, 0.1),
				Vector3.new(0, 3.9, 0.72),
				chairColor,
				Enum.Material.Fabric
			)
			for _, lx in { -0.85, 0.85 } do
				for _, lz in { -0.8, 0.8 } do
					bit(chair, "ChairLeg", Vector3.new(0.25, 1.75, 0.25), Vector3.new(lx, 0.88, lz), DARK_WOOD)
				end
			end
		end
	end
	for _, cx in { -length / 4, length / 4 } do
		candelabra(b * CFrame.new(cx, 0, 0), 3.35)
	end
end

function Kit.roundTable(x: number, z: number, radius: number)
	local b = frame(x, z, 0)
	cylinder(
		piece(
			b,
			"Table",
			Vector3.new(radius * 2, 0.4, radius * 2),
			Vector3.new(0, 3.4, 0),
			DARK_WOOD,
			Enum.Material.Wood
		),
		"Y"
	)
	cylinder(bit(b, "Pedestal", Vector3.new(0.8, 3.2, 0.8), Vector3.new(0, 1.7, 0), DARK_WOOD, Enum.Material.Wood), "Y")
	cylinder(bit(b, "Foot", Vector3.new(2.4, 0.3, 2.4), Vector3.new(0, 0.15, 0), DARK_WOOD, Enum.Material.Wood), "Y")
	cylinder(bit(b, "Vase", Vector3.new(1, 2, 1), Vector3.new(0, 4.6, 0), rgb(40, 60, 140), Enum.Material.Glass), "Y")
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2
		ball(
			bit(
				b,
				"Flower",
				Vector3.one * 0.55,
				Vector3.new(math.cos(a) * 0.5, 5.9 + (i % 2) * 0.3, math.sin(a) * 0.5),
				if i % 2 == 0 then rgb(170, 20, 40) else rgb(240, 240, 240)
			)
		)
	end
end

function Kit.bookshelf(x: number, z: number, rotation: number, color: Color3?)
	local b = frame(x, z, rotation)
	local wood = color or darker(WOOD, 0.25)
	piece(b, "Shelf", Vector3.new(7, 9, 1.8), Vector3.new(0, 4.5, 0.15), wood, Enum.Material.Wood)
	bit(b, "ShelfTop", Vector3.new(7.4, 0.4, 2.1), Vector3.new(0, 9.2, 0), darker(wood, 0.15), Enum.Material.Wood)
	local rng = Random.new(math.floor(x * 7 + z * 13))
	local colors =
		{ rgb(180, 40, 40), rgb(40, 80, 170), rgb(50, 130, 60), rgb(220, 180, 60), rgb(90, 50, 110), rgb(60, 40, 30) }
	for row = 0, 3 do
		bit(
			b,
			"ShelfBoard",
			Vector3.new(6.6, 0.15, 1.6),
			Vector3.new(0, 0.82 + row * 2.1, -0.85),
			darker(wood, 0.2),
			Enum.Material.Wood
		)
		local cursor = -3.1
		while cursor < 2.8 do
			local w = rng:NextNumber(0.35, 0.7)
			local h = rng:NextNumber(1.3, 1.8)
			local book = bit(
				b,
				"Book",
				Vector3.new(w, h, 1.2),
				Vector3.new(cursor + w / 2, 0.9 + row * 2.1 + h / 2, -0.95),
				colors[rng:NextInteger(1, #colors)]
			)
			if rng:NextNumber() < 0.08 then
				-- the odd book leaning over
				book.CFrame = book.CFrame * CFrame.Angles(0, 0, math.rad(-18))
				cursor += 0.3
			end
			cursor += w + 0.05
		end
	end
end

function Kit.bed(x: number, z: number, rotation: number, color: Color3)
	local b = frame(x, z, rotation)
	piece(b, "BedFrame", Vector3.new(6, 1.4, 9), Vector3.new(0, 0.7, 0), WOOD, Enum.Material.Wood)
	piece(b, "Mattress", Vector3.new(5.6, 0.8, 8.4), Vector3.new(0, 1.8, 0), rgb(245, 245, 245), Enum.Material.Fabric)
	bit(b, "Blanket", Vector3.new(5.8, 0.3, 5.5), Vector3.new(0, 2.25, -1.3), color, Enum.Material.Fabric)
	bit(
		b,
		"BlanketFold",
		Vector3.new(5.8, 0.35, 0.8),
		Vector3.new(0, 2.3, 1.3),
		lighter(color, 0.3),
		Enum.Material.Fabric
	)
	bit(b, "Pillow", Vector3.new(3.6, 0.6, 1.6), Vector3.new(0, 2.5, 3.2), rgb(255, 255, 255), Enum.Material.Fabric)
	piece(b, "Headboard", Vector3.new(6, 4, 0.5), Vector3.new(0, 2, 4.4), WOOD, Enum.Material.Wood)
end

-- Canopy bed with turned posts and drapes
function Kit.fourPosterBed(x: number, z: number, rotation: number, color: Color3)
	local b = frame(x, z, rotation)
	piece(b, "BedFrame", Vector3.new(7.4, 1.6, 10), Vector3.new(0, 0.8, 0), DARK_WOOD, Enum.Material.Wood)
	piece(b, "Mattress", Vector3.new(7, 1, 9.4), Vector3.new(0, 2.1, 0), rgb(245, 240, 230), Enum.Material.Fabric)
	bit(b, "Blanket", Vector3.new(7.3, 0.35, 6.4), Vector3.new(0, 2.7, -1.6), color, Enum.Material.Fabric)
	bit(b, "Blanket", Vector3.new(7.5, 1.6, 0.2), Vector3.new(0, 2, -4.8), color, Enum.Material.Fabric)
	for _, sx in { -1.7, 1.7 } do
		bit(b, "Pillow", Vector3.new(2.8, 0.8, 1.6), Vector3.new(sx, 3, 3.6), rgb(255, 255, 255), Enum.Material.Fabric)
	end
	piece(b, "Headboard", Vector3.new(7.4, 5.5, 0.6), Vector3.new(0, 2.75, 4.9), DARK_WOOD, Enum.Material.Wood)
	for _, sx in { -3.5, 3.5 } do
		for _, sz in { -4.8, 4.8 } do
			cylinder(
				piece(b, "BedPost", Vector3.new(0.45, 10, 0.45), Vector3.new(sx, 5, sz), DARK_WOOD, Enum.Material.Wood),
				"Y"
			)
			ball(
				bit(
					b,
					"PostFinial",
					Vector3.one * 0.6,
					Vector3.new(sx, 10.1, sz),
					rgb(212, 175, 80),
					Enum.Material.Metal
				)
			)
		end
	end
	bit(b, "Canopy", Vector3.new(7.6, 0.25, 10.2), Vector3.new(0, 9.8, 0), darker(color, 0.25), Enum.Material.Fabric)
	for _, sx in { -3.7, 3.7 } do
		bit(
			b,
			"Drape",
			Vector3.new(0.15, 1.4, 10.2),
			Vector3.new(sx, 9.1, 0),
			darker(color, 0.25),
			Enum.Material.Fabric
		)
		for _, sz in { -4.5, 4.5 } do
			bit(
				b,
				"Drape",
				Vector3.new(0.3, 8.4, 1.4),
				Vector3.new(sx, 5.6, sz),
				darker(color, 0.25),
				Enum.Material.Fabric
			)
		end
	end
	-- a chest at the foot of the bed
	piece(b, "Chest", Vector3.new(4.5, 2, 2), Vector3.new(0, 1, -6.6), DARK_WOOD, Enum.Material.Wood)
	bit(
		b,
		"ChestLid",
		Vector3.new(4.7, 0.3, 2.2),
		Vector3.new(0, 2.1, -6.6),
		darker(DARK_WOOD, 0.2),
		Enum.Material.Wood
	)
	bit(b, "ChestLock", Vector3.new(0.5, 0.6, 0.1), Vector3.new(0, 1.6, -7.65), rgb(212, 175, 80), Enum.Material.Metal)
end

function Kit.nightstand(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	piece(b, "Nightstand", Vector3.new(2.2, 2.6, 2), Vector3.new(0, 1.3, 0), DARK_WOOD, Enum.Material.Wood)
	bit(
		b,
		"Drawer",
		Vector3.new(1.8, 0.8, 0.06),
		Vector3.new(0, 1.9, -1.02),
		darker(DARK_WOOD, 0.15),
		Enum.Material.Wood
	)
	ball(bit(b, "Knob", Vector3.one * 0.2, Vector3.new(0, 1.9, -1.1), rgb(212, 175, 80), Enum.Material.Metal))
	cylinder(
		bit(b, "LampBase", Vector3.new(0.5, 1, 0.5), Vector3.new(0, 3.1, 0.2), rgb(200, 190, 170), Enum.Material.Marble),
		"Y"
	)
	local shade = cylinder(
		bit(
			b,
			"LampShade",
			Vector3.new(1.2, 0.9, 1.2),
			Vector3.new(0, 4, 0.2),
			rgb(245, 225, 190),
			Enum.Material.Fabric
		),
		"Y"
	)
	light(shade, rgb(255, 205, 140), 10, 0.5)
	bit(b, "Book", Vector3.new(0.9, 0.2, 1.2), Vector3.new(-0.5, 2.7, -0.3), rgb(120, 30, 30))
end

function Kit.wardrobe(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	piece(b, "Wardrobe", Vector3.new(5, 9, 2.4), Vector3.new(0, 4.5, 0), DARK_WOOD, Enum.Material.Wood)
	bit(
		b,
		"WardrobeTop",
		Vector3.new(5.4, 0.5, 2.7),
		Vector3.new(0, 9.2, 0),
		darker(DARK_WOOD, 0.15),
		Enum.Material.Wood
	)
	for _, sx in { -1.22, 1.22 } do
		bit(
			b,
			"WardrobeDoor",
			Vector3.new(2.3, 7.4, 0.08),
			Vector3.new(sx, 4.9, -1.23),
			darker(DARK_WOOD, 0.1),
			Enum.Material.Wood
		)
		bit(
			b,
			"DoorPanel",
			Vector3.new(1.6, 2.6, 0.06),
			Vector3.new(sx, 6.6, -1.28),
			darker(DARK_WOOD, 0.22),
			Enum.Material.Wood
		)
		bit(
			b,
			"DoorPanel",
			Vector3.new(1.6, 2.6, 0.06),
			Vector3.new(sx, 3.2, -1.28),
			darker(DARK_WOOD, 0.22),
			Enum.Material.Wood
		)
	end
	for _, sx in { -0.25, 0.25 } do
		ball(bit(b, "Knob", Vector3.one * 0.25, Vector3.new(sx, 5, -1.32), rgb(212, 175, 80), Enum.Material.Metal))
	end
	-- a door left slightly open: something might be in there
	bit(b, "Gap", Vector3.new(0.08, 7.4, 0.1), Vector3.new(0, 4.9, -1.24), rgb(10, 10, 10))
end

function Kit.vanity(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	piece(b, "Vanity", Vector3.new(5, 3, 2), Vector3.new(0, 1.5, 0), rgb(240, 235, 225))
	bit(b, "VanityTop", Vector3.new(5.2, 0.2, 2.2), Vector3.new(0, 3.1, 0), rgb(255, 250, 240), Enum.Material.Marble)
	bit(
		b,
		"MirrorFrame",
		Vector3.new(3.6, 4.4, 0.25),
		Vector3.new(0, 5.6, 0.85),
		rgb(212, 175, 80),
		Enum.Material.Metal
	)
	local mirror =
		bit(b, "Mirror", Vector3.new(3.2, 4, 0.1), Vector3.new(0, 5.6, 0.7), rgb(200, 210, 220), Enum.Material.Glass)
	mirror.Reflectance = 0.6
	for i, c in { rgb(230, 80, 120), rgb(140, 90, 200), rgb(250, 250, 250) } do
		cylinder(
			bit(b, "Bottle", Vector3.new(0.3, 0.6, 0.3), Vector3.new(-2 + i * 0.4, 3.5, 0.3), c, Enum.Material.Glass),
			"Y"
		)
	end
	bit(b, "Brush", Vector3.new(0.3, 0.12, 1), Vector3.new(1.5, 3.25, -0.2), rgb(120, 80, 50))
	piece(b, "Stool", Vector3.new(1.8, 0.4, 1.8), Vector3.new(0, 1.8, -2.4), rgb(200, 120, 150), Enum.Material.Fabric)
	cylinder(
		bit(
			b,
			"StoolLeg",
			Vector3.new(0.4, 1.6, 0.4),
			Vector3.new(0, 0.8, -2.4),
			rgb(212, 175, 80),
			Enum.Material.Metal
		),
		"Y"
	)
end

function Kit.stove(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	piece(b, "Stove", Vector3.new(5, 3.3, 2.8), Vector3.new(0, 1.65, 0), rgb(40, 40, 42), Enum.Material.Metal)
	bit(b, "OvenDoor", Vector3.new(4.2, 2, 0.1), Vector3.new(0, 1.4, -1.42), rgb(55, 55, 58), Enum.Material.Metal)
	bit(b, "OvenWindow", Vector3.new(2.6, 0.9, 0.06), Vector3.new(0, 1.5, -1.48), rgb(255, 120, 40), Enum.Material.Neon)
	bit(b, "OvenHandle", Vector3.new(3.4, 0.15, 0.2), Vector3.new(0, 2.25, -1.55), STEEL, Enum.Material.Metal)
	for i = 0, 3 do
		bit(b, "Dial", Vector3.new(0.3, 0.3, 0.1), Vector3.new(-1.5 + i, 2.85, -1.45), rgb(220, 220, 220))
	end
	for _, sx in { -1.2, 1.2 } do
		for _, sz in { -0.6, 0.6 } do
			cylinder(bit(b, "Burner", Vector3.new(1.2, 0.08, 1.2), Vector3.new(sx, 3.34, sz), rgb(20, 20, 20)), "Y")
		end
	end
	-- a pot on the boil
	local pot = cylinder(
		bit(b, "Pot", Vector3.new(1.3, 0.9, 1.3), Vector3.new(-1.2, 3.8, -0.6), rgb(150, 150, 155), Enum.Material.Metal),
		"Y"
	)
	local steam = Instance.new("ParticleEmitter")
	steam.Texture = Textures.Smoke
	steam.Color = ColorSequence.new(rgb(240, 240, 240))
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	steam.Size = NumberSequence.new(0.6, 2)
	steam.Speed = NumberRange.new(1, 2)
	steam.Lifetime = NumberRange.new(1.5, 2.5)
	steam.Rate = 3
	steam.SpreadAngle = Vector2.new(10, 10)
	steam.EmissionDirection = Enum.NormalId.Right -- the pot is a cylinder turned upright: its +X points up
	steam.Parent = pot
	-- range hood
	bit(b, "Hood", Vector3.new(5, 1.4, 2.6), Vector3.new(0, 8.6, 0.2), STEEL, Enum.Material.Metal)
	bit(b, "HoodChimney", Vector3.new(1.8, 4, 1.5), Vector3.new(0, 11.3, 0.7), STEEL, Enum.Material.Metal)
	local hoodLight = bit(
		b,
		"HoodLight",
		Vector3.new(1.2, 0.08, 0.6),
		Vector3.new(0, 7.88, -0.4),
		rgb(255, 230, 180),
		Enum.Material.Neon
	)
	light(hoodLight, rgb(255, 220, 170), 8, 0.5)
end

-- Pots and pans hanging from a rail on the wall
function Kit.potRail(x: number, y: number, z: number, rotation: number, length: number)
	local b = frame(x, z, rotation, y)
	bit(b, "Rail", Vector3.new(length, 0.15, 0.15), Vector3.new(0, 0, -0.4), STEEL, Enum.Material.Metal)
	local n = math.floor(length / 1.6)
	for i = 0, n - 1 do
		local px = -length / 2 + 0.8 + i * 1.6
		bit(b, "Hook", Vector3.new(0.06, 0.5, 0.06), Vector3.new(px, -0.3, -0.4), STEEL, Enum.Material.Metal)
		if i % 2 == 0 then
			cylinder(
				bit(
					b,
					"Pan",
					Vector3.new(1.2, 0.15, 1.2),
					Vector3.new(px, -1.3, -0.45),
					rgb(40, 40, 42),
					Enum.Material.Metal
				),
				"Z"
			)
		else
			bit(b, "Ladle", Vector3.new(0.15, 1.4, 0.1), Vector3.new(px, -1.1, -0.45), STEEL, Enum.Material.Metal)
			ball(bit(b, "LadleCup", Vector3.one * 0.45, Vector3.new(px, -1.85, -0.45), STEEL, Enum.Material.Metal))
		end
	end
end

function Kit.kitchenIsland(x: number, z: number, length: number, rotation: number)
	local b = frame(x, z, rotation)
	piece(b, "Island", Vector3.new(length, 3, 3.6), Vector3.new(0, 1.5, 0), rgb(60, 80, 100))
	piece(
		b,
		"IslandTop",
		Vector3.new(length + 0.6, 0.3, 4.4),
		Vector3.new(0, 3.15, 0),
		rgb(235, 235, 230),
		Enum.Material.Marble
	)
	bit(
		b,
		"CuttingBoard",
		Vector3.new(2, 0.15, 1.2),
		Vector3.new(-length / 4, 3.38, 0),
		rgb(190, 140, 90),
		Enum.Material.Wood
	)
	bit(
		b,
		"Cleaver",
		Vector3.new(1.1, 0.06, 0.5),
		Vector3.new(-length / 4 + 0.2, 3.5, 0.1),
		rgb(200, 200, 205),
		Enum.Material.Metal
	)
	for i = 0, 3 do
		ball(
			bit(
				b,
				"Apple",
				Vector3.one * 0.45,
				Vector3.new(length / 4 + (i % 2) * 0.4, 3.52 + (i // 2) * 0.35, (i // 2) * 0.2),
				rgb(200, 30, 30)
			)
		)
	end
	local stools = math.floor(length / 3)
	for i = 1, stools do
		local sx = -length / 2 + (i - 0.5) * length / stools
		local s = b * CFrame.new(sx, 0, -3)
		cylinder(
			piece(
				s,
				"Stool",
				Vector3.new(1.5, 0.3, 1.5),
				Vector3.new(0, 2.6, 0),
				rgb(40, 40, 42),
				Enum.Material.Leather
			),
			"Y"
		)
		cylinder(
			bit(s, "StoolLeg", Vector3.new(0.3, 2.5, 0.3), Vector3.new(0, 1.25, 0), STEEL, Enum.Material.Metal),
			"Y"
		)
		cylinder(
			bit(s, "StoolFoot", Vector3.new(1.2, 0.12, 1.2), Vector3.new(0, 0.06, 0), STEEL, Enum.Material.Metal),
			"Y"
		)
	end
end

function Kit.chinaCabinet(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	piece(b, "Cabinet", Vector3.new(6, 3.4, 2.2), Vector3.new(0, 1.7, 0), DARK_WOOD, Enum.Material.Wood)
	piece(b, "Hutch", Vector3.new(5.6, 6, 1.4), Vector3.new(0, 6.4, 0.4), DARK_WOOD, Enum.Material.Wood)
	local glass =
		bit(b, "Glass", Vector3.new(5, 5.4, 0.06), Vector3.new(0, 6.4, -0.32), rgb(210, 230, 240), Enum.Material.Glass)
	glass.Transparency = 0.6
	for row = 0, 2 do
		bit(b, "ShelfBoard", Vector3.new(5, 0.1, 1), Vector3.new(0, 4.4 + row * 1.8, 0.3), darker(DARK_WOOD, 0.2))
		for i = 0, 3 do
			cylinder(
				bit(
					b,
					"Plate",
					Vector3.new(1, 1, 0.08),
					Vector3.new(-1.8 + i * 1.2, 5 + row * 1.8, 0.75),
					rgb(245, 245, 250)
				),
				"Z"
			)
		end
	end
	for _, sx in { -1.5, 1.5 } do
		bit(
			b,
			"CabinetDoor",
			Vector3.new(2.7, 2.6, 0.06),
			Vector3.new(sx, 1.7, -1.13),
			darker(DARK_WOOD, 0.1),
			Enum.Material.Wood
		)
	end
end

function Kit.grandfatherClock(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	piece(b, "ClockCase", Vector3.new(2.4, 8, 1.6), Vector3.new(0, 4, 0), DARK_WOOD, Enum.Material.Wood)
	bit(b, "ClockHood", Vector3.new(2.8, 0.6, 1.9), Vector3.new(0, 8.3, 0), darker(DARK_WOOD, 0.15), Enum.Material.Wood)
	local glass = bit(
		b,
		"PendulumWindow",
		Vector3.new(1.4, 3.4, 0.06),
		Vector3.new(0, 3.6, -0.82),
		rgb(40, 30, 20),
		Enum.Material.Glass
	)
	glass.Transparency = 0.2
	bit(
		b,
		"PendulumRod",
		Vector3.new(0.08, 2.4, 0.06),
		Vector3.new(0, 4, -0.75),
		rgb(212, 175, 80),
		Enum.Material.Metal
	)
	cylinder(
		bit(
			b,
			"PendulumBob",
			Vector3.new(0.7, 0.7, 0.08),
			Vector3.new(0, 2.8, -0.75),
			rgb(212, 175, 80),
			Enum.Material.Metal
		),
		"Z"
	)
	-- the face (its hands turn like every other clock)
	local faceAt = b * CFrame.new(0, 6.7, -0.8)
	local p = faceAt.Position - origin
	local look = faceAt.LookVector
	local rot = math.deg(math.atan2(-look.X, -look.Z))
	Kit.clock(p.X, p.Y, p.Z, rot, rgb(245, 235, 210), rgb(212, 175, 80))
end

-- A suit of armour standing guard, halberd in hand
function Kit.armor(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	local steel = rgb(160, 165, 175)
	piece(b, "ArmorStand", Vector3.new(2.6, 0.6, 2.6), Vector3.new(0, 0.3, 0), rgb(60, 55, 50), Enum.Material.Slate)
	for _, sx in { -0.5, 0.5 } do
		bit(b, "ArmorLeg", Vector3.new(0.8, 3, 0.9), Vector3.new(sx, 2.1, 0), steel, Enum.Material.Metal)
		bit(
			b,
			"ArmorBoot",
			Vector3.new(0.9, 0.5, 1.4),
			Vector3.new(sx, 0.85, -0.2),
			darker(steel, 0.2),
			Enum.Material.Metal
		)
	end
	piece(b, "ArmorTorso", Vector3.new(2.1, 2.6, 1.2), Vector3.new(0, 4.9, 0), steel, Enum.Material.Metal)
	bit(b, "ArmorBelt", Vector3.new(2.2, 0.35, 1.3), Vector3.new(0, 3.75, 0), rgb(80, 50, 30), Enum.Material.Leather)
	for _, sx in { -1.4, 1.4 } do
		ball(
			bit(
				b,
				"Pauldron",
				Vector3.new(1.1, 0.9, 1.3),
				Vector3.new(sx, 6, 0),
				darker(steel, 0.1),
				Enum.Material.Metal
			)
		)
		bit(b, "ArmorArm", Vector3.new(0.7, 2.6, 0.8), Vector3.new(sx, 4.5, 0), steel, Enum.Material.Metal)
	end
	bit(b, "Helmet", Vector3.new(1.2, 1.4, 1.3), Vector3.new(0, 6.95, 0), steel, Enum.Material.Metal)
	bit(b, "Visor", Vector3.new(1.0, 0.12, 0.1), Vector3.new(0, 7, -0.66), rgb(15, 15, 15))
	bit(b, "Plume", Vector3.new(0.25, 1, 1.2), Vector3.new(0, 7.9, 0.2), rgb(150, 20, 30), Enum.Material.Fabric)
	bit(b, "Halberd", Vector3.new(0.15, 9.5, 0.15), Vector3.new(1.4, 4.9, -0.6), DARK_WOOD, Enum.Material.Wood)
	bit(b, "HalberdBlade", Vector3.new(0.08, 1.4, 1), Vector3.new(1.4, 9.4, -0.9), steel, Enum.Material.Metal)
end

function Kit.piano(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	local black = rgb(18, 18, 20)
	piece(b, "Piano", Vector3.new(6, 1.6, 5), Vector3.new(0, 3.4, 0.6), black, Enum.Material.Glass)
	piece(b, "PianoLid", Vector3.new(5.8, 0.15, 4.6), Vector3.new(0, 5.6, 1.4), black, Enum.Material.Glass).CFrame = b
		* CFrame.new(0, 5.2, 1.4)
		* CFrame.Angles(math.rad(25), 0, 0)
	bit(b, "LidProp", Vector3.new(0.1, 1.6, 0.1), Vector3.new(2.6, 4.9, 0.4), black)
	bit(b, "Keys", Vector3.new(5.4, 0.15, 1), Vector3.new(0, 3.1, -2.2), rgb(250, 250, 245))
	for i = 0, 13 do
		if i % 7 ~= 2 and i % 7 ~= 6 then
			bit(b, "BlackKey", Vector3.new(0.2, 0.1, 0.6), Vector3.new(-2.55 + i * 0.39, 3.22, -2.0), black)
		end
	end
	bit(b, "Fallboard", Vector3.new(5.6, 0.8, 0.2), Vector3.new(0, 3.6, -1.75), black)
	bit(b, "SheetMusic", Vector3.new(1.6, 1.1, 0.05), Vector3.new(0, 4.3, -1.6), rgb(245, 240, 225)).CFrame = b
		* CFrame.new(0, 4.3, -1.6)
		* CFrame.Angles(math.rad(-15), 0, 0)
	for _, sx in { -2.6, 2.6 } do
		bit(b, "PianoLeg", Vector3.new(0.5, 2.6, 0.5), Vector3.new(sx, 1.3, -1.4), black)
	end
	bit(b, "PianoLeg", Vector3.new(0.5, 2.6, 0.5), Vector3.new(0, 1.3, 2.8), black)
	-- bench
	piece(b, "PianoBench", Vector3.new(3.2, 0.5, 1.4), Vector3.new(0, 2, -3.6), black, Enum.Material.Leather)
	for _, sx in { -1.3, 1.3 } do
		bit(b, "BenchLeg", Vector3.new(0.3, 1.8, 1.2), Vector3.new(sx, 0.9, -3.6), black)
	end
end

function Kit.globe(x: number, z: number)
	local b = frame(x, z, 0)
	cylinder(
		bit(b, "GlobeStand", Vector3.new(1.8, 0.3, 1.8), Vector3.new(0, 0.15, 0), DARK_WOOD, Enum.Material.Wood),
		"Y"
	)
	bit(b, "GlobePole", Vector3.new(0.2, 2.6, 0.2), Vector3.new(0, 1.5, 0), DARK_WOOD, Enum.Material.Wood)
	local globe = ball(piece(b, "Globe", Vector3.one * 2, Vector3.new(0, 3.6, 0), rgb(70, 120, 180)))
	globe.CFrame = globe.CFrame * CFrame.Angles(0, 0, math.rad(23))
	ball(
		bit(
			b,
			"Continent",
			Vector3.new(0.9, 1, 0.9),
			Vector3.new(0.45, 3.8, -0.4),
			rgb(90, 150, 80),
			Enum.Material.Grass
		)
	)
	ball(
		bit(
			b,
			"Continent",
			Vector3.new(0.8, 0.7, 0.8),
			Vector3.new(-0.5, 3.3, 0.45),
			rgb(170, 150, 90),
			Enum.Material.Sand
		)
	)
	bit(b, "Meridian", Vector3.new(0.12, 2.4, 2.4), Vector3.new(0, 3.6, 0), rgb(212, 175, 80), Enum.Material.Metal).CFrame = b
		* CFrame.new(0, 3.6, 0)
		* CFrame.Angles(0, math.rad(90), math.rad(23))
end

function Kit.sideTable(x: number, z: number, withLamp: boolean?)
	local b = frame(x, z, 0)
	cylinder(piece(b, "SideTable", Vector3.new(2, 0.2, 2), Vector3.new(0, 2.6, 0), DARK_WOOD, Enum.Material.Wood), "Y")
	cylinder(
		bit(b, "SideTableLeg", Vector3.new(0.3, 2.5, 0.3), Vector3.new(0, 1.3, 0), DARK_WOOD, Enum.Material.Wood),
		"Y"
	)
	if withLamp then
		cylinder(
			bit(
				b,
				"LampBase",
				Vector3.new(0.4, 1.1, 0.4),
				Vector3.new(0, 3.25, 0),
				rgb(212, 175, 80),
				Enum.Material.Metal
			),
			"Y"
		)
		local shade = cylinder(
			bit(
				b,
				"LampShade",
				Vector3.new(1.3, 0.9, 1.3),
				Vector3.new(0, 4.2, 0),
				rgb(150, 30, 40),
				Enum.Material.Fabric
			),
			"Y"
		)
		light(shade, rgb(255, 180, 120), 12, 0.55)
	else
		candelabra(b, 2.7)
	end
end

-- Fireplace with a stone surround, a mantel, a crackling fire and a portrait above it
function Kit.fireplace(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	local stone = rgb(150, 145, 140)
	piece(b, "Fireplace", Vector3.new(12, 8, 3), Vector3.new(0, 4, 0), stone, Enum.Material.Brick)
	piece(
		b,
		"Chimney",
		Vector3.new(9, WALL_HEIGHT - 8, 2.2),
		Vector3.new(0, 8 + (WALL_HEIGHT - 8) / 2, 0.4),
		darker(stone, 0.1),
		Enum.Material.Brick
	)
	piece(b, "Mantel", Vector3.new(13, 0.6, 3.8), Vector3.new(0, 8.1, -0.3), DARK_WOOD, Enum.Material.Wood)
	piece(b, "Hearth", Vector3.new(13, 0.3, 2.4), Vector3.new(0, 0.15, -2.6), darker(stone, 0.3), Enum.Material.Slate)
	bit(b, "FireHole", Vector3.new(6, 4.4, 1.2), Vector3.new(0, 2.2, -1.1), rgb(20, 15, 15))
	bit(b, "Arch", Vector3.new(7, 0.8, 0.4), Vector3.new(0, 4.6, -1.6), darker(stone, 0.2), Enum.Material.Brick)
	for i, sx in { -0.9, 0.9 } do
		cylinder(
			bit(
				b,
				"Log",
				Vector3.new(3, 0.6, 0.6),
				Vector3.new(sx * 0.3, 0.6 + i * 0.25, -1.2),
				rgb(80, 50, 30),
				Enum.Material.Wood
			)
		).CFrame = b
			* CFrame.new(sx * 0.3, 0.6 + (i - 1) * 0.35, -1.2)
			* CFrame.Angles(0, sx * 0.3, 0)
	end
	local fire =
		bit(b, "Fire", Vector3.new(3.2, 1.6, 0.6), Vector3.new(0, 1.4, -1.3), rgb(255, 140, 30), Enum.Material.Neon)
	fire.Transparency = 0.3
	local flames = Instance.new("ParticleEmitter")
	flames.Texture = Textures.Fire
	flames.Color = ColorSequence.new(rgb(255, 180, 60), rgb(255, 70, 20))
	flames.LightEmission = 1
	flames.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0.2) })
	flames.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	flames.Lifetime = NumberRange.new(0.5, 0.9)
	flames.Rate = 30
	flames.Speed = NumberRange.new(2, 3.5)
	flames.SpreadAngle = Vector2.new(15, 15)
	flames.EmissionDirection = Enum.NormalId.Top
	flames.Parent = fire
	local embers = Instance.new("ParticleEmitter")
	embers.Color = ColorSequence.new(rgb(255, 150, 50))
	embers.LightEmission = 1
	embers.Size = NumberSequence.new(0.12, 0)
	embers.Lifetime = NumberRange.new(1, 2)
	embers.Rate = 6
	embers.Speed = NumberRange.new(2, 4)
	embers.SpreadAngle = Vector2.new(30, 30)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Parent = fire
	light(fire, rgb(255, 140, 60), 28, 1.1)
	flame(fire)
	-- mantel clutter
	candelabra(b * CFrame.new(-4.8, 0, -0.6), 8.4)
	candelabra(b * CFrame.new(4.8, 0, -0.6), 8.4)
	local skull = solidProp("Skull")
	skull:PivotTo(b * CFrame.new(-2.2, 9.05, -0.8) * CFrame.Angles(0, math.rad(20), 0))
	skull:ScaleTo(0.6)
	skull.Parent = folder
	cylinder(
		bit(b, "Urn", Vector3.new(0.9, 1.4, 0.9), Vector3.new(2.4, 9.1, -0.6), rgb(40, 60, 70), Enum.Material.Marble),
		"Y"
	)
	-- portrait on the chimney breast
	local p = (b * CFrame.new(0, 11, -0.72)).Position - origin
	Kit.picture(p.X, p.Y, p.Z, rotation, "Portrait", rgb(212, 175, 80), 1.1)
	-- poker set
	bit(b, "Poker", Vector3.new(0.12, 3, 0.12), Vector3.new(6.8, 1.6, -2.4), rgb(30, 30, 30), Enum.Material.Metal)
	bit(b, "PokerStand", Vector3.new(0.8, 0.15, 0.8), Vector3.new(6.8, 0.1, -2.4), rgb(30, 30, 30), Enum.Material.Metal)
end

-- Grand double doors with a fanlight (decor on a solid outer wall)
function Kit.frontDoors(x: number, z: number, rotation: number)
	local b = frame(x, z, rotation)
	local wood = rgb(60, 30, 20)
	bit(b, "DoorFrame", Vector3.new(10.4, 12.6, 0.6), Vector3.new(0, 6.3, -0.3), rgb(240, 235, 225))
	for _, sx in { -2.3, 2.3 } do
		bit(b, "FrontDoor", Vector3.new(4.4, 9.6, 0.3), Vector3.new(sx, 4.8, -0.7), wood, Enum.Material.Wood)
		for _, y in { 2.4, 6.8 } do
			bit(
				b,
				"DoorPanel",
				Vector3.new(3, 3.2, 0.12),
				Vector3.new(sx, y, -0.9),
				darker(wood, 0.25),
				Enum.Material.Wood
			)
		end
		ball(
			bit(
				b,
				"Knocker",
				Vector3.new(0.8, 0.8, 0.15),
				Vector3.new(sx, 5.2, -0.95),
				rgb(212, 175, 80),
				Enum.Material.Metal
			)
		)
	end
	local fan =
		bit(b, "Window", Vector3.new(9, 2.4, 0.1), Vector3.new(0, 10.9, -0.65), rgb(16, 24, 48), Enum.Material.Neon)
	fan:AddTag("Window")
	for i = -2, 2 do
		bit(b, "FanBar", Vector3.new(0.15, 2.4, 0.15), Vector3.new(i * 1.8, 10.9, -0.75), rgb(240, 235, 225))
	end
	local mat =
		bit(b, "Mat", Vector3.new(6, 0.1, 3), Vector3.new(0, 0.12, -2.6), rgb(110, 30, 30), Enum.Material.Fabric)
	label(mat, "WELCOME", rgb(230, 200, 140), Enum.Font.Garamond, Enum.NormalId.Top)
end

function Kit.coatRack(x: number, z: number)
	local b = frame(x, z, 0)
	cylinder(
		bit(b, "RackBase", Vector3.new(1.6, 0.25, 1.6), Vector3.new(0, 0.12, 0), DARK_WOOD, Enum.Material.Wood),
		"Y"
	)
	cylinder(
		piece(b, "RackPole", Vector3.new(0.3, 6.5, 0.3), Vector3.new(0, 3.3, 0), DARK_WOOD, Enum.Material.Wood),
		"Y"
	)
	bit(b, "Coat", Vector3.new(1.6, 3.2, 0.8), Vector3.new(0, 4.4, -0.4), rgb(40, 40, 50), Enum.Material.Fabric)
	bit(b, "Hat", Vector3.new(1.3, 0.7, 1.3), Vector3.new(0.4, 6.8, 0.2), rgb(25, 25, 28), Enum.Material.Fabric)
	bit(b, "Scarf", Vector3.new(0.4, 2.4, 0.3), Vector3.new(0.5, 4.8, 0.4), rgb(150, 30, 40), Enum.Material.Fabric)
end

return Kit
