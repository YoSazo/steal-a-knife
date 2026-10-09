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
local Favorite = require(script.Parent.Favorite)
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
		if Ui.menuOpen() then
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
	-- End-of-round VS card (MM2 style) --------------------------------------------------------------
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.55)
	card.Size = UDim2.fromOffset(560, 330)
	card.BackgroundColor3 = Color3.fromRGB(24, 18, 30)
	card.BackgroundTransparency = 0.08
	card.Visible = false
	card.ZIndex = 30
	card.Name = "RoundResults"
	Ui.TrackPresentation(card)
	card.Parent = Ui.root
	-- Shrink the WHOLE card to fit small screens (its panels are laid out in fixed sizes: resizing
	-- only the card left them hanging out of the bottom on a phone)
	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card
	local function fitCard()
		local menu = Ui.Layout.get().Menu
		cardScale.Scale = math.min(1, menu.X / 560, menu.Y / 340)
	end
	Ui.Layout.Changed:Connect(fitCard)
	fitCard()
	Ui.registerMenu(card)
	Ui.button(
		{ Name = "Close", Text = "X", Position = UDim2.new(1, -52, 0, 6), Size = UDim2.fromOffset(44, 44), ZIndex = 33 },
		card,
		function()
			card.Visible = false
		end
	)
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 16)
	cardCorner.Parent = card
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Thickness = 2
	cardStroke.Parent = card
	local cardTitle = label(card, {
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -80, 0, 38),
		ZIndex = 31,
	})
	label(card, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(70, 50),
		Text = "VS",
		ZIndex = 31,
	})
	local function side(x: number, role: string, color: Color3)
		local holder = Instance.new("Frame")
		holder.Position = UDim2.fromOffset(x, 54)
		holder.Size = UDim2.fromOffset(220, 216)
		holder.BackgroundColor3 = Color3.fromRGB(40, 32, 50)
		holder.ZIndex = 31
		holder.Parent = card
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = holder
		label(holder, {
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.new(1, -12, 0, 26),
			Text = role,
			TextColor3 = color,
			ZIndex = 32,
		})
		local photo = Instance.new("ImageLabel")
		photo.AnchorPoint = Vector2.new(0.5, 0)
		photo.Position = UDim2.new(0.5, 0, 0, 34)
		photo.Size = UDim2.fromOffset(96, 96)
		photo.BackgroundColor3 = Color3.fromRGB(60, 50, 70)
		photo.ZIndex = 32
		photo.Parent = holder
		local photoCorner = Instance.new("UICorner")
		photoCorner.CornerRadius = UDim.new(0.5, 0)
		photoCorner.Parent = photo
		local name = label(holder, {
			Position = UDim2.fromOffset(6, 134),
			Size = UDim2.new(1, -12, 0, 24),
			ZIndex = 32,
		})
		local detail = label(holder, {
			Position = UDim2.fromOffset(6, 158),
			Size = UDim2.new(1, -12, 0, 20),
			TextColor3 = Color3.fromRGB(220, 220, 230),
			ZIndex = 32,
		})
		-- Their power, big and gold: everyone sees where these two are at
		local power = label(holder, {
			Position = UDim2.fromOffset(6, 182),
			Size = UDim2.new(1, -12, 0, 26),
			TextColor3 = Color3.fromRGB(255, 215, 70),
			ZIndex = 32,
		})
		return photo, name, detail, power
	end
	-- Your own result, the biggest line on the card: "YOU WON! +12K 👟" / "+1.2K 👟 banked"
	local yours = label(card, {
		Name = "YourResult",
		Position = UDim2.fromOffset(12, 278),
		Size = UDim2.new(1, -24, 0, 44),
		ZIndex = 31,
	})
	local mPhoto, mName, mDetail, mPower = side(14, "MURDERER", Color3.fromRGB(255, 70, 80))
	local hPhoto, hName, hDetail, hPower = side(326, "SHERIFF", Color3.fromRGB(90, 170, 255))
	local cardToken = 0
	local function setPhoto(image: ImageLabel, userId: number, face: any?)
		image.Image = ""
		image.BackgroundColor3 = Color3.fromRGB(60, 50, 70)
		-- A bot: its disguise's face drawn on its skin colour
		if userId <= 0 and type(face) == "table" then
			image.BackgroundColor3 = if typeof(face.Skin) == "Color3" then face.Skin else Color3.fromRGB(230, 190, 150)
			image.Image = if type(face.Face) == "string" then face.Face else ""
			return
		end
		if userId > 0 then
			task.spawn(function()
				local ok, url = pcall(
					Players.GetUserThumbnailAsync,
					Players,
					userId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size150x150
				)
				if ok then
					image.Image = url
				end
			end)
		end
	end
	local function showCard(info: { [string]: any })
		cardToken += 1
		local token = cardToken
		local murdererWon = info.Won == "Murderer"
		cardTitle.Text = tostring(info.Title or "")
		cardTitle.TextColor3 = if murdererWon then Color3.fromRGB(255, 80, 90) else Color3.fromRGB(110, 200, 255)
		cardStroke.Color = cardTitle.TextColor3
		mName.Text = tostring(info.MurdererName or "?")
		local knife = if type(info.Knife) == "string" then info.Knife else ""
		mDetail.Text = `{if knife ~= "" then Items.DisplayName(knife) else "Knife"} · {info.Kills or 0} kills`
		mDetail.TextColor3 = if knife ~= "" then Items.Color(knife) else Color3.new(1, 1, 1)
		setPhoto(mPhoto, tonumber(info.MurdererId) or 0, info.MurdererFace)
		-- (no Murderer powers any more: the card shows the knife they flexed, not a power line)
		mPower.Visible = false
		if info.SheriffName then
			-- The Sheriff, whether or not they got the shot
			hName.Text = tostring(info.SheriffName)
			hDetail.Text = `Revolver · {info.SheriffStatus or ""}`
			setPhoto(hPhoto, tonumber(info.SheriffId) or tonumber(info.HeroId) or 0, info.HeroFace)
		else
			hName.Text = if murdererWon then "Nobody stopped them" else "Survived!"
			hDetail.Text = if murdererWon then "" else "The innocents made it"
			setPhoto(hPhoto, tonumber(info.HeroId) or 0, info.HeroFace)
		end
		hPower.Text = ""
		local speed = tonumber(info.YourSpeed) or 0
		local gain = if speed > 0 then ` +{Format.Short(speed)} 👟` else ""
		yours.Text = if info.YouWon == true then `YOU WON!{gain}` elseif speed > 0 then `{gain} banked` else ""
		yours.TextColor3 = if info.YouWon == true then Color3.fromRGB(120, 255, 140) else Color3.fromRGB(120, 200, 255)
		card.Visible = true
		local scale = card:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Parent = card
		scale.Scale = 0.7
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		task.delay(6, function()
			if token == cardToken then
				card.Visible = false
			end
		end)
	end

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
	kill.BackgroundTransparency = 0.1
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
		prizeCard.BackgroundTransparency = 0.1
		prizeCard.ZIndex = 45
		prizeCard.Parent = Ui.root
		local jingle = Instance.new("Sound")
		jingle.SoundId = Sounds.Win
		jingle.Volume = 0.5
		jingle.Parent = workspace.CurrentCamera
		jingle:Play()
		Debris:AddItem(jingle, 6)
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
			-- the round is over: the VS card takes the middle, the death card makes way
			killToken += 1
			kill.Visible = false
			if type(text) == "table" then
				showCard(text)
				-- The payoff, big, once you're home (every role): "🎉 You won the murder round!
				-- +12K 👟" with the shoe shower into the Speed readout
				local speed = tonumber(text.YourSpeed) or 0
				if speed > 0 then
					local won = text.YouWon == true
					task.spawn(function()
						local started = os.clock()
						task.wait(6.2) -- (the VS card's time)
						while
							(player:GetAttribute("InRound") or Ui.gui:GetAttribute("FadeCover"))
							and os.clock() - started < 25
						do
							task.wait(0.2)
						end
						task.wait(0.6)
						queueCard(4.8, function()
							showPrize(
								`+{Format.Short(speed)} 👟 Speed`,
								"Speed",
								nil,
								false,
								if won then "🎉 You won the murder round!" else "👟 Your Speed from the round"
							)
						end)
					end)
				end
				-- you won it: the best moment of the first visit to ask for a favourite (once ever)
				local murdererWon = text.Won == "Murderer"
				local mine = tonumber(text.MurdererId) == Players.LocalPlayer.UserId
				if murdererWon == mine then
					task.delay(6.5, Favorite.Ask, if mine then "murderer_win" else "round_win", function()
						task.delay(3, GiftCard.Offer)
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
