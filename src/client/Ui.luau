--!strict
-- Small UI toolkit shared by the client modules: one ScreenGui, instance helper, and the house
-- style (FredokaOne, rounded corners, thick dark outlines).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Ui = {}

-- Phones (and tablets): touch with no keyboard. They get a compact layout that keeps clear of the
-- thumbstick (bottom left) and jump button (bottom right). In Studio, ReplicatedStorage attribute
-- DebugPhone = true previews it on desktop (with ghosts of where the touch controls would be).
Ui.Phone = (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	or (RunService:IsStudio() and ReplicatedStorage:GetAttribute("DebugPhone") == true)

-- Turn a Ui.chunky button into a square icon-only one (phones: no room for the words)
function Ui.iconOnly(button: GuiObject)
	local label = button:FindFirstChild("Label")
	if label and label:IsA("GuiObject") then
		label.Visible = false
	end
	for _, child in button:GetChildren() do
		if child:IsA("TextLabel") and child.Name ~= "Label" and child.Name ~= "Badge" then
			-- the icon: centre it
			child.AnchorPoint = Vector2.new(0.5, 0.5)
			child.Position = UDim2.fromScale(0.5, 0.5)
		end
	end
end

Ui.FONT = Enum.Font.FredokaOne
Ui.WHITE = Color3.new(1, 1, 1)
Ui.PANEL = Color3.fromRGB(30, 26, 40)
Ui.SPOOKY = Enum.Font.Creepster -- big dramatic text (role reveal, results)
Ui.OUTLINE = Color3.fromRGB(30, 30, 40)

function Ui.new(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

function Ui.corner(parent: Instance, radius: number)
	Ui.new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

function Ui.stroke(parent: Instance, thickness: number?)
	Ui.new("UIStroke", {
		Thickness = thickness or 3,
		Color = Ui.OUTLINE,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

function Ui.padding(parent: Instance, x: number, y: number?)
	Ui.new("UIPadding", {
		PaddingLeft = UDim.new(0, x),
		PaddingRight = UDim.new(0, x),
		PaddingTop = UDim.new(0, y or x),
		PaddingBottom = UDim.new(0, y or x),
	}, parent)
end

function Ui.label(props: { [string]: any }, parent: Instance?): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Ui.FONT,
		TextScaled = true,
		TextColor3 = Ui.WHITE,
	}
	for key, value in props do
		defaults[key] = value
	end
	return Ui.new("TextLabel", defaults, parent)
end

-- Chunky rounded button with an outline; `onClick` fires for mouse, touch and gamepad select
function Ui.button(props: { [string]: any }, parent: Instance?, onClick: (() -> ())?): TextButton
	local defaults: { [string]: any } = {
		AutoButtonColor = true,
		Font = Ui.FONT,
		TextScaled = true,
		TextColor3 = Ui.WHITE,
		BackgroundColor3 = Color3.fromRGB(80, 170, 255),
	}
	for key, value in props do
		defaults[key] = value
	end
	local button: TextButton = Ui.new("TextButton", defaults, parent)
	Ui.corner(button, 12)
	Ui.stroke(button)
	Ui.padding(button, 8, 4)
	Ui.new("UITextSizeConstraint", { MaxTextSize = 26 }, button)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

-- Thick dark outline around text (the chunky Steal-An-Egg look)
function Ui.textStroke(label: TextLabel | TextButton, thickness: number?, color: Color3?)
	Ui.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or Color3.fromRGB(20, 16, 28),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, label)
end

-- Top-to-bottom gradient from a colour to a darker version of it
function Ui.gradient(parent: GuiObject, top: Color3, bottom: Color3?)
	Ui.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(top, bottom or top:Lerp(Color3.new(0, 0, 0), 0.35)),
	}, parent)
end

-- A big menu button: icon + label, gradient body, dark outline, little bounce when pressed.
-- `badge` (optional) is a red bubble in the corner for things to collect.
function Ui.chunky(
	props: { [string]: any },
	parent: Instance?,
	icon: string?,
	onClick: (() -> ())?
): (TextButton, TextLabel?)
	local color = props.BackgroundColor3 or Color3.fromRGB(80, 200, 90)
	local text = props.Text or ""
	props.Text = ""
	props.BackgroundColor3 = Color3.new(1, 1, 1)
	props.AutoButtonColor = false
	local button: TextButton = Ui.new("TextButton", props, parent)
	Ui.corner(button, 12)
	Ui.new("UIStroke", {
		Thickness = 3.5,
		Color = Color3.fromRGB(20, 16, 28),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, button)
	Ui.gradient(button, color:Lerp(Color3.new(1, 1, 1), 0.15), color:Lerp(Color3.new(0, 0, 0), 0.25))
	-- Glossy top strip
	local shine = Ui.new("Frame", {
		Size = UDim2.new(1, -10, 0.38, 0),
		Position = UDim2.fromOffset(5, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.82,
		ZIndex = (button.ZIndex or 1) + 1,
	}, button)
	Ui.corner(shine, 8)
	local iconLabel: TextLabel? = nil
	local hasIcon = icon ~= nil and icon ~= ""
	if hasIcon then
		iconLabel = Ui.label({
			Size = UDim2.new(1, -8, 1, -8),
			Position = UDim2.fromOffset(6, 4),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			Text = icon,
			ZIndex = (button.ZIndex or 1) + 2,
		}, button)
	end
	local label = Ui.label({
		Name = "Label",
		Size = UDim2.new(1, -12, 1, -10),
		Position = UDim2.fromOffset(6, 5),
		Text = text,
		ZIndex = (button.ZIndex or 1) + 2,
	}, button)
	if hasIcon then
		-- leave room for the icon on the left
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0.28, 0) }, label)
	end
	Ui.textStroke(label, 2.5)
	Ui.new("UITextSizeConstraint", { MaxTextSize = 34 }, label)
	local scale = Ui.new("UIScale", {}, button)
	button.MouseEnter:Connect(function()
		scale.Scale = 1.05
	end)
	button.MouseLeave:Connect(function()
		scale.Scale = 1
	end)
	button.Activated:Connect(function()
		scale.Scale = 0.92
		task.delay(0.08, function()
			scale.Scale = 1
		end)
		if onClick then
			onClick()
		end
	end)
	return button, iconLabel
end

-- A red bubble with a number in a button's corner (hidden at 0)
function Ui.badge(parent: GuiObject): TextLabel
	local badge = Ui.label({
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(230, 40, 50),
		Text = "",
		Visible = false,
		ZIndex = (parent.ZIndex or 1) + 5,
	}, parent)
	Ui.corner(badge, 15)
	Ui.new("UIStroke", { Thickness = 2.5, Color = Color3.new(1, 1, 1) }, badge)
	return badge
end

function Ui.abbreviate(n: number): string
	local suffixes = { "", "K", "M", "B", "T" }
	local i = 1
	while n >= 1000 and i < #suffixes do
		n /= 1000
		i += 1
	end
	return if i == 1 then tostring(math.floor(n)) else string.format("%.1f%s", n, suffixes[i])
end

function Ui.clock(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Comma-separated player attributes ("Knives", "Discovered", "Items") as a list
function Ui.list(value: any): { string }
	local out = {}
	if type(value) == "string" and value ~= "" then
		for item in value:gmatch("[^,]+") do
			table.insert(out, item)
		end
	end
	return out
end

local player = Players.LocalPlayer
Ui.gui = Ui.new("ScreenGui", {
	Name = "HUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui")) :: ScreenGui

-- Scale everything down a bit on small (phone) screens
local uiScale = Ui.new("UIScale", {}, Ui.gui)
local function updateScale()
	local camera = workspace.CurrentCamera
	local shortSide = math.min(camera.ViewportSize.X, camera.ViewportSize.Y)
	-- Phones lay out for ~560 units of height so buttons stay thumb-sized (~36pt and up)
	uiScale.Scale = if Ui.Phone then math.clamp(shortSide / 560, 0.55, 1) else math.clamp(shortSide / 800, 0.6, 1.2)
end
-- Roblox games are played sideways: never let a phone turn this into portrait
player:WaitForChild("PlayerGui").ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
updateScale()

return Ui
