--!strict
-- Curve-authored animated silhouettes: outer lobes, hot core, curled tips and embers.
-- Independent upright attachments keep the effect separate from the spinning knife.
local Art = require(script.Parent.Config.KnifeAuraArt)
local Variants = require(script.Parent.Config.KnifeAuraVariants)
local Items = require(script.Parent.Items)
local Knives = require(script.Parent.Config.Knives)
local KnifeAura = {}

function KnifeAura.Power(item: string): number
	local parsed = Items.Parse(item)
	if not parsed then
		return 0
	end
	local family = Knives.ByRarity[parsed.Knife.Rarity]
	local low, high = math.huge, 0
	for _, knife in family do
		low = math.min(low, knife.Damage)
		high = math.max(high, knife.Damage)
	end
	local withinTier = if high > low then (parsed.Knife.Damage - low) / (high - low) else 0
	return Items.AuraPower(item) + withinTier * 0.7
end

function KnifeAura.Dimensions(power: number): (number, number)
	local strength = math.clamp(power, 0, 15)
	return 2.1 + strength * 0.34, 5 + strength * 1.2
end

function KnifeAura.Variation(item: string): Variants.Style
	local parsed = Items.Parse(item)
	if not parsed then
		return Variants.List[1]
	end
	local hash = 0
	-- Ignore the rolled combat perk: it must not change a knife's visual identity.
	local identity = parsed.Name .. "|" .. parsed.Mutation.Id .. "|" .. parsed.Size.Id
	for i = 1, #identity do
		hash = (hash * 31 + string.byte(identity, i)) % 65521
	end
	return Variants.List[hash % #Variants.List + 1]
end

local function emitter(anchor: BasePart, name: string, texture: string, rate: number, y: number): ParticleEmitter
	local attachment = Instance.new("Attachment")
	attachment.Name = name .. "Origin"
	attachment.Position = Vector3.new(0, y, 0)
	attachment:SetAttribute("KnifeAuraOwned", true)
	local p = Instance.new("ParticleEmitter")
	p.Name = name
	p.Texture = texture
	p.FlipbookLayout = if texture == Art.Ember
		then Enum.ParticleFlipbookLayout.Grid4x4
		else Enum.ParticleFlipbookLayout.Grid8x8
	p.FlipbookMode = Enum.ParticleFlipbookMode.Loop
	p.FlipbookFramerate = NumberRange.new(24, 28)
	p.FlipbookStartRandom = true
	p.FlipbookBlendFrames = true
	p.LightEmission = 0.15
	p.LightInfluence = 0
	p.Brightness = 1
	p.EmissionDirection = Enum.NormalId.Top
	p.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
	p.SpreadAngle = Vector2.new(5, 5)
	p.Rotation = NumberRange.new(0)
	p.RotSpeed = NumberRange.new(0)
	p.LockedToPart = true
	p.Rate = rate
	p:SetAttribute("BaseRate", rate)
	p:AddTag("KnifeAuraEmitter")
	p.Parent = attachment
	attachment.Parent = anchor
	return p
end

local function shape(p: ParticleEmitter, width: number, height: number, maskWidth: number, maskHeight: number)
	-- Account for transparent atlas padding when fitting the visible silhouette.
	local quadWidth, quadHeight = width / maskWidth, height / maskHeight
	local size = math.sqrt(quadWidth * quadHeight)
	local stretch = math.sqrt(quadHeight / quadWidth)
	p.Squash = NumberSequence.new(stretch - 1)
	p.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.65),
		NumberSequenceKeypoint.new(0.18, size),
		NumberSequenceKeypoint.new(0.7, size * 0.93),
		NumberSequenceKeypoint.new(1, size * 0.35),
	})
end

-- The aura is sewn onto the blade: flames spawn all over the blade's surface and draw behind it,
-- so the steel stays clean and fire licks off its outline (no flame standing on the floor).
-- `blade` is the knife's Blade part; without one (old callers) it falls back to `anchor`.
-- Effects that must stay upright (smoke, glow light) live on `anchor`.
function KnifeAura.Mount(anchor: BasePart, power: number, clearance: number?, style: Variants.Style?, blade: BasePart?)
	local recipe = style or Variants.List[1]
	local motion = recipe.Motion
	local strength = math.clamp(power, 0, 15)
	local width, height = KnifeAura.Dimensions(strength)
	width *= motion.Width
	if clearance then
		local room = math.max(0.1, clearance)
		height = room * (1 - math.exp(-height / room))
		width = math.min(width, height * 0.8 + 0.8)
	end
	local source = blade or anchor
	local holders: { Instance } = { anchor, source }
	local guardPart = blade and blade.Parent and blade.Parent:FindFirstChild("Guard")
	if guardPart then
		table.insert(holders, guardPart)
	end
	for _, holder in holders do
		for _, child in holder:GetChildren() do
			if
				child:GetAttribute("KnifeAuraOwned")
				or child.Name == "AuraFire"
				or (child:IsA("ParticleEmitter") and child:HasTag("KnifeAuraEmitter"))
			then
				child:Destroy()
			end
		end
	end
	anchor:SetAttribute("AuraPower", power)
	anchor:SetAttribute("AuraWidth", width)
	anchor:SetAttribute("AuraHeight", height)
	anchor:SetAttribute("AuraArtVersion", 5)
	anchor:SetAttribute("AuraVariation", recipe.Id)

	-- Flames from the blade's whole surface, in world space (they rise while the knife turns)
	local function sewn(name: string, rate: number): ParticleEmitter
		local p = Instance.new("ParticleEmitter")
		p.Name = name
		p.Texture = Art.CartoonFlame
		p.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid8x8
		p.FlipbookMode = Enum.ParticleFlipbookMode.Loop
		p.FlipbookFramerate = NumberRange.new(24, 30)
		p.FlipbookStartRandom = true
		p.Shape = Enum.ParticleEmitterShape.Box
		p.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		p.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		p.EmissionDirection = Enum.NormalId.Top
		p.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
		p.LightInfluence = 0
		p.LockedToPart = false
		p.Rate = rate
		p:SetAttribute("BaseRate", rate)
		p:SetAttribute("KnifeAuraOwned", true)
		p:AddTag("KnifeAuraEmitter")
		p.Parent = source
		return p
	end
	-- ONE flame, shaped like a triangle: a big body whose wide base sits at the guard and whose
	-- point rises past the blade's tip, a hot inner flame inside it, and lots of small licks along
	-- the edges that blend it all together. Everything draws behind the blade.
	local bladeLength = if blade then math.max(blade.Size.X, blade.Size.Y, blade.Size.Z) else 4
	-- (a particle's Size is HALF its quad: the flame stands ~1.8 x body tall above the guard)
	local body = bladeLength * (0.62 + strength * 0.03)
	if clearance then
		body = math.min(body, math.max(1, clearance / 1.85))
	end
	local function bodyFlame(name: string, size: number, rate: number): ParticleEmitter
		-- quad (2 x size tall) centred so the flame's base, 5% up the art, sits on the guard
		local p = emitter(anchor, name, Art.CartoonFlame, rate, size * 0.9)
		p.LockedToPart = true
		p.Speed = NumberRange.new(0)
		p.SpreadAngle = Vector2.new(0, 0)
		p.Lifetime = NumberRange.new(1, 1.3)
		p.FlipbookFramerate = NumberRange.new(20, 26)
		p.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, size * 0.92),
			NumberSequenceKeypoint.new(0.3, size),
			NumberSequenceKeypoint.new(1, size * 0.96),
		})
		-- slightly taller than wide: a sharper triangle
		p.Squash = NumberSequence.new(0.15)
		p.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.08),
			NumberSequenceKeypoint.new(0.75, 0.12),
			NumberSequenceKeypoint.new(1, 1),
		})
		return p
	end
	local outer = bodyFlame("FlameOuter", body, 3)
	outer:SetAttribute("AuraMinRate", 2.4)
	outer.LightEmission = 0.12 -- low: keeps the colour rich instead of washing out
	outer.Brightness = 1.3
	outer.ZOffset = -1.2
	local core = bodyFlame("FlameCore", body * 0.62, 3.4)
	core:SetAttribute("AuraMinRate", 2.6)
	core.LightEmission = 0.5
	core.Brightness = 1.5
	core.ZOffset = -1

	-- Licks all along the blade's edges, in the body's colours, so it reads as one fire
	local flameSize = math.clamp(0.7 + strength * 0.08, 0.7, math.max(0.7, body * 0.25))
	local rise = math.min(body * 0.6, 1.6 + strength * 0.2)
	local licks = sewn("FlameLicks", 45 + strength * 5)
	licks:SetAttribute("AuraMinRate", 18)
	licks.LightEmission = 0.6
	licks.Brightness = 1.5
	licks.ZOffset = -0.8
	licks.Lifetime = NumberRange.new(0.35, 0.6)
	licks.Speed = NumberRange.new(0.2, 0.5)
	licks.Acceleration = Vector3.new(0, rise * 3, 0)
	licks.SpreadAngle = Vector2.new(20, 20)
	licks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, flameSize * 0.6),
		NumberSequenceKeypoint.new(0.3, flameSize * motion.Body),
		NumberSequenceKeypoint.new(1, flameSize * 0.15),
	})
	licks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.2, 0.15),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	local lickColors = recipe.Colors.Outer
	licks.Color = ColorSequence.new(recipe.Colors.Core.Start, lickColors.Start)

	-- ...and off the crossguard itself, so the fire visibly grows out of the guard
	local guard = blade and blade.Parent and blade.Parent:FindFirstChild("Guard")
	if guard and guard:IsA("BasePart") then
		local guardLicks = licks:Clone()
		guardLicks.Name = "FlameGuard"
		guardLicks.Rate = 30 + strength * 3
		guardLicks:SetAttribute("BaseRate", guardLicks.Rate)
		guardLicks:SetAttribute("AuraMinRate", 12)
		guardLicks.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, flameSize * 0.7),
			NumberSequenceKeypoint.new(0.3, flameSize * 1.1),
			NumberSequenceKeypoint.new(1, flameSize * 0.2),
		})
		guardLicks.Parent = guard
	end

	-- Tongues that break off the point and fly up
	local tongues = emitter(anchor, "FlameTongues", Art.CartoonFlame, 4 + strength * 0.5, body * 1.5)
	tongues:SetAttribute("AuraMinRate", 2)
	tongues.LockedToPart = false
	tongues.LightEmission = 0.6
	tongues.Brightness = 1.4
	tongues.ZOffset = -0.9
	tongues.Lifetime = NumberRange.new(0.5, 0.8)
	tongues.Speed = NumberRange.new(rise * 0.9, rise * 1.4)
	tongues.SpreadAngle = Vector2.new(15, 15)
	tongues.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, flameSize * 0.9),
		NumberSequenceKeypoint.new(1, flameSize * 0.1),
	})
	tongues.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.6, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})

	-- A soft wide glow behind the whole flame
	local glow = bodyFlame("FlameGlow", body * 1.2, 1.6)
	glow:SetAttribute("AuraMinRate", 1)
	glow.LightEmission = 1
	glow.Brightness = 1
	glow.ZOffset = -1.5
	glow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.8),
		NumberSequenceKeypoint.new(0.7, 0.84),
		NumberSequenceKeypoint.new(1, 1),
	})
	height = body * 1.85

	-- The smoke curl drifting off the top (upright, from above the knife)
	local wisps = emitter(anchor, "FlameWisps", Art.Wisp, 1.2 + strength * 0.05, height * 0.55)
	wisps:SetAttribute("AuraMinRate", 0.8)
	wisps.LightEmission = 0.3
	wisps.ZOffset = -0.25
	wisps.LockedToPart = false
	wisps.Lifetime = NumberRange.new(1.6, 2)
	wisps.FlipbookFramerate = NumberRange.new(18, 22)
	wisps.Speed = NumberRange.new(height * 0.08, height * 0.14)
	wisps.SpreadAngle = Vector2.new(7, 7)
	shape(wisps, width * 0.3, height * 0.45 * motion.Curl, 0.38, 0.78)
	wisps.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.45),
		NumberSequenceKeypoint.new(0.6, 0.65),
		NumberSequenceKeypoint.new(1, 1),
	})

	-- Sparks off the blade
	local embers = sewn("FlameEmbers", 3 + strength * 0.4)
	embers.Texture = Art.Ember
	embers.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	embers:SetAttribute("AuraMinRate", 1.5)
	embers.LightEmission = 0.8
	embers.Lifetime = NumberRange.new(0.8, 1.2)
	embers.Speed = NumberRange.new(rise * 1.2, rise * 2)
	embers.SpreadAngle = Vector2.new(30, 30)
	embers.Rotation = NumberRange.new(-25, 25)
	embers.RotSpeed = NumberRange.new(-35, 35)
	local emberSize = math.min(0.3 + strength * 0.04, height * 0.2)
	embers.Size = NumberSequence.new(emberSize, math.min(0.06, emberSize))
	embers.Transparency = NumberSequence.new(0.05, 1)

	local layers: { [string]: ParticleEmitter } = {
		Outer = outer,
		Core = core,
		Tongues = tongues,
		Smoke = wisps,
		Glow = glow,
		Embers = embers,
	}
	for role, effect in layers do
		local colors = recipe.Colors[role]
		effect:SetAttribute("AuraLayer", role)
		effect.Color = ColorSequence.new(colors.Start, colors.Finish)
		local frames = effect.FlipbookFramerate
		effect.FlipbookFramerate =
			NumberRange.new(math.min(30, frames.Min * motion.Tempo), math.min(30, frames.Max * motion.Tempo))
	end
	local light = Instance.new("PointLight")
	light.Name = "AuraGlow"
	light:SetAttribute("KnifeAuraOwned", true)
	light.Color = recipe.Colors.Glow.Start
	light.Range = 5 + strength * 0.65
	light.Brightness = 0.55 + strength * 0.045
	light.Shadows = false
	light.Parent = anchor
end

return KnifeAura
