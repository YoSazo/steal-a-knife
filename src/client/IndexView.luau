--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local Config = ReplicatedStorage.Shared.Config
local Knives = require(Config.Knives)
local GameConfig = require(Config.GameConfig)
local player = Players.LocalPlayer
local Remotes = ReplicatedStorage.Remotes
local View = {}

function View.Build(): (Frame, () -> number)
	local frame, body = Theme.shell("Index", "Knife Index", Theme.Cyan, "Index", 530)
	local filter = "All"
	local selected = Knives.List[1]
	local found: { [string]: boolean } = {}
	local claimed: { [string]: boolean } = {}
	local filters = Ui.new("ScrollingFrame", {
		Name = "RarityFilters",
		Size = UDim2.new(0, 128, 1, -52),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ZIndex = 7,
	}, body)
	Ui.new("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, filters)
	Ui.padding(filters, 3, 3)
	local grid = Ui.new("ScrollingFrame", {
		Name = "Collection",
		Position = UDim2.fromOffset(142, 0),
		Size = UDim2.new(1, -380, 1, -52),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Cyan,
		ZIndex = 7,
	}, body)
	Ui.padding(grid, 3, 3)
	Ui.new("UIGridLayout", {
		CellSize = UDim2.new(0.25, -9, 0, 176),
		CellPadding = UDim2.fromOffset(8, 9),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	local inspector = Theme.surface(
		body,
		{ Name = "Inspector", Position = UDim2.new(1, -226, 0, 0), Size = UDim2.new(0, 226, 1, 0), ZIndex = 7 },
		Theme.Navy,
		Color3.fromRGB(70, 119, 179)
	)
	local title = Theme.text(
		inspector,
		"",
		{ Name = "KnifeName", Position = UDim2.fromOffset(6, 4), Size = UDim2.new(1, -12, 0, 36), MaximumTextSize = 30 }
	)
	local rarity = Theme.text(
		inspector,
		"",
		{ Position = UDim2.fromOffset(6, 40), Size = UDim2.new(1, -12, 0, 25), MaximumTextSize = 22 }
	)
	local display = Ui.new(
		"Frame",
		{ Position = UDim2.fromOffset(4, 64), Size = UDim2.new(1, -8, 0, 190), BackgroundTransparency = 1, ZIndex = 7 },
		inspector
	)
	local burst = Theme.burst(display, Theme.Gold)
	local art = Theme.image(display, selected.Name)
	Theme.text(
		inspector,
		"Rewards",
		{ Position = UDim2.fromOffset(4, 250), Size = UDim2.new(1, -8, 0, 26), MaximumTextSize = 24 }
	)
	local rewards = {}
	for i, symbol in { "Cash", "Speed" } do
		local tile = Theme.surface(
			inspector,
			{ Position = UDim2.new((i - 1) * 0.5, 6, 0, 278), Size = UDim2.new(0.5, -12, 0, 74), ZIndex = 7 },
			Theme.Navy,
			Color3.fromRGB(61, 99, 144)
		)
		Theme.image(tile, symbol, { Position = UDim2.new(0.5, -28, 0, -4), Size = UDim2.fromOffset(56, 48) })
		rewards[i] = Theme.text(tile, "", {
			Name = symbol .. "Reward",
			Position = UDim2.fromOffset(2, 42),
			Size = UDim2.new(1, -4, 0, 28),
			MaximumTextSize = 22,
		})
	end
	local claim = Theme.button(
		inspector,
		"CLAIM",
		Theme.Green,
		{ Name = "Claim", Position = UDim2.new(0, 6, 1, -60), Size = UDim2.new(1, -12, 0, 54), MaximumTextSize = 40 },
		function()
			Remotes.ClaimIndex:InvokeServer(selected.Name)
		end
	)
	local footer = Theme.surface(
		body,
		{ Name = "Progress", Position = UDim2.new(0, 0, 1, -42), Size = UDim2.new(1, -238, 0, 42), ZIndex = 7 },
		Theme.Navy,
		Color3.fromRGB(47, 103, 155)
	)
	local fill = Theme.surface(
		footer,
		{ Position = UDim2.fromOffset(5, 5), Size = UDim2.new(0, 0, 1, -10), ZIndex = 7, Visible = false },
		Theme.Green
	)
	local progress = Theme.text(footer, "", {
		Name = "ProgressText",
		Position = UDim2.fromOffset(8, 2),
		Size = UDim2.new(1, -150, 1, -4),
		MaximumTextSize = 25,
	})
	local all = Theme.button(footer, "Claim all", Theme.Cyan, {
		Name = "ClaimAll",
		Position = UDim2.new(1, -138, 0, 3),
		Size = UDim2.fromOffset(132, 36),
		MaximumTextSize = 21,
	}, function()
		Remotes.ClaimIndex:InvokeServer("All")
	end)
	local tiles: { [string]: any } = {}
	local filterButtons: { [string]: TextButton } = {}
	local function inspect()
		local known = found[selected.Name] == true
		title.Text = if known then selected.DisplayName else "???"
		rarity.Text, rarity.TextColor3 = selected.Rarity:upper(), Knives.RarityColors[selected.Rarity]
		art:Destroy()
		art = Theme.image(
			display,
			selected.Name,
			{ ImageColor3 = if known then Color3.new(1, 1, 1) else Color3.new(0, 0, 0) }
		)
		burst.Visible = known
		local reward = GameConfig.IndexRewards[selected.Rarity]
		rewards[1].Text, rewards[2].Text = "+$" .. Ui.abbreviate(reward.Cash), "+" .. Ui.abbreviate(reward.Speed)
		Theme.enabled(
			claim,
			known and not claimed[selected.Name],
			if not known then "UNDISCOVERED" elseif claimed[selected.Name] then "CLAIMED" else "CLAIM"
		)
		for name, tile in tiles do
			tile.Border.Color = if name == selected.Name then Theme.Gold else Theme.Black
			tile.Border.Thickness = if name == selected.Name then 4 else 3
		end
	end
	local function applyFilter()
		for _, knife in Knives.List do
			tiles[knife.Name].Button.Visible = filter == "All" or knife.Rarity == filter
		end
		for name, button in filterButtons do
			local border = button:FindFirstChildOfClass("UIStroke") :: UIStroke
			border.Color = if name == filter then Theme.Gold else Theme.Black
		end
		grid.CanvasPosition = Vector2.zero
	end
	local names = { "All" }
	for _, name in Knives.Rarities do
		table.insert(names, name)
	end
	for order, name in names do
		local color = if name == "All" then Theme.Green else Knives.RarityColors[name]
		filterButtons[name] = Theme.button(
			filters,
			name,
			color,
			{ Name = name, LayoutOrder = order, Size = UDim2.new(1, -6, 0, 37), MaximumTextSize = 21 },
			function()
				filter = name
				applyFilter()
			end
		)
	end
	for order, knife in Knives.List do
		local button = Theme.button(
			grid,
			"",
			Knives.RarityColors[knife.Rarity],
			{ Name = knife.Name, LayoutOrder = order, MaximumTextSize = 25 },
			function()
				selected = knife
				inspect()
			end
		)
		local border = button:FindFirstChildOfClass("UIStroke") :: UIStroke
		local name = Theme.text(button, "???", {
			Name = "KnifeName",
			Position = UDim2.fromOffset(4, 3),
			Size = UDim2.new(1, -8, 0, 30),
			MaximumTextSize = 23,
			ZIndex = 10,
		})
		local image = Theme.image(
			button,
			knife.Name,
			{ Position = UDim2.fromOffset(3, 28), Size = UDim2.new(1, -6, 1, -32), ZIndex = 9 }
		)
		tiles[knife.Name] = { Button = button, Name = name, Art = image, Border = border }
	end
	local function refresh(): number
		found, claimed = {}, {}
		for _, name in Ui.list(player:GetAttribute("Discovered")) do
			found[name] = true
		end
		for _, name in Ui.list(player:GetAttribute("IndexClaimed")) do
			claimed[name] = true
		end
		local count, claimable = 0, 0
		for _, knife in Knives.List do
			local known = found[knife.Name] == true
			count += if known then 1 else 0
			claimable += if known and not claimed[knife.Name] then 1 else 0
			local tile = tiles[knife.Name]
			tile.Name.Text = if known then knife.DisplayName else "???"
			tile.Art.ImageColor3 = if known then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
		end
		fill.Size = UDim2.new(count / #Knives.List, -10 * count / #Knives.List, 1, -10)
		fill.Visible = count > 0
		progress.Text = `Discovered: {count} / {#Knives.List}`
		Theme.enabled(all, claimable > 0, `Claim all ({claimable})`)
		inspect()
		return claimable
	end
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			refresh()
		end
	end)
	refresh()
	applyFilter()
	return frame, refresh
end

return View
