--!strict
-- Staged asset factory only. No gameplay registration, timers, remotes, purchases or animation loop.
local Shared = script.Parent.Parent
local Geometry = Shared.Config.ToyGeometry
local Names = require(Shared.Config.KnifeCharacters)
local FaceDecals = require(Shared.Config.KnifeFaceDecals)
local CharacterGeometry = require(Shared.Config.ToyGeometry.KnifeCharacters.RustyShank)
type Block = CharacterGeometry.Block
local Assets = {}
export type Options = { Scale: number?, Peek: boolean? }
local function build(source: ModuleScript, name: string, parent: Instance?, frame: CFrame?, options: Options?): Model
	local opts: Options = options or {}
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name, root.Size, root.Transparency = "Root", Vector3.one * 0.01, 1
	root.Anchored, root.CanCollide, root.CanQuery, root.CanTouch, root.CastShadow = true, false, false, false, false
	root.Parent = model
	model.PrimaryPart = root
	model:SetAttribute("ArtOnly", true)
	model:SetAttribute("FrontAxis", "-Z")
	model:SetAttribute("Origin", "floor below pommel / coffin centre")
	local specs: { Block } = (require :: any)(source)
	for _, spec in specs do
		local p = Instance.new("Part")
		p.Name, p.Size, p.Color = spec.Name, spec.Size, spec.Color
		p.Shape = if spec.Shape == "Ball" then Enum.PartType.Ball else Enum.PartType.Block
		p.CFrame = CFrame.new(spec.Offset) * CFrame.Angles(0, 0, math.rad(spec.Angle or 0))
		p.Transparency = if spec.Hidden and not (spec.Role == "Peek" and opts.Peek) then 1 else 0
		p.Material = if spec.Neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.Reflectance = if spec.Gloss then 0.08 else 0
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Massless = true
		p:SetAttribute("Role", spec.Role)
		p:SetAttribute("KnifeRole", spec.Role)
		p:SetAttribute("RestOffset", spec.Offset)
		p:SetAttribute("RestSize", spec.Size)
		if spec.Pulse or spec.Role == "Glow" then
			p:SetAttribute("Pulse", true)
		end
		p.Parent = model
		if p.Name == "FacePlate" then
			assert(FaceDecals[name], `Missing painted eye texture: {name}`)
			local decal = Instance.new("Decal")
			decal.Name = "EyesDecal"
			decal.Face = Enum.NormalId.Front
			decal.Texture = FaceDecals[name]
			decal.Parent = p
		end
	end
	model:ScaleTo(opts.Scale or 1)
	model:PivotTo(frame or CFrame.identity)
	model.Parent = parent
	return model
end
function Assets.BuildCharacter(name: string, parent: Instance?, frame: CFrame?, options: Options?): Model
	assert(Names[name], `Knife character not authored: {name}`)
	local source = Geometry.KnifeCharacters:FindFirstChild(name)
	assert(source and source:IsA("ModuleScript"), `Missing character art {name}`)
	local model = build(source, name, parent, frame, options)
	model:SetAttribute("KnifeName", name)
	model:SetAttribute("DisplayName", Names[name].Display)
	model:SetAttribute("Personality", Names[name].Personality)
	model:SetAttribute("BaseHeight", 2.4)
	model:SetAttribute("GripOffset", Names[name].GripOffset)
	model:SetAttribute("StaticFace", true)
	return model
end
function Assets.BuildCoffin(rarity: string, parent: Instance?, frame: CFrame?, options: Options?): Model
	local source = Geometry:FindFirstChild("Coffin_" .. rarity)
	assert(source and source:IsA("ModuleScript"), `Coffin not authored: {rarity}`)
	local model = build(source, "Coffin_" .. rarity, parent, frame, options)
	local length = ({
		Common = 3,
		Rare = 4,
		Epic = 5.2,
		Legendary = 6.6,
		Mythic = 8.2,
		Godly = 10,
		Celestial = 12,
		Cosmic = 14,
	})[rarity]
	assert(length, `Unknown coffin rarity {rarity}`)
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("BaseLength", length)
	model:SetAttribute("LidHinge", CFrame.new(0, length * 0.22 + length * 0.035 * 2.4, length / 2))
	model:SetAttribute("LidOpenAngle", 105)
	return model
end
function Assets.BuildPen(name: string, parent: Instance?, frame: CFrame?, options: Options?): Model
	assert(table.find({ "PenFence", "PenCorner", "PenGate", "PenFloor" }, name), "Unknown pen prop")
	local source = Geometry:FindFirstChild(name)
	assert(source and source:IsA("ModuleScript"), `Missing pen art {name}`)
	return build(source, name, parent, frame, options)
end
-- Closed/rest transforms stay on each lid part; clients can animate this same rigid hinge operation.
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
