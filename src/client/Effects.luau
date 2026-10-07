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
local GameConfig = require(ReplicatedStorage.Shared.Config:WaitForChild("GameConfig"))
local Props = require(ReplicatedStorage.Shared:WaitForChild("Props"))
local Format = require(ReplicatedStorage.Shared:WaitForChild("Format"))
local Items = require(ReplicatedStorage.Shared:WaitForChild("Items"))
local KnifeModel = require(ReplicatedStorage.Shared:WaitForChild("KnifeModel"))
local Lod = require(script.Parent.Lod)
local Ui = require(script.Parent.Ui)
local KnifePowers = require(ReplicatedStorage.Shared.Config.KnifePowers)
local TopLine = require(script.Parent.TopLine)
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
		if taken or not character or not other:IsDescendantOf(character) then
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
			elseif d:IsA("ParticleEmitter") or d:IsA("Light") then
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

-- Chunks flying off something that broke (gates, barricades): real little parts, client-only
local function debris(position: Vector3, color: Color3, material: Enum.Material, count: number)
	for _ = 1, count do
		local chunk = Instance.new("Part")
		chunk.Size = Vector3.new(math.random(4, 10) / 10, math.random(4, 10) / 10, math.random(4, 14) / 10)
		chunk.CFrame = CFrame.new(
			position + Vector3.new(math.random(-20, 20) / 10, math.random(0, 30) / 10, math.random(-20, 20) / 10)
		) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		chunk.Color = color
		chunk.Material = material
		chunk.CanCollide = true
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.AssemblyLinearVelocity = Vector3.new(math.random(-30, 30), math.random(15, 40), math.random(-30, 30))
		chunk.AssemblyAngularVelocity = Vector3.new(math.random(-10, 10), math.random(-10, 10), math.random(-10, 10))
		chunk.Parent = workspace
		Debris:AddItem(chunk, 3)
		task.delay(2.2, function()
			if chunk.Parent then
				TweenService:Create(chunk, TweenInfo.new(0.7), { Transparency = 1 }):Play()
			end
		end)
	end
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
local function flyKnife(item: string, from: Vector3, to: Vector3, duration: number, length: number)
	local model = KnifeModel.Build(item, true)
	KnifeModel.FitLength(model, length)
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
	-- Double Trouble: your fellow Murderer, outlined red for you only, for the round
	Partner = function(character: Model?, name: string)
		if not character then
			return
		end
		local highlight = Instance.new("Highlight")
		highlight.Name = "PartnerOutline"
		highlight.FillTransparency = 1
		highlight.OutlineColor = Color3.fromRGB(255, 40, 60)
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Adornee = character
		highlight.Parent = character
		Effects.FloatText(
			(character:GetPivot()).Position + Vector3.new(0, 5, 0),
			`🔪 Partner: {name}`,
			Color3.fromRGB(255, 80, 90)
		)
		local connection: RBXScriptConnection
		connection = player:GetAttributeChangedSignal("InRound"):Connect(function()
			if not player:GetAttribute("InRound") then
				connection:Disconnect()
				highlight:Destroy()
			end
		end)
	end,
	-- A Murderer power rolled on a knife you just got (or stole from the Sheriff-shot Murderer)
	PowerRoll = function(item: string, power: string, oneIn: number)
		local perk = GameConfig.Perks[power]
		local gui = Instance.new("ScreenGui")
		gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "PowerRoll", false, 45
		gui.Parent = player:WaitForChild("PlayerGui")
		Ui.TrackPresentation(gui)
		local rare = oneIn >= 300
		local color = if oneIn >= 1000
			then Color3.fromRGB(255, 80, 200)
			else if rare then Color3.fromRGB(255, 120, 60) else Color3.fromRGB(255, 220, 90)
		local card = Ui.new("Frame", {
			Name = "Card",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.44),
			BackgroundColor3 = Color3.fromRGB(22, 18, 34),
			BackgroundTransparency = 0.12,
		}, gui) :: Frame
		Ui.corner(card, 14)
		local stroke = Ui.new("UIStroke", { Thickness = 2, Color = color }, card)
		local labels: { TextLabel } = {}
		local short = KnifePowers.Short[power]
		local words = {
			"✨ KNIFE POWER! ✨",
			if perk then perk.DisplayName else power,
			`on your {Items.DisplayName(item)} · 1 in {oneIn}`,
		}
		if perk then
			table.insert(words, `Murderer: {if short then short[1] else perk.Description}`)
		end
		if short then
			table.insert(words, `Innocent: {short[2]}`)
		end
		for i, text in words do
			local label = Ui.label({
				Name = `Line{i}`,
				Text = text,
				TextScaled = false,
				TextWrapped = false,
				TextColor3 = if i == 2
					then color
					else if i == 4
						then Color3.fromRGB(255, 200, 210)
						else if i == 5 then Color3.fromRGB(180, 230, 255) else Color3.new(1, 1, 1),
				ZIndex = 2,
			}, card)
			Ui.textStroke(label, 1.5)
			table.insert(labels, label)
		end
		local function layout()
			local _, bounds = Ui.bounds()
			local phone = Ui.Phone
			local width = math.min(if phone then 420 else 760, bounds.X - (if phone then 200 else 40))
			local y, gap = if phone then 8 else 12, if phone then 4 else 6
			for i, label in labels do
				local height = if i == 1
					then (if phone then 18 else 28)
					else if i == 2 then (if phone then 28 else 48) else (if phone then 16 else 24)
				label.Position, label.Size = UDim2.fromOffset(12, y), UDim2.new(1, -24, 0, height)
				label.TextSize = height - 2
				local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
				if limit then
					limit.MinTextSize, limit.MaxTextSize = if phone then 12 else 14, height
				end
				y += height + gap
			end
			card.Size = UDim2.fromOffset(width, y + (if phone then 4 else 8))
		end
		local watch = Ui.Layout.Changed:Connect(layout)
		gui.Destroying:Connect(function()
			watch:Disconnect()
		end)
		layout()
		local scale = Ui.new("UIScale", { Scale = 0.9 }, card)
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		Effects.Sound(Sounds.Reveal, nil, 1)
		task.delay(if rare then 4 else 2.6, function()
			if not gui.Parent then
				return
			end
			TweenService:Create(card, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			for _, label in labels do
				TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
				local border = label:FindFirstChildOfClass("UIStroke")
				if border then
					TweenService:Create(border, TweenInfo.new(0.5), { Transparency = 1 }):Play()
				end
			end
			task.wait(0.55)
			gui:Destroy()
		end)
	end,
	-- Putting a stolen knife on your plate: it flies from your hands and lands with a burst
	PlaceKnife = function(from: Vector3, to: Vector3, item: string)
		if not Lod.Near(to) then
			return
		end
		flyKnife(item, from, to, 0.45, 4)
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
	-- Your map vote landed
	MapVoted = function(_name: string)
		Effects.Sound(Sounds.Coin, nil, 0.5)
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
		local parsed = Items.Parse(item)
		local perk = parsed and parsed.Perk and GameConfig.Perks[parsed.Perk]
		local tint = Items.Color(item):Lerp(Color3.new(1, 1, 1), 0.25)
		local text = `⚔️ Equipped <font color="#{tint:ToHex()}"><b>{Items.DisplayName(item)}</b></font>`
		if perk then
			text ..= `  <font color="#FF8C9E">🔪 {perk.DisplayName}</font>`
		end
		TopLine.Show(text, 2.4, "Equipped")
	end,
	-- A coffin hatched (server CoffinService): the knife pops up out of it, hangs a beat, then flies
	-- into its owner's hand with a burst (Steal an Egg's creature flying into you). The character
	-- itself is already hopping in the pen; your fighting knife doesn't change.
	CoffinHatch = function(who: Player, item: string, from: Vector3)
		local character = who.Character
		local hand = character
			and (character:FindFirstChild("RightHand") or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
		if not hand or not Lod.Near(from, 160) then
			return
		end
		local top = from + Vector3.new(0, 7, 0)
		flyKnife(item, from, top, 0.45, 3.5)
		task.delay(0.75, function()
			local to = hand.Position
			flyKnife(item, top, to, 0.5, 3)
			task.delay(0.5, function()
				Effects.Burst(to, Items.Color(item), 40, 18, 0.8)
				Effects.Sound(Sounds.Unsheath, to, 1)
			end)
		end)
		if who == player then
			local tint = Items.Color(item):Lerp(Color3.new(1, 1, 1), 0.25)
			TopLine.Show(
				`🎉 It's a <font color="#{tint:ToHex()}"><b>{Items.DisplayName(item)}</b></font>!`,
				3,
				"Hatched"
			)
		end
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
		Effects.Sound(if kind == "Case" then Sounds.Reveal else Sounds.Cash, at, 0.8)
		Effects.FloatText(at + Vector3.new(0, 4, 0), `🎁 {what}`, Color3.fromRGB(255, 230, 120))
	end,
	-- (Murderer only) a vanished innocent still leaves a faint shimmer
	Shimmer = function(character: Model?, duration: number)
		if not character or not character.Parent then
			return
		end
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(200, 220, 255)
		highlight.FillTransparency = 0.88
		highlight.OutlineColor = Color3.fromRGB(220, 235, 255)
		highlight.OutlineTransparency = 0.65
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = character
		highlight.Parent = character
		Debris:AddItem(highlight, duration)
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
	CoffinOpen = function(position: Vector3, color: Color3?)
		local tint = color or Color3.fromRGB(255, 230, 120)
		Effects.Burst(position, tint, 40, 22, 0.8)
		Effects.Burst(position, Color3.new(1, 1, 1), 16, 14, 0.5)
		Effects.Sound(Sounds.Reveal, position, 1)
		Effects.FloatText(position + Vector3.new(0, 4, 0), "IT'S OPEN!", tint)
	end,
	TrapSnap = function(position: Vector3)
		Effects.Burst(position + Vector3.new(0, 1, 0), Color3.fromRGB(200, 200, 210), 25, 12, 0.5)
		Effects.Sound(Sounds.Slash, position, 1)
		Effects.FloatText(position + Vector3.new(0, 4, 0), "SNAP!", Color3.fromRGB(255, 200, 80))
	end,
	PowerUsed = function(_id: string, position: Vector3)
		Effects.Burst(position, Color3.fromRGB(200, 170, 255), 15, 8, 0.4)
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
	Blink = function(from: Vector3, to: Vector3)
		Effects.Burst(from, Color3.fromRGB(170, 70, 255), 30, 12, 0.8)
		Effects.Burst(to, Color3.fromRGB(170, 70, 255), 30, 12, 0.8)
		Effects.Sound(Sounds.Lunge, to, 0.8)
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

	-- Raids ----------------------------------------------------------------------------------------
	GateHit = function(position: Vector3, amount: number)
		Effects.Burst(position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 170, 60), 18, 18, 0.5)
		Effects.Sound(Sounds.GateHit, position, 0.6)
		Effects.FloatText(
			position + Vector3.new(math.random(-4, 4), 5, 0),
			`-{math.floor(amount)}`,
			Color3.fromRGB(255, 120, 80)
		)
	end,
	GateBreak = function(position: Vector3, color: Color3)
		Effects.Burst(position, color, 80, 35, 1.2)
		debris(position, Color3.fromRGB(70, 66, 78), Enum.Material.Metal, 16)
		lightFlash(position, color, 8, 40, 0.8)
		Effects.Sound(Sounds.GateBreak, position, 1)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - position).Magnitude < 60 then
			Effects.Shake(5, 0.6)
		end
	end,
	GateReforge = function(position: Vector3, color: Color3)
		Effects.Burst(position, color, 40, 12, 0.8)
		Effects.Sound(Sounds.Unsheath, position, 0.8)
	end,
	GateRepair = function(position: Vector3, color: Color3)
		Effects.Burst(position, Color3.fromRGB(120, 255, 140), 30, 10, 0.6)
		Effects.FloatText(position + Vector3.new(0, 6, 0), "REPAIRED!", Color3.fromRGB(120, 255, 140))
		Effects.Sound(Sounds.GateHit, position, 0.4)
		local _ = color
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
	Recovered = function(position: Vector3, color: Color3)
		Effects.Burst(position + Vector3.new(0, 3, 0), color, 50, 20, 0.8)
		Effects.Sound(Sounds.Cash, position, 0.8)
	end,
	Knockdown = function(position: Vector3)
		Effects.Burst(position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 230, 120), 30, 14, 0.6)
		Effects.Sound(Sounds.Knockdown, position, 0.8)
		Effects.FloatText(position + Vector3.new(0, 4, 0), "KO!", Color3.fromRGB(255, 230, 120))
	end,
	BurglarSpawn = function(position: Vector3)
		smoke(position)
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
	Barricade = function(position: Vector3)
		smoke(position)
		Effects.Sound(Sounds.GateHit, position, 0.7)
		Effects.Shake(1.5, 0.2)
	end,
	Smash = function(position: Vector3)
		debris(position, Color3.fromRGB(150, 98, 54), Enum.Material.WoodPlanks, 14)
		Effects.Sound(Sounds.WoodBreak, position, 1)
	end,
	NoEnergy = function(_id: string)
		Effects.Sound(Sounds.Tick, nil, 0.6)
		Effects.Shake(0.8, 0.15)
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
	WallsUp = function(_who: Player, position: Vector3)
		smoke(position)
		Effects.Sound(Sounds.GateBreak, position, 0.6)
	end,
	ChestOpen = function(position: Vector3, _who: Player)
		pillar(position, Color3.fromRGB(255, 220, 90), 40, 1.2)
		Effects.Burst(position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 220, 90), 60, 25, 0.9)
		Effects.Sound(Sounds.Reveal, position, 0.8)
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
		end
	end,
	IndexClaim = function(cash: number, speed: number)
		Effects.Sound(Sounds.Reveal, nil, 0.7)
		local root = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
		if root then
			Effects.FloatText(
				root.Position + Vector3.new(0, 3, 0),
				`+${Format.Short(cash)}  +{Format.Short(speed)}⚡`,
				Color3.fromRGB(255, 230, 90)
			)
			Effects.Burst(root.Position, Color3.fromRGB(80, 170, 255), 50, 20, 0.8)
		end
	end,
}

-- 🤝 Your teammate is outlined green in the hub (so you can find each other)
local function trackTeammate()
	local current: Highlight? = nil
	local function refresh()
		if current then
			current:Destroy()
			current = nil
		end
		local id = player:GetAttribute("Partner")
		local mate = if type(id) == "number" then Players:GetPlayerByUserId(id) else nil
		local character = mate and mate.Character
		if character and not player:GetAttribute("InRound") then
			local highlight = Instance.new("Highlight")
			highlight.Name = "TeammateOutline"
			highlight.FillTransparency = 1
			highlight.OutlineColor = Color3.fromRGB(90, 255, 120)
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.Adornee = character
			highlight.Parent = character
			current = highlight
		end
	end
	player:GetAttributeChangedSignal("Partner"):Connect(refresh)
	player:GetAttributeChangedSignal("InRound"):Connect(refresh)
	task.spawn(function()
		while true do
			task.wait(3) -- they respawn / stream in
			refresh()
		end
	end)
end

function Effects.Init()
	trackTeammate()
	local pendingRolls: { { any } } = {}
	local rollWorker = false
	Remotes:WaitForChild("Effect").OnClientEvent:Connect(function(kind: string, ...)
		local handler = handlers[kind]
		if kind == "PowerRoll" then
			table.insert(pendingRolls, { ... })
			Ui.gui:SetAttribute("PendingPowerRolls", #pendingRolls)
			if not rollWorker then
				rollWorker = true
				task.spawn(function()
					while #pendingRolls > 0 do
						while
							Ui.gui:GetAttribute("Presenting") == true
							or Ui.gui:GetAttribute("FadeCover") == true
							or player:GetAttribute("InRound")
						do
							task.wait(0.1)
						end
						local args = table.remove(pendingRolls, 1) :: { any }
						handlers.PowerRoll(table.unpack(args))
						Ui.gui:SetAttribute("PendingPowerRolls", #pendingRolls)
					end
					rollWorker = false
				end)
			end
			return
		end
		if handler then
			handler(...)
		end
	end)

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
	local wheels: { [Model]: CFrame } = {}
	local function trackWheel(wheel: Instance)
		local pivot = wheel:GetAttribute("Pivot")
		if wheel:IsA("Model") and typeof(pivot) == "CFrame" then
			wheels[wheel] = pivot -- the server's resting position, not whatever has streamed in yet
		end
	end
	for _, wheel in CollectionService:GetTagged("HauntedWheel") do
		trackWheel(wheel)
	end
	CollectionService:GetInstanceAddedSignal("HauntedWheel"):Connect(trackWheel)
	local wheelAngles: { [Model]: number } = {}
	local WHEEL_SEGMENT = math.pi * 2 / 24 -- the repeating rim / tread pattern (WheelTiers)
	-- Segments turned per frame, by wheel tier. Up to ~0.45 the eye follows it forwards (that's as
	-- fast as a wheel can LOOK); around 0.5 it strobes; past that it reads as rolling backwards,
	-- faster the further below 1 it is (0.7 = a fast backwards roll). Per frame, not per second, so
	-- it reads the same on a 30 fps phone and a 144 Hz PC.
	local WHEEL_STEPS = { 0.12, 0.17, 0.22, 0.27, 0.32, 0.36, 0.40, 0.43, 0.46, 0.5, 0.55, 0.64, 0.7 }
	-- Sparks spraying off the tread under the runner's feet: none on the first wheels, a fountain on
	-- the top ones (an invisible anchored emitter part per wheel, at the inside bottom of the rim)
	local sparks: { [Model]: ParticleEmitter } = {}
	local sparkFolder = Instance.new("Folder")
	sparkFolder.Name = "WheelSparks"
	sparkFolder.Parent = workspace
	local function sparksFor(wheel: Model, base: CFrame): ParticleEmitter
		local existing = sparks[wheel]
		if existing then
			return existing
		end
		local anchor = Instance.new("Part")
		anchor.Name = "Sparks"
		anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(2.5, 0.2, 0.6)
		anchor.CFrame = base * CFrame.new(0, -5.1, 0)
		anchor.Parent = sparkFolder
		local p = Instance.new("ParticleEmitter")
		p.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		p.Color = ColorSequence.new(Color3.fromRGB(255, 250, 210), Color3.fromRGB(255, 170, 60))
		p.LightEmission = 1
		p.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		p.Lifetime = NumberRange.new(0.25, 0.55)
		p.Speed = NumberRange.new(14, 26)
		p.SpreadAngle = Vector2.new(35, 35)
		p.Acceleration = Vector3.new(0, -60, 0)
		p.EmissionDirection = Enum.NormalId.Top
		p.Drag = 2
		p.Rate = 0
		p.Parent = anchor
		sparks[wheel] = p
		wheel.Destroying:Once(function()
			sparks[wheel] = nil
			anchor:Destroy()
		end)
		return p
	end
	local rumbleAt = 0
	RunService.RenderStepped:Connect(function(_dt: number)
		for wheel, spark in sparks do
			if not wheel.Parent or not wheel:GetAttribute("Spinning") then
				spark.Rate = 0
			end
		end
		for wheel, base in wheels do
			if not wheel.Parent then
				wheels[wheel] = nil
				wheelAngles[wheel] = nil
			elseif wheel:GetAttribute("Spinning") and wheel.PrimaryPart and Lod.Near(base.Position) then
				-- Faster wheel tiers spin faster; the rungs roll back under the runner's feet. Steal An
				-- Egg's trick at the top: every wheel has 24 identical segments, so turning by just under
				-- one segment a frame reads as the wheel rolling BACKWARDS (it's really flying round),
				-- and a bit less than that reads as a strobing blur - at any frame rate
				local tier = math.clamp((wheel:GetAttribute("Tier") or 1) :: number, 1, #WHEEL_STEPS)
				local step = WHEEL_SEGMENT * WHEEL_STEPS[tier]
				local angle = (wheelAngles[wheel] or 0) + step
				wheelAngles[wheel] = angle
				wheel:PivotTo(base * CFrame.Angles(angle, 0, 0))
				sparksFor(wheel, base).Rate = math.max(0, tier - 2) * 9
			end
		end
		-- Your own wheel, top tiers: the camera rumbles like the wheel is shaking under you
		local level = (player:GetAttribute("TreadmillLevel") or 1) :: number
		if player:GetAttribute("Training") and level >= 7 and os.clock() >= rumbleAt then
			rumbleAt = os.clock() + 0.12
			Effects.Shake(0.4 + (level - 7) * 0.15, 0.2) -- degrees: ~0.4 on wheel 7, ~1.3 on the Cosmic Wheel
		end
	end)

	-- Keep exposure steady across joins and round teleports; room lamps supply the mood.
	local Lighting = game:GetService("Lighting")
	local function roundLighting()
		local inRound = player:GetAttribute("InRound") == true
		local info = TweenInfo.new(1.2, Enum.EasingStyle.Quad)
		-- (exposure, bloom and the rest of the mood: client/ZoneLighting)
		-- Round maps are indoors with no lamps: rounds get warm, neutral room light, and the hub's
		-- own values (published by the server as Lighting attributes, MapService) come back after.
		-- Never cache Lighting here: the client can start before the server has set it up.
		local hubAmbient = Lighting:GetAttribute("HubAmbient")
		local hubOutdoor = Lighting:GetAttribute("HubOutdoor")
		if inRound then
			TweenService:Create(Lighting, info, {
				Ambient = Color3.fromRGB(165, 160, 150),
				OutdoorAmbient = Color3.fromRGB(170, 165, 155),
			}):Play()
		elseif typeof(hubAmbient) == "Color3" and typeof(hubOutdoor) == "Color3" then
			TweenService:Create(Lighting, info, { Ambient = hubAmbient, OutdoorAmbient = hubOutdoor }):Play()
		end
	end
	player:GetAttributeChangedSignal("InRound"):Connect(roundLighting)
	roundLighting()

	-- While training you keep facing the way you run (the server turns you once you step in)
	player:GetAttributeChangedSignal("Training"):Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.AutoRotate = not player:GetAttribute("Training")
		end
	end)

	-- Every stride on your own wheel pops a "+Speed" number and a soft footstep
	local strideTimer = 0
	RunService.RenderStepped:Connect(function(dt: number)
		if not player:GetAttribute("Training") then
			strideTimer = 0
			return
		end
		local level = (player:GetAttribute("TreadmillLevel") or 1) :: number
		local stride = 0.6 / (1 + level * 0.12) -- quicker steps on better wheels
		strideTimer += dt
		if strideTimer < stride then
			return
		end
		strideTimer = 0
		local character = player.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		if head then
			local rate = GameConfig.Treadmills[level] and GameConfig.Treadmills[level].Rate or 0
			local gained = math.max(1, math.floor(rate * stride))
			local jitter = Vector3.new(math.random(-10, 10) / 10, 2.5, math.random(-10, 10) / 10)
			Effects.FloatText(head.Position + jitter, `+{Format.Short(gained)} ⚡`, Color3.fromRGB(120, 200, 255))
			Effects.Sound("rbxasset://sounds/action_footsteps_plastic.mp3", head.Position, 0.25)
		end
	end)

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

	-- Rack "Sell" prompts belong to one player; hide everyone else's
	local function filterPrompt(instance: Instance)
		-- (raid "Steal" prompts are managed by client/Raid)
		if instance:IsA("ProximityPrompt") and not instance:GetAttribute("Steal") then
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
