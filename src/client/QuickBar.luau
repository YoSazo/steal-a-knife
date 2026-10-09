--!strict
-- One character inventory: waiting coffins and unlocked characters, with a READY count.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local SimpleUi = require(script.Parent.SimpleUi)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local PenMode = require(ReplicatedStorage.Shared.PenMode)
local Items = require(ReplicatedStorage.Shared.Items)
local Format = require(ReplicatedStorage.Shared.Format)
local CoffinState = require(ReplicatedStorage.Shared.CoffinState)
local VoxelUi = require(ReplicatedStorage.Shared.Config.VoxelUi)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local QuickBar = {}
local GOLD, GREEN, BLUE = Color3.fromRGB(255, 190, 40), Color3.fromRGB(80, 210, 50), Color3.fromRGB(70, 150, 255)
local S = { Art = 54, Top = 44, Row = 76, Button = 48 }

function QuickBar.Init()
	local frame, body = SimpleUi.window(
		"QuickKnives",
		"My Knives",
		VoxelUi.Hud.Knives,
		GOLD,
		if Ui.Phone then Vector2.new(560, 210) else Vector2.new(760, 620)
	)
	Ui.Panels.QuickKnives = frame
	local count = SimpleUi.text(
		body,
		"",
		{ Size = UDim2.new(0.45, 0, 0, S.Top), TextXAlignment = Enum.TextXAlignment.Left, Max = 26 }
	)
	local room = SimpleUi.button(
		body,
		"",
		GREEN,
		{ Position = UDim2.fromScale(0.55, 0), Size = UDim2.new(0.45, 0, 0, S.Top), Max = 24 },
		function()
			Remotes.Purchase:InvokeServer("Slot")
		end
	)
	local list: ScrollingFrame = Ui.new("ScrollingFrame", {
		Name = "Characters",
		Position = UDim2.fromOffset(0, S.Top + 6),
		Size = UDim2.new(1, 0, 1, -S.Top - 6),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 6,
	}, body)
	Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	Ui.new("UIPadding", { PaddingRight = UDim.new(0, 10) }, list)
	type Timer = { Entry: CoffinState.Entry, Text: TextLabel, Button: TextButton }
	local timers: { Timer } = {}
	local function open(plate: number)
		local ok, message = Remotes.OpenCoffin:InvokeServer(plate)
		if not ok and Ui.Toast then
			Ui.Toast(message, "bad")
		end
	end
	local function updateTimers()
		local now = workspace:GetServerTimeNow()
		for _, timer in timers do
			local entry = timer.Entry
			local ready = CoffinState.Ready(entry.Rounds, entry.OpensAt, now)
			timer.Text.Text = if ready
				then "READY!"
				elseif entry.Rounds >= 0 then `Unlocks after {entry.Rounds} rounds`
				else `Unlocks in {Format.Duration(math.max(0, entry.OpensAt - now))}`
			SimpleUi.set(timer.Button, if ready then "READY!" else "Unlock R$19", if ready then GREEN else BLUE)
		end
	end
	local function refreshRoom()
		local slots = (player:GetAttribute("Slots") or GameConfig.StartingSlots) :: number
		local cash = (player:GetAttribute("Cash") or 0) :: number
		local cost, step = PenMode.RoomUpgrade(slots)
		local n = #Ui.list(player:GetAttribute("Knives"))
		count.Text = `{n} {if n == 1 then "Knife" else "Knives"}`
		SimpleUi.set(
			room,
			if slots >= PenMode.MaxSlots() then "Full size!" else `+{step} room {Format.Cash(cost)}`,
			GREEN,
			slots < PenMode.MaxSlots() and cash >= cost
		)
	end
	local function refresh()
		table.clear(timers)
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		refreshRoom()
		local owned = Ui.list(player:GetAttribute("Knives"))
		local plates = Ui.list(player:GetAttribute("KnifePlates"))
		local coffins = CoffinState.Parse(player:GetAttribute("CoffinList"))
		local sealed: { [number]: boolean } = {}
		for _, v in Ui.list(player:GetAttribute("SealedKnives")) do
			sealed[tonumber(v) or 0] = true
		end
		if #owned == 0 then
			local empty =
				Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 76), BackgroundTransparency = 1, ZIndex = 6 }, list)
			SimpleUi.text(empty, "Steal a monster's coffin!", { Size = UDim2.fromScale(1, 1), Max = 28 })
			return
		end
		local sorted: { { Item: string, Index: number, Plate: number } } = {}
		for index, item in owned do
			table.insert(sorted, { Item = item, Index = index, Plate = tonumber(plates[index]) or index })
		end
		table.sort(sorted, function(a, b)
			local ca, cb = coffins[a.Plate], coffins[b.Plate]
			local ra = ca and CoffinState.Ready(ca.Rounds, ca.OpensAt, workspace:GetServerTimeNow()) or false
			local rb = cb and CoffinState.Ready(cb.Rounds, cb.OpensAt, workspace:GetServerTimeNow()) or false
			if ra ~= rb then
				return ra
			end
			if sealed[a.Index] ~= sealed[b.Index] then
				return sealed[a.Index] == true
			end
			return Items.Income(a.Item) > Items.Income(b.Item)
		end)
		local equipped = player:GetAttribute("FightingKnife")
		local equippedShown = false
		for order, entry in sorted do
			local parsed = Items.Parse(entry.Item)
			if not parsed then
				continue
			end
			local hidden = sealed[entry.Index] == true
			local coffin = coffins[entry.Plate]
			local row: Frame = Ui.new("Frame", {
				Name = `Character{entry.Index}`,
				LayoutOrder = order,
				Size = UDim2.new(1, 0, 0, S.Row),
				BackgroundColor3 = Color3.fromRGB(34, 38, 56),
				BackgroundTransparency = 0.2,
				ZIndex = 6,
			}, list)
			Ui.corner(row, 12)
			if hidden then
				SimpleUi.text(
					row,
					"⚰️",
					{ Position = UDim2.new(0, 6, 0.1, 0), Size = UDim2.fromOffset(S.Art, S.Art), Max = 44 }
				)
			else
				Ui.art(
					row,
					parsed.Name,
					{ Position = UDim2.new(0, 6, 0.1, 0), Size = UDim2.fromOffset(S.Art, S.Art), ZIndex = 7 }
				)
			end
			local right = if hidden then 116 else 172
			local x = S.Art + 14
			SimpleUi.text(row, Items.DisplayName(entry.Item), {
				Position = UDim2.fromOffset(x, 4),
				Size = UDim2.new(1, -x - right, 0, 32),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Items.Color(entry.Item),
				Max = 26,
			})
			local detail =
				SimpleUi.text(row, if hidden then "Locked" else `{Format.Cash(Items.Income(entry.Item))}/s`, {
					Position = UDim2.fromOffset(x, 38),
					Size = UDim2.new(1, -x - right, 0, 30),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = GREEN,
					Max = 24,
				})
			if hidden then
				local button = SimpleUi.button(row, "", GREEN, {
					Name = "Ready",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -8, 0.5, 0),
					Size = UDim2.fromOffset(104, S.Button),
					ZIndex = 8,
					Max = 24,
				}, function()
					if coffin and CoffinState.Ready(coffin.Rounds, coffin.OpensAt, workspace:GetServerTimeNow()) then
						open(entry.Plate)
					elseif Ui.Buy then
						Remotes.CoffinTarget:FireServer(entry.Plate)
						Ui.Buy("Product", "CoffinOpen")
					end
				end)
				if coffin then
					table.insert(timers, { Entry = coffin, Text = detail, Button = button })
				end
			else
				local selected = entry.Item == equipped and not equippedShown
				equippedShown = equippedShown or selected
				SimpleUi.button(row, if selected then "✓" else "Equip", if selected then GREEN else BLUE, {
					Name = "Equip",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -8, 0.5, 0),
					Size = UDim2.fromOffset(76, S.Button),
					ZIndex = 8,
					Max = 24,
				}, function()
					Remotes.Equip:InvokeServer(entry.Item)
				end)
				SimpleUi.button(row, "Sell", Color3.fromRGB(230, 150, 50), {
					Name = "Sell",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -90, 0.5, 0),
					Size = UDim2.fromOffset(76, S.Button),
					ZIndex = 8,
					Max = 24,
				}, function()
					Remotes.Sell:InvokeServer(entry.Index)
				end)
			end
		end
		updateTimers()
	end
	for _, attribute in
		{ "Knives", "SealedKnives", "CoffinList", "CoffinsReady", "FightingKnife", "Slots", "KnifePlates" }
	do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if frame.Visible then
				refresh()
			end
		end)
	end
	player:GetAttributeChangedSignal("Cash"):Connect(refreshRoom)
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			refresh()
		end
	end)
	local button = Theme.button(Ui.gui, "My Knives", GOLD, {
		Name = "KnivesButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 56),
		Size = UDim2.fromOffset(140, 44),
		MaximumTextSize = 20,
	}, function()
		Ui.Menu.Toggle(frame)
	end, "Knives")
	Ui.GuideTargets.Knives = button
	local badge = Theme.badge(button)
	local nextUpdate = 0
	RunService.Heartbeat:Connect(function()
		button.Visible = Ui.inHub() and not Ui.menuOpen()
		local ready = (player:GetAttribute("CoffinsReady") or 0) :: number
		badge.Visible = ready > 0
		badge.Text = tostring(ready)
		if os.clock() >= nextUpdate and frame.Visible then
			nextUpdate = os.clock() + 0.25
			updateTimers()
		end
	end)
	ContextActionService:BindAction("ToggleKnives", function(_, state)
		if state == Enum.UserInputState.Begin and Ui.inHub() then
			Ui.Menu.Toggle(frame)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.K, Enum.KeyCode.ButtonL1)
	refreshRoom()
end
return QuickBar
