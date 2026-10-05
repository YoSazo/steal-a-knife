--!strict
-- Server-selected rewards only; the reel is presentation and never rolls a grant.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local Effects = require(script.Parent.Effects)
local Items = require(ReplicatedStorage.Shared.Items)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local View = {}

function View.Play(rarity: string, item: string, upgraded: boolean, isNew: boolean, lucky: boolean?)
	local parsed = Items.Parse(item)
	if not parsed then
		return
	end
	local color = Items.Color(item)
	local rarityColor = Knives.RarityColors[rarity] or color
	-- Same philosophy as every other window: a solid-colour header (the case's own rarity
	-- colour) with a real icon, a red X, and a see-through dark body.
	local frame = Ui.new("Frame", {
		Name = "Unbox",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(14, 16, 26),
		BackgroundTransparency = 0.25,
		ZIndex = 30,
	}, Ui.gui)
	Ui.corner(frame, 16)
	Theme.outline(frame, Theme.Black, 4)
	-- (just tall enough for the reel and the reward card under it)
	Ui.fitMenu(frame, Vector2.new(900, 380))
	Ui.registerMenu(frame)
	local header = Theme.surface(frame, { Size = UDim2.new(1, 0, 0, 64), ZIndex = 31 }, rarityColor)
	local headerCorner = header:FindFirstChildOfClass("UICorner") :: UICorner
	headerCorner.CornerRadius = UDim.new(0, 16)
	Theme.image(header, "Case" .. rarity, { Position = UDim2.fromOffset(6, 2), Size = UDim2.fromOffset(60, 60) })
	local title = Theme.text(header, "Opening " .. rarity .. (if lucky then " Lucky Block" else " Case"), {
		Position = UDim2.fromOffset(74, 2),
		Size = UDim2.new(1, -150, 1, -4),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaximumTextSize = 34,
	})
	local skipped, dismissed = false, false
	local close = Theme.button(header, "Skip", Theme.Red, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(74, 50),
		MaximumTextSize = 28,
	}, function()
		if skipped then
			dismissed = true
		else
			skipped = true
		end
	end)
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not frame.Visible then
			skipped = true
			dismissed = true
		end
	end)
	local scroll = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 76),
		Size = UDim2.new(1, -24, 1, -88),
		BackgroundTransparency = 1,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ZIndex = 31,
	}, frame)
	local window = Ui.new("Frame", {
		Size = UDim2.new(1, -8, 0, 150),
		ClipsDescendants = true,
		BackgroundColor3 = Color3.fromRGB(14, 16, 26),
		BackgroundTransparency = 0.25,
		ZIndex = 31,
	}, scroll)
	Ui.corner(window, 12)
	Theme.outline(window, Theme.Black, 3)
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
		-- The knife's own rarity colour, full strength with a black outline (not a muddy
		-- navy-tinted one) - same as the Index and every other knife card.
		local tile = Theme.surface(strip, {
			Position = UDim2.fromOffset((i - 1) * 130, 0),
			Size = UDim2.fromOffset(120, 144),
			ZIndex = 31,
		}, Knives.RarityColors[knife.Rarity])
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
			Effects.Sound(Sounds.ReelTick, nil, 0.35)
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
		title.Text = if lucky then "Lucky Block Reward" else "Case Reward"
		Theme.enabled(close, true, "X")
		skipped = true
		Effects.Sound(Sounds.Reveal, nil, 0.7)
		local tags = (if isNew then "NEW!  " else "") .. (if upgraded then "RARITY UP!  " else "")
		-- A solid card in the knife's own colour, not plain floating text.
		local reveal = Theme.surface(scroll, {
			Position = UDim2.fromOffset(4, 158),
			Size = UDim2.new(1, -16, 0, 110),
			ZIndex = 31,
		}, color)
		Theme.text(reveal, tags .. Items.DisplayName(item), {
			Position = UDim2.fromOffset(10, 6),
			Size = UDim2.new(1, -20, 0, 36),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaximumTextSize = 30,
		})
		Theme.text(
			reveal,
			`{parsed.Knife.Rarity} · +${Ui.abbreviate(Items.Income(item))}/s · Damage {Items.Damage(item)}`,
			{
				Position = UDim2.fromOffset(10, 46),
				Size = UDim2.new(1, -20, 0, 28),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaximumTextSize = 22,
			}
		)
		Theme.text(reveal, `Mutation: {parsed.Mutation.DisplayName} · Size: {parsed.Size.DisplayName}`, {
			Position = UDim2.fromOffset(10, 76),
			Size = UDim2.new(1, -20, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaximumTextSize = 20,
		})
		local revealed = os.clock()
		while not dismissed and os.clock() - revealed < 2.7 do
			task.wait()
		end
	end
	frame:Destroy()
end
return View
