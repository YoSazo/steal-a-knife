--!strict
-- The left-side menu buttons (chunky, Steal An Egg style) and their panels:
--   Shop     sealed cases for cash, with the odds of everything inside
--   Index    every knife in the game: silhouettes until you own one, and a reward to claim for each
--   Knives   your wall (equip the one you fight / murder with, sell the rest)
--   Powers   buy, upgrade and equip Innocent Powers
--   Rebirth  start over for a permanent multiplier
-- Knife cards show a live 3D model in a ViewportFrame built from the same KnifeModel as the game.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Items = require(Shared:WaitForChild("Items"))
local Knives = require(Shared.Config:WaitForChild("Knives"))
local KnifeModel = require(Shared:WaitForChild("KnifeModel"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local new = Ui.new

local Menus = {}

local DARK = Color3.fromRGB(28, 24, 38)

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
		elseif frame.Visible then
			model:PivotTo(model:GetPivot() * CFrame.Angles(0, dt * 0.8, 0))
		end
	end
end)

local function panel(title: string, color: Color3, icon: string): (Frame, Frame)
	local frame = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(700, 470),
		BackgroundColor3 = DARK,
		Visible = false,
		ZIndex = 5,
	}, Ui.gui)
	Ui.corner(frame, 18)
	new("UIStroke", { Thickness = 5, Color = Color3.fromRGB(16, 12, 22) }, frame)
	-- Faint diagonal stripes in the background
	new("UIGradient", {
		Rotation = 45,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 215)),
	}, frame)
	local header = new("Frame", {
		Size = UDim2.new(1, 0, 0, 64),
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
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 1, -72),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, frame)
	Ui.padding(body, 14, 8)
	-- Pop in
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			local scale = frame:FindFirstChildOfClass("UIScale") or new("UIScale", {}, frame)
			scale.Scale = 0.85
			TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end)
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
		TextColor3 = color or Color3.new(1, 1, 1),
		ZIndex = 6,
	}, parent)
	Ui.textStroke(label, 1.5)
	return label
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
	local column = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.4, 0),
		Size = UDim2.fromOffset(190, 330),
		BackgroundTransparency = 1,
	}, Ui.gui)
	new("UIListLayout", { Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder }, column)

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
	local shopFrame, shopBody = panel("Case Shop", Color3.fromRGB(70, 200, 90), "🛒")
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
	-- Odds shared by every case
	local mutationTotal, sizeTotal = 0, 0
	for _, m in Items.Mutations do
		mutationTotal += m.Weight
	end
	for _, s in Items.Sizes do
		sizeTotal += s.Weight
	end
	local function pct(n: number): string
		if n >= 10 then
			return `{math.floor(n + 0.5)}%`
		end
		return string.format("%.1f%%", n)
	end
	for order, entry in GameConfig.CaseShop do
		local color = Knives.RarityColors[entry.Rarity]
		local row = new("Frame", {
			LayoutOrder = order,
			Size = UDim2.new(1, -12, 0, 150),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 5,
		}, shopList)
		Ui.corner(row, 14)
		Ui.gradient(row, color:Lerp(DARK, 0.3), color:Lerp(DARK, 0.8))
		new("UIStroke", { Thickness = 3, Color = color }, row)
		viewport(row, function()
			return KnifeModel.BuildCase(entry.Rarity, true)
		end, false, UDim2.fromOffset(130, 130)).Position =
			UDim2.fromOffset(6, 10)
		local title = Ui.label({
			Position = UDim2.fromOffset(140, 6),
			Size = UDim2.fromOffset(300, 36),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = `{entry.Rarity:upper()} CASE`,
			TextColor3 = color,
			ZIndex = 6,
		}, row)
		Ui.textStroke(title, 2.5)
		-- What's inside, with chances
		local pool = Knives.ByRarity[entry.Rarity]
		local nextRarity = Knives.Rarities[(table.find(Knives.Rarities, entry.Rarity) or 1) + 1]
		local inside = {}
		for _, knife in pool do
			table.insert(inside, `{knife.DisplayName} {pct((if nextRarity then 96 else 100) / #pool)}`)
		end
		if nextRarity then
			table.insert(inside, `any {nextRarity} 4%`)
		end
		local odds = Ui.label({
			Position = UDim2.fromOffset(140, 42),
			Size = UDim2.fromOffset(370, 40),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextScaled = false,
			TextSize = 15,
			TextWrapped = true,
			Text = table.concat(inside, "  ·  "),
			ZIndex = 6,
		}, row)
		Ui.textStroke(odds, 1)
		local mutationBits = {}
		for _, m in Items.Mutations do
			if m.Rank > 0 then
				table.insert(
					mutationBits,
					`<font color="#{m.Color:ToHex()}">{m.DisplayName} {pct(m.Weight / mutationTotal * 100)}</font>`
				)
			end
		end
		local sizeBits = {}
		for _, s in Items.Sizes do
			if s.Rank > 0 then
				table.insert(sizeBits, `{s.DisplayName} {pct(s.Weight / sizeTotal * 100)}`)
			end
		end
		local extra = Ui.label({
			Position = UDim2.fromOffset(140, 86),
			Size = UDim2.fromOffset(370, 52),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextScaled = false,
			TextSize = 15,
			TextWrapped = true,
			RichText = true,
			Text = `Mutations: {table.concat(mutationBits, " · ")}\nSizes: {table.concat(sizeBits, " · ")}`,
			ZIndex = 6,
		}, row)
		Ui.textStroke(extra, 1)
		Ui.chunky(
			{
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(140, 70),
				BackgroundColor3 = Color3.fromRGB(70, 200, 90),
				Text = `${Ui.abbreviate(entry.Cost)}`,
				ZIndex = 7,
			},
			row,
			nil,
			function()
				Remotes.Purchase:InvokeServer(`Case:{entry.Rarity}`)
			end
		)
	end

	-- INDEX: every knife, rewards to claim ---------------------------------------------------------
	local indexFrame, indexBody = panel("Index", Color3.fromRGB(60, 150, 255), "📖")
	table.insert(panels, indexFrame)
	local indexTop = new("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, ZIndex = 5 }, indexBody)
	local progressBack = new("Frame", {
		Size = UDim2.new(0.55, 0, 0, 40),
		Position = UDim2.fromOffset(0, 4),
		BackgroundColor3 = Color3.fromRGB(16, 12, 22),
		ZIndex = 5,
	}, indexTop)
	Ui.corner(progressBack, 10)
	local progressFill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(90, 220, 90),
		ZIndex = 6,
	}, progressBack)
	Ui.corner(progressFill, 10)
	local progressText = Ui.label({ Size = UDim2.fromScale(1, 1), Text = "", ZIndex = 7 }, progressBack)
	Ui.textStroke(progressText, 2)
	local claimAll = Ui.chunky(
		{
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 2),
			Size = UDim2.new(0.42, 0, 0, 44),
			BackgroundColor3 = Color3.fromRGB(60, 150, 255),
			Text = "CLAIM ALL",
			ZIndex = 6,
		},
		indexTop,
		nil,
		function()
			Remotes.ClaimIndex:InvokeServer("All")
		end
	)
	local indexHolder = new("Frame", {
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, indexBody)
	local indexGrid = scrollGrid(indexHolder, Vector2.new(150, 186))

	-- KNIVES: your wall ----------------------------------------------------------------------------
	local knivesFrame, knivesBody = panel("My Knives", Color3.fromRGB(130, 80, 230), "🔪")
	table.insert(panels, knivesFrame)
	local rackGrid = scrollGrid(knivesBody, Vector2.new(150, 214))

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
	local powersGrid = scrollGrid(powersHolder, Vector2.new(205, 170))

	-- REBIRTH --------------------------------------------------------------------------------------
	local rebirthFrame, rebirthBody = panel("Rebirth", Color3.fromRGB(240, 190, 50), "♻️")
	table.insert(panels, rebirthFrame)
	local rebirthInfo = Ui.label({
		Size = UDim2.new(1, 0, 0, 250),
		TextScaled = false,
		TextSize = 22,
		TextWrapped = true,
		RichText = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
		ZIndex = 6,
	}, rebirthBody)
	Ui.textStroke(rebirthInfo, 1.5)
	local rebirthButton = Ui.chunky(
		{
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.fromOffset(360, 74),
			BackgroundColor3 = Color3.fromRGB(240, 190, 50),
			Text = "REBIRTH",
			ZIndex = 7,
		},
		rebirthBody,
		nil,
		function()
			Remotes.Purchase:InvokeServer("Rebirth")
		end
	)

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
			cardText(empty, 20, 120, "Kill watchmen in the arena and carry their cases home!")
			return
		end
		for index, item in owned do
			local parsed = Items.Parse(item)
			if not parsed then
				continue
			end
			local knife = parsed.Knife
			local c = card(rackGrid, index, Items.Color(item))
			viewport(c, function()
				return KnifeModel.Build(item, true)
			end, false, UDim2.fromScale(1, 0.45))
			cardText(c, 88, 20, Items.DisplayName(item), Items.Color(item))
			cardText(c, 108, 16, `{knife.Rarity} · Dmg {Items.Damage(item)}`, Knives.RarityColors[knife.Rarity])
			cardText(c, 124, 18, `+${Ui.abbreviate(Items.Income(item))}/s`, Color3.fromRGB(120, 255, 140))
			local isEquipped = item == equipped
			smallButton(
				c,
				UDim.new(1, -64),
				28,
				if isEquipped then Color3.fromRGB(70, 200, 100) else Color3.fromRGB(80, 150, 240),
				if isEquipped then "Equipped" else "Equip",
				function()
					Remotes.Equip:InvokeServer(if isEquipped then "" else item)
				end
			)
			smallButton(
				c,
				UDim.new(1, -32),
				26,
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
		clearGrid(indexGrid)
		local found, claimed = {}, {}
		for _, name in Ui.list(player:GetAttribute("Discovered")) do
			found[name] = true
		end
		for _, name in Ui.list(player:GetAttribute("IndexClaimed")) do
			claimed[name] = true
		end
		local count, claimable = 0, 0
		for index, knife in Knives.List do
			local known = found[knife.Name] == true
			count += if known then 1 else 0
			local color = Knives.RarityColors[knife.Rarity]
			local c = card(indexGrid, index, if known then color else Color3.fromRGB(70, 70, 85))
			viewport(c, function()
				return KnifeModel.Build(knife.Name, true)
			end, not known, UDim2.fromScale(1, 0.5))
			cardText(c, 94, 22, if known then knife.DisplayName else "???", color)
			cardText(c, 116, 16, knife.Rarity, Color3.fromRGB(210, 210, 220))
			local reward = GameConfig.IndexRewards[knife.Rarity]
			if known and not claimed[knife.Name] then
				claimable += 1
				smallButton(
					c,
					UDim.new(1, -38),
					32,
					Color3.fromRGB(90, 210, 90),
					`CLAIM $${Ui.abbreviate(reward.Cash)}`,
					function()
						Remotes.ClaimIndex:InvokeServer(knife.Name)
					end
				)
			else
				cardText(
					c,
					140,
					32,
					if known
						then "✔ Claimed"
						else `Reward: ${Ui.abbreviate(reward.Cash)} + {Ui.abbreviate(reward.Speed)}⚡`,
					if known then Color3.fromRGB(120, 230, 150) else Color3.fromRGB(180, 180, 195)
				)
			end
		end
		progressFill.Size = UDim2.fromScale(count / #Knives.List, 1)
		progressText.Text = `{count}/{#Knives.List} found`
		claimAll.Visible = claimable > 0
		local label = claimAll:FindFirstChild("Label") :: TextLabel?
		if label then
			label.Text = `CLAIM ALL ({claimable})`
		end
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
		loadoutLabel.Text = `Loadout {#loadout}/{slots}  ·  keys Z X C`
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
				UDim.new(1, -62),
				28,
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
					UDim.new(1, -31),
					26,
					if equipped then Color3.fromRGB(70, 200, 100) else Color3.fromRGB(80, 150, 240),
					if equipped then "Equipped" else "Equip",
					function()
						Remotes.Power:InvokeServer(if equipped then "Unequip" else "Equip", power.Id)
					end
				)
			end
		end
	end

	local function refreshRebirth()
		local rebirths = player:GetAttribute("Rebirths") or 0
		local cash = player:GetAttribute("Cash") or 0
		local cost = GameConfig.RebirthCost(rebirths)
		local config = GameConfig.Rebirth
		local nextTitle = GameConfig.RebirthTitle(rebirths + 1) or ""
		local current = 1 + rebirths * config.IncomeBonus
		local nextMult = 1 + (rebirths + 1) * config.IncomeBonus
		rebirthInfo.Text = table.concat({
			`<font size="30" color="#FFD84A">Rebirth {rebirths} → {rebirths + 1}</font>`,
			`Become a <b>{nextTitle}</b>`,
			"",
			`<font color="#78FF8C">Income x{current} → x{nextMult}</font>`,
			`<font color="#8CC8FF">Speed training +{math.floor((rebirths + 1) * config.SpeedBonus * 100)}%</font>`,
			`<font color="#FF9CF0">Case luck +{math.floor((rebirths + 1) * config.LuckBonus * 100)}%</font>`,
			"",
			`<font color="#FF8080">Resets: cash, knives, mounts, Speed, Haunted Wheel, vault walls</font>`,
			`<font color="#C8C8D8">Keeps: powers, Index, tickets, stats</font>`,
		}, "\n")
		local label = rebirthButton:FindFirstChild("Label") :: TextLabel?
		if label then
			label.Text = if cash >= cost
				then `REBIRTH  ($ {Ui.abbreviate(cost)})`
				else `Need ${Ui.abbreviate(cost)}  ({math.floor(cash / cost * 100)}%)`
		end
	end

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
		local button = Ui.chunky(
			{
				LayoutOrder = order,
				Size = UDim2.new(1, 0, 0, 56),
				BackgroundColor3 = color,
				Text = text,
			},
			column,
			icon,
			function()
				refresh()
				toggle(frame)
			end
		)
		return button
	end
	menuButton(1, "Shop", Color3.fromRGB(70, 200, 90), "🛒", shopFrame, function() end)
	local indexButton = menuButton(2, "Index", Color3.fromRGB(60, 150, 255), "📖", indexFrame, refreshIndex)
	indexBadge = Ui.badge(indexButton)
	menuButton(3, "Knives [K]", Color3.fromRGB(130, 80, 230), "🔪", knivesFrame, refreshRack)
	menuButton(4, "Powers [B]", Color3.fromRGB(240, 130, 40), "⚡", powersFrame, refreshPowers)
	menuButton(5, "Rebirth", Color3.fromRGB(240, 190, 50), "♻️", rebirthFrame, refreshRebirth)
	if RunService:IsStudio() then
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
	ContextActionService:BindAction("ToggleShop", function(_, state)
		if state == Enum.UserInputState.Begin and column.Visible then
			refreshPowers()
			toggle(powersFrame)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.B, Enum.KeyCode.ButtonR1)
end

return Menus
