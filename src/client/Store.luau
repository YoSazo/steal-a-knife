--!strict
-- The Robux side of the HUD (Config/Monetization, server: MonetizationService):
--   * the 💎 STORE button and panel: passes, boosts, and Robux cases with their full odds
--   * contextual offers (Remotes.Offer): a card that slides in when you hit something a product
--     fixes - short on cash, wall full, gate under attack - then gets out of the way
--   * "Instant Repair" beside the Repair button while your gate is damaged
--   * the Server Luck timer while someone's luck boost is running
-- Purchases go through MarketplaceService; in Studio, anything without an id is faked for testing.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Effects = require(script.Parent.Effects)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Monetization = require(Shared.Config:WaitForChild("Monetization"))
local Items = require(Shared:WaitForChild("Items"))
local Knives = require(Shared.Config:WaitForChild("Knives"))
local Sounds = require(Shared.Config:WaitForChild("Sounds"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local new = Ui.new

local Store = {}

local DARK = Color3.fromRGB(28, 24, 38)
local ROBUX = Color3.fromRGB(0, 176, 111)
-- Where offer cards settle: left of the right-hand buttons (higher on phones, above the thumbs)
local OFFER_X = if Ui.Phone then -190 else -262
local OFFER_Y = if Ui.Phone then 0.46 else 0.62

-- Buying ---------------------------------------------------------------------------------------

local function buy(kind: string, key: string)
	local entry: { Id: number } = if kind == "Pass"
		then Monetization.PassByKey[key] :: any
		else Monetization.ProductByKey[key] :: any
	if not entry then
		return
	end
	if entry.Id > 0 then
		if kind == "Pass" then
			MarketplaceService:PromptGamePassPurchase(player, entry.Id)
		else
			MarketplaceService:PromptProductPurchase(player, entry.Id)
		end
	elseif RunService:IsStudio() then
		Remotes:WaitForChild("StoreTest"):InvokeServer(kind, key)
	end
end

local function kindOf(key: string): string
	return if Monetization.PassByKey[key] then "Pass" else "Product"
end

local function owned(key: string): boolean
	return player:GetAttribute("Pass_" .. key) == true or player:GetAttribute("Bought_" .. key) == true
end

-- What a cash pack is worth to *you* right now
local function cashFor(product: Monetization.Product): number?
	if not product.Cash then
		return nil
	end
	local income = (player:GetAttribute("Income") or 0) :: number
	return GameConfig.Pay(product.Cash, income)
end

-- A green Robux price button
local function priceButton(parent: Instance, price: number, props: { [string]: any }, onClick: () -> ()): TextButton
	props.BackgroundColor3 = ROBUX
	props.Text = `R$ {price}`
	local button = Ui.chunky(props, parent, nil, onClick)
	return button
end

-- Case odds (the same numbers the Case Shop shows) -----------------------------------------------

local function pct(n: number): string
	if n >= 10 then
		return `{math.floor(n + 0.5)}%`
	end
	return string.format("%.1f%%", n)
end

local function caseOdds(rarity: string): string
	local pool = Knives.ByRarity[rarity]
	local nextRarity = Knives.Rarities[(table.find(Knives.Rarities, rarity) or 1) + 1]
	local inside = {}
	for _, knife in pool do
		table.insert(inside, `{knife.DisplayName} {pct((if nextRarity then 96 else 100) / #pool)}`)
	end
	if nextRarity then
		table.insert(inside, `any {nextRarity} 4%`)
	end
	local mutationTotal, sizeTotal = 0, 0
	for _, m in Items.Mutations do
		mutationTotal += m.Weight
	end
	for _, s in Items.Sizes do
		sizeTotal += s.Weight
	end
	local mutations, sizes = {}, {}
	for _, m in Items.Mutations do
		if m.Rank > 0 then
			table.insert(mutations, `{m.DisplayName} {pct(m.Weight / mutationTotal * 100)}`)
		end
	end
	for _, s in Items.Sizes do
		if s.Rank > 0 then
			table.insert(sizes, `{s.DisplayName} {pct(s.Weight / sizeTotal * 100)}`)
		end
	end
	return `{table.concat(inside, " · ")}\nMutations: {table.concat(mutations, " · ")}\nSizes: {table.concat(
		sizes,
		" · "
	)}`
end

-- The Store panel --------------------------------------------------------------------------------

local function sectionTitle(parent: Instance, order: number, text: string)
	local label = Ui.label({
		LayoutOrder = order,
		Size = UDim2.new(1, -12, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		TextColor3 = Color3.fromRGB(255, 220, 110),
		ZIndex = 6,
	}, parent)
	Ui.textStroke(label, 2.5)
end

local function cardFrame(parent: Instance, order: number, size: UDim2, color: Color3): Frame
	local frame = new("Frame", {
		LayoutOrder = order,
		Size = size,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 5,
	}, parent)
	Ui.corner(frame, 12)
	Ui.gradient(frame, color:Lerp(DARK, 0.3), color:Lerp(DARK, 0.78))
	new("UIStroke", { Thickness = 3, Color = color }, frame)
	return frame
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	props.ZIndex = props.ZIndex or 6
	local label = Ui.label(props, parent)
	Ui.textStroke(label, 1.5)
	return label
end

function Store.Init()
	local gui = Ui.gui

	-- Panel shell (same look as the other menus)
	local frame = new("Frame", {
		Name = "Store",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(740, 500),
		BackgroundColor3 = DARK,
		Visible = false,
		ZIndex = 5,
	}, gui)
	Ui.corner(frame, 18)
	new("UIStroke", { Thickness = 5, Color = Color3.fromRGB(16, 12, 22) }, frame)
	local header =
		new("Frame", { Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 5 }, frame)
	Ui.corner(header, 18)
	Ui.gradient(header, Color3.fromRGB(80, 220, 160), Color3.fromRGB(20, 140, 100))
	local title = Ui.label({
		Size = UDim2.new(1, -130, 1, -12),
		Position = UDim2.fromOffset(20, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "💎 Store",
		ZIndex = 6,
	}, header)
	Ui.textStroke(title, 3)
	Ui.chunky(
		{
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
	local list = new("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 72),
		Size = UDim2.new(1, -24, 1, -82),
		BackgroundTransparency = 1,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 5,
	}, frame)
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)

	local refreshers: { () -> () } = {}

	-- Starter Pack banner (only until it's bought)
	local starter = Monetization.ProductByKey.Starter
	local starterRow = cardFrame(list, 1, UDim2.new(1, -12, 0, 96), starter.Color)
	text(starterRow, {
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -200, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = `{starter.Icon} {starter.Name:upper()}  ·  once per player`,
	})
	text(starterRow, {
		Position = UDim2.fromOffset(14, 50),
		Size = UDim2.new(1, -200, 0, 38),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = false,
		TextSize = 16,
		TextWrapped = true,
		Text = starter.Description,
	})
	priceButton(starterRow, starter.Price, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(160, 64),
		ZIndex = 7,
	}, function()
		buy("Product", "Starter")
	end)
	table.insert(refreshers, function()
		starterRow.Visible = not owned("Starter")
	end)

	-- Passes
	sectionTitle(list, 2, "⭐ GAME PASSES (forever)")
	local passGrid = new("Frame", {
		LayoutOrder = 3,
		Size = UDim2.new(1, -12, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, list)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(222, 196),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, passGrid)
	for i, pass in Monetization.Passes do
		local card = cardFrame(passGrid, i, UDim2.new(), pass.Color)
		text(card, { Position = UDim2.fromOffset(6, 4), Size = UDim2.new(1, -12, 0, 46), Text = pass.Icon })
		text(card, { Position = UDim2.fromOffset(6, 50), Size = UDim2.new(1, -12, 0, 28), Text = pass.Name })
		text(card, {
			Position = UDim2.fromOffset(8, 80),
			Size = UDim2.new(1, -16, 0, 56),
			TextScaled = false,
			TextSize = 14,
			TextWrapped = true,
			Text = pass.Description,
		})
		local button = priceButton(card, pass.Price, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -20, 0, 44),
			ZIndex = 7,
		}, function()
			if not owned(pass.Key) then
				buy("Pass", pass.Key)
			end
		end)
		table.insert(refreshers, function()
			local label = button:FindFirstChild("Label") :: TextLabel?
			if label then
				label.Text = if owned(pass.Key) then "✓ OWNED" else `R$ {pass.Price}`
			end
		end)
	end

	-- Boosts
	sectionTitle(list, 4, "⚡ BOOSTS")
	local boostGrid = new("Frame", {
		LayoutOrder = 5,
		Size = UDim2.new(1, -12, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, list)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(222, 172),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, boostGrid)
	local boosts =
		{ "ServerLuck", "CashSmall", "CashMedium", "CashBig", "Mount", "Tickets", "ChestRefill", "BloodMoon" }
	for i, key in boosts do
		local product = Monetization.ProductByKey[key]
		local card = cardFrame(boostGrid, i, UDim2.new(), product.Color)
		text(card, {
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.new(1, -12, 0, 30),
			Text = `{product.Icon} {product.Name}`,
		})
		local desc = text(card, {
			Position = UDim2.fromOffset(8, 38),
			Size = UDim2.new(1, -16, 0, 76),
			TextScaled = false,
			TextSize = 14,
			TextWrapped = true,
			Text = product.Description,
		})
		priceButton(card, product.Price, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -20, 0, 44),
			ZIndex = 7,
		}, function()
			buy("Product", key)
		end)
		if product.Cash then
			-- Show what it's worth to them today
			table.insert(refreshers, function()
				desc.Text = `{product.Description}\n= ${Ui.abbreviate(cashFor(product) or 0)} for you`
			end)
		end
	end

	-- Robux cases, odds included
	sectionTitle(list, 6, "📦 CASES (odds shown)")
	for i, key in { "CaseEpic", "CaseLegendary", "CaseGodly" } do
		local product = Monetization.ProductByKey[key]
		local rarity = product.Case :: string
		local color = Knives.RarityColors[rarity] or product.Color
		local row = cardFrame(list, 6 + i, UDim2.new(1, -12, 0, 118), color)
		text(row, {
			Position = UDim2.fromOffset(14, 6),
			Size = UDim2.new(1, -200, 0, 32),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = `{rarity:upper()} CASE`,
			TextColor3 = color,
		})
		text(row, {
			Position = UDim2.fromOffset(14, 40),
			Size = UDim2.new(1, -200, 0, 72),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextScaled = false,
			TextSize = 13,
			TextWrapped = true,
			Text = caseOdds(rarity),
		})
		priceButton(row, product.Price, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(150, 64),
			ZIndex = 7,
		}, function()
			buy("Product", key)
		end)
	end

	local function refresh()
		for _, fn in refreshers do
			fn()
		end
	end
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			refresh()
			local scale = frame:FindFirstChildOfClass("UIScale") or new("UIScale", {}, frame)
			scale.Scale = 0.85
			TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end)
	player.AttributeChanged:Connect(function(name: string)
		if frame.Visible and (name:sub(1, 5) == "Pass_" or name:sub(1, 7) == "Bought_" or name == "Income") then
			refresh()
		end
	end)

	-- The 💎 STORE button: top left, above the menu column
	local storeButton = Ui.chunky(
		{
			Name = "StoreButton",
			Position = if Ui.Phone then UDim2.fromOffset(10, 58) else UDim2.fromOffset(14, 62),
			Size = if Ui.Phone then UDim2.fromOffset(60, 52) else UDim2.fromOffset(190, 58),
			BackgroundColor3 = ROBUX,
			Text = "STORE",
		},
		gui,
		"💎",
		function()
			frame.Visible = not frame.Visible
		end
	)
	if Ui.Phone then
		Ui.iconOnly(storeButton)
	end
	player:GetAttributeChangedSignal("InRound"):Connect(function()
		local inRound = player:GetAttribute("InRound") == true
		storeButton.Visible = not inRound
		if inRound then
			frame.Visible = false
		end
	end)

	-- Contextual offers ---------------------------------------------------------------------------
	local offerCard: Frame? = nil
	local function closeOffer()
		local card = offerCard
		offerCard = nil
		if card then
			TweenService:Create(card, TweenInfo.new(0.25), { Position = UDim2.new(1, 360, OFFER_Y, 0) }):Play()
			task.delay(0.3, function()
				card:Destroy()
			end)
		end
	end
	Remotes:WaitForChild("Offer").OnClientEvent:Connect(function(key: string, reason: string)
		if player:GetAttribute("InRound") or owned(key) then
			return
		end
		local kind = kindOf(key)
		local entry: { Name: string, Icon: string, Price: number, Color: Color3 } = if kind == "Pass"
			then Monetization.PassByKey[key] :: any
			else Monetization.ProductByKey[key] :: any
		if not entry then
			return
		end
		closeOffer()
		local card = new("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 360, OFFER_Y, 0),
			Size = UDim2.fromOffset(330, 150),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 20,
		}, gui)
		offerCard = card
		Ui.corner(card, 14)
		Ui.gradient(card, entry.Color:Lerp(DARK, 0.25), entry.Color:Lerp(DARK, 0.75))
		new("UIStroke", { Thickness = 3.5, Color = Color3.fromRGB(16, 12, 22) }, card)
		text(card, {
			Position = UDim2.fromOffset(10, 6),
			Size = UDim2.new(1, -56, 0, 32),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = `{entry.Icon} {entry.Name}`,
			ZIndex = 21,
		})
		text(card, {
			Position = UDim2.fromOffset(10, 40),
			Size = UDim2.new(1, -20, 0, 46),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = false,
			TextSize = 16,
			TextWrapped = true,
			Text = reason,
			ZIndex = 21,
		})
		priceButton(card, entry.Price, {
			Position = UDim2.fromOffset(10, 94),
			Size = UDim2.fromOffset(190, 46),
			ZIndex = 22,
		}, function()
			buy(kind, key)
			closeOffer()
		end)
		Ui.button({
			Position = UDim2.fromOffset(210, 94),
			Size = UDim2.fromOffset(110, 46),
			BackgroundColor3 = Color3.fromRGB(80, 76, 96),
			Text = "No thanks",
			ZIndex = 22,
		}, card, closeOffer)
		Effects.Sound(Sounds.Reveal, nil, 0.4)
		TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back), {
			Position = UDim2.new(1, OFFER_X, OFFER_Y, 0),
		}):Play()
		task.delay(14, function()
			if offerCard == card then
				closeOffer()
			end
		end)
	end)
	player:GetAttributeChangedSignal("InRound"):Connect(function()
		if player:GetAttribute("InRound") then
			closeOffer()
		end
	end)

	-- Instant Repair, beside the Repair button while your gate is damaged -------------------------
	local repair = Monetization.ProductByKey.Repair
	local instant = priceButton(gui, repair.Price, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 150, 1, -230),
		Size = UDim2.fromOffset(170, 58),
		Visible = false,
	}, function()
		buy("Product", "Repair")
	end)
	local instantLabel = instant:FindFirstChild("Label") :: TextLabel?
	if instantLabel then
		instantLabel.Text = `🔧 Instant  R$ {repair.Price}`
	end
	gui:GetAttributeChangedSignal("RepairVisible"):Connect(function()
		instant.Visible = gui:GetAttribute("RepairVisible") == true
	end)

	-- Server Luck timer ----------------------------------------------------------------------------
	local luckPill = new("Frame", {
		AnchorPoint = if Ui.Phone then Vector2.zero else Vector2.new(1, 0),
		Position = if Ui.Phone then UDim2.fromOffset(80, 190) else UDim2.new(1, -14, 0, 62),
		Size = UDim2.fromOffset(230, 40),
		BackgroundColor3 = Color3.fromRGB(30, 80, 45),
		BackgroundTransparency = 0.1,
		Visible = false,
	}, gui)
	Ui.corner(luckPill, 12)
	new("UIStroke", { Thickness = 2.5, Color = Color3.fromRGB(14, 10, 20) }, luckPill)
	local luckLabel = text(luckPill, { Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromOffset(6, 3), Text = "" })
	RunService.Heartbeat:Connect(function()
		local until_ = ReplicatedStorage:GetAttribute("ServerLuckUntil")
		local left = if type(until_) == "number" then until_ - workspace:GetServerTimeNow() else 0
		luckPill.Visible = left > 0
		if left > 0 then
			local mult = ReplicatedStorage:GetAttribute("ServerLuckMultiplier") or 2
			luckLabel.Text = `🍀 {mult}x Server Luck  {Ui.clock(left)}`
		end
	end)
end

return Store
