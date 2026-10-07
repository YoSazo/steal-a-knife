--!strict
-- Solid round-map artwork only. Layout, spawns and the stair Ramp remain in RoundMapKit.
local AssetService = game:GetService("AssetService")
local Geometry = require(script.Parent.Parent.Config.ToyGeometry.RoundMapArt)
local Meshes = require(script.Parent.Parent.Config.RoundMapArtMeshes)
local Art = {}
local templates: { [string]: Model } = {}
local loading = false
local ready = false

local function root(model: Model): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.Transparency = "Origin", Vector3.one * 0.05, 1
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.Parent = model
	model.PrimaryPart = p
	return p
end

function Art.Preload()
	if loading then
		while not ready do
			task.wait()
		end
		return
	end
	loading = true
	for name, specs in Meshes do
		local model = Instance.new("Model")
		model.Name = name
		root(model)
		local ok = pcall(function()
			for _, spec in specs do
				local mesh = AssetService:CreateMeshPartAsync(Content.fromUri(spec.MeshId), {
					CollisionFidelity = Enum.CollisionFidelity.Hull,
				})
				mesh.Name, mesh.Size, mesh.CFrame = spec.Name, spec.Size, CFrame.new(spec.Offset)
				mesh.Color = spec.Color
				mesh.Material = Enum.Material.SmoothPlastic
				mesh.Anchored, mesh.CanCollide, mesh.CanTouch, mesh.CanQuery = true, true, false, false
				mesh.Parent = model
			end
		end)
		if ok then
			templates[name] = model
		else
			model:Destroy() -- the matching solid native fallback is always available
		end
	end
	ready = true
end

function Art.Build(name: string, parent: Instance?, frame: CFrame?): Model
	local rows = Geometry[name]
	assert(rows, `Unknown round-map artwork {name}`)
	local template = templates[name]
	local model = if template then template:Clone() else Instance.new("Model")
	model.Name = `RoundArt_{name}`
	if not template then
		root(model)
		for _, spec in rows do
			local p = Instance.new("Part")
			p.Name, p.Size, p.CFrame = spec.Name, spec.Size, CFrame.new(spec.Offset)
			if spec.Rotation then
				p.CFrame *= CFrame.Angles(
					math.rad(spec.Rotation.X),
					math.rad(spec.Rotation.Y),
					math.rad(spec.Rotation.Z)
				)
			end
			if spec.Shape == "Cylinder" then
				p.Shape = Enum.PartType.Cylinder
				p.Size = Vector3.new(p.Size.Y, p.Size.X, p.Size.Z)
				p.CFrame *= CFrame.Angles(0, 0, math.pi / 2)
			end
			p.Color = spec.Color
			p.Material = if spec.Neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
			p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, true, false, false
			p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
			p.Parent = model
		end
	end
	model:SetAttribute("RoundMapArtwork", name)
	model:PivotTo(frame or CFrame.identity)
	model.Parent = parent
	return model
end

return Art
