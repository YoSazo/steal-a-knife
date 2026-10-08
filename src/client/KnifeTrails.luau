--!strict
-- Running fast should *feel* fast (Steal An Egg style), on this client:
--   * knife trails: anyone with a trail (attribute TrailLevel, or the Phantom Trail pass) sheds a
--     stream of their trail's knife as they run - spinning, glowing in the trail colour, fading out.
--     The faster they go, the thicker the stream. Hidden in rounds (disguises stay anonymous).
--   * for you: the camera widens with your speed, speed lines streak in from the screen edges,
--     the wind gets louder and your feet kick up dust.
-- Purely cosmetic; speed itself is the server's (BaseService.RefreshWalkSpeed).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Ui = require(script.Parent.Ui)
local Lod = require(script.Parent.Lod)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local KnifeModel = require(Shared:WaitForChild("KnifeModel"))
local Sounds = require(Shared.Config:WaitForChild("Sounds"))
local player = Players.LocalPlayer
local new = Ui.new

local KnifeTrails = {}

local BASE_FOV = 70
local MAX_EXTRA_FOV = 24
local KNIFE_LENGTH = 3
local LIFE = 0.55
local MAX_PER_PLAYER = if Ui.Phone then 12 else 24 -- phones get a lighter stream
local VIEW_DISTANCE = if Ui.Phone then 120 else 170

type Trail = { Knife: string, Color: Color3 }
type Flying = { Model: Model, Parts: { BasePart }, Born: number, Spin: Vector3, Drift: Vector3, Base: CFrame }

local templates: { [string]: Model } = {}
local flying: { [Player]: { Flying } } = {}
local lastSpawn: { [Player]: number } = {}
local folder: Folder

-- The trail a player shows, if any
local function trailOf(other: Player): Trail?
	if other:GetAttribute("InRound") then
		return nil
	end
	if other:GetAttribute("Pass_PhantomTrail") then
		return GameConfig.PhantomTrail
	end
	local level = other:GetAttribute("TrailLevel")
	local trail = if type(level) == "number" then GameConfig.Trails[level] else nil
	return trail
end

-- A small glowing copy of a knife, built once per kind and cloned after that
local function template(knife: string, color: Color3): Model
	local key = knife .. color:ToHex()
	local cached = templates[key]
	if cached then
		return cached
	end
	local model = KnifeModel.Build(knife, false)
	KnifeModel.FitLength(model, KNIFE_LENGTH)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Massless = true
		elseif d:IsA("Script") or d:IsA("Sound") or d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		end
	end
	-- Every knife in the stream leaves a short streak in the trail's colour (Highlights would be
	-- simpler, but Roblox only draws ~31 of those at once)
	local _, size = model:GetBoundingBox()
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if anchor then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, size.Y * 0.4, 0)
		a0.Parent = anchor
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -size.Y * 0.4, 0)
		a1.Parent = anchor
		local streak = Instance.new("Trail")
		streak.Attachment0 = a0
		streak.Attachment1 = a1
		streak.Color = ColorSequence.new(color)
		streak.LightEmission = 1
		streak.LightInfluence = 0
		streak.Lifetime = 0.18
		streak.Transparency = NumberSequence.new(0.3, 1)
		streak.Parent = anchor
	end
	templates[key] = model
	return model
end

local function spawnKnife(other: Player, root: BasePart, velocity: Vector3, trail: Trail)
	local list = flying[other] or {}
	flying[other] = list
	if #list >= MAX_PER_PLAYER then
		return
	end
	local rng = Random.new()
	local back = -velocity.Unit
	local side = back:Cross(Vector3.yAxis)
	local at = root.Position
		+ back * rng:NextNumber(1.5, 3)
		+ side * rng:NextNumber(-1.4, 1.4)
		+ Vector3.new(0, rng:NextNumber(-1.6, 1.2), 0)
	local model = template(trail.Knife, trail.Color):Clone()
	local base = CFrame.lookAt(at, at + velocity) * CFrame.Angles(math.rad(rng:NextNumber(-60, 60)), 0, math.rad(90))
	model:PivotTo(base)
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	model.Parent = folder
	table.insert(list, {
		Model = model,
		Parts = parts,
		Born = os.clock(),
		Spin = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-14, 14), rng:NextNumber(-8, 8)), -- rad/s
		Drift = back * rng:NextNumber(2, 5) + Vector3.new(0, rng:NextNumber(0.5, 2.5), 0),
		Base = base,
	})
end

local function stepTrails(now: number)
	local camera = workspace.CurrentCamera
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local trail = trailOf(other)
		if root and trail and camera and (root.Position - camera.CFrame.Position).Magnitude < VIEW_DISTANCE then
			local velocity = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
			local speed = velocity.Magnitude
			if speed > 14 then
				-- Faster = more knives (one every ~0.1s at a jog, every ~0.025s flat out)
				local interval = math.clamp(2.2 / speed, 0.025, 0.1)
				-- Weaker devices (LOD profile) get a thinner stream, and other people's trails thinner still
				local fewest = if Lod.Profile == "Low" then 0.09 elseif Lod.Profile == "Medium" then 0.05 else 0.025
				interval = math.max(interval, if other == Players.LocalPlayer then fewest else fewest * 1.6)
				local live = flying[other]
				local cap = if Lod.Profile == "Low" then 8 elseif Lod.Profile == "Medium" then 14 else 30
				if live and #live >= cap then
					continue
				end
				if now - (lastSpawn[other] or 0) >= interval then
					lastSpawn[other] = now
					spawnKnife(other, root, velocity, trail)
				end
			end
		end
	end
	-- Animate and retire
	for other, list in flying do
		for i = #list, 1, -1 do
			local f = list[i]
			local t = (now - f.Born) / LIFE
			if t >= 1 or not f.Model.Parent then
				f.Model:Destroy()
				table.remove(list, i)
				continue
			end
			local age = now - f.Born
			local spin = f.Spin * age
			f.Model:PivotTo(CFrame.new(f.Drift * age) * f.Base * CFrame.Angles(spin.X, spin.Y, spin.Z))
			local fade = t * t
			for _, p in f.Parts do
				p.LocalTransparencyModifier = fade
			end
		end
		if #list == 0 and not other.Parent then
			flying[other] = nil
		end
	end
end

-- Your own speed: camera, lines, wind, dust ------------------------------------------------------

function KnifeTrails.Init()
	folder = Instance.new("Folder")
	folder.Name = "KnifeTrailFx"
	folder.Parent = workspace

	local gui = new("ScreenGui", {
		Name = "SpeedLines",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 1,
	}, player:WaitForChild("PlayerGui"))
	-- Thin white streaks pointing at the middle of the screen from all round the edge
	local lines: { { Frame: Frame, Angle: number, Phase: number } } = {}
	local rng = Random.new()
	for i = 1, 26 do
		local angle = (i / 26) * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local line = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(rng:NextInteger(90, 200), 2),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Rotation = math.deg(angle),
		}, gui)
		table.insert(lines, { Frame = line, Angle = angle, Phase = rng:NextNumber(0, 1) })
	end

	local wind = Instance.new("Sound")
	wind.SoundId = Sounds.Wind
	wind.Looped = true
	wind.Volume = 0
	wind.Parent = SoundService
	wind:Play()

	-- Dust at your feet (a fresh emitter for every character: the old one dies with it)
	local dustTemplate = Instance.new("ParticleEmitter")
	local dust = dustTemplate
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(200, 190, 175))
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.4) })
	dust.Lifetime = NumberRange.new(0.4, 0.7)
	dust.Speed = NumberRange.new(1, 3)
	dust.SpreadAngle = Vector2.new(40, 40)
	dust.Rate = 0
	local function attachDust(character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		if root then
			local at = Instance.new("Attachment")
			at.Name = "DustAt"
			at.Position = Vector3.new(0, -2.8, 0.6)
			at.Parent = root
			dust = dustTemplate:Clone()
			dust.Parent = at
		end
	end
	if player.Character then
		task.spawn(attachDust, player.Character)
	end
	player.CharacterAdded:Connect(attachDust)

	local fovNow = BASE_FOV
	local linesHidden = false
	RunService.RenderStepped:Connect(function(dt: number)
		local now = os.clock()
		stepTrails(now)

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local speed = if root then (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude else 0
		local inRound = player:GetAttribute("InRound") == true
		-- 0 at a normal jog, 1 flat out
		local rush = if inRound then 0 else math.clamp((speed - 20) / (GameConfig.MaxWalkSpeed - 20), 0, 1)
		-- Running on your wheel counts too (you're standing still, but you're SPRINTING): the
		-- better the wheel, the harder the lines, wind, dust and camera go
		if player:GetAttribute("Training") and not inRound then
			local level = (player:GetAttribute("TreadmillLevel") or 1) :: number
			rush = math.max(rush, 0.35 + 0.65 * math.clamp((level - 1) / 12, 0, 1))
		end

		-- Camera: wider the faster you go (left alone while something else is steering the FOV:
		-- aiming a throw, or being pulled by a knife aura)
		local camera = workspace.CurrentCamera
		local busy = (character and character:GetAttribute("ChargeStart") ~= nil)
		if camera and not busy then
			local target = BASE_FOV + MAX_EXTRA_FOV * rush
			fovNow += (target - fovNow) * math.min(1, dt * 4)
			if math.abs(camera.FieldOfView - fovNow) > 0.05 then
				camera.FieldOfView = fovNow
			end
		elseif camera then
			fovNow = camera.FieldOfView
		end

		-- Speed lines from the edges (nothing to move while they're all hidden)
		if rush <= 0.25 and linesHidden then
			wind.Volume = 0
			dust.Rate = 0
			return
		end
		linesHidden = rush <= 0.25
		local size = gui.AbsoluteSize
		local radius = math.max(size.X, size.Y) * 0.5
		for _, l in lines do
			local phase = (now * 2.6 + l.Phase) % 1
			local dist = radius * (1.05 - phase * 0.35)
			l.Frame.Position = UDim2.new(0.5, math.cos(l.Angle) * dist, 0.5, math.sin(l.Angle) * dist)
			l.Frame.BackgroundTransparency = if rush > 0.25 then 1 - (rush - 0.25) * 0.75 * (1 - phase) else 1
		end

		wind.Volume = 0.6 * rush
		wind.PlaybackSpeed = 0.9 + 0.3 * rush
		dust.Rate = if rush > 0.1 and root then 30 * rush else 0
	end)
end

return KnifeTrails
