--!strict
-- The left-side menu buttons (chunky, Steal An Egg style) and their panels:
--   Index    every knife in the game: silhouettes until you own one, and a reward to claim for each
--   Knives   your wall (equip the one you fight / murder with, sell the rest)
--   Rebirth  start over for a permanent multiplier
-- and the shopkeepers' panels, opened by standing on the ring at their stall (server ShopNPCs):
--   Mortimer the Knife Merchant  Health upgrades and sealed cases, with the odds of everything inside
--   Madame Vesper the Mystic     buy, upgrade and equip Innocent Powers
-- Knife cards show a live 3D model in a ViewportFrame built from the same KnifeModel as the game.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local IndexView = require(script.Parent.IndexView)
local RebirthView = require(script.Parent.RebirthView)
local CaseShowcase = require(script.Parent.CaseShowcase)
local CaseOdds = require(script.Parent.CaseOdds)
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
	if model:GetAttribute("Case") then
		model:PivotTo(CFrame.Angles(math.rad(-18), math.rad(205), 0)) -- three-quarter view of the lock
	else
		model:PivotTo(CFrame.Angles(0, 0, math.rad(-40))) -- flat of the blade to the camera, tilted
	end
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

local function panel(title: string, color: Color3, icon: string): (Frame, Frame)
	if title == "Mortimer's Knife Cases" then
		local frame, body = Theme.shell(title, "Shop", Theme.Green, "Cash", 540)
		return frame, body
	end
	local frame = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Name = title,
		Size = UDim2.fromOffset(960, 650),
		BackgroundColor3 = DARK,
		Visible = false,
		ZIndex = 5,
	}, Ui.gui)
	Ui.corner(frame, 18)
	new("UIStroke", { Thickness = 2, Color = Color3.fromRGB(10, 18, 34) }, frame)
	-- Faint diagonal stripes in the background
	new("UIGradient", {
		Rotation = 45,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 215)),
	}, frame)
	local header = new("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 5,
	}, frame)
	Ui.corner(header, 18)
	Ui.gradient(header, color:Lerp(Color3.new(1, 1, 1), 0.2), color:Lerp(Color3.new(0, 0, 0), 0.2))
	local titleLabel = Ui.label({
		Size = UDim2.new(1, -130, 1, -12),
		Position = UDim2.fromOffset(20, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = `{icon} {title}`,
		ZIndex = 6,
	}, header)
	Ui.textStroke(titleLabel, 3)
	local close = Ui.chunky(
		{
			Name = "Close",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(50, 46),
			BackgroundColor3 = Color3.fromRGB(230, 50, 60),
			Text = "X",
			ZIndex = 6,
		},
		header,
		nil,
		function()
			frame.Visible = false
		end
	)
	close.Name = "Close"
	local body = new("Frame", {
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 1, -64),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, frame)
	Ui.padding(body, 14, 8)
	-- Pop in
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			local scale = frame:FindFirstChildOfClass("UIScale") or new("UIScale", {}, frame)
			local target = 1 -- a bit bigger on desktop: easier to read
			scale.Scale = target * 0.85
			TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = target }):Play()
		end
	end)
	Ui.fitMenu(frame)
	Ui.registerMenu(frame)
	return frame, body
end

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
	new("ImageLabel", {
		Name = "Perk",
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(34, 34),
		BackgroundTransparency = 1,
		Image = icon,
		ZIndex = 8,
	}, parent)
	local name = Ui.label({
		Position = UDim2.fromOffset(40, 10),
		Size = UDim2.new(1, -44, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 120, 120),
		Text = perk.DisplayName,
		ZIndex = 8,
	}, parent)
	Ui.textStroke(name, 1.5)
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

	-- SHOP: sealed cases ---------------------------------------------------------------------------
	local shopFrame, shopBody = panel("Mortimer's Knife Cases", Color3.fromRGB(70, 200, 90), "🛒")
	table.insert(panels, shopFrame)
	local shopList = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 5,
	}, shopBody)
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, shopList)
	local oddsFrame, oddsBody = panel("Cash case: full odds", Color3.fromRGB(61, 178, 255), "📊")
	table.insert(panels, oddsFrame)
	local oddsScroll = new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -56),
		BackgroundTransparency = 1,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ZIndex = 5,
	}, oddsBody)
	local fullOdds = Ui.label({
		Size = UDim2.new(1, -12, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 16,
		TextScaled = false,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 6,
	}, oddsScroll)
	Ui.button(
		{ Text = "Back to cash cases", Position = UDim2.new(0, 0, 1, -48), Size = UDim2.new(1, 0, 0, 44), ZIndex = 6 },
		oddsBody,
		function()
			oddsFrame.Visible = false
			shopFrame.Visible = true
		end
	)

	-- Health upgrades, at the top of the merchant's list
	do
		local color = Color3.fromRGB(235, 70, 90)
		local row = new("Frame", {
			LayoutOrder = 0,
			Size = UDim2.new(1, -12, 0, 86),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 5,
		}, shopList)
		Ui.corner(row, 14)
		Ui.gradient(row, color:Lerp(DARK, 0.3), color:Lerp(DARK, 0.8))
		new("UIStroke", { Thickness = 3, Color = color }, row)
		local label = Ui.label({
			Position = UDim2.fromOffset(16, 8),
			Size = UDim2.new(1, -190, 1, -16),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
			ZIndex = 6,
		}, row)
		Ui.textStroke(label, 2)
		local buy = Ui.chunky(
			{
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(150, 60),
				BackgroundColor3 = color,
				Text = "",
				ZIndex = 7,
			},
			row,
			"❤️",
			function()
				Remotes.Purchase:InvokeServer("Health")
			end
		)
		local function refreshHealth()
			local level = (player:GetAttribute("HealthLevel") or 0) :: number
			local titan = if player:GetAttribute("Pass_Titan") then 2 else 1
			local now = GameConfig.MaxHealthFor(level, titan)
			if level >= GameConfig.Health.MaxLevel then
				label.Text = `❤️ MAX HEALTH {now} (maxed!)`
				buy.Visible = false
			else
				label.Text =
					`❤️ MAX HEALTH {now} → {GameConfig.MaxHealthFor(level + 1, titan)}\nBosses and vault owners need more hits to take you down`
				local text = buy:FindFirstChild("Label") :: TextLabel?
				if text then
					text.Text = `${Ui.abbreviate(GameConfig.HealthCost(level))}`
				end
			end
		end
		player:GetAttributeChangedSignal("HealthLevel"):Connect(refreshHealth)
		player:GetAttributeChangedSignal("Pass_Titan"):Connect(refreshHealth)
		refreshHealth()
	end
	for order, entry in GameConfig.CaseShop do
		local row = CaseShowcase.Build(shopList, entry.Rarity, "$" .. Ui.abbreviate(entry.Cost), function()
			Remotes.Purchase:InvokeServer("Case:" .. entry.Rarity)
		end, function()
			fullOdds.Text = CaseOdds.Text(entry.Rarity)
				.. "\n\nCash purchase. Knife, mutation and size are separate rolls. Current rebirth and server luck apply to mutation and size."
			oddsFrame.Visible = true
		end)
		row.LayoutOrder = order + 1
	end

	-- INDEX: the illustrated collection grid and selected knife inspector.
	local indexFrame, refreshIndexView = IndexView.Build()
	table.insert(panels, indexFrame)

	-- KNIVES: your wall ----------------------------------------------------------------------------
	local knivesFrame, knivesBody =
		panel("My Knives · equipped = your Murderer perk", Color3.fromRGB(130, 80, 230), "🔪")
	table.insert(panels, knivesFrame)
	local rackGrid = scrollGrid(knivesBody, Vector2.new(150, 254))

	-- POWERS ---------------------------------------------------------------------------------------
	local powersFrame, powersBody = panel("Innocent Powers", Color3.fromRGB(240, 130, 40), "⚡")
	table.insert(panels, powersFrame)
	local topRow = new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, ZIndex = 5 }, powersBody)
	local loadoutLabel = Ui.label({
		Size = UDim2.fromScale(0.6, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		ZIndex = 6,
	}, topRow)
	Ui.textStroke(loadoutLabel, 2)
	local slotButton = Ui.chunky(
		{
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.38, 1),
			BackgroundColor3 = Color3.fromRGB(90, 180, 90),
			Text = "",
			ZIndex = 6,
		},
		topRow,
		nil,
		function()
			Remotes.Power:InvokeServer("Slot")
		end
	)
	local powersHolder = new("Frame", {
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 1, -48),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, powersBody)
	local powersGrid = scrollGrid(powersHolder, Vector2.new(205, 230))

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
		if #owned == 0 then
			local empty = card(rackGrid, 1)
			cardText(empty, 20, 120, "Steal knives off the bosses' walls on the runway and carry them home!")
			return
		end
		for index, item in owned do
			local parsed = Items.Parse(item)
			if not parsed then
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
				local selected, body = panel("Knife Preview", Items.Color(item), "🔪")
				selected:SetAttribute("MaximumWidth", 460)
				selected:SetAttribute("MaximumHeight", 380)
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
			cardText(c, 108, 16, `{knife.Rarity} · Dmg {Items.Damage(item)}`, Knives.RarityColors[knife.Rarity])
			cardText(c, 124, 18, `+${Ui.abbreviate(Items.Income(item))}/s`, Color3.fromRGB(120, 255, 140))
			if parsed.Perk then
				perkBadge(c, parsed.Perk)
			end
			local isEquipped = item == equipped
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

	local function parsePowers(): { [string]: number }
		local out = {}
		for _, entry in Ui.list(player:GetAttribute("Powers")) do
			local id, level = entry:match("^(%w+):(%d+)$")
			if id and level then
				out[id] = tonumber(level) :: number
			end
		end
		return out
	end

	local function refreshPowers()
		clearGrid(powersGrid)
		local owned = parsePowers()
		local loadout = Ui.list(player:GetAttribute("Loadout"))
		local slots = player:GetAttribute("PowerSlots") or GameConfig.PowerSlots
		loadoutLabel.Text = `Loadout {#loadout}/{slots}{if Ui.Phone then "" else " · keys Z X C"}`
		local label = slotButton:FindFirstChild("Label") :: TextLabel?
		if label then
			label.Text = if slots >= GameConfig.MaxPowerSlots
				then "All slots"
				else `+1 Slot ${Ui.abbreviate(GameConfig.PowerSlotCost)}`
		end
		for index, power in GameConfig.Powers do
			local level = owned[power.Id] or 0
			local equipped = table.find(loadout, power.Id) ~= nil
			local c = card(powersGrid, index, power.Color)
			if equipped then
				(c:FindFirstChildOfClass("UIStroke") :: UIStroke).Color = Color3.new(1, 1, 1)
			end
			cardText(c, 4, 26, power.DisplayName, power.Color)
			local energy = (power :: any).Energy
			cardText(
				c,
				30,
				15,
				if level > 0
					then `Level {level}/{GameConfig.PowerMaxLevel} · ⚡{energy[level]} in rounds`
					else `Locked · ⚡{energy[1]} in rounds`,
				Color3.fromRGB(220, 220, 230)
			)
			local description = Ui.label({
				Position = UDim2.fromOffset(8, 48),
				Size = UDim2.new(1, -16, 0, 56),
				Text = power.Description,
				TextScaled = false,
				TextSize = 14,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 6,
			}, c)
			Ui.textStroke(description, 1)
			local maxed = level >= GameConfig.PowerMaxLevel
			smallButton(
				c,
				UDim.new(1, -98),
				44,
				if maxed then Color3.fromRGB(90, 90, 100) else Color3.fromRGB(240, 150, 50),
				if maxed
					then "MAX"
					elseif level == 0 then `Unlock ${Ui.abbreviate(GameConfig.PowerCost(power.Cost, 0))}`
					else `Upgrade ${Ui.abbreviate(GameConfig.PowerCost(power.Cost, level))}`,
				function()
					if not maxed then
						Remotes.Power:InvokeServer("Buy", power.Id)
					end
				end
			)
			if level > 0 then
				smallButton(
					c,
					UDim.new(1, -48),
					44,
					if equipped then Color3.fromRGB(70, 200, 100) else Color3.fromRGB(80, 150, 240),
					if equipped then "Equipped" else "Equip",
					function()
						Remotes.Power:InvokeServer(if equipped then "Unequip" else "Equip", power.Id)
					end
				)
			end
		end
	end

	-- RebirthView owns its live requirement and bonus displays.

	for attribute, refresh in
		{
			Knives = refreshRack,
			Equipped = refreshRack,
			Discovered = refreshIndex,
			IndexClaimed = refreshIndex,
			Powers = refreshPowers,
			Loadout = refreshPowers,
			PowerSlots = refreshPowers,
			Rebirths = refreshRebirth,
		} :: { [string]: () -> () }
	do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
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
	indexBadge = Theme.badge(indexButton)
	local moreFrame, moreBody = Theme.shell("More", "More", Theme.Cyan, "More", 460, 580)
	table.insert(panels, moreFrame)
	local moreList = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ZIndex = 5,
	}, moreBody)
	Ui.new(
		"UIPadding",
		{ PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) },
		moreList
	)
	Ui.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, moreList)
	local moreOrder = { Knives = 1, Players = 2, Powers = 3, Rebirth = 4, Stats = 5 }
	local moreColors = {
		Knives = Theme.Gold,
		Players = Theme.Cyan,
		Powers = Color3.fromRGB(255, 148, 28),
		Rebirth = Theme.Purple,
		Stats = Theme.Green,
	}
	local function moreButton(name: string, icon: string, frame: Frame, refresh: () -> ())
		Theme.button(moreList, name, moreColors[name], {
			Name = name,
			LayoutOrder = moreOrder[name],
			Size = UDim2.new(1, -6, 0, 60),
			ZIndex = 8,
		}, function()
			refresh()
			toggle(frame)
		end, icon)
	end
	moreButton("Knives", "Katana", knivesFrame, refreshRack)
	moreButton("Powers", "Speed", powersFrame, refreshPowers)
	moreButton("Rebirth", "Rebirth", rebirthFrame, refreshRebirth)

	-- PLAYERS: everyone here, with a Team Up and a Trade button each (+ invite friends) -------------
	local playersFrame, playersBody = panel("Players", Color3.fromRGB(90, 200, 255), "👥")
	table.insert(panels, playersFrame)
	local playersHint = Ui.label({
		Size = UDim2.new(1, 0, 0, 44),
		Text = "🤝 Team up: you're picked together in Double Trouble rounds (both Murderers or both Sheriffs) and share steals. 👥 Friends here = +10% cash each!",
		TextColor3 = Color3.fromRGB(220, 230, 255),
		TextWrapped = true,
		ZIndex = 6,
	}, playersBody)
	playersHint.TextScaled = true
	local playersList = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		BackgroundTransparency = 1,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 5,
	}, playersBody)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, playersList)
	local function refreshPlayers()
		for _, child in playersList:GetChildren() do
			if child:IsA("Frame") or child:IsA("TextButton") or child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		Ui.button(
			{
				LayoutOrder = 0,
				Size = UDim2.new(1, -10, 0, 44),
				Text = "📨 Invite friends (+10% cash each!)",
				BackgroundColor3 = Color3.fromRGB(90, 200, 110),
				ZIndex = 6,
			},
			playersList,
			function()
				pcall(function()
					game:GetService("SocialService"):PromptGameInvite(player)
				end)
			end
		)
		local others = #Players:GetPlayers() - 1
		playersFrame:SetAttribute("PreferredHeight", math.min(650, 200 + math.max(1, others) * 100))
		if others == 0 then
			Ui.label({
				Text = "No other players here yet",
				Size = UDim2.new(1, -10, 0, 44),
				TextSize = 16,
				TextScaled = false,
				ZIndex = 6,
			}, playersList)
		end
		local partnerId = player:GetAttribute("Partner")
		for i, other in Players:GetPlayers() do
			if other == player then
				continue
			end
			local row = new("Frame", {
				LayoutOrder = i,
				Size = UDim2.new(1, -10, 0, 96),
				BackgroundColor3 = Color3.fromRGB(44, 38, 58),
				ZIndex = 6,
			}, playersList)
			Ui.corner(row, 10)
			local teammate = partnerId == other.UserId
			Ui.label({
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.new(1, -20, 0, 32),
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = (if teammate then "🤝 " else "") .. other.DisplayName,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = if teammate then Color3.fromRGB(120, 255, 140) else Color3.new(1, 1, 1),
				ZIndex = 7,
			}, row)
			Ui.button(
				{
					AnchorPoint = Vector2.new(1, 1),
					Position = UDim2.new(0.5, -6, 1, -8),
					Size = UDim2.new(0.5, -16, 0, 44),
					Text = if teammate then "Leave team" else "🤝 Team up",
					BackgroundColor3 = if teammate then Color3.fromRGB(200, 80, 80) else Color3.fromRGB(80, 170, 255),
					ZIndex = 7,
				},
				row,
				function()
					if teammate then
						Remotes.TeamUp:FireServer("Leave")
					else
						Remotes.TeamUp:FireServer("Invite", other.UserId)
					end
				end
			)
			Ui.button(
				{
					AnchorPoint = Vector2.new(1, 1),
					Position = UDim2.new(1, -6, 1, -8),
					Size = UDim2.new(0.5, -16, 0, 44),
					Text = "🔁 Trade",
					BackgroundColor3 = Color3.fromRGB(240, 170, 60),
					ZIndex = 7,
				},
				row,
				function()
					Remotes.Trade:InvokeServer("Request", other.UserId)
				end
			)
		end
	end
	moreButton("Players", "Players", playersFrame, refreshPlayers)
	local statsFrame, statsBody = panel("Stats", Color3.fromRGB(87, 202, 150), "📊")
	table.insert(panels, statsFrame)
	local detailsScroll = new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -56),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		ZIndex = 5,
	}, statsBody)
	local statsText = Ui.label({
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextScaled = false,
		TextSize = 18,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 6,
	}, detailsScroll)
	local blurButton = Ui.button(
		{
			Name = "MenuBlur",
			Text = "Menu blur: OFF",
			Position = UDim2.new(0, 0, 1, -48),
			Size = UDim2.new(1, -8, 0, 44),
			ZIndex = 6,
		},
		statsBody,
		function()
			if Ui.Menu.CanBlur() then
				Ui.gui:SetAttribute("MenuBlurEnabled", not Ui.gui:GetAttribute("MenuBlurEnabled"))
			end
		end
	)
	local function refreshDetails()
		statsText.Text = `Income: ${Ui.abbreviate(player:GetAttribute("Income") or 0)}/s\nHeat: {player:GetAttribute(
			"Heat"
		) or 0}/10\nWalk speed: {math.floor(GameConfig.WalkSpeedFor((player:GetAttribute("Speed") or 0) :: number))}\nWall level: {player:GetAttribute(
			"WallLevel"
		) or 0}\nLuck: {player:GetAttribute("Luck") or 0}\nRebirths: {player:GetAttribute("Rebirths") or 0}\nFriend boost: +{(player:GetAttribute(
			"FriendsHere"
		) or 0) * 10}%\n\nServer goal: {ReplicatedStorage:GetAttribute("GoalText") or "None"} ({ReplicatedStorage:GetAttribute(
			"GoalProgress"
		) or 0}/{ReplicatedStorage:GetAttribute("GoalNeed") or 1})`
		local now = workspace:GetServerTimeNow()
		local boost = player:GetAttribute("BoostUntil")
		local luck = ReplicatedStorage:GetAttribute("ServerLuckUntil")
		statsText.Text ..= `\nShield: {if player:GetAttribute("Shielded")
			then Ui.clock(player:GetAttribute("ShieldLeft") or 0)
			else "None"}\nCash boost: {if type(boost) == "number" and boost > now then Ui.clock(boost - now) else "None"}\nServer luck: {if type(
				luck
			)
					== "number"
				and luck > now
			then Ui.clock(luck - now)
			else "None"}`
		blurButton.Text = if Ui.Menu.CanBlur()
			then (if Ui.gui:GetAttribute("MenuBlurEnabled") then "Menu blur: ON" else "Menu blur: OFF")
			else "Menu blur: requires High graphics"
	end
	moreButton("Stats", "Stats", statsFrame, refreshDetails)
	Ui.gui:GetAttributeChangedSignal("MenuBlurEnabled"):Connect(refreshDetails)
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
	menuButton(3, "More", Theme.Cyan, "More", moreFrame, function() end)
	player:GetAttributeChangedSignal("Partner"):Connect(function()
		if playersFrame.Visible then
			refreshPlayers()
		end
	end)

	-- Yes / No popups for team-up and trade requests -------------------------------------------------
	local function ask(text: string, onYes: () -> (), onNo: () -> ())
		local box = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 140),
			Size = UDim2.fromOffset(420, 110),
			BackgroundColor3 = DARK,
			ZIndex = 40,
		}, Ui.gui)
		Ui.corner(box, 14)
		Ui.fitMenu(box, Vector2.new(420, 120))
		Ui.registerMenu(box)
		Ui.stroke(box)
		Ui.label({
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.new(1, -20, 0, 44),
			Text = text,
			TextWrapped = true,
			ZIndex = 41,
		}, box)
		local function finish(yes: boolean)
			box:Destroy()
			if yes then
				onYes()
			else
				onNo()
			end
		end
		Ui.button(
			{
				Position = UDim2.new(0, 10, 1, -50),
				Size = UDim2.new(0.5, -15, 0, 44),
				Text = "✅ Yes",
				BackgroundColor3 = Color3.fromRGB(80, 200, 100),
				ZIndex = 41,
			},
			box,
			function()
				finish(true)
			end
		)
		Ui.button(
			{
				Position = UDim2.new(0.5, 5, 1, -50),
				Size = UDim2.new(0.5, -15, 0, 44),
				Text = "No",
				BackgroundColor3 = Color3.fromRGB(200, 80, 80),
				ZIndex = 41,
			},
			box,
			function()
				finish(false)
			end
		)
		task.delay(20, function()
			if box.Parent then
				finish(false)
			end
		end)
	end

	-- TRADE window ------------------------------------------------------------------------------------
	local tradeFrame, tradeBody = panel("Trade", Color3.fromRGB(240, 170, 60), "🔁")
	local tradeOffer: { string } = {}
	local tradeState: { [string]: any } = {}
	local tradeActive = false
	tradeFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not tradeFrame.Visible and tradeActive then
			tradeActive = false
			tradeOffer = {}
			task.spawn(function()
				Remotes.Trade:InvokeServer("Cancel")
			end)
		end
	end)
	local function tradeColumn(x: number, title: string): ScrollingFrame
		Ui.label({
			Position = UDim2.new(x, 4, 0, 0),
			Size = UDim2.new(0.5, -8, 0, 28),
			Text = title,
			ZIndex = 6,
		}, tradeBody)
		local list = new("ScrollingFrame", {
			Position = UDim2.new(x, 4, 0, 32),
			Size = UDim2.new(0.5, -8, 1, -100),
			BackgroundColor3 = Color3.fromRGB(40, 34, 52),
			ScrollBarThickness = 6,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			ZIndex = 6,
		}, tradeBody)
		Ui.corner(list, 10)
		new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)
		return list
	end
	local myList = tradeColumn(0, "Your knives (tap to offer, max 6)")
	local theirList = tradeColumn(0.5, "They offer")
	local tradeStatus = Ui.label({
		Position = UDim2.new(0, 4, 1, -64),
		Size = UDim2.new(0.5, -8, 0, 28),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 230, 140),
		ZIndex = 6,
	}, tradeBody)
	local readyButton = Ui.button(
		{
			Position = UDim2.new(0.5, 4, 1, -64),
			Size = UDim2.new(0.25, -6, 0, 56),
			Text = "Ready",
			BackgroundColor3 = Color3.fromRGB(80, 200, 100),
			ZIndex = 6,
		},
		tradeBody,
		function()
			Remotes.Trade:InvokeServer("Ready")
		end
	)
	Ui.button(
		{
			Position = UDim2.new(0.75, 2, 1, -64),
			Size = UDim2.new(0.25, -6, 0, 56),
			Text = "Cancel",
			BackgroundColor3 = Color3.fromRGB(200, 80, 80),
			ZIndex = 6,
		},
		tradeBody,
		function()
			tradeFrame.Visible = false
		end
	)
	local function itemRow(list: ScrollingFrame, item: string, order: number, picked: boolean, onTap: (() -> ())?)
		local row = Ui.button({
			LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, 44),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = Items.DisplayName(item),
			TextColor3 = Items.Color(item),
			BackgroundColor3 = if picked then Color3.fromRGB(80, 160, 90) else Color3.fromRGB(60, 54, 74),
			ZIndex = 7,
		}, list, onTap)
		local parsed = Items.Parse(item)
		if parsed and parsed.Perk and GameConfig.Perks[parsed.Perk] then
			row.Text ..= ` · {GameConfig.Perks[parsed.Perk].DisplayName}`
		end
	end
	local function drawTrade()
		for _, list in { myList, theirList } do
			for _, child in list:GetChildren() do
				if child:IsA("GuiButton") then
					child:Destroy()
				end
			end
		end
		local counted: { [string]: number } = {}
		for _, item in tradeOffer do
			counted[item] = (counted[item] or 0) + 1
		end
		for i, item in Ui.list(player:GetAttribute("Knives")) do
			local picked = (counted[item] or 0) > 0
			if picked then
				counted[item] -= 1
			end
			itemRow(myList, item, i, picked, function()
				local index = table.find(tradeOffer, item)
				if picked and index then
					table.remove(tradeOffer, index)
				elseif #tradeOffer < 6 then
					table.insert(tradeOffer, item)
				end
				Remotes.Trade:InvokeServer("Offer", tradeOffer)
			end)
		end
		for i, item in tradeState.Theirs or {} do
			itemRow(theirList, item, i, true, nil)
		end
		local countdown = tradeState.CountdownEnds
		tradeStatus.Text = if type(countdown) == "number"
			then `Swapping in {math.max(0, math.ceil(countdown - workspace:GetServerTimeNow()))}...`
			elseif tradeState.TheirReady then `{tradeState.OtherName or "They"} is ready!`
			else `Trading with {tradeState.OtherName or "?"}`
		readyButton.Text = if tradeState.MyReady then "Not ready" else "Ready"
	end
	Remotes.Effect.OnClientEvent:Connect(function(kind: string, a: any, b: any)
		if kind == "TeamInvite" and type(a) == "number" then
			ask(`🤝 {b} wants to team up with you!`, function()
				Remotes.TeamUp:FireServer("Accept", a)
			end, function()
				Remotes.TeamUp:FireServer("Decline", a)
			end)
		elseif kind == "TradeRequest" and type(a) == "number" then
			ask(`🔁 {b} wants to trade knives with you!`, function()
				Remotes.Trade:InvokeServer("Accept", a)
			end, function()
				Remotes.Trade:InvokeServer("Decline", a)
			end)
		elseif kind == "TradeState" and type(a) == "table" then
			tradeActive = true
			tradeState = a
			tradeOffer = table.clone(a.Mine or {})
			if not tradeFrame.Visible then
				for _, p in panels do
					p.Visible = false
				end
				tradeFrame.Visible = true
			end
			drawTrade()
		elseif kind == "TradeClosed" then
			tradeActive = false
			tradeFrame.Visible = false
			tradeState = {}
			tradeOffer = {}
		end
	end)
	-- Keep the countdown ticking
	task.spawn(function()
		while true do
			task.wait(0.25)
			if tradeFrame.Visible and type(tradeState.CountdownEnds) == "number" then
				drawTrade()
			end
		end
	end)
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
			{ Text = "Raid", Command = "Raid", Arg = nil, Color = Color3.fromRGB(230, 90, 40) },
			{ Text = "Case", Command = "Case", Arg = "Epic", Color = Color3.fromRGB(170, 90, 255) },
		}
		for _, spec in specs do
			Ui.button({ Text = spec.Text, BackgroundColor3 = spec.Color }, tests, function()
				Remotes.Debug:InvokeServer(spec.Command, spec.Arg)
			end)
		end
	end

	refreshRack()
	refreshIndex()
	refreshPowers()
	refreshRebirth()

	player:GetAttributeChangedSignal("InRound"):Connect(function()
		local inRound = player:GetAttribute("InRound") == true
		column.Visible = not inRound
		if inRound then
			for _, p in panels do
				p.Visible = false
			end
		end
	end)

	-- Keyboard / gamepad shortcuts: K = knives, B = powers (gamepad: L1 / R1)
	ContextActionService:BindAction("ToggleKnives", function(_, state)
		if state == Enum.UserInputState.Begin and column.Visible then
			refreshRack()
			toggle(knivesFrame)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.K, Enum.KeyCode.ButtonL1)

	-- Shopkeepers (server ShopNPCs): stand on the glowing ring in front of a stall and its shop
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
			local frame = if which == "Shop" then shopFrame elseif which == "Powers" then powersFrame else nil
			if frame then
				if which == "Powers" then
					refreshPowers()
				end
				if not frame.Visible then
					toggle(frame)
				end
				openedFrame = frame
			end
		end
	end)
end

return Menus
