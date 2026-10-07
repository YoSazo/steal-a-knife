--!strict
-- The aura sprites (Config/Textures.AuraSprites) dressed onto Codex's biome shells
-- (MapService.BuildBiomeShells): sparkles on water, embers and smoke off the lava, twinkles on gems
-- and lights, slow god-rays behind the big lights, mist off the Heavens' cloud channels, crackles
-- over Outer Space's portal. Picked by part name (the shells are generated, the names are stable),
-- biggest parts first, a budget per rule so a biome never carries hundreds of emitters. Particles
-- only; client/Lod switches far ones off.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Textures = require(ReplicatedStorage.Shared.Config.Textures)

local BiomeSprites = {}

local PARTICLE_MAX = 20 -- (Roblox draws nothing bigger)

type Rule = {
	Match: (name: string, part: BasePart) -> boolean,
	Budget: number,
	Dress: (part: BasePart) -> (),
}

local function seq(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

local function has(name: string, words: { string }): boolean
	for _, word in words do
		if name:find(word, 1, true) then
			return true
		end
	end
	return false
end

-- The area of a part's biggest face (how much room it has for particles)
local function area(part: BasePart): number
	local s = part.Size
	return math.max(s.X * s.Z, s.X * s.Y, s.Y * s.Z)
end

local function emitter(part: BasePart, name: string, props: { [string]: any })
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.LightInfluence = 0
	e.LightEmission = 0.5
	e.Speed = NumberRange.new(0)
	e.Rotation = NumberRange.new(0, 360)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = part
end

-- (more particles on a bigger surface, within limits)
local function rate(part: BasePart, perArea: number, low: number, high: number): number
	return math.clamp(area(part) * perArea, low, high)
end

local function tintOf(part: BasePart, toWhite: number): Color3
	return part.Color:Lerp(Color3.new(1, 1, 1), toWhite)
end

local function sparkle(part: BasePart, size: number, perArea: number, high: number)
	emitter(part, "SpriteSparkle", {
		Texture = Textures.AuraSprites.Star.Id,
		Color = ColorSequence.new(Color3.new(1, 1, 1), tintOf(part, 0.4)),
		Rate = rate(part, perArea, 0.4, high),
		Lifetime = NumberRange.new(0.6, 1.1),
		Size = seq({ { 0, 0 }, { 0.35, size }, { 1, 0 } }),
		Transparency = seq({ { 0, 0.1 }, { 1, 0.7 } }),
		RotSpeed = NumberRange.new(-60, 60),
		Brightness = 1.4,
	})
end

local RULES: { Rule } = {
	-- Water (Gardens' ponds, the Crypts' and Catacombs' channels): glints dancing on the surface
	{
		Match = function(name)
			return has(name, { "water", "pond" }) and not name:find("rim", 1, true)
		end,
		Budget = 8,
		Dress = function(part)
			sparkle(part, 1.6, 0.05, 6)
		end,
	},
	-- Lava (the Inferno's channels, basin and fissures): flame tongues rising, a little dark smoke
	{
		Match = function(name)
			return has(name, { "lavachannelbed", "lavabasin", "lavafissure", "basinember" })
		end,
		Budget = 22,
		Dress = function(part)
			emitter(part, "SpriteEmbers", {
				Texture = Textures.AuraSprites.Ember.Id,
				FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2,
				FlipbookMode = Enum.ParticleFlipbookMode.Loop,
				FlipbookFramerate = NumberRange.new(8, 8),
				Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 90, 30)),
				Rate = rate(part, 0.1, 3, 45),
				Lifetime = NumberRange.new(1, 1.8),
				Speed = NumberRange.new(4, 8),
				EmissionDirection = Enum.NormalId.Top,
				ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
				Acceleration = Vector3.new(0, 2, 0),
				Size = seq({ { 0, 3.4 }, { 1, 0.4 } }),
				Transparency = seq({ { 0, 0.1 }, { 1, 1 } }),
				Rotation = NumberRange.new(-10, 10),
				Brightness = 1.6,
			})
			emitter(part, "SpriteSmoke", {
				Texture = Textures.AuraSprites.SmokeWisp.Id,
				FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
				FlipbookMode = Enum.ParticleFlipbookMode.Loop,
				FlipbookFramerate = NumberRange.new(8, 8),
				Color = ColorSequence.new(Color3.fromRGB(70, 40, 40)),
				LightEmission = 0,
				Rate = rate(part, 0.01, 0.4, 3),
				Lifetime = NumberRange.new(2.5, 3.5),
				Speed = NumberRange.new(2, 4),
				EmissionDirection = Enum.NormalId.Top,
				ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
				Size = seq({ { 0, 3 }, { 1, 7 } }),
				Transparency = seq({ { 0, 1 }, { 0.2, 0.55 }, { 1, 1 } }),
				Brightness = 1,
			})
		end,
	},
	-- Hot ember cores in the forge walls: a few embers drifting up
	{
		Match = function(name)
			return has(name, { "hotcore", "embercore" })
		end,
		Budget = 12,
		Dress = function(part)
			emitter(part, "SpriteEmbers", {
				Texture = Textures.AuraSprites.Ember.Id,
				FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2,
				FlipbookMode = Enum.ParticleFlipbookMode.Loop,
				FlipbookFramerate = NumberRange.new(8, 8),
				Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 80, 30)),
				Rate = 0.8,
				Lifetime = NumberRange.new(0.8, 1.3),
				Speed = NumberRange.new(2, 4),
				EmissionDirection = Enum.NormalId.Top,
				Size = seq({ { 0, 0.9 }, { 1, 0.1 } }),
				Transparency = seq({ { 0, 0.1 }, { 1, 1 } }),
				Rotation = NumberRange.new(-10, 10),
				Brightness = 1.6,
			})
		end,
	},
	-- Gems and lenses (Crypts, Catacombs): the odd twinkle
	{
		Match = function(name)
			return has(name, { "gemgem", "lensglint", "inlaidgem", "inlaidteal", "gemcentre", "gemcrest" })
		end,
		Budget = 20,
		Dress = function(part)
			sparkle(part, 1.5, 0.05, 0.6)
		end,
	},
	-- Space crystals: twinkles and the occasional shard flicking off
	{
		Match = function(name, part)
			return part.Material == Enum.Material.Neon and has(name, { "crystal" })
		end,
		Budget = 16,
		Dress = function(part)
			sparkle(part, 1.4, 0.1, 0.8)
			emitter(part, "SpriteShards", {
				Texture = Textures.AuraSprites.LightningShard.Id,
				Color = ColorSequence.new(Color3.new(1, 1, 1), tintOf(part, 0.2)),
				Rate = 0.3,
				Lifetime = NumberRange.new(0.5, 0.8),
				Speed = NumberRange.new(4, 7),
				SpreadAngle = Vector2.new(60, 60),
				EmissionDirection = Enum.NormalId.Top,
				Size = seq({ { 0, 1.4 }, { 1, 0 } }),
				Transparency = seq({ { 0, 0 }, { 1, 0.8 } }),
				Brightness = 1.6,
			})
		end,
	},
	-- Outer Space's portal: lightning crackling over the energy surface
	{
		Match = function(name)
			return has(name, { "portalbasinenergysurface" })
		end,
		Budget = 1,
		Dress = function(part)
			emitter(part, "SpriteBolts", {
				Texture = Textures.AuraSprites.LightningBolt.Id,
				FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
				FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
				Color = ColorSequence.new(Color3.new(1, 1, 1), tintOf(part, 0.3)),
				Rate = 1.2,
				Lifetime = NumberRange.new(1.4, 1.4),
				Size = seq({ { 0, 9 }, { 1, 9 } }),
				Transparency = seq({ { 0, 0 }, { 1, 0 } }),
				Brightness = 1.8,
			})
			sparkle(part, 2, 0.01, 4)
		end,
	},
	-- The Heavens' cloud channels: soft white mist curling off them
	{
		Match = function(name)
			return has(name, { "cloudchannelwhitecore" })
		end,
		Budget = 4,
		Dress = function(part)
			emitter(part, "SpriteMist", {
				Texture = Textures.AuraSprites.SmokeWisp.Id,
				FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
				FlipbookMode = Enum.ParticleFlipbookMode.Loop,
				FlipbookFramerate = NumberRange.new(6, 6),
				Color = ColorSequence.new(Color3.fromRGB(255, 250, 240)),
				LightEmission = 0.2,
				Rate = rate(part, 0.004, 0.5, 3),
				Lifetime = NumberRange.new(3, 4),
				Speed = NumberRange.new(0.5, 1.5),
				EmissionDirection = Enum.NormalId.Top,
				Size = seq({ { 0, 4 }, { 1, 9 } }),
				Transparency = seq({ { 0, 1 }, { 0.3, 0.6 }, { 1, 1 } }),
				Brightness = 1,
			})
		end,
	},
	-- Lights (glowing neon: suns, halos, light cores, pouring light): twinkles, and slow god-rays
	-- turning behind the biggest
	{
		Match = function(name, part)
			return part.Material == Enum.Material.Neon
				and has(name, { "light", "sun", "halo", "glow", "shimmer", "core", "pouring", "falling", "star" })
				and not has(name, { "voxelstar" }) -- (hundreds of tiny ones)
		end,
		Budget = 30,
		Dress = function(part)
			sparkle(part, 1.5, 0.04, 1.5)
			local big = math.max(part.Size.X, part.Size.Y, part.Size.Z)
			if big >= 4 then
				emitter(part, "SpriteRays", {
					Texture = Textures.AuraSprites.LightRays.Id,
					Color = ColorSequence.new(tintOf(part, 0.5)),
					Rate = 0.4,
					Lifetime = NumberRange.new(5, 6),
					ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
					Size = seq({ { 0, math.min(big * 1.2, PARTICLE_MAX) }, { 1, math.min(big * 1.5, PARTICLE_MAX) } }),
					Transparency = seq({ { 0, 1 }, { 0.3, 0.75 }, { 0.7, 0.8 }, { 1, 1 } }),
					RotSpeed = NumberRange.new(8, 14),
					Brightness = 1.1,
					LightEmission = 0.4,
					ZOffset = -2,
				})
			end
		end,
	},
}

-- Dresses one biome shell (call once, after it's built)
function BiomeSprites.Dress(shell: Instance)
	local picked: { { BasePart } } = {}
	for i in RULES do
		picked[i] = {}
	end
	for _, part in shell:GetDescendants() do
		if not part:IsA("BasePart") or part.Transparency >= 1 then
			continue
		end
		local name = part.Name:lower()
		if name:find("clamp", 1, true) then
			continue
		end
		for i, rule in RULES do
			if rule.Match(name, part) then
				table.insert(picked[i], part)
				break
			end
		end
	end
	for i, rule in RULES do
		local parts = picked[i]
		table.sort(parts, function(a, b)
			return area(a) > area(b)
		end)
		for n = 1, math.min(rule.Budget, #parts) do
			rule.Dress(parts[n])
		end
	end
end

return BiomeSprites
