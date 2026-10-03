--!strict
-- Server-selected rewards only; the reel is presentation and never rolls a grant.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Ui = require(script.Parent.Ui)
local Effects = require(script.Parent.Effects)
local Items = require(ReplicatedStorage.Shared.Items)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local View = {}

function View.Play(rarity: string, item: string, upgraded: boolean, isNew: boolean)
	local parsed = Items.Parse(item)
	if not parsed then
		return
	end
	local color = Items.Color(item)
	local frame = Ui.new("Frame", { Name = "Unbox", BackgroundColor3 = Ui.PANEL, ZIndex = 30 }, Ui.gui)
	Ui.corner(frame, 16)
	Ui.fitMenu(frame, Vector2.new(900, 520))
	Ui.registerMenu(frame)
	local title = Ui.label({
		Text = "Opening " .. rarity .. " Case",
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -84, 0, 44),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 31,
	}, frame)
	local skipped, dismissed = false, false
	local close = Ui.button(
		{
			Name = "Close",
			Text = "Skip",
			Position = UDim2.new(1, -68, 0, 8),
			Size = UDim2.fromOffset(60, 44),
			ZIndex = 32,
		},
		frame,
		function()
			if skipped then
				dismissed = true
			else
				skipped = true
			end
		end
	)
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not frame.Visible then
			skipped = true
			dismissed = true
		end
	end)
	local scroll = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 64),
		Size = UDim2.new(1, -24, 1, -76),
		BackgroundTransparency = 1,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ZIndex = 31,
	}, frame)
	local window = Ui.new("Frame", {
		Size = UDim2.new(1, -8, 0, 150),
		ClipsDescendants = true,
		BackgroundColor3 = Color3.fromRGB(14, 23, 41),
		ZIndex = 31,
	}, scroll)
	Ui.corner(window, 12)
	local strip = Ui.new("Frame", {
		Size = UDim2.fromOffset(34 * 130, 144),
		Position = UDim2.fromOffset(window.AbsoluteSize.X / 2 - 60, 3),
		BackgroundTransparency = 1,
		ZIndex = 31,
	}, window)
	local rng = Random.new()
	local pool = Knives.ByRarity[rarity]
	for i = 1, 34 do
		local knife = if i == 29 then parsed.Knife else pool[rng:NextInteger(1, #pool)]
		local tile = Ui.new("Frame", {
			Position = UDim2.fromOffset((i - 1) * 130, 0),
			Size = UDim2.fromOffset(120, 144),
			BackgroundColor3 = Knives.RarityColors[knife.Rarity]:Lerp(Ui.PANEL, 0.7),
			ZIndex = 31,
		}, strip)
		Ui.corner(tile, 10)
		Ui.art(tile, knife.Name, { Size = UDim2.new(1, 0, 0, 90), ZIndex = 31 })
		Ui.label({
			Text = knife.DisplayName,
			Position = UDim2.fromOffset(4, 90),
			Size = UDim2.new(1, -8, 0, 50),
			TextSize = 14,
			TextScaled = false,
			TextWrapped = true,
			ZIndex = 32,
		}, tile)
	end
	Ui.new("Frame", {
		Position = UDim2.new(0.5, -2, 0, 0),
		Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = Color3.fromRGB(255, 215, 80),
		ZIndex = 33,
	}, window)
	-- Wait for fitting/layout to resolve before choosing the reel's center.
	RunService.RenderStepped:Wait()
	local startX = window.AbsoluteSize.X / 2 - 60
	strip.Position = UDim2.fromOffset(startX, 3)
	local endX = startX - 28 * 130
	local spin = TweenService:Create(
		strip,
		TweenInfo.new(3.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(endX, 3) }
	)
	local last = -1
	local tick = RunService.RenderStepped:Connect(function()
		local index = math.floor((startX - strip.Position.X.Offset) / 130)
		if index ~= last then
			last = index
			Effects.Sound(Sounds.Tick, nil, 0.25)
		end
	end)
	spin:Play()
	local started = os.clock()
	while not skipped and spin.PlaybackState == Enum.PlaybackState.Playing and os.clock() - started < 4 do
		task.wait()
	end
	spin:Cancel()
	tick:Disconnect()
	strip.Position = UDim2.fromOffset(endX, 3)
	if not dismissed then
		title.Text = "Case reward"
		close.Text = "X"
		skipped = true
		Effects.Sound(Sounds.Reveal, nil, 0.7)
		local tags = (if isNew then "NEW!  " else "") .. (if upgraded then "RARITY UP!  " else "")
		local text = Ui.label({
			Text = tags
				.. Items.DisplayName(item)
				.. `\n{parsed.Knife.Rarity} · +${Ui.abbreviate(Items.Income(item))}/s · Damage {Items.Damage(item)}\nMutation: {parsed.Mutation.DisplayName} · Size: {parsed.Size.DisplayName}`,
			Position = UDim2.fromOffset(8, 158),
			Size = UDim2.new(1, -24, 0, 100),
			TextScaled = false,
			TextSize = 16,
			TextWrapped = true,
			TextColor3 = color,
			ZIndex = 32,
		}, scroll)
		Ui.textStroke(text, 1)
		local revealed = os.clock()
		while not dismissed and os.clock() - revealed < 2.7 do
			task.wait()
		end
	end
	frame:Destroy()
end
return View
