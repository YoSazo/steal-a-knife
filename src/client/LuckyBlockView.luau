--!strict
-- The Store's LUCKY BLOCKS row (Steal a Brainrot style): three blocks side by side, each with a big
-- glowing icon, a strip of every knife inside with its exact chance (Items.LuckyBlockOdds, most
-- likely first) and a Robux price button.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local Items = require(ReplicatedStorage.Shared.Items)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local VoxelLuckyBlocks = require(ReplicatedStorage.Shared.Config.VoxelUi).LuckyBlocks :: { [string]: string }
local View = {}

local function percent(n: number): string
	local text = if n >= 10
		then string.format("%.0f", n)
		elseif n >= 1 then string.format("%.1f", n)
		else string.format("%.2f", n)
	text = text:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
	return text .. "%"
end

-- One block card
local function card(parent: Instance, block: string, price: string, order: number, buy: () -> (), cash: boolean?): Frame
	-- Same philosophy as the Index/case rows: a solid rarity-colour card with a black outline,
	-- not a dark card with a coloured edge.
	local color = Knives.RarityColors[block]
	local frame = Theme.surface(parent, { Name = block .. "Block", LayoutOrder = order, ZIndex = 7 }, color)
	Theme.text(frame, block:upper(), {
		Name = "Title",
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.new(1, -12, 0, 40),
		MaximumTextSize = 36,
		ZIndex = 10,
	})
	-- Codex's own Lucky Block picture, not the native 3D toy.
	Ui.new("ImageLabel", {
		Name = "Art",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 48),
		Size = UDim2.fromOffset(150, 150),
		BackgroundTransparency = 1,
		Image = VoxelLuckyBlocks[block] or "",
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 8,
	}, frame)
	-- Every knife inside, scrolling sideways, with its chance
	local strip = Ui.new("ScrollingFrame", {
		Name = "Odds",
		Position = UDim2.fromOffset(6, 206),
		Size = UDim2.new(1, -12, 0, 92),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 3,
		ZIndex = 8,
	}, frame)
	Ui.corner(strip, 8)
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, strip)
	for i, odd in Items.LuckyBlockOdds(block) do
		local tile = Ui.new("Frame", {
			LayoutOrder = i,
			Size = UDim2.new(0, 64, 1, -6),
			BackgroundTransparency = 1,
			ZIndex = 9,
		}, strip)
		Theme.image(tile, odd.Knife, { Size = UDim2.new(1, 0, 1, -20), ZIndex = 9 })
		Theme.text(tile, percent(odd.Percent), {
			Position = UDim2.new(0, 0, 1, -20),
			Size = UDim2.new(1, 0, 0, 20),
			MaximumTextSize = 18,
			TextColor3 = Knives.RarityColors[odd.Rarity]:Lerp(Color3.new(1, 1, 1), 0.35),
			ZIndex = 10,
		})
	end
	Theme.button(frame, price, if cash then Theme.Gold else Theme.Green, {
		Name = "Purchase",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(0.8, 0, 0, 56),
		MaximumTextSize = 40,
		ZIndex = 10,
	}, buy)
	return frame
end

-- `products` = { { Block, Price (text), Buy, Cash? } } in display order
function View.Build(
	parent: Instance,
	order: number,
	products: { { Block: string, Price: string, Buy: () -> (), Cash: boolean? } }
)
	local row = Ui.new("Frame", {
		Name = "LuckyBlocks",
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 380),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, parent)
	Ui.new("UIGridLayout", {
		CellSize = UDim2.new(1 / #products, -8, 1, 0),
		CellPadding = UDim2.fromOffset(8, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	for i, product in products do
		card(row, product.Block, product.Price, i, product.Buy, product.Cash)
	end
	return row
end

return View
