--!strict
-- Presentation only. Marketplace prompts, ownership and grants stay in Store/server services.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Config = ReplicatedStorage.Shared.Config
local Monetization = require(Config.Monetization)
local player = Players.LocalPlayer
local View = {}

local function exactCash(amount: number): string
	local text = string.format("%.0f", amount)
	local groups = text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return "$" .. groups
end

local function label(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local options: { [string]: any } =
		{ Text = text, TextScaled = false, TextSize = 16, TextWrapped = true, ZIndex = 6 }
	for key, value in (props or {}) :: { [string]: any } do
		options[key] = value
	end
	return Theme.text(parent, text, options)
end
local function card(parent: Instance, order: number, color: Color3, height: number): Frame
	return Theme.surface(
		parent,
		{ LayoutOrder = order, Size = UDim2.new(1, -8, 0, height), ZIndex = 7 },
		color:Lerp(Theme.Navy, 0.3),
		color
	)
end
local function page(parent: Instance, props: { [string]: any }): ScrollingFrame
	props.BackgroundTransparency = 1
	props.CanvasSize = UDim2.new()
	props.AutomaticCanvasSize = Enum.AutomaticSize.Y
	props.ScrollBarThickness = 4
	props.ZIndex = 5
	local scroll: ScrollingFrame = Ui.new("ScrollingFrame", props, parent)
	Ui.new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	Ui.padding(scroll, 4)
	return scroll
end

function View.Build(actions: any): Frame
	local frame, body, header = Theme.shell("Store", "Shop", Theme.Green, "Shop", 540)
	local shopTitle = header:FindFirstChild("Title") :: TextLabel
	shopTitle.Size = UDim2.fromOffset(340, 80)
	local tabs = Ui.new("Frame", {
		Position = UDim2.fromOffset(478, 16),
		Size = UDim2.fromOffset(432, 60),
		BackgroundTransparency = 1,
		ZIndex = 8,
	}, header)
	Ui.new("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -8, 1, 0),
		CellPadding = UDim2.fromOffset(8, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tabs)
	local pages: { [string]: ScrollingFrame } = {}
	local tabButtons: { [string]: TextButton } = {}
	local function selectTab(name: string)
		for key, scroll in pages do
			scroll.Visible = key == name
			local border = tabButtons[key]:FindFirstChildOfClass("UIStroke") :: UIStroke
			border.Color = if key == name then Color3.new(1, 1, 1) else Theme.Black
		end
	end
	-- Steal An Egg's shop: Featured / Speed / Money (consumables that fix one moment are offered at
	-- that moment instead)
	for i, name in { "Featured", "Speed", "Money" } do -- (the tab says "Top": "Featured" wrapped on phones)
		pages[name] = page(body, { Name = name, Size = UDim2.fromScale(1, 1), Visible = i == 1 })
		tabButtons[name] = Theme.button(
			tabs,
			if name == "Featured" then "Top" else name,
			({ Theme.Gold, Theme.Cyan, Theme.Green })[i],
			{ Name = name, LayoutOrder = i, MaximumTextSize = 25 },
			function()
				selectTab(name)
			end,
			({ "Shop", "Speed", "Cash" })[i]
		)
	end
	local refreshers: { () -> () } = {}
	local symbols: { [string]: string } = {
		DoubleCash = "Cash",
		VIP = "VIP",
		FastWheel = "Speed",
		PhantomTrail = "VoidEdge",
		AutoCollect = "Cash",
		Luck = "Luck",
		OfflinePlus = "Rebirth",
		ExtraFloor = "Upgrades",
		Spins10 = "Spin",
		SpeedPotion = "Speed",
		SpeedPotionBig = "Speed",
		CollectSession = "Cash",
		CashPotion = "Cash",
		CashPotionBig = "Cash",
		CashSmall = "Cash",
		CashMedium = "Cash",
		CashBig = "Cash",
		TrainingPotion = "Speed",
		SpeedUpgrade = "Upgrades",
		SpeedSmall = "Speed",
		SpeedMedium = "Speed",
		SpeedBig = "Speed",
	}
	local function title(scroll: ScrollingFrame, text: string, order: number, name: string?): TextLabel
		return label(scroll, text, {
			Name = name or "Title",
			LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, 44),
			TextSize = 28,
			TextColor3 = Theme.Gold,
		})
	end
	-- One wide row (Steal An Egg): the picture, a BIG line of what you get, a short line under it,
	-- and the Robux button. `big` is recomputed on every refresh (packs scale with you).
	local function row(scroll: ScrollingFrame, entry: any, order: number, kind: string, big: () -> string)
		local item = card(scroll, order, entry.Color, 112)
		Theme.image(
			item,
			symbols[entry.Key] or "Cash",
			{ Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(90, 90), ZIndex = 8 }
		)
		local headline = label(item, "", {
			Position = UDim2.fromOffset(112, 8),
			Size = UDim2.new(1, -290, 0, 54),
			TextSize = 34,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 8,
		})
		local detail = label(item, entry.Description, {
			Position = UDim2.fromOffset(112, 62),
			Size = UDim2.new(1, -290, 0, 46),
			TextSize = 20, -- (16 was ~8 px once the Shop is scaled to a phone)
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = Color3.fromRGB(215, 225, 245),
			ZIndex = 8,
		})
		local purchase = actions.price(item, entry.Price, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(150, 64),
			ZIndex = 9,
		}, function()
			if kind ~= "Pass" or not actions.owned(entry.Key) then
				actions.buy(kind, entry.Key)
			end
		end)
		table.insert(refreshers, function()
			headline.Text = big()
			local text = purchase:FindFirstChild("Label") :: TextLabel?
			if text then
				text.Text = if kind == "Pass" and actions.owned(entry.Key) then "✓ Owned" else `R$ {entry.Price}`
			end
			if entry.Charge then
				local have = (player:GetAttribute("Charge_" .. entry.Charge.Name) or 0) :: number
				detail.Text = if have > 0 then `You have {have} · {entry.Description}` else entry.Description
			end
		end)
		return item
	end
	local function named(entry: any): () -> string
		return function()
			return entry.Name
		end
	end
	local function product(scroll: ScrollingFrame, key: string, order: number, big: (() -> string)?)
		local entry = Monetization.ProductByKey[key]
		if entry then
			row(scroll, entry, order, "Product", big or named(entry))
		end
	end
	local function pass(scroll: ScrollingFrame, key: string, order: number)
		local entry = Monetization.PassByKey[key]
		if entry then
			row(scroll, entry, order, "Pass", named(entry))
		end
	end

	-- FEATURED: the Starter Pack (once), the passes, then luck and spins
	local featured = pages.Featured
	title(featured, "PASSES", 3)
	local passOrder = 4
	for _, key in { "DoubleCash", "VIP", "Luck", "AutoCollect", "OfflinePlus", "ExtraFloor" } do
		pass(featured, key, passOrder)
		passOrder += 1
	end
	title(featured, "LUCK", 30)
	product(featured, "Spins10", 31)

	-- SPEED: the wheel's next level, Speed packs scaled to you, then the Speed passes and potions
	local speed = pages.Speed
	product(speed, "SpeedUpgrade", 1, function()
		local nextUpgrade = GameConfig.NextSpeedUpgrade(
			(player:GetAttribute("TreadmillLevel") or 1) :: number,
			(player:GetAttribute("TrailLevel") or 0) :: number
		)
		return if nextUpgrade then `Wheel Level {nextUpgrade.Level} > {nextUpgrade.Level + 1}` else "Wheel maxed"
	end)
	for i, key in { "SpeedSmall", "SpeedMedium", "SpeedBig" } do
		local entry = Monetization.ProductByKey[key]
		product(speed, key, 1 + i, function()
			local have = (player:GetAttribute("Speed") or 0) :: number
			return `+{Ui.abbreviate(Monetization.SpeedFor(entry, have))} Speed`
		end)
	end
	pass(speed, "FastWheel", 10)
	pass(speed, "PhantomTrail", 11)
	product(speed, "TrainingPotion", 12)
	product(speed, "SpeedPotion", 13)
	product(speed, "SpeedPotionBig", 14)

	-- MONEY: cash packs scaled to your income, then the money passes and potions
	local money = pages.Money
	for i, key in { "CashSmall", "CashMedium", "CashBig" } do
		local entry = Monetization.ProductByKey[key]
		product(money, key, i, function()
			return `+${Ui.abbreviate(actions.cash(entry) or 0)}`
		end)
	end
	pass(money, "DoubleCash", 10)
	pass(money, "AutoCollect", 11)
	pass(money, "OfflinePlus", 12)
	product(money, "CashPotion", 13)
	product(money, "CashPotionBig", 14)
	local session = Monetization.ProductByKey.CollectSession
	if session then
		local item = row(money, session, 15, "Product", named(session))
		-- "Auto Collect (this visit)" is pointless with the Auto Collect pass: hide it for owners
		local function hideIfOwned()
			item.Visible = player:GetAttribute("Pass_AutoCollect") ~= true
		end
		player:GetAttributeChangedSignal("Pass_AutoCollect"):Connect(hideIfOwned)
		hideIfOwned()
	end

	-- The Starter Pack: cash and a Legendary Coffin (a paid random item: hidden where Roblox's policy
	-- restricts those - PolicyService, set by the server - and the server pays its value there)
	local starter = Monetization.ProductByKey.Starter
	local starterRow = card(featured, 1, starter.Color, 112)
	label(starterRow, "⚰️", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(80, 90),
		TextSize = 64,
		ZIndex = 6,
	})
	-- (big type: the Shop is scaled down to fit a phone, and 16 pt came out ~8 px on an iPhone 7)
	label(starterRow, "Starter Pack · once per player", {
		Position = UDim2.fromOffset(96, 8),
		Size = UDim2.new(1, -252, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 28,
	})
	local contents = label(starterRow, "", {
		Position = UDim2.fromOffset(96, 50),
		Size = UDim2.new(1, -252, 0, 52),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 28,
		TextColor3 = Color3.fromRGB(140, 255, 150),
	})
	actions.price(
		starterRow,
		starter.Price,
		{ Position = UDim2.new(1, -140, 0, 12), Size = UDim2.fromOffset(128, 44), ZIndex = 7 },
		function()
			actions.buy("Product", "Starter")
		end
	)
	table.insert(refreshers, function()
		starterRow.Visible = not actions.owned("Starter")
			and Players.LocalPlayer:GetAttribute("PaidRandomRestricted") == false
		contents.Text = `{exactCash(actions.cash(starter) or 0)} + 1 Legendary Coffin`
	end)
	local function refresh()
		for _, fn in refreshers do
			fn()
		end
	end
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			selectTab("Featured")
			refresh()
		end
	end)
	player.AttributeChanged:Connect(function()
		if frame.Visible then
			refresh()
		end
	end)
	local shop = Theme.button(Ui.Navigation, "Shop", Theme.Green, {
		Name = "StoreButton",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(112, 44),
		MaximumTextSize = 23,
	}, function()
		Ui.Menu.Toggle(frame)
	end, "Shop")
	local function visibility()
		shop.Visible = not player:GetAttribute("InRound")
	end
	player:GetAttributeChangedSignal("InRound"):Connect(visibility)
	visibility()
	selectTab("Featured")
	Ui.OpenShop = function(tab: string)
		if player:GetAttribute("InRound") then
			return
		end
		selectTab(if pages[tab] then tab else "Featured")
		if not frame.Visible then
			Ui.Menu.Toggle(frame)
		end
	end
	return frame
end
return View
