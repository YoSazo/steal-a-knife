--!strict
-- The "sun inside the creature" haze (Steal an Egg's top creatures): a big soft glow at the knife's
-- core, bright enough to catch the game's bloom (MapService: Threshold 1.6) so it bleeds light
-- into everything around it, plus layers stacked by rarity - nothing on a Common, a faint glow on a
-- Rare, ... every layer on a Cosmic. Particles only (no Light instances; client/Lod culls far ones).
-- Add(model, rarity, colour) puts an invisible "HazeCore" box over the model's body with the
-- emitters on it, so the haze moves with a hopping knife.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local Textures = require(ReplicatedStorage.Shared.Config.Textures)

local KnifeHaze = {}

-- Roblox draws nothing for particles bigger than this (measured: 20 studs shows, ~49 doesn't), so a
-- glow bigger than this is a camera-facing image instead (no size limit)
local PARTICLE_MAX = 20

-- Deep, saturated haze colours: pale glows vanished against our bright sky and grass in testing
-- (Steal an Egg's auras are strong purples / greens / golds that pop against anything)
local HAZE: { [string]: Color3 } = {
	Rare = Color3.fromRGB(60, 140, 255),
	Epic = Color3.fromRGB(170, 70, 255),
	Legendary = Color3.fromRGB(255, 175, 30),
	Mythic = Color3.fromRGB(255, 55, 70),
	Godly = Color3.fromRGB(255, 225, 90),
	Celestial = Color3.fromRGB(40, 215, 255),
	Cosmic = Color3.fromRGB(195, 55, 255),
}

-- A big soft glow that always faces the camera, set back behind the knife so its face stays crisp.
-- Brightness > 1 catches the bloom like the particles do.
local function sun(
	core: BasePart,
	name: string,
	span: number,
	color: Color3,
	alpha: number,
	brightness: number,
	back: number
)
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = UDim2.fromScale(span, span) -- (studs)
	gui.StudsOffset = Vector3.new(0, 0, -back) -- (away from the camera: behind the knife)
	gui.LightInfluence = 0
	gui.Brightness = brightness
	gui.MaxDistance = 600
	gui.Adornee = core
	local image = Instance.new("ImageLabel")
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.Image = Textures.Glow.Soft
	image.ImageColor3 = color
	image.ImageTransparency = alpha
	image.Parent = gui
	gui.Parent = core
end

local function seq(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

local function emitter(core: BasePart, name: string, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.LightEmission = 0.45 -- (half light, half paint: stacked auras glowed white and hid the knives)
	e.LightInfluence = 0
	e.LockedToPart = true
	e.Speed = NumberRange.new(0)
	e.Rotation = NumberRange.new(0, 360)
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = core
	return e
end

function KnifeHaze.Add(model: Model, rarity: string, color: Color3?)
	local tier = table.find(Knives.Rarities, rarity) or 1
	if tier < 2 then
		return -- (a Common is just a knife: the haze is something you earn)
	end
	local old = model:FindFirstChild("HazeCore")
	if old then
		old:Destroy()
	end
	local tint = color or HAZE[rarity] or Knives.RarityColors[rarity] or Color3.new(1, 1, 1)
	local cf, size = model:GetBoundingBox()
	local height = size.Y
	local core = Instance.new("Part")
	core.Name = "HazeCore"
	core.Size = Vector3.new(size.X * 0.6, height * 0.7, size.Z * 0.6)
	core.CFrame = cf
	core.Transparency = 1
	core.Anchored = model.PrimaryPart ~= nil and model.PrimaryPart.Anchored
	core.CanCollide, core.CanQuery, core.CanTouch = false, false, false
	core.Massless = true
	core.Parent = model
	if not core.Anchored and model.PrimaryPart then
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = model.PrimaryPart, core
		weld.Parent = core
	end
	local glowColor = ColorSequence.new(tint:Lerp(Color3.new(1, 1, 1), 0.15), tint)

	-- 1. The core glow: one big soft sun, slowly breathing. Brighter tiers push past the bloom
	-- threshold, which is what spreads the haze over everything near it.
	-- (about the knife's own size: Steal an Egg's glow hugs the creature, it doesn't wash the pen)
	local span = height * (0.75 + tier * 0.05)
	if span > PARTICLE_MAX then
		-- too big for a particle: the sun is an image; a smaller breathing particle glow still sits in it
		sun(core, "CoreSun", span, tint, 0.72, 1 + tier * 0.08, size.Z)
		span = PARTICLE_MAX
	end
	emitter(core, "CoreGlow", {
		Texture = Textures.Glow.Soft,
		Color = glowColor,
		Rate = 2.2,
		Lifetime = NumberRange.new(2.4, 3.2),
		Size = seq({ { 0, span * 0.85 }, { 0.5, span }, { 1, span * 0.9 } }),
		Transparency = seq({ { 0, 1 }, { 0.35, 0.62 - tier * 0.015 }, { 0.7, 0.68 - tier * 0.015 }, { 1, 1 } }),
		LightEmission = 0.2, -- (part painted, part light: keeps its colour on a bright day)
		Brightness = 0.7 + tier * 0.12,
		RotSpeed = NumberRange.new(-8, 8),
		ZOffset = -2, -- (behind the knife, so the face stays crisp)
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})
	-- 2. Twinkles (Epic+): little 4-point flares popping around the body
	if tier >= 3 then
		local rainbow = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 110, 110)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 240, 110)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(110, 230, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 120, 255)),
		})
		local twinkle = math.min(height * (0.16 + tier * 0.02), 8)
		emitter(core, "Twinkles", {
			Texture = Textures.AuraSprites.Star.Id,
			Color = if tier >= 8 then rainbow else ColorSequence.new(Color3.new(1, 1, 1), tint),
			Rate = 1 + tier * 0.6,
			Lifetime = NumberRange.new(0.6, 1.1),
			Size = seq({ { 0, 0 }, { 0.3, twinkle }, { 1, 0 } }),
			Transparency = seq({ { 0, 0.2 }, { 1, 0.6 } }),
			Brightness = 1.4 + tier * 0.1,
			RotSpeed = NumberRange.new(-40, 40),
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		})
	end
	-- 3. Rising embers (Legendary+): soft sparks drifting up out of it
	if tier >= 4 then
		emitter(core, "Embers", {
			Texture = Textures.AuraSprites.Ember.Id,
			FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2,
			FlipbookMode = Enum.ParticleFlipbookMode.Loop,
			Color = glowColor,
			Rate = 4 + tier,
			Lifetime = NumberRange.new(1.2, 2),
			Speed = NumberRange.new(height * 0.25, height * 0.5),
			SpreadAngle = Vector2.new(25, 25),
			EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, height * 0.1, 0),
			Size = seq({ { 0, math.min(height * 0.18, 4) }, { 1, 0 } }),
			Transparency = seq({ { 0, 0.15 }, { 1, 1 } }),
			Brightness = 1.4 + tier * 0.08,
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		})
	end
	-- 4. A second, wider halo (Mythic+): the "sun inside it" that lights the air around it
	if tier >= 5 then
		local wide = height * (1.25 + (tier - 5) * 0.08)
		sun(core, "Halo", wide, tint, 0.92, 1 + tier * 0.05, size.Z * 1.5)
	end
	-- 5. Personality (Steal an Egg's monstrosity look): sprites with shapes of their own, stacked by rarity
	local big = math.min(height, 14) -- (x1.4 for the biggest layers stays under PARTICLE_MAX)
	local function flipbook(layout: Enum.ParticleFlipbookLayout, mode: Enum.ParticleFlipbookMode): { [string]: any }
		return { FlipbookLayout = layout, FlipbookMode = mode, FlipbookFramerate = NumberRange.new(8, 8) }
	end
	-- Epic+: goo dripping off it
	if tier >= 3 then
		local props = flipbook(Enum.ParticleFlipbookLayout.Grid4x4, Enum.ParticleFlipbookMode.Loop)
		props.Texture = Textures.AuraSprites.SlimeDrip.Id
		props.Color = ColorSequence.new(tint:Lerp(Color3.new(1, 1, 1), 0.2), tint)
		props.Rate = 2 + tier * 0.8
		props.Lifetime = NumberRange.new(1.6, 2.4)
		props.Size = seq({ { 0, big * 0.22 }, { 1, big * 0.3 } })
		props.Transparency = seq({ { 0, 1 }, { 0.15, 0.1 }, { 0.8, 0.2 }, { 1, 1 } })
		props.Acceleration = Vector3.new(0, -big * 0.5, 0)
		props.Rotation = NumberRange.new(0, 0)
		props.LightEmission = 0.5
		props.Brightness = 1.1
		props.Shape = Enum.ParticleEmitterShape.Box
		props.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter(core, "Drips", props)
	end
	-- Legendary+: bold swirls turning in the air around it
	if tier >= 4 then
		emitter(core, "Spirals", {
			Texture = Textures.AuraSprites.Spiral.Id,
			Color = ColorSequence.new(tint:Lerp(Color3.new(1, 1, 1), 0.25), tint),
			Rate = 3 + tier * 0.7,
			Lifetime = NumberRange.new(2.2, 3.2),
			Size = seq({ { 0, big * 0.2 }, { 0.5, big * 0.5 }, { 1, big * 0.35 } }),
			Transparency = seq({ { 0, 1 }, { 0.25, 0.3 }, { 0.75, 0.4 }, { 1, 1 } }),
			RotSpeed = NumberRange.new(70, 140),
			Brightness = 1.15,
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		})
	end
	-- Mythic+: crystal shards bursting out, dark smoke curling round it
	if tier >= 5 then
		emitter(core, "Shards", {
			Texture = Textures.AuraSprites.LightningShard.Id,
			Color = ColorSequence.new(Color3.new(1, 1, 1), tint),
			Rate = 3 + tier * 0.8,
			Lifetime = NumberRange.new(0.7, 1.2),
			Speed = NumberRange.new(big * 0.6, big * 1.1),
			SpreadAngle = Vector2.new(180, 180),
			Size = seq({ { 0, big * 0.22 }, { 1, 0 } }),
			Transparency = seq({ { 0, 0 }, { 1, 0.8 } }),
			Brightness = 1.5,
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			LockedToPart = false,
		})
		local smoke = flipbook(Enum.ParticleFlipbookLayout.Grid4x4, Enum.ParticleFlipbookMode.Loop)
		smoke.Texture = Textures.AuraSprites.SmokeWisp.Id
		smoke.Color = ColorSequence.new(tint:Lerp(Color3.new(0, 0, 0), 0.65))
		smoke.Rate = 2.5 + tier * 0.5
		smoke.Lifetime = NumberRange.new(2.4, 3.4)
		smoke.Speed = NumberRange.new(big * 0.08, big * 0.18)
		smoke.SpreadAngle = Vector2.new(40, 40)
		smoke.EmissionDirection = Enum.NormalId.Top
		smoke.Size = seq({ { 0, big * 0.3 }, { 1, big * 0.7 } })
		smoke.Transparency = seq({ { 0, 1 }, { 0.2, 0.35 }, { 0.8, 0.55 }, { 1, 1 } })
		smoke.LightEmission = 0
		smoke.Brightness = 1
		smoke.ZOffset = -1
		smoke.Shape = Enum.ParticleEmitterShape.Box
		smoke.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter(core, "Smoke", smoke)
	end
	-- Godly+: slow god-rays turning behind it
	if tier >= 6 then
		emitter(core, "Rays", {
			Texture = Textures.AuraSprites.LightRays.Id,
			Color = ColorSequence.new(tint:Lerp(Color3.new(1, 1, 1), 0.4), tint),
			Rate = 0.9,
			Lifetime = NumberRange.new(5, 6),
			Size = seq({ { 0, big * 1.1 }, { 1, big * 1.4 } }),
			Transparency = seq({ { 0, 1 }, { 0.25, 0.7 }, { 0.75, 0.75 }, { 1, 1 } }),
			RotSpeed = NumberRange.new(12, 18),
			Brightness = 1.2,
			ZOffset = -3,
		})
	end
	-- Celestial+: lightning cracking round the top tiers
	if tier >= 7 then
		local bolt = flipbook(Enum.ParticleFlipbookLayout.Grid4x4, Enum.ParticleFlipbookMode.OneShot)
		bolt.Texture = Textures.AuraSprites.LightningBolt.Id
		bolt.Color = ColorSequence.new(Color3.new(1, 1, 1), tint)
		bolt.Rate = 1 + (tier - 7) * 0.6
		bolt.Lifetime = NumberRange.new(1.6, 1.6)
		bolt.Size = seq({ { 0, big * 0.9 }, { 1, big * 0.9 } })
		bolt.Transparency = seq({ { 0, 0 }, { 1, 0 } })
		bolt.Brightness = 1.8
		bolt.Shape = Enum.ParticleEmitterShape.Box
		bolt.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter(core, "Bolts", bolt)
	end
	-- Cosmic: a rainbow band arching over it
	if tier >= 8 then
		emitter(core, "Rainbow", {
			Texture = Textures.AuraSprites.RainbowArc.Id,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 110)),
				ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 235, 110)),
				ColorSequenceKeypoint.new(0.7, Color3.fromRGB(110, 230, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(215, 120, 255)),
			}),
			Rate = 0.9,
			Lifetime = NumberRange.new(3, 3.6),
			Size = seq({ { 0, big * 1.1 }, { 1, big * 1.3 } }),
			Transparency = seq({ { 0, 1 }, { 0.3, 0.35 }, { 0.7, 0.45 }, { 1, 1 } }),
			Rotation = NumberRange.new(0, 0),
			Brightness = 1.2,
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		})
	end
end

-- The ground shockwave when a big knife lands from a hop: a flat ring that spreads and fades
function KnifeHaze.Shock(at: Vector3, radius: number, color: Color3)
	local ring = Instance.new("Part")
	ring.Name = "ShockRing"
	ring.Size = Vector3.new(radius * 0.4, 0.1, radius * 0.4)
	ring.Anchored = true
	ring.CanCollide, ring.CanQuery, ring.CanTouch = false, false, false
	ring.Transparency = 1
	ring.CFrame = CFrame.new(at + Vector3.new(0, 0.2, 0))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	local image = Instance.new("ImageLabel")
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.Image = Textures.AuraSprites.ShockRing.Id
	image.ImageColor3 = color
	image.Parent = gui
	gui.Parent = ring
	ring.Parent = workspace
	local info = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweens = game:GetService("TweenService")
	tweens:Create(ring, info, { Size = Vector3.new(radius * 2, 0.1, radius * 2) }):Play()
	tweens:Create(image, info, { ImageTransparency = 1 }):Play()
	task.delay(0.8, function()
		ring:Destroy()
	end)
end

return KnifeHaze
