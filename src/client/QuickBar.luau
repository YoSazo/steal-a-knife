--!strict
-- The right side of the HUD, Steal An Egg style: only the two things you use all the time.
--   Knives: your wall as Tsunami-simple rows (icon, name, $/s, Sell and Equip), "Equip Best", and
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
local ORANGE = Color3.fromRGB(230, 150, 50)

-- Sizes: phones get their own smaller design, so the window shrinks far less to fit and the words
-- stay readable (the desktop design was scaled to 0.4 on a 640 x 300 screen)
local PHONE = { Window = Vector2.new(560, 420), Top = 54, RowH = 70, Art = 58, Equip = 120, Sell = 108, ButtonH = 54 }
local DESKTOP = { Window = Vector2.new(720, 700), Top = 64, RowH = 92, Art = 80, Equip = 180, Sell = 150, ButtonH = 70 }

local function buildKnivesPanel(): (Frame, () -> ())
	local S = if Ui.Phone then PHONE else DESKTOP
	local frame, body = SimpleUi.window("QuickKnives", "Your Knives", VoxelUi.Hud.Knives, GOLD, S.Window)
	-- Top: how full your vault is, Equip Best, and more room
	local count = SimpleUi.text(body, "", {
		Size = UDim2.new(0.34, 0, 0, S.Top),
		TextXAlignment = Enum.TextXAlignment.Left,
		Max = 34,
	})
	local selectionMode = SimpleUi.text(body, "Best power: auto", {
		Position = UDim2.fromScale(0.35, 0),
		Size = UDim2.new(0.3, -8, 0, S.Top),
		Max = 20,
	})
	local floorButton = SimpleUi.button(body, "", GREEN, {
		Position = UDim2.fromScale(0.65, 0),
		Size = UDim2.new(0.35, 0, 0, S.Top),
		Max = 28,
	}, function()
		Remotes.Purchase:InvokeServer("Slot")
	end)
	local list = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, S.Top + 12),
		Size = UDim2.new(1, 0, 1, -(S.Top + 12)),
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
		local equipped = player:GetAttribute("FightingKnife") or ""
		selectionMode.Text = if player:GetAttribute("Equipped") ~= "" then "Your pick: ON" else "Best power: auto"
		count.Text = `{#owned}/{slots} in your vault`
		-- The next floor: +10 plates (later floors wait for a rebirth)
		local floorRebirths = GameConfig.FloorRebirthsFor(slots)
		if slots >= GameConfig.MaxSlots then
			SimpleUi.set(floorButton, "Vault is max size", GOLD, false)
		elseif ((player:GetAttribute("Rebirths") or 0) :: number) < floorRebirths then
			SimpleUi.set(floorButton, "🔒 More room after Rebirth", Color3.fromRGB(160, 70, 235), false)
		else
			local cost = GameConfig.SlotCost(slots)
			SimpleUi.set(floorButton, `+10 room  ${Ui.abbreviate(cost)}`, GREEN, cash >= cost)
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
		-- (each keeps its place in the wall list: the server sells by that index)
		local sorted: { { Item: string, Index: number } } = {}
		for index, item in owned do
			table.insert(sorted, { Item = item, Index = index })
		end
		table.sort(sorted, function(a, b)
			return Items.Income(a.Item) > Items.Income(b.Item)
		end)
		local equippedShown = false
		for order, entry in sorted do
			local item = entry.Item
			local parsed = Items.Parse(item)
			if not parsed then
				continue
			end
			local knife = parsed.Knife
			local row = new("Frame", {
				LayoutOrder = order,
				Size = UDim2.new(1, 0, 0, S.RowH),
				BackgroundColor3 = Color3.fromRGB(34, 38, 56),
				BackgroundTransparency = 0.2,
				ZIndex = 6,
			}, list)
			Ui.corner(row, 12)
			Ui.art(row, knife.Name, {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 6, 0.5, 0),
				Size = UDim2.fromOffset(S.Art, S.Art),
				ZIndex = 7,
			})
			local textX = S.Art + 16
			local textW = -(textX + S.Equip + S.Sell + 30)
			SimpleUi.text(row, Items.DisplayName(item), {
				Position = UDim2.fromOffset(textX, 6),
				Size = UDim2.new(1, textW, 0.45, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Knives.RarityColors[knife.Rarity],
				Max = 30,
			})
			SimpleUi.text(row, `+${Ui.abbreviate(Items.Income(item))}/s  ·  {knife.Rarity}`, {
				Position = UDim2.new(0, textX, 0.52, 0),
				Size = UDim2.new(1, textW, 0.38, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.fromRGB(120, 255, 140),
				Max = 24,
			})
			local isEquipped = item == equipped and not equippedShown
			equippedShown = equippedShown or isEquipped
			SimpleUi.button(row, if isEquipped then "Equipped ✓" else "Equip", if isEquipped then GREEN else BLUE, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(S.Equip, S.ButtonH),
				ZIndex = 7,
				Max = 30,
			}, function()
				if not isEquipped then
					Remotes.Equip:InvokeServer(item)
				end
			end)
			-- Sell, same as More > Knives
			SimpleUi.button(row, `Sell ${Ui.abbreviate(Items.Income(item) * GameConfig.SellSeconds)}`, ORANGE, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -(S.Equip + 18), 0.5, 0),
				Size = UDim2.fromOffset(S.Sell, S.ButtonH),
				ZIndex = 7,
				Max = 24,
			}, function()
				Remotes.Sell:InvokeServer(entry.Index)
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
	Ui.GuideTargets.Knives = knivesButton
	Ui.GuideTargets.Powers = powersButton
	-- A "!" on Knives when you're not holding your best knife (Steal An Egg's "+1 EQUIP")
	local badge = Theme.badge(knivesButton)
	local function refreshBadge()
		badge.Visible = false
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
