--!strict
-- The welcome-back card, shown once when you join (the server sends Remotes.Welcome):
--   * what your vault earned while you were away (already paid)
--   * the 7-day login streak, with today's reward to claim (Remotes.ClaimDaily)
--   * the new-player shield, for people who just started

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Effects = require(script.Parent.Effects)
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local Sounds = require(ReplicatedStorage.Shared.Config:WaitForChild("Sounds"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local new = Ui.new

local Welcome = {}

type Info = { Offline: number, Away: number, Streak: number, DailyReady: boolean, Shielded: boolean? }

local GOLD = Color3.fromRGB(255, 205, 60)
local RARITY_COLORS: { [string]: Color3 } = {
	Common = Color3.fromRGB(170, 175, 185),
	Rare = Color3.fromRGB(80, 160, 255),
	Epic = Color3.fromRGB(180, 90, 255),
	Legendary = Color3.fromRGB(255, 190, 40),
	Godly = Color3.fromRGB(255, 80, 120),
}

local function rewardText(reward: GameConfig.DailyReward): (string, string, Color3)
	if reward.Kind == "Case" then
		local rarity = reward.Rarity or "Common"
		return "📦", `{rarity} Case`, RARITY_COLORS[rarity] or GOLD
	elseif reward.Kind == "Tickets" then
		return "🎟️", `{reward.Amount or 1} Tickets`, Color3.fromRGB(230, 70, 90)
	end
	return "💰", "Cash", Color3.fromRGB(90, 210, 110)
end

local function awayText(seconds: number): string
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	if hours >= 1 then
		return `{hours}h {minutes}m`
	end
	return `{minutes}m`
end

local function show(info: Info)
	local nothingNew = info.Offline <= 0 and not info.DailyReady and not info.Shielded
	if nothingNew then
		return
	end

	local dim = new("Frame", {
		Name = "Welcome",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(30, 26, 23),
		BackgroundTransparency = 0.78,
		ZIndex = 50,
	}, Ui.gui)
	local card = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 430),
		BackgroundColor3 = Ui.PANEL,
		ZIndex = 51,
	}, dim)
	Ui.corner(card, 18)
	new("UIStroke", { Thickness = 4, Color = Color3.fromRGB(20, 16, 28) }, card)
	Ui.gradient(card, Color3.fromRGB(48, 38, 66), Color3.fromRGB(24, 20, 34))
	local scale = new("UIScale", { Scale = 0.6 }, card)
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()

	local title = Ui.label({
		Size = UDim2.new(1, -40, 0, 54),
		Position = UDim2.fromOffset(20, 14),
		Text = if info.Away > 0 then "WELCOME BACK!" else "WELCOME TO BLACKWOOD!",
		Font = Ui.SPOOKY,
		TextColor3 = GOLD,
		ZIndex = 52,
	}, card)
	Ui.textStroke(title, 3)

	local y = 78
	if info.Offline > 0 then
		local earned = Ui.label({
			Size = UDim2.new(1, -40, 0, 34),
			Position = UDim2.fromOffset(20, y),
			Text = `💰 Your vault earned ${Ui.abbreviate(info.Offline)} while you were away ({awayText(info.Away)})`,
			TextColor3 = Color3.fromRGB(140, 240, 150),
			ZIndex = 52,
		}, card)
		Ui.textStroke(earned, 2)
		y += 44
	end
	if info.Shielded then
		local shield = Ui.label({
			Size = UDim2.new(1, -40, 0, 30),
			Position = UDim2.fromOffset(20, y),
			Text = `🛡️ New-player shield: nobody can steal your knives for your first {GameConfig.NewPlayerShield // 60} minutes`,
			TextColor3 = Color3.fromRGB(150, 210, 255),
			ZIndex = 52,
		}, card)
		Ui.textStroke(shield, 2)
		y += 40
	end

	-- The streak: seven days, today's lit up
	local heading = Ui.label({
		Size = UDim2.new(1, -40, 0, 28),
		Position = UDim2.fromOffset(20, y),
		Text = "DAILY STREAK - log in every day, miss one and it starts over",
		TextColor3 = Color3.fromRGB(230, 220, 255),
		ZIndex = 52,
	}, card)
	Ui.textStroke(heading, 2)
	y += 36
	local row = new("Frame", {
		Size = UDim2.new(1, -40, 0, 104),
		Position = UDim2.fromOffset(20, y),
		BackgroundTransparency = 1,
		ZIndex = 52,
	}, card)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
	}, row)
	local today = info.Streak
	for day, reward in GameConfig.Daily do
		local icon, text, color = rewardText(reward)
		local claimed = day < today or (day == today and not info.DailyReady)
		local isToday = day == today
		local tile = new("Frame", {
			Size = UDim2.fromOffset(76, if isToday then 104 else 92),
			BackgroundColor3 = if isToday then color else Color3.fromRGB(40, 34, 54),
			BackgroundTransparency = if claimed and not isToday then 0.4 else 0,
			ZIndex = 53,
		}, row)
		Ui.corner(tile, 10)
		new("UIStroke", { Thickness = if isToday then 3 else 2, Color = if isToday then GOLD else color }, tile)
		local dayLabel = Ui.label({
			Size = UDim2.new(1, -6, 0, 20),
			Position = UDim2.fromOffset(3, 4),
			Text = if claimed then "✓ DAY " .. day else "DAY " .. day,
			ZIndex = 54,
		}, tile)
		Ui.textStroke(dayLabel, 1.5)
		Ui.label({
			Size = UDim2.new(1, 0, 0, 36),
			Position = UDim2.fromOffset(0, 26),
			Text = icon,
			ZIndex = 54,
		}, tile)
		local what = Ui.label({
			Size = UDim2.new(1, -6, 0, 22),
			Position = UDim2.new(0, 3, 1, -28),
			Text = text,
			ZIndex = 54,
		}, tile)
		Ui.textStroke(what, 1.5)
	end
	y += 116

	local function close()
		TweenService:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(scale, TweenInfo.new(0.2), { Scale = 0.6 }):Play()
		task.delay(0.2, function()
			dim:Destroy()
		end)
	end

	if info.DailyReady then
		local claim: TextButton
		claim = Ui.chunky(
			{
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, y),
				Size = UDim2.fromOffset(300, 60),
				BackgroundColor3 = Color3.fromRGB(80, 200, 90),
				Text = `Claim Day {today}!`,
				ZIndex = 53,
			},
			card,
			"🎁",
			function()
				claim.Active = false
				local ok, result = Remotes:WaitForChild("ClaimDaily"):InvokeServer()
				if ok then
					Effects.Sound(Sounds.Cash, nil, 0.7)
				end
				local _ = result
				close()
			end
		)
	else
		Ui.chunky({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, y),
			Size = UDim2.fromOffset(300, 60),
			BackgroundColor3 = Color3.fromRGB(90, 140, 230),
			Text = "Let's go!",
			ZIndex = 53,
		}, card, "🔪", close)
	end
	card.Size = UDim2.fromOffset(620, y + 76)
	if info.Offline > 0 then
		Effects.Sound(Sounds.Cash, nil, 0.6)
	end
end

function Welcome.Init()
	Remotes:WaitForChild("Welcome").OnClientEvent:Connect(show)
end

return Welcome
