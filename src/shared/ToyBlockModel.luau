--!strict
-- Individual cuboids shared by the game and the Blender review exports.
local Geometry = require(script.Parent.Config.ToyGeometryData)

local ToyBlockModel = {}

function ToyBlockModel.Build(name: string, anchored: boolean?, rootName: string?): Model
	local specs = Geometry[name]
	assert(specs, `No block design for {name}`)
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = rootName or "Root"
	root.Size = Vector3.one * 0.2
	root.Transparency = 1
	root.Anchored = anchored == true
	root.CanCollide, root.CanQuery, root.CanTouch = false, false, false
	root.Parent = model
	model.PrimaryPart = root
	model:SetAttribute("ToyBlockDesign", name)
	for _, spec in specs do
		local p = Instance.new("Part")
		p.Name = spec.Name
		p.Size = spec.Size
		p.CFrame = CFrame.new(spec.Offset) * CFrame.Angles(0, 0, math.rad(spec.Angle or 0))
		p.Color = spec.Color
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Anchored = anchored == true
		p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
		p.Massless = true
		p.CastShadow = false
		p:SetAttribute("ToyBlock", true)
		if spec.Role then
			p:SetAttribute("KnifeRole", spec.Role)
			if name == "NightWhisper" then
				p.Color = if spec.Neon then Color3.fromRGB(220, 255, 235) else Color3.fromRGB(20, 30, 30)
			end
		end
		p.Parent = model
		if not anchored then
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = root, p
			weld.Parent = p
		end
	end
	return model
end

return ToyBlockModel
