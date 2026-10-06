--!strict
-- Always-on HUD, Steal An Egg style:
--   * bottom left: your Speed and Cash in big chunky numbers (with income, training, boost)
--   * right: upgrade buttons (Haunted Wheel, vault walls, mounts, Murderer tickets)
--   * bottom right: event timers (next raid, next murder round, the plaza's free chest)
--   * top: the phase / round timer, raid banner, and big server-wide announcements
--   * rounds: the Energy meter that powers your Innocent Powers, the role reveal, results
--   * toasts, the zone title when you cross into a new part of the runway
-- Pure display; every number comes from attributes the server sets.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local CartoonArt = require(ReplicatedStorage.Shared.Config.CartoonArt)
local VoxelUi = require(ReplicatedStorage.Shared.Config.VoxelUi)
local CoinIcon = require(ReplicatedStorage.Shared.Config.CoinIcon)
local RoundPrize = require(ReplicatedStorage.Shared.RoundPrize)
local KnifeIcons = require(ReplicatedStorage.Shared.Config.KnifeIcons)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Items = require(ReplicatedStorage.Shared.Items)
local Effects = require(script.Parent.Effects)
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local Sounds = require(ReplicatedStorage.Shared.Config:WaitForChild("Sounds"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local new = Ui.new

local Hud = {}

local KIND_COLORS = {
	good = Color3.fromRGB(70, 200, 100),
	bad = Color3.fromRGB(230, 70, 70),
	info = Color3.fromRGB(70, 150, 240),
}
local SPEED_COLOR = Color3.fromRGB(255, 160, 40)
local CASH_COLOR = Color3.fromRGB(110, 255, 110)

-- Big number with a thick outline (the Speed and Cash readouts)
local function bigNumber(parent: Instance, color: Color3, position: UDim2, size: UDim2): TextLabel
	local label = Ui.label({
		Position = position,
		Size = size,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		Text = "",
	}, parent)
	Ui.textStroke(label, 3.5)
	Ui.gradient(label, Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	return label
end

local function pill(parent: Instance, order: number): (Frame, TextLabel, TextLabel)
	local frame = new("Frame", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(250, 46),
		BackgroundColor3 = Color3.fromRGB(20, 16, 28),
		BackgroundTransparency = 0.35,
	}, parent)
	Ui.corner(frame, 14)
	local icon = Ui.label({ Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(4, 3), Text = "" }, frame)
	local text = Ui.label({
		Size = UDim2.new(1, -54, 1, -8),
		Position = UDim2.fromOffset(48, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, frame)
	Ui.textStroke(text, 2.5)
	return frame, icon, text
end

-- Studio phone preview (DebugPhone): ghosts of Roblox's touch thumbstick and jump button, using
-- the same sizes and positions Roblox's TouchGui does, so the layout can be checked on desktop
local function touchGhosts()
	-- Studio-only guides share the real safe-area geometry used by the combat controls.
	local function ghost(name: string, text: string): Frame
		local frame = new(
			"Frame",
			{ Name = name, BackgroundColor3 = Color3.fromRGB(255, 60, 60), BackgroundTransparency = 0.75 },
			Ui.gui
		)
		Ui.corner(frame, 100)
		Ui.label({ Size = UDim2.fromScale(1, 1), Text = text, TextSize = 14, TextScaled = false }, frame)
		return frame
	end
	local jump, stick = ghost("DebugJump", "JUMP"), ghost("DebugStick", "MOVE")
	local function resize()
		local at, size = Ui.Layout.touchBounds()
		jump.Position, jump.Size = UDim2.fromOffset(at.X, at.Y), UDim2.fromOffset(size.X, size.Y)
		local _, bounds = Ui.bounds()
		local diameter = if bounds.Y < 500 then 70 else 120
		stick.Position, stick.Size = UDim2.new(0, 25, 1, -diameter - 20), UDim2.fromOffset(diameter, diameter)
	end
	Ui.Layout.Changed:Connect(resize)
	resize()
end

-- Puts an art-pack picture where an emoji icon label was (the label keeps its size and place)
local function pictureIcon(label: TextLabel, image: string)
	label.Text = ""
	local picture = label:FindFirstChild("Picture") :: ImageLabel?
	if not picture then
		picture = new("ImageLabel", {
			Name = "Picture",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = label.ZIndex + 1,
		}, label)
	end
	(picture :: ImageLabel).Image = image
end

function Hud.Init()
	local gui = Ui.gui
	if Ui.Phone and RunService:IsStudio() and ReplicatedStorage:GetAttribute("DebugPhone") then
		touchGhosts()
	end

	-- Top centre: phase + timer, with a smaller line under it for round info -------------------
	local timerFrame = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(380, 58),
		BackgroundColor3 = Ui.PANEL,
		BackgroundTransparency = 0.15,
	}, gui)
	-- No box: big outlined text straight on the world, like Steal An Egg's event timers
	timerFrame.BackgroundTransparency = 1
	local timerLabel = Ui.label({ Size = UDim2.fromScale(1, 1), Text = "Loading..." }, timerFrame)
	new("UIStroke", {
		Thickness = 3,
		Color = Color3.fromRGB(20, 16, 28),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, timerLabel)
	-- During the Blood Moon its name takes the left of the timer: big plain text in the game's font
	-- (like the floating shop titles), the countdown stays live beside it
	local moonTitle = new("TextLabel", {
		Name = "BloodMoonTitle",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.5, 1.3),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Font = Enum.Font.FredokaOne,
		Text = "BLOOD MOON",
		TextColor3 = Color3.fromRGB(255, 60, 60),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
	}, timerFrame)
	new("UIStroke", {
		Thickness = 3,
		Color = Color3.fromRGB(20, 16, 28),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, moonTitle)
	local timerCap = timerLabel:FindFirstChildOfClass("UITextSizeConstraint")
	if timerCap then
		timerCap.MaxTextSize = if Ui.Phone then 24 else 36
	end
	local subLabel = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(460, 26),
		Text = "",
	}, gui)

	-- The round prize (Shared/RoundPrize), from AnnounceAt seconds before the round: what each side
	-- wins in your own numbers, and "Double it!" (Robux). The big red countdown repeats it at 10 s.
	local prizeBox = new("Frame", {
		Name = "RoundPrize",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 98),
		Size = UDim2.fromOffset(560, 92),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	local function prizeLine(y: number, color: Color3): TextLabel
		local label = Ui.label({
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, 24),
			TextColor3 = color,
			RichText = true,
			Text = "",
		}, prizeBox)
		Ui.textStroke(label, 2.5)
		return label
	end
	local jackpotLine = prizeLine(0, Color3.fromRGB(255, 215, 70))
	local innocentLine = prizeLine(0, Color3.fromRGB(140, 255, 150))
	local murdererLine = prizeLine(26, Color3.fromRGB(255, 120, 120))
	local doubleButton = Ui.button(
		{
			Name = "DoublePrize",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 56),
			Size = UDim2.fromOffset(190, 32),
			BackgroundColor3 = Color3.fromRGB(0, 176, 111),
			Text = "🎁 Double it! R$25",
		},
		prizeBox,
		function()
			if Ui.Buy and ((player:GetAttribute("Charge_DoublePrize") or 0) :: number) == 0 then
				Ui.Buy("Product", "DoublePrize")
			end
		end
	)
	task.spawn(function()
		while true do
			task.wait(0.25)
			local kind = ReplicatedStorage:GetAttribute("PrizeKind")
			local endsAt = ReplicatedStorage:GetAttribute("PhaseEndsAt")
			local left = if type(endsAt) == "number" then endsAt - workspace:GetServerTimeNow() else math.huge
			local show = type(kind) == "string"
				and ReplicatedStorage:GetAttribute("Phase") == "Intermission"
				and ReplicatedStorage:GetAttribute("Status") == "🔪 MURDER ROUND in"
				and left <= GameConfig.RoundPrize.AnnounceAt
				and left > 0
				and not player:GetAttribute("InRound")
				and not Ui.menuOpen()
			prizeBox.Visible = show
			if show then
				local jackpot = ReplicatedStorage:GetAttribute("PrizeJackpot") == true
				local seed = (ReplicatedStorage:GetAttribute("PrizeSeed") or 1) :: number
				local doubled = ((player:GetAttribute("Charge_DoublePrize") or 0) :: number) > 0
				local stats = RoundPrize.Stats(player)
				local innocent = RoundPrize.For(kind :: string, "Innocent", jackpot, seed, stats, doubled)
				local murderer = RoundPrize.For(kind :: string, "Murderer", jackpot, seed, stats, doubled)
				jackpotLine.Visible = jackpot
				jackpotLine.Text = "⭐ JACKPOT ROUND! ⭐"
				local y = if jackpot then 26 else 0
				innocentLine.Position = UDim2.fromOffset(0, y)
				murdererLine.Position = UDim2.fromOffset(0, y + 26)
				doubleButton.Position = UDim2.new(0.5, 0, 0, y + 56)
				innocentLine.Text = `😇 If Innocents win: <b>{innocent.Text}</b>`
				murdererLine.Text = `🔪 If the Murderer wins: <b>{murderer.Text}</b>`
				local label = doubleButton:FindFirstChild("Label") :: TextLabel?
				local text = if doubled then "✓ Prize doubled!" else "🎁 Double it! R$25"
				if label then
					label.Text = text
				else
					doubleButton.Text = text
				end
			end
		end
	end)
	-- The signs at your own vault (other vaults' signs stay blank): Upgrade Base by the gate (next
	-- floor's price, how full you are) and Upgrade Wheel in front of the Haunted Wheel (Steal An Egg's
	-- treadmill sign: "Lv 6 ➜ 7", the cash price, and R$ on the small board under it). A "!" when you
	-- can afford it; clicking the sign buys it.
	type SignLabels = { Title: TextLabel, Price: TextLabel, Count: TextLabel, Alert: TextLabel }
	local function signLabels(surface: SurfaceGui): SignLabels?
		-- The sign's labels are built in the world (MapService); this only fills them in
		local signPill = surface:FindFirstChild("Pill", true)
		local labels = {
			Title = surface:FindFirstChild("Title"),
			Price = signPill and signPill:FindFirstChild("Price"),
			Count = signPill and signPill:FindFirstChild("Count"),
			Alert = surface:FindFirstChild("Alert"),
		}
		return if labels.Price and labels.Count and labels.Title and labels.Alert then labels :: any else nil
	end
	local robuxClick: ClickDetector? = nil
	task.spawn(function()
		while true do
			task.wait(0.5)
			local index = player:GetAttribute("VaultIndex")
			local map = workspace:FindFirstChild("Map")
			local bases = map and map:FindFirstChild("Bases")
			local base = bases and type(index) == "number" and bases:FindFirstChild(`Base{index}`)
			if not base then
				continue
			end
			local cash = (player:GetAttribute("Cash") or 0) :: number
			local function surfaceOf(signName: string): SurfaceGui?
				local sign = base:FindFirstChild(signName)
				local board = sign and sign:FindFirstChild("Board")
				return board and board:FindFirstChild("Gui") :: SurfaceGui?
			end
			local floorSurface = surfaceOf("UpgradeSign")
			local labels = floorSurface and signLabels(floorSurface)
			if labels then
				local slots = (player:GetAttribute("Slots") or GameConfig.StartingSlots) :: number
				local knives = (player:GetAttribute("KnifeCount") or 0) :: number
				labels.Title.Text = "Upgrade Base"
				labels.Count.Text = `{knives}/{slots}`
				if slots >= GameConfig.MaxSlots then
					labels.Price.Text = "MAX"
					labels.Alert.Visible = false
				else
					local cost = GameConfig.SlotCost(slots)
					labels.Price.Text = `${Ui.abbreviate(cost)}`
					labels.Alert.Visible = cash >= cost
				end
			end
			local wheelSurface = surfaceOf("WheelUpgradeSign")
			local wheelLabels = wheelSurface and signLabels(wheelSurface)
			if wheelLabels then
				local nextUpgrade = GameConfig.NextSpeedUpgrade(
					(player:GetAttribute("TreadmillLevel") or 1) :: number,
					(player:GetAttribute("TrailLevel") or 0) :: number
				)
				wheelLabels.Title.Text = "Upgrade Wheel"
				if nextUpgrade then
					wheelLabels.Count.Text = `Level {nextUpgrade.Level} > {nextUpgrade.Level + 1}`
					wheelLabels.Price.Text = `${Ui.abbreviate(nextUpgrade.Cost)}`
					wheelLabels.Alert.Visible = cash >= nextUpgrade.Cost
				else
					wheelLabels.Count.Text = "Max level"
					wheelLabels.Price.Text = "MAX"
					wheelLabels.Alert.Visible = false
				end
			end
			local wheelSign = base:FindFirstChild("WheelUpgradeSign")
			local robuxBoard = wheelSign and wheelSign:FindFirstChild("RobuxBoard")
			local robuxPrice = robuxBoard and robuxBoard:FindFirstChild("Price", true) :: TextLabel?
			if robuxPrice then
				local product = Monetization.ProductByKey.SpeedUpgrade
				robuxPrice.Text = if product then `R${product.Price}` else ""
			end
			-- The Robux board's click (the server only adds the detector for the owner)
			local click = robuxBoard and robuxBoard:FindFirstChild("BuyWheel") :: ClickDetector?
			if click and click ~= robuxClick then
				robuxClick = click
				click.MouseClick:Connect(function()
					if Ui.Buy then
						Ui.Buy("Product", "SpeedUpgrade")
					end
				end)
			end
		end
	end)

	-- 🤝 The server goal and any live events (ServerEvents), under the timer
	local goalLabel = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 122),
		Size = UDim2.fromOffset(460, 22),
		Text = "",
		TextColor3 = Color3.fromRGB(150, 230, 255),
	}, gui)
	Ui.textStroke(goalLabel, 1.5)
	local eventLabel = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 146),
		Size = UDim2.fromOffset(520, 26),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 230, 120),
	}, gui)
	Ui.textStroke(eventLabel, 2)
	local EVENT_TEXT: { { Name: string, Text: string } } = {
		{ Name = "LuckyRush", Text = "🍀 LUCKY RUSH · 2x power luck" },
		{ Name = "CashRush", Text = "💸 CASH RUSH · 2x cash" },
		{ Name = "HeatWave", Text = "🔥 HEAT WAVE · 2x Heat" },
		{ Name = "CosmicRush", Text = "🪐 COSMIC RUSH · deep bosses restock fast" },
	}
	task.spawn(function()
		while true do
			task.wait(0.5)
			local inRound = player:GetAttribute("InRound") == true
			local text = ReplicatedStorage:GetAttribute("GoalText")
			local progress = ReplicatedStorage:GetAttribute("GoalProgress") or 0
			local need = ReplicatedStorage:GetAttribute("GoalNeed") or 1
			goalLabel.Visible = not inRound and type(text) == "string"
			goalLabel.Text = `🤝 Server goal: {text} ({progress}/{need})`
			local now = workspace:GetServerTimeNow()
			local live = {}
			for _, event in EVENT_TEXT do
				local ends = ReplicatedStorage:GetAttribute(`Event_{event.Name}`)
				if type(ends) == "number" and ends > now then
					table.insert(live, `{event.Text} {Ui.clock(ends - now)}`)
				end
			end
			eventLabel.Visible = #live > 0 and not player:GetAttribute("InRound") and not Ui.menuOpen()
			eventLabel.Text = table.concat(live, "   ")
		end
	end)

	-- "Your chance to be the Murderer: 6%" (MM2 style), between rounds
	local chanceLabel = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 98),
		Size = UDim2.fromOffset(420, 22),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 110, 120),
	}, gui)
	Ui.textStroke(chanceLabel, 1.5)
	-- (plain text, centred: no icon beside it)
	local function refreshChance()
		local chance = player:GetAttribute("MurdererChance")
		chanceLabel.Visible = type(chance) == "number" and Ui.inHub()
		chanceLabel.Text = `Murderer chance: {chance or 0}%`
	end
	player:GetAttributeChangedSignal("MurdererChance"):Connect(refreshChance)
	player:GetAttributeChangedSignal("InRound"):Connect(refreshChance)
	refreshChance()
	Ui.textStroke(subLabel, 2)

	-- Bottom centre: health, big and easy to see (Roblox's own bar sits top right where nobody looks)
	pcall(function()
		game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
	local healthFrame = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if Ui.Phone then -8 else -74),
		Size = UDim2.fromOffset(if Ui.Phone then 240 else 360, if Ui.Phone then 24 else 30),
		BackgroundColor3 = Color3.fromRGB(40, 14, 18),
		BackgroundTransparency = 0.1,
	}, gui)
	Ui.corner(healthFrame, 12)
	Ui.stroke(healthFrame)
	local healthFill = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(80, 220, 100),
	}, healthFrame)
	Ui.corner(healthFill, 12)
	local healthText = Ui.label({
		Size = UDim2.fromScale(1, 1),
		Text = "❤️ 100 / 100",
		ZIndex = 3,
	}, healthFrame)
	Ui.textStroke(healthText, 2)
	local healthConnections: { RBXScriptConnection } = {}
	local hideToken = 0
	local function watchHealth(character: Model)
		for _, c in healthConnections do
			c:Disconnect()
		end
		table.clear(healthConnections)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then
			return
		end
		local function refresh()
			local fraction = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
			healthFill.Size = UDim2.fromScale(fraction, 1)
			healthFill.Visible = fraction > 0.01
			-- Green -> yellow -> red as it drops
			healthFill.BackgroundColor3 = if fraction > 0.5
				then Color3.fromRGB(255, 220, 60):Lerp(Color3.fromRGB(80, 220, 100), (fraction - 0.5) * 2)
				else Color3.fromRGB(230, 50, 50):Lerp(Color3.fromRGB(255, 220, 60), fraction * 2)
			healthText.Text = `❤️ {math.ceil(humanoid.Health)} / {math.floor(humanoid.MaxHealth)}`
			-- Only on screen while it means something: hurt, or in a round. Full health in the hub
			-- hides it a moment later.
			-- (never in a round: one stab and you're out, a bar says nothing)
			if fraction < 0.999 and not player:GetAttribute("InRound") and not Ui.menuOpen() then
				healthFrame.Visible = true
				hideToken += 1
			else
				hideToken += 1
				local token = hideToken
				task.delay(2.5, function()
					if token == hideToken and not player:GetAttribute("InRound") then
						healthFrame.Visible = false
					end
				end)
			end
		end
		table.insert(healthConnections, player:GetAttributeChangedSignal("InRound"):Connect(refresh))
		table.insert(healthConnections, humanoid.HealthChanged:Connect(refresh))
		table.insert(healthConnections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh))
		refresh()
	end
	player.CharacterAdded:Connect(watchHealth)
	if player.Character then
		task.spawn(watchHealth, player.Character)
	end

	-- Bottom left: Speed and Cash -----------------------------------------------------------------
	-- (phones: top left beside the icon strip, away from the thumbstick)
	local stats = new("Frame", {
		Name = "Stats",
		AnchorPoint = if Ui.Phone then Vector2.zero else Vector2.new(0, 1),
		Position = if Ui.Phone then UDim2.fromOffset(80, 58) else UDim2.new(0, 14, 1, -14),
		Size = UDim2.fromOffset(330, 176),
		BackgroundTransparency = 1,
	}, gui)
	if Ui.Phone then
		new("UIScale", { Scale = 0.72 }, stats)
	end
	Ui.label({ Size = UDim2.fromOffset(50, 50), Position = UDim2.fromOffset(0, 4), Text = "👟" }, stats)
	local speedLabel = bigNumber(stats, SPEED_COLOR, UDim2.fromOffset(56, 0), UDim2.fromOffset(270, 58))
	local trainLabel = Ui.label({
		Position = UDim2.fromOffset(58, 54),
		Size = UDim2.fromOffset(260, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(150, 210, 255),
		Text = "",
	}, stats)
	Ui.textStroke(trainLabel, 2)
	Ui.label({ Size = UDim2.fromOffset(50, 50), Position = UDim2.fromOffset(0, 84), Text = "💵" }, stats)
	local cashLabel = bigNumber(stats, CASH_COLOR, UDim2.fromOffset(56, 78), UDim2.fromOffset(270, 62))
	local incomeLabel = Ui.label({
		Position = UDim2.fromOffset(58, 138),
		Size = UDim2.fromOffset(270, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, stats)
	Ui.textStroke(incomeLabel, 2)
	local rackLabel = Ui.label({
		Position = UDim2.fromOffset(58, 158),
		Size = UDim2.fromOffset(270, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(200, 200, 220),
		Text = "",
	}, stats)
	Ui.textStroke(rackLabel, 1.5)
	Hud.CashLabel = cashLabel

	-- 🔥 Heat, right above Speed: one number that both games fill, boosting cash and power luck
	local heatLabel = Ui.label({
		Position = UDim2.fromOffset(0, -44),
		Size = UDim2.fromOffset(320, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 150, 60),
		Text = "",
	}, stats)
	Ui.textStroke(heatLabel, 2.5)
	local heatHint = Ui.label({
		Position = UDim2.fromOffset(4, -14),
		Size = UDim2.fromOffset(320, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 220, 170),
		Text = "",
	}, stats)
	Ui.textStroke(heatHint, 1.5)
	local function refreshHeat()
		local heat = (player:GetAttribute("Heat") or 0) :: number
		local fuel = GameConfig.Fuel
		heatLabel.Text = `HEAT {heat}/{fuel.MaxHeat}` -- (the flame is the art-pack icon beside it)
		heatLabel.TextColor3 = Color3.fromRGB(255, 200, 90):Lerp(Color3.fromRGB(255, 60, 40), heat / fuel.MaxHeat)
		local friends = (player:GetAttribute("FriendsHere") or 0) :: number
		heatHint.Text = (
			if heat > 0
				then `x{math.floor((1 + heat * fuel.HeatIncome) * 10) / 10} cash · x{math.floor(
					(1 + heat * fuel.HeatLuck) * 10
				) / 10} power luck`
				else "Steal & survive rounds to heat up!"
		) .. (if friends > 0 then `  · 👥 +{friends * 10}%` else "")
	end
	player:GetAttributeChangedSignal("Heat"):Connect(refreshHeat)
	player:GetAttributeChangedSignal("FriendsHere"):Connect(refreshHeat)
	refreshHeat()
	Remotes.Effect.OnClientEvent:Connect(function(kind: string, _heat: any, delta: any, reason: any)
		if kind ~= "Heat" or type(delta) ~= "number" then
			return
		end
		local scale = heatLabel:FindFirstChildOfClass("UIScale") or new("UIScale", {}, heatLabel)
		scale.Scale = 1.35
		TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			Effects.FloatText(
				root.Position + Vector3.new(0, 4, 0),
				`{if delta > 0 then "+" else ""}{delta} 🔥 {reason or ""}`,
				if delta > 0 then Color3.fromRGB(255, 160, 60) else Color3.fromRGB(150, 160, 190)
			)
		end
	end)

	-- (No Upgrades button any more: the wheel + trail are one "Upgrade Wheel" sign by your Haunted
	-- Wheel, the vault floor is the Upgrade Base sign / the Knives panel, and Health is gone.)

	-- Bottom right: event timers ----------------------------------------------------------------
	-- (phones: top right, out from under the jump button)
	local timers = new("Frame", {
		Name = "Timers",
		AnchorPoint = if Ui.Phone then Vector2.new(1, 0) else Vector2.new(1, 1),
		Position = if Ui.Phone then UDim2.new(1, -10, 0, 6) else UDim2.new(1, -14, 1, -14),
		Size = UDim2.fromOffset(250, 160),
		BackgroundTransparency = 1,
	}, gui)
	if Ui.Phone then
		new("UIScale", { Scale = 0.72 }, timers)
	end
	new("UIListLayout", {
		Padding = UDim.new(0, if Ui.Phone then 4 else 8),
		VerticalAlignment = if Ui.Phone then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, timers)
	-- New-player shield: how long nobody can rob you
	local shieldPill, shieldIcon, shieldText = pill(timers, 0)
	shieldIcon.Text = "🛡️"
	local function refreshShield()
		local left = player:GetAttribute("ShieldLeft")
		local on = player:GetAttribute("Shielded") == true and type(left) == "number" and left > 0
		shieldPill.Visible = on
		if on then
			shieldText.Text = `Protected {math.ceil((left :: number) / 60)}m`
			shieldText.TextColor3 = Color3.fromRGB(150, 210, 255)
		end
	end
	player:GetAttributeChangedSignal("ShieldLeft"):Connect(refreshShield)
	player:GetAttributeChangedSignal("Shielded"):Connect(refreshShield)
	refreshShield()
	local raidPill, raidIcon, raidText = pill(timers, 1)
	pictureIcon(raidIcon, CartoonArt.LootBag)
	local roundPill, roundIcon, roundText = pill(timers, 2)
	roundPill.Visible = false -- the top timer says the same thing
	roundIcon.Text = "🔪"
	local chestPill, chestIcon, chestText = pill(timers, 3)
	chestPill.Name = "ChestPill"
	chestIcon.Visible = false
	chestPill.BackgroundColor3 = Theme.Navy
	chestPill.BackgroundTransparency = 0
	Theme.outline(chestPill)
	Theme.studs(chestPill)
	Theme.image(
		chestPill,
		"FreeChest",
		{ Position = UDim2.fromOffset(2, 4), Size = UDim2.fromOffset(32, 36), ZIndex = 2 }
	)
	chestText.ZIndex = 2
	-- Named "Label" so HudSkin keeps and styles it like Upgrades/Spin/Merchant's words (it hid it
	-- before: the click-catcher below had that name, so the chest showed no text at all)
	chestText.Name = "Label"
	-- It looked like a button (same skin as Upgrades/Spin/Merchant) but did nothing when tapped;
	-- tapping it now claims the chest directly, same as walking up and holding E.
	-- Named "Tap": HudSkin's restyle skips it too, so this click-catcher survives the restyle.
	local chestButton = new("TextButton", {
		Name = "Tap",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
	}, chestPill)
	chestButton.Activated:Connect(function()
		if chestButton:GetAttribute("Busy") then
			return
		end
		chestButton:SetAttribute("Busy", true)
		Remotes.ClaimFreeChest:InvokeServer()
		chestButton:SetAttribute("Busy", false)
	end)

	local function refreshStats()
		local cash = player:GetAttribute("Cash") or 0
		local slots = player:GetAttribute("Slots") or GameConfig.StartingSlots
		local speed = player:GetAttribute("Speed") or 0
		local treadmill = player:GetAttribute("TreadmillLevel") or 1
		local walls = player:GetAttribute("WallLevel") or 1
		local rebirths = player:GetAttribute("Rebirths") or 0
		cashLabel.Text = `${Ui.abbreviate(cash)}`
		speedLabel.Text = Ui.abbreviate(speed)
		local training = player:GetAttribute("Training")
		local rate = GameConfig.Treadmills[treadmill].Rate
			* (1 + rebirths * GameConfig.Rebirth.SpeedBonus)
			* GameConfig.TrailMultiplier(
				(player:GetAttribute("TrailLevel") or 0) :: number,
				player:GetAttribute("Pass_PhantomTrail") == true
			)
		trainLabel.Text = if training
			then `+{Ui.abbreviate(rate)}/s  running!`
			else `{math.floor(GameConfig.WalkSpeedFor(speed))} walk speed`
		incomeLabel.Text = `+${Ui.abbreviate(player:GetAttribute("Income") or 0)}/s`
		rackLabel.Text = `Wall {player:GetAttribute("KnifeCount") or 0}/{slots}  ·  Luck {player:GetAttribute("Luck") or 0}`
			.. (if rebirths > 0 then `  ·  Rebirth {rebirths}` else "")

		local _ = walls -- (vault walls are gone: open vaults, nothing to upgrade)
	end
	for _, attribute in
		{
			"Cash",
			"Slots",
			"Speed",
			"TreadmillLevel",
			"TrailLevel",
			"WallLevel",
			"HealthLevel",
			"Pass_Titan",
			"Training",
			"Tickets",
			"Income",
			"KnifeCount",
			"Luck",
			"Rebirths",
		}
	do
		player:GetAttributeChangedSignal(attribute):Connect(refreshStats)
	end
	refreshStats()

	-- Cash pops: every gain floats up from the cash readout (Steal An Egg's "+$372K")
	local lastCash = player:GetAttribute("Cash") or 0
	player:GetAttributeChangedSignal("Cash"):Connect(function()
		local cash = (player:GetAttribute("Cash") or 0) :: number
		local gained = cash - lastCash
		lastCash = cash
		if gained <= 0 or Ui.Phone or Ui.menuOpen() then
			return
		end
		local pop = Ui.label({
			Position = UDim2.fromOffset(60 + math.random(0, 120), 70),
			Size = UDim2.fromOffset(160, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = CASH_COLOR,
			Text = `+${Ui.abbreviate(gained)}`,
		}, stats)
		Ui.textStroke(pop, 2)
		local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(pop, info, { Position = pop.Position - UDim2.fromOffset(0, 50), TextTransparency = 1 })
			:Play()
		local stroke = pop:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		end
		game:GetService("Debris"):AddItem(pop, 1)
		-- Big gains make the number punch
		if gained >= math.max(100, ((player:GetAttribute("Income") or 0) :: number) * 5) then
			local scale = cashLabel:FindFirstChildOfClass("UIScale") or new("UIScale", {}, cashLabel)
			scale.Scale = 1.25
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end)

	-- Thief Moon rewards: the case badge pops in mid-screen for a moment
	Remotes.Effect.OnClientEvent:Connect(function(kind: string, rarity: any)
		if kind ~= "MoonReward" then
			return
		end
		local badge = new("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.fromOffset(150, 150),
			BackgroundTransparency = 1,
			Image = CartoonArt.CaseReward,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 20,
		}, gui)
		local caption = Ui.label({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromOffset(240, 34),
			Text = `{rarity} CASE!`,
			ZIndex = 21,
		}, badge)
		Ui.textStroke(caption, 2)
		local scale = new("UIScale", { Scale = 0.2 }, badge)
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = Ui.phoneScale() }):Play()
		task.delay(1.8, function()
			TweenService:Create(badge, TweenInfo.new(0.3), { ImageTransparency = 1 }):Play()
			task.wait(0.3)
			badge:Destroy()
		end)
	end)

	-- Results banner (big, centre) for the few seconds between a round and the next intermission
	local banner = Ui.label({
		Font = Ui.SPOOKY,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(760, 90),
		TextStrokeTransparency = 0,
		TextColor3 = Color3.fromRGB(255, 230, 120),
		Visible = false,
	}, gui)

	-- Announcements: big banners across the top for rare unboxes, raids, thefts, rebirths --------
	local announceHolder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 178),
		Size = UDim2.fromOffset(720, 70),
		BackgroundTransparency = 1,
	}, Ui.feedback) -- (above every menu: never hidden behind a window)
	local announceQueue: { { Text: string, Color: Color3, Hype: number } } = {}
	local announcing = false
	local function nextAnnouncement()
		local entry = table.remove(announceQueue, 1)
		if not entry then
			announcing = false
			return
		end
		announcing = true
		local frame = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, -90),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = entry.Color:Lerp(Color3.new(0, 0, 0), 0.55),
			BackgroundTransparency = 0.15,
		}, announceHolder)
		Ui.corner(frame, 16)
		new("UIStroke", { Thickness = 3, Color = entry.Color }, frame)
		local label = Ui.label({
			Size = UDim2.new(1, -24, 1, -12),
			Position = UDim2.fromOffset(12, 6),
			TextColor3 = Color3.new(1, 1, 1),
			Text = entry.Text,
		}, frame)
		Ui.textStroke(label, 2.5)
		if entry.Hype >= 3 then
			-- Rainbow sweep for the really big ones
			local gradient = new("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 120)),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 150)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 200, 255)),
				}),
			}, label)
			task.spawn(function()
				while gradient.Parent do
					gradient.Offset = Vector2.new(math.sin(os.clock() * 3) * 0.5, 0)
					task.wait()
				end
			end)
		end
		Effects.Sound(if entry.Hype >= 2 then Sounds.Announce else Sounds.Coin, nil, 0.4)
		TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0) })
			:Play()
		task.delay(if Ui.Phone then 2.2 else 2.6 + entry.Hype * 0.5, function()
			local out = TweenService:Create(
				frame,
				TweenInfo.new(0.3),
				{ Position = UDim2.new(0.5, 0, 0, -90), BackgroundTransparency = 1 }
			)
			out:Play()
			out.Completed:Wait()
			frame:Destroy()
			nextAnnouncement()
		end)
	end
	Remotes.Effect.OnClientEvent:Connect(function(kind: string, text: string, color: Color3, hype: number)
		if kind ~= "Announce" then
			return
		end
		table.insert(announceQueue, { Text = text, Color = color, Hype = hype or 1 })
		if #announceQueue > (if Ui.Phone then 2 else 4) then
			table.remove(announceQueue, 1)
		end
		if not announcing then
			nextAnnouncement()
		end
	end)

	-- Energy (rounds): the charge your Innocent Powers spend; coins fill it -----------------------
	-- A pill that sizes itself to its contents: "⚡ ENERGY", one cell per point, then "3/8"
	local ENERGY_ON = Color3.fromRGB(255, 214, 60)
	local ENERGY_OFF = Color3.fromRGB(58, 52, 70)
	local energyFrame = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Name = "EnergyBar",
		Position = UDim2.new(0.5, 0, 1, if Ui.Phone then -130 else -204), -- above the power buttons
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.fromRGB(24, 19, 34),
		BackgroundTransparency = 0.15,
		Visible = false,
	}, gui)
	Ui.corner(energyFrame, 18)
	new("UIStroke", { Thickness = 2.5, Color = Color3.fromRGB(14, 10, 20) }, energyFrame)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, energyFrame)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, energyFrame)
	local function energyText(text: string, layoutOrder: number, color: Color3): TextLabel
		local label = Ui.label({
			Size = UDim2.fromOffset(0, 26),
			AutomaticSize = Enum.AutomaticSize.X,
			TextScaled = false,
			TextSize = 20,
			LayoutOrder = layoutOrder,
			TextColor3 = color,
			Text = text,
		}, energyFrame)
		Ui.textStroke(label, 2)
		return label
	end
	-- Plain words instead of an abstract meter: [skull coin] 2/3 to use VANISH -> VANISH READY!
	-- (the coins on the floor are what fill it; the goal is the power you actually have)
	local coin = new("ImageLabel", {
		Size = UDim2.fromOffset(26, 26),
		BackgroundTransparency = 1,
		Image = CoinIcon.Image, -- the real round coin, rendered (Config/CoinIcon)
		ScaleType = Enum.ScaleType.Fit,
		LayoutOrder = 0,
	}, energyFrame)
	local countLabel = energyText("0/0", 1, ENERGY_ON)
	local powerGoal = energyText("", 2, Color3.fromRGB(235, 230, 245))
	local _ = ENERGY_OFF
	local lastEnergy = 0
	local function costOfRoundPower(): (number?, string?)
		local id = player:GetAttribute("RoundPower")
		for _, power in GameConfig.Powers do
			if power.Id == id then
				local energy = (power :: any).Energy :: { number }
				local name = player:GetAttribute("RoundPowerName")
				return energy[math.clamp(GameConfig.RoundPowerLevel, 1, #energy)],
					if type(name) == "string" then name else power.DisplayName
			end
		end
		return nil, nil
	end
	local function refreshEnergy()
		local energy = player:GetAttribute("Energy")
		local cost, name = costOfRoundPower()
		energyFrame.Visible = type(energy) == "number" and cost ~= nil and not Ui.menuOpen()
		if type(energy) ~= "number" or not cost or not name then
			return
		end
		local upper = string.upper(name :: string)
		if energy >= cost then
			coin.Visible = false
			countLabel.Text = ""
			powerGoal.Text = `{upper} READY!`
			powerGoal.TextColor3 = Color3.fromRGB(120, 255, 140)
		else
			coin.Visible = true
			countLabel.Text = `{math.floor(energy)}/{cost}`
			powerGoal.Text = `to use {upper}`
			powerGoal.TextColor3 = Color3.fromRGB(235, 230, 245)
		end
		if energy > lastEnergy then
			local scale = energyFrame:FindFirstChildOfClass("UIScale") or new("UIScale", {}, energyFrame)
			scale.Scale = 1.12
			TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		lastEnergy = energy
	end
	player:GetAttributeChangedSignal("RoundPower"):Connect(refreshEnergy)
	player:GetAttributeChangedSignal("Energy"):Connect(refreshEnergy)
	refreshEnergy()

	-- The events board over the runway entrance: live countdowns, filled in on this client ------
	task.spawn(function()
		local board: Instance? = nil
		while true do
			task.wait(0.5)
			if not board or not board.Parent then
				local map = workspace:FindFirstChild("Map")
				local decor = map and map:FindFirstChild("Decor")
				board = decor and decor:FindFirstChild("EventBoard")
				if not board then
					continue
				end
			end
			local phase = ReplicatedStorage:GetAttribute("Phase")
			local now = workspace:GetServerTimeNow()
			local left = (ReplicatedStorage:GetAttribute("PhaseEndsAt") or 0) - now
			local status = ReplicatedStorage:GetAttribute("Status") or ""
			local raidEnds = ReplicatedStorage:GetAttribute("RaidEndsAt")
			local nextRaid = ReplicatedStorage:GetAttribute("NextRaidAt")
			-- Tsunami style: each event's name in its own colour, then the time in white
			local function line(color: string, name: string, rest: string): string
				return `<font color="{color}">{name}</font> {rest}`
			end
			local line1 = if phase == "Round"
				then line("#FF5A5A", "MURDER ROUND", "NOW!")
				elseif phase == "Results" then line("#FF5A5A", "MURDER ROUND", "OVER")
				elseif status:find("Waiting") then line("#FF5A5A", string.upper(status), "")
				else line("#FF5A5A", "MURDER ROUND", `IN {Ui.clock(left)}`)
			local line2 = if type(raidEnds) == "number"
				then line("#FF4646", "BLOOD MOON", `ENDS IN {Ui.clock(raidEnds - now)}`)
				elseif type(nextRaid) == "number" then line(
					"#FF4646",
					"BLOOD MOON",
					`IN {Ui.clock(nextRaid - now)}`
				)
				else line("#FF4646", "BLOOD MOON", "SOON")
			local texts = {
				line1,
				line2,
				line("#FFE14B", "SURVIVORS", "EARN 2X CASH"),
				line(
					"#5AF08C",
					"SERVER GOAL",
					`{ReplicatedStorage:GetAttribute("GoalProgress") or 0}/{ReplicatedStorage:GetAttribute("GoalNeed") or "?"}`
				),
			}
			for _, face in (board :: Instance):GetChildren() do
				for i = 1, #texts do
					local label = face:FindFirstChild(`Line{i}`) :: TextLabel?
					if label then
						label.Text = texts[i]
					end
				end
			end
		end
	end)

	-- Timers, banners, every frame ------------------------------------------------------------
	local freeChestLabel: TextLabel? = nil
	RunService.RenderStepped:Connect(function()
		local phase = ReplicatedStorage:GetAttribute("Phase")
		local endsAt = ReplicatedStorage:GetAttribute("PhaseEndsAt") or 0
		local status = ReplicatedStorage:GetAttribute("Status") or ""
		local now = workspace:GetServerTimeNow()
		local clock = Ui.clock(endsAt - now)
		local inRound = player:GetAttribute("InRound")
		local raidEnds = ReplicatedStorage:GetAttribute("RaidEndsAt")
		timerFrame.Visible = not Ui.menuOpen() and Ui.gui:GetAttribute("ZoneNotice") ~= true
		if phase == "Round" then
			local map = ReplicatedStorage:GetAttribute("MapName") or ""
			-- In a round the screen is for the game: just the time and who's left (MM2 shows less)
			timerLabel.Text = if inRound
				then `{clock}  ·  {ReplicatedStorage:GetAttribute("Alive") or 0} alive`
				else `{map}  {clock}  ·  {ReplicatedStorage:GetAttribute("Alive") or 0} alive`
			timerFrame.BackgroundColor3 = Color3.fromRGB(150, 30, 50)
			subLabel.Text = if inRound then "" else "Round on - steal while they're busy!"
		elseif type(raidEnds) == "number" then
			-- The raid takes over the top of the screen, pulsing red
			local pulse = (math.sin(os.clock() * 6) + 1) / 2
			timerLabel.Text = `ENDS IN {Ui.clock(raidEnds - now)}`
			timerFrame.BackgroundColor3 = Color3.fromRGB(120, 20, 30):Lerp(Color3.fromRGB(200, 40, 50), pulse)
			subLabel.Text = if player:GetAttribute("Carrying")
				then "Get it home before someone knocks it loose!"
				else "Biomes closed - steal a knife from another vault!"
		elseif phase == "Results" or status:find("Waiting") then
			timerLabel.Text = if phase == "Results" then "Round over!" else status
			timerFrame.BackgroundColor3 = Ui.PANEL
			subLabel.Text = ""
		else
			timerLabel.Text = `MURDER ROUND in {clock}`
			timerFrame.BackgroundColor3 = Ui.PANEL
			local revengeUntil = player:GetAttribute("RevengeUntil")
			subLabel.Text = if type(revengeUntil) == "number" and revengeUntil > now
				then `REVENGE! Their vault is open to you: {Ui.clock(revengeUntil - now)}`
				elseif (endsAt - now) < 30 then "Get ready! Check your powers"
				else ""
		end
		local moon = phase ~= "Round" and type(raidEnds) == "number"
		moonTitle.Visible = moon
		timerLabel.Position = UDim2.fromScale(if moon then 0.5 else 0, 0)
		timerLabel.Size = UDim2.fromScale(if moon then 0.5 else 1, 1)
		banner.Visible = phase == "Results" and not Ui.menuOpen()
		if phase == "Results" then
			banner.Text = status
		end
		-- (not hidden while the knife is held: they never overlap, and taps made it flicker)
		stats.Visible = not Ui.menuOpen() and not player:GetAttribute("InRound") -- (speed / cash: hub things)
		timers.Visible = Ui.inHub()

		-- Event pills
		local nextRaid = ReplicatedStorage:GetAttribute("NextRaidAt")
		-- (only once it's close; the top timer already shows the next murder round)
		raidPill.Visible = type(raidEnds) == "number" or (type(nextRaid) == "number" and nextRaid - now < 60)
		raidText.Text = if type(raidEnds) == "number"
			then `BLOOD MOON {Ui.clock(raidEnds - now)}`
			elseif type(nextRaid) == "number" then `Blood Moon in {Ui.clock(nextRaid - now)}`
			else ""
		raidText.TextColor3 = if type(raidEnds) == "number" then Color3.fromRGB(255, 90, 90) else Color3.new(1, 1, 1)
		roundText.Text = if phase == "Round"
			then "Murder round on!"
			elseif status:find("Waiting") then "Waiting for players"
			else `Murder in {clock}`
		local nextChest = (player:GetAttribute("NextFreeChest") or 0) :: number
		local chestLeft = nextChest - now
		chestText.Text = if chestLeft <= 0 then "Free Chest" else Ui.clock(chestLeft)
		chestText.TextColor3 = Color3.new(1, 1, 1)
		chestText.TextScaled = true -- (something resets it once after the skin; keep it like the others)
		-- (no HUD chest button any more: the chest itself on the plaza says FREE! - less is more)
		chestPill.Visible = false
		shieldPill.Visible = false -- remaining shield/boost times are available in Stats
		raidPill.Visible = false -- the top timer already reports active raids
		-- The chest's own label on the plaza counts down for you too
		if not freeChestLabel or not freeChestLabel.Parent then
			local map = workspace:FindFirstChild("Map")
			local rewards = map and map:FindFirstChild("PlazaRewards")
			local chest = rewards and rewards:FindFirstChild("FreeChest")
			freeChestLabel = chest and chest:FindFirstChild("Text", true) :: TextLabel?
		end
		if freeChestLabel then
			freeChestLabel.Text = if chestLeft <= 0 then "FREE!" else Ui.clock(chestLeft)
			freeChestLabel.TextColor3 = if chestLeft <= 0
				then Color3.fromRGB(120, 255, 140)
				else Color3.fromRGB(220, 220, 230)
		end
		-- Boost
		local boostUntil = player:GetAttribute("BoostUntil")
		local boostLeft = if type(boostUntil) == "number" then boostUntil - now else 0
		if boostLeft > 0 then
			incomeLabel.Text =
				`+${Ui.abbreviate(player:GetAttribute("Income") or 0)}/s  ·  {GameConfig.BoostMultiplier}x BOOST {Ui.clock(
					boostLeft
				)}`
			incomeLabel.TextColor3 = Color3.fromRGB(255, 210, 80)
		else
			incomeLabel.TextColor3 = Color3.new(1, 1, 1)
		end
	end)

	-- Notifications: small outlined words at the top under the timer, no box (big solid bars across
	-- the middle of the screen hid what you were doing) --------------------------------------------
	local toasts = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, if Ui.Phone then 176 else 196), -- under the timer and status
		Size = UDim2.fromOffset(if Ui.Phone then 520 else 600, 70),
		BackgroundTransparency = 1,
		-- On the Feedback layer, above every menu and screen: a toast (what you bought, why you
		-- can't) must never be hidden behind the window you clicked in
		ZIndex = 60,
	}, Ui.feedback)
	new("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Top,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	}, toasts)
	local toastOrder = 0

	local function toast(text: string, kind: string)
		for _, child in toasts:GetChildren() do
			if child:IsA("TextLabel") and child.Text == text then
				return -- already on screen
			end
		end
		local tint = KIND_COLORS[kind] or KIND_COLORS.info
		toastOrder += 1
		local bubble = Ui.label({
			LayoutOrder = -toastOrder, -- newest on top
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			TextScaled = false,
			TextSize = if Ui.Phone then 27 else 21, -- (the feedback layer is scaled down on phones)
			TextWrapped = true,
			TextColor3 = tint:Lerp(Color3.new(1, 1, 1), 0.3),
			Text = text,
		}, toasts)
		new("UISizeConstraint", { MaxSize = Vector2.new(if Ui.Phone then 520 else 600, math.huge) }, bubble)
		Ui.textStroke(bubble, 2)
		local scale = new("UIScale", { Scale = 0.6 }, bubble)
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		task.delay(if Ui.Phone then 2.5 else 3.5, function()
			local fade = TweenService:Create(
				bubble,
				TweenInfo.new(0.4),
				{ BackgroundTransparency = 1, TextTransparency = 1, TextStrokeTransparency = 1 }
			)
			fade:Play()
			fade.Completed:Wait()
			bubble:Destroy()
		end)
		local labels = {}
		for _, child in toasts:GetChildren() do
			if child:IsA("TextLabel") then
				table.insert(labels, child)
			end
		end
		table.sort(labels, function(a, b)
			return a.LayoutOrder > b.LayoutOrder -- oldest first
		end)
		while #labels > 2 do
			local oldest = table.remove(labels, 1) :: TextLabel
			oldest:Destroy()
		end
	end
	-- In a round nothing pops up at all: the game speaks for itself (a vanished Murderer, a body)
	Remotes.Notify.OnClientEvent:Connect(function(text: string, kind: string)
		if not player:GetAttribute("InRound") then
			toast(text, kind)
		end
	end)
	-- (client-side answers use the same toast: a click must always say something)
	Ui.Toast = toast

	-- Classic full-screen role reveal ----------------------------------------------------------
	local reveal = new("Frame", {
		-- Oversized so it also covers the top-bar inset
		Size = UDim2.new(1, 0, 1, 120),
		Position = UDim2.fromOffset(0, -60),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
	}, gui)
	local nameLabel = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(700, 70),
		TextColor3 = Color3.fromRGB(230, 230, 230),
		ZIndex = 21,
	}, reveal)
	local roleLabel = Ui.label({
		Font = Enum.Font.FredokaOne,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromOffset(800, 110),
		TextStrokeTransparency = 0,
		ZIndex = 21,
	}, reveal)
	local hintLabel = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromOffset(760, 36),
		TextColor3 = Color3.fromRGB(200, 200, 200),
		ZIndex = 21,
	}, reveal)

	-- The Murderer's own knife, big, above the reveal
	local knifeArt = new("ImageLabel", {
		Name = "MurdererKnife",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.5, -96),
		Size = UDim2.fromOffset(150, 150),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		ZIndex = 20,
	}, reveal)
	if Ui.Phone then
		new("UIScale", { Scale = Ui.phoneScale() }, knifeArt)
	end
	reveal:GetPropertyChangedSignal("Visible"):Connect(function()
		if not reveal.Visible then
			knifeArt.Visible = false
		end
	end)
	-- "You are..." then a slot-machine reel (MM2 / The Mad Murderer): INNOCENT / SHERIFF / MURDERER
	-- spin, slow down, sometimes slide just past MURDERER, and land - the role is already decided
	-- (server), this is the moment. A second Role message (Innocent -> Sheriff) skips the spin.
	local ROLES = {
		Innocent = { Text = "INNOCENT", Color = Color3.fromRGB(90, 230, 120) },
		Sheriff = { Text = "THE SHERIFF", Color = Color3.fromRGB(90, 170, 255) },
		Murderer = { Text = "THE MURDERER", Color = Color3.fromRGB(255, 50, 60) },
	}
	local ORDER = { "Innocent", "Sheriff", "Murderer" }
	local roleScale = new("UIScale", { Scale = 1 }, roleLabel) :: UIScale
	local reelRng = Random.new()
	local revealToken = 0
	local function showRole(key: string)
		local entry = ROLES[key]
		roleLabel.Text = entry.Text
		roleLabel.TextColor3 = entry.Color
	end
	Remotes.Role.OnClientEvent:Connect(function(role: string, disguise: string?)
		revealToken += 1
		local token = revealToken
		local final = if ROLES[role] then role else "Innocent"
		local respin = reveal.Visible -- (already showing: a role change, no second spin)
		nameLabel.Text = `You are {disguise or player.DisplayName}`
		local hint: string
		local knifeImage = ""
		if final == "Murderer" then
			-- Make the link obvious: this is the knife from YOUR vault, with its power
			local equipped = player:GetAttribute("Equipped")
			local parsed = if type(equipped) == "string" and equipped ~= "" then Items.Parse(equipped) else nil
			local perk = parsed and parsed.Perk and GameConfig.Perks[parsed.Perk]
			hint = if parsed
				then `You're fighting with YOUR {Items.DisplayName(equipped :: string)} from your vault{if perk
					then ` - power: {perk.DisplayName}!`
					else "!"} It arrives in {GameConfig.MurdererGrace}s.`
				else `Blend in - your knife arrives in {GameConfig.MurdererGrace}s, and pulling it out shows everyone!`
			knifeImage = if parsed
				then (VoxelUi.Knives[parsed.Knife.Name] or KnifeIcons[parsed.Knife.Name] or "")
				else ""
		elseif final == "Sheriff" then
			hint = "You have the Revolver! Find the Murderer and shoot them - but hit an innocent and you're out."
		else
			local power = player:GetAttribute("RoundPowerName")
			hint = if type(power) == "string" and power ~= ""
				then `Survive! Your power: {power}. Grab coins to charge it, and find the Revolver!`
				else "Survive. Grab coins to charge your powers. Find the Revolver!"
		end

		-- The round teleport's loading cover goes first: a reel spun behind it was never seen
		local waitedFrom = os.clock()
		while Ui.gui:GetAttribute("FadeCover") and os.clock() - waitedFrom < 6 do
			task.wait()
		end
		if token ~= revealToken then
			return
		end
		reveal.Visible = true
		reveal.BackgroundTransparency = 0.15
		knifeArt.Visible = false
		nameLabel.TextTransparency = 0
		roleLabel.TextTransparency = 0
		roleLabel.TextStrokeTransparency = 0
		hintLabel.Text = hint
		hintLabel.TextTransparency = 1

		if not respin then
			-- The spin: ~2 s, fast to slow. Build it backwards from the result; half the time the
			-- step before the landing is MURDERER (the near miss that makes you want the next one)
			local steps = 14
			local sequence: { string } = table.create(steps)
			sequence[steps] = final
			for i = steps - 1, 1, -1 do
				local nextKey = sequence[i + 1]
				local choice: string
				if i == steps - 1 and final ~= "Murderer" and reelRng:NextNumber() < 0.5 then
					choice = "Murderer"
				else
					repeat
						choice = ORDER[reelRng:NextInteger(1, #ORDER)]
					until choice ~= nextKey
				end
				sequence[i] = choice
			end
			for i, key in sequence do
				if token ~= revealToken then
					return
				end
				showRole(key)
				roleScale.Scale = 1.12
				TweenService:Create(roleScale, TweenInfo.new(0.08), { Scale = 1 }):Play()
				Effects.Sound(Sounds.ReelTick, nil, 0.35)
				if i < steps then
					local t = i / steps
					task.wait(0.05 + 0.3 * t * t * t)
				end
			end
		else
			showRole(final)
		end
		if token ~= revealToken then
			return
		end

		-- The landing: a punch, its own sound, then the hint (and the Murderer's knife)
		roleScale.Scale = 1.5
		TweenService:Create(roleScale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		if final == "Murderer" then
			Effects.Sound(Sounds.RoleMurderer, nil, 0.8)
			reveal.BackgroundColor3 = Color3.fromRGB(90, 0, 10)
			TweenService:Create(reveal, TweenInfo.new(0.6), { BackgroundColor3 = Color3.new(0, 0, 0) }):Play()
			knifeArt.Image = knifeImage
			knifeArt.Visible = knifeImage ~= ""
		else
			Effects.Sound(if final == "Sheriff" then Sounds.RoleSheriff else Sounds.RoleInnocent, nil, 0.7)
		end
		TweenService:Create(hintLabel, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()

		task.delay(2.8, function()
			if token ~= revealToken then
				return
			end
			local info = TweenInfo.new(0.8)
			TweenService:Create(reveal, info, { BackgroundTransparency = 1 }):Play()
			for _, label in { nameLabel, roleLabel, hintLabel } do
				TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
			task.wait(0.8)
			if token == revealToken then
				reveal.Visible = false
			end
		end)
	end)

	-- Physical pixels inside Roblox's safe area; input device never controls HUD scale.
	stats.AnchorPoint = Vector2.new(0, 1)
	stats.Position = UDim2.new(0, 12, 1, -12)
	stats.Size = UDim2.fromOffset(232, 44)
	local oldScale = stats:FindFirstChildOfClass("UIScale")
	if oldScale then
		oldScale:Destroy()
	end
	for _, child in stats:GetChildren() do
		if child:IsA("TextLabel") then
			child.Visible = child == speedLabel or child == cashLabel
		end
	end
	-- Steal An Egg readout: a big icon and a big chunky number per row, Speed over Cash
	local speedArt = Ui.art(stats, "Speed", { Image = CartoonArt.Speed }) -- the + badge is baked in
	local cashArt = Ui.art(stats, "Cash", { Image = CartoonArt.Cash })
	local heatArt = Ui.art(stats, "Heat", { Image = CartoonArt.Heat })
	heatLabel.Visible = true
	heatLabel.Font = Enum.Font.LuckiestGuy
	heatLabel.TextScaled = false
	heatLabel.TextXAlignment = Enum.TextXAlignment.Left
	heatLabel.TextYAlignment = Enum.TextYAlignment.Center
	for _, text in { speedLabel, cashLabel } do
		text.TextScaled = false
		text.Font = Enum.Font.LuckiestGuy
		text.TextTruncate = Enum.TextTruncate.None
		text.TextYAlignment = Enum.TextYAlignment.Center
		local stroke = text:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = if Ui.Phone then 2.5 else 3.5
		end
	end
	speedLabel.TextColor3 = Color3.new(1, 1, 1)
	local function placeStats()
		-- rows: icon size, text size, row height
		local icon, size, row = 46, 42, 54
		local x = 12
		if Ui.Phone then
			local _, bounds = Ui.bounds()
			local stick = if bounds.Y < 500 then 70 else 120
			-- as big as the screen allows (Steal An Egg keeps them huge on phones too)
			-- Steal An Egg keeps these small and tucked in: two short rows, no Heat row on phones
			size = math.clamp(math.floor(bounds.Y * 0.085), 26, 44) -- big and chunky, like theirs
			icon, row = math.floor(size * 1.1), math.floor(size * 1.2)
			x = 25 + stick + 12 -- just right of the thumbstick
		end
		heatArt.Visible, heatLabel.Visible = not Ui.Phone, not Ui.Phone
		-- a smaller Heat row on top (not on phones), then Speed, then Cash
		local small = if Ui.Phone then 0 else math.floor(row * 0.7)
		local smallIcon = math.floor(icon * 0.7)
		stats.Position, stats.Size = UDim2.new(0, x, 1, -12), UDim2.fromOffset(icon + 8 + size * 6, small + row * 2)
		heatArt.Position, heatArt.Size =
			UDim2.fromOffset((icon - smallIcon) / 2, (small - smallIcon) / 2), UDim2.fromOffset(smallIcon, smallIcon)
		speedArt.Position, speedArt.Size = UDim2.fromOffset(0, small + (row - icon) / 2), UDim2.fromOffset(icon, icon)
		cashArt.Position, cashArt.Size =
			UDim2.fromOffset(0, small + row + (row - icon) / 2), UDim2.fromOffset(icon, icon)
		heatLabel.Position, heatLabel.Size = UDim2.fromOffset(icon + 8, 0), UDim2.fromOffset(size * 6, small)
		speedLabel.Position, speedLabel.Size = UDim2.fromOffset(icon + 8, small), UDim2.fromOffset(size * 6, row)
		cashLabel.Position, cashLabel.Size = UDim2.fromOffset(icon + 8, small + row), UDim2.fromOffset(size * 6, row)
		speedLabel.TextSize, cashLabel.TextSize = math.floor(size * 0.9), size
		heatLabel.TextSize = math.floor(size * 0.6)
	end
	Ui.Layout.Changed:Connect(placeStats)
	placeStats()
	timers.AnchorPoint, timers.Position, timers.Size =
		Vector2.new(1, 0), UDim2.new(1, -12, 0, 0), UDim2.fromOffset(120, 44)
	local timerScale = timers:FindFirstChildOfClass("UIScale")
	if timerScale then
		timerScale:Destroy()
	end
	chestPill.Size = UDim2.fromOffset(120, 44)
	chestIcon.Size, chestIcon.Position = UDim2.fromOffset(26, 32), UDim2.fromOffset(2, 6)
	chestText.Position, chestText.Size = UDim2.fromOffset(36, 4), UDim2.fromOffset(80, 36)
	chestText.TextScaled, chestText.TextWrapped = true, false
	goalLabel.Visible = false
	goalLabel:GetPropertyChangedSignal("Visible"):Connect(function()
		if goalLabel.Visible then
			goalLabel.Visible = false
		end
	end)
	-- The coin pill (rounds): a slim line just above the health bar, sized to its words
	energyFrame.AnchorPoint, energyFrame.Position, energyFrame.Size =
		Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -38), UDim2.fromOffset(0, 26)
	energyFrame.AutomaticSize = Enum.AutomaticSize.X
	for _, child in energyFrame:GetChildren() do
		if child:IsA("TextLabel") then
			child.TextSize = 16
			child.Size = UDim2.fromOffset(0, 22)
			child.AutomaticSize = Enum.AutomaticSize.X
		elseif child:IsA("ImageLabel") then
			child.Size = UDim2.fromOffset(22, 22)
		end
	end
	healthFrame.AnchorPoint, healthFrame.Position, healthFrame.Size =
		Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -12), UDim2.fromOffset(180, 20)
	for _, text in { healthText, chanceLabel, subLabel } do
		text.TextScaled = false
		text.TextSize = if text == chanceLabel then 17 else 14
		text.TextTruncate = Enum.TextTruncate.AtEnd
	end
	local function layout()
		local _, bounds = Ui.bounds()
		local width = math.min(380, math.max(220, bounds.X - 300))
		local center = bounds.X / 2
		if Ui.Phone then
			local right = math.min(center + 90, Ui.Layout.knifePosition().X - 12)
			local left = if bounds.Y < 420 then 256 else 136
			local healthWidth = math.min(180, math.max(80, right - left))
			-- bottom centre, clear of the thumbstick and the knife / jump buttons
			healthFrame.Position = UDim2.new(0, math.min(center, right - healthWidth / 2), 1, -12)
			energyFrame.Position = UDim2.new(0, math.min(center, right - healthWidth / 2), 1, -38)
			healthFrame.Size = UDim2.fromOffset(healthWidth, 20)
		end
		-- The Murderer chance sits above the timer, so the timer is the lowest line up there and the
		-- view of the world (boss stashes, knife labels) stays clear
		chanceLabel.Position, chanceLabel.Size = UDim2.fromOffset(center, 0), UDim2.fromOffset(width, 20)
		timerFrame.Position, timerFrame.Size = UDim2.fromOffset(center, 18), UDim2.fromOffset(width, 40)
		subLabel.Position, subLabel.Size = UDim2.fromOffset(center, 68), UDim2.fromOffset(width, 20)
		subLabel.TextWrapped = false
		eventLabel.Position, eventLabel.Size = UDim2.fromOffset(center, 90), UDim2.fromOffset(width, 20)
		eventLabel.TextScaled, eventLabel.TextSize, eventLabel.TextTruncate = false, 14, Enum.TextTruncate.AtEnd
		banner.Size = UDim2.fromOffset(math.min(600, bounds.X - 24), 44)
		announceHolder.Size = UDim2.fromOffset(math.min(480, bounds.X - 24), 60)
		if Ui.Phone then
			-- Between the left buttons and the right ones, under the timer: never mid-screen
			local lane = math.max(220, math.min(420, bounds.X - 2 * 150))
			-- the tutorial line sits at 92-126: everything else goes under it while it's up
			local below = if Ui.gui:GetAttribute("TutorialBar") == true then 44 else 0
			announceHolder.Position, announceHolder.Size =
				UDim2.fromOffset(center, 66 + below), UDim2.fromOffset(lane, 30)
			toasts.AnchorPoint = Vector2.new(0.5, 0)
			toasts.Position, toasts.Size = UDim2.fromOffset(center, 100 + below), UDim2.fromOffset(lane, 70)
			local list = toasts:FindFirstChildOfClass("UIListLayout")
			if list then
				list.VerticalAlignment = Enum.VerticalAlignment.Top
				list.Padding = UDim.new(0, 3)
			end
			banner.Position = UDim2.fromOffset(center, 100)
			for _, text in { nameLabel, roleLabel, hintLabel } do
				local scale = text:FindFirstChildOfClass("UIScale") or new("UIScale", {}, text)
				scale.Scale = Ui.phoneScale()
			end
		end
		for _, text in { nameLabel, roleLabel, hintLabel } do
			text.Size = UDim2.new(1, -32, 0, if text == hintLabel then 60 else 54)
			text.TextWrapped = true
		end
		nameLabel.Position = UDim2.new(0.5, 0, 0.5, -72)
		roleLabel.Position = UDim2.new(0.5, 0, 0.5, -12)
		hintLabel.Position = UDim2.new(0.5, 0, 0.5, 54)
		hintLabel.TextScaled, hintLabel.TextSize = false, 14
		if not Ui.Phone then
			toasts.Size, toasts.Position =
				UDim2.fromOffset(math.min(440, bounds.X - 260), 96), UDim2.new(0.5, 0, 1, -160)
		end
	end
	Ui.Layout.Changed:Connect(layout)
	Ui.gui:GetAttributeChangedSignal("TutorialBar"):Connect(layout)
	layout()
	Ui.Menu.Changed:Connect(function()
		-- (toasts and announcements stay up with a menu open: they're how a click answers you)
		if Ui.menuOpen() then
			healthFrame.Visible = false
			energyFrame.Visible = false
		else
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			healthFrame.Visible = hum ~= nil
				and hum.Health > 0
				and hum.Health < hum.MaxHealth
				and not player:GetAttribute("InRound")
			refreshEnergy()
		end
	end)
end

Hud.CashLabel = nil :: TextLabel?

return Hud
