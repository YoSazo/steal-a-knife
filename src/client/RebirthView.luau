--!strict
-- Rebirth, Tsunami-simple: current -> next multiplier, one line on what resets, a cash bar, and one
-- huge REBIRTH button.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ui = require(script.Parent.Ui)
local SimpleUi = require(script.Parent.SimpleUi)
local VoxelUi = require(ReplicatedStorage.Shared.Config.VoxelUi)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local player = Players.LocalPlayer
local Remotes = ReplicatedStorage.Remotes
local View = {}

local PURPLE = Color3.fromRGB(160, 70, 235)
local GREEN = Color3.fromRGB(80, 210, 50)
local GOLD = Color3.fromRGB(255, 185, 30)

local function tile(parent: Instance, color: Color3, position: UDim2, size: UDim2): Frame
	local frame: Frame = Ui.new("Frame", {
		Position = position,
		Size = size,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 6,
	}, parent)
	Ui.corner(frame, 14)
	Ui.new("UIStroke", { Color = Color3.fromRGB(16, 14, 24), Thickness = 3 }, frame)
	Ui.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.2), color:Lerp(Color3.new(0, 0, 0), 0.12)),
	}, frame)
	return frame
end

function View.Build(): (Frame, () -> ())
	local frame, body = SimpleUi.window("Rebirth", "Rebirth", VoxelUi.Hud.Rebirth, PURPLE, Vector2.new(900, 600))
	local labels: { TextLabel } = {}
	local values: { TextLabel } = {}
	for i, color in { GREEN, GOLD } do
		local x = if i == 1 then 0 else 0.56
		labels[i] = SimpleUi.text(body, "", {
			Position = UDim2.fromScale(x, 0),
			Size = UDim2.new(0.44, 0, 0, 44),
			Max = 36,
		})
		local box = tile(body, color, UDim2.new(x, 0, 0, 50), UDim2.new(0.44, 0, 0, 110))
		Ui.new("ImageLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.fromOffset(86, 86),
			Image = VoxelUi.Hud.Cash,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 7,
		}, box)
		values[i] = SimpleUi.text(box, "", {
			Position = UDim2.fromOffset(104, 14),
			Size = UDim2.new(1, -116, 1, -28),
			Max = 52,
		})
	end
	SimpleUi.text(body, "➜", {
		Position = UDim2.new(0.44, 0, 0, 60),
		Size = UDim2.new(0.12, 0, 0, 90),
		Max = 80,
	})
	local note = SimpleUi.text(body, "", {
		Position = UDim2.fromOffset(0, 178),
		Size = UDim2.new(1, 0, 0, 40),
		Max = 32,
	})
	-- Cash bar
	local bar: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(0, 230),
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = Color3.fromRGB(26, 30, 44),
		ZIndex = 6,
	}, body)
	Ui.corner(bar, 14)
	Ui.new("UIStroke", { Color = Color3.fromRGB(16, 14, 24), Thickness = 3 }, bar)
	local fill = tile(bar, Color3.fromRGB(40, 190, 255), UDim2.fromOffset(4, 4), UDim2.new(0, 0, 1, -8))
	fill.ZIndex = 7
	local barText = SimpleUi.text(bar, "", {
		Size = UDim2.fromScale(1, 1),
		Max = 40,
		ZIndex = 9,
	})
	local action = SimpleUi.button(body, "REBIRTH", PURPLE, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(0.7, 0, 0, 110),
		ZIndex = 7,
		Max = 64,
	}, function()
		Remotes.Purchase:InvokeServer("Rebirth")
	end, VoxelUi.Hud.Rebirth)

	local function refresh()
		local rebirths = (player:GetAttribute("Rebirths") or 0) :: number
		local cash = (player:GetAttribute("Cash") or 0) :: number
		local config = GameConfig.Rebirth
		local maximum = rebirths >= config.Max
		local nextCount = if maximum then rebirths else rebirths + 1
		local cost = GameConfig.RebirthCost(rebirths)
		labels[1].Text = `Rebirth {rebirths}`
		labels[2].Text = if maximum then "MAX" else `Rebirth {nextCount}`
		values[1].Text = `{1 + rebirths * config.IncomeBonus}x Money`
		values[2].Text = `{1 + nextCount * config.IncomeBonus}x Money`
		-- Steal a Brainrot style: a knife of this rarity has to be in your vault too
		local need = GameConfig.RebirthNeeds(rebirths)
		local hasNeed = false
		for _, item in Ui.list(player:GetAttribute("Knives")) do
			local parsed = Items.Parse(item)
			if parsed and Knives.Rank(parsed.Knife.Rarity) >= Knives.Rank(need) then
				hasNeed = true
				break
			end
		end
		note.Text = if maximum
			then "You've reached the final rebirth!"
			else `Needs a <font color="{if hasNeed then "#78FF6E" else "#FF6E6E"}">{need} knife {if hasNeed
				then "✓"
				else "✗"}</font>  ·  resets cash, knives & speed  ·  <font color="#78FF6E">+{math.floor(
				nextCount * config.LuckBonus * 100
			)}% luck</font>`
		local ratio = if maximum then 1 else math.clamp(cash / cost, 0, 1)
		fill.Size = UDim2.new(ratio, -8 * ratio, 1, -8)
		fill.Visible = ratio > 0
		barText.Text = if maximum then "MAX REBIRTH!" else `${Ui.abbreviate(cash)} / ${Ui.abbreviate(cost)}`
		local carrying = player:GetAttribute("Carrying")
		local blocked = player:GetAttribute("InRound") == true
			or (carrying ~= nil and carrying ~= false and carrying ~= "")
		local text = if maximum
			then "MAX"
			elseif blocked then "Finish your run first"
			elseif not hasNeed then `Need a {need} knife`
			else "REBIRTH"
		SimpleUi.set(action, text, PURPLE, not maximum and not blocked and hasNeed and cash >= cost)
	end
	for _, attribute in { "Cash", "Rebirths", "InRound", "Carrying", "Knives" } do
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
