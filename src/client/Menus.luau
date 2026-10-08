--!strict
-- The left-side menu buttons (chunky, Steal An Egg style) and their panels:
--   Index    every knife in the game: silhouettes until you own one, and a reward to claim for each
--   Knives   your wall (equip the one you fight / murder with, sell the rest)
--   Rebirth  start over for a permanent multiplier
-- and the Lucky Wheel's panel, opened by standing on the ring in front of it (server PlazaWheel).
-- Knife cards show a live 3D model in a ViewportFrame built from the same KnifeModel as the game.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local IndexView = require(script.Parent.IndexView)
local RebirthView = require(script.Parent.RebirthView)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Items = require(Shared:WaitForChild("Items"))
local Knives = require(Shared.Config:WaitForChild("Knives"))
local Textures = require(Shared.Config:WaitForChild("Textures"))
local KnifeModel = require(Shared:WaitForChild("KnifeModel"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local new = Ui.new

local Menus = {}

local DARK = Ui.PANEL

-- A live 3D knife (or case) in a card; rotates slowly
local spinning: { [ViewportFrame]: Model } = {}
local function viewport(parent: Instance, build: () -> Model, dim: boolean?, size: UDim2?): ViewportFrame
	local frame = new("ViewportFrame", {
		Size = size or UDim2.fromScale(1, 0.55),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 200, 200),
		LightColor = Color3.new(1, 1, 1),
		ImageColor3 = if dim then Color3.new(0, 0, 0) else Color3.new(1, 1, 1),
		ZIndex = 6,
	}, parent)
	local model = build()
	model:PivotTo(CFrame.Angles(0, 0, math.rad(-40))) -- flat of the blade to the camera, tilted
	model.Parent = frame
	local camera = new("Camera", { FieldOfView = 30 }, frame)
	frame.CurrentCamera = camera
	local cf, size3 = model:GetBoundingBox()
	camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, 0, size3.Magnitude * 1.7), cf.Position)
	spinning[frame] = model
	return frame
end
RunService.RenderStepped:Connect(function(dt: number)
	for frame, model in spinning do
		if not frame.Parent then
			spinning[frame] = nil
		else
			local visible = true
			local ancestor: Instance? = frame
			while ancestor do
				if ancestor:IsA("GuiObject") and not ancestor.Visible then
					visible = false
					break
				end
				ancestor = ancestor.Parent
			end
			if visible and require(script.Parent.Lod).Profile == "High" then
				model:PivotTo(model:GetPivot() * CFrame.Angles(0, dt * 0.8, 0))
			end
		end
	end
end)

local function scrollGrid(parent: Instance, cell: Vector2): ScrollingFrame
	local scroll = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 5,
	}, parent)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.X, cell.Y),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, scroll)
	Ui.padding(scroll, 4, 4)
	local grid = scroll:FindFirstChildOfClass("UIGridLayout") :: UIGridLayout
	local function reflow()
		local width = math.max(140, scroll.AbsoluteSize.X - 16)
		local columns = math.max(1, math.floor((width + 10) / (cell.X + 10)))
		grid.CellSize = UDim2.fromOffset((width - (columns - 1) * 10) / columns, cell.Y)
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(reflow)
	reflow()
	return scroll
end

local function card(parent: Instance, order: number, color: Color3?): Frame
	local tint = color or Color3.fromRGB(90, 90, 110)
	local frame = new("Frame", {
		LayoutOrder = order,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 5,
	}, parent)
	Ui.corner(frame, 12)
	Ui.gradient(frame, tint:Lerp(DARK, 0.35), tint:Lerp(DARK, 0.75))
	new("UIStroke", { Color = tint, Thickness = 3 }, frame)
	return frame
end

local function cardText(parent: Instance, y: number, height: number, text: string, color: Color3?): TextLabel
	local label = Ui.label({
		Position = UDim2.fromOffset(6, y),
		Size = UDim2.new(1, -12, 0, height),
		Text = text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = color or Color3.new(1, 1, 1),
		ZIndex = 6,
	}, parent)
	Ui.textStroke(label, 1.5)
	return label
end

-- The knife's Murderer perk: its Blender badge in the card's top corner
local function perkBadge(parent: Instance, perkId: string)
	local icon = Textures.PerkIcons[perkId]
	local perk = GameConfig.Perks[perkId]
	if not icon or not perk then
		return
	end
	-- A small dark pill in the corner (it used to sit big across the knife picture)
	local pill = new("Frame", {
		Name = "Perk",
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.fromRGB(20, 16, 30),
		BackgroundTransparency = 0.25,
		ZIndex = 8,
	}, parent)
	Ui.corner(pill, 11)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 3),
	}, pill)
	new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 7) }, pill)
	new("ImageLabel", {
		Size = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
		Image = icon,
		ZIndex = 9,
	}, pill)
	local name = Ui.label({
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(255, 140, 140),
		Text = perk.DisplayName,
		ZIndex = 9,
	}, pill)
	Ui.textStroke(name, 1.2)
end

local function smallButton(
	parent: Instance,
	y: UDim,
	height: number,
	color: Color3,
	text: string,
	onClick: () -> ()
): TextButton
	return Ui.chunky({
		Position = UDim2.new(0, 6, y.Scale, y.Offset),
		Size = UDim2.new(1, -12, 0, height),
		BackgroundColor3 = color,
		Text = text,
		ZIndex = 7,
	}, parent, nil, onClick)
end

function Menus.Init()
	-- Left column of big buttons
	-- (phones: a strip of square icon buttons down the left edge, under the Store button)
	local column = new("Frame", {
		Name = "Navigation",
		AnchorPoint = if Ui.Phone then Vector2.zero else Vector2.new(0, 0.5),
		Position = if Ui.Phone then UDim2.fromOffset(10, 118) else UDim2.new(0, 14, 0.4, 0),
		Size = if Ui.Phone then UDim2.fromOffset(60, 300) else UDim2.fromOffset(190, 330),
		BackgroundTransparency = 1,
	}, Ui.gui)
	local navGrid = new("UIGridLayout", {
		CellSize = UDim2.fromOffset(112, 44),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, column)
	local function placeNavigation()
		local layout = Ui.Layout.get()
		column.AnchorPoint = Vector2.zero
		column.Position = UDim2.fromOffset(12, 64)
		column.Size = UDim2.fromOffset(layout.NavigationWidth, if layout.Short then 96 else 200)
		navGrid.FillDirectionMaxCells = if layout.Short then 2 else 1
	end
	Ui.Layout.Changed:Connect(placeNavigation)
	placeNavigation()

	local panels: { Frame } = {}
	local function toggle(frame: Frame)
		local open = not frame.Visible
		for _, p in panels do
			p.Visible = false
		end
		frame.Visible = open
		if open and GuiService.SelectedObject ~= nil then
			GuiService.SelectedObject = frame:FindFirstChild("Close", true)
		end
	end

	-- INDEX: the illustrated collection grid and selected knife inspector.
	local indexFrame, refreshIndexView = IndexView.Build()
	table.insert(panels, indexFrame)

	-- KNIVES: your wall ----------------------------------------------------------------------------
	local knivesFrame, knivesBody =
		Theme.shell("My Knives", "My Knives", Color3.fromRGB(130, 80, 230), "Knives", 650, 960)
	table.insert(panels, knivesFrame)
	local rackGrid = scrollGrid(knivesBody, Vector2.new(150, 254))

	-- POWERS ---------------------------------------------------------------------------------------

	-- REBIRTH --------------------------------------------------------------------------------------
	local rebirthFrame, refreshRebirth = RebirthView.Build()
	table.insert(panels, rebirthFrame)

	-- Refreshers ------------------------------------------------------------------------------------
	local function clearGrid(grid: Instance)
		for _, child in grid:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
	end

	local function refreshRack()
		clearGrid(rackGrid)
		local owned = Ui.list(player:GetAttribute("Knives"))
		local equipped = player:GetAttribute("Equipped") or ""
		local sealed: { [number]: boolean } = {}
		for _, i in Ui.list(player:GetAttribute("SealedKnives")) do
			sealed[tonumber(i) or 0] = true
		end
		if #owned == 0 or #owned == #Ui.list(player:GetAttribute("SealedKnives")) then
			local empty = card(rackGrid, 1)
			cardText(empty, 20, 120, "Steal a coffin from a monster and run it home!")
			return
		end
		local equippedShown = false -- two copies of the same knife: only one says "Equipped"
		for index, item in owned do
			local parsed = Items.Parse(item)
			if not parsed or sealed[index] then
				continue
			end
			local knife = parsed.Knife
			local c = card(rackGrid, index, Items.Color(item))
			Ui.art(c, knife.Name, { Size = UDim2.new(1, 0, 0, 84), ZIndex = 6 })
			local previewButton = new(
				"TextButton",
				{ Name = "Preview", Text = "", Size = UDim2.new(1, 0, 0, 84), BackgroundTransparency = 1, ZIndex = 7 },
				c
			)
			previewButton.Activated:Connect(function()
				local selected, body =
					Theme.shell("Knife Preview", knife.DisplayName, Items.Color(item), knife.Name, 380, 460)
				viewport(body, function()
					return KnifeModel.Build(item, true)
				end, false, UDim2.new(1, 0, 1, -44))
				cardText(body, 0, 24, Items.DisplayName(item), Items.Color(item)).Position = UDim2.new(0, 6, 1, -36)
				selected.Visible = true
				selected:GetPropertyChangedSignal("Visible"):Connect(function()
					if not selected.Visible then
						selected:Destroy()
					end
				end)
			end)
			cardText(c, 88, 20, Items.DisplayName(item), Items.Color(item))
			cardText(c, 108, 16, knife.Rarity, Knives.RarityColors[knife.Rarity])
			cardText(c, 124, 18, `+${Ui.abbreviate(Items.Income(item))}/s`, Color3.fromRGB(120, 255, 140))
			if parsed.Perk then
				perkBadge(c, parsed.Perk)
			end
			local isEquipped = item == equipped and not equippedShown
			equippedShown = equippedShown or isEquipped
			smallButton(
				c,
				UDim.new(1, -98),
				44,
				if isEquipped then Color3.fromRGB(70, 200, 100) else Color3.fromRGB(80, 150, 240),
				if isEquipped then "Equipped" else "Equip",
				function()
					Remotes.Equip:InvokeServer(if isEquipped then "" else item)
				end
			)
			smallButton(
				c,
				UDim.new(1, -48),
				44,
				Color3.fromRGB(230, 150, 50),
				`Sell ${Ui.abbreviate(Items.Income(item) * GameConfig.SellSeconds)}`,
				function()
					Remotes.Sell:InvokeServer(index)
				end
			)
		end
	end

	local indexBadge: TextLabel? = nil
	local function refreshIndex()
		local claimable = refreshIndexView()
		if indexBadge then
			indexBadge.Visible = claimable > 0
			indexBadge.Text = tostring(claimable)
		end
	end

	Ui.Panels.Index = indexFrame

	-- RebirthView owns its live requirement and bonus displays.

	for attribute, refresh in
		{
			Knives = refreshRack,
			SealedKnives = refreshRack,
			Equipped = refreshRack,
			Discovered = refreshIndex,
			IndexClaimed = refreshIndex,
			Rebirths = refreshRebirth,
		} :: { [string]: () -> () }
	do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	Ui.gui:GetAttributeChangedSignal("IndexAcknowledged"):Connect(refreshIndex)
	player:GetAttributeChangedSignal("Cash"):Connect(function()
		if rebirthFrame.Visible then
			refreshRebirth()
		end
	end)

	-- The buttons themselves ------------------------------------------------------------------------
	local function menuButton(order: number, text: string, color: Color3, icon: string, frame: Frame, refresh: () -> ())
		local button = Theme.button(column, text, color, {
			LayoutOrder = order,
			Size = UDim2.fromOffset(112, 44),
			MaximumTextSize = 23,
		}, function()
			refresh()
			toggle(frame)
		end, icon)
		return button
	end
	Ui.Navigation = column
	local indexButton = menuButton(2, "Index", Theme.Cyan, "Index", indexFrame, refreshIndex)
	Ui.GuideTargets.Index = indexButton
	indexBadge = Theme.badge(indexButton)
	-- Big tiles two to a row: easy to read, easy to tap (no scrolling)
	local moreFrame, moreBody = Theme.shell("More", "More", Theme.Cyan, "More", 640, 640)
	table.insert(panels, moreFrame)
	local moreList = new("Frame", {
		Size = UDim2.fromScale(1, 0.74),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, moreBody)
	Ui.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -8, 0.5, -8),
		CellPadding = UDim2.fromOffset(16, 14),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, moreList)
	local moreOrder = { Knives = 1, Invite = 2, Rebirth = 3, Stats = 4 }
	local moreColors = {
		Knives = Theme.Gold,
		Invite = Theme.Cyan,
		Rebirth = Theme.Purple,
		Stats = Theme.Green,
	}
	-- (a 2x2 of Knives, Invite, Rebirth, Stats; Guidance and How to play along the bottom)
	local function moreButton(name: string, icon: string, frame: Frame, refresh: () -> ())
		local tile = Theme.button(moreList, name, moreColors[name], {
			Name = name,
			LayoutOrder = moreOrder[name],
			ZIndex = 8,
			MaximumTextSize = 44,
		}, function()
			refresh()
			toggle(frame)
		end, icon)
		-- icon big on the left half, the word big on the right
		Ui.GuideTargets[name] = tile
		for _, child in tile:GetChildren() do
			if child:IsA("ImageLabel") and child.Name ~= "Studs" then
				child.Position = UDim2.fromScale(0.04, 0.1)
				child.Size = UDim2.fromScale(0.36, 0.8)
			end
		end
		local word = tile:FindFirstChild("Label") :: TextLabel?
		if word then
			word.Position = UDim2.fromScale(0.4, 0.15)
			word.Size = UDim2.fromScale(0.56, 0.7)
		end
	end
	moreButton("Knives", "Katana", knivesFrame, refreshRack)
	moreButton("Rebirth", "Rebirth", rebirthFrame, refreshRebirth)

	-- Invite friends (friends here = more cash: Social): Roblox's own invite, one tap
	local inviteTile = Theme.button(moreList, "Invite", Theme.Cyan, {
		Name = "Invite",
		LayoutOrder = 2,
		ZIndex = 8,
		MaximumTextSize = 44,
	}, function()
		pcall(function()
			game:GetService("SocialService"):PromptGameInvite(player)
		end)
	end, "Players")
	Ui.GuideTargets.Invite = inviteTile
	local statsFrame, statsBody = Theme.shell("Stats", "Stats", Color3.fromRGB(87, 202, 150), "Stats", 650, 960)
	table.insert(panels, statsFrame)
	-- Stat tiles (big number, small label), like the rest of the menus - it used to be a plain text
	-- list floating over the world
	local detailsScroll = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		ZIndex = 5,
	}, statsBody)
	new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0, 92),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, detailsScroll)
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingRight = UDim.new(0, 8) }, detailsScroll)
	type Tile = { Frame: Frame, Value: TextLabel }
	local tiles: { [string]: Tile } = {}
	local function tile(key: string, order: number, icon: string, label: string, color: Color3)
		local frame = new("Frame", {
			Name = key,
			LayoutOrder = order,
			BackgroundColor3 = Color3.fromRGB(30, 34, 52),
			BackgroundTransparency = 0.1,
			ZIndex = 6,
		}, detailsScroll)
		Ui.corner(frame, 12)
		new("UIStroke", { Color = color, Thickness = 2 }, frame)
		local value = Ui.label({
			Position = UDim2.fromOffset(10, 6),
			Size = UDim2.new(1, -20, 0, 48),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color,
			Text = "",
			ZIndex = 7,
		}, frame)
		Ui.textStroke(value, 2)
		local name = Ui.label({
			Position = UDim2.new(0, 10, 1, -34),
			Size = UDim2.new(1, -20, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(220, 222, 235),
			Text = `{icon}  {label}`,
			ZIndex = 7,
		}, frame)
		Ui.textStroke(name, 1.5)
		tiles[key] = { Frame = frame, Value = value }
	end
	tile("Income", 1, "💰", "Income per second", Color3.fromRGB(120, 255, 140))
	tile("Speed", 2, "👟", "Walk speed", Color3.fromRGB(120, 200, 255))
	tile("Rebirths", 3, "🔁", "Rebirths", Color3.fromRGB(200, 140, 255))
	tile("Kills", 5, "🔪", "Murderer kills", Color3.fromRGB(255, 110, 120))
	tile("Wins", 6, "🏆", "Rounds won", Color3.fromRGB(255, 215, 80))
	tile("Stolen", 7, "🔪", "Knives stolen", Color3.fromRGB(255, 120, 120))
	tile("Friends", 10, "👥", "Friend boost", Color3.fromRGB(120, 230, 200))
	tile("Shield", 12, "🛡️", "Knives safe for", Color3.fromRGB(140, 220, 255))
	tile("Boost", 13, "⚡", "Cash boost", Color3.fromRGB(120, 255, 140))
	local function refreshDetails()
		local function set(key: string, text: string, show: boolean?)
			tiles[key].Value.Text = text
			tiles[key].Frame.Visible = show ~= false
		end
		local now = workspace:GetServerTimeNow()
		set("Income", `${Ui.abbreviate(player:GetAttribute("Income") or 0)}/s`)
		set("Speed", tostring(math.floor(GameConfig.WalkSpeedFor((player:GetAttribute("Speed") or 0) :: number))))
		set("Rebirths", tostring(player:GetAttribute("Rebirths") or 0))
		set("Kills", Ui.abbreviate(player:GetAttribute("Kills") or 0))
		set("Wins", Ui.abbreviate(player:GetAttribute("Wins") or 0))
		set("Stolen", Ui.abbreviate(player:GetAttribute("KnivesStolen") or 0))
		set("Friends", `+{(player:GetAttribute("FriendsHere") or 0) * 10}%`)
		set("Shield", Ui.clock(player:GetAttribute("ShieldLeft") or 0), player:GetAttribute("Shielded") == true)
		local boost = player:GetAttribute("BoostUntil")
		set(
			"Boost",
			if type(boost) == "number" and boost > now then Ui.clock(boost - now) else "",
			type(boost) == "number" and boost > now
		)
	end
	moreButton("Stats", "Trophy", statsFrame, refreshDetails)
	local guidanceButton: TextButton
	guidanceButton = Theme.button(moreBody, "Guidance: AUTO", Theme.Cyan, {
		Name = "GuidanceMode",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(0.5, -8, 0.24, 0),
		ZIndex = 8,
		MaximumTextSize = 34,
	}, function()
		local current = Ui.gui:GetAttribute("GuidanceMode") or player:GetAttribute("GuidanceMode") or "Auto"
		local mode = if current == "Auto" then "On" else if current == "On" then "Off" else "Auto"
		Ui.gui:SetAttribute("GuidanceMode", mode)
		Remotes.Tutorial:FireServer("GuideMode", mode)
	end)
	local function refreshGuidance()
		local label = guidanceButton:FindFirstChild("Label") :: TextLabel?
		if label then
			label.Text = `Guidance: {string.upper(
				(Ui.gui:GetAttribute("GuidanceMode") or player:GetAttribute("GuidanceMode") or "Auto") :: string
			)}`
		end
	end
	Ui.gui:GetAttributeChangedSignal("GuidanceMode"):Connect(refreshGuidance)
	refreshGuidance()
	-- How to play: the first-minutes guide again (client/Tutorial)
	Theme.button(moreBody, "How to play", Theme.Cyan, {
		Name = "HowToPlay",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0.5, -8, 0.24, 0),
		ZIndex = 8,
		MaximumTextSize = 34,
	}, function()
		Ui.Menu.Close()
		if Ui.ReplayTutorial then
			Ui.ReplayTutorial()
		end
	end)
	player.AttributeChanged:Connect(function()
		if statsFrame.Visible then
			refreshDetails()
		end
	end)
	ReplicatedStorage.AttributeChanged:Connect(function()
		if statsFrame.Visible then
			refreshDetails()
		end
	end)
	Ui.GuideTargets.More = menuButton(3, "More", Theme.Cyan, "More", moreFrame, function() end)

	-- Slow mode (T): walk at normal speed instead of your trained speed
	local slowButton: TextButton
	local function setSlow(on: boolean)
		Remotes.SlowMode:FireServer(on)
	end
	slowButton = Theme.button(column, "Slow: OFF", Color3.fromRGB(150, 150, 160), {
		LayoutOrder = 5,
		Name = "Slow",
		Size = UDim2.fromOffset(112, 44),
		MaximumTextSize = 18,
	}, function()
		setSlow(not player:GetAttribute("SlowMode"))
	end)
	local function refreshSlow()
		local on = player:GetAttribute("SlowMode") == true
		(slowButton:FindFirstChild("Label") :: TextLabel).Text = (if Ui.Phone then "Slow: " else "[T] Slow: ")
			.. (if on then "ON" else "OFF")
		slowButton.BackgroundColor3 = if on then Color3.fromRGB(90, 200, 110) else Color3.fromRGB(150, 150, 160)
	end
	player:GetAttributeChangedSignal("SlowMode"):Connect(refreshSlow)
	refreshSlow()
	-- Steal An Egg's switch: a little on/off slider with "Slow Mode" beside it, under the left
	-- buttons (the old button stays hidden; T still toggles it)
	slowButton.Visible = false
	slowButton:GetPropertyChangedSignal("Visible"):Connect(function()
		if slowButton.Visible then
			slowButton.Visible = false
		end
	end)
	local slowToggle = new("TextButton", {
		Name = "SlowToggle",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(150, 30),
	}, Ui.gui)
	local track = new("Frame", {
		Size = UDim2.fromOffset(58, 28),
		BackgroundColor3 = Color3.fromRGB(40, 70, 50),
		ZIndex = 2,
	}, slowToggle)
	Ui.corner(track, 8)
	new("UIStroke", { Color = Color3.fromRGB(16, 14, 24), Thickness = 2.5 }, track)
	local knob = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(24, 22),
		BackgroundColor3 = Color3.fromRGB(130, 255, 60),
		ZIndex = 3,
	}, track)
	Ui.corner(knob, 6)
	local caption = new("TextLabel", {
		Position = UDim2.fromOffset(64, 0),
		Size = UDim2.new(1, -64, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Text = "Slow Mode",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	}, slowToggle)
	new("UIStroke", { Color = Color3.fromRGB(16, 14, 24), Thickness = 2 }, caption)
	local function drawToggle()
		local on = player:GetAttribute("SlowMode") == true
		knob.Position = if on then UDim2.new(1, -27, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
		track.BackgroundColor3 = if on then Color3.fromRGB(70, 190, 60) else Color3.fromRGB(40, 50, 60)
		knob.BackgroundColor3 = if on then Color3.new(1, 1, 1) else Color3.fromRGB(130, 255, 60)
	end
	player:GetAttributeChangedSignal("SlowMode"):Connect(drawToggle)
	drawToggle()
	slowToggle.Activated:Connect(function()
		setSlow(not player:GetAttribute("SlowMode"))
	end)
	-- Above the left column (Steal An Egg puts it there too): under it, it sat right by the move
	-- thumbstick on phones and got hit while running
	game:GetService("RunService").Heartbeat:Connect(function()
		local nav = Ui.Navigation :: GuiObject?
		local holder = slowToggle.Parent :: GuiObject?
		slowToggle.Visible = nav ~= nil and nav.Visible and Ui.inHub()
		if nav and holder then
			local first: GuiObject? = nil
			for _, child in nav:GetChildren() do
				if child:IsA("GuiObject") and child.Visible and child ~= slowButton then
					if not first or child.AbsolutePosition.Y < first.AbsolutePosition.Y then
						first = child
					end
				end
			end
			local factor = Ui.Scale.Scale
			local top = if first then first.AbsolutePosition.Y else nav.AbsolutePosition.Y
			slowToggle.Position = UDim2.fromOffset(
				(nav.AbsolutePosition.X - holder.AbsolutePosition.X) / factor,
				(top - holder.AbsolutePosition.Y) / factor - 30 - 6
			)
		end
	end)
	game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.T then
			setSlow(not player:GetAttribute("SlowMode"))
		end
	end)
	if RunService:IsStudio() and not Ui.Phone then
		-- Studio: test buttons
		local tests = new("Frame", {
			LayoutOrder = 6,
			Size = UDim2.new(1, 0, 0, 66),
			BackgroundTransparency = 1,
		}, column)
		new("UIGridLayout", { CellSize = UDim2.new(0.5, -3, 0, 30), CellPadding = UDim2.fromOffset(6, 6) }, tests)
		type Test = { Text: string, Command: string, Arg: string?, Color: Color3 }
		local specs: { Test } = {
			{ Text = "Bot: Murd", Command = "BotRound", Arg = "Murderer", Color = Color3.fromRGB(200, 40, 50) },
			{ Text = "Bot: Inno", Command = "BotRound", Arg = "Innocent", Color = Color3.fromRGB(70, 150, 240) },
			{ Text = "Coffin", Command = "Coffin", Arg = "Epic", Color = Color3.fromRGB(170, 90, 255) },
		}
		for _, spec in specs do
			Ui.button({ Text = spec.Text, BackgroundColor3 = spec.Color }, tests, function()
				Remotes.Debug:InvokeServer(spec.Command, spec.Arg)
			end)
		end
	end

	refreshRack()
	refreshIndex()
	refreshRebirth()

	-- The left buttons only in the hub (Ui.inHub: alive, not in or still watching a round)
	game:GetService("RunService").Heartbeat:Connect(function()
		column.Visible = Ui.inHub()
	end)
	player:GetAttributeChangedSignal("InRound"):Connect(function()
		local inRound = player:GetAttribute("InRound") == true
		if inRound then
			for _, p in panels do
				p.Visible = false
			end
		end
	end)

	-- Keyboard / gamepad shortcut: K = knives (gamepad: L1)
	ContextActionService:BindAction("ToggleKnives", function(_, state)
		if state == Enum.UserInputState.Begin and column.Visible then
			refreshRack()
			toggle(knivesFrame)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.K, Enum.KeyCode.ButtonL1)

	-- The Lucky Wheel (server PlazaWheel): stand on the glowing ring in front of it and its panel
	-- opens; step off and it closes. Close it yourself and it stays shut until you step off.
	local onRing: BasePart? = nil
	local openedFrame: Frame? = nil
	local nextCheck = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextCheck then
			return
		end
		nextCheck = now + 0.15
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local standing: BasePart? = nil
		if root and not player:GetAttribute("InRound") then
			for _, instance in CollectionService:GetTagged("ShopRing") do
				local ring = instance :: BasePart
				local offset = root.Position - ring.Position
				local radius = ring.Size.Y / 2 + 1.5
				if Vector3.new(offset.X, 0, offset.Z).Magnitude < radius and math.abs(offset.Y) < 6 then
					standing = ring
					break
				end
			end
		end
		if standing == onRing then
			return
		end
		-- Stepped off (or onto a different ring): close what this ring opened
		if openedFrame and openedFrame.Visible then
			openedFrame.Visible = false
		end
		openedFrame = nil
		onRing = standing
		if standing then
			local which = standing:GetAttribute("ShopPanel")
			local frame: Frame? = Ui.Panels[tostring(which)] :: any -- the Lucky Wheel (client/GambleUi)
			if frame then
				if not frame.Visible then
					toggle(frame)
				end
				openedFrame = frame
			end
		end
	end)
end

return Menus
