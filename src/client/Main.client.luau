--!strict
-- HUD: cash, round timer, upgrade buttons, notifications and the role reveal.
-- Pure display + requests; the server owns every number shown here.
-- Works with mouse, touch, and gamepad (D-pad shortcuts for the three upgrades).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local KIND_COLORS = {
	good = Color3.fromRGB(90, 220, 120),
	bad = Color3.fromRGB(255, 90, 90),
	info = Color3.fromRGB(90, 170, 255),
}

local function abbreviate(n: number): string
	local suffixes = { "", "K", "M", "B", "T" }
	local i = 1
	while n >= 1000 and i < #suffixes do
		n /= 1000
		i += 1
	end
	return if i == 1 then tostring(math.floor(n)) else string.format("%.1f%s", n, suffixes[i])
end

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

local function round(parent: Instance, radius: number)
	new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function stroke(parent: Instance)
	new(
		"UIStroke",
		{ Thickness = 3, Color = Color3.fromRGB(30, 30, 40), ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
		parent
	)
end

local gui = new(
	"ScreenGui",
	{ Name = "HUD", ResetOnSpawn = false, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling },
	player:WaitForChild("PlayerGui")
)
-- Scale everything down a bit on small (phone) screens
local uiScale = new("UIScale", {}, gui)
local function updateScale()
	local camera = workspace.CurrentCamera
	local shortSide = math.min(camera.ViewportSize.X, camera.ViewportSize.Y)
	uiScale.Scale = math.clamp(shortSide / 800, 0.6, 1.2)
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
updateScale()

-- Top center: phase + timer
local timerFrame = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(340, 64),
	BackgroundColor3 = Color3.fromRGB(40, 40, 60),
	BackgroundTransparency = 0.15,
}, gui)
round(timerFrame, 16)
stroke(timerFrame)
local timerLabel = new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = FONT,
	TextScaled = true,
	TextColor3 = WHITE,
	Text = "Loading...",
}, timerFrame)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
	PaddingTop = UDim.new(0, 8),
	PaddingBottom = UDim.new(0, 8),
}, timerFrame)

-- Top left: cash / income / rack
local statsFrame = new("Frame", {
	Position = UDim2.fromOffset(12, 60),
	Size = UDim2.fromOffset(230, 110),
	BackgroundColor3 = Color3.fromRGB(40, 40, 60),
	BackgroundTransparency = 0.15,
}, gui)
round(statsFrame, 16)
stroke(statsFrame)
new("UIListLayout", { Padding = UDim.new(0, 2) }, statsFrame)
new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingTop = UDim.new(0, 6) }, statsFrame)
local function statLine(color: Color3, height: number): TextLabel
	return new("TextLabel", {
		Size = UDim2.new(1, -12, 0, height),
		BackgroundTransparency = 1,
		Font = FONT,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color,
		Text = "",
	}, statsFrame)
end
local cashLabel = statLine(Color3.fromRGB(120, 255, 140), 44)
local incomeLabel = statLine(WHITE, 26)
local rackLabel = statLine(Color3.fromRGB(200, 200, 220), 26)

-- Right side: upgrade buttons
local shop = new("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(210, 250),
	BackgroundTransparency = 1,
}, gui)
new("UIListLayout", { Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Center }, shop)

local buttons: { [string]: TextButton } = {}
local function shopButton(kind: string, color: Color3, keyHint: string): TextButton
	local button = new("TextButton", {
		Name = kind,
		Size = UDim2.new(1, 0, 0, 72),
		BackgroundColor3 = color,
		AutoButtonColor = true,
		Font = FONT,
		TextScaled = true,
		TextColor3 = WHITE,
		Text = kind,
	}, shop)
	round(button, 14)
	stroke(button)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
	}, button)
	new("UITextSizeConstraint", { MaxTextSize = 26 }, button)
	button:SetAttribute("KeyHint", keyHint)
	button.Activated:Connect(function()
		Remotes.Purchase:InvokeServer(kind)
	end)
	buttons[kind] = button
	return button
end
shopButton("Speed", Color3.fromRGB(80, 170, 255), "D-pad Up")
shopButton("Slot", Color3.fromRGB(255, 170, 60), "D-pad Right")
shopButton("Ticket", Color3.fromRGB(230, 70, 90), "D-pad Left")

-- Gamepad shortcuts
local function bindPurchase(kind: string, key: Enum.KeyCode)
	ContextActionService:BindAction(`Buy{kind}`, function(_, state)
		if state == Enum.UserInputState.Begin then
			Remotes.Purchase:InvokeServer(kind)
		end
		return Enum.ContextActionResult.Pass
	end, false, key)
end
bindPurchase("Speed", Enum.KeyCode.DPadUp)
bindPurchase("Slot", Enum.KeyCode.DPadRight)
bindPurchase("Ticket", Enum.KeyCode.DPadLeft)

local function refreshStats()
	local cash = player:GetAttribute("Cash") or 0
	local slots = player:GetAttribute("Slots") or GameConfig.StartingSlots
	local speed = player:GetAttribute("SpeedLevel") or 0
	local tickets = player:GetAttribute("Tickets") or 0
	cashLabel.Text = `${abbreviate(cash)}`
	incomeLabel.Text = `+${abbreviate(player:GetAttribute("Income") or 0)}/s`
	rackLabel.Text = `Rack {player:GetAttribute("KnifeCount") or 0}/{slots}   Luck {player:GetAttribute("Luck") or 0}`

	local gamepad = UserInputService.GamepadEnabled
	local function hint(button: TextButton): string
		return if gamepad then `\n[{button:GetAttribute("KeyHint")}]` else ""
	end
	buttons.Speed.Text = if speed >= GameConfig.MaxSpeedLevel
		then "Speed MAX"
		else `Speed Lv{speed + 1}  ${abbreviate(GameConfig.SpeedCost(speed))}{hint(buttons.Speed)}`
	buttons.Slot.Text = if slots >= GameConfig.MaxSlots
		then "Rack MAX"
		else `+1 Slot  ${abbreviate(GameConfig.SlotCost(slots))}{hint(buttons.Slot)}`
	buttons.Ticket.Text = `Murderer Ticket ({tickets})  ${abbreviate(GameConfig.TicketCost)}{hint(buttons.Ticket)}`
end
for _, attribute in { "Cash", "Slots", "SpeedLevel", "Tickets", "Income", "KnifeCount", "Luck" } do
	player:GetAttributeChangedSignal(attribute):Connect(refreshStats)
end
UserInputService.GamepadConnected:Connect(refreshStats)
UserInputService.GamepadDisconnected:Connect(refreshStats)
refreshStats()

-- Round timer
RunService.RenderStepped:Connect(function()
	local phase = ReplicatedStorage:GetAttribute("Phase")
	local endsAt = ReplicatedStorage:GetAttribute("PhaseEndsAt") or 0
	local status = ReplicatedStorage:GetAttribute("Status") or ""
	local left = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
	local clock = string.format("%d:%02d", left // 60, left % 60)
	if phase == "Round" then
		timerLabel.Text = `{status} {clock}  ·  {ReplicatedStorage:GetAttribute("Alive") or 0} alive`
		timerFrame.BackgroundColor3 = Color3.fromRGB(150, 30, 50)
	elseif phase == "Results" or status:find("Waiting") then
		timerLabel.Text = status
		timerFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
	else
		timerLabel.Text = `{status} {clock}`
		timerFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
	end
	shop.Visible = not player:GetAttribute("InRound")
end)

-- Notifications (stack at the bottom middle)
local toasts = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -110),
	Size = UDim2.fromOffset(460, 200),
	BackgroundTransparency = 1,
}, gui)
new("UIListLayout", {
	Padding = UDim.new(0, 6),
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, toasts)

Remotes.Notify.OnClientEvent:Connect(function(text: string, kind: string)
	local toast = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = KIND_COLORS[kind] or KIND_COLORS.info,
		Font = FONT,
		TextScaled = true,
		TextColor3 = WHITE,
		Text = text,
		TextStrokeTransparency = 0.5,
	}, toasts)
	round(toast, 12)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 5),
		PaddingBottom = UDim.new(0, 5),
	}, toast)
	task.delay(3.5, function()
		local fade = TweenService:Create(
			toast,
			TweenInfo.new(0.4),
			{ BackgroundTransparency = 1, TextTransparency = 1, TextStrokeTransparency = 1 }
		)
		fade:Play()
		fade.Completed:Wait()
		toast:Destroy()
	end)
	local children = toasts:GetChildren()
	if #children > 5 then
		for _, child in children do
			if child:IsA("TextLabel") then
				child:Destroy()
				break
			end
		end
	end
end)

-- Role reveal
local roleLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.35),
	Size = UDim2.fromOffset(600, 110),
	BackgroundTransparency = 1,
	Font = FONT,
	TextScaled = true,
	TextStrokeTransparency = 0,
	Visible = false,
}, gui)
Remotes.Role.OnClientEvent:Connect(function(role: string)
	if role == "Murderer" then
		roleLabel.Text = "You are the MURDERER!"
		roleLabel.TextColor3 = Color3.fromRGB(255, 60, 70)
	else
		roleLabel.Text = "You are INNOCENT. Survive!"
		roleLabel.TextColor3 = Color3.fromRGB(90, 230, 120)
	end
	roleLabel.TextTransparency = 0
	roleLabel.Visible = true
	task.delay(3, function()
		TweenService:Create(roleLabel, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
	end)
end)
