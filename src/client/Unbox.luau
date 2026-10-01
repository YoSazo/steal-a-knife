--!strict
-- The case reveal: a reel of knife cards spins past a marker (with a tick for every card and a
-- drum roll), slows, and lands on what you got. The winner pops with its mutation's colour,
-- confetti, and "NEW!" / "RARITY UP!" banners. Click to skip. The server already decided the item
-- (StealService.OpenCase); this is pure show.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Ui = require(script.Parent.Ui)
local Effects = require(script.Parent.Effects)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Knives = require(Shared.Config:WaitForChild("Knives"))
local KnifeModel = require(Shared:WaitForChild("KnifeModel"))
local Sounds = require(Shared.Config:WaitForChild("Sounds"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local new = Ui.new

local Unbox = {}

local CARD_W, CARD_H, GAP = 150, 190, 10
local CARDS = 34
local WINNER = 29
local SPIN_TIME = 3.1

local queue: { { Rarity: string, Item: string, Upgraded: boolean, IsNew: boolean } } = {}
local playing = false

local function knifeCard(parent: Instance, item: string, index: number): Frame
	local parsed = Items.Parse(item) :: Items.Item
	local color = Items.Color(item)
	local rarityColor = Knives.RarityColors[parsed.Knife.Rarity]
	local card = new("Frame", {
		Position = UDim2.fromOffset((index - 1) * (CARD_W + GAP), 0),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = Color3.new(1, 1, 1),
	}, parent)
	Ui.corner(card, 14)
	Ui.gradient(
		card,
		rarityColor:Lerp(Color3.fromRGB(20, 16, 28), 0.3),
		rarityColor:Lerp(Color3.fromRGB(20, 16, 28), 0.85)
	)
	new("UIStroke", { Thickness = 3, Color = color }, card)
	local view = new("ViewportFrame", {
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(210, 210, 210),
		LightColor = Color3.new(1, 1, 1),
	}, card)
	local model = KnifeModel.Build(item, true)
	model:PivotTo(CFrame.Angles(0, 0, math.rad(-40))) -- flat of the blade to the camera, tilted
	model.Parent = view
	local camera = new("Camera", { FieldOfView = 30 }, view)
	view.CurrentCamera = camera
	local cf, size = model:GetBoundingBox()
	camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, 0, size.Magnitude * 1.6), cf.Position)
	local name = Ui.label({
		Position = UDim2.fromOffset(6, 122),
		Size = UDim2.new(1, -12, 0, 40),
		Text = Items.DisplayName(item),
		TextColor3 = color,
	}, card)
	Ui.textStroke(name, 2)
	local rarity = Ui.label({
		Position = UDim2.fromOffset(6, 164),
		Size = UDim2.new(1, -12, 0, 20),
		Text = parsed.Knife.Rarity,
		TextColor3 = rarityColor,
	}, card)
	Ui.textStroke(rarity, 1.5)
	return card
end

-- Filler for the reel: mostly the case's own rarity, a sprinkle of the next one up, some mutated
local function filler(rng: Random, rarity: string): string
	local index = table.find(Knives.Rarities, rarity) or 1
	if index < #Knives.Rarities and rng:NextNumber() < 0.12 then
		index += 1
	end
	local pool = Knives.ByRarity[Knives.Rarities[index]]
	local knife = pool[rng:NextInteger(1, #pool)]
	local mutation, size = Items.Roll(rng, 4) -- tease: show off mutations more than they really drop
	return Items.Make(knife.Name, mutation.Id, size.Id)
end

local function confetti(parent: Instance, color: Color3)
	for _ = 1, 60 do
		local bit = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromOffset(math.random(6, 14), math.random(10, 20)),
			BackgroundColor3 = if math.random() < 0.5 then color else Color3.fromHSV(math.random(), 0.7, 1),
			Rotation = math.random(0, 360),
			ZIndex = 50,
		}, parent)
		local angle = math.random() * math.pi * 2
		local distance = math.random(200, 520)
		local info = TweenInfo.new(math.random(9, 16) / 10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(bit, info, {
			Position = UDim2.new(0.5, math.cos(angle) * distance, 0.45, math.sin(angle) * distance * 0.7 + 120),
			Rotation = bit.Rotation + math.random(-360, 360),
			BackgroundTransparency = 1,
		}):Play()
	end
end

local function play(rarity: string, item: string, upgraded: boolean, isNew: boolean)
	playing = true
	local parsed = Items.Parse(item) :: Items.Item
	local color = Items.Color(item)
	local hype = Items.Hype(item)
	local rng = Random.new()

	local gui = new("ScreenGui", {
		Name = "Unbox",
		IgnoreGuiInset = true,
		DisplayOrder = 30,
		ResetOnSpawn = false,
	}, player:WaitForChild("PlayerGui"))
	local scale = new("UIScale", {}, gui)
	local camera = workspace.CurrentCamera
	scale.Scale = math.clamp(math.min(camera.ViewportSize.X / 1100, camera.ViewportSize.Y / 700), 0.55, 1.2)
	local backdrop = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(8, 6, 14),
		BackgroundTransparency = 1,
	}, gui)
	TweenService:Create(backdrop, TweenInfo.new(0.3), { BackgroundTransparency = 0.3 }):Play()

	local title = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.16),
		Size = UDim2.fromOffset(700, 60),
		Text = `OPENING {rarity:upper()} CASE`,
		TextColor3 = Knives.RarityColors[rarity],
	}, gui)
	Ui.textStroke(title, 3)

	-- The reel: a window the cards slide through, with a marker in the middle
	local window = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(900, CARD_H + 30),
		BackgroundColor3 = Color3.fromRGB(16, 12, 24),
		BackgroundTransparency = 0.1,
		ClipsDescendants = true,
	}, gui)
	Ui.corner(window, 16)
	new("UIStroke", { Thickness = 4, Color = Knives.RarityColors[rarity] }, window)
	local strip = new("Frame", {
		Position = UDim2.fromOffset(450 - CARD_W / 2, 15),
		Size = UDim2.fromOffset(CARDS * (CARD_W + GAP), CARD_H),
		BackgroundTransparency = 1,
	}, window)
	local winnerCard: Frame? = nil
	for i = 1, CARDS do
		local cardItem = if i == WINNER then item else filler(rng, rarity)
		local c = knifeCard(strip, cardItem, i)
		if i == WINNER then
			winnerCard = c
		end
	end
	local marker = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = Color3.fromRGB(255, 220, 80),
		ZIndex = 10,
	}, window)
	for _, y in { 0, 1 } do
		local arrow = Ui.label({
			AnchorPoint = Vector2.new(0.5, y),
			Position = UDim2.fromScale(0.5, y),
			Size = UDim2.fromOffset(40, 30),
			Text = if y == 0 then "▼" else "▲",
			TextColor3 = Color3.fromRGB(255, 220, 80),
			ZIndex = 11,
		}, window)
		Ui.textStroke(arrow, 2)
	end
	local _ = marker

	-- Spin: land somewhere inside the winning card (never exactly centred: feels real)
	local landing = -((WINNER - 1) * (CARD_W + GAP)) + rng:NextNumber(-CARD_W * 0.35, CARD_W * 0.35)
	local startX = strip.Position.X.Offset
	local endX = startX + landing
	local drum = Instance.new("Sound")
	drum.SoundId = Sounds.DrumRoll
	drum.Volume = 0.5
	drum.Looped = true
	drum.Parent = gui
	drum:Play()
	local tween = TweenService:Create(
		strip,
		TweenInfo.new(SPIN_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(endX, 15) }
	)
	local lastIndex = 0
	local tick = RunService.RenderStepped:Connect(function()
		local offset = startX - strip.Position.X.Offset
		local index = math.floor((offset + CARD_W / 2) / (CARD_W + GAP))
		if index ~= lastIndex then
			lastIndex = index
			Effects.Sound(Sounds.Tick, nil, 0.25)
		end
	end)
	local skipped = false
	local skip = UserInputService.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			skipped = true
		end
	end)
	tween:Play()
	local started = os.clock()
	while
		tween.PlaybackState == Enum.PlaybackState.Playing
		and not skipped
		and os.clock() - started < SPIN_TIME + 0.5
	do
		task.wait()
	end
	tween:Cancel()
	strip.Position = UDim2.fromOffset(endX, 15)
	tick:Disconnect()
	skip:Disconnect()
	drum:Stop()

	-- The reveal
	Effects.Sound(Sounds.Reveal, nil, 0.7)
	if hype >= 2 then
		Effects.Sound(Sounds.Cheer, nil, 0.4)
		Effects.Shake(2, 0.4)
	end
	if winnerCard then
		local pop = new("UIScale", {}, winnerCard)
		TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1.12 }):Play()
		local glow = winnerCard:FindFirstChildOfClass("UIStroke")
		if glow then
			glow.Thickness = 6
		end
	end
	local flashFrame = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.35,
		ZIndex = 40,
	}, gui)
	TweenService:Create(flashFrame, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	confetti(gui, color)

	local result = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(820, 70),
		Text = Items.DisplayName(item),
		TextColor3 = color,
		ZIndex = 45,
	}, gui)
	Ui.textStroke(result, 4)
	if parsed.Mutation.Id == "Rainbow" then
		local gradient = new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
				ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 230, 90)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 255, 140)),
				ColorSequenceKeypoint.new(0.75, Color3.fromRGB(90, 170, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
			}),
		}, result)
		result.TextColor3 = Color3.new(1, 1, 1)
		task.spawn(function()
			while gradient.Parent do
				gradient.Offset = Vector2.new(math.sin(os.clock() * 2) * 0.6, 0)
				task.wait()
			end
		end)
	end
	local resultScale = new("UIScale", { Scale = 0.3 }, result)
	TweenService:Create(resultScale, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	local detail = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.62, 74),
		Size = UDim2.fromOffset(700, 34),
		Text = `{parsed.Knife.Rarity}  ·  +${Ui.abbreviate(Items.Income(item))}/s  ·  Damage {Items.Damage(item)}`,
		TextColor3 = Color3.fromRGB(120, 255, 140),
		ZIndex = 45,
	}, gui)
	Ui.textStroke(detail, 2.5)
	local tags = {}
	if isNew then
		table.insert(tags, "NEW!")
	end
	if upgraded then
		table.insert(tags, "RARITY UP!")
	end
	if parsed.Mutation.Rank > 0 then
		table.insert(tags, `{parsed.Mutation.DisplayName:upper()} x{parsed.Mutation.Income}`)
	end
	if parsed.Size.Rank > 0 then
		table.insert(tags, `{parsed.Size.DisplayName:upper()} x{parsed.Size.Income}`)
	end
	if #tags > 0 then
		local tagLabel = Ui.label({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0.62, -6),
			Size = UDim2.fromOffset(700, 40),
			Text = table.concat(tags, "   "),
			TextColor3 = Color3.fromRGB(255, 230, 90),
			Rotation = -3,
			ZIndex = 45,
		}, gui)
		Ui.textStroke(tagLabel, 3)
	end

	task.wait(if skipped then 1.2 else 1.8 + math.min(hype, 3) * 0.3)
	local fade = TweenInfo.new(0.35)
	for _, d in gui:GetDescendants() do
		if d:IsA("GuiObject") then
			TweenService:Create(d, fade, { BackgroundTransparency = 1 }):Play()
			if d:IsA("TextLabel") then
				TweenService:Create(d, fade, { TextTransparency = 1 }):Play()
			elseif d:IsA("ViewportFrame") then
				TweenService:Create(d, fade, { ImageTransparency = 1 }):Play()
			end
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, fade, { Transparency = 1 }):Play()
		end
	end
	task.wait(0.4)
	gui:Destroy()
	playing = false
	local nextOne = table.remove(queue, 1)
	if nextOne then
		play(nextOne.Rarity, nextOne.Item, nextOne.Upgraded, nextOne.IsNew)
	end
end

function Unbox.Init()
	Remotes:WaitForChild("Effect").OnClientEvent:Connect(function(kind: string, ...)
		if kind ~= "Unbox" then
			return
		end
		local rarity, item, upgraded, isNew = ...
		if type(item) ~= "string" or not Items.Parse(item) then
			return
		end
		if playing then
			table.insert(queue, { Rarity = rarity, Item = item, Upgraded = upgraded, IsNew = isNew })
		else
			task.spawn(play, rarity, item, upgraded == true, isNew == true)
		end
	end)
end

return Unbox
