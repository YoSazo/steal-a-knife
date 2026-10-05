--!strict
-- Two simple on-screen moments, Steal An Egg style:
--  * Zone titles: walking into a zone pops its name up at the top of the screen for a moment
--    (there are no signs in the world), with a red "needs X speed" line if you're too slow for it.
--  * Round fades: the server fires Effect "Fade" just before teleporting you into a round or back
--    home; the screen fades to black with where you're going, then fades back in once you're there.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Format = require(ReplicatedStorage.Shared.Format)
local Items = require(ReplicatedStorage.Shared.Items)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)

local Ui = require(script.Parent.Ui)
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
	local banner = Instance.new("Frame")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	-- Just under the Murderer chance + round timer (they end ~64px down), big
	banner.Position = UDim2.new(0.5, 0, 0, 78)
	banner.Size = UDim2.new(0.6, 0, 0, 120)
	banner.BackgroundTransparency = 1
	banner.Visible = false
	banner.Parent = Ui.root
	banner.ZIndex = 3
	local title = label(banner, { Size = UDim2.fromScale(1, 0.68) })
	local subtitle = label(banner, {
		Position = UDim2.fromScale(0, 0.68),
		Size = UDim2.fromScale(1, 0.32),
		TextColor3 = Color3.fromRGB(255, 90, 90),
	})
	local bannerToken = 0
	if Ui.Phone then
		local function fitZone()
			local _, bounds = Ui.bounds()
			banner.Position = UDim2.new(0.5, 0, 0, 70)
			banner.Size = UDim2.fromOffset(math.min(620, math.max(300, bounds.X - 300)), 80)
		end
		Ui.Layout.Changed:Connect(fitZone)
		fitZone()
		title.Size = UDim2.new(1, 0, 0, 52)
		subtitle.Position, subtitle.Size = UDim2.fromOffset(0, 54), UDim2.new(1, 0, 0, 24)
		for _, text in { title, subtitle } do
			text.TextScaled, text.TextTruncate = false, Enum.TextTruncate.AtEnd
		end
		title.TextSize, subtitle.TextSize = 46, 20
	end
	Ui.Menu.Changed:Connect(function()
		if Ui.menuOpen() then
			bannerToken += 1
			banner.Visible = false
			Ui.gui:SetAttribute("ZoneNotice", false)
		end
	end)
	local function showZone(index: number)
		if Ui.menuOpen() then
			return
		end
		local zone = GameConfig.Zones[index] :: any
		title.Text = `{zone.Title or zone.Rarity} {ZONE_EMOJI[zone.Rarity] or ""}`
		title.TextColor3 = zone.Color:Lerp(Color3.new(1, 1, 1), 0.35)
		local need = zone.SpeedNeeded or 0
		local speed = (player:GetAttribute("Speed") or 0) :: number
		subtitle.Text = if need > speed
			then (if Ui.Phone
				then `Needs {Format.Short(need)} speed`
				else `Needs {Format.Short(need)} speed to outrun the boss!`)
			else ""
		bannerToken += 1
		local token = bannerToken
		banner.Visible = true
		Ui.gui:SetAttribute("ZoneTitle", true) -- (the tutorial line steps aside meanwhile)
		for _, text in { title, subtitle } do
			text.TextTransparency = 0
			local stroke = text:FindFirstChildOfClass("UIStroke") :: UIStroke
			stroke.Transparency = 0
		end
		-- (below the timer now, so the timer stays up)
		local rest = UDim2.new(0.5, 0, 0, if Ui.Phone then 70 else 78)
		banner.Position = rest - UDim2.fromOffset(0, 16)
		TweenService:Create(banner, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Position = rest }):Play()
		task.delay(1.8, function()
			if token ~= bannerToken then
				return
			end
			for _, text in { title, subtitle } do
				TweenService:Create(text, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
				TweenService:Create(text:FindFirstChildOfClass("UIStroke") :: UIStroke, TweenInfo.new(0.5), {
					Transparency = 1,
				}):Play()
			end
		end)
		task.delay(2.3, function()
			if token == bannerToken then
				banner.Visible = false
				Ui.gui:SetAttribute("ZoneNotice", false)
				Ui.gui:SetAttribute("ZoneTitle", false)
			end
		end)
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
					zone = math.clamp(math.floor(pos.Z / GameConfig.ZoneDepth) + 1, 1, #GameConfig.Zones)
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
	-- At-risk reel ---------------------------------------------------------------------------------
	-- At the start of a round a reel of your knives spins and lands on the one the Murderer takes if
	-- they get you; then it shrinks to a reminder in the corner for the rest of the round.
	local riskPanel = Instance.new("Frame")
	riskPanel.AnchorPoint = Vector2.new(0.5, 0)
	riskPanel.Position = UDim2.fromScale(0.5, 0.6)
	riskPanel.Size = UDim2.fromOffset(560, 150)
	riskPanel.BackgroundColor3 = Color3.fromRGB(24, 18, 30)
	riskPanel.BackgroundTransparency = 0.1
	riskPanel.Visible = false
	riskPanel.ZIndex = 20
	riskPanel.Parent = gui
	local riskCorner = Instance.new("UICorner")
	riskCorner.CornerRadius = UDim.new(0, 16)
	riskCorner.Parent = riskPanel
	local riskStroke = Instance.new("UIStroke")
	riskStroke.Thickness = 4
	riskStroke.Color = Color3.fromRGB(255, 80, 90)
	riskStroke.Parent = riskPanel
	label(riskPanel, {
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 30),
		Text = "IF THE MURDERER GETS YOU, THEY TAKE...",
		TextColor3 = Color3.fromRGB(255, 110, 110),
		ZIndex = 21,
	})
	local window = Instance.new("Frame")
	window.Position = UDim2.fromOffset(10, 42)
	window.Size = UDim2.new(1, -20, 0, 70)
	window.BackgroundColor3 = Color3.fromRGB(12, 10, 16)
	window.ClipsDescendants = true
	window.ZIndex = 21
	window.Parent = riskPanel
	local strip = Instance.new("Frame")
	strip.BackgroundTransparency = 1
	strip.Size = UDim2.fromScale(0, 1)
	strip.ZIndex = 22
	strip.Parent = window
	local pointer = Instance.new("Frame")
	pointer.AnchorPoint = Vector2.new(0.5, 0)
	pointer.Position = UDim2.fromScale(0.5, 0)
	pointer.Size = UDim2.new(0, 4, 1, 0)
	pointer.BackgroundColor3 = Color3.fromRGB(255, 220, 60)
	pointer.BorderSizePixel = 0
	pointer.ZIndex = 25
	pointer.Parent = window
	local riskHint = label(riskPanel, {
		Position = UDim2.fromOffset(10, 118),
		Size = UDim2.new(1, -20, 0, 24),
		Text = "",
		TextColor3 = Color3.fromRGB(230, 230, 240),
		ZIndex = 21,
	})
	local badge = label(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.fromOffset(320, 24),
		Text = "",
		Visible = false,
		ZIndex = 3,
	})
	local riskIcon = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.fromOffset(-32, 0),
		Visible = false,
		ZIndex = 20,
	}, badge)
	if Ui.Phone then
		badge.Name = "AtRisk"
		badge.Parent = Ui.root
		badge.TextScaled = false
		badge.TextSize = 14
		badge.TextTruncate = Enum.TextTruncate.AtEnd
		badge.BackgroundTransparency = 0.15
		badge.BackgroundColor3 = Ui.PANEL
		Ui.corner(badge, 8)
	end
	local TILE = 150
	local riskToken = 0
	local riskActive = false
	Ui.Menu.Changed:Connect(function()
		badge.Visible = riskActive and player:GetAttribute("InRound") == true and not Ui.menuOpen()
	end)
	Ui.Layout.Changed:Connect(function()
		if Ui.Phone then
			local _, bounds = Ui.bounds()
			badge.Size = UDim2.fromOffset(math.min(320, bounds.X * 0.5), 28)
		end
	end)
	local function tile(item: string, index: number)
		local parsed = Items.Parse(item)
		local frame = Instance.new("Frame")
		frame.Position = UDim2.fromOffset((index - 1) * TILE, 0)
		frame.Size = UDim2.new(0, TILE - 6, 1, 0)
		frame.BackgroundColor3 = Items.Color(item):Lerp(Color3.fromRGB(20, 16, 26), 0.75)
		frame.ZIndex = 22
		frame.Parent = strip
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = frame
		label(frame, {
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.new(1, -12, 0.55, 0),
			Text = Items.DisplayName(item),
			TextColor3 = Items.Color(item),
			ZIndex = 23,
		})
		label(frame, {
			Position = UDim2.new(0, 6, 0.6, 0),
			Size = UDim2.new(1, -12, 0.32, 0),
			Text = if parsed then parsed.Knife.Rarity else "",
			TextColor3 = if parsed then Knives.RarityColors[parsed.Knife.Rarity] else Color3.new(1, 1, 1),
			ZIndex = 23,
		})
	end
	local function showRisk(choices: { string }, chosen: string)
		riskActive = true
		riskToken += 1
		local token = riskToken
		if Ui.Phone then
			local parsed = Items.Parse(chosen)
			badge.Text = `At risk: {Items.DisplayName(chosen)}`
			badge.TextColor3 = Items.Color(chosen)
			local _, bounds = Ui.bounds()
			badge.Size = UDim2.fromOffset(math.min(320, bounds.X * 0.5), 28)
			badge.Position = UDim2.new(0.5, 0, 0, 90)
			riskIcon.Image = if parsed
				then VoxelKnives[parsed.Knife.Name] or KnifeIcons[parsed.Knife.Name] or ""
				else ""
			riskIcon.Visible = true
			badge.Visible = player:GetAttribute("InRound") == true and not Ui.menuOpen()
			return
		end
		strip:ClearAllChildren()
		local count = 34
		local landAt = count - 3
		for i = 1, count do
			tile(if i == landAt then chosen else choices[math.random(1, #choices)], i)
		end
		strip.Size = UDim2.new(0, count * TILE, 1, 0)
		strip.Position = UDim2.fromOffset(0, 0)
		riskHint.Text = ""
		badge.Visible = false
		task.wait(1.4) -- after the fade and the role reveal
		if token ~= riskToken or not player:GetAttribute("InRound") then
			return
		end
		riskPanel.Visible = true
		local centre = window.AbsoluteSize.X / 2 - (TILE - 6) / 2
		local target = -((landAt - 1) * TILE) + centre + math.random(-30, 30)
		local spin = TweenService:Create(strip, TweenInfo.new(3.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(target, 0),
		})
		spin:Play()
		spin.Completed:Wait()
		if token ~= riskToken then
			return
		end
		riskHint.Text = `Survive - or shoot the Murderer - to keep your {Items.DisplayName(chosen)}!`
		task.wait(3)
		if token ~= riskToken then
			return
		end
		riskPanel.Visible = false
		if player:GetAttribute("InRound") then
			badge.Text = `⚠ At risk: {Items.DisplayName(chosen)}`
			badge.TextColor3 = Items.Color(chosen)
			badge.Visible = true
		end
	end
	player:GetAttributeChangedSignal("InRound"):Connect(function()
		if not player:GetAttribute("InRound") then
			riskActive = false
			riskToken += 1
			riskPanel.Visible = false
			badge.Visible = false
		end
	end)

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.Died:Connect(function()
			riskActive = false
			riskToken += 1
			badge.Visible = false
			riskPanel.Visible = false
		end)
	end)
	if player.Character then
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				riskActive = false
				riskToken += 1
				badge.Visible = false
				riskPanel.Visible = false
			end)
		end
	end

	-- End-of-round VS card (MM2 style) --------------------------------------------------------------
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.55)
	card.Size = UDim2.fromOffset(560, 280)
	card.BackgroundColor3 = Color3.fromRGB(24, 18, 30)
	card.BackgroundTransparency = 0.08
	card.Visible = false
	card.ZIndex = 30
	card.Name = "RoundResults"
	card.Parent = Ui.root
	Ui.fitMenu(card, Vector2.new(560, 290))
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
		cardTitle.Text = (if info.Classic then "CLASSIC · " else "") .. tostring(info.Title or "")
		cardTitle.TextColor3 = if murdererWon then Color3.fromRGB(255, 80, 90) else Color3.fromRGB(110, 200, 255)
		cardStroke.Color = cardTitle.TextColor3
		mName.Text = tostring(info.MurdererName or "?")
		local knife = if type(info.Knife) == "string" then info.Knife else ""
		mDetail.Text = `{if knife ~= "" then Items.DisplayName(knife) else "Knife"} · {info.Kills or 0} kills`
		mDetail.TextColor3 = if knife ~= "" then Items.Color(knife) else Color3.new(1, 1, 1)
		setPhoto(mPhoto, tonumber(info.MurdererId) or 0, info.MurdererFace)
		mPower.Text = if type(info.MurdererPower) == "string" then `⚡ {info.MurdererPower}` else "No power"
		mPower.TextColor3 = if info.MurdererPower then Color3.fromRGB(255, 215, 70) else Color3.fromRGB(160, 160, 175)
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
		hPower.Text = if type(info.SheriffPower) == "string" then `✨ {info.SheriffPower}` else ""
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
	-- "THE MURDERER HAS SPAM KNIFE": the first time the Murderer's power shows itself. It names the
	-- power, never the player. Everyone in the round (and anyone spectating) sees it.
	local reveal = Instance.new("Frame")
	reveal.Name = "PowerReveal"
	reveal.AnchorPoint = Vector2.new(0.5, 0)
	reveal.Position = UDim2.fromScale(0.5, 0.2)
	reveal.Size = UDim2.fromOffset(520, 130)
	reveal.BackgroundColor3 = Color3.fromRGB(30, 8, 12)
	reveal.BackgroundTransparency = 0.25
	reveal.Visible = false
	reveal.ZIndex = 40
	reveal.Parent = Ui.root
	Instance.new("UICorner", reveal).CornerRadius = UDim.new(0, 16)
	local revealStroke = Instance.new("UIStroke")
	revealStroke.Color, revealStroke.Thickness = Color3.fromRGB(255, 60, 70), 3
	revealStroke.Parent = reveal
	local revealArt = Ui.art(reveal, "", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(110, 110),
		ZIndex = 41,
	})
	label(reveal, {
		Position = UDim2.fromOffset(128, 10),
		Size = UDim2.new(1, -140, 0, 26),
		Text = "🔪 THE MURDERER HAS",
		TextColor3 = Color3.fromRGB(255, 200, 200),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 41,
	})
	local revealName = label(reveal, {
		Position = UDim2.fromOffset(128, 36),
		Size = UDim2.new(1, -140, 0, 50),
		TextColor3 = Color3.fromRGB(255, 70, 80),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 41,
	})
	local revealText = label(reveal, {
		Position = UDim2.fromOffset(128, 90),
		Size = UDim2.new(1, -140, 0, 28),
		TextColor3 = Color3.fromRGB(230, 230, 240),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		ZIndex = 41,
	})
	local revealToken = 0
	local function showReveal(info: { [string]: any })
		if not player:GetAttribute("InRound") and not player:GetAttribute("Spectating") then
			return
		end
		revealToken += 1
		local token = revealToken
		local knife = if type(info.Knife) == "string" then info.Knife else ""
		local parsed = Items.Parse(knife)
		revealArt.Image = if parsed then (VoxelKnives[parsed.Name] or KnifeIcons[parsed.Name] or "") else ""
		revealName.Text = `{string.upper(tostring(info.Name or "?"))}  Lv {tonumber(info.Level) or 1}`
		revealText.Text = tostring(info.Description or "")
		reveal.Visible = true
		local scale = reveal:FindFirstChild("Pop") :: UIScale? or Instance.new("UIScale")
		scale.Name = "Pop"
		scale.Parent = reveal
		scale.Scale = 1.4
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		task.delay(4, function()
			if token == revealToken then
				reveal.Visible = false
			end
		end)
	end

	-- The kill card: who got you, with what, and where that knife comes from - the "I need that"
	-- moment (right after dying in a round)
	local kill = Instance.new("Frame")
	kill.Name = "KillCard"
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
	local killArt = Ui.art(kill, "", {
		Position = UDim2.fromOffset(16, 54),
		Size = UDim2.fromOffset(130, 130),
		ZIndex = 41,
	})
	local killKnife = label(kill, {
		Position = UDim2.fromOffset(156, 58),
		Size = UDim2.new(1, -168, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 41,
	})
	local killRarity = label(kill, {
		Position = UDim2.fromOffset(156, 92),
		Size = UDim2.new(1, -168, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 41,
	})
	local killPower = label(kill, {
		Position = UDim2.fromOffset(156, 120),
		Size = UDim2.new(1, -168, 0, 30),
		TextColor3 = Color3.fromRGB(255, 215, 70),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 41,
	})
	local killWhere = label(kill, {
		Position = UDim2.fromOffset(12, 196),
		Size = UDim2.new(1, -24, 0, 40),
		TextColor3 = Color3.fromRGB(140, 240, 150),
		TextWrapped = true,
		ZIndex = 41,
	})
	local killToken = 0
	local function showKill(info: { [string]: any })
		killToken += 1
		local token = killToken
		local knife = if type(info.Knife) == "string" then info.Knife else ""
		local parsed = Items.Parse(knife)
		killTitle.Text = `Killed by {tostring(info.Name or "the Murderer")}`
		killArt.Image = if parsed then (VoxelKnives[parsed.Name] or KnifeIcons[parsed.Name] or "") else ""
		killKnife.Text = if parsed then Items.DisplayName(knife) else "A knife"
		killKnife.TextColor3 = if parsed then Items.Color(knife) else Color3.new(1, 1, 1)
		local rarity = if parsed then parsed.Knife.Rarity else ""
		killRarity.Text = string.upper(rarity)
		killRarity.TextColor3 = Knives.RarityColors[rarity] or Color3.new(1, 1, 1)
		killPower.Text = if type(info.PerkName) == "string"
			then `⚡ {info.PerkName}  Lv {tonumber(info.Level) or 1}`
			else "No power"
		-- Where to get one: the biome that knife's rarity lives in
		local biome = nil
		for _, zone in GameConfig.Zones do
			if zone.Rarity == rarity then
				biome = zone.Title
			end
		end
		killWhere.Text = if biome then `Want one? Steal it from {biome}!` else ""
		kill.Visible = true
		local scale = kill:FindFirstChild("Pop") :: UIScale? or Instance.new("UIScale")
		scale.Name = "Pop"
		scale.Parent = kill
		scale.Scale = 0.7
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		task.delay(5, function()
			if token == killToken then
				kill.Visible = false
			end
		end)
	end

	Remotes:WaitForChild("Effect").OnClientEvent:Connect(function(kind: string, text: any, extra: any)
		if kind == "PowerReveal" then
			if type(text) == "table" then
				showReveal(text)
			end
			return
		end
		if kind == "KillCard" then
			if type(text) == "table" then
				showKill(text)
			end
			return
		end
		if kind == "RoundCard" then
			if type(text) == "table" then
				showCard(text)
			end
			return
		end
		if kind == "AtRisk" then
			if type(text) == "table" and type(extra) == "string" and #text > 0 then
				task.spawn(showRisk, text, extra)
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
			end
		end)
	end)
end

return Transitions
