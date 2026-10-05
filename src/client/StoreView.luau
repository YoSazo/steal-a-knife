--!strict
-- Presentation only. Marketplace prompts, ownership and grants stay in Store/server services.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local CaseShowcase = require(script.Parent.CaseShowcase)
local LuckyBlockView = require(script.Parent.LuckyBlockView)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = ReplicatedStorage.Remotes
local Config = ReplicatedStorage.Shared.Config
local Monetization = require(Config.Monetization)
local Knives = require(Config.Knives)
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
	for i, name in { "Cases", "Passes", "Boosts" } do
		pages[name] = page(body, { Name = name, Size = UDim2.fromScale(1, 1), Visible = i == 1 })
		tabButtons[name] = Theme.button(
			tabs,
			name,
			({ Theme.Gold, Theme.Cyan, Theme.Purple })[i],
			{ Name = name, LayoutOrder = i, MaximumTextSize = 25 },
			function()
				selectTab(name)
			end,
			({ "CaseLegendary", "Index", "Speed" })[i]
		)
	end
	local refreshers: { () -> () } = {}
	local function showOdds(rarity: string)
		local dialog = Ui.new(
			"Frame",
			{ Name = "CaseOdds", Size = UDim2.fromOffset(720, 560), BackgroundColor3 = Ui.PANEL, ZIndex = 8 },
			Ui.gui
		)
		Ui.corner(dialog, 16)
		Ui.fitMenu(dialog, Vector2.new(720, 560))
		Ui.registerMenu(dialog)
		label(dialog, rarity .. " Case — full odds", {
			Position = UDim2.fromOffset(16, 8),
			Size = UDim2.new(1, -80, 0, 44),
			ZIndex = 9,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		Ui.button(
			{
				Name = "Close",
				Text = "X",
				Position = UDim2.new(1, -52, 0, 8),
				Size = UDim2.fromOffset(44, 44),
				ZIndex = 10,
			},
			dialog,
			function()
				dialog:Destroy()
				frame.Visible = true
			end
		)
		local scroll = page(dialog, { Position = UDim2.fromOffset(16, 64), Size = UDim2.new(1, -32, 1, -80) })
		label(
			scroll,
			actions.odds(rarity)
				.. "\n\nKnife, mutation and size are separate rolls. Current rebirth and server luck apply to mutations and sizes. Murderer powers are rolled separately at your vault.",
			{
				TextSize = 16,
				TextYAlignment = Enum.TextYAlignment.Top,
				Size = UDim2.new(1, -12, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				ZIndex = 10,
			}
		)
	end
	local function cashCase(rarity: string)
		for _, entry in GameConfig.CaseShop do
			if entry.Rarity == rarity then
				return entry
			end
		end
		error("Unknown cash case " .. rarity)
	end
	local hero = Ui.new("Frame", {
		Name = "FeaturedCase",
		Size = UDim2.new(1, -8, 0, 328),
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, pages.Cases)
	local function feature(rarity: string)
		for _, child in hero:GetChildren() do
			child:Destroy()
		end
		local entry = cashCase(rarity)
		local showcase = CaseShowcase.Build(hero, rarity, "$" .. Ui.abbreviate(entry.Cost), function()
			Remotes.Purchase:InvokeServer("Case:" .. rarity)
		end, function()
			showOdds(rarity)
		end)
		showcase.Size = UDim2.fromScale(1, 1)
	end
	local secondary = Ui.new("Frame", {
		Name = "MoreCashCases",
		LayoutOrder = 2,
		Size = UDim2.new(1, -8, 0, 78),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, pages.Cases)
	for i, rarity in { "Epic", "Godly" } do
		Theme.button(secondary, rarity:upper() .. "\nCASE", Knives.RarityColors[rarity], {
			Name = rarity .. "Case",
			Position = UDim2.fromScale((i - 1) * 0.32, 0),
			Size = UDim2.new(0.31, 0, 1, -4),
			MaximumTextSize = 31,
		}, function()
			feature(rarity)
			pages.Cases.CanvasPosition = Vector2.zero
		end, "Case" .. rarity)
	end
	local otherCash = Ui.new("Frame", {
		Name = "CashCatalog",
		LayoutOrder = 3,
		Size = UDim2.new(1, -8, 0, 78),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, pages.Cases)
	Ui.new("UIGridLayout", {
		CellSize = UDim2.new(1 / 5, -7, 1, 0),
		CellPadding = UDim2.fromOffset(7, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, otherCash)
	for i, rarity in { "Common", "Rare", "Mythic", "Celestial", "Cosmic" } do
		Theme.button(
			otherCash,
			rarity .. "\n$" .. Ui.abbreviate(cashCase(rarity).Cost),
			Knives.RarityColors[rarity],
			{ LayoutOrder = i, MaximumTextSize = 24 },
			function()
				feature(rarity)
				pages.Cases.CanvasPosition = Vector2.zero
			end
		)
	end
	feature("Legendary")
	label(pages.Cases, "ROBUX CASES", {
		Name = "RobuxCasesTitle",
		LayoutOrder = 5,
		Size = UDim2.new(1, -8, 0, 44),
		TextSize = 28,
		TextColor3 = Theme.Gold,
	})
	local function caseRow(key: string, order: number)
		local product = Monetization.ProductByKey[key]
		local rarity = product.Case :: string
		local row = CaseShowcase.Build(pages.Cases, rarity, "R$ " .. product.Price, function()
			actions.buy("Product", key)
		end, function()
			showOdds(rarity)
		end)
		row.LayoutOrder = order
		row:SetAttribute("PaidRandom", true)
	end
	caseRow("CaseLegendary", 6)
	caseRow("CaseEpic", 7)
	caseRow("CaseGodly", 8)
	label(
		pages.Cases,
		"LUCKY BLOCKS",
		{ Name = "LuckyTitle", LayoutOrder = 9, Size = UDim2.new(1, -8, 0, 44), TextSize = 28, TextColor3 = Theme.Gold }
	)
	local blocks = {}
	for _, key in { "LuckyMythic", "LuckyGodly", "LuckyCosmic" } do
		local product = Monetization.ProductByKey[key]
		table.insert(blocks, {
			Block = product.LuckyBlock :: string,
			Price = "R$ " .. product.Price,
			Buy = function()
				actions.buy("Product", key)
			end,
		})
	end
	local luckyRow = LuckyBlockView.Build(pages.Cases, 10, blocks)
	-- Cash Lucky Blocks: the same gamble for in-game cash, at every tier (free to play)
	label(pages.Cases, "CASH LUCKY BLOCKS", {
		LayoutOrder = 11,
		Size = UDim2.new(1, -8, 0, 44),
		TextSize = 28,
		TextColor3 = Theme.Gold,
	})
	for row, tiers in { { "Rare", "Epic", "Legendary" }, { "Mythic", "Godly", "Cosmic" } } do
		local cashBlocks = {}
		for _, tier in tiers do
			table.insert(cashBlocks, {
				Block = tier,
				Price = "$" .. Ui.abbreviate(GameConfig.LuckyBlockCash[tier]),
				Cash = true,
				Buy = function()
					Remotes.Gamble:InvokeServer("LuckyBlock", tier) -- (the server toasts any problem)
				end,
			})
		end
		LuckyBlockView.Build(pages.Cases, 11 + row, cashBlocks).Name = `CashLucky{row}`
	end
	-- Roblox policy: no paid random items where they're restricted (PolicyService, set by the server)
	local function applyPolicy()
		local allowed = Players.LocalPlayer:GetAttribute("PaidRandomRestricted") == false
		for _, child in pages.Cases:GetChildren() do
			if child == luckyRow or child.Name == "RobuxCasesTitle" or child.Name == "LuckyTitle" then
				(child :: GuiObject).Visible = allowed
			elseif child:IsA("GuiObject") and child:GetAttribute("PaidRandom") then
				child.Visible = allowed
			end
		end
	end
	Players.LocalPlayer:GetAttributeChangedSignal("PaidRandomRestricted"):Connect(applyPolicy)
	task.defer(applyPolicy)
	local starter = Monetization.ProductByKey.Starter
	local starterRow = card(pages.Cases, 4, starter.Color, 112)
	starterRow:SetAttribute("PaidRandom", true) -- contains a case
	-- Theme.image (not Ui.art) so this picks up Codex's Cases chest, not the old wooden one.
	Theme.image(
		starterRow,
		"CaseRare",
		{ Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(80, 90), ZIndex = 6 }
	)
	label(starterRow, "Starter Pack · once per player", {
		Position = UDim2.fromOffset(96, 8),
		Size = UDim2.new(1, -252, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local contents = label(starterRow, "", {
		Position = UDim2.fromOffset(96, 48),
		Size = UDim2.new(1, -252, 0, 56),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	actions.price(
		starterRow,
		starter.Price,
		{ Position = UDim2.new(1, -140, 0, 12), Size = UDim2.fromOffset(128, 44), ZIndex = 7 },
		function()
			actions.buy("Product", "Starter")
		end
	)
	Ui.button(
		{ Text = "Case odds", Position = UDim2.new(1, -140, 0, 62), Size = UDim2.fromOffset(128, 44), ZIndex = 7 },
		starterRow,
		function()
			showOdds("Rare")
		end
	)
	table.insert(refreshers, function()
		starterRow.Visible = not actions.owned("Starter")
		contents.Text = `{exactCash(actions.cash(starter) or 0)} + 1 Rare Case`
	end)
	local function productGrid(scroll: ScrollingFrame): Frame
		local grid = Ui.new("Frame", {
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex = 5,
		}, scroll) :: Frame
		local layout = Ui.new(
			"UIGridLayout",
			{ CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder },
			grid
		)
		local function resize()
			local width = math.max(160, grid.AbsoluteSize.X)
			local columns = math.max(1, math.floor((width + 12) / 192))
			layout.CellSize = UDim2.fromOffset((width - (columns - 1) * 12) / columns, 256)
		end
		grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
		resize()
		return grid
	end
	local passGrid, boostGrid = productGrid(pages.Passes), productGrid(pages.Boosts)
	local symbols: { [string]: string } = {
		DoubleCash = "Cash",
		VIP = "VIP",
		FastWheel = "Speed",
		PhantomTrail = "VoidEdge",
		AutoCollect = "Cash",
		Luck = "CaseLegendary",
		OfflinePlus = "Rebirth",
		ExtraFloor = "Upgrades",
		Spins3 = "CaseEpic",
		Spins10 = "CaseGodly",
		LuckPotion = "CaseLegendary",
		LuckPotionBig = "CaseLegendary",
		Titan = "Health",
		Mount = "Upgrades",
		ServerLuck = "Rebirth",
		BloodMoon = "CaseMythic",
		ChestRefill = "CaseRare",
		SpeedPotion = "Speed",
		CollectSession = "Cash",
		Reroll3 = "Powers",
		Reroll10 = "Powers",
		SpeedPotionBig = "Speed",
		CashPotion = "Cash",
		CashPotionBig = "Cash",
		TrainingPotion = "Wheel",
		Escape3 = "Padlock",
		Escape10 = "Padlock",
		Insurance3 = "Shield",
		Insurance10 = "Shield",
		HeatRefill = "Heat",
		BossRestock = "Rebirth",
	}
	local function offer(parent: Frame, entry: any, order: number, kind: string)
		local item = card(parent, order, entry.Color, 256)
		-- "Auto Collect (this visit)" is pointless with the Auto Collect pass: hide it for owners
		if entry.Key == "CollectSession" then
			local function hideIfOwned()
				item.Visible = player:GetAttribute("Pass_AutoCollect") ~= true
			end
			player:GetAttributeChangedSignal("Pass_AutoCollect"):Connect(hideIfOwned)
			hideIfOwned()
		end
		Theme.image(
			item,
			symbols[entry.Key] or "Cash",
			{ Position = UDim2.new(0.5, -32, 0, 4), Size = UDim2.fromOffset(64, 64), ZIndex = 6 }
		)
		label(item, entry.Name, { Position = UDim2.fromOffset(8, 72), Size = UDim2.new(1, -16, 0, 40), TextSize = 20 })
		local description = label(item, entry.Description, {
			TextSize = 14,
			Position = UDim2.fromOffset(12, 114),
			Size = UDim2.new(1, -24, 0, 82),
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		local purchase = actions.price(
			item,
			entry.Price,
			{ Position = UDim2.new(0, 8, 1, -52), Size = UDim2.new(1, -16, 0, 44), ZIndex = 7 },
			function()
				if kind ~= "Pass" or not actions.owned(entry.Key) then
					actions.buy(kind, entry.Key)
				end
			end
		)
		table.insert(refreshers, function()
			local text = purchase:FindFirstChild("Label") :: TextLabel
			text.Text = if kind == "Pass" and actions.owned(entry.Key) then "✓ Owned" else `R$ {entry.Price}`
			-- Charges: how many you still have
			if entry.Charge then
				local have = (player:GetAttribute("Charge_" .. entry.Charge.Name) or 0) :: number
				description.Text = if have > 0 then `You have {have}\n{entry.Description}` else entry.Description
			end
			if entry.Cash then
				description.Text = `${Ui.abbreviate(actions.cash(entry) or 0)} for you\n{entry.Description}`
			end
		end)
	end
	for i, pass in Monetization.Passes do
		offer(passGrid, pass, i, "Pass")
	end
	for i, key in
		{
			"SpeedPotion",
			"CashPotion",
			"CollectSession",
			"Reroll3",
			"Reroll10",
			"Escape3",
			"Insurance3",
			"SpeedPotionBig",
			"CashPotionBig",
			"Escape10",
			"Insurance10",
			"TrainingPotion",
			"HeatRefill",
			"BossRestock",
			"Spins10",
			"Spins3",
			"LuckPotion",
			"LuckPotionBig",
			"ServerLuck",
			"CashSmall",
			"CashMedium",
			"CashBig",
			"Mount",
			"ChestRefill",
		}
	do
		offer(boostGrid, Monetization.ProductByKey[key], i, "Product")
	end
	local function refresh()
		for _, fn in refreshers do
			fn()
		end
	end
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			selectTab("Cases")
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
	end, "CaseLegendary")
	local function visibility()
		shop.Visible = not player:GetAttribute("InRound")
	end
	player:GetAttributeChangedSignal("InRound"):Connect(visibility)
	visibility()
	selectTab("Cases")
	return frame
end
return View
