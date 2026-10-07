--!strict
-- The same block geometry is used by the Blender previews and the playable wheels.
-- Only Rotor is tagged/spun; the pedestal, machinery and emblems stay stationary.
local Geometry = require(script.Parent.Config.WheelGeometry)
local Textures = require(script.Parent.Config.Textures)

local WheelModel = {}
export type Built = { Rotor: Model, Stand: Model }

local function populate(model: Model, rows: { Geometry.Row }, palette: { Color3 }, pivot: CFrame)
	for _, row in rows do
		local part = Instance.new("Part")
		part.Name = row[1]
		part.Size = Vector3.new(row[2], row[3], row[4])
		part.CFrame = pivot * CFrame.new(row[5], row[6], row[7]) * CFrame.Angles(row[8], row[9], row[10])
		part.Color = palette[row[11]]
		part.Material = if row[12] then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.Anchored = true
		part.Massless = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CastShadow = false
		part.Parent = model
	end
end

local function seq(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

-- The better wheels show off (the aura sprites, Config/Textures.AuraSprites), more the higher the
-- tier: twinkles from the Haunted Wheel up, then swirls, ghostly smoke, embers, god-rays, lightning,
-- and a rainbow over the very best. On an invisible box round the wheel in the stand (it doesn't
-- spin), tinted with the wheel's own glow colour. Particles only; client/Lod culls far ones.
local function sprites(stand: Model, rotor: Model, level: number)
	if level < 4 then
		return
	end
	local glow: Color3? = nil
	for _, part in rotor:GetChildren() do
		if part:IsA("BasePart") and part.Material == Enum.Material.Neon then
			glow = part.Color
			break
		end
	end
	local tint = glow or Color3.fromRGB(255, 220, 120)
	local cf, size = rotor:GetBoundingBox()
	local core = Instance.new("Part")
	core.Name = "SpriteCore"
	core.Size = size * 1.1
	core.CFrame = cf
	core.Transparency = 1
	core.Anchored = true
	core.CanCollide, core.CanQuery, core.CanTouch = false, false, false
	core.Parent = stand
	local big = math.min(math.max(size.X, size.Y, size.Z), 14)
	local function emit(name: string, props: { [string]: any })
		local e = Instance.new("ParticleEmitter")
		e.Name = name
		e.LightInfluence = 0
		e.LightEmission = 0.45
		e.Rotation = NumberRange.new(0, 360)
		-- (from the wheel's outside, drifting out: inside it they hid behind its own blocks)
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		e.Speed = NumberRange.new(1, 2.5)
		for key, value in props do
			(e :: any)[key] = value
		end
		e.Parent = core
	end
	local light = ColorSequence.new(Color3.new(1, 1, 1), tint)
	emit("Twinkles", {
		Texture = Textures.AuraSprites.Star.Id,
		Color = light,
		Rate = 3 + level * 0.6,
		Lifetime = NumberRange.new(0.6, 1.1),
		Size = seq({ { 0, 0 }, { 0.35, big * 0.17 }, { 1, 0 } }),
		Transparency = seq({ { 0, 0.15 }, { 1, 0.7 } }),
		RotSpeed = NumberRange.new(-50, 50),
		Brightness = 1.4,
	})
	if level >= 6 then
		emit("Spirals", {
			Texture = Textures.AuraSprites.Spiral.Id,
			Color = light,
			Rate = 2 + (level - 6) * 0.4,
			Lifetime = NumberRange.new(2.2, 3),
			Size = seq({ { 0, big * 0.15 }, { 0.5, big * 0.38 }, { 1, big * 0.25 } }),
			Transparency = seq({ { 0, 1 }, { 0.25, 0.4 }, { 0.75, 0.5 }, { 1, 1 } }),
			RotSpeed = NumberRange.new(70, 130),
			Brightness = 1.2,
		})
	end
	if level >= 8 then
		emit("Smoke", {
			Texture = Textures.AuraSprites.SmokeWisp.Id,
			FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
			FlipbookMode = Enum.ParticleFlipbookMode.Loop,
			FlipbookFramerate = NumberRange.new(8, 8),
			Color = ColorSequence.new(tint:Lerp(Color3.new(0, 0, 0), 0.6)),
			LightEmission = 0,
			Rate = 2.5,
			Lifetime = NumberRange.new(2.4, 3.2),
			Speed = NumberRange.new(1, 2.5),
			EmissionDirection = Enum.NormalId.Top,
			Size = seq({ { 0, big * 0.2 }, { 1, big * 0.45 } }),
			Transparency = seq({ { 0, 1 }, { 0.2, 0.45 }, { 0.8, 0.6 }, { 1, 1 } }),
			Brightness = 1,
			ZOffset = -1,
		})
	end
	if level >= 9 then
		emit("Embers", {
			Texture = Textures.AuraSprites.Ember.Id,
			FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2,
			FlipbookMode = Enum.ParticleFlipbookMode.Loop,
			FlipbookFramerate = NumberRange.new(8, 8),
			Color = light,
			Rate = 8 + (level - 9) * 2,
			Lifetime = NumberRange.new(1, 1.6),
			Speed = NumberRange.new(3, 5),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(25, 25),
			Size = seq({ { 0, big * 0.16 }, { 1, 0 } }),
			Transparency = seq({ { 0, 0.15 }, { 1, 1 } }),
			Rotation = NumberRange.new(-10, 10),
			Brightness = 1.4,
		})
	end
	if level >= 10 then
		emit("Rays", {
			Texture = Textures.AuraSprites.LightRays.Id,
			Color = ColorSequence.new(tint:Lerp(Color3.new(1, 1, 1), 0.4)),
			Rate = 0.5,
			Lifetime = NumberRange.new(5, 6),
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			Speed = NumberRange.new(0), -- (stays centred on the wheel)
			Size = seq({ { 0, big * 1.1 }, { 1, big * 1.35 } }),
			Transparency = seq({ { 0, 1 }, { 0.3, 0.72 }, { 0.7, 0.78 }, { 1, 1 } }),
			RotSpeed = NumberRange.new(10, 16),
			Brightness = 1.1,
			ZOffset = -3,
		})
	end
	if level >= 12 then
		emit("Bolts", {
			Texture = Textures.AuraSprites.LightningBolt.Id,
			Speed = NumberRange.new(0),
			FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
			FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
			Color = light,
			Rate = 0.8,
			Lifetime = NumberRange.new(1.4, 1.4),
			Size = seq({ { 0, big * 0.6 }, { 1, big * 0.6 } }),
			Transparency = seq({ { 0, 0 }, { 1, 0 } }),
			Brightness = 1.8,
		})
	end
	if level >= 13 then
		emit("Rainbow", {
			Texture = Textures.AuraSprites.RainbowArc.Id,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 110)),
				ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 235, 110)),
				ColorSequenceKeypoint.new(0.7, Color3.fromRGB(110, 230, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(215, 120, 255)),
			}),
			Rate = 0.7,
			Lifetime = NumberRange.new(3, 3.6),
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			Speed = NumberRange.new(0), -- (stays centred on the wheel)
			Size = seq({ { 0, big * 1.1 }, { 1, big * 1.3 } }),
			Transparency = seq({ { 0, 1 }, { 0.3, 0.4 }, { 0.7, 0.5 }, { 1, 1 } }),
			Rotation = NumberRange.new(0, 0),
			Brightness = 1.2,
		})
	end
end

function WheelModel.Build(level: number, pivot: CFrame): Built
	level = math.clamp(math.floor(level), 1, #Geometry)
	local tier = Geometry[level]
	local rotor = Instance.new("Model")
	rotor.Name = "HauntedWheel"
	rotor.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local hub = Instance.new("Part")
	hub.Name = "Hub"
	hub.Size = Vector3.one * 0.1
	hub.CFrame = pivot
	hub.Transparency = 1
	hub.Anchored = true
	hub.CanCollide = false
	hub.CanTouch = false
	hub.CanQuery = false
	hub.Parent = rotor
	rotor.PrimaryPart = hub
	rotor:SetAttribute("Pivot", pivot)
	rotor:SetAttribute("Tier", level)
	rotor:SetAttribute("DesignName", tier.Name)
	populate(rotor, tier.Rotor, tier.Palette, pivot)
	local stand = Instance.new("Model")
	stand.Name = "WheelDetails"
	stand.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	stand:SetAttribute("Tier", level)
	populate(stand, tier.Stand, tier.Palette, pivot)
	sprites(stand, rotor, level)
	return { Rotor = rotor, Stand = stand }
end

return WheelModel
