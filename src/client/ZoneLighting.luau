--!strict
-- Keeps the hub's one look (MapService.buildLighting) on your screen: the same grade, exposure and
-- sun everywhere - the plaza, every biome and the round maps. (It used to blend a different mood per
-- biome; that changed the whole feel the moment you walked into the first one.)
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

-- The one look (MapService.buildLighting): the same on the plaza and in every biome. Only the grade,
-- exposure and sun position are ours to set; there's no Atmosphere, bloom or sun rays any more.
local BASE: Mood = {
	Density = 0,
	Offset = 0,
	Color = rgb(255, 255, 255),
	Decay = rgb(255, 255, 255),
	Glare = 0,
	Haze = 0,
	Bloom = { Intensity = 0, Size = 0, Threshold = 0 },
	Rays = { Intensity = 0, Spread = 0 },
	Grade = { Brightness = 0.05, Contrast = 0.1, Saturation = 0.15, Tint = rgb(255, 255, 255) },
	Exposure = 0,
	Clock = 13.5,
	Latitude = 3,
	Stars = 0,
	Moon = 0,
}

ZoneLighting.Moods = {} :: { [number]: Mood }
for index in GameConfig.Zones do
	ZoneLighting.Moods[index] = BASE
end

-- Rounds: the same look (indoor maps set their own ambient: client/Effects)
local ROUND = BASE

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
		set(atmosphere, {
			Density = target.Density,
			Offset = target.Offset,
			Color = target.Color,
			Decay = target.Decay,
			Glare = target.Glare,
			Haze = target.Haze,
		})
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
	return ZoneLighting.Moods[zone] or ZoneLighting.Moods[1]
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
		return ZoneLighting.Moods[1], 0 -- (the plaza and pens)
	end
	local pos = root.Position
	if math.abs(pos.X) > GameConfig.ArenaWidth / 2 + 4 or pos.Z < 0 then
		return ZoneLighting.Moods[1], 0 -- (the plaza and pens)
	end
	local zones = #GameConfig.Zones
	local zone = GameConfig.ZoneAtZ(pos.Z) or zones -- preserve the last biome's mood at the Manor
	local here = ZoneLighting.MoodFor(zone)
	if zone >= zones then
		return here, zone
	end
	local intoNext = (pos.Z - (GameConfig.ZoneEnd(zone) - BLEND)) / BLEND
	-- smoothstep: eases in and out of the band
	local t = math.clamp(intoNext, 0, 1)
	t = t * t * (3 - 2 * t)
	return mix(here, ZoneLighting.MoodFor(zone + 1), t), zone + t
end

function ZoneLighting.Init()
	task.spawn(function()
		-- The server builds the lighting a moment after we start
		while not grade() do
			task.wait(0.5)
		end
		-- Every frame, so the blend moves with you exactly; nothing is touched while the key (zone +
		-- how far into the blend) stays the same, e.g. standing still or walking inside one zone
		local lastKey: number? = nil
		RunService.RenderStepped:Connect(function()
			local here, key = moodHere()
			if key ~= lastKey then
				lastKey = key
				apply(here)
			end
		end)
	end)
end

return ZoneLighting
