--!strict
-- Part-built Revolver: the floating pickup that drops into the round, and the Tool an innocent
-- holds after grabbing it. Firing is handled by RoundService (Remotes.Shoot).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)

local Revolver = {}

local METAL = Color3.fromRGB(70, 72, 80)
local GRIP = Color3.fromRGB(110, 65, 35)

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Parent = parent
	return p
end

-- Grip along +Y at the origin, barrel pointing towards -Z (the direction a Tool faces)
local function assemble(parent: Instance): BasePart
	local handle = part(
		parent,
		"Handle",
		Vector3.new(0.35, 1.1, 0.55),
		CFrame.Angles(math.rad(-15), 0, 0),
		GRIP,
		Enum.Material.Wood
	)
	part(parent, "Frame", Vector3.new(0.4, 0.55, 1.1), CFrame.new(0, 0.7, -0.3), METAL, Enum.Material.Metal)
	local cylinder = part(
		parent,
		"Cylinder",
		Vector3.new(0.7, 0.62, 0.62),
		CFrame.new(0, 0.72, -0.45) * CFrame.Angles(0, math.rad(90), 0),
		METAL:Lerp(Color3.new(1, 1, 1), 0.2),
		Enum.Material.Metal
	)
	cylinder.Shape = Enum.PartType.Cylinder
	local barrel = part(
		parent,
		"Barrel",
		Vector3.new(1.5, 0.28, 0.28),
		CFrame.new(0, 0.85, -1.4) * CFrame.Angles(0, math.rad(90), 0),
		METAL,
		Enum.Material.Metal
	)
	barrel.Shape = Enum.PartType.Cylinder
	part(parent, "Hammer", Vector3.new(0.15, 0.3, 0.2), CFrame.new(0, 1.05, 0.25), METAL)
	part(parent, "Muzzle", Vector3.new(0.1, 0.1, 0.1), CFrame.new(0, 0.85, -2.2), METAL).Transparency = 1
	for _, child in parent:GetChildren() do
		if child:IsA("BasePart") and child ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = child
			weld.Parent = child
		end
	end
	return handle
end

function Revolver.BuildTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Revolver"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.GripPos = Vector3.new(0, -0.2, 0)
	tool.GripForward = Vector3.new(0, 0, -1)
	tool.GripUp = Vector3.new(0, 1, 0)
	tool.GripRight = Vector3.new(1, 0, 0)
	tool:SetAttribute("Revolver", true)
	local handle = assemble(tool)
	handle.Massless = false
	local sound = Instance.new("Sound")
	sound.Name = "Shot"
	sound.SoundId = Sounds.Gunshot
	sound.Volume = 1
	sound.Parent = handle
	return tool
end

-- The pickup: anchored, glowing, with sparkles so everyone knows where it is
function Revolver.BuildPickup(position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "RevolverPickup"
	local handle = assemble(model)
	model.PrimaryPart = handle
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
		end
	end
	model:ScaleTo(1.6)
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)))
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = Color3.fromRGB(80, 255, 120)
	sparkles.Parent = handle
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(80, 255, 120)
	light.Range = 12
	light.Parent = handle
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(80, 255, 120)
	highlight.FillTransparency = 0.6
	highlight.OutlineColor = Color3.fromRGB(200, 255, 210)
	highlight.Parent = model
	-- A plain part that people touch to pick it up (the gun itself doesn't take touches)
	local zone = Instance.new("Part")
	zone.Name = "PickupZone"
	zone.Size = Vector3.new(5, 6, 5)
	zone.CFrame = CFrame.new(position)
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.Transparency = 1
	zone.Parent = model
	model:AddTag("Spin")
	return model
end

return Revolver
