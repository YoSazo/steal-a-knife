--!strict
-- Cosmetic effects the server asks for through Remotes.Effect (sounds, particle bursts, bullet
-- tracers), plus local-only polish: spinning coins and pickups, and hiding other players' "Sell"
-- prompts on their racks. Nothing here affects gameplay.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Knives = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Knives"))
local Sounds = require(ReplicatedStorage.Shared.Config:WaitForChild("Sounds"))
local Props = require(ReplicatedStorage.Shared:WaitForChild("Props"))
local Format = require(ReplicatedStorage.Shared:WaitForChild("Format"))
local Items = require(ReplicatedStorage.Shared:WaitForChild("Items"))
local KnifeModel = require(ReplicatedStorage.Shared:WaitForChild("KnifeModel"))
local PenMode = require(ReplicatedStorage.Shared:WaitForChild("PenMode"))
local CoffinModel = require(ReplicatedStorage.Shared:WaitForChild("CoffinModel"))
local Lod = require(script.Parent.Lod)
local TopLine = require(script.Parent.TopLine)
local Ui = require(script.Parent.Ui)
local WorldSignInput = require(script.Parent.WorldSignInput)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local Effects = {}

local function anchorAt(position: Vector3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.Position = position
	p.Parent = workspace
	Debris:AddItem(p, 4)
	return p
end

-- 2D sound (UI) when position is nil, otherwise a 3D sound at that spot
function Effects.Sound(id: string, position: Vector3?, volume: number?)
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 0.7
	if position then
		sound.RollOffMaxDistance = 120
		sound.Parent = anchorAt(position)
		sound:Play()
	else
		SoundService:PlayLocalSound(sound)
		sound.Parent = SoundService
		Debris:AddItem(sound, 4)
	end
end

function Effects.Burst(position: Vector3, color: Color3, count: number, speed: number?, size: number?)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.4
	emitter.Size = NumberSequence.new(size or 0.6, 0)
	emitter.Speed = NumberRange.new((speed or 12) * 0.5, speed or 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Drag = 3
	emitter.Enabled = false
	emitter.Parent = anchorAt(position)
	emitter:Emit(count)
end

local function smoke(position: Vector3)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(200, 200, 205))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Speed = NumberRange.new(3, 8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(1.5, 2.5)
	emitter.Enabled = false
	emitter.Parent = anchorAt(position)
	emitter:Emit(30)
end

local function tracer(from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 230, 120)
	beam.Size = Vector3.new(0.15, 0.15, length)
	beam.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
	beam.Parent = workspace
	TweenService:Create(beam, TweenInfo.new(0.25), { Transparency = 1 }):Play()
	Debris:AddItem(beam, 0.3)
end

-- Floating "+$5" text over a spot, only for the local player
function Effects.FloatText(position: Vector3, text: string, color: Color3)
	local holder = anchorAt(position)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(4, 1.5)
	gui.AlwaysOnTop = true
	gui.Parent = holder
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Text = text
	label.Parent = gui
	TweenService:Create(gui, TweenInfo.new(1), { StudsOffset = Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
end

-- Coins ---------------------------------------------------------------------------------------
-- The pickup plays the moment you touch a coin (the server confirms and pays a beat later): the
-- coin flies into you and shrinks, and the chime climbs while you keep a streak going.

local GOLD = Color3.fromRGB(255, 215, 60)
local COIN_STREAK_WINDOW = 1.6
local coinStreak, lastCoinAt, lastCoinPredicted = 0, 0, 0

local function coinChime()
	local now = os.clock()
	coinStreak = if now - lastCoinAt < COIN_STREAK_WINDOW then math.min(coinStreak + 1, 10) else 0
	lastCoinAt = now
	local sound = Instance.new("Sound")
	sound.SoundId = Sounds.Coin
	sound.Volume = 0.5
	sound.PlaybackSpeed = 1 + coinStreak * 0.06
	SoundService:PlayLocalSound(sound)
	sound.Parent = SoundService
	Debris:AddItem(sound, 3)
end

local function flyCoinIn(coin: Model)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local ghost = coin:Clone()
	for _, d in ghost:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanTouch = false
		end
	end
	ghost:RemoveTag("Coin")
	ghost.Parent = workspace
	local start = coin:GetPivot()
	local started = os.clock()
	local duration = 0.22
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.min((os.clock() - started) / duration, 1)
		local target = if root and root.Parent then root.Position + Vector3.new(0, 1, 0) else start.Position
		local eased = t * t
		local position = start.Position:Lerp(target, eased) + Vector3.new(0, math.sin(t * math.pi) * 1.5, 0)
		ghost:PivotTo(CFrame.new(position) * CFrame.Angles(0, os.clock() * 18, 0))
		ghost:ScaleTo(math.max(1 - t * 0.7, 0.05))
		if t >= 1 then
			connection:Disconnect()
			ghost:Destroy()
			Effects.Burst(target, GOLD, 8, 8, 0.35)
		end
	end)
end

-- Hooks a coin the server just spawned: a glint when it appears, local pickup when touched
local function trackCoin(coin: Instance)
	if not coin:IsA("Model") then
		return
	end
	local hitbox = coin:WaitForChild("Hitbox", 5) :: BasePart?
	if not hitbox then
		return
	end
	if (hitbox.Position - (workspace.CurrentCamera :: Camera).CFrame.Position).Magnitude < 150 then
		Effects.Burst(hitbox.Position, GOLD, 6, 4, 0.4)
	end
	local taken = false
	hitbox.Touched:Connect(function(other)
		local character = player.Character
		if
			taken
			or not character
			or not other:IsDescendantOf(character)
			or ((player:GetAttribute("RunResumeAt") or 0) :: number) > workspace:GetServerTimeNow()
			or ((coin:GetAttribute("RoundOnly") == true) ~= (player:GetAttribute("InRound") == true))
		then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		taken = true
		lastCoinPredicted = os.clock()
		coinChime()
		flyCoinIn(coin)
		-- Hide our copy now; the server removes the real one when it pays out
		for _, d in coin:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
			elseif d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("BillboardGui") then
				(d :: any).Enabled = false
			end
		end
	end)
end

-- Short camera shake (hits you land and hits you take)
local shakeUntil, shakeStrength = 0, 0

function Effects.Shake(strength: number, duration: number)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
	shakeStrength = math.max(if os.clock() < shakeUntil then shakeStrength else 0, strength)
end
RunService:BindToRenderStep("KnifeShake", Enum.RenderPriority.Camera.Value + 1, function()
	local left = shakeUntil - os.clock()
	if left <= 0 then
		shakeStrength = 0
		return
	end
	local s = shakeStrength * math.min(1, left * 6)
	local camera = workspace.CurrentCamera
	camera.CFrame *= CFrame.Angles(
		math.rad((math.random() - 0.5) * s),
		math.rad((math.random() - 0.5) * s),
		math.rad((math.random() - 0.5) * s * 0.5)
	)
end)

-- Full-screen red flash, optionally with big text ("YOU DIED")
local function flash(text: string?, strength: number, duration: number)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Flash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255) -- a white flash, not a red one
	frame.BackgroundTransparency = 1 - strength
	frame.Parent = gui
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
	if text then
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.45)
		label.Size = UDim2.fromScale(0.6, 0.16)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0
		label.Text = text
		label.Parent = frame
		TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end
	Debris:AddItem(gui, duration + 0.1)
end

-- "THE BOSS IS COMING!" is a small toast today; Steal An Egg slams a huge red "RUN!!" banner on
-- screen the instant a guardian wakes for you. This is that banner, just for the thief (server:
-- GuardService sendChaser fires "Alarm" to them alone).
local function runBanner()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RunBanner"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 25
	gui.Parent = player:WaitForChild("PlayerGui")
	local box = Instance.new("Frame")
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.Position = UDim2.new(0.5, 0, 0, 90)
	box.Size = UDim2.fromOffset(0, 74) -- (pops open from 0 width)
	box.BackgroundColor3 = Color3.fromRGB(120, 15, 15)
	box.BorderSizePixel = 0
	box.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = box
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 70, 70)
	stroke.Thickness = 3
	stroke.Parent = box
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromOffset(300, 54)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Text = "RUN!!"
	label.TextTransparency = 1
	label.Parent = box
	local open = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(box, open, { Size = UDim2.fromOffset(260, 74) }):Play()
	TweenService:Create(label, TweenInfo.new(0.15), { TextTransparency = 0 }):Play()
	task.delay(1.1, function()
		local close = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(box, close, { Size = UDim2.fromOffset(0, 74) }):Play()
		TweenService:Create(label, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
	end)
	Debris:AddItem(gui, 1.6)
end

-- A quick burst of light
local function lightFlash(position: Vector3, color: Color3, brightness: number, range: number, duration: number)
	local holder = anchorAt(position)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = holder
	TweenService:Create(light, TweenInfo.new(duration, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
end

-- A pillar of light shooting up from a spot (rebirths, chests)
local function pillar(position: Vector3, color: Color3, height: number, duration: number)
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Shape = Enum.PartType.Cylinder
	beam.Material = Enum.Material.Neon
	beam.Color = color
	beam.Transparency = 0.2
	beam.Size = Vector3.new(0.5, 6, 6)
	beam.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	beam.Parent = workspace
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(beam, info, {
		Size = Vector3.new(height, 1, 1),
		CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Transparency = 1,
	}):Play()
	Debris:AddItem(beam, duration + 0.1)
end

-- A copy of a knife flying in an arc from `from` to `to` (placing it, equipping it)
-- (a knife character - Codex's art with its face - when this knife has one, else the plain knife)
local characterAssets: any = nil
local function buildFlying(item: string, character: boolean?): Model
	if character then
		if characterAssets == nil then
			local ok, loaded = pcall(function()
				return require(ReplicatedStorage.Shared.Assets.KnifeCharacterAssets) :: any
			end)
			characterAssets = if ok then loaded else false
		end
		local parsed = Items.Parse(item)
		if characterAssets and parsed then
			local ok, built = pcall(characterAssets.BuildCharacter, parsed.Name, nil, CFrame.identity, { Scale = 1 })
			if ok and built then
				return built
			end
		end
	end
	return KnifeModel.Build(item, true)
end

local function flyKnife(
	item: string,
	from: Vector3,
	to: Vector3,
	duration: number,
	length: number,
	character: boolean?,
	coffin: string? -- a rarity: fly its coffin instead (the knife inside stays a secret)
)
	local model = if coffin then CoffinModel.Build(coffin, CFrame.identity, item) else buildFlying(item, character)
	if coffin then
		CoffinModel.Weld(model)
	else
		KnifeModel.FitLength(model, length)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("Trail") then
			d.Enabled = true
		end
	end
	model.Parent = workspace
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.min(1, (os.clock() - start) / duration)
		local eased = 1 - (1 - t) ^ 2
		local at = from:Lerp(to, eased) + Vector3.new(0, math.sin(t * math.pi) * 3, 0)
		model:PivotTo(CFrame.new(at) * CFrame.Angles(0, t * math.pi * 2, math.rad(20)))
		if t >= 1 then
			connection:Disconnect()
			model:Destroy()
		end
	end)
end

local handlers: { [string]: (...any) -> () } = {
	-- Putting a stolen knife on your plate: it flies from your hands and lands with a burst
	PlaceKnife = function(from: Vector3, to: Vector3, item: string, coffin: string?)
		if not Lod.Near(to) then
			return
		end
		flyKnife(item, from, to, 0.45, 4, nil, coffin)
		task.delay(0.45, function()
			Effects.Burst(to, Items.Color(item), 30, 14, 0.7)
			Effects.Burst(to, Color3.fromRGB(110, 255, 110), 16, 10, 0.5)
			Effects.Sound(Sounds.Cash, to, 0.8)
		end)
	end,
	-- A knife leaves someone's hand (hub or round): a swish where it was thrown from
	KnifeThrow = function(from: Vector3)
		if Lod.Near(from, 120) then
			Effects.Sound(Sounds.Throw, from, 0.9)
		end
	end,
	-- Equipping a knife: it flies off its plate into your hand, a ring of light, a big banner
	Equipped = function(who: Player, item: string, from: Vector3?)
		local character = who.Character
		local hand = character
			and (character:FindFirstChild("RightHand") or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
		if not hand then
			return
		end
		local to = hand.Position
		if from and Lod.Near(to) then
			flyKnife(item, from, to, 0.4, 3)
		end
		task.delay(if from then 0.4 else 0, function()
			Effects.Burst(to, Items.Color(item), 40, 18, 0.8)
			Effects.Sound(Sounds.Unsheath, to, 1)
		end)
		if who ~= player then
			return
		end
		-- Your own screen: one line on the top line (client/TopLine) - the knife's name in its colour
		-- and its Murderer power. (It was three big lines in a card in the middle of the screen.)
		local tint = Items.Color(item):Lerp(Color3.new(1, 1, 1), 0.25)
		local text = `⚔️ Equipped <font color="#{tint:ToHex()}"><b>{Items.DisplayName(item)}</b></font>`
		TopLine.Show(text, 2.4, "Equipped")
	end,
	-- A coffin opened (CoffinService.Reveal): the knife stands where it was, full size, with a white
	-- swoosh round it, looks at its owner, hops, then flies into their hand and shrinks into the
	-- hotbar (Steal an Egg). ~1.7 s, matching BaseService HATCH_FLIGHT.
	CoffinHatch = function(who: Player, item: string, from: Vector3)
		if not Lod.Near(from, 160) then
			return
		end
		local parsed = Items.Parse(item)
		local model = buildFlying(item, true)
		local _, natural = model:GetBoundingBox()
		local full = PenMode.Scale(if parsed then parsed.Knife.Rarity else "Common")
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
			end
		end
		-- where it stands: the grass under the coffin
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore: { Instance } = { model }
		for _, other in Players:GetPlayers() do
			if other.Character then
				table.insert(ignore, other.Character)
			end
		end
		for _, coffin in CollectionService:GetTagged("Coffin") do
			table.insert(ignore, coffin) -- (its own coffin may not have gone yet)
		end
		params.FilterDescendantsInstances = ignore
		local ground = workspace:Raycast(from + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), params)
		local floor = if ground then ground.Position else from - Vector3.new(0, 3.5, 0)
		model:ScaleTo(full * 0.2)
		model.Parent = workspace
		local color = Items.Color(item)
		-- the swoosh: a bright white streak sweeping round it
		local radius = math.max(3, natural.Y * full * 0.55)
		local swoosh = Instance.new("Part")
		swoosh.Name = "HatchSwoosh"
		swoosh.Size = Vector3.one * 0.2
		swoosh.Transparency = 1
		swoosh.Anchored = true
		swoosh.CanCollide, swoosh.CanQuery, swoosh.CanTouch = false, false, false
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Position, a1.Position = Vector3.new(0, -0.9, 0), Vector3.new(0, 0.9, 0)
		a0.Parent, a1.Parent = swoosh, swoosh
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.Lifetime = 0.35
		trail.LightEmission = 1
		trail.Brightness = 3
		trail.FaceCamera = true
		trail.Color = ColorSequence.new(Color3.new(1, 1, 1), color:Lerp(Color3.new(1, 1, 1), 0.6))
		trail.Transparency = NumberSequence.new(0, 1)
		trail.WidthScale = NumberSequence.new(1, 0.2)
		trail.Parent = swoosh
		swoosh.CFrame = CFrame.new(floor + Vector3.new(radius, radius * 0.6, 0))
		swoosh.Parent = workspace
		Effects.Burst(floor + Vector3.new(0, 1.5, 0), Color3.new(1, 1, 1), 26, 14, 0.5)
		Effects.Sound(Sounds.Reveal, floor, 0.8)
		if who == player then
			local tint = color:Lerp(Color3.new(1, 1, 1), 0.25)
			TopLine.Show(
				`🎉 It's a <font color="#{tint:ToHex()}"><b>{Items.DisplayName(item)}</b></font>!`,
				3,
				"Hatched"
			)
		end
		local GROW, STAND, FLY = 0.35, 0.85, 0.5
		local start = os.clock()
		local flyFrom: Vector3? = nil
		local connection: RBXScriptConnection
		connection = RunService.RenderStepped:Connect(function()
			local t = os.clock() - start
			local character = who.Character
			local hand = character
				and (character:FindFirstChild("RightHand") or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
			local target = if hand then hand.Position else floor + Vector3.new(0, 3, 0)
			local flat = Vector3.new(target.X - floor.X, 0, target.Z - floor.Z)
			local facing = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
			-- (the swoosh sweeps once round it, rising)
			if t < 0.4 then
				local angle = t / 0.4 * math.pi * 2
				swoosh.CFrame = CFrame.new(
					floor + Vector3.new(math.cos(angle) * radius, radius * (0.4 + t), math.sin(angle) * radius)
				)
			elseif swoosh.Parent then
				swoosh:Destroy()
			end
			if t < GROW + STAND then
				-- pop up to full size, look at its owner, then a little hop
				local grow = math.min(1, t / GROW)
				local c1, c3 = 1.70158, 2.70158
				local eased = 1 + c3 * (grow - 1) ^ 3 + c1 * (grow - 1) ^ 2
				model:ScaleTo(math.max(0.05, full * (0.2 + 0.8 * eased)))
				local hopT = (t - GROW - 0.35) / 0.35
				local lift = if hopT > 0 and hopT < 1 then 4 * hopT * (1 - hopT) * (1 + full * 0.4) else 0
				model:PivotTo(CFrame.lookAt(floor + Vector3.new(0, lift, 0), floor + Vector3.new(0, lift, 0) + facing))
				return
			end
			-- fly into its owner, spinning and shrinking to hand size
			local f = math.min(1, (t - GROW - STAND) / FLY)
			flyFrom = flyFrom or model:GetPivot().Position
			local eased = 1 - (1 - f) ^ 2
			local at = (flyFrom :: Vector3):Lerp(target, eased) + Vector3.new(0, math.sin(f * math.pi) * 4, 0)
			model:ScaleTo(math.max(0.05, full * (1 - 0.8 * eased)))
			model:PivotTo(CFrame.new(at) * CFrame.Angles(0, f * math.pi * 3, 0))
			if f >= 1 then
				connection:Disconnect()
				model:Destroy()
				if swoosh.Parent then
					swoosh:Destroy()
				end
				Effects.Burst(target, color, 40, 18, 0.8)
				Effects.Sound(Sounds.Unsheath, target, 1)
			end
		end)
	end,
	-- ...and when you're back in your pen it jumps out of your hand and hops to where its coffin stood
	HatchHome = function(from: Vector3, item: string, to: Vector3, flight: number)
		if not Lod.Near(to, 160) then
			return
		end
		flyKnife(item, from, to, flight, 3.5, true)
		task.delay(flight, function()
			Effects.Burst(to, Items.Color(item), 30, 14, 0.7)
			Effects.Sound(Sounds.Reveal, to, 0.6)
		end)
	end,
	-- A surprise gift landed by you: a pop, a chime and a burst of light
	GiftDrop = function(at: Vector3)
		Effects.Burst(at, Color3.fromRGB(255, 215, 80), 30, 14, 0.6)
		Effects.Sound(Sounds.Reveal, at, 0.6)
	end,
	-- ...and opened: confetti and the prize floating up
	GiftOpen = function(at: Vector3, what: string, kind: string)
		Effects.Burst(at, Color3.fromRGB(255, 120, 200), 40, 18, 0.8)
		Effects.Burst(at, Color3.fromRGB(255, 215, 80), 30, 14, 0.6)
		Effects.Sound(if kind == "Coffin" then Sounds.Reveal else Sounds.Cash, at, 0.8)
		Effects.FloatText(at + Vector3.new(0, 4, 0), `🎁 {what}`, Color3.fromRGB(255, 230, 120))
	end,
	-- Bought a Health level: a green burst over them
	Heal = function(position: Vector3)
		Effects.FloatText(position + Vector3.new(0, 4, 0), "+MAX HEALTH", Color3.fromRGB(110, 255, 140))
		Effects.Sound(Sounds.Reveal, position, 0.5)
	end,
	-- Radar: outlines through walls, only on this client, for a few seconds
	Radar = function(entries: { any }, duration: number)
		Effects.Sound(Sounds.Sting, nil, 0.4)
		for _, entry in entries do
			local model = entry.Model :: Instance?
			if model and model.Parent then
				local highlight = Instance.new("Highlight")
				highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				highlight.FillColor = entry.Color
				highlight.FillTransparency = 0.55
				highlight.OutlineColor = entry.Color
				highlight.Parent = model
				Debris:AddItem(highlight, duration)
			end
		end
	end,
	-- A coffin on a vault plate pops open (server CoffinService): a burst in its rarity colour
	CoffinOpen = function(position: Vector3, color: Color3?, rank: number?)
		local tint = color or Color3.fromRGB(255, 230, 120)
		local size = rank or 1
		Effects.Burst(position, tint, 40 + size * 8, 22 + size, 0.8)
		Effects.Burst(position + Vector3.new(0, 3, 0), Color3.new(1, 1, 1), 16 + size * 3, 14, 0.5)
		Effects.Sound(Sounds.Reveal, position, 1)
		if size >= 4 then
			Effects.Sound(Sounds.Sting, position, 0.8)
			Effects.Shake(math.min(7, size), 0.4)
		end
		Effects.FloatText(
			position + Vector3.new(0, 4 + size * 0.5, 0),
			if size >= 6 then "WOW!!" else "IT'S OPEN!",
			tint
		)
	end,
	Died = function()
		flash(nil, 0.5, 0.6) -- (no words: the death card says what happened)
	end,
	Hurt = function()
		flash(nil, 0.35, 0.35)
		Effects.Shake(3, 0.3)
	end,
	-- Floating damage number over a guard you hit
	Damage = function(position: Vector3, amount: number)
		Effects.FloatText(position, tostring(amount), Color3.fromRGB(255, 230, 120))
		Effects.Shake(1.2, 0.12)
	end,
	Swing = function(position: Vector3)
		Effects.Sound(Sounds.Throw, position, 0.9) -- (the throw's swish: one knife sound for both)
	end,
	Hit = function(position: Vector3)
		-- Cartoon impact sparks (no blood: keeps the game rated for younger players)
		Effects.Burst(position, Color3.fromRGB(255, 235, 120), 24, 16, 0.6)
	end,
	KnifeKill = function(position: Vector3, color: Color3, rank: number)
		Effects.Burst(position, color, 12 + math.clamp(rank, 1, 9) * 5, 14 + rank * 2, 0.6)
	end,
	SpeedPickup = function(position: Vector3, amount: number?)
		Effects.FloatText(
			position + Vector3.new(0, 1, 0),
			`+{Format.Short(amount or 1)} SPEED`,
			Color3.fromRGB(120, 220, 255)
		)
		Effects.Sound(Sounds.PrizeLand, position, 0.5)
	end,
	Shield = function(position: Vector3)
		Effects.Burst(position, Color3.fromRGB(90, 190, 255), 40, 20, 0.9)
		Effects.Sound(Sounds.Unsheath, position, 1)
	end,
	Smoke = function(position: Vector3)
		smoke(position)
	end,
	Dash = function(position: Vector3)
		Effects.Burst(position, Color3.fromRGB(255, 255, 255), 20, 14, 0.5)
		Effects.Sound(Sounds.Lunge, position, 0.8)
	end,
	Shot = function(from: Vector3, to: Vector3)
		tracer(from, to)
		Effects.Sound(Sounds.Gunshot, from, 1)
		Effects.Burst(to, Color3.fromRGB(255, 220, 120), 10, 8, 0.4)
	end,
	Coin = function(position: Vector3, amount: number)
		-- Usually the pickup already played locally (see trackCoin); this just confirms the cash
		if os.clock() - lastCoinPredicted > 0.75 then
			coinChime()
		end
		Effects.FloatText(position, `+${Format.Short(amount)}`, Color3.fromRGB(255, 215, 60))
	end,
	Deposit = function(who: Player, rarity: string)
		local character = who.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			Effects.Burst(
				root.Position + Vector3.new(0, 3, 0),
				Knives.RarityColors[rarity] or Color3.new(1, 1, 1),
				50,
				22,
				0.8
			)
		end
		if who == player then
			Effects.Sound(Sounds.Cash, nil, 0.6)
		end
	end,
	RevolverDrop = function(position: Vector3)
		Effects.Burst(position, Color3.fromRGB(80, 255, 120), 30, 10, 0.6)
	end,
	Unsheath = function(position: Vector3?)
		Effects.Sound(Sounds.Unsheath, position, 1)
	end,

	-- A boss wakes up (GuardService sendChaser, before the chase): eyes glow red, a rising sting, and
	-- a roar once they're on their feet
	BossWake = function(model: Model, duration: number)
		local head = model and model:FindFirstChild("Head") :: BasePart?
		if not head then
			return
		end
		local eyes: { BasePart } = {}
		for _, side in { -1, 1 } do
			local eye = Instance.new("Part")
			eye.Name = "WakeEye"
			eye.Shape = Enum.PartType.Ball
			eye.Material = Enum.Material.Neon
			eye.Color = Color3.fromRGB(255, 30, 30)
			eye.Size = Vector3.one * 0.05
			eye.CanCollide, eye.CanQuery, eye.CanTouch, eye.Massless = false, false, false, true
			eye.CastShadow = false
			local offset = CFrame.new(side * head.Size.X * 0.17, head.Size.Y * 0.08, -head.Size.Z * 0.47)
			eye.CFrame = head.CFrame * offset
			local weld = Instance.new("Weld")
			weld.Part0, weld.Part1, weld.C0 = head, eye, offset
			weld.Parent = eye
			eye.Parent = model
			TweenService:Create(eye, TweenInfo.new(0.25, Enum.EasingStyle.Back), {
				Size = Vector3.one * head.Size.X * 0.2,
			}):Play()
			table.insert(eyes, eye)
		end
		-- (one "!" only: the boss's own Alert mark, GuardService)
		Effects.Sound(Sounds.BossWake, head.Position, 0.8)
		task.delay(duration * 0.85, function()
			if head.Parent then
				Effects.Sound(Sounds.BossRoar, head.Position, 0.45)
			end
		end)
		task.delay(duration + 1.5, function()
			for _, eye in eyes do
				eye:Destroy()
			end
		end)
	end,
	-- A boss is coming for you: a quick red flash (the alarm bell rang on every steal - too much)
	Alarm = function()
		flash(nil, 0.25, 0.8)
		runBanner()
		-- One quick siren whoop, faded out after a second (no ringing: the old bell rang on and on)
		local siren = Instance.new("Sound")
		siren.SoundId = Sounds.StealSiren
		siren.Volume = 0.55
		siren.Parent = SoundService
		siren:Play()
		task.delay(0.9, function()
			TweenService:Create(siren, TweenInfo.new(0.25), { Volume = 0 }):Play()
		end)
		Debris:AddItem(siren, 1.3)
	end,
	Stolen = function(position: Vector3, color: Color3)
		Effects.Burst(position + Vector3.new(0, 3, 0), color, 40, 16, 0.7)
		Effects.Sound(Sounds.Lunge, position, 1)
	end,

	-- Powers ---------------------------------------------------------------------------------------
	Flash = function(origin: Vector3, look: Vector3)
		-- The old camera pops up in front of them, and the bulb goes off
		local camera = Props.Build("Camera", true)
		camera:PivotTo(CFrame.lookAt(origin + look * 1.6, origin + look * 6))
		for _, d in camera:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
			end
		end
		camera.Parent = workspace
		Debris:AddItem(camera, 0.9)
		lightFlash(origin + look * 2, Color3.fromRGB(255, 255, 230), 40, 45, 0.5)
		Effects.Burst(origin + look * 2, Color3.new(1, 1, 1), 40, 30, 0.8)
		Effects.Sound(Sounds.Flash, origin, 1)
	end,

	-- Progress -------------------------------------------------------------------------------------
	Rebirth = function(who: Player, position: Vector3)
		pillar(position, Color3.fromRGB(255, 220, 90), 140, 2.2)
		Effects.Burst(position + Vector3.new(0, 3, 0), Color3.fromRGB(255, 220, 90), 120, 40, 1.2)
		lightFlash(position, Color3.fromRGB(255, 220, 120), 10, 60, 2)
		Effects.Sound(Sounds.Reveal, position, 1)
		if who == player then
			Effects.Sound(Sounds.Reveal, nil, 0.5)
			flash("REBIRTH!", 0.3, 2)
		end
	end,
	CashBurst = function(at: Vector3?, cash: number, automatic: boolean?)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local position = at or (if root then root.Position else nil)
		if not position then
			if not automatic then
				Effects.Sound(Sounds.Cash, nil, 0.9)
			end
			return
		end
		Effects.Burst(position + Vector3.new(0, 2, 0), Color3.fromRGB(110, 255, 110), 70, 30, 1)
		Effects.FloatText(position + Vector3.new(0, 6, 0), `+${Format.Short(cash)}`, Color3.fromRGB(110, 255, 110))
		-- Auto Collect repeats for every occupied plate each tick; income stays visible but quiet.
		if not automatic then
			Effects.Sound(Sounds.Cash, nil, 0.9)
			-- the bills fly from where you picked them up into your cash (show, don't tell)
			local camera = workspace.CurrentCamera
			local screen, visible = camera:WorldToScreenPoint(position)
			if Ui.FlyIn then
				Ui.FlyIn(true, if visible then Vector2.new(screen.X, screen.Y) else nil, 5)
			end
		end
	end,
	-- More pen room: each new spot bursts green with a "+1" where it is
	RoomAdded = function(spots: { Vector3 })
		if type(spots) ~= "table" then
			return
		end
		for i, at in spots do
			if typeof(at) == "Vector3" then
				task.delay((i - 1) * 0.15, function()
					Effects.Burst(at + Vector3.new(0, 1, 0), Color3.fromRGB(120, 255, 140), 60, 26, 1.1)
					Effects.FloatText(at + Vector3.new(0, 4, 0), "+1 🏠", Color3.fromRGB(120, 255, 140))
				end)
			end
		end
		Effects.Sound(Sounds.Reveal, nil, 0.6)
	end,
	IndexClaim = function(cash: number, speed: number)
		Effects.Sound(Sounds.Reveal, nil, 0.7)
		local root = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
		if root then
			Effects.FloatText(
				root.Position + Vector3.new(0, 3, 0),
				`+${Format.Short(cash)}  +{Format.Short(speed)} 👟`,
				Color3.fromRGB(255, 230, 90)
			)
			Effects.Burst(root.Position, Color3.fromRGB(80, 170, 255), 50, 20, 0.8)
		end
		if Ui.FlyIn then
			Ui.FlyIn(true, nil, 6)
			if speed > 0 then
				task.delay(0.3, Ui.FlyIn, false, nil, 8)
			end
		end
	end,
}

function Effects.Init()
	Remotes:WaitForChild("Effect").OnClientEvent:Connect(function(kind: string, ...)
		local handler = handlers[kind]
		if handler then
			handler(...)
		end
	end)

	-- A red glow at the screen's edges the whole time you're carrying a boss's coffin (BossCarry):
	-- Steal An Egg keeps this up the entire run home, not just a one-off flash - a constant "you are
	-- not safe yet" the Alarm's single banner can't carry on its own.
	do
		local gui = Instance.new("ScreenGui")
		gui.Name = "ChaseVignette"
		gui.IgnoreGuiInset = true
		gui.ScreenInsets = Enum.ScreenInsets.None
		gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
		gui.ClipToDeviceSafeArea = false
		gui.DisplayOrder = 15
		gui.ResetOnSpawn = false
		gui.Parent = player:WaitForChild("PlayerGui")
		local edges = {}
		local function edge(size: UDim2, position: UDim2, rotation: number)
			local frame = Instance.new("Frame")
			frame.Size = size
			frame.Position = position
			frame.BackgroundColor3 = Color3.fromRGB(200, 20, 20)
			frame.BackgroundTransparency = 1
			frame.BorderSizePixel = 0
			local gradient = Instance.new("UIGradient")
			gradient.Rotation = rotation
			gradient.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
			gradient.Parent = frame
			frame.Parent = gui
			table.insert(edges, frame)
		end
		edge(UDim2.fromScale(1, 0.16), UDim2.fromScale(0, 0), 90) -- top
		edge(UDim2.fromScale(1, 0.16), UDim2.fromScale(0, 0.84), 270) -- bottom
		edge(UDim2.fromScale(0.1, 1), UDim2.fromScale(0, 0), 0) -- left
		edge(UDim2.fromScale(0.1, 1), UDim2.fromScale(0.9, 0), 180) -- right
		local target = -1
		-- (only while you're still out on the runway: once you're past the safe line - the plaza,
		-- your pen - the boss has given up, so the "not safe yet" glow goes)
		local function refresh()
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local safe = root ~= nil and root.Position.Z <= 0
			local want = if player:GetAttribute("BossCarry") ~= nil
					and not safe
					and player:GetAttribute("RunSaved") ~= true
				then 0.55
				else 1
			if want == target then
				return
			end
			target = want
			for _, frame in edges do
				TweenService:Create(frame, TweenInfo.new(0.4), { BackgroundTransparency = target }):Play()
			end
		end
		task.spawn(function()
			while true do
				task.wait(0.25)
				refresh()
			end
		end)
		player:GetAttributeChangedSignal("BossCarry"):Connect(refresh)
		refresh()
	end

	-- Surprise gifts are for one player: everyone else's are hidden on this screen
	-- (the server builds them invisible: the owner's screen shows its own, everyone else's stays
	-- invisible with no prompt - parts that streamed in late used to slip through the hiding)
	local function showGiftPart(gift: Instance, d: Instance)
		local mine = gift:GetAttribute("Owner") == player.UserId
		if d:IsA("BasePart") then
			local look = d:GetAttribute("Look")
			if mine and type(look) == "number" then
				d.Transparency = look
			end
		elseif d:IsA("Sparkles") or d:IsA("ProximityPrompt") then
			(d :: any).Enabled = mine
		end
	end
	local function watchGift(gift: Instance)
		for _, d in gift:GetDescendants() do
			showGiftPart(gift, d)
		end
		gift.DescendantAdded:Connect(function(d)
			showGiftPart(gift, d)
		end)
	end
	for _, gift in CollectionService:GetTagged("SurpriseGift") do
		watchGift(gift)
	end
	CollectionService:GetInstanceAddedSignal("SurpriseGift"):Connect(watchGift)

	-- Coins and the Revolver pickup spin locally (no server traffic)
	local spinning: { [Instance]: CFrame } = {}
	local function track(instance: Instance)
		if instance:IsA("BasePart") then
			spinning[instance] = instance.CFrame
		elseif instance:IsA("Model") then
			spinning[instance] = instance:GetPivot()
		end
	end
	for _, tag in { "Coin", "Spin" } do
		for _, instance in CollectionService:GetTagged(tag) do
			track(instance)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(track)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
			spinning[instance] = nil
		end)
	end
	for _, coin in CollectionService:GetTagged("Coin") do
		task.spawn(trackCoin, coin)
	end
	CollectionService:GetInstanceAddedSignal("Coin"):Connect(trackCoin)
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for instance, base in spinning do
			if not instance.Parent then
				spinning[instance] = nil
				continue
			end
			-- Nobody near enough to notice it turning (LOD)
			if not Lod.Near(base.Position) then
				continue
			end
			-- Each one a little out of step with its neighbours
			local t = now + (base.Position.X + base.Position.Z) * 0.37
			local bob = CFrame.new(0, math.sin(t * 2) * 0.3, 0)
			local turn = CFrame.Angles(0, t * 2, 0)
			local goal = CFrame.new(base.Position) * bob * turn * (base - base.Position)
			if instance:HasTag("Coin") then
				-- Keep the embossed sneaker upright and readable; a full spin showed thin edges.
				local camera = workspace.CurrentCamera
				local direction = Vector3.new(camera.CFrame.Position.X, base.Position.Y, camera.CFrame.Position.Z)
				if (direction - base.Position).Magnitude > 0.01 then
					goal = CFrame.lookAt(base.Position, direction) * bob * CFrame.Angles(0, math.sin(t) * 0.12, 0)
				end
			end
			if instance:IsA("BasePart") then
				instance.CFrame = goal
			elseif instance:IsA("Model") then
				instance:PivotTo(goal)
			end
		end
	end)

	-- Rainbow-mutation knives cycle through every colour; aura rings on vault floors breathe
	local rainbow: { [Instance]: { BasePart } } = {}
	local function trackRainbow(model: Instance)
		local parts = {}
		for _, d in model:GetDescendants() do
			if
				d:IsA("BasePart")
				and d.Transparency < 1
				and (d:GetAttribute("KnifeRole") == nil or d:GetAttribute("RainbowValue") ~= nil)
			then
				table.insert(parts, d)
			end
		end
		rainbow[model] = parts
	end
	for _, model in CollectionService:GetTagged("RainbowKnife") do
		trackRainbow(model)
	end
	CollectionService:GetInstanceAddedSignal("RainbowKnife"):Connect(trackRainbow)
	CollectionService:GetInstanceRemovedSignal("RainbowKnife"):Connect(function(model)
		rainbow[model] = nil
	end)
	local rings: { [BasePart]: Vector3 } = {}
	local function trackRing(ring: Instance)
		if ring:IsA("BasePart") then
			rings[ring] = ring.Size
		end
	end
	for _, ring in CollectionService:GetTagged("AuraRing") do
		trackRing(ring)
	end
	CollectionService:GetInstanceAddedSignal("AuraRing"):Connect(trackRing)
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for model, parts in rainbow do
			if not model.Parent then
				rainbow[model] = nil
				continue
			end
			local first = parts[1]
			if first and not Lod.Near(first.Position) then
				continue
			end
			for i, part in parts do
				local value = part:GetAttribute("RainbowValue")
				part.Color =
					Color3.fromHSV((t * 0.35 + i * 0.08) % 1, 0.65, if type(value) == "number" then value else 1)
			end
		end
		for ring, size in rings do
			if not ring.Parent then
				rings[ring] = nil
				continue
			end
			if not Lod.Near(ring.Position) then
				continue
			end
			local pulse = 1 + math.sin(t * 2.2 + size.Y) * 0.04
			ring.Size = Vector3.new(size.X, size.Y * pulse, size.Z * pulse)
		end
	end)

	-- Haunted Wheels turn while their owner runs inside (local only, pivoting around the hub)
	-- Keep exposure steady across joins and round teleports; room lamps supply the mood.
	local Lighting = game:GetService("Lighting")
	local function roundLighting()
		local inRound = player:GetAttribute("InRound") == true
		local info = TweenInfo.new(1.2, Enum.EasingStyle.Quad)
		-- (exposure, bloom and the rest of the mood: client/ZoneLighting)
		-- Round maps are indoors with no lamps: rounds get bright, neutral room light, and the hub's
		-- own values (published by the server as Lighting attributes, MapService) come back after.
		-- Never cache Lighting here: the client can start before the server has set it up.
		local hubAmbient = Lighting:GetAttribute("HubAmbient")
		local hubOutdoor = Lighting:GetAttribute("HubOutdoor")
		Lighting.GlobalShadows = if inRound then false else Lighting:GetAttribute("HubShadows") == true
		if inRound then
			TweenService:Create(Lighting, info, {
				Ambient = Color3.fromRGB(210, 210, 200),
				OutdoorAmbient = Color3.fromRGB(210, 210, 200),
			}):Play()
		elseif typeof(hubAmbient) == "Color3" and typeof(hubOutdoor) == "Color3" then
			TweenService:Create(Lighting, info, { Ambient = hubAmbient, OutdoorAmbient = hubOutdoor }):Play()
		end
	end
	player:GetAttributeChangedSignal("InRound"):Connect(roundLighting)
	roundLighting()

	-- Flickering lamps in the round maps: electric lights cut out for a blink now and then,
	-- flames (candles, fireplaces; attribute "Flame") waver softly all the time
	local flickering: { [BasePart]: PointLight } = {}
	local function trackFlicker(instance: Instance)
		local light = instance:FindFirstChildOfClass("PointLight")
		if instance:IsA("BasePart") and light then
			flickering[instance] = light
			light:SetAttribute("BaseBrightness", light.Brightness)
			instance:SetAttribute("BaseTransparency", instance.Transparency)
		end
	end
	for _, instance in CollectionService:GetTagged("Flicker") do
		trackFlicker(instance)
	end
	CollectionService:GetInstanceAddedSignal("Flicker"):Connect(trackFlicker)
	CollectionService:GetInstanceRemovedSignal("Flicker"):Connect(function(instance)
		flickering[instance :: BasePart] = nil
	end)
	task.spawn(function()
		local rng = Random.new()
		while true do
			task.wait(0.08)
			local t = os.clock()
			for part, light in flickering do
				local base = (light:GetAttribute("BaseBrightness") or 1) :: number
				if part:GetAttribute("Flame") then
					local seed = part.Position.X * 0.13 + part.Position.Z * 0.07
					light.Brightness = base * (0.85 + 0.2 * math.noise(t * 4, seed))
				else
					local baseTransparency = (part:GetAttribute("BaseTransparency") or 0) :: number
					local off = rng:NextNumber() < 0.08
					light.Brightness = if off then base * 0.1 else base
					part.Transparency = if off then math.max(baseTransparency, 0.6) else baseTransparency
				end
			end
		end
	end)

	-- Wall clocks in the round maps keep real time (the second hand ticks)
	local hands: { [BasePart]: CFrame } = {}
	local function trackHand(instance: Instance)
		local center = instance:GetAttribute("Center")
		if instance:IsA("BasePart") and typeof(center) == "CFrame" then
			hands[instance] = center
		end
	end
	for _, instance in CollectionService:GetTagged("ClockHand") do
		trackHand(instance)
	end
	CollectionService:GetInstanceAddedSignal("ClockHand"):Connect(trackHand)
	CollectionService:GetInstanceRemovedSignal("ClockHand"):Connect(function(instance)
		hands[instance :: BasePart] = nil
	end)
	task.spawn(function()
		while true do
			local now = os.date("*t")
			local seconds = now.sec
			local minutes = now.min + seconds / 60
			local hours = now.hour % 12 + minutes / 60
			for hand, built in hands do
				-- (read fresh: the server corrects it after scaling the map up)
				local live = hand:GetAttribute("Center")
				local center = if typeof(live) == "CFrame" then live else built
				local kind = hand:GetAttribute("Hand")
				local turn = if kind == "Hour"
					then hours / 12
					elseif kind == "Minute" then minutes / 60
					else seconds / 60
				hand.CFrame = center * CFrame.Angles(0, 0, -turn * math.pi * 2) * CFrame.new(0, hand.Size.Y / 2, 0)
			end
			task.wait(1)
		end
	end)

	-- Owner prompts (Open now, Sell...) belong to one player; hide everyone else's
	local function filterPrompt(instance: Instance)
		if instance:IsA("ProximityPrompt") then
			local owner = instance:GetAttribute("Owner")
			if owner ~= nil and owner ~= player.UserId then
				instance.Enabled = false
			end
		end
	end
	for _, d in workspace:GetDescendants() do
		filterPrompt(d)
	end
	workspace.DescendantAdded:Connect(filterPrompt)

	WorldSignInput.Init()
end

return Effects
