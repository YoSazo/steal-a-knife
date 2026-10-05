--!strict
-- A lighting mood per biome, on your screen only: the haze, the sun's glare, bloom, light shafts,
-- colour grade, exposure and even where the sun sits follow your position, blending into the next
-- biome's look over the last stretch of each zone (Roblox has one sun; this is how the concept art's glow is faked). The plaza / vaults and the
-- Courtyard keep the base look the server sets up (MapService.buildLighting).
--
-- This is the one place the mood lives. Rounds get their own flat indoor profile; the Blood Moon's red
-- sky (client/Atmosphere) takes the Atmosphere over while it's up and hands it back through the
-- Hub* attributes this keeps current.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local player = Players.LocalPlayer

local ZoneLighting = {}

type Mood = {
	Density: number,
	Offset: number,
	Color: Color3,
	Decay: Color3,
	Glare: number,
	Haze: number,
	Bloom: { Intensity: number, Size: number, Threshold: number },
	Rays: { Intensity: number, Spread: number },
	Grade: { Brightness: number, Contrast: number, Saturation: number, Tint: Color3 },
	Exposure: number,
	Clock: number, -- ClockTime + GeographicLatitude place the sun
	Latitude: number,
	Stars: number, -- stars in the sky (0 by day; Outer Space is night)
	Moon: number, -- the moon's size in the sky (0 = hidden)
}

local rgb = Color3.fromRGB

-- The base: what the server sets (MapService.buildLighting). The cyan haze everything grew from.
local BASE: Mood = {
	Density = 0.32,
	Offset = 0.25,
	Color = rgb(199, 236, 255),
	Decay = rgb(92, 196, 230),
	Glare = 4,
	Haze = 2,
	Bloom = { Intensity = 1, Size = 56, Threshold = 1.6 },
	Rays = { Intensity = 0.28, Spread = 0.85 },
	Grade = { Brightness = 0, Contrast = 0.1, Saturation = 0.12, Tint = rgb(255, 253, 248) },
	Exposure = 0,
	Clock = 13.5,
	Latitude = 3,
	Stars = 0,
	Moon = 0,
}

local function mood(changes: { [string]: any }): Mood
	local out = table.clone(BASE) :: any
	for key, value in changes do
		out[key] = value
	end
	return out
end

-- Sun straight ahead as you run deeper, ~44 degrees up (found with Lighting:GetSunDirection)
local SUN_AHEAD = { Clock = 12, Latitude = 70 }

ZoneLighting.Moods = {
	[1] = BASE, -- Courtyard: the cyan water already glows under the base look
	-- Gardens: soft, bright and a touch warmer, the greens a little richer
	[2] = mood({
		Color = rgb(222, 246, 232),
		Decay = rgb(120, 206, 178),
		Haze = 2.2,
		Bloom = { Intensity = 1, Size = 56, Threshold = 1.5 },
		Grade = { Brightness = 0.02, Contrast = 0.1, Saturation = 0.16, Tint = rgb(255, 251, 240) },
		Exposure = 0.05,
	}),
	-- Crypts: cool and misty but still bright (no horror): pale lavender-blue haze
	[3] = mood({
		Density = 0.33,
		Color = rgb(218, 226, 255),
		Decay = rgb(124, 142, 222),
		Haze = 2.2,
		Glare = 3,
		Grade = { Brightness = 0.02, Contrast = 0.12, Saturation = 0.06, Tint = rgb(246, 248, 255) },
	}),
	-- Catacombs: Leo the Collector's treasure: warm amber glow in the dust
	[4] = mood({
		Density = 0.32,
		Color = rgb(246, 232, 204),
		Decay = rgb(204, 162, 92),
		Haze = 2.1,
		Bloom = { Intensity = 1.1, Size = 56, Threshold = 1.4 },
		Grade = { Brightness = 0.02, Contrast = 0.11, Saturation = 0.14, Tint = rgb(255, 248, 234) },
	}),
	-- Inferno: an orange furnace haze (fixes it reading cold under the cyan)
	[5] = mood({
		Density = 0.29,
		Color = rgb(255, 224, 196),
		Decay = rgb(238, 142, 92),
		Glare = 3.5,
		Haze = 1.7,
		Bloom = { Intensity = 1.1, Size = 56, Threshold = 1.4 },
		Rays = { Intensity = 0.32, Spread = 0.85 },
		Grade = { Brightness = 0, Contrast = 0.12, Saturation = 0.14, Tint = rgb(255, 244, 232) },
	}),
	-- Mount Olympus: golden glare off the marble, the sun ahead over the temples
	[6] = mood({
		Density = 0.29,
		Color = rgb(255, 244, 214),
		Decay = rgb(232, 196, 120),
		Glare = 4,
		Haze = 1.8,
		Bloom = { Intensity = 1.1, Size = 58, Threshold = 1.4 },
		Rays = { Intensity = 0.36, Spread = 0.9 },
		Grade = { Brightness = 0.01, Contrast = 0.1, Saturation = 0.12, Tint = rgb(255, 250, 238) },
		Exposure = 0.04,
		Clock = SUN_AHEAD.Clock,
		Latitude = SUN_AHEAD.Latitude,
	}),
	-- The Heavens: the concept art: white-gold, overexposed, heavy bloom, light pouring in ahead
	[7] = mood({
		Density = 0.31,
		Color = rgb(255, 248, 238),
		Decay = rgb(238, 220, 232), -- a lavender blush, so the lavender and gold don't go blue
		Glare = 5,
		Haze = 2,
		Bloom = { Intensity = 1.25, Size = 60, Threshold = 1.3 },
		Rays = { Intensity = 0.42, Spread = 0.95 },
		Grade = { Brightness = 0.02, Contrast = 0.08, Saturation = 0.08, Tint = rgb(255, 252, 242) },
		Exposure = 0.1,
		Clock = SUN_AHEAD.Clock,
		Latitude = SUN_AHEAD.Latitude,
	}),
	-- Outer Space: MOONLIGHT. Walking in from the Heavens the sun sets over the last stretch (the
	-- clock runs on through 18:00 to midnight) and a big moon rises straight ahead over the runway,
	-- the violet haze glowing round it, stars above; the station's neon cyan and magenta pop
	-- against the night. (ClockTime 24 + latitude 80 puts the moon dead ahead, ~33 degrees up.)
	[8] = mood({
		Density = 0.32,
		Color = rgb(176, 152, 255),
		Decay = rgb(120, 76, 205),
		Glare = 4,
		Haze = 2.4,
		Bloom = { Intensity = 1.3, Size = 56, Threshold = 1.2 },
		Rays = { Intensity = 0.2, Spread = 0.85 },
		Grade = { Brightness = 0.02, Contrast = 0.12, Saturation = 0.2, Tint = rgb(240, 234, 255) },
		Exposure = 0.38,
		Clock = 24,
		Latitude = 80,
		Stars = 3000,
		Moon = 17,
	}),
} :: { [number]: Mood }

-- Rounds: indoors, flat and even (bloom low so the rooms don't glow)
local ROUND = mood({ Bloom = { Intensity = 0.25, Size = 56, Threshold = 1.6 } })

local function find(className: string): Instance?
	return Lighting:FindFirstChildOfClass(className)
end
-- The server's grade (not the round / raid / final-moment ones, which have names of their own)
local function grade(): ColorCorrectionEffect?
	for _, child in Lighting:GetChildren() do
		if child:IsA("ColorCorrectionEffect") and child.Name == "ColorCorrection" then
			return child
		end
	end
	return nil
end

-- How far before a zone's end its look starts blending into the next one (studs). Inside that
-- band the mood follows your position, stud by stud: no delay, no visible switch.
local BLEND = 60

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function mix(a: Mood, b: Mood, t: number): Mood
	if t <= 0 then
		return a
	elseif t >= 1 then
		return b
	end
	return {
		Density = lerp(a.Density, b.Density, t),
		Offset = lerp(a.Offset, b.Offset, t),
		Color = a.Color:Lerp(b.Color, t),
		Decay = a.Decay:Lerp(b.Decay, t),
		Glare = lerp(a.Glare, b.Glare, t),
		Haze = lerp(a.Haze, b.Haze, t),
		Bloom = {
			Intensity = lerp(a.Bloom.Intensity, b.Bloom.Intensity, t),
			Size = lerp(a.Bloom.Size, b.Bloom.Size, t),
			Threshold = lerp(a.Bloom.Threshold, b.Bloom.Threshold, t),
		},
		Rays = {
			Intensity = lerp(a.Rays.Intensity, b.Rays.Intensity, t),
			Spread = lerp(a.Rays.Spread, b.Rays.Spread, t),
		},
		Grade = {
			Brightness = lerp(a.Grade.Brightness, b.Grade.Brightness, t),
			Contrast = lerp(a.Grade.Contrast, b.Grade.Contrast, t),
			Saturation = lerp(a.Grade.Saturation, b.Grade.Saturation, t),
			Tint = a.Grade.Tint:Lerp(b.Grade.Tint, t),
		},
		Exposure = lerp(a.Exposure, b.Exposure, t),
		Clock = lerp(a.Clock, b.Clock, t),
		Stars = lerp(a.Stars, b.Stars, t),
		Moon = lerp(a.Moon, b.Moon, t),
		Latitude = lerp(a.Latitude, b.Latitude, t), -- the sun swings across the sky as you walk
	}
end

local function set(instance: Instance?, props: { [string]: any })
	if instance then
		for key, value in props do
			(instance :: any)[key] = value
		end
	end
end

local function apply(target: Mood)
	Lighting.ExposureCompensation = target.Exposure
	Lighting.ClockTime = target.Clock
	Lighting.GeographicLatitude = target.Latitude
	local sky = find("Sky") :: Sky?
	if sky then
		sky.StarCount = math.floor(target.Stars)
		sky.MoonAngularSize = target.Moon
	end
	local atmosphere = find("Atmosphere")
	if atmosphere then
		-- Where the Blood Moon's sky returns to when it sets
		atmosphere:SetAttribute("HubColor", target.Color)
		atmosphere:SetAttribute("HubDecay", target.Decay)
		atmosphere:SetAttribute("HubGlare", target.Glare)
		atmosphere:SetAttribute("HubHaze", target.Haze)
		if not ReplicatedStorage:GetAttribute("Raid") or player:GetAttribute("InRound") then
			set(atmosphere, {
				Density = target.Density,
				Offset = target.Offset,
				Color = target.Color,
				Decay = target.Decay,
				Glare = target.Glare,
				Haze = target.Haze,
			})
		end
	end
	set(find("BloomEffect"), target.Bloom)
	set(find("SunRaysEffect"), target.Rays)
	set(grade(), {
		Brightness = target.Grade.Brightness,
		Contrast = target.Grade.Contrast,
		Saturation = target.Grade.Saturation,
		TintColor = target.Grade.Tint,
	})
end

function ZoneLighting.MoodFor(zone: number): Mood
	if zone < 0 then
		return ROUND
	end
	return ZoneLighting.Moods[zone] or BASE
end

-- The mood right here: a round's, the plaza's, or a zone's - blended into the next zone's over
-- the last BLEND studs before it (and the plaza into the Courtyard, which share a look anyway)
local function moodHere(): (Mood, number)
	if player:GetAttribute("InRound") then
		return ROUND, -1
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return BASE, 0
	end
	local pos = root.Position
	if math.abs(pos.X) > GameConfig.ArenaWidth / 2 + 4 or pos.Z < 0 then
		return BASE, 0
	end
	local depth = GameConfig.ZoneDepth
	local zones = #GameConfig.Zones
	local zone = math.clamp(math.floor(pos.Z / depth) + 1, 1, zones)
	local here = ZoneLighting.MoodFor(zone)
	if zone >= zones then
		return here, zone
	end
	local intoNext = (pos.Z - (zone * depth - BLEND)) / BLEND
	-- smoothstep: eases in and out of the band
	local t = math.clamp(intoNext, 0, 1)
	t = t * t * (3 - 2 * t)
	return mix(here, ZoneLighting.MoodFor(zone + 1), t), zone + t
end

function ZoneLighting.Init()
	task.spawn(function()
		-- The server builds the lighting a moment after we start
		while not find("Atmosphere") or not grade() do
			task.wait(0.5)
		end
		-- Every frame, so the blend moves with you exactly; nothing is touched while the key (zone +
		-- how far into the blend) stays the same, e.g. standing still or walking inside one zone
		local lastKey: number? = nil
		RunService.RenderStepped:Connect(function()
			local here, key = moodHere()
			if key ~= lastKey or ReplicatedStorage:GetAttribute("Raid") == true then
				lastKey = key
				apply(here)
			end
		end)
	end)
end

return ZoneLighting
