--!strict
-- Powers, one system (docs/POWERS.md): every knife carries a power with a Murderer side and an
-- Innocent side. Top: the power on the knife you fight with, its level and XP to the next. Below:
-- every power by tier with both sides and your level in it (the collection to chase). Nothing is
-- bought here any more: you get powers by stealing knives, and levels by playing.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ui = require(script.Parent.Ui)
local SimpleUi = require(script.Parent.SimpleUi)
local VoxelUi = require(ReplicatedStorage.Shared.Config.VoxelUi)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local KnifePowers = require(ReplicatedStorage.Shared.Config.KnifePowers)
local Items = require(ReplicatedStorage.Shared.Items)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local View = {}

local PURPLE = Color3.fromRGB(150, 70, 235)
local MURDERER = Color3.fromRGB(255, 110, 110)
local INNOCENT = Color3.fromRGB(120, 200, 255)

local function innocentText(power: KnifePowers.KnifePower): string
	if power.Innocent == "SecondLife" then
		return "Second Life: once a round, survive a killing hit and vanish"
	end
	for _, entry in GameConfig.Powers do
		if entry.Id == power.Innocent then
			return `{entry.DisplayName}: {entry.Description}`
		end
	end
	return power.InnocentName
end

local function murdererText(power: KnifePowers.KnifePower): string
	local perk = GameConfig.Perks[power.Id]
	return if perk then `{perk.DisplayName}: {perk.Description}` else "Coming soon"
end

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

function View.Build(): (Frame, () -> ())
	local frame, body = SimpleUi.window("Innocent Powers", "Powers", VoxelUi.Hud.Powers, PURPLE, Vector2.new(1000, 760))

	-- Your power: the knife you fight with
	local mine: Frame = Ui.new("Frame", {
		Size = UDim2.new(1, 0, 0, 170),
		BackgroundColor3 = Color3.fromRGB(44, 30, 70),
		BackgroundTransparency = 0.15,
		ZIndex = 6,
	}, body)
	Ui.corner(mine, 14)
	Ui.new("UIStroke", { Color = PURPLE, Thickness = 3 }, mine)
	local mineTitle = SimpleUi.text(mine, "", {
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -300, 0, 46),
		TextXAlignment = Enum.TextXAlignment.Left,
		Max = 40,
	})
	local mineM = SimpleUi.text(mine, "", {
		Position = UDim2.fromOffset(16, 56),
		Size = UDim2.new(1, -300, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = MURDERER,
		Max = 24,
	})
	local mineI = SimpleUi.text(mine, "", {
		Position = UDim2.fromOffset(16, 88),
		Size = UDim2.new(1, -300, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = INNOCENT,
		Max = 24,
	})
	-- XP bar to the next level
	local bar: Frame = Ui.new("Frame", {
		Position = UDim2.new(0, 16, 1, -40),
		Size = UDim2.new(1, -300, 0, 28),
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
	local barText = SimpleUi.text(bar, "", { Size = UDim2.fromScale(1, 1), Max = 20, ZIndex = 9 })

	-- The Enchanter (Madame Vesper): re-roll this knife's power for cash or a Reroll Token
	local enchantCash = SimpleUi.button(mine, "", PURPLE, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(264, 48),
		ZIndex = 8,
		Max = 24,
	}, function()
		Remotes.Power:InvokeServer("Enchant", "Cash")
	end)
	local enchantToken = SimpleUi.button(mine, "", Color3.fromRGB(110, 60, 200), {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 64),
		Size = UDim2.fromOffset(264, 44),
		ZIndex = 8,
		Max = 22,
	}, function()
		Remotes.Power:InvokeServer("Enchant", "Token")
	end)
	SimpleUi.button(mine, "Get Reroll Tokens", Color3.fromRGB(0, 176, 111), {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 114),
		Size = UDim2.fromOffset(264, 44),
		ZIndex = 8,
		Max = 22,
	}, function()
		if Ui.Buy then
			Ui.Buy("Product", "Reroll3")
		end
	end)

	-- Every power, by tier
	local list: ScrollingFrame = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 182),
		Size = UDim2.new(1, 0, 1, -182),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 6,
	}, body)
	Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	Ui.new("UIPadding", { PaddingRight = UDim.new(0, 12) }, list)
	type Row = { Level: TextLabel, Power: KnifePowers.KnifePower }
	local rows: { Row } = {}
	for i, power in KnifePowers.List do
		local tier = KnifePowers.TierById[power.Tier]
		local row: Frame = Ui.new("Frame", {
			LayoutOrder = KnifePowers.TierRank(power.Tier) * 100 + i,
			Size = UDim2.new(1, 0, 0, 100),
			BackgroundColor3 = Color3.fromRGB(34, 38, 56),
			BackgroundTransparency = if power.Ready then 0.2 else 0.55,
			ZIndex = 6,
		}, list)
		Ui.corner(row, 12)
		Ui.new("UIStroke", { Color = tier.Color, Thickness = 2 }, row)
		SimpleUi.text(row, power.Name, {
			Position = UDim2.fromOffset(14, 6),
			Size = UDim2.new(0.4, 0, 0, 36),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = tier.Color,
			Max = 32,
		})
		SimpleUi.text(row, string.upper(power.Tier) .. (if power.Ready then "" else "  ·  COMING SOON"), {
			Position = UDim2.new(0.4, 0, 0, 10),
			Size = UDim2.new(0.35, 0, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = tier.Color,
			Max = 20,
		})
		local level = SimpleUi.text(row, "", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 6),
			Size = UDim2.new(0.22, 0, 0, 34),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Color3.fromRGB(255, 215, 70),
			Max = 28,
		})
		SimpleUi.text(row, `🔪 {murdererText(power)}`, {
			Position = UDim2.fromOffset(14, 44),
			Size = UDim2.new(1, -28, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = MURDERER,
			Max = 18,
		})
		SimpleUi.text(row, `😇 {innocentText(power)}`, {
			Position = UDim2.fromOffset(14, 70),
			Size = UDim2.new(1, -28, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = INNOCENT,
			Max = 18,
		})
		table.insert(rows, { Level = level, Power = power })
	end

	local function refresh()
		local id = player:GetAttribute("PowerId")
		local power = type(id) == "string" and KnifePowers.ById[id] or nil
		local level = (player:GetAttribute("PowerLevel") or 1) :: number
		local xp = (player:GetAttribute("PowerXP") or 0) :: number
		if power then
			local tier = KnifePowers.TierById[power.Tier]
			mineTitle.Text = `Your power: <font color="#{tier.Color:ToHex()}">{power.Name}</font>  Lv {level}`
			mineM.Text = `🔪 As the Murderer — {murdererText(power)}`
			mineI.Text = `😇 As an Innocent / Sheriff — {innocentText(power)}`
		else
			mineTitle.Text = "Your power: none yet"
			mineM.Text = "Steal a knife: every knife carries a power."
			mineI.Text = "The knife you fight with is the power you bring to every round."
		end
		local from, to = GameConfig.PowerXPFor(level), GameConfig.PowerXPFor(level + 1)
		local ratio = if level >= 100 then 1 else math.clamp((xp - from) / math.max(1, to - from), 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		fill.Visible = ratio > 0
		barText.Text = if level >= 100 then "MAX LEVEL" else `Lv {level} → {level + 1}: {xp - from} / {to - from} XP`
		local fighting = player:GetAttribute("FightingKnife")
		local cost = if type(fighting) == "string" and Items.Parse(fighting)
			then math.max(
				GameConfig.Enchant.MinCost,
				math.floor(Items.Income(fighting) * GameConfig.Enchant.CostSeconds)
			)
			else GameConfig.Enchant.MinCost
		local tokens = (player:GetAttribute("Charge_Reroll") or 0) :: number
		SimpleUi.set(
			enchantCash,
			`🔮 Re-roll  ${Ui.abbreviate(cost)}`,
			PURPLE,
			((player:GetAttribute("Cash") or 0) :: number) >= cost
		)
		SimpleUi.set(enchantToken, `🔮 Use a Token ({tokens})`, Color3.fromRGB(110, 60, 200), tokens > 0)
		local mineLevels = levels()
		for _, row in rows do
			local have = mineLevels[row.Power.Id]
			row.Level.Text = if have then `Lv {have}` else ""
		end
	end
	for _, attribute in { "PowerId", "PowerLevel", "PowerXP", "PowerLevels", "FightingKnife", "Charge_Reroll", "Cash" } do
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
