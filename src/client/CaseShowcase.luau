--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local View = {}

function View.Build(
	parent: Instance,
	rarity: string,
	price: string,
	purchase: () -> (),
	odds: () -> (),
	height: number?
): Frame
	local color = Knives.RarityColors[rarity]
	local row = Theme.surface(
		parent,
		{ Name = rarity .. "Case", Size = UDim2.new(1, -8, 0, height or 346), ZIndex = 7 },
		Theme.Navy,
		color
	)
	Theme.text(row, rarity:upper() .. " CASE", {
		Name = "CaseTitle",
		Position = UDim2.fromOffset(12, 2),
		Size = UDim2.new(1, -24, 0, 60),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		MaximumTextSize = 52,
		ZIndex = 10,
	})
	local chest = Ui.new("Frame", {
		Position = UDim2.fromOffset(4, 62),
		Size = UDim2.new(0.33, 0, 1, -68),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, row)
	Theme.burst(chest, color)
	Theme.image(chest, "Case" .. rarity, { Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1), ZIndex = 9 })
	local rewards = Ui.new("Frame", {
		Name = "Rewards",
		Position = UDim2.new(0.34, 0, 0, 66),
		Size = UDim2.new(0.65, -6, 1, -154),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, row)
	local nextRarity = Knives.Rarities[(table.find(Knives.Rarities, rarity) or 1) + 1]
	local count = #Knives.ByRarity[rarity] + (if nextRarity then #Knives.ByRarity[nextRarity] else 0)
	Ui.new("UIGridLayout", {
		CellSize = UDim2.new(1 / count, -6, 1, -4),
		CellPadding = UDim2.fromOffset(6, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, rewards)
	local order = 0
	for _, tier in { rarity, nextRarity } do
		if not tier then
			continue
		end
		for _, knife in Knives.ByRarity[tier] do
			order += 1
			local tile = Theme.surface(
				rewards,
				{ Name = knife.Name, LayoutOrder = order, ZIndex = 8 },
				Knives.RarityColors[tier]
			)
			Theme.image(
				tile,
				knife.Name,
				{ Name = "Knife", Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 1, -36), ZIndex = 9 }
			)
			local percent = (if tier == rarity then (if nextRarity then 96 else 100) else 4) / #Knives.ByRarity[tier]
			local value = string.format("%.2f", percent):gsub("0+$", ""):gsub("%.$", "")
			Theme.text(tile, value .. "%", {
				Name = "Odds",
				Position = UDim2.new(0, 0, 1, -38),
				Size = UDim2.new(1, 0, 0, 36),
				MaximumTextSize = 30,
				ZIndex = 10,
			})
		end
	end
	Theme.button(row, "Full odds", Theme.Cyan, {
		Name = "FullOdds",
		Position = UDim2.new(0.60, -8, 1, -66),
		Size = UDim2.new(0.12, 0, 0, 54),
		MaximumTextSize = 23,
		ZIndex = 10,
	}, odds)
	Theme.button(row, price, Theme.Green, {
		Name = "Purchase",
		Position = UDim2.new(0.73, -4, 1, -74),
		Size = UDim2.new(0.27, -8, 0, 64),
		MaximumTextSize = 50,
		ZIndex = 10,
	}, purchase, if price:sub(1, 1) == "$" then "Cash" else nil)
	return row
end

return View
