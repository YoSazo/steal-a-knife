--!strict
-- Sparse early-biome artwork. Gameplay floors, lairs and collision belong to MapService/GuardService.
local CollectionService = game:GetService("CollectionService")
local Textures = require(script.Parent.Parent.Config.Textures)
type Block = {
	Name: string,
	Size: { number },
	Offset: { number },
	Color: { number },
	Detail: boolean?,
	Stud: boolean?,
	WaterFace: string?,
	Ambient: boolean?,
	Hidden: boolean?,
	Neon: boolean?,
	ProfileSource: string?,
}
type Data = { Name: string, BiomeIndex: number, Depth: number, Origin: { number }, Groups: { [string]: { Block } } }
export type Options = { Detail: boolean?, WaterTexture: string?, Ambient: boolean? }
local Shell = {}
local function vec(v: { number }): Vector3
	return Vector3.new(v[1], v[2], v[3])
end
local function pivot(name: string, cf: CFrame, parent: Model): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Transparency = name, Vector3.one * 0.1, cf, 1
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p:SetAttribute("BiomeShellPivot", true)
	p.Parent = parent
	return p
end
function Shell.Build(data: Data, parent: Instance?, origin: CFrame?, options: Options?): Model
	local frame = origin or CFrame.new(vec(data.Origin))
	local settings: Options = options or {}
	local model = Instance.new("Model")
	model.Name = data.Name
	model.PrimaryPart = pivot("Origin", frame, model)
	model:SetAttribute("BiomeIndex", data.BiomeIndex)
	model:SetAttribute("Zone", data.BiomeIndex)
	model:SetAttribute("Boss", if data.BiomeIndex == 1 then "Frank" else "Ivy")
	model:SetAttribute("BossTitle", if data.BiomeIndex == 1 then "The Groundskeeper" else "The Gardener")
	model:SetAttribute("FrontAxis", "-Z; +Z goes deeper")
	model:SetAttribute("GroundWidth", 160)
	model:SetAttribute("GroundDepth", data.Depth)
	CollectionService:AddTag(model, "BiomeShell")
	local count = 1
	for name, rows in data.Groups do
		local group = Instance.new("Model")
		group.Name, group.ModelStreamingMode = name, Enum.ModelStreamingMode.Atomic
		group:SetAttribute("BiomeShellGroup", true)
		group.Parent = model
		group.PrimaryPart = pivot("GroupOrigin", frame, group)
		count += 1
		for _, spec in rows do
			if spec.Detail and settings.Detail == false then
				continue
			end
			local p = Instance.new("Part")
			p.Name, p.Size, p.CFrame = spec.Name, vec(spec.Size), frame * CFrame.new(vec(spec.Offset))
			p.Color = Color3.fromRGB(spec.Color[1], spec.Color[2], spec.Color[3])
			p.Material = Enum.Material.SmoothPlastic
			p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
			p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
			p:SetAttribute("BiomeShellPart", true)
			p.Parent = group
			count += 1
			if spec.Detail then
				p:SetAttribute("MapDetail", true)
				CollectionService:AddTag(p, "BiomeFarDetail")
			end
			if spec.Stud then
				local texture = Instance.new("Texture")
				texture.Name, texture.Texture, texture.Face = "ToyStuds", Textures.Toy.Stud, Enum.NormalId.Top
				texture.StudsPerTileU, texture.StudsPerTileV, texture.Transparency = 2, 2, 0.45
				texture.Parent = p
			end
		end
	end
	model:SetAttribute("PartCount", count)
	model.Parent = parent
	return model
end
-- Early ponds stay still: no emitters, light sources, neon or flowing-water distraction.
function Shell.StepWater(_model: Model, _dt: number) end
function Shell.SetDetailVisible(model: Model, visible: boolean)
	for _, p in CollectionService:GetTagged("BiomeFarDetail") do
		if p:IsA("BasePart") and p:IsDescendantOf(model) then
			p.LocalTransparencyModifier = if visible then 0 else 1
		end
	end
end
return Shell
