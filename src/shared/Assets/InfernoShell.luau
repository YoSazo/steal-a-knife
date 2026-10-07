--!strict
-- Standalone measured environment asset. Claude owns integration into the world.
local CollectionService = game:GetService("CollectionService")
local Textures = require(script.Parent.Parent.Config.Textures)
local Art = require(script.Parent.Parent.Config.InfernoArt)
local Geometry = require(script.Parent.Parent.Config.ToyGeometry.ProgressiveBiomes.InfernoShellData)

type Block = Geometry.Block
export type Options = { Detail: boolean?, WaterTexture: string?, Ambient: boolean? }
local InfernoShell = {}

local function vec(value: { number }): Vector3
	return Vector3.new(value[1], value[2], value[3])
end

local function pivot(name: string, frame: CFrame, parent: Model): Part
	local root = Instance.new("Part")
	root.Name, root.Size, root.CFrame = name, Vector3.one * 0.1, frame
	root.Anchored, root.Transparency = true, 1
	root.CanCollide, root.CanTouch, root.CanQuery, root.CastShadow = false, false, false, false
	root:SetAttribute("BiomeShellPivot", true)
	root.Parent = parent
	return root
end

function InfernoShell.Build(parent: Instance?, origin: CFrame?, options: Options?): Model
	local frame = origin or CFrame.new(Geometry.Origin[1], Geometry.Origin[2], Geometry.Origin[3])
	local settings: Options = options or {}
	local waterImage = settings.WaterTexture or Art.WaterFoam.Image
	local assembly = Instance.new("Model")
	assembly.Name = "InfernoShell"
	assembly.PrimaryPart = pivot("Origin", frame, assembly)
	assembly:SetAttribute("BiomeIndex", 5)
	assembly:SetAttribute("Zone", 5)
	assembly:SetAttribute("Boss", "Ruby")
	assembly:SetAttribute("BossTitle", "The Firestarter")
	assembly:SetAttribute("FrontAxis", "-Z; +Z goes deeper")
	assembly:SetAttribute("GroundWidth", 160)
	assembly:SetAttribute("GroundDepth", Geometry.Depth)
	CollectionService:AddTag(assembly, "BiomeShell")
	local parts = 1
	local geometryGroups = Geometry.Groups :: { [string]: { Block } }
	for name, blocks in geometryGroups do
		local group = Instance.new("Model")
		group.Name = name
		group.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		group:SetAttribute("BiomeShellGroup", true)
		group.Parent = assembly
		local minimum = Vector3.new(math.huge, math.huge, math.huge)
		local maximum = -minimum
		for _, spec in blocks do
			if spec.Detail and settings.Detail == false then
				continue
			end
			local p = Instance.new("Part")
			p.Name, p.Size, p.CFrame = spec.Name, vec(spec.Size), frame * CFrame.new(vec(spec.Offset))
			p.Color = Color3.fromRGB(spec.Color[1], spec.Color[2], spec.Color[3])
			-- Matte molten flow keeps the game's strong bloom from whitening the blue channels.
			p.Material = Enum.Material.SmoothPlastic
			p.Anchored, p.Massless, p.CastShadow = true, true, false
			p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
			p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
			p.Transparency = if spec.Hidden then 1 else 0
			p:SetAttribute("BiomeShellPart", true)
			p.Parent = group
			parts += 1
			local lo, hi = vec(spec.Offset) - p.Size / 2, vec(spec.Offset) + p.Size / 2
			minimum = Vector3.new(math.min(minimum.X, lo.X), math.min(minimum.Y, lo.Y), math.min(minimum.Z, lo.Z))
			maximum = Vector3.new(math.max(maximum.X, hi.X), math.max(maximum.Y, hi.Y), math.max(maximum.Z, hi.Z))
			if spec.Detail then
				p:SetAttribute("MapDetail", true)
				CollectionService:AddTag(p, "BiomeFarDetail")
			end
			if spec.Stud then
				local stud = Instance.new("Texture")
				stud.Name, stud.Texture, stud.Face = "ToyStuds", Textures.Toy.Stud, Enum.NormalId.Top
				stud.StudsPerTileU, stud.StudsPerTileV, stud.Transparency = 2, 2, 0.45
				stud.Parent = p
			end
			if spec.WaterFace then
				local texture = Instance.new("Texture")
				texture.Name, texture.Texture = "WaterFoam", waterImage
				texture.Face = if spec.WaterFace == "Right"
					then Enum.NormalId.Right
					elseif spec.WaterFace == "Left" then Enum.NormalId.Left
					else Enum.NormalId.Top
				texture.StudsPerTileU, texture.StudsPerTileV = 12, 12
				texture.Transparency = 0.65
				texture.Color3 = Color3.fromRGB(230, 75, 9)
				texture:SetAttribute("FlowSpeed", if spec.WaterFace == "Top" then 0.7 else 2.5)
				CollectionService:AddTag(texture, "BiomeFlowTexture")
				texture.Parent = p
			end
			if spec.Ambient and settings.Ambient ~= false then
				local emitter = Instance.new("ParticleEmitter")
				emitter.Name, emitter.Texture = "InfernoDust", Textures.Sparkle
				emitter.Color = ColorSequence.new(Color3.fromRGB(139, 68, 172))
				emitter.Size = NumberSequence.new(0.25)
				emitter.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.25, 0.15),
					NumberSequenceKeypoint.new(1, 1),
				})
				emitter.Rate, emitter.Lifetime, emitter.Speed = 2, NumberRange.new(4, 6), NumberRange.new(0.2, 0.5)
				emitter.SpreadAngle = Vector2.new(180, 180)
				emitter.Acceleration = Vector3.new(0, -0.4, 0)
				emitter.LightEmission = 0.2
				emitter.Parent = p
			end
		end
		group.PrimaryPart = pivot("GroupOrigin", frame * CFrame.new((minimum + maximum) / 2), group)
		parts += 1
	end
	assembly:SetAttribute("PartCount", parts)
	assembly.Parent = parent
	return assembly
end

-- Caller-owned animation hook: no connections, physics or global UI/world modifications.
function InfernoShell.StepWater(model: Model, deltaTime: number)
	for _, texture in CollectionService:GetTagged("BiomeFlowTexture") do
		if texture:IsA("Texture") and texture:IsDescendantOf(model) then
			local speed = texture:GetAttribute("FlowSpeed")
			if type(speed) == "number" then
				texture.OffsetStudsV = (texture.OffsetStudsV + speed * math.clamp(deltaTime, 0, 0.1)) % 12
			end
		end
	end
end

function InfernoShell.SetDetailVisible(model: Model, visible: boolean)
	for _, part in CollectionService:GetTagged("BiomeFarDetail") do
		if part:IsA("BasePart") and part:IsDescendantOf(model) then
			part.LocalTransparencyModifier = if visible then 0 else 1
			for _, effect in part:GetChildren() do
				if effect:IsA("ParticleEmitter") then
					effect.Enabled = visible
				end
			end
		end
	end
end

InfernoShell.Geometry = Geometry
return InfernoShell
