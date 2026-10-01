--!strict
-- The Innocent Power bar: one button per equipped power (keys Z / X / C, gamepad d-pad
-- Left / Up / Right, or tap). Shows the cooldown in the arena and the Energy cost in a round, and
-- hides itself while you're the Murderer. The server decides whether a use actually happens.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Ui = require(script.Parent.Ui)
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local new = Ui.new

local PowerBar = {}

local KEYS = { Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C }
local PAD = { Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadUp, Enum.KeyCode.DPadRight }
local KEY_LABELS = { "Z", "X", "C" }
local PAD_LABELS = { "◀", "▲", "▶" }

local byId: { [string]: any } = {}
for _, power in GameConfig.Powers do
	byId[power.Id] = power
end

local function aimDirection(): Vector3
	return workspace.CurrentCamera.CFrame.LookVector
end

function PowerBar.Init()
	local bar = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -78),
		Size = UDim2.fromOffset(3 * 96, 84),
		BackgroundTransparency = 1,
	}, Ui.gui)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
	}, bar)

	type Slot = { Button: TextButton, Name: TextLabel, Key: TextLabel, Shade: Frame, Count: TextLabel }
	local slots: { Slot } = {}
	local loadout: { string } = {}

	local function use(index: number)
		local id = loadout[index]
		if id and bar.Visible then
			Remotes.UsePower:FireServer(id, aimDirection())
		end
	end

	for i = 1, GameConfig.MaxPowerSlots do
		local button: TextButton = new("TextButton", {
			LayoutOrder = i,
			Size = UDim2.fromOffset(86, 84),
			AutoButtonColor = true,
			Text = "",
			BackgroundColor3 = Ui.PANEL,
			Visible = false,
		}, bar)
		Ui.corner(button, 14)
		new("UIStroke", { Thickness = 3, Color = Color3.new(1, 1, 1) }, button)
		local name = Ui.label({
			Position = UDim2.fromOffset(4, 22),
			Size = UDim2.new(1, -8, 0, 22),
			Text = "",
			TextStrokeTransparency = 0.4,
		}, button)
		local key = Ui.label({
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.fromOffset(22, 18),
			Text = KEY_LABELS[i],
			TextColor3 = Color3.fromRGB(220, 220, 230),
		}, button)
		local shade = new("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,
			ZIndex = 3,
		}, button)
		Ui.corner(shade, 14)
		local count = Ui.label({
			Position = UDim2.new(0, 4, 1, -32),
			Size = UDim2.new(1, -8, 0, 26),
			Text = "",
			ZIndex = 4,
		}, button)
		button.Activated:Connect(function()
			use(i)
		end)
		slots[i] = { Button = button, Name = name, Key = key, Shade = shade, Count = count }
	end

	local function refresh()
		loadout = Ui.list(player:GetAttribute("Loadout"))
		for i, slot in slots do
			local power = byId[loadout[i]]
			slot.Button.Visible = power ~= nil
			if power then
				slot.Name.Text = power.DisplayName
				slot.Name.TextColor3 = power.Color
				slot.Button.BackgroundColor3 = power.Color:Lerp(Color3.fromRGB(20, 18, 28), 0.72);
				(slot.Button:FindFirstChildOfClass("UIStroke") :: UIStroke).Color = power.Color
			end
		end
	end
	player:GetAttributeChangedSignal("Loadout"):Connect(refresh)
	refresh()

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		for i = 1, #KEYS do
			if input.KeyCode == KEYS[i] or input.KeyCode == PAD[i] then
				use(i)
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		-- The Murderer fights with their knife; powers are for innocents
		local murderer = player:GetAttribute("InRound") and player:GetAttribute("Role") == "Murderer"
		bar.Visible = not murderer and #loadout > 0
		local gamepad = UserInputService.GamepadEnabled
		local now = workspace:GetServerTimeNow()
		for i, slot in slots do
			local id = loadout[i]
			if not id then
				continue
			end
			slot.Key.Text = if gamepad then PAD_LABELS[i] else KEY_LABELS[i]
			local energy = player:GetAttribute("Energy")
			if type(energy) == "number" then
				-- In a round: costs Energy (coins fill it); shaded while you can't afford it
				local power = byId[id]
				local level = 1
				for _, entry in Ui.list(player:GetAttribute("Powers")) do
					local pid, lvl = entry:match("^(%w+):(%d+)$")
					if pid == id then
						level = tonumber(lvl) or 1
					end
				end
				local cost = power.Energy[math.clamp(level, 1, #power.Energy)]
				slot.Shade.Size = UDim2.fromScale(1, if energy >= cost then 0 else 1 - energy / cost)
				slot.Count.Text = `⚡{cost}`
			else
				-- In the arena: cooldown, the shade drains as it recharges
				local readyAt = player:GetAttribute(`PowerReady_{id}`)
				local left = if type(readyAt) == "number" then readyAt - now else 0
				local power = byId[id]
				slot.Shade.Size = UDim2.fromScale(1, math.clamp(left / power.Cooldown, 0, 1))
				slot.Count.Text = if left > 0 then tostring(math.ceil(left)) else ""
			end
		end
	end)
end

return PowerBar
