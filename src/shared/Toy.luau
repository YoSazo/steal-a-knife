--!strict
-- The toy look (Steal An Egg style): saturated flat colours covered in small classic studs, with a
-- two-tone checker every few studs. Both are tinted by the part's own colour, so one call dresses
-- any floor or wall. Textures are per face, so only dress the faces people see.
-- Every boundary wall in the hub uses the same DirtWall (tan dirt + studs + a grass cap), so the
-- vault area and the runway read as one place.

local Textures = require(script.Parent.Config.Textures)

local Toy = {}

-- Matched to how Steal An Egg renders (their grass ~(78,203,47), dirt ~(196,139,87) on screen)
Toy.Grass = Color3.fromRGB(48, 146, 30)
Toy.Dirt = Color3.fromRGB(214, 146, 78)

local function texture(part: BasePart, face: Enum.NormalId, id: string, tile: number, name: string): Texture
	local t = Instance.new("Texture")
	t.Name = name
	t.Texture = id
	t.Face = face
	t.StudsPerTileU = tile
	t.StudsPerTileV = tile
	t.Parent = part
	return t
end

-- studSize: studs per stud (default 1); checker: studs per checker square (0 = none)
function Toy.Dress(part: BasePart, faces: { Enum.NormalId }?, studSize: number?, checker: number?)
	part.Material = Enum.Material.SmoothPlastic
	local square = checker or 8
	local list: { Enum.NormalId } = faces or { Enum.NormalId.Top }
	for _, face in list do
		-- The stud image holds 2x2 studs
		texture(part, face, Textures.Toy.Stud, (studSize or 1) * 2, "Studs")
		if square > 0 then
			-- The checker image holds 2x2 squares
			-- Faint, like Steal An Egg's: the two shades blend rather than stand out
			texture(part, face, Textures.Toy.Checker, square * 2, "Checker").Transparency = 0.55
		end
	end
end

-- Every face but the bottom (walls you can see from both sides, posts)
Toy.Sides = {
	Enum.NormalId.Top,
	Enum.NormalId.Front,
	Enum.NormalId.Back,
	Enum.NormalId.Left,
	Enum.NormalId.Right,
}

-- The hub's one wall style: studded tan dirt in a checker with a strip of grass along the top.
-- Expects an axis-aligned (unrotated or 90-degree-turned) wall.
function Toy.DirtWall(part: BasePart, color: Color3?): Part
	part.Color = color or Toy.Dirt
	part.CastShadow = false -- 170 studs tall: its shadow would cover half the arena
	Toy.Dress(part, {
		Enum.NormalId.Front,
		Enum.NormalId.Back,
		Enum.NormalId.Left,
		Enum.NormalId.Right,
	}, 1, 4)
	local cap = Instance.new("Part")
	cap.Name = "GrassCap"
	cap.Anchored = true
	cap.CanCollide = false
	cap.CanQuery = false
	cap.CanTouch = false
	cap.Size = Vector3.new(part.Size.X + 0.8, 1.6, part.Size.Z + 0.8)
	cap.CFrame = part.CFrame * CFrame.new(0, part.Size.Y / 2 + 0.5, 0)
	cap.Color = Toy.Grass
	cap.CastShadow = false
	cap.TopSurface = Enum.SurfaceType.Smooth
	cap.BottomSurface = Enum.SurfaceType.Smooth
	cap.Parent = part.Parent
	Toy.Dress(cap, Toy.Sides, 1, 0)
	return cap
end

return Toy
