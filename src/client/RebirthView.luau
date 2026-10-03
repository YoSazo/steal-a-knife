--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local player = Players.LocalPlayer
local Remotes = ReplicatedStorage.Remotes
local View = {}

function View.Build(): (Frame, () -> ())
	local frame, body = Theme.shell("Rebirth", "Rebirth", Theme.Purple, "Rebirth", 450)
	local current = Theme.surface(body, { Name = "Current", Size = UDim2.new(0.36, -6, 0, 126) }, Theme.Green)
	local nextTier = Theme.surface(
		body,
		{ Name = "Next", Position = UDim2.fromScale(0.45, 0), Size = UDim2.new(0.34, -6, 0, 126) },
		Theme.Gold
	)
	Theme.arrow(
		body,
		{ Name = "UpgradeArrow", Position = UDim2.new(0.36, 0, 0, 30), Size = UDim2.new(0.09, -6, 0, 60) }
	)
	local titles, multipliers = {}, {}
	for i, pane in { current, nextTier } do
		titles[i] = Theme.text(pane, "", {
			Name = "RebirthNumber",
			Position = UDim2.fromOffset(6, 5),
			Size = UDim2.new(1, -12, 0, 42),
			MaximumTextSize = 37,
		})
		Theme.image(pane, "Cash", { Position = UDim2.fromOffset(12, 44), Size = UDim2.fromOffset(82, 74) })
		multipliers[i] = Theme.text(pane, "", {
			Name = "Multiplier",
			Position = UDim2.fromOffset(92, 46),
			Size = UDim2.new(1, -100, 0, 70),
			MaximumTextSize = 43,
		})
	end
	local benefits = {}
	for i, symbol in { "Training", "Luck" } do
		local pane = Theme.surface(
			body,
			{ Position = UDim2.new(0.8, 0, 0, (i - 1) * 66), Size = UDim2.new(0.2, 0, 0, 60) },
			if i == 1 then Theme.Cyan else Theme.Purple
		)
		Theme.image(pane, symbol, { Position = UDim2.fromOffset(2, 5), Size = UDim2.fromOffset(55, 50) })
		benefits[i] = Theme.text(
			pane,
			"",
			{ Position = UDim2.fromOffset(56, 2), Size = UDim2.new(1, -60, 1, -4), MaximumTextSize = 26 }
		)
	end
	local warning = Theme.surface(
		body,
		{ Name = "ResetWarning", Position = UDim2.fromOffset(0, 140), Size = UDim2.new(1, 0, 0, 48) },
		Theme.Navy,
		Color3.fromRGB(57, 116, 175)
	)
	Theme.image(warning, "Rebirth", { Position = UDim2.fromOffset(2, 4), Size = UDim2.fromOffset(40, 40) })
	Theme.text(warning, "Resets: cash, knives, mounts, speed, wheel, walls", {
		Position = UDim2.fromOffset(44, 4),
		Size = UDim2.new(0.64, -44, 1, -8),
		MaximumTextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	Theme.text(warning, "✓ Keeps: powers, Index, stats", {
		Position = UDim2.new(0.64, 6, 0, 4),
		Size = UDim2.new(0.36, -12, 1, -8),
		MaximumTextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local progress = Theme.surface(
		body,
		{ Name = "CashProgress", Position = UDim2.fromOffset(0, 200), Size = UDim2.new(1, 0, 0, 48) },
		Theme.Navy,
		Color3.fromRGB(57, 116, 175)
	)
	local fill = Theme.surface(
		progress,
		{ Position = UDim2.fromOffset(5, 5), Size = UDim2.new(0, 0, 1, -10), Visible = false },
		Theme.Green
	)
	local cashText =
		Theme.text(progress, "", { Name = "CashRequirement", Size = UDim2.fromScale(1, 1), MaximumTextSize = 38 })
	local action = Theme.button(body, "REBIRTH", Theme.Purple, {
		Name = "RebirthAction",
		Position = UDim2.new(0.12, 0, 0, 262),
		Size = UDim2.new(0.76, 0, 0, 66),
		MaximumTextSize = 52,
	}, function()
		Remotes.Purchase:InvokeServer("Rebirth")
	end, "Rebirth")
	local lock = Ui.new("Frame", {
		Name = "Locked",
		Position = UDim2.new(1, -66, 0.5, -22),
		Size = UDim2.fromOffset(38, 44),
		BackgroundTransparency = 1,
		ZIndex = 12,
	}, action)
	local lavender = Color3.fromRGB(180, 116, 240)
	local bow = Ui.new(
		"Frame",
		{ Position = UDim2.fromOffset(7, 0), Size = UDim2.fromOffset(24, 28), BackgroundTransparency = 1, ZIndex = 12 },
		lock
	)
	Ui.corner(bow, 12)
	Theme.outline(bow, lavender, 5)
	local plate = Ui.new("Frame", {
		Position = UDim2.fromOffset(2, 18),
		Size = UDim2.fromOffset(34, 24),
		BackgroundColor3 = lavender,
		BorderSizePixel = 0,
		ZIndex = 13,
	}, lock)
	Ui.corner(plate, 4)
	Ui.new("Frame", {
		Position = UDim2.fromOffset(15, 6),
		Size = UDim2.fromOffset(4, 11),
		BackgroundColor3 = Theme.Purple:Lerp(Theme.Navy, 0.75),
		BorderSizePixel = 0,
		ZIndex = 14,
	}, plate)
	local function refresh()
		local rebirths = player:GetAttribute("Rebirths") or 0
		local cash = player:GetAttribute("Cash") or 0
		local config = GameConfig.Rebirth
		local maximum = rebirths >= config.Max
		local nextCount = if maximum then rebirths else rebirths + 1
		local cost = GameConfig.RebirthCost(rebirths)
		titles[1].Text, titles[2].Text = `Rebirth {rebirths}`, if maximum then "MAX REBIRTH" else `Rebirth {nextCount}`
		multipliers[1].Text = `{1 + rebirths * config.IncomeBonus}x Income`
		multipliers[2].Text = `{1 + nextCount * config.IncomeBonus}x Income`
		benefits[1].Text = `+{math.floor(nextCount * config.SpeedBonus * 100)}%\nTraining`
		benefits[2].Text = `+{math.floor(nextCount * config.LuckBonus * 100)}%\nCase Luck`
		local ratio = if maximum then 1 else math.clamp(cash / cost, 0, 1)
		fill.Size, fill.Visible = UDim2.new(ratio, -10 * ratio, 1, -10), ratio > 0
		cashText.Text = if maximum then "MAXIMUM REBIRTH REACHED" else `${Ui.abbreviate(cash)} / ${Ui.abbreviate(cost)}`
		local carrying = player:GetAttribute("Carrying")
		local blocked = player:GetAttribute("InRound") == true
			or (carrying ~= nil and carrying ~= false and carrying ~= "")
		local label = if maximum then "MAX REBIRTH" elseif blocked then "FINISH YOUR CURRENT RUN" else "REBIRTH"
		Theme.enabled(action, not maximum and not blocked and cash >= cost, label)
		lock.Visible = action:GetAttribute("Disabled") == true
	end
	for _, attribute in { "Cash", "Rebirths", "InRound", "Carrying" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
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
