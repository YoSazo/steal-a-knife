--!strict
-- Builds knives out of plain Parts (bright, low-poly). Once the Blender meshes are uploaded this is
-- the one place to swap in MeshParts. The knife stands along +Y from a grip at the origin.

local Knives = require(script.Parent.Config.Knives)

local KnifeModel = {}

local function part(parent: Instance, name: string, size: Vector3, offset: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = offset
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Parent = parent
	return p
end

local function assemble(parent: Instance, knife: Knives.Knife): BasePart
	local length, width = knife.BladeLength, knife.BladeWidth
	local handle = part(parent, "Handle", Vector3.new(0.35, 1.1, 0.35), CFrame.new(), knife.HandleColor)
	local pommel = part(parent, "Pommel", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, -0.65, 0), knife.GuardColor)
	pommel.Shape = Enum.PartType.Ball
	part(parent, "Guard", Vector3.new(0.3, 0.2, width + 0.6), CFrame.new(0, 0.65, 0), knife.GuardColor)
	local blade = part(
		parent,
		"Blade",
		Vector3.new(0.12, length * 0.8, width),
		CFrame.new(0, 0.75 + length * 0.4, 0),
		knife.BladeColor
	)

	local tip = Instance.new("WedgePart")
	tip.Name = "Tip"
	tip.Size = Vector3.new(0.12, length * 0.25, width)
	tip.CFrame = CFrame.new(0, 0.75 + length * 0.8 + length * 0.125, 0)
	tip.Color = knife.BladeColor
	tip.CanCollide, tip.CanQuery, tip.CanTouch, tip.Massless = false, false, false, true
	tip.Parent = parent

	if knife.Neon then
		blade.Material = Enum.Material.Neon
		tip.Material = Enum.Material.Neon
		local light = Instance.new("PointLight")
		light.Color = knife.BladeColor
		light.Range = 10
		light.Parent = blade
	end

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

-- Static display model (pedestals, racks, carried over the head)
function KnifeModel.Build(name: string, anchored: boolean?): Model
	local knife = Knives.ByName[name]
	assert(knife, `unknown knife {name}`)
	local model = Instance.new("Model")
	model.Name = name
	local handle = assemble(model, knife)
	handle.Massless = false
	model.PrimaryPart = handle
	if anchored then
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = true
			end
		end
	end
	return model
end

-- Tool version, used as the Murderer's weapon
function KnifeModel.BuildTool(name: string): Tool
	local knife = Knives.ByName[name]
	assert(knife, `unknown knife {name}`)
	local tool = Instance.new("Tool")
	tool.Name = knife.DisplayName
	tool.CanBeDropped = false
	tool.GripForward = Vector3.new(-1, 0, 0)
	tool.GripRight = Vector3.new(0, 1, 0)
	tool.GripUp = Vector3.new(0, 0, 1)
	tool.GripPos = Vector3.new(0, 0, -0.1)
	local handle = assemble(tool, knife)
	handle.Massless = false
	return tool
end

return KnifeModel
