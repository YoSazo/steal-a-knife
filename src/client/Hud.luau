--!strict
-- Always-on HUD, Steal An Egg style:
--   * bottom left: your Speed and Cash in big chunky numbers (with income, training, boost)
--   * right: upgrade buttons (Haunted Wheel, vault walls, mounts, Murderer tickets)
--   * top: the phase / round timer, raid banner, and big server-wide announcements
--   * rounds: the role reveal, results
--   * toasts, the zone title when you cross into a new part of the runway
-- Pure display; every number comes from attributes the server sets.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PenMode = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PenMode"))
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local WorldSignModel = require(ReplicatedStorage.Shared.WorldSignModel)
local CartoonArt = require(ReplicatedStorage.Shared.Config.CartoonArt)
local VoxelUi = require(ReplicatedStorage.Shared.Config.VoxelUi)
local RoundPrize = require(ReplicatedStorage.Shared.RoundPrize)
local KnifeIcons = require(ReplicatedStorage.Shared.Config.KnifeIcons)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local TopLine = require(script.Parent.TopLine)
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

function Hud.Init()
	local gui = Ui.gui
	if
		Ui.Phone
		and RunService:IsStudio()
		and ReplicatedStorage:GetAttribute("DebugPhone")
		and not UserInputService.TouchEnabled
	then
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
	local timerCap = timerLabel:FindFirstChildOfClass("UITextSizeConstraint")
	if timerCap then
		timerCap.MaxTextSize = if Ui.Phone then 24 else 36
	end
	-- (the old line under the timer - "REVENGE!", a second "round on" - is gone: one top line)
	local subLabel = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(460, 26),
		Text = "",
		Visible = false,
	}, gui)

	-- The top line's resting text (client/TopLine; notices take its place for a few seconds):
	--   * between rounds: "🔪 MURDER ROUND in 3:12"
	--       - after the tutorial it takes turns with your next goal ("🎯 Next: steal from Ivy ...";
	--         25 of 60 early quitters left right after placing their first knife: nothing said what next)
	--       - the last AnnounceAt seconds it takes turns with what the Murder Round pays, one side at a
	--         time, with a small "x2 R$25" pill (RoundPrize; the server pays the same numbers)
	--       - the last 10 s: just the time, red and pulsing
	--   * in a round: "2:15 · 4 alive" (the map's name too while you watch)
	local doubleButton = Ui.button(
		{
			Name = "DoublePrize",
			Size = UDim2.fromOffset(78, 22),
			BackgroundColor3 = Color3.fromRGB(0, 176, 111),
			Text = "x2 R$25",
			TextScaled = false,
			TextSize = 13,
		},
		gui,
		function()
			if Ui.Buy and ((player:GetAttribute("Charge_DoublePrize") or 0) :: number) == 0 then
				Ui.Buy("Product", "DoublePrize")
			end
		end
	)
	TopLine.SetPill(doubleButton)
	-- Phones, in a round: the prize gets its own badge on the left, just above the thumbstick
	-- ("2:04 · GET EVERYONE = +$5K" didn't fit the top line and ended in "...")
	local prizeBadge = Ui.new("Frame", {
		Name = "RoundPrizeBadge",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 0.56, 0),
		Size = UDim2.fromOffset(92, 74),
		BackgroundColor3 = Color3.fromRGB(24, 22, 36),
		BackgroundTransparency = 0.25,
		Visible = false,
	}, gui) :: Frame
	Ui.corner(prizeBadge, 12)
	Ui.new("UIStroke", { Color = Color3.fromRGB(140, 255, 150), Thickness = 2 }, prizeBadge)
	local badgeIcon = Ui.art(prizeBadge, "Icon", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(34, 34),
	})
	local badgeText = Ui.label({
		Name = "Prize",
		Position = UDim2.fromOffset(4, 40),
		Size = UDim2.new(1, -8, 0, 28),
		Text = "",
		TextColor3 = Color3.fromRGB(140, 255, 150),
	}, prizeBadge)
	Ui.textStroke(badgeText, 2)
	-- (what to do next is the guide's DO line now - client/Guide; this line is information only)
	TopLine.Resting = function(): TopLine.Rest?
		if Ui.menuOpen() or Ui.gui:GetAttribute("FadeCover") == true then
			prizeBadge.Visible = false
			return nil
		end
		local phase = ReplicatedStorage:GetAttribute("Phase")
		local status = (ReplicatedStorage:GetAttribute("Status") or "") :: string
		local endsAt = (ReplicatedStorage:GetAttribute("PhaseEndsAt") or 0) :: number
		local now = workspace:GetServerTimeNow()
		local left = endsAt - now
		local clock = Ui.clock(left)
		if phase == "Round" then
			local alive = ReplicatedStorage:GetAttribute("Alive") or 0
			-- (not during the first seconds: it would give your role away before the role reel lands)
			local elapsed = GameConfig.RoundTime - left
			prizeBadge.Visible = false
			if player:GetAttribute("InRound") and elapsed < 6 then
				return { Text = `🔪 {clock}  ·  {alive} alive` }
			end
			if player:GetAttribute("InRound") then
				-- how YOU win, and what it gets you, all round long
				local prize = RoundPrize.For(
					"Speed",
					"",
					ReplicatedStorage:GetAttribute("PrizeJackpot") == true,
					1,
					RoundPrize.Stats(player),
					((player:GetAttribute("Charge_DoublePrize") or 0) :: number) > 0
				)
				local goal = if player:GetAttribute("Role") == "Murderer"
					then "GET EVERYONE"
					else if Ui.gui:GetAttribute("GuideRole") == "Sheriff" then "STOP THE MURDERER" else "SURVIVE"
				-- (the prize you picked after it - the Speed shoe or the cash, like the line before the round;
				-- phones: on the badge instead, the line only fits the clock and the goal)
				local icon = if prize.Kind == "Cash" then CartoonArt.Cash else CartoonArt.Speed
				if Ui.Phone then
					prizeBadge.Visible = true
					badgeIcon.Image = icon
					badgeText.Text = `WIN {prize.Text:gsub(" Speed$", "")}`
					return { Text = `{clock} · <b>{goal}</b>` }
				end
				return {
					Text = `🔪 {clock} · <b>{goal}</b> = <font color="#8CFF96">{prize.Text}</font>`,
					Icon = icon,
				}
			end
			return {
				Text = `🔪 {ReplicatedStorage:GetAttribute("MapName") or "Murder Round"} {clock}  ·  {alive} alive  ·  steal while they're busy!`,
			}
		end
		prizeBadge.Visible = false
		if phase == "Results" then
			return { Text = `<font color="#FFE678">{status}</font>` }
		end
		if status ~= "🔪 MURDER ROUND in" then
			return if status ~= "" then { Text = status } else nil
		end
		if left <= 10 and left > 0 and not player:GetAttribute("InRound") then
			return { Text = `<font color="#FF4646"><b>🔪 MURDER ROUND in {clock}</b></font>`, Pulse = true }
		end
		local timer = { Text = `🔪 MURDER ROUND in <b>{clock}</b>` }
		local beat = os.clock() % 10
		local kind = ReplicatedStorage:GetAttribute("PrizeKind")
		if type(kind) == "string" and left <= GameConfig.RoundPrize.AnnounceAt and left > 0 then
			if beat < 4 then
				return timer
			end
			local jackpot = ReplicatedStorage:GetAttribute("PrizeJackpot") == true
			local seed = (ReplicatedStorage:GetAttribute("PrizeSeed") or 1) :: number
			local doubled = ((player:GetAttribute("Charge_DoublePrize") or 0) :: number) > 0
			local stats = RoundPrize.Stats(player)
			local star = if jackpot then "⭐ JACKPOT! " else ""
			local done = if doubled then '  <font color="#78FF8C">✓ x2</font>' else ""
			-- One promise for everyone: "Win the round: +1.9K Speed" (+ "outrun Ivy!" when it gets you
			-- there). No sides to work out - whoever wins gets it.
			local prize = RoundPrize.For(kind, "", jackpot, seed, stats, doubled)
			-- (always says what the Speed is for: the next boss you can't outrun yet)
			-- what it's FOR, in things you can see: the next knives ("RARE knives"), never a boss's name
			local zoneColor = if prize.Zone then (GameConfig.Zones :: any)[prize.Zone].Color :: Color3 else nil
			local knives = if prize.Rarity and zoneColor
				then `<font color="#{zoneColor:Lerp(Color3.new(1, 1, 1), 0.3):ToHex()}">{string.upper(prize.Rarity)} knives</font>`
				else nil
			local outrun = if knives and prize.Reaches then ` = {knives}!` elseif knives then ` for {knives}` else ""
			return {
				Text = `{star}Win the round: <font color="#8CFF96"><b>{prize.Text}</b></font>{outrun}{done}`,
				Short = `{clock} · Win <font color="#8CFF96"><b>{prize.Text}</b></font>{done}`,
				-- (not before your first round: 12 of 48 "x2 R$25" prompts came mid-tutorial, closed in ~1.6 s -
				-- taps meant for the timer line, a Robux popup in the first minutes)
				Pill = not doubled and ((player:GetAttribute("RoundsPlayed") or 0) :: number) > 0,
				Icon = if prize.Kind == "Cash" then CartoonArt.Cash else CartoonArt.Speed, -- (as your readout)
			}
		end
		return timer
	end
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
			-- Only YOUR two upgrade signs exist for you: everyone else's are hidden on your screen
			if bases then
				for _, other in bases:GetChildren() do
					for _, signName in { "UpgradeSign", "WheelUpgradeSign" } do
						local sign = other:FindFirstChild(signName)
						local mine = other == base
						-- (checked part by part, every tick: with streaming a sign's parts arrive later
						-- than the sign itself, and a once-per-sign flag left them showing)
						if sign then
							for _, d in sign:GetDescendants() do
								if d:GetAttribute("ShownToMe") == mine then
									continue
								end
								d:SetAttribute("ShownToMe", mine)
								if d:IsA("BasePart") then
									-- (a client-side change: only your own screen; LocalTransparencyModifier got reset)
									local original = d:GetAttribute("ShownTransparency")
									if original == nil then
										original = d.Transparency
										d:SetAttribute("ShownTransparency", original)
									end
									d.Transparency = if mine then original :: number else 1
									d.CanQuery = mine
									local collides = d:GetAttribute("ShownCollide")
									if collides == nil then
										collides = d.CanCollide
										d:SetAttribute("ShownCollide", collides)
									end
									d.CanCollide = mine and collides == true
								elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") or d:IsA("ProximityPrompt") then
									(d :: any).Enabled = mine
								elseif d:IsA("ClickDetector") then
									d.MaxActivationDistance = if mine then WorldSignModel.UpgradeRange else 0
								end
							end
						end
					end
				end
			end
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
				labels.Title.Text = PenMode.Words("Bigger Vault")
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
				wheelLabels.Title.Text = "Faster Wheel"
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

	-- "Your chance to be the Murderer: 6%" (MM2 style), between rounds
	local chanceLabel = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 98),
		Size = UDim2.fromOffset(420, 22),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 110, 120),
	}, gui)
	Ui.textStroke(chanceLabel, 1.5)
	local roundPrizeIcon = Ui.art(chanceLabel, "RoundPrizeSpeed", {
		Image = CartoonArt.Speed,
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Visible = false,
	})
	-- (plain text, centred: no icon beside it)
	local function refreshChance()
		local chance = player:GetAttribute("MurdererChance")
		local inRound = player:GetAttribute("InRound") == true
		-- (in a round the status line already says "SURVIVE = +1.1K 👟": no second prize line)
		roundPrizeIcon.Visible = false
		if inRound then
			chanceLabel.Visible = false
			return
		end
		chanceLabel.TextColor3 = Color3.fromRGB(255, 110, 120)
		chanceLabel.TextXAlignment = Enum.TextXAlignment.Center
		local chanceStrip = Ui.topStrip("Chance")
		if chanceStrip then
			chanceLabel.Position = UDim2.fromOffset(chanceStrip.X, chanceStrip.Y)
			chanceLabel.Size = UDim2.fromOffset(chanceStrip.W, chanceStrip.H)
		else
			local _, bounds = Ui.bounds()
			chanceLabel.Size = UDim2.fromOffset(math.min(420, bounds.X - 24), 20)
		end
		-- (only after your first round: before that it's a number about something you haven't seen)
		chanceLabel.Visible = type(chance) == "number"
			and Ui.inHub()
			and ((player:GetAttribute("RoundsPlayed") or 0) :: number) > 0
		chanceLabel.Text = `🔪 Murderer chance: {chance or 0}%`
	end
	player:GetAttributeChangedSignal("RoundsPlayed"):Connect(refreshChance)
	player:GetAttributeChangedSignal("MurdererChance"):Connect(refreshChance)
	player:GetAttributeChangedSignal("InRound"):Connect(refreshChance)
	Ui.Layout.Changed:Connect(refreshChance)
	local chanceChecked = 0
	RunService.Heartbeat:Connect(function()
		if os.clock() - chanceChecked >= 0.25 then
			chanceChecked = os.clock()
			refreshChance() -- returning home changes position after InRound clears
		end
	end)
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

	-- (No Upgrades button any more: the wheel + trail are one "Upgrade Wheel" sign by your Haunted
	-- Wheel, the vault floor is the Upgrade Base sign / the Knives panel, and Health is gone.)

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
		local rate = GameConfig.TrainRate(
			treadmill,
			rebirths,
			(player:GetAttribute("TrailLevel") or 0) :: number,
			player:GetAttribute("Pass_PhantomTrail") == true,
			player:GetAttribute("Pass_FastWheel") == true,
			false
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

	-- Announcements: big banners across the top for rare coffins, rebirths -----------------------
	local announceHolder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 178),
		Size = UDim2.fromOffset(720, 70),
		BackgroundTransparency = 1,
	}, Ui.feedback) -- (above every menu: never hidden behind a window)
	-- (announcements go on the top line now - client/TopLine - one at a time, in their colour; they
	-- used to be a big coloured pill dropping in under the timer, over the middle of the screen)
	Remotes.Effect.OnClientEvent:Connect(function(kind: string, text: string, color: Color3, hype: number)
		if kind ~= "Announce" or type(text) ~= "string" then
			return
		end
		local tint = if typeof(color) == "Color3" then color:Lerp(Color3.new(1, 1, 1), 0.35) else Color3.new(1, 1, 1)
		Effects.Sound(if (hype or 1) >= 2 then Sounds.Announce else Sounds.Coin, nil, 0.4)
		TopLine.Show(`<font color="#{tint:ToHex()}">{text}</font>`, 2.4 + (hype or 1) * 0.4)
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
			-- Tsunami style: each event's name in its own colour, then the time in white
			local function line(color: string, name: string, rest: string): string
				return `<font color="{color}">{name}</font> {rest}`
			end
			local line1 = if phase == "Round"
				then line("#FF5A5A", "MURDER ROUND", "NOW!")
				elseif phase == "Results" then line("#FF5A5A", "MURDER ROUND", "OVER")
				elseif status:find("Waiting") then line("#FF5A5A", string.upper(status), "")
				else line("#FF5A5A", "MURDER ROUND", `IN {Ui.clock(left)}`)
			-- (no Blood Moon any more: line 2 is what winning the round gets you)
			local prize = RoundPrize.For(
				"Speed",
				"",
				ReplicatedStorage:GetAttribute("PrizeJackpot") == true,
				1,
				RoundPrize.Stats(player),
				false
			)
			local texts = {
				line1,
				line("#8CFF96", "WIN IT:", `{string.upper(prize.Text)}`),
				if prize.Rarity then line("#FFE14B", "FOR", `{string.upper(prize.Rarity)} KNIVES`) else "",
				"", -- (no server goals any more)
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

	-- The bosses' speed boards (server GuardService): green with a tick once YOU are fast enough
	task.spawn(function()
		local CollectionService = game:GetService("CollectionService")
		while true do
			local speed = (player:GetAttribute("Speed") or 0) :: number
			for _, sign in CollectionService:GetTagged("SpeedSign") do
				local need = (sign:GetAttribute("Need") or 0) :: number
				local surface = sign:FindFirstChildOfClass("SurfaceGui")
				local title = surface and surface:FindFirstChild("Title") :: TextLabel?
				local value = surface and surface:FindFirstChild("Value") :: TextLabel?
				if title and value then
					local fast = speed >= need
					title.Text = if fast then "✓ YOU'RE FAST ENOUGH" else "SPEED NEEDED"
					title.TextColor3 = if fast then Color3.fromRGB(120, 255, 140) else Color3.fromRGB(255, 225, 90)
					value.TextColor3 = if fast then Color3.fromRGB(120, 255, 140) else Color3.new(1, 1, 1)
				end
			end
			task.wait(1)
		end
	end)

	-- Timers, banners, every frame ------------------------------------------------------------
	RunService.RenderStepped:Connect(function()
		local phase = ReplicatedStorage:GetAttribute("Phase")
		local endsAt = ReplicatedStorage:GetAttribute("PhaseEndsAt") or 0
		local status = ReplicatedStorage:GetAttribute("Status") or ""
		local now = workspace:GetServerTimeNow()
		local clock = Ui.clock(endsAt - now)
		local inRound = player:GetAttribute("InRound")
		timerFrame.Visible = false -- (the time is on the top line now: client/TopLine, TopLine.Resting)
		if phase == "Round" then
			local map = ReplicatedStorage:GetAttribute("MapName") or ""
			-- In a round the screen is for the game: just the time and who's left (MM2 shows less)
			timerLabel.Text = if inRound
				then `{clock}  ·  {ReplicatedStorage:GetAttribute("Alive") or 0} alive`
				else `{map}  {clock}  ·  {ReplicatedStorage:GetAttribute("Alive") or 0} alive`
			timerFrame.BackgroundColor3 = Color3.fromRGB(150, 30, 50)
		elseif phase == "Results" or status:find("Waiting") then
			timerLabel.Text = if phase == "Results" then "Round over!" else status
			timerFrame.BackgroundColor3 = Ui.PANEL
		else
			timerLabel.Text = `MURDER ROUND in {clock}`
			timerFrame.BackgroundColor3 = Ui.PANEL
		end
		-- The last 10 s before a round: the timer itself goes red and pulses (that IS the countdown;
		-- a second big red one on top of it used to cover it on phones)
		local finalCount = phase == "Intermission"
			and status == "🔪 MURDER ROUND in"
			and endsAt - now <= 10
			and endsAt - now > 0
			and not inRound
		timerLabel.TextColor3 = if finalCount then Color3.fromRGB(255, 70, 70) else Color3.new(1, 1, 1)
		local timerPulse = timerLabel:FindFirstChildOfClass("UIScale") or new("UIScale", {}, timerLabel)
		timerPulse.Scale = if finalCount then 1.1 + 0.08 * math.abs(math.sin((endsAt - now) * math.pi)) else 1
		-- ("Innocents win!" etc. is the top line's resting text during Results: TopLine.Resting)
		banner.Visible = false
		-- (not hidden while the knife is held: they never overlap, and taps made it flicker)
		stats.Visible = not Ui.menuOpen() and Ui.inHub() -- (speed / cash: hub things; not while dead in a round)
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
		Name = "Toasts",
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

	local function showToast(text: string, kind: string): TextLabel?
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
			if not bubble.Parent then
				return
			end
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
		return bubble
	end
	local toastQueue: { { Text: string, Kind: string } } = {}
	local toastWorker = false
	local function busy(): boolean
		return Ui.gui:GetAttribute("Presenting") == true or Ui.gui:GetAttribute("FadeCover") == true
	end
	local function toast(text: string, kind: string)
		for _, entry in toastQueue do
			if entry.Text == text then
				return
			end
		end
		table.insert(toastQueue, { Text = text, Kind = kind })
		while #toastQueue > 4 do
			table.remove(toastQueue, 1)
		end
		if toastWorker then
			return
		end
		toastWorker = true
		task.spawn(function()
			while #toastQueue > 0 do
				-- Related Notify/Effect events can arrive in either order. Let the reveal register first.
				task.wait(0.15)
				while busy() or player:GetAttribute("InRound") do
					task.wait(0.1)
				end
				local entry = table.remove(toastQueue, 1) :: { Text: string, Kind: string }
				local bubble = showToast(entry.Text, entry.Kind)
				while bubble and bubble.Parent do
					if busy() or player:GetAttribute("InRound") then
						bubble:Destroy()
						table.insert(toastQueue, 1, entry)
						break
					end
					task.wait(0.05)
				end
			end
			toastWorker = false
		end)
	end
	Ui.gui:GetAttributeChangedSignal("Presenting"):Connect(function()
		toasts.Visible = not busy()
	end)
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
		Name = "RoleReveal",
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
		-- (the screen's width, not a fixed 760: it was cut off on small phones) - the one line that
		-- says what to do and what you win, so bright
		Size = UDim2.new(0.94, 0, 0, if Ui.Phone then 30 else 36),
		TextColor3 = Color3.fromRGB(255, 235, 140),
		ZIndex = 21,
	}, reveal)
	local hintCap = hintLabel:FindFirstChildOfClass("UITextSizeConstraint")
	if hintCap then
		hintCap.MaxTextSize = if Ui.Phone then 22 else 30
	end

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
		local function winText(): string
			local prize = RoundPrize.For(
				"Speed",
				"",
				ReplicatedStorage:GetAttribute("PrizeJackpot") == true,
				1,
				RoundPrize.Stats(player),
				((player:GetAttribute("Charge_DoublePrize") or 0) :: number) > 0
			)
			return `{if prize.Kind == "Cash" then "💵" else "👟"} {prize.Text}`
		end
		if final == "Murderer" then
			-- Make the link obvious: this is the knife from YOUR vault, with its power
			local equipped = player:GetAttribute("FightingKnife")
			local parsed = if type(equipped) == "string" and equipped ~= "" then Items.Parse(equipped) else nil
			-- One job and what it wins (a 5-year-old reads one line): the knife picture says which knife
			hint = `GET EVERYONE! Win {winText()}`
			knifeImage = if parsed
				then (VoxelUi.Knives[parsed.Knife.Name] or KnifeIcons[parsed.Knife.Name] or "")
				else ""
		elseif final == "Sheriff" then
			hint = `SHOOT THE MURDERER! Win {winText()}`
		else
			hint = `SURVIVE! Win {winText()}`
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
	Ui.SpeedIcon = speedArt -- (the round prize's shoes fly into it: client/Transitions)
	local cashArt = Ui.art(stats, "Cash", { Image = CartoonArt.Cash })
	Ui.CashIcon = cashArt
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
			-- Steal An Egg keeps these small and tucked in: two short rows
			size = math.clamp(math.floor(bounds.Y * 0.085), 26, 44) -- big and chunky, like theirs
			icon, row = math.floor(size * 1.1), math.floor(size * 1.2)
			x = 25 + stick + 12 -- just right of the thumbstick
		end
		-- Speed over Cash
		local small = 0
		stats.Position, stats.Size = UDim2.new(0, x, 1, -12), UDim2.fromOffset(icon + 8 + size * 6, small + row * 2)
		speedArt.Position, speedArt.Size = UDim2.fromOffset(0, small + (row - icon) / 2), UDim2.fromOffset(icon, icon)
		cashArt.Position, cashArt.Size =
			UDim2.fromOffset(0, small + row + (row - icon) / 2), UDim2.fromOffset(icon, icon)
		speedLabel.Position, speedLabel.Size = UDim2.fromOffset(icon + 8, small), UDim2.fromOffset(size * 6, row)
		cashLabel.Position, cashLabel.Size = UDim2.fromOffset(icon + 8, small + row), UDim2.fromOffset(size * 6, row)
		speedLabel.TextSize, cashLabel.TextSize = math.floor(size * 0.9), size
	end
	Ui.Layout.Changed:Connect(placeStats)
	placeStats()
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
			healthFrame.Size = UDim2.fromOffset(healthWidth, 20)
		end
		-- The Murderer chance sits above the timer, so the timer is the lowest line up there and the
		-- view of the world (boss stashes, knife labels) stays clear
		-- (the tutorial's line runs across the very top while it's up: everything here moves under it)
		-- (and under a TopLine notice: zone titles, announcements - client/TopLine)
		-- Under the top line (and the tutorial's line above it): the Murderer chance, then the small
		-- lines (revenge / events / server goal)
		local top = (Ui.gui:GetAttribute("TopLineHeight") or 0) :: number
		if top == 0 and Ui.gui:GetAttribute("TutorialBar") == true then
			top = ((Ui.gui:GetAttribute("TutorialBarHeight") or 36) :: number) + 2
		elseif top == 0 and Ui.gui:GetAttribute("DoLine") == true and Ui.gui:GetAttribute("DoLineInStrip") ~= true then
			top = ((Ui.gui:GetAttribute("DoLineHeight") or 38) :: number) + 2
		end
		chanceLabel.Position, chanceLabel.Size = UDim2.fromOffset(center, top), UDim2.fromOffset(width, 20)
		local chanceStrip = Ui.topStrip("Chance")
		if chanceStrip then
			chanceLabel.Position = UDim2.fromOffset(chanceStrip.X, chanceStrip.Y)
			chanceLabel.Size = UDim2.fromOffset(chanceStrip.W, chanceStrip.H)
			chanceLabel.TextSize = 14
		end
		refreshChance()
		timerFrame.Position, timerFrame.Size = UDim2.fromOffset(center, top + 18), UDim2.fromOffset(width, 40)
		subLabel.Position, subLabel.Size = UDim2.fromOffset(center, top + 22), UDim2.fromOffset(width, 20)
		subLabel.TextWrapped = false
		Ui.gui:SetAttribute("HudTop", top) -- (under the top line: RoundIntro's rule line follows it)
		banner.Size = UDim2.fromOffset(math.min(600, bounds.X - 24), 44)
		announceHolder.Size = UDim2.fromOffset(math.min(480, bounds.X - 24), 60)
		if Ui.Phone then
			-- Between the left buttons and the right ones, under the timer: never mid-screen
			local lane = math.max(220, math.min(420, bounds.X - 2 * 150))
			-- Keep other messages below the tutorial and timer while the top strip is showing.
			local below = top
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
	Ui.gui:GetAttributeChangedSignal("TutorialBarHeight"):Connect(layout)
	Ui.gui:GetAttributeChangedSignal("TopLine"):Connect(layout)
	Ui.gui:GetAttributeChangedSignal("TopLineHeight"):Connect(layout)
	Ui.gui:GetAttributeChangedSignal("DoLine"):Connect(layout)
	layout()
	Ui.Menu.Changed:Connect(function()
		-- (toasts and announcements stay up with a menu open: they're how a click answers you)
		if Ui.menuOpen() then
			healthFrame.Visible = false
		else
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			healthFrame.Visible = hum ~= nil
				and hum.Health > 0
				and hum.Health < hum.MaxHealth
				and not player:GetAttribute("InRound")
		end
	end)
end

Hud.CashLabel = nil :: TextLabel?

return Hud
