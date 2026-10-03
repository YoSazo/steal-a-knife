--!strict
-- Level of detail for weak devices. The world has hundreds of lights and dozens of particle
-- effects (vault chandeliers, sconces, knife auras, guard lanterns, biome props); a phone can't
-- light all of them. Every few frames this works through a slice of them and only keeps on:
--   * lights within LightRange of the camera, the closest LightBudget of them
--   * particles / fire / sparkles within ParticleRange
-- Phones (and the lowest graphics levels) get tighter numbers and no bloom. Anything another
-- script turns off stays off: LOD only ever switches off what was on, and puts it back as it was.
--
-- Lod.Near(position, range) is the shared distance check other client loops use to skip work
-- on things nobody can see (Moves, Effects spinners).

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Lod = {}

type Profile = { LightRange: number, LightBudget: number, ParticleRange: number, AnimRange: number }

local PROFILES: { [string]: Profile } = {
	High = { LightRange = 160, LightBudget = 64, ParticleRange = 180, AnimRange = 220 },
	Medium = { LightRange = 110, LightBudget = 36, ParticleRange = 120, AnimRange = 150 },
	Low = { LightRange = 70, LightBudget = 18, ParticleRange = 75, AnimRange = 100 },
}

local profile: Profile = PROFILES.High
Lod.Profile = "High"

local lights: { [Light]: boolean } = {} -- tracked lights -> currently culled by us
local effects: { [Instance]: boolean } = {} -- ParticleEmitter / Fire / Sparkles / Smoke
local lightList: { Light } = {}
local effectList: { Instance } = {}
local dirty = true

-- (Studio: ReplicatedStorage DebugPhone = true previews the phone profile, like Ui.Phone)
local function phone(): boolean
	return (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
		or (RunService:IsStudio() and game:GetService("ReplicatedStorage"):GetAttribute("DebugPhone") == true)
end

local applyStars: (ParticleEmitter) -> ()
local applyKnifeAura: (ParticleEmitter) -> ()

-- The graphics slider (1-10; 0 = automatic) decides the profile; phones never go above Medium
local function pickProfile()
	local level = 0
	pcall(function()
		level = UserSettings().GameSettings.SavedQualityLevel.Value
	end)
	local name
	if level == 0 then
		name = if phone() then "Low" else "High"
	elseif level <= 3 then
		name = "Low"
	elseif level <= 6 then
		name = "Medium"
	else
		name = "High"
	end
	if phone() and name == "High" then
		name = "Medium"
	end
	if name ~= Lod.Profile then
		Lod.Profile = name
	end
	profile = PROFILES[name]
	for _, part in game:GetService("CollectionService"):GetTagged("StarField") do
		local emitter = part:FindFirstChildOfClass("ParticleEmitter")
		if emitter then
			applyStars(emitter)
		end
	end
	for _, effect in game:GetService("CollectionService"):GetTagged("KnifeAuraEmitter") do
		if effect:IsA("ParticleEmitter") then
			applyKnifeAura(effect)
		end
	end
	-- Bloom is a full-screen pass: skip it on low settings
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		bloom.Enabled = name ~= "Low"
	end
end

local function positionOf(instance: Instance): Vector3?
	local parent = instance.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return nil
end

local function isEffect(instance: Instance): boolean
	return instance:IsA("ParticleEmitter") or instance:IsA("Fire") or instance:IsA("Sparkles") or instance:IsA("Smoke")
end

-- Star fields (tag "StarField" on the emitter's part) are seen from everywhere: instead of being
-- culled by distance, their density follows the profile
local STAR_DENSITY: { [string]: number } = { High = 1, Medium = 0.55, Low = 0.25 }
local AURA_DENSITY: { [string]: number } = { High = 1, Medium = 0.65, Low = 0.35 }
applyKnifeAura = function(emitter: ParticleEmitter)
	local rate = emitter:GetAttribute("BaseRate")
	if type(rate) == "number" then
		local minimum = emitter:GetAttribute("AuraMinRate")
		local floor = if type(minimum) == "number" then minimum else 0
		emitter.Rate = math.min(rate, math.max(floor, rate * AURA_DENSITY[Lod.Profile]))
	end
end
local function isStarField(instance: Instance): boolean
	local parent = instance.Parent
	return parent ~= nil and game:GetService("CollectionService"):HasTag(parent, "StarField")
end
applyStars = function(emitter: ParticleEmitter)
	local base = emitter:GetAttribute("BaseRate")
	if type(base) ~= "number" then
		base = emitter.Rate
		emitter:SetAttribute("BaseRate", base)
	end
	emitter.Rate = (base :: number) * (STAR_DENSITY[Lod.Profile] or 1)
	-- Fill the sky straight away instead of over the first half minute (once per emitter)
	if not emitter:GetAttribute("Filled") then
		emitter:SetAttribute("Filled", true)
		task.defer(function()
			emitter:Emit(math.floor(emitter.Rate * emitter.Lifetime.Max * 0.8))
		end)
	end
end

local function add(instance: Instance)
	if instance:IsA("ParticleEmitter") and instance:HasTag("KnifeAuraEmitter") then
		applyKnifeAura(instance)
	end
	if instance:IsA("ParticleEmitter") and isStarField(instance) then
		applyStars(instance)
		return
	end
	if instance:IsA("Light") then
		if lights[instance] == nil then
			lights[instance] = false
			dirty = true
		end
	elseif isEffect(instance) then
		if effects[instance] == nil then
			effects[instance] = false
			dirty = true
		end
	end
end

local function remove(instance: Instance)
	if lights[instance :: any] ~= nil then
		lights[instance :: any] = nil
		dirty = true
	elseif effects[instance] ~= nil then
		effects[instance] = nil
		dirty = true
	end
end

local function rebuildLists()
	table.clear(lightList)
	for light in lights do
		table.insert(lightList, light)
	end
	table.clear(effectList)
	for effect in effects do
		table.insert(effectList, effect)
	end
	dirty = false
end

-- Turn something off for LOD (remembering it was on), or back on if LOD turned it off
local function setCulled(instance: Instance, culled: boolean, map: { [any]: boolean })
	local was = map[instance]
	if culled and not was then
		if (instance :: any).Enabled then
			(instance :: any).Enabled = false
			map[instance] = true
		end
	elseif not culled and was then
		(instance :: any).Enabled = true
		map[instance] = false
	end
end

local cameraPosition = Vector3.zero

-- Shared cheap check for other client loops: is `position` close enough to be worth animating?
function Lod.Near(position: Vector3, range: number?): boolean
	return (position - cameraPosition).Magnitude <= (range or profile.AnimRange)
end

function Lod.AnimRange(): number
	return profile.AnimRange
end

-- Lights: everything in range, then only the closest LightBudget of those
local scored: { { Light: Light, Distance: number } } = {}
local function updateLights()
	table.clear(scored)
	local range = profile.LightRange
	for _, light in lightList do
		local position = positionOf(light)
		if not position or not light.Parent then
			continue
		end
		local distance = (position - cameraPosition).Magnitude
		if distance <= range then
			table.insert(scored, { Light = light, Distance = distance })
		else
			setCulled(light, true, lights)
		end
	end
	table.sort(scored, function(a, b)
		return a.Distance < b.Distance
	end)
	for i, entry in scored do
		setCulled(entry.Light, i > profile.LightBudget, lights)
	end
end

local function updateEffects()
	local range = profile.ParticleRange
	for _, effect in effectList do
		local position = positionOf(effect)
		if position and effect.Parent then
			setCulled(effect, (position - cameraPosition).Magnitude > range, effects)
		end
	end
end

function Lod.Init()
	pickProfile()
	pcall(function()
		UserSettings().GameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(pickProfile)
	end)
	for _, d in workspace:GetDescendants() do
		add(d)
	end
	workspace.DescendantAdded:Connect(add)
	workspace.DescendantRemoving:Connect(remove)

	-- Lights and effects alternate, a few times a second: plenty for things that only change as
	-- you walk, and nearly free per frame
	local timer = 0
	local turn = false
	RunService.Heartbeat:Connect(function(dt: number)
		cameraPosition = workspace.CurrentCamera.CFrame.Position
		timer += dt
		if timer < 0.2 then
			return
		end
		timer = 0
		if dirty then
			rebuildLists()
		end
		turn = not turn
		if turn then
			updateLights()
		else
			updateEffects()
		end
	end)
end

return Lod
