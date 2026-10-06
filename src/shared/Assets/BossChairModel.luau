--!strict
-- Art-only chair construction/preparation. No gameplay, prompts, lights, seats or connections.
-- Every frame is Roblox-local: floor origin beneath seat centre, front -Z, backrest +Z.
local Chairs = require(script.Parent.Parent.Config.BossChairs)

export type Options = { Detail: boolean? }
local BossChairModel = {}

local function preparePart(part: BasePart)
	part.Anchored, part.Massless, part.CastShadow = true, true, false
	part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
end

local function stamp(model: Model, zone: number)
	local spec = Chairs[zone]
	assert(spec, `Unknown boss chair zone {zone}`)
	model.Name = `{spec.Boss}Chair`
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("BossChair", true)
	model:SetAttribute("Zone", zone)
	model:SetAttribute("Boss", spec.Boss)
	model:SetAttribute("SeatTop", spec.SeatTop)
	model:SetAttribute("SeatDepth", spec.SeatDepth)
	model:SetAttribute("FrontAxis", "-Z")
end

-- Preload the uploaded ModelAssetId in Studio, then prepare its model before mounting it.
-- The invisible Origin mesh marks the floor pivot; imported geometry retains its own UVs.
function BossChairModel.Prepare(model: Model, zone: number, parent: Instance?, frame: CFrame?): Model
	local spec = Chairs[zone]
	assert(spec, `Unknown boss chair zone {zone}`)
	local chunks: { [string]: Chairs.Mesh } = {}
	for _, chunk in spec.MeshParts do
		chunks[chunk.SourceName] = chunk
		chunks[chunk.Name] = chunk
	end
	local origin: BasePart? = nil
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			preparePart(part)
			local chunk = chunks[part.Name]
			if chunk then
				part.Name = chunk.Name -- normalize Blender's per-scene .001/.002 suffixes
				if chunk.Hidden then
					origin = part
					part.Transparency = 1
				end
				part.Material = if chunk.Neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
			if part:IsA("MeshPart") then
				part.Color = Color3.new(1, 1, 1)
				part.TextureID = spec.TextureId
			end
		end
	end
	assert(origin, "Uploaded chair is missing its floor Origin")
	model.PrimaryPart = origin
	stamp(model, zone)
	if frame then
		model:PivotTo(frame)
	end
	model.Parent = parent
	return model
end

-- Exact native block fallback from the same geometry exported to the uploaded mesh models.
-- Create unparented until complete; all parts are cosmetic, with no Seat instance/physics.
function BossChairModel.Build(zone: number, parent: Instance?, frame: CFrame?, options: Options?): Model
	local spec = Chairs[zone]
	assert(spec, `Unknown boss chair zone {zone}`)
	local at = frame or CFrame.identity
	local settings: Options = options or {}
	local model = Instance.new("Model")
	local origin = Instance.new("Part")
	origin.Name, origin.Size, origin.CFrame = "Origin", Vector3.one * 0.05, at
	origin.Transparency = 1
	preparePart(origin)
	origin.Parent = model
	model.PrimaryPart = origin
	local count = 1
	for _, block in spec.Parts do
		if block.Detail and settings.Detail == false then
			continue
		end
		local part = Instance.new("Part")
		part.Name, part.Size = block.Name, block.Size
		part.CFrame = at * CFrame.new(block.Offset)
		if block.Rotation then
			part.CFrame *= CFrame.Angles(
				math.rad(block.Rotation.X),
				math.rad(block.Rotation.Y),
				math.rad(block.Rotation.Z)
			)
		end
		part.Color = block.Color
		part.Material = if block.Neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		part:SetAttribute("ChairGroup", block.Group)
		preparePart(part)
		part.Parent = model
		count += 1
	end
	stamp(model, zone)
	model:SetAttribute("PartCount", count)
	model.Parent = parent
	return model
end

return BossChairModel
