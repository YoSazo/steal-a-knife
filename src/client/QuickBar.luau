--!strict
-- The right side of the HUD, Steal An Egg style: only the two things you use all the time.
--   Knives: your wall as Tsunami-simple rows (icon, name, $/s, one Equip button), "Equip Best", and
--           the next floor ("+10 slots") - Steal An Egg's "9/12 Active, +1 EQUIP, Equip Best" panel
--   Powers: the Power Mystic panel (client/PowersView, registered by Menus as Ui.Panels.Powers)
-- Everything else moved into the world: Upgrade Wheel sign by your Haunted Wheel, the Lucky Wheel
-- and the Mystery Merchant on the plaza, the free chest on the plaza.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local SimpleUi = require(script.Parent.SimpleUi)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local VoxelUi = require(ReplicatedStorage.Shared.Config.VoxelUi)
local Items = require(ReplicatedStorage.Shared.Items)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local new = Ui.new

local QuickBar = {}

local GOLD = Color3.fromRGB(255, 190, 40)
local GREEN = Color3.fromRGB(80, 210, 50)
local BLUE = Color3.fromRGB(70, 150, 255)

-- The knife you'd fight best with: highest damage, then highest income
local function bestKnife(owned: { string }): string?
	local best: string? = nil
	local bestDamage, bestIncome = -1, -1
	for _, item in owned do
		local damage, income = Items.Damage(item), Items.Income(item)
		if damage > bestDamage or (damage == bestDamage and income > bestIncome) then
			best, bestDamage, bestIncome = item, damage, income
		end
	end
	return best
end

local function buildKnivesPanel(): (Frame, () -> ())
	local frame, body = SimpleUi.window("QuickKnives", "Your Knives", VoxelUi.Hud.Knives, GOLD, Vector2.new(720, 700))
	-- Top: how full your wall is, Equip Best, and the next floor
	local count = SimpleUi.text(body, "", {
		Size = UDim2.new(0.34, 0, 0, 64),
		TextXAlignment = Enum.TextXAlignment.Left,
		Max = 34,
	})
	local equipBest = SimpleUi.button(body, "Equip Best", BLUE, {
		Position = UDim2.fromScale(0.35, 0),
		Size = UDim2.new(0.3, -8, 0, 64),
		Max = 30,
	}, function()
		local best = bestKnife(Ui.list(player:GetAttribute("Knives")))
		if best and best ~= player:GetAttribute("Equipped") then
			Remotes.Equip:InvokeServer(best)
		end
	end)
	local floorButton = SimpleUi.button(body, "", GREEN, {
		Position = UDim2.fromScale(0.65, 0),
		Size = UDim2.new(0.35, 0, 0, 64),
		Max = 28,
	}, function()
		Remotes.Purchase:InvokeServer("Slot")
	end)
	local list = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 76),
		Size = UDim2.new(1, 0, 1, -76),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 6,
	}, body)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	Ui.new("UIPadding", { PaddingRight = UDim.new(0, 10) }, list)

	local function refresh()
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local owned = Ui.list(player:GetAttribute("Knives"))
		local slots = (player:GetAttribute("Slots") or GameConfig.StartingSlots) :: number
		local cash = (player:GetAttribute("Cash") or 0) :: number
		local equipped = player:GetAttribute("Equipped") or ""
		count.Text = `{#owned}/{slots} on your wall`
		local best = bestKnife(owned)
		SimpleUi.set(equipBest, if best and best == equipped then "Best ✓" else "Equip Best", BLUE, best ~= equipped)
		-- The next floor: +10 plates (later floors wait for a rebirth)
		local floorRebirths = GameConfig.FloorRebirthsFor(slots)
		if slots >= GameConfig.MaxSlots then
			SimpleUi.set(floorButton, "Wall maxed", GOLD, false)
		elseif ((player:GetAttribute("Rebirths") or 0) :: number) < floorRebirths then
			SimpleUi.set(floorButton, `+10 slots: Rebirth {floorRebirths}`, Color3.fromRGB(160, 70, 235), false)
		else
			local cost = GameConfig.SlotCost(slots)
			SimpleUi.set(floorButton, `+10 slots  ${Ui.abbreviate(cost)}`, GREEN, cash >= cost)
		end
		if #owned == 0 then
			local empty = new("Frame", { Size = UDim2.new(1, 0, 0, 90), BackgroundTransparency = 1, ZIndex = 6 }, list)
			SimpleUi.text(empty, "Steal a knife from a boss and carry it home!", {
				Size = UDim2.fromScale(1, 1),
				Max = 30,
			})
			return
		end
		-- Best first
		local sorted = table.clone(owned)
		table.sort(sorted, function(a, b)
			return Items.Income(a) > Items.Income(b)
		end)
		local equippedShown = false
		for order, item in sorted do
			local parsed = Items.Parse(item)
			if not parsed then
				continue
			end
			local knife = parsed.Knife
			local row = new("Frame", {
				LayoutOrder = order,
				Size = UDim2.new(1, 0, 0, 92),
				BackgroundColor3 = Color3.fromRGB(34, 38, 56),
				BackgroundTransparency = 0.2,
				ZIndex = 6,
			}, list)
			Ui.corner(row, 12)
			Ui.art(row, knife.Name, {
				Position = UDim2.fromOffset(8, 6),
				Size = UDim2.fromOffset(80, 80),
				ZIndex = 7,
			})
			SimpleUi.text(row, Items.DisplayName(item), {
				Position = UDim2.fromOffset(98, 8),
				Size = UDim2.new(1, -310, 0, 40),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Knives.RarityColors[knife.Rarity],
				Max = 30,
			})
			SimpleUi.text(row, `+${Ui.abbreviate(Items.Income(item))}/s  ·  {knife.Rarity}`, {
				Position = UDim2.fromOffset(98, 50),
				Size = UDim2.new(1, -310, 0, 32),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.fromRGB(120, 255, 140),
				Max = 24,
			})
			local isEquipped = item == equipped and not equippedShown
			equippedShown = equippedShown or isEquipped
			SimpleUi.button(row, if isEquipped then "Equipped ✓" else "Equip", if isEquipped then GREEN else BLUE, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(190, 70),
				ZIndex = 7,
				Max = 30,
			}, function()
				if not isEquipped then
					Remotes.Equip:InvokeServer(item)
				end
			end)
		end
	end
	for _, attribute in { "Knives", "Equipped", "Slots", "Rebirths" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if frame.Visible then
				refresh()
			end
		end)
	end
	player:GetAttributeChangedSignal("Cash"):Connect(function()
		if frame.Visible then
			-- (only the floor button depends on cash: cheap enough to redo the lot at this size)
			refresh()
		end
	end)
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			refresh()
		end
	end)
	return frame, refresh
end

-- One of the right-side buttons (HudSkin gives them the voxel look; PhoneHud lays them out)
local function sideButton(name: string, text: string, color: Color3, icon: string, y: number, onClick: () -> ())
	return Theme.button(Ui.gui, text, color, {
		AnchorPoint = Vector2.new(1, 0),
		Name = name,
		Position = UDim2.new(1, -12, 0, y),
		Size = UDim2.fromOffset(120, 44),
		MaximumTextSize = 20,
	}, onClick, icon)
end

function QuickBar.Init()
	local knivesFrame = buildKnivesPanel()
	Ui.Panels.QuickKnives = knivesFrame
	local knivesButton = sideButton("KnivesButton", "Knives", GOLD, "Knives", 56, function()
		Ui.Menu.Toggle(knivesFrame)
	end)
	local powersButton = sideButton("PowersButton", "Powers", Color3.fromRGB(255, 148, 28), "Powers", 108, function()
		local powers = Ui.Panels.Powers
		if powers then
			Ui.Menu.Toggle(powers)
		end
	end)
	-- A "!" on Knives when you're not holding your best knife (Steal An Egg's "+1 EQUIP")
	local badge = Theme.badge(knivesButton)
	local function refreshBadge()
		local best = bestKnife(Ui.list(player:GetAttribute("Knives")))
		badge.Visible = best ~= nil and best ~= player:GetAttribute("Equipped")
		badge.Text = "!"
	end
	player:GetAttributeChangedSignal("Knives"):Connect(refreshBadge)
	player:GetAttributeChangedSignal("Equipped"):Connect(refreshBadge)
	refreshBadge()
	-- Out of the way during rounds and while menus are open
	RunService.Heartbeat:Connect(function()
		local show = Ui.inHub() and not Ui.menuOpen()
		knivesButton.Visible = show
		powersButton.Visible = show
	end)
end

return QuickBar
