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
	local camera = workspace.CurrentCamera
	local minAxis = math.min(camera.ViewportSize.X, camera.ViewportSize.Y)
	local small = minAxis <= 500
	local ghosts = new("ScreenGui", { Name = "TouchGhosts", DisplayOrder = 50, ResetOnSpawn = false }, player.PlayerGui)
	local function ghost(position: UDim2, size: number, text: string)
		local frame = new("Frame", {
			Position = position,
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Color3.fromRGB(255, 60, 60),
			BackgroundTransparency = 0.6,
		}, ghosts)
		Ui.corner(frame, size)
		Ui.label({ Size = UDim2.fromScale(1, 1), Text = text }, frame)
	end
	local jump = if small then 70 else 120
	ghost(UDim2.new(1, -(jump * 1.5 - 10), 1, -jump - 20), jump, "JUMP")
	local stick = if small then 70 else 120
	ghost(
		if small then UDim2.new(0, stick / 2 - 10, 1, -stick - 20) else UDim2.new(0, stick / 2, 1, -stick * 1.75),
		stick,
		"STICK"
	)
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
	Ui.corner(timerFrame, 16)
	Ui.stroke(timerFrame)
	Ui.padding(timerFrame, 12, 6)
	local timerLabel = Ui.label({ Size = UDim2.fromScale(1, 1), Text = "Loading..." }, timerFrame)
	Ui.textStroke(timerLabel, 2)
	local subLabel = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(460, 26),
		Text = "",
	}, gui)
	Ui.textStroke(subLabel, 2)

	-- Bottom left: Speed and Cash -----------------------------------------------------------------
	-- (phones: top left beside the icon strip, away from the thumbstick)
	local stats = new("Frame", {
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

	-- Right side: upgrades ---------------------------------------------------------------------
	-- (phones: narrower, starting under the timers and ending above the jump button)
	local shop = new("Frame", {
		AnchorPoint = if Ui.Phone then Vector2.new(1, 0) else Vector2.new(1, 0.5),
		Position = if Ui.Phone then UDim2.new(1, -10, 0, 168) else UDim2.new(1, -12, 0.39, 0),
		Size = if Ui.Phone then UDim2.fromOffset(170, 250) else UDim2.fromOffset(230, 300),
		BackgroundTransparency = 1,
	}, gui)
	new("UIListLayout", {
		Padding = UDim.new(0, if Ui.Phone then 5 else 7),
		VerticalAlignment = if Ui.Phone then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, shop)
	local buttons: { [string]: TextButton } = {}
	local order = 0
	local function shopButton(kind: string, color: Color3, icon: string)
		order += 1
		local button = Ui.chunky(
			{
				Name = kind,
				LayoutOrder = order,
				Size = UDim2.new(1, 0, 0, if Ui.Phone then 46 else 54),
				BackgroundColor3 = color,
				Text = kind,
			},
			shop,
			icon,
			function()
				Remotes.Purchase:InvokeServer(kind)
			end
		)
		buttons[kind] = button
	end
	shopButton("Treadmill", Color3.fromRGB(70, 160, 255), "🎡")
	shopButton("Trail", Color3.fromRGB(190, 90, 255), "🔪")
	shopButton("Walls", Color3.fromRGB(150, 110, 80), "🏰")
	shopButton("Slot", Color3.fromRGB(255, 165, 50), "➕")
	shopButton("Ticket", Color3.fromRGB(225, 60, 80), "🎟️")
	local function setButtonText(kind: string, text: string)
		local label = buttons[kind]:FindFirstChild("Label") :: TextLabel?
		if label then
			label.Text = text
		end
	end

	-- Bottom right: event timers ----------------------------------------------------------------
	-- (phones: top right, out from under the jump button)
	local timers = new("Frame", {
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
	raidIcon.Text = "⚔️"
	local _roundPill, roundIcon, roundText = pill(timers, 2)
	roundIcon.Text = "🔪"
	local chestPill, chestIcon, chestText = pill(timers, 3)
	chestIcon.Text = "🎁"

	local function refreshStats()
		local cash = player:GetAttribute("Cash") or 0
		local slots = player:GetAttribute("Slots") or GameConfig.StartingSlots
		local speed = player:GetAttribute("Speed") or 0
		local treadmill = player:GetAttribute("TreadmillLevel") or 1
		local walls = player:GetAttribute("WallLevel") or 1
		local tickets = player:GetAttribute("Tickets") or 0
		local rebirths = player:GetAttribute("Rebirths") or 0
		cashLabel.Text = `${Ui.abbreviate(cash)}`
		speedLabel.Text = Ui.abbreviate(speed)
		local training = player:GetAttribute("Training")
		local rate = GameConfig.Treadmills[treadmill].Rate * (1 + rebirths * GameConfig.Rebirth.SpeedBonus)
		trainLabel.Text = if training
			then `+{Ui.abbreviate(rate)}/s  running!`
			else `{math.floor(GameConfig.WalkSpeedFor(speed))} walk speed`
		incomeLabel.Text = `+${Ui.abbreviate(player:GetAttribute("Income") or 0)}/s`
		rackLabel.Text = `Wall {player:GetAttribute("KnifeCount") or 0}/{slots}  ·  Luck {player:GetAttribute("Luck") or 0}`
			.. (if rebirths > 0 then `  ·  Rebirth {rebirths}` else "")

		local nextWheel = GameConfig.Treadmills[treadmill + 1]
		setButtonText(
			"Treadmill",
			if nextWheel then `{nextWheel.Name}\n${Ui.abbreviate(nextWheel.Cost)}` else "Wheel MAX"
		)
		local trailLevel = (player:GetAttribute("TrailLevel") or 0) :: number
		local nextTrail = GameConfig.Trails[trailLevel + 1]
		setButtonText(
			"Trail",
			if nextTrail
				then `{nextTrail.Name} x{nextTrail.Multiplier}\n${Ui.abbreviate(nextTrail.Cost)}`
				else "Trail MAX"
		)
		local nextWalls = GameConfig.Walls[walls + 1]
		setButtonText(
			"Walls",
			if nextWalls
				then `Upgrade Walls\n{Ui.abbreviate(nextWalls.GateHealth)} HP - ${Ui.abbreviate(nextWalls.Cost)}`
				else "Walls MAX"
		)
		setButtonText(
			"Slot",
			if slots >= GameConfig.MaxSlots
				then "Wall MAX"
				else `+1 Mount\n${Ui.abbreviate(GameConfig.SlotCost(slots))}`
		)
		setButtonText(
			"Ticket",
			`Murderer Ticket ({tickets})\n${Ui.abbreviate(
				GameConfig.TicketPrice((player:GetAttribute("Income") or 0) :: number)
			)}`
		)
	end
	for _, attribute in
		{
			"Cash",
			"Slots",
			"Speed",
			"TreadmillLevel",
			"TrailLevel",
			"WallLevel",
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
		if gained <= 0 then
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
	}, gui)
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
		Effects.Sound(if entry.Hype >= 2 then Sounds.Sting else Sounds.Coin, nil, if entry.Hype >= 2 then 0.6 else 0.4)
		TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0) })
			:Play()
		task.delay(2.6 + entry.Hype * 0.5, function()
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
		if #announceQueue > 4 then
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
		Position = UDim2.new(0.5, 0, 1, -180), -- leave room above the power buttons and their outlines
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
	energyText("⚡ ENERGY", 0, ENERGY_ON)
	new("Frame", { Size = UDim2.fromOffset(4, 1), BackgroundTransparency = 1, LayoutOrder = 1 }, energyFrame)
	local cells: { Frame } = {}
	for i = 1, GameConfig.MaxEnergy do
		local cell = new("Frame", {
			Size = UDim2.fromOffset(16, 20),
			BackgroundColor3 = ENERGY_OFF,
			LayoutOrder = 1 + i,
		}, energyFrame)
		Ui.corner(cell, 4)
		new("UIStroke", { Thickness = 1.5, Color = Color3.fromRGB(14, 10, 20) }, cell)
		table.insert(cells, cell)
	end
	new("Frame", { Size = UDim2.fromOffset(4, 1), BackgroundTransparency = 1, LayoutOrder = 98 }, energyFrame)
	local countLabel = energyText("0/" .. GameConfig.MaxEnergy, 99, Color3.fromRGB(235, 230, 245))
	local lastEnergy = 0
	local function refreshEnergy()
		local energy = player:GetAttribute("Energy")
		energyFrame.Visible = type(energy) == "number"
		if type(energy) ~= "number" then
			return
		end
		for i, cell in cells do
			cell.BackgroundColor3 = if i <= energy then ENERGY_ON else ENERGY_OFF
		end
		countLabel.Text = `{math.floor(energy)}/{GameConfig.MaxEnergy}`
		if energy > lastEnergy then
			local scale = energyFrame:FindFirstChildOfClass("UIScale") or new("UIScale", {}, energyFrame)
			scale.Scale = 1.12
			TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		lastEnergy = energy
	end
	player:GetAttributeChangedSignal("Energy"):Connect(refreshEnergy)
	refreshEnergy()

	-- Zone title: the zone's name fades in at the top of the screen when you cross into it ------
	local zoneTitle = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 256),
		Size = UDim2.fromOffset(620, 64),
		Font = Ui.SPOOKY,
		TextStrokeTransparency = 0,
		TextTransparency = 1,
		TextStrokeColor3 = Color3.new(0, 0, 0),
	}, gui)
	local zoneNeed = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 318),
		Size = UDim2.fromOffset(560, 28),
		TextStrokeTransparency = 0,
		TextTransparency = 1,
	}, gui)
	local currentZone = 0
	local function showZone(index: number)
		local zone = GameConfig.Zones[index]
		zoneTitle.Text = ((zone :: any).Title or zone.Rarity):upper()
		zoneTitle.TextColor3 = zone.Color
		-- How fast you need to be to get a case home from here
		local need = (zone :: any).SpeedNeeded or 0
		local have = player:GetAttribute("Speed") or 0
		zoneNeed.Text = if need <= 0
			then "No speed needed"
			elseif have >= need then `{Ui.abbreviate(need)} Speed needed - you're fast enough!`
			else `{Ui.abbreviate(need)} Speed needed - you have {Ui.abbreviate(have)}. Run in your Haunted Wheel!`
		zoneNeed.TextColor3 = if need <= 0 or have >= need
			then Color3.fromRGB(120, 230, 150)
			else Color3.fromRGB(255, 110, 110)
		local info = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 2)
		for _, label in { zoneTitle, zoneNeed } do
			label.TextTransparency = 0
			label.TextStrokeTransparency = 0
			TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end
	RunService.Heartbeat:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or player:GetAttribute("InRound") then
			currentZone = 0
			return
		end
		local p = root.Position
		local half = GameConfig.ArenaWidth / 2
		local index = 0
		if math.abs(p.X) <= half and p.Z >= 0 then
			index = math.min(math.floor(p.Z / GameConfig.ZoneDepth) + 1, #GameConfig.Zones)
		end
		if index ~= currentZone then
			currentZone = index
			if index > 0 then
				showZone(index)
			end
		end
	end)

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
			local line1 = if phase == "Round"
				then "MURDER ROUND IN PROGRESS"
				elseif phase == "Results" then "ROUND OVER"
				elseif status:find("Waiting") then string.upper(status)
				else `MURDER ROUND IN {Ui.clock(left)}`
			local line2 = if type(raidEnds) == "number"
				then `BLOOD MOON {Ui.clock(raidEnds - now)}`
				elseif type(nextRaid) == "number" then `BLOOD MOON IN {Ui.clock(nextRaid - now)}`
				else "DEEPER = RARER CASES"
			local texts = { line1, line2, "SURVIVORS EARN 2X VAULT INCOME" }
			local colors = { Color3.fromRGB(255, 80, 90), Color3.fromRGB(255, 210, 90), Color3.fromRGB(120, 230, 150) }
			for _, face in (board :: Instance):GetChildren() do
				for i = 1, #texts do
					local label = face:FindFirstChild(`Line{i}`) :: TextLabel?
					if label then
						label.Text = texts[i]
						label.TextColor3 = colors[i]
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
		timerFrame.Visible = true
		if phase == "Round" then
			local map = ReplicatedStorage:GetAttribute("MapName") or ""
			timerLabel.Text = `{map}  {clock}  ·  {ReplicatedStorage:GetAttribute("Alive") or 0} alive`
			timerFrame.BackgroundColor3 = Color3.fromRGB(150, 30, 50)
			local bits = {}
			local disguise = player:GetAttribute("Disguise")
			if inRound and disguise then
				local role = player:GetAttribute("Role")
				table.insert(bits, `You are {disguise} ({role})`)
			elseif not inRound then
				table.insert(bits, "Round in progress - steal while they're busy!")
			end
			local revolver = ReplicatedStorage:GetAttribute("Revolver")
			if revolver == "Dropped" then
				table.insert(bits, "Revolver on the floor!")
			elseif revolver == "Taken" then
				table.insert(bits, "Someone has the Revolver")
			end
			local loot = ReplicatedStorage:GetAttribute("Loot")
			if loot then
				table.insert(bits, `Murderer loot: {loot}`)
			end
			subLabel.Text = table.concat(bits, "   ·   ")
		elseif type(raidEnds) == "number" then
			-- The raid takes over the top of the screen, pulsing red
			local pulse = (math.sin(os.clock() * 6) + 1) / 2
			timerLabel.Text = `🌕 BLOOD MOON  {Ui.clock(raidEnds - now)}`
			timerFrame.BackgroundColor3 = Color3.fromRGB(120, 20, 30):Lerp(Color3.fromRGB(200, 40, 50), pulse)
			local revengeUntil = player:GetAttribute("RevengeUntil")
			subLabel.Text = if type(revengeUntil) == "number" and revengeUntil > now
				then `REVENGE! Their vault is open to you: {Ui.clock(revengeUntil - now)}`
				else "Burglars are out · gates are weak · bounties x2!"
		elseif phase == "Results" or status:find("Waiting") then
			timerLabel.Text = if phase == "Results" then "Round over!" else status
			timerFrame.BackgroundColor3 = Ui.PANEL
			subLabel.Text = ""
		else
			timerLabel.Text = `{status} {clock}`
			timerFrame.BackgroundColor3 = Ui.PANEL
			local revengeUntil = player:GetAttribute("RevengeUntil")
			subLabel.Text = if type(revengeUntil) == "number" and revengeUntil > now
				then `REVENGE! Their vault is open to you: {Ui.clock(revengeUntil - now)}`
				elseif (endsAt - now) < 30 then "Get ready! Check your powers [B]"
				else ""
		end
		banner.Visible = phase == "Results"
		if phase == "Results" then
			banner.Text = status
		end
		shop.Visible = not inRound
		stats.Visible = not inRound
		timers.Visible = not inRound

		-- Event pills
		local nextRaid = ReplicatedStorage:GetAttribute("NextRaidAt")
		raidPill.Visible = type(raidEnds) == "number" or type(nextRaid) == "number"
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
		chestText.Text = if chestLeft <= 0 then "Free chest READY!" else `Free chest {Ui.clock(chestLeft)}`
		chestText.TextColor3 = if chestLeft <= 0 then Color3.fromRGB(120, 255, 140) else Color3.new(1, 1, 1)
		chestPill.Visible = true
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

	-- Notifications (stack at the bottom middle) -------------------------------------------------
	local toasts = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -230), -- above the power bar and the Energy bar
		Size = UDim2.fromOffset(560, 220),
		BackgroundTransparency = 1,
	}, gui)
	new("UIListLayout", {
		Padding = UDim.new(0, 6),
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, toasts)

	gui:GetAttributeChangedSignal("RepairVisible"):Connect(function()
		toasts.Position = UDim2.new(0.5, 0, 1, if gui:GetAttribute("RepairVisible") then -298 else -230)
	end)

	Remotes.Notify.OnClientEvent:Connect(function(text: string, kind: string)
		local toast = Ui.label({
			Size = UDim2.fromOffset(0, 36),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 0,
			BackgroundColor3 = KIND_COLORS[kind] or KIND_COLORS.info,
			TextScaled = false,
			TextSize = 22,
			Text = text,
		}, toasts)
		Ui.corner(toast, 12)
		Ui.stroke(toast, 2)
		Ui.textStroke(toast, 1.5)
		Ui.padding(toast, 14, 4)
		local scale = new("UIScale", { Scale = 0.6 }, toast)
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		task.delay(4, function()
			local fade = TweenService:Create(
				toast,
				TweenInfo.new(0.4),
				{ BackgroundTransparency = 1, TextTransparency = 1, TextStrokeTransparency = 1 }
			)
			fade:Play()
			fade.Completed:Wait()
			toast:Destroy()
		end)
		local labels = {}
		for _, child in toasts:GetChildren() do
			if child:IsA("TextLabel") then
				table.insert(labels, child)
			end
		end
		if #labels > 5 then
			labels[1]:Destroy()
		end
	end)

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
		Font = Ui.SPOOKY,
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

	Remotes.Role.OnClientEvent:Connect(function(role: string, disguise: string?)
		nameLabel.Text = `You are {disguise or player.DisplayName}`
		if role == "Murderer" then
			roleLabel.Text = "THE MURDERER"
			roleLabel.TextColor3 = Color3.fromRGB(255, 50, 60)
			hintLabel.Text =
				`Your knife arrives in {GameConfig.MurdererGrace}s. Click to stab, hold to throw. Every kill steals a knife!`
		else
			roleLabel.Text = "INNOCENT"
			roleLabel.TextColor3 = Color3.fromRGB(90, 230, 120)
			hintLabel.Text = "Survive. Grab coins to charge your powers (Z X C). Find the Revolver!"
		end
		Effects.Sound(Sounds.Sting, nil, 0.8)
		reveal.Visible = true
		reveal.BackgroundTransparency = 0.15
		for _, label in { nameLabel, roleLabel, hintLabel } do
			label.TextTransparency = 0
			label.TextStrokeTransparency = if label == roleLabel then 0 else 1
		end
		task.delay(3.5, function()
			local info = TweenInfo.new(0.8)
			TweenService:Create(reveal, info, { BackgroundTransparency = 1 }):Play()
			for _, label in { nameLabel, roleLabel, hintLabel } do
				TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
			task.wait(0.8)
			reveal.Visible = false
		end)
	end)
end

Hud.CashLabel = nil :: TextLabel?

return Hud
