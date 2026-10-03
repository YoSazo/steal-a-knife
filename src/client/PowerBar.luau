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
		Name = "Powers",
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(224, 52),
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
		if id and bar.Visible and not Ui.menuOpen() then
			Remotes.UsePower:FireServer(id, aimDirection())
		end
	end

	for i = 1, GameConfig.MaxPowerSlots do
		local button: TextButton = new("TextButton", {
			LayoutOrder = i,
			Size = UDim2.fromOffset(68, 52),
			AutoButtonColor = true,
			Text = "",
			BackgroundColor3 = Ui.PANEL,
			Visible = false,
		}, bar)
		Ui.corner(button, 14)
		new("UIStroke", { Thickness = 2, Color = Color3.new(1, 1, 1) }, button)
		local name = Ui.label({
			Position = UDim2.fromOffset(4, 2),
			Size = UDim2.new(1, -8, 0, 26),
			Text = "",
			TextTruncate = Enum.TextTruncate.AtEnd,
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
			Position = UDim2.new(0, 4, 1, -22),
			Size = UDim2.new(1, -8, 0, 20),
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
		if Ui.Phone then
			local _, bounds = Ui.bounds()
			local knife = Ui.Layout.knifePosition()
			local right = math.min(bounds.X / 2 + 112, knife.X - 88)
			local left = math.max(152, right - 224)
			local width = math.max(140, right - left)
			bar.Position = UDim2.fromOffset((left + right) / 2, math.max(172, bounds.Y - 162) + 52)
			bar.Size = UDim2.fromOffset(width, 52)
			for _, slot in slots do
				slot.Button.Size = UDim2.fromOffset((width - 20) / 3, 52)
			end
		end
		-- The Murderer fights with their knife; powers are for innocents
		local inRound = player:GetAttribute("InRound") == true
		local murderer = inRound and player:GetAttribute("Role") == "Murderer"
		-- In the hub the powers only show where you'd use them: out on the runway with the guards,
		-- or during a Thief Moon. Safe on the plaza / in your vault, they're out of the way.
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local onRunway = root ~= nil
			and root.Position.Z > -2
			and math.abs(root.Position.X) < GameConfig.ArenaWidth / 2 + 2
		local bloodMoon = type(ReplicatedStorage:GetAttribute("RaidEndsAt")) == "number"
		local classic = inRound and ReplicatedStorage:GetAttribute("Classic") == true
		bar.Visible = not Ui.menuOpen()
			and not murderer
			and not classic
			and #loadout > 0
			and (inRound or onRunway or bloodMoon)
		local gamepad = UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
		local now = workspace:GetServerTimeNow()
		for i, slot in slots do
			local id = loadout[i]
			if not id then
				continue
			end
			-- Rounds: only your first power comes along
			slot.Button.Visible = not inRound or i == 1
			slot.Key.Text = if Ui.Phone then "" elseif gamepad then PAD_LABELS[i] else KEY_LABELS[i]
			local energy = player:GetAttribute("Energy")
			if type(energy) == "number" then
				-- In a round: costs Energy (coins fill it); shaded while you can't afford it
				local power = byId[id]
				local level = GameConfig.RoundPowerLevel -- the same for everyone in rounds
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
