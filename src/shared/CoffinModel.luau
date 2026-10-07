--!strict
-- The coffin a stolen knife waits in on its plate (CoffinService / BaseService.RefreshRack).
-- STAND-IN blocks until Codex's art lands (Config/ToyGeometry/Coffin_<Rarity>, see
-- docs/KNIFE_CHARACTERS_BRIEF.md): the same contract either way - parts named/role "Lid" swing
-- open, "Glow" pulses, two "Peek" eyes sit at the crack (client/Coffins rattles and animates it).
-- Bigger and brighter by rarity: a Common is a shoebox, a Cosmic a glowing monument.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knives = require(ReplicatedStorage.Shared.Config.Knives)

local CoffinModel = {}

-- Length in studs by rarity (Common 3 ... Cosmic 8)
function CoffinModel.Length(rarity: string): number
	local rank = table.find(Knives.Rarities, rarity) or 1
	return 3 + (rank - 1) * (5 / 7) -- (3 .. 8: it has to fit its plate; the pen makes room for huge ones)
end

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, neon: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- A coffin lying on the plate at `at` (its bottom centre), long side along local Z, face up
function CoffinModel.Build(rarity: string, at: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Coffin"
	model:SetAttribute("Rarity", rarity)
	local color = Knives.RarityColors[rarity] or Color3.fromRGB(200, 200, 200)
	local length = CoffinModel.Length(rarity)
	local width = length * 0.42
	local height = length * 0.22
	local wood = color:Lerp(Color3.fromRGB(70, 45, 35), 0.45)
	local body = part(model, "Body", Vector3.new(width, height, length), at * CFrame.new(0, height / 2, 0), wood)
	-- (the classic coffin shape: wider at the shoulders)
	part(
		model,
		"Shoulders",
		Vector3.new(width * 1.18, height * 0.98, length * 0.3),
		at * CFrame.new(0, height / 2, -length * 0.18),
		wood
	)
	local lidY = height + height * 0.12
	local lid =
		part(model, "Lid", Vector3.new(width * 1.06, height * 0.24, length * 1.02), at * CFrame.new(0, lidY, 0), color)
	lid:SetAttribute("Role", "Lid")
	local cross = part(
		model,
		"LidCross",
		Vector3.new(width * 0.16, height * 0.08, length * 0.55),
		at * CFrame.new(0, lidY + height * 0.16, -length * 0.05),
		Color3.new(1, 1, 1),
		true
	)
	cross:SetAttribute("Role", "Lid")
	part(
		model,
		"LidCrossBar",
		Vector3.new(width * 0.6, height * 0.08, length * 0.12),
		at * CFrame.new(0, lidY + height * 0.16, -length * 0.18),
		Color3.new(1, 1, 1),
		true
	):SetAttribute("Role", "Lid")
	-- the glowing seam all round, and two eyes peeking out of the crack at the head end
	local glow = part(
		model,
		"Seam",
		Vector3.new(width * 1.08, height * 0.06, length * 1.04),
		at * CFrame.new(0, height + 0.01, 0),
		color,
		true
	)
	glow:SetAttribute("Role", "Glow")
	for side = -1, 1, 2 do
		local eye = part(
			model,
			"Peek",
			Vector3.new(width * 0.12, height * 0.1, width * 0.12),
			at * CFrame.new(side * width * 0.16, height + 0.02, -length * 0.5 - 0.02),
			Color3.fromRGB(255, 255, 210),
			true
		)
		eye:SetAttribute("Role", "Peek")
	end
	model.PrimaryPart = body
	return model
end

return CoffinModel
