--!strict
-- The welcome-back card, shown once when you join (the server sends Remotes.Welcome):
--   * what your vault earned while you were away (already paid)
--   * the 7-day login streak, with today's reward to claim (Remotes.ClaimDaily)
--   * the new-player shield, for people who just started

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local Effects = require(script.Parent.Effects)
local TopLine = require(script.Parent.TopLine)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local Sounds = require(ReplicatedStorage.Shared.Config:WaitForChild("Sounds"))
local Knives = require(ReplicatedStorage.Shared.Config:WaitForChild("Knives"))
local VoxelUi = require(ReplicatedStorage.Shared.Config.VoxelUi)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local new = Ui.new

local Welcome = {}

type Info = {
	Offline: number,
	Away: number,
	Streak: number,
	DailyReady: boolean,
	Shielded: boolean?,
	LostStreak: number?,
}

local GOLD = Color3.fromRGB(255, 205, 60)
local RARITY_COLORS: { [string]: Color3 } = Knives.RarityColors

-- Real Codex art where there is any (Cash, every case rarity); Tickets has none yet, so it keeps
-- its emoji until Codex makes one.
local function rewardArt(reward: GameConfig.DailyReward): (string?, string, string, Color3)
	if reward.Kind == "Case" then
		local rarity = reward.Rarity or "Common"
		return VoxelUi.Cases[rarity], "", `{rarity} Case`, RARITY_COLORS[rarity] or GOLD
	elseif reward.Kind == "Tickets" then
		return nil, "🎟️", `{reward.Amount or 1} Tickets`, Color3.fromRGB(230, 70, 90)
	end
	return VoxelUi.Hud.Cash, "", "Cash", Color3.fromRGB(90, 210, 110)
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
	local nothingNew = info.Offline <= 0 and not info.DailyReady and not info.Shielded and info.Away > 0
	if nothingNew then
		return
	end
	-- The very first join: no card at all - straight into the arrows to Frank (9 of 26 early quitters
	-- left within 12 s having seen nothing but this card). Day 1 of the streak is claimed for them
	-- and said on the top line; the card shows from the second visit.
	if info.Away <= 0 then
		task.spawn(function()
			if info.DailyReady then
				local ok = Remotes:WaitForChild("ClaimDaily"):InvokeServer()
				if ok then
					Effects.Sound(Sounds.Cash, nil, 0.6)
					TopLine.Show("🎁 Come back tomorrow for your Day 2 reward!", 4, "Daily")
				end
			end
		end)
		return
	end

	local dim = new("Frame", {
		Name = "Welcome",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(30, 26, 23),
		BackgroundTransparency = 1,
		ZIndex = 50,
	}, Ui.gui)
	-- Same philosophy as every other window: a solid-colour header with a real icon and a red X,
	-- a see-through dark body - not an opaque gradient card.
	local card = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 430),
		BackgroundColor3 = Color3.fromRGB(14, 16, 26),
		BackgroundTransparency = 0.25,
		ZIndex = 51,
	}, dim)
	Ui.corner(card, 18)
	Theme.outline(card, Theme.Black, 4)
	local scale = new("UIScale", { Scale = 0.6 }, card)

	local close: () -> () = function() end
	local header = Theme.surface(card, { Name = "Header", Size = UDim2.new(1, 0, 0, 64), ZIndex = 52 }, GOLD)
	local headerCorner = header:FindFirstChildOfClass("UICorner") :: UICorner
	headerCorner.CornerRadius = UDim.new(0, 18)
	Theme.image(header, "Gift", { Position = UDim2.fromOffset(8, 2), Size = UDim2.fromOffset(60, 60) })
	Theme.text(header, if info.Away > 0 then "WELCOME BACK!" else "WELCOME TO BLACKWOOD!", {
		Name = "Title",
		Position = UDim2.fromOffset(76, 2),
		Size = UDim2.new(1, -180, 1, -4),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaximumTextSize = 36,
	})
	Theme.button(header, "X", Theme.Red, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(50, 50),
		MaximumTextSize = 40,
	}, function()
		close()
	end)

	local y = 78
	-- First visit: the game in one glance, the same promise as the thumbnail
	if info.Away <= 0 then
		-- One line of big coloured words, not two raised pills: those looked like buttons to tap
		local loop = Ui.label({
			Size = UDim2.new(1, -40, 0, 56),
			Position = UDim2.fromOffset(20, y + 4),
			RichText = true,
			Text = `<font color="#FFD24A">🔪 STEAL KNIVES</font>  ➜  <font color="#FF5A5A">😈 BECOME THE MURDERER</font>`,
			ZIndex = 53,
		}, card)
		Ui.textStroke(loop, 3)
		y += 72
		local how = Ui.label({
			Size = UDim2.new(1, -40, 0, 46),
			Position = UDim2.fromOffset(20, y),
			-- (two lines at most: on a phone the third was cut off)
			Text = "Every few minutes the WHOLE SERVER plays Murder Mystery. "
				.. "The knives you steal give you Murderer powers!",
			TextColor3 = Color3.fromRGB(255, 225, 225),
			TextWrapped = true,
			ZIndex = 52,
		}, card)
		Ui.textStroke(how, 2)
		y += 54
	end
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
		-- Double it (Robux): the moment the number is biggest on screen
		local double = Monetization.ProductByKey.OfflineDouble
		if double and Ui.Buy then
			local holder = new("Frame", {
				Size = UDim2.new(1, -40, 0, 48),
				Position = UDim2.fromOffset(20, y),
				BackgroundTransparency = 1,
				ZIndex = 52,
			}, card)
			Theme.button(
				holder,
				`Double it! +${Ui.abbreviate(info.Offline)}  R$ {double.Price}`,
				Color3.fromRGB(0, 176, 111),
				{
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromScale(0.5, 0),
					Size = UDim2.fromOffset(340, 44),
					ZIndex = 53,
					MaximumTextSize = 24,
				},
				function()
					(Ui.Buy :: any)("Product", "OfflineDouble")
				end
			)
			y += 54
		end
	end
	if info.LostStreak and info.LostStreak > 0 then
		local save = Monetization.ProductByKey.StreakSave
		local lost = Ui.label({
			Size = UDim2.new(1, -40, 0, 30),
			Position = UDim2.fromOffset(20, y),
			Text = `📅 You missed a day and lost your Day {info.LostStreak} streak!`,
			TextColor3 = Color3.fromRGB(255, 200, 90),
			ZIndex = 52,
		}, card)
		Ui.textStroke(lost, 2)
		y += 36
		if save and Ui.Buy then
			local holder = new("Frame", {
				Size = UDim2.new(1, -40, 0, 48),
				Position = UDim2.fromOffset(20, y),
				BackgroundTransparency = 1,
				ZIndex = 52,
			}, card)
			Theme.button(holder, `Save my streak  R$ {save.Price}`, Color3.fromRGB(255, 170, 40), {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromOffset(300, 44),
				ZIndex = 53,
				MaximumTextSize = 24,
			}, function()
				(Ui.Buy :: any)("Product", "StreakSave")
			end)
			y += 54
		end
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
		local image, emoji, text, color = rewardArt(reward)
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
		if image then
			new("ImageLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(36, 36),
				Position = UDim2.fromOffset(20, 26),
				Image = image,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 54,
			}, tile)
		else
			Ui.label({
				Size = UDim2.new(1, 0, 0, 36),
				Position = UDim2.fromOffset(0, 26),
				Text = emoji,
				ZIndex = 54,
			}, tile)
		end
		local what = Ui.label({
			Size = UDim2.new(1, -6, 0, 22),
			Position = UDim2.new(0, 3, 1, -28),
			Text = text,
			ZIndex = 54,
		}, tile)
		Ui.textStroke(what, 1.5)
	end
	y += 116

	close = function()
		TweenService:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(scale, TweenInfo.new(0.2), { Scale = 0.6 }):Play()
		task.delay(0.2, function()
			dim:Destroy()
		end)
	end

	if info.DailyReady then
		local claim: TextButton
		claim = Theme.button(card, `Claim Day {today}!`, Color3.fromRGB(80, 200, 90), {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, y),
			Size = UDim2.fromOffset(300, 60),
			ZIndex = 53,
			MaximumTextSize = 32,
		}, function()
			claim.Active = false
			local ok, result = Remotes:WaitForChild("ClaimDaily"):InvokeServer()
			if ok then
				Effects.Sound(Sounds.Cash, nil, 0.7)
			end
			local _ = result
			close()
		end, "Gift")
	else
		Theme.button(card, "Let's go!", Color3.fromRGB(90, 140, 230), {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, y),
			Size = UDim2.fromOffset(220, 54),
			ZIndex = 53,
			MaximumTextSize = 32,
		}, close)
	end
	local content = new("ScrollingFrame", {
		Name = "Content",
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 1, -132),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.fromOffset(0, y - 72),
		ScrollBarThickness = 4,
		ZIndex = 52,
	}, card)
	local children = card:GetChildren()
	for _, child in children do
		if child:IsA("GuiObject") and child ~= header and child ~= content then
			if child:IsA("TextButton") then
				child.AnchorPoint = Vector2.new(0.5, 1)
				child.Position = UDim2.new(0.5, 0, 1, -8)
			else
				child.Position -= UDim2.fromOffset(0, 72)
				child.Parent = content
			end
		end
	end
	for _, tile in row:GetChildren() do
		if tile:IsA("Frame") then
			tile.Size = UDim2.new(1 / 7, -8, 0, tile.Size.Y.Offset)
		end
	end
	-- Always tall enough for everything, then the whole card scales to fit the screen (fitMenu
	-- clamped its height instead: on a phone the day tiles ended up in a scroll area behind the
	-- Claim button)
	card.Size = UDim2.fromOffset(620, y + 76)
	local function fit(): number
		local _, bounds = Ui.bounds()
		return math.min(1, (bounds.Y - 16) / (y + 76), (bounds.X - 16) / 620)
	end
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = fit() }):Play()
	local relayout = Ui.Layout.Changed:Connect(function()
		scale.Scale = fit()
	end)
	dim.Destroying:Connect(function()
		relayout:Disconnect()
	end)
	Ui.registerMenu(dim)
	if info.Offline > 0 then
		Effects.Sound(Sounds.Cash, nil, 0.6)
	end
end

function Welcome.Init()
	Remotes:WaitForChild("Welcome").OnClientEvent:Connect(show)
end

return Welcome
