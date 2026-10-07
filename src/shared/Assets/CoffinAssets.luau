--!strict
-- Self-contained art builder. Floor-centre pivot; front -Z. No gameplay hooks or animation loop.
local Geometry = script.Parent.Parent.Config.ToyGeometry
local Common = require(Geometry.Coffin_Common)
type Block = Common.Block
local Assets = {}
local Lengths: { [string]: number } = {
	Common = 3,
	Rare = 4,
	Epic = 5.2,
	Legendary = 6.6,
	Mythic = 8.2,
	Godly = 10,
	Celestial = 12,
	Cosmic = 14,
}
export type Options = { Scale: number?, Peek: boolean? }
function Assets.BuildCoffin(rarity: string, parent: Instance?, frame: CFrame?, options: Options?): Model
	local length = Lengths[rarity]
	assert(length, `Unknown coffin rarity: {rarity}`)
	local source = Geometry:FindFirstChild("Coffin_" .. rarity)
	assert(source and source:IsA("ModuleScript"), `Missing coffin art: {rarity}`)
	local opts: Options = options or {}
	local model = Instance.new("Model")
	model.Name = "Coffin_" .. rarity
	local root = Instance.new("Part")
	root.Name, root.Size, root.Transparency = "Root", Vector3.one * 0.01, 1
	root.Anchored, root.CanCollide, root.CanQuery, root.CanTouch, root.CastShadow = true, false, false, false, false
	root.Parent = model
	model.PrimaryPart = root
	local blocks: { Block } = (require :: any)(source)
	for _, spec in blocks do
		local p = Instance.new("Part")
		p.Name, p.Size, p.Color = spec.Name, spec.Size, spec.Color
		p.CFrame = CFrame.new(spec.Offset) * CFrame.Angles(0, 0, math.rad(spec.Angle or 0))
		p.Transparency = if spec.Hidden and not (spec.Role == "Peek" and opts.Peek) then 1 else 0
		p.Material = if spec.Neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Massless = true
		p:SetAttribute("Role", spec.Role)
		p:SetAttribute("RestOffset", spec.Offset)
		p:SetAttribute("RestSize", spec.Size)
		if spec.Pulse or spec.Role == "Glow" then
			p:SetAttribute("Pulse", true)
		end
		p.Parent = model
	end
	model:SetAttribute("ArtOnly", true)
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("BaseLength", length)
	model:SetAttribute("FrontAxis", "-Z")
	model:SetAttribute("Origin", "bottom centre")
	model:SetAttribute("LidHinge", CFrame.new(0, length * 0.304, length / 2))
	model:SetAttribute("LidOpenAngle", 105)
	model:ScaleTo(opts.Scale or 1)
	model:PivotTo(frame or CFrame.identity)
	model.Parent = parent
	return model
end
function Assets.SetCoffinOpen(model: Model, degrees: number)
	local scale = model:GetScale()
	local rest = model:GetAttribute("LidHinge") :: CFrame
	local hinge = CFrame.new(rest.Position * scale)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p:GetAttribute("Role") == "Lid" then
			local offset = p:GetAttribute("RestOffset") :: Vector3
			p.CFrame = model:GetPivot()
				* hinge
				* CFrame.Angles(math.rad(degrees), 0, 0)
				* hinge:Inverse()
				* CFrame.new(offset * scale)
		end
	end
end
return Assets
