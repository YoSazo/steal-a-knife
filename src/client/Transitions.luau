--!strict
-- Two simple on-screen moments, Steal An Egg style:
--  * Zone titles: walking into a zone pops its name up at the top of the screen for a moment
--    (there are no signs in the world), with a red "needs X speed" line if you're too slow for it.
--  * Round fades: the server fires Effect "Fade" just before teleporting you into a round or back
--    home; the screen fades to black with where you're going, then fades back in once you're there.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Format = require(ReplicatedStorage.Shared.Format)
local Items = require(ReplicatedStorage.Shared.Items)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local CartoonArt = require(ReplicatedStorage.Shared.Config.CartoonArt)

local Ui = require(script.Parent.Ui)
local TopLine = require(script.Parent.TopLine)
local GiftCard = require(script.Parent.GiftCard)
local KnifeIcons = require(ReplicatedStorage.Shared.Config.KnifeIcons)
local VoxelKnives = require(ReplicatedStorage.Shared.Config.VoxelUi).Knives :: { [string]: string }
local Transitions = {}

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local ZONE_EMOJI: { [string]: string } = {
	Common = "🌳",
	Rare = "🌸",
	Epic = "💀",
	Legendary = "⚱️",
	Mythic = "🔥",
	Godly = "⚡",
	Celestial = "👼",
	Cosmic = "🪐",
}

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	for key, value in props do
		(text :: any)[key] = value
	end
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(20, 20, 40)
	stroke.Parent = text
	text.Parent = parent
	return text
end

function Transitions.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Transitions"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Zone title ----------------------------------------------------------------------------------
	-- On the top line (client/TopLine), like the tutorial: "Gardens 🌸 · Needs 4K speed" - it was a
	-- big title under the timer, over the middle of the screen
	local function showZone(index: number)
		if
			Ui.menuOpen()
			or player:GetAttribute("Carrying")
			or player:GetAttribute("RunSaved")
			or player:GetAttribute("InRound")
		then
			return
		end
		local zone = GameConfig.Zones[index] :: any
		local tint = (zone.Color :: Color3):Lerp(Color3.new(1, 1, 1), 0.35)
		-- The monster, not the biome (a kid is after the monster; the biome name cut the line off at
		-- phone width): "🔥 LAVA SALAMANDER · Needs 950M 👟"
		local text = `<font color="#{tint:ToHex()}"><b>{ZONE_EMOJI[zone.Rarity] or ""} {string.upper(
			GameConfig.MonsterName(index)
		)}</b></font>`
		local need = zone.SpeedNeeded or 0
		local speed = (player:GetAttribute("Speed") or 0) :: number
		if need > speed then
			text ..= ` · <font color="#FF6E6E">Needs {Format.Short(need)} 👟</font>`
		end
		TopLine.Show(text, 2.2, "Zone")
	end
	local lastZone = 0
	task.spawn(function()
		while true do
			task.wait(0.25)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local zone = 0
			if root and not player:GetAttribute("InRound") then
				local pos = root.Position
				if math.abs(pos.X) <= GameConfig.ArenaWidth / 2 and pos.Z >= 0 then
					zone = GameConfig.ZoneAtZ(pos.Z) or #GameConfig.Zones
				end
			end
			if zone ~= lastZone and zone > 0 then
				showZone(zone)
			end
			lastZone = zone
		end
	end)

	-- Round fade ----------------------------------------------------------------------------------
	local cover = Instance.new("Frame")
	cover.Size = UDim2.fromScale(1, 1)
	cover.BackgroundColor3 = Color3.fromRGB(12, 10, 20)
	cover.BackgroundTransparency = 1
	cover.Visible = false
	cover.ZIndex = 10
	cover.Parent = gui
	local where = label(cover, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.1),
		TextTransparency = 1,
		ZIndex = 11,
	})

	local fadeToken = 0
	-- The kill card: who got you, with what, and where that knife comes from - the "I need that"
	-- moment (right after dying in a round)
	local kill = Instance.new("Frame")
	kill.Name = "KillCard"
	Ui.TrackPresentation(kill)
	kill.AnchorPoint = Vector2.new(0.5, 0.5)
	kill.Position = UDim2.fromScale(0.5, 0.45)
	kill.Size = UDim2.fromOffset(480, 260)
	kill.BackgroundColor3 = Color3.fromRGB(22, 16, 28)
	kill.BackgroundTransparency = 0
	kill.Visible = false
	kill.ZIndex = 40
	kill.Parent = Ui.root
	Instance.new("UICorner", kill).CornerRadius = UDim.new(0, 16)
	local killStroke = Instance.new("UIStroke")
	killStroke.Color, killStroke.Thickness = Color3.fromRGB(255, 60, 70), 3
	killStroke.Parent = kill
	local killTitle = label(kill, {
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -24, 0, 34),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 90, 100),
		ZIndex = 41,
	})
	local killWhere = label(kill, {
		Position = UDim2.fromOffset(12, 196),
		Size = UDim2.new(1, -24, 0, 40),
		TextColor3 = Color3.fromRGB(140, 240, 150),
		TextWrapped = true,
		ZIndex = 41,
	})
	-- The death card, in plain words: the Murderer got you, and your knives are always safe
	-- The Speed prize's payoff: ~30 shoes burst out of the "You won!" card and fly into the Speed
	-- shoe at the bottom left (Ui.SpeedIcon), which pops with every one that lands
	local function shoeShower(fromCard: GuiObject, cash: boolean?, amount: number?)
		local target = (if cash then Ui.CashIcon else Ui.SpeedIcon) :: GuiObject?
		if not target or not target.Parent or not fromCard.Parent or not target.Visible then
			return -- (a hidden readout: shoes flying into nothing)
		end
		Ui.LastFlyIn[if cash then "Cash" else "Speed"] = os.clock()
		local root = Ui.root
		local scale = math.max(Ui.Scale.Scale, 0.01)
		local function local_(at: Vector2): UDim2
			local p = (at - root.AbsolutePosition) / scale
			return UDim2.fromOffset(p.X, p.Y)
		end
		local from = fromCard.AbsolutePosition + fromCard.AbsoluteSize / 2
		local to = target.AbsolutePosition + target.AbsoluteSize / 2
		local size = math.clamp(target.AbsoluteSize.X / scale * 0.8, 28, 44)
		local bump = target:FindFirstChild("ShoeBump") :: UIScale? or Instance.new("UIScale")
		bump.Name = "ShoeBump"
		bump.Parent = target
		local count = amount or 30
		for i = 1, count do
			local shoe = Instance.new("ImageLabel")
			shoe.Name = "PrizeShoe"
			shoe.BackgroundTransparency = 1
			shoe.Image = if cash then CartoonArt.Cash else CartoonArt.Speed
			shoe.ScaleType = Enum.ScaleType.Fit
			shoe.AnchorPoint = Vector2.new(0.5, 0.5)
			shoe.Size = UDim2.fromOffset(size, size)
			shoe.Rotation = math.random(-30, 30)
			shoe.ZIndex = 60
			-- burst out of the card in a ring, then swoop down into the readout
			local angle = math.random() * math.pi * 2
			local spread = Vector2.new(math.cos(angle), math.sin(angle)) * math.random(40, 150) * scale
			shoe.Position = local_(from)
			shoe.Parent = root
			task.delay((i - 1) * 0.03, function()
				TweenService:Create(
					shoe,
					TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Position = local_(from + spread), Rotation = shoe.Rotation * 2 }
				):Play()
				task.wait(0.28 + math.random() * 0.15)
				local fly = TweenService:Create(
					shoe,
					TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Position = local_(to), Size = UDim2.fromOffset(size * 0.55, size * 0.55), Rotation = 0 }
				)
				fly:Play()
				fly.Completed:Wait()
				shoe:Destroy()
				bump.Scale = 1.25
				TweenService:Create(bump, TweenInfo.new(0.12), { Scale = 1 }):Play()
				-- one "got it" when the first shoe lands (it was a coin clink every third shoe)
				if i == 1 then
					local got = Instance.new("Sound")
					got.SoundId = Sounds.PrizeLand
					got.Volume = 0.5
					got.Parent = workspace.CurrentCamera
					got:Play()
					Debris:AddItem(got, 4)
				end
			end)
		end
	end

	-- Anything else that adds Speed / Cash flies in from where it happened (Ui.FlyIn)
	Ui.FlyIn = function(cash: boolean, at: Vector2?, count: number?)
		local root = Ui.root
		local scale = math.max(Ui.Scale.Scale, 0.01)
		local screen = at or (root.AbsolutePosition + root.AbsoluteSize / 2)
		local p = (screen - root.AbsolutePosition) / scale
		local source = Ui.new("Frame", {
			Size = UDim2.fromOffset(1, 1),
			Position = UDim2.fromOffset(p.X, p.Y),
			BackgroundTransparency = 1,
		}, root)
		shoeShower(source, cash, count or 8)
		Debris:AddItem(source, 2)
	end

	-- The round prize, paid once you're home: "You won! +$4.2M" (a knife shows its picture)
	local function showPrize(text: string, kind: unknown, knife: unknown, jackpot: boolean, title: string?)
		local prizeCard = Instance.new("Frame")
		prizeCard.Name = "PrizeWon"
		Ui.TrackPresentation(prizeCard)
		prizeCard.AnchorPoint = Vector2.new(0.5, 0.5)
		prizeCard.Position = UDim2.fromScale(0.5, 0.4)
		prizeCard.Size = UDim2.fromOffset(440, if type(knife) == "string" then 260 else 150)
		prizeCard.BackgroundColor3 = Color3.fromRGB(22, 16, 28)
		prizeCard.BackgroundTransparency = 0
		prizeCard.ZIndex = 45
		prizeCard.Parent = Ui.root
		Instance.new("UICorner", prizeCard).CornerRadius = UDim.new(0, 18)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 4
		stroke.Color = Color3.fromRGB(255, 205, 60)
		stroke.Parent = prizeCard
		label(prizeCard, {
			Position = UDim2.fromOffset(16, 12),
			Size = UDim2.new(1, -32, 0, 48),
			Text = title
				or (if jackpot then "⭐ JACKPOT! You won the murder round! ⭐" else "🎉 You won the murder round!"),
			TextColor3 = Color3.fromRGB(255, 215, 70),
			ZIndex = 46,
		})
		if type(knife) == "string" then
			local parsed = Items.Parse(knife)
			Ui.art(prizeCard, "", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 64),
				Size = UDim2.fromOffset(120, 120),
				Image = if parsed then (VoxelKnives[parsed.Name] or KnifeIcons[parsed.Name] or "") else "",
				ZIndex = 46,
			})
		end
		label(prizeCard, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 16, 1, -16),
			Size = UDim2.new(1, -32, 0, 56),
			Text = text,
			TextWrapped = true,
			TextColor3 = if kind == "Speed" then Color3.fromRGB(120, 200, 255) else Color3.fromRGB(120, 255, 140),
			ZIndex = 46,
		})
		local pop = Instance.new("UIScale")
		pop.Scale = 0.6
		pop.Parent = prizeCard
		TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		if kind == "Speed" or kind == "Cash" then
			task.delay(0.9, shoeShower, prizeCard, kind == "Cash")
		end
		task.delay(4.5, function()
			TweenService:Create(pop, TweenInfo.new(0.2), { Scale = 0.8 }):Play()
			task.wait(0.2)
			prizeCard:Destroy()
		end)
	end

	-- The end-of-round cards take turns in the middle of the screen: a winning Murderer gets their
	-- haul ("You stole 3 knives!") AND the prize ("You won! +1.1K Speed") a second apart, and the two
	-- sat on top of each other. Each waits until the one before has gone. `seconds` = how long it shows.
	local cardFreeAt = 0
	local function queueCard(seconds: number, show: () -> ())
		local now = os.clock()
		local start = math.max(now, cardFreeAt)
		cardFreeAt = start + seconds
		task.delay(start - now, show)
	end

	local killToken = 0
	local function showKill(info: any)
		killToken += 1
		local token = killToken
		killTitle.Text = "Killed by"
		local item = if type(info) == "table" and type(info.Knife) == "string" then info.Knife else ""
		killWhere.Text = if Items.Parse(item) then Items.DisplayName(item) else "The Murderer"
		killWhere.TextColor3 = if Items.Parse(item) then Items.Color(item) else Color3.fromRGB(255, 90, 100)
		killWhere.Position = UDim2.fromOffset(12, 64) -- (inside the short card)
		kill.Size = UDim2.fromOffset(480, 120)
		kill.Visible = true
		local scale = kill:FindFirstChild("Pop") :: UIScale? or Instance.new("UIScale")
		scale.Name = "Pop"
		scale.Parent = kill
		-- (fits a short phone screen: the knife card is 300 tall, a 640x300 screen cut its button off)
		local screen = workspace.CurrentCamera.ViewportSize
		local fit = math.min(1, (screen.Y - 40) / kill.Size.Y.Offset, (screen.X - 40) / kill.Size.X.Offset)
		scale.Scale = 0.7 * fit
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = fit }):Play()
		task.delay(4, function()
			if token == killToken then
				kill.Visible = false
			end
		end)
	end

	-- Fast enough for the next monster (from a round, a delivery, a code, a Robux pack - anything):
	-- the big card, once you're home and nothing else is on screen. "Steal from the FLOWER TOAD!"
	local function zoneReached(speed: number): number?
		local reached: number? = nil
		for i, zone in GameConfig.Zones :: { any } do
			if i > 1 and speed >= ((zone.SpeedNeeded or 0) :: number) then
				reached = i
			end
		end
		return reached
	end
	local speedSeen: number? = nil
	local unlockShown: number? = nil
	local unlockWaiting = false
	player:GetAttributeChangedSignal("Speed"):Connect(function()
		local speed = (player:GetAttribute("Speed") or 0) :: number
		if speedSeen == nil then
			speedSeen = speed -- (the saved Speed arriving on join is not an unlock)
			unlockShown = zoneReached(speed)
			return
		end
		speedSeen = speed
		local reached = zoneReached(speed)
		if not reached or (unlockShown and reached <= unlockShown) then
			unlockShown = reached -- (a rebirth resets Speed: the climb shows again)
			return
		end
		if unlockWaiting then
			return
		end
		unlockWaiting = true
		task.spawn(function()
			while
				player:GetAttribute("InRound")
				or player:GetAttribute("Carrying")
				or player:GetAttribute("RunSaved")
				or Ui.gui:GetAttribute("FadeCover")
			do
				task.wait(0.3)
			end
			task.wait(1.5)
			unlockWaiting = false
			local now = zoneReached((player:GetAttribute("Speed") or 0) :: number)
			if not now or (unlockShown and now <= unlockShown) then
				return
			end
			unlockShown = now
			queueCard(4.5, function()
				showPrize(
					`Steal from the {string.upper(GameConfig.MonsterName(now))}!`,
					"Unlock",
					nil,
					false,
					"🏃 YOU'RE FAST ENOUGH!"
				)
			end)
		end)
	end)
	if player:GetAttribute("Speed") ~= nil then
		local saved = (player:GetAttribute("Speed") or 0) :: number
		speedSeen = saved
		unlockShown = zoneReached(saved)
	end

	Remotes:WaitForChild("Effect").OnClientEvent:Connect(function(kind: string, text: any, extra: any, ...)
		if kind == "SpeedBank" and type(text) == "number" then
			local source = Ui.new(
				"Frame",
				{ Size = UDim2.fromOffset(1, 1), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1 },
				Ui.root
			)
			shoeShower(source, false, 6)
			local pop = label(source, {
				Size = UDim2.fromOffset(300, 56),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Text = `+{Ui.abbreviate(text)} 👟`,
				TextSize = 44,
				TextScaled = false,
				TextColor3 = Color3.fromRGB(120, 200, 255),
				ZIndex = 61,
			})
			-- (solid while you read it, then text and outline fade together: fading only the
			-- letters left a hollow ghost outline)
			TweenService:Create(pop, TweenInfo.new(1.6), { Position = UDim2.fromOffset(0, -50) }):Play()
			task.delay(1.1, function()
				local fade = TweenInfo.new(0.4)
				TweenService:Create(pop, fade, { TextTransparency = 1 }):Play()
				local outline = pop:FindFirstChildOfClass("UIStroke")
				if outline then
					TweenService:Create(outline, fade, { Transparency = 1 }):Play()
				end
			end)
			Debris:AddItem(source, 2)
			return
		end
		if kind == "KillCard" then
			showKill(text)
			return
		end
		if kind == "RoundCard" then
			-- Only the outcome text remains at round end; clear an older death card.
			killToken += 1
			kill.Visible = false
			if type(text) == "table" then
				local outcome = if text.Won == "Murderer" then "MURDERER WINS!" else "INNOCENTS WIN!"
				if not player:GetAttribute("RunSaved") and not player:GetAttribute("Carrying") then
					TopLine.Show(outcome, 5.5, "RoundOutcome")
				end
				if (tonumber(text.YourSpeed) or 0) > 0 and not player:GetAttribute("RunSaved") then
					task.delay(0.8, function()
						if Ui.FlyIn then
							Ui.FlyIn(false, nil, 12)
						end
					end)
				end
				-- you won it: the best moment of the first visit to ask for a favourite (once ever)
				local murdererWon = text.Won == "Murderer"
				local mine = tonumber(text.MurdererId) == Players.LocalPlayer.UserId
				if murdererWon == mine then
					task.spawn(function()
						task.wait(6.5)
						while
							player:GetAttribute("Carrying")
							or player:GetAttribute("RunSaved")
							or player:GetAttribute("InRound")
						do
							task.wait(0.3)
						end
						GiftCard.Offer()
					end)
				end
			end
			return
		end
		if kind == "PrizeWon" then
			if type(text) == "string" then
				local args = { ... }
				queueCard(4.8, function()
					showPrize(text, extra, args[1], args[2] == true)
				end)
			end
			return
		end
		if kind ~= "Fade" then
			return
		end
		fadeToken += 1
		local token = fadeToken
		local wasInRound = player:GetAttribute("InRound") == true
		cover.Visible = true
		Ui.gui:SetAttribute("FadeCover", true) -- (the role reel waits for this to clear)
		where.Text = if type(text) == "string" then text else ""
		local stroke = where:FindFirstChildOfClass("UIStroke") :: UIStroke
		TweenService:Create(cover, TweenInfo.new(0.3), { BackgroundTransparency = 0 }):Play()
		TweenService:Create(where, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 0 }):Play()
		-- Hold until we've actually moved (InRound flips), then a beat for the camera and streaming
		local start = os.clock()
		while
			token == fadeToken
			and (player:GetAttribute("InRound") == true) == wasInRound
			and os.clock() - start < 6
		do
			task.wait()
		end
		task.wait(0.6)
		if token ~= fadeToken then
			return
		end
		TweenService:Create(cover, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(where, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		task.delay(0.65, function()
			if token == fadeToken then
				cover.Visible = false
				Ui.gui:SetAttribute("FadeCover", false)
			end
		end)
	end)
end

return Transitions
