--!strict
-- Powers, Tsunami-simple (the Power Mystic north star): one big row per power (Codex's voxel icon,
-- name, a few words, ONE big button that says what tapping it does), and your power as a big bar
-- along the bottom. One power system (docs/POWERS.md): every knife carries a power with a Murderer
-- power and an Innocent power (spelled out on every row); the knife you fight with is the power you bring to rounds.
-- Powers come from stealing knives, levels from playing: the row button equips your best knife
-- with that power; the bottom bar re-rolls yours (cash or a Re-roll Token).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ui = require(script.Parent.Ui)
local SimpleUi = require(script.Parent.SimpleUi)
local VoxelUi = require(ReplicatedStorage.Shared.Config.VoxelUi)
local Icons = require(ReplicatedStorage.Shared.Config.VoxelPowerIcons)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local KnifePowers = require(ReplicatedStorage.Shared.Config.KnifePowers)
local Items = require(ReplicatedStorage.Shared.Items)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local View = {}

local PURPLE = Color3.fromRGB(150, 70, 235)
local GREEN = Color3.fromRGB(80, 210, 50)
local BLUE = Color3.fromRGB(40, 150, 255)
local GREY = Color3.fromRGB(110, 115, 130)
local MURDERER = Color3.fromRGB(255, 130, 130)
local INNOCENT = Color3.fromRGB(140, 215, 255)

local function levels(): { [string]: number }
	local out = {}
	for _, entry in Ui.list(player:GetAttribute("PowerLevels")) do
		local id, level = entry:match("^(%w+):(%d+)$")
		if id and level then
			out[id] = tonumber(level) :: number
		end
	end
	return out
end

-- Your best (highest income) knife carrying each power
local function bestKnives(): { [string]: string }
	local best: { [string]: string } = {}
	for _, item in Ui.list(player:GetAttribute("Knives")) do
		local parsed = Items.Parse(item)
		local perk = parsed and parsed.Perk
		if perk and (not best[perk] or Items.Income(item) > Items.Income(best[perk])) then
			best[perk] = item
		end
	end
	return best
end

-- Sizes: phones get their own, smaller design (it's scaled down to fit far less, so the words stay
-- readable: checked on an iPhone 7 in Studio's emulator, where the desktop design shrank to 0.38)
local PHONE = {
	Window = Vector2.new(600, 440),
	RowH = 92,
	Icon = 76,
	TextX = 92,
	Button = Vector2.new(124, 60),
	NameH = 34,
	LineH = 22,
	Bar = 86,
	Reroll = 138,
	Token = 128,
}
local DESKTOP = {
	Window = Vector2.new(1000, 760),
	RowH = 110,
	Icon = 94,
	TextX = 116,
	Button = Vector2.new(240, 78),
	NameH = 42,
	LineH = 26,
	Bar = 112,
	Reroll = 220,
	Token = 212,
}

function View.Build(): (Frame, () -> ())
	local S = if Ui.Phone then PHONE else DESKTOP
	local frame, body = SimpleUi.window("Innocent Powers", "Powers", VoxelUi.Hud.Powers, PURPLE, S.Window)
	local textW = -(S.TextX + S.Button.X + 28) -- the room left for the words beside the icon and button
	local list: ScrollingFrame = Ui.new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -(S.Bar + 16)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 6,
	}, body)
	Ui.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	Ui.new("UIPadding", { PaddingRight = UDim.new(0, 12) }, list)

	type Row = { Name: TextLabel, Icon: ImageLabel, Main: TextButton, Power: KnifePowers.KnifePower }
	local rows: { Row } = {}
	local equipItem: { [string]: string } = {}
	for i, power in KnifePowers.List do
		local tier = KnifePowers.TierById[power.Tier]
		local short = KnifePowers.Short[power.Id] or { "", "" }
		local row: Frame = Ui.new("Frame", {
			LayoutOrder = KnifePowers.TierRank(power.Tier) * 100 + i,
			Size = UDim2.new(1, 0, 0, S.RowH),
			BackgroundColor3 = Color3.fromRGB(34, 38, 56),
			BackgroundTransparency = 0.2,
			ZIndex = 6,
		}, list)
		Ui.corner(row, 12)
		Ui.new("UIStroke", { Color = tier.Color, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, row)
		local icon: ImageLabel = Ui.new("ImageLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.fromOffset(S.Icon, S.Icon),
			Image = Icons.KnifePowers[power.Id] or VoxelUi.Hud.Powers,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 7,
		}, row)
		local name = SimpleUi.text(row, power.Name, {
			Position = UDim2.fromOffset(S.TextX, 6),
			Size = UDim2.new(1, textW, 0, S.NameH),
			TextXAlignment = Enum.TextXAlignment.Left,
			RichText = true,
			Max = 38,
		})
		SimpleUi.text(row, `Murderer power: {short[1]}`, {
			Position = UDim2.fromOffset(S.TextX, S.NameH + 8),
			Size = UDim2.new(1, textW, 0, S.LineH),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = MURDERER,
			Max = 22,
		})
		SimpleUi.text(row, `Innocent power: {short[2]}`, {
			Position = UDim2.fromOffset(S.TextX, S.NameH + S.LineH + 10),
			Size = UDim2.new(1, textW, 0, S.LineH),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = INNOCENT,
			Max = 22,
		})
		local main = SimpleUi.button(row, "", BLUE, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(S.Button.X, S.Button.Y),
			ZIndex = 7,
			Max = if Ui.Phone then 24 else 30,
		}, function()
			local item = equipItem[power.Id]
			if item then
				Remotes.Equip:InvokeServer(item)
			end
		end)
		table.insert(rows, { Name = name, Icon = icon, Main = main, Power = power })
	end

	-- Your power: one big bar along the bottom (like the old loadout bar)
	local mine: Frame = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, S.Bar),
		BackgroundColor3 = Color3.fromRGB(34, 38, 56),
		BackgroundTransparency = 0.2,
		ZIndex = 6,
	}, body)
	Ui.corner(mine, 12)
	Ui.new("UIStroke", { Color = PURPLE, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, mine)
	local mineIcon: ImageLabel = Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(S.Bar - 16, S.Bar - 16),
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 7,
	}, mine)
	local mineName = SimpleUi.text(mine, "", {
		Position = UDim2.fromOffset(S.Bar, 6),
		Size = UDim2.new(1, -(S.Bar + S.Reroll + S.Token + 40), 0, S.Bar * 0.42),
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,
		Max = 38,
	})
	-- XP to the next level
	local bar: Frame = Ui.new("Frame", {
		Position = UDim2.new(0, S.Bar, 1, -(S.Bar * 0.36 + 8)),
		Size = UDim2.new(1, -(S.Bar + S.Reroll + S.Token + 40), 0, S.Bar * 0.36),
		BackgroundColor3 = Color3.fromRGB(20, 18, 30),
		ZIndex = 7,
	}, mine)
	Ui.corner(bar, 10)
	local fill: Frame = Ui.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(255, 200, 60),
		ZIndex = 8,
	}, bar)
	Ui.corner(fill, 10)
	local barText = SimpleUi.text(bar, "", { Size = UDim2.fromScale(1, 1), Max = 22, ZIndex = 9 })
	local reroll = SimpleUi.button(mine, "", PURPLE, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(S.Token + 20), 0.5, 0),
		Size = UDim2.fromOffset(S.Reroll, S.Bar - 22),
		ZIndex = 7,
		Max = 28,
	}, function()
		Remotes.Power:InvokeServer("Enchant", "Cash")
	end)
	-- A token re-roll when you have tokens, else the button to get some
	local token = SimpleUi.button(mine, "", GREEN, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(S.Token, S.Bar - 22),
		ZIndex = 7,
		Max = 26,
	}, function()
		if ((player:GetAttribute("Charge_Reroll") or 0) :: number) > 0 then
			Remotes.Power:InvokeServer("Enchant", "Token")
		elseif Ui.Buy then
			Ui.Buy("Product", "Reroll3")
		end
	end)

	local function refresh()
		local id = player:GetAttribute("PowerId")
		local power = type(id) == "string" and KnifePowers.ById[id] or nil
		local level = (player:GetAttribute("PowerLevel") or 1) :: number
		local xp = (player:GetAttribute("PowerXP") or 0) :: number
		local cash = (player:GetAttribute("Cash") or 0) :: number

		-- the rows
		local have = levels()
		local best = bestKnives()
		table.clear(equipItem)
		for _, row in rows do
			local pid = row.Power.Id
			local isMine = power ~= nil and power.Id == pid
			local lv = if isMine then level else have[pid]
			local tier = KnifePowers.TierById[row.Power.Tier]
			row.Name.Text = `<font color="#{tier.Color:ToHex()}">{row.Power.Name}</font>`
				.. (if lv then `  <font color="#FFD746">Lv {lv}</font>` else "")
			row.Icon.ImageColor3 = if lv or best[pid] then Color3.new(1, 1, 1) else Color3.fromRGB(70, 75, 95)
			if isMine then
				SimpleUi.set(row.Main, "Equipped", GREEN, true) -- (green, and tapping does nothing)
			elseif best[pid] then
				equipItem[pid] = best[pid]
				SimpleUi.set(row.Main, "Equip", BLUE, true)
			else
				SimpleUi.set(row.Main, "🔒 Locked", GREY, false) -- (powers are random rolls on knives you bring home)
			end
		end

		-- the bottom bar
		if power then
			local tier = KnifePowers.TierById[power.Tier]
			mineIcon.Image = Icons.KnifePowers[power.Id] or VoxelUi.Hud.Powers
			mineName.Text = `Your power: <font color="#{tier.Color:ToHex()}">{power.Name}</font>  Lv {level}`
		else
			mineIcon.Image = VoxelUi.Hud.Powers
			mineName.Text = "Steal a knife to get a power!"
		end
		local from, to = GameConfig.PowerXPFor(level), GameConfig.PowerXPFor(level + 1)
		local ratio = if level >= 100 then 1 else math.clamp((xp - from) / math.max(1, to - from), 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		fill.Visible = ratio > 0
		barText.Text = if level >= 100 then "MAX LEVEL" else `Lv {level + 1}: {xp - from} / {to - from}`
		local fighting = player:GetAttribute("FightingKnife")
		local cost = if type(fighting) == "string" and Items.Parse(fighting)
			then math.max(
				GameConfig.Enchant.MinCost,
				math.floor(Items.Income(fighting) * GameConfig.Enchant.CostSeconds)
			)
			else GameConfig.Enchant.MinCost
		SimpleUi.set(reroll, `🔮 Re-roll ${Ui.abbreviate(cost)}`, PURPLE, power ~= nil and cash >= cost)
		local tokens = (player:GetAttribute("Charge_Reroll") or 0) :: number
		SimpleUi.set(token, if tokens > 0 then `🔮 Token ({tokens})` else "Get Tokens", GREEN, true)
	end
	for _, attribute in
		{
			"PowerId",
			"PowerLevel",
			"PowerXP",
			"PowerLevels",
			"FightingKnife",
			"Knives",
			"Equipped",
			"Charge_Reroll",
			"Cash",
		}
	do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if frame.Visible then
				refresh()
			end
		end)
	end
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			refresh()
		end
	end)
	refresh()
	return frame, refresh
end

return View
