--!strict
-- A cartoon fire made of our own flame sprite (Config/KnifeAuraArt.CartoonFlame, the same 8x8 toon
-- flame the knife auras use: tools/make_cartoon_flame.py) instead of Roblox's realistic Fire
-- effect, which looked like a different game on the toy-style biomes. Torches, braziers and lava
-- vents call SpriteFire.Add. Particles only (no Light): client/Lod switches far ones off.
local Art = require(script.Parent.Config.KnifeAuraArt)

local SpriteFire = {}

-- A flame standing on top of `part`, about `height` studs tall, tinted `color` (white = the
-- sprite's own oranges), with a few embers drifting up off it
function SpriteFire.Add(part: BasePart, height: number, color: Color3?): ParticleEmitter
	local base = Instance.new("Attachment")
	base.Name = "SpriteFire"
	base.Position = Vector3.new(0, part.Size.Y / 2 + height * 0.45, 0)
	base.Parent = part

	-- (a particle's Size is half its quad: the flame is about `height` tall)
	local half = height / 2
	local flame = Instance.new("ParticleEmitter")
	flame.Name = "Flame"
	flame.Texture = Art.CartoonFlame
	flame.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid8x8
	flame.FlipbookMode = Enum.ParticleFlipbookMode.Loop
	flame.FlipbookFramerate = NumberRange.new(20, 26)
	flame.FlipbookStartRandom = true
	flame.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
	flame.LightInfluence = 0
	flame.LightEmission = 0.2
	flame.Color = ColorSequence.new(color or Color3.new(1, 1, 1))
	flame.LockedToPart = true
	flame.Speed = NumberRange.new(0)
	flame.SpreadAngle = Vector2.new(0, 0)
	flame.Lifetime = NumberRange.new(0.9, 1.2)
	flame.Rate = 3
	flame.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, half * 0.9),
		NumberSequenceKeypoint.new(0.4, half),
		NumberSequenceKeypoint.new(1, half * 0.85),
	})
	flame.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.15, 0),
		NumberSequenceKeypoint.new(0.8, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	flame.Parent = base

	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.Texture = Art.Ember
	embers.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	embers.FlipbookMode = Enum.ParticleFlipbookMode.Loop
	embers.FlipbookStartRandom = true
	embers.LightInfluence = 0
	embers.LightEmission = 0.4
	embers.Color = ColorSequence.new(color or Color3.fromRGB(255, 190, 90))
	embers.Speed = NumberRange.new(height * 0.6, height * 1.1)
	embers.SpreadAngle = Vector2.new(25, 25)
	embers.Lifetime = NumberRange.new(0.8, 1.4)
	embers.Rate = 2 + height * 0.5
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, height * 0.06),
		NumberSequenceKeypoint.new(1, 0),
	})
	embers.Parent = base
	return flame
end

return SpriteFire
