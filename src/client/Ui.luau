--!strict
-- Small UI toolkit shared by the client modules: one ScreenGui, instance helper, and the house
-- style (FredokaOne, rounded corners, thick dark outlines).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Layout = require(script.Parent.Layout)
local MenuController = require(script.Parent.MenuController)

local Format = require(ReplicatedStorage.Shared.Format)
local Artwork = require(ReplicatedStorage.Shared.Config.UiArtwork)
local KnifeIcons = require(ReplicatedStorage.Shared.Config.KnifeIcons)
local VoxelKnives = require(ReplicatedStorage.Shared.Config.VoxelUi).Knives :: { [string]: string }

local Ui = {
	gui = nil :: any,
	root = nil :: any,
	feedback = nil :: any, -- the always-on-top layer for messages (see below)
	Navigation = nil :: any,
	Buy = nil :: ((kind: string, key: string) -> ())?, -- set by Store
	OpenGift = nil :: ((target: Player) -> ())?, -- set by GambleUi
	ReplayTutorial = nil :: (() -> ())?, -- set by Tutorial (More > How to play)
	Toast = nil :: ((text: string, kind: string) -> ())?, -- set by Hud: a message on the Feedback layer
}

-- Phones (and tablets): touch with no keyboard. They get a compact layout that keeps clear of the
-- thumbstick (bottom left) and jump button (bottom right). In Studio, ReplicatedStorage attribute
-- DebugPhone = true previews it on desktop (with ghosts of where the touch controls would be).
Ui.Phone = UserInputService.TouchEnabled
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
Ui.PANEL = Color3.fromRGB(24, 35, 57)
Ui.SPOOKY = Enum.Font.FredokaOne -- big dramatic text (role reveal, results)
Ui.OUTLINE = Color3.fromRGB(30, 30, 40)

function Ui.new(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = if parent == Ui.gui and Ui.root then Ui.root else parent
	return instance
end

function Ui.art(parent: Instance, name: string, props: { [string]: any }?): ImageLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		-- Knives: Codex's voxel renders of the current models first
		Image = VoxelKnives[name] or KnifeIcons[name] or Artwork[name] or "",
		ScaleType = Enum.ScaleType.Fit,
	}
	for key, value in (props or {}) :: { [string]: any } do
		defaults[key] = value
	end
	local image: ImageLabel = Ui.new("ImageLabel", defaults, parent)
	if KnifeIcons[name] and not VoxelKnives[name] then
		task.delay(8, function()
			if image.Parent and not image.IsLoaded then
				image.Image = Artwork[name] or KnifeIcons[name]
			end
		end)
	end
	return image
end

function Ui.corner(parent: Instance, radius: number)
	Ui.new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

function Ui.stroke(parent: Instance, thickness: number?)
	Ui.new("UIStroke", {
		Thickness = math.min(thickness or 2, 2),
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
	local label: TextLabel = Ui.new("TextLabel", defaults, parent)
	if label.TextScaled then
		Ui.new("UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = 28 }, label)
	end
	return label
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
		Thickness = math.min(thickness or 2, 2),
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
		Thickness = 2,
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
		local symbol = ({
			["📖"] = "Index",
			["☰"] = "More",
			["⬆️"] = "Upgrades",
			["♻️"] = "Rebirth",
			["💎"] = "CaseLegendary",
			["🔪"] = "RustyShank",
			["💰"] = "Cash",
			["👑"] = "VIP",
			["❤️"] = "Health",
		})[icon :: string]
		iconLabel = Ui.label({
			Size = UDim2.new(1, -8, 1, -8),
			Position = UDim2.fromOffset(6, 4),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			Text = icon,
			ZIndex = (button.ZIndex or 1) + 2,
		}, button)
		if symbol then
			(iconLabel :: TextLabel).Visible = false
			Ui.art(
				button,
				symbol,
				{ Size = UDim2.new(0, 36, 1, -8), Position = UDim2.fromOffset(4, 4), ZIndex = (button.ZIndex or 1) + 2 }
			)
		end
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
	Ui.textStroke(label, 1.5)
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
	return Format.Short(n)
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
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui")) :: ScreenGui

-- The root uses safe-area pixels; individual components reflow instead of shrinking text.
Ui.root =
	Ui.new("Frame", { Name = "SafeRoot", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, Ui.gui) :: Frame
Ui.Scale = Ui.new("UIScale", { Scale = 1 }, Ui.gui)
-- Studio phone emulator (Layout.debugSafe): the safe area becomes the phone's, top-left, with a
-- magenta outline where its screen ends
do
	local outline: Frame? = nil
	local function emulate()
		local sim = Layout.debugSafe()
		if sim then
			Ui.root.Size = UDim2.fromOffset(sim.X, sim.Y)
			if not outline then
				outline = Ui.new("Frame", { Name = "PhoneEdge", BackgroundTransparency = 1, ZIndex = 1000 }, Ui.gui)
				Ui.new("UIStroke", { Color = Color3.fromRGB(255, 0, 255), Thickness = 3 }, outline)
			end
			(outline :: Frame).Size = UDim2.fromOffset(sim.X + 47, sim.Y + 21);
			(outline :: Frame).Visible = true
		else
			Ui.root.Size = UDim2.fromScale(1, 1)
			if outline then
				outline.Visible = false
			end
		end
	end
	ReplicatedStorage:GetAttributeChangedSignal("DebugSafe"):Connect(emulate)
	emulate()
end
-- Feedback (toasts, announcements, offer cards) lives on its own layer ABOVE every menu and screen:
-- a message must never be hidden behind the window you clicked in (Steal An Egg does the same).
-- Same safe area and scale as the HUD, so positions mean the same thing.
Ui.feedback = Ui.new("ScreenGui", {
	Name = "Feedback",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 100,
}, player:WaitForChild("PlayerGui")) :: ScreenGui
local feedbackScale = Ui.new("UIScale", { Scale = 1 }, Ui.feedback) :: UIScale
Ui.Scale:GetPropertyChangedSignal("Scale"):Connect(function()
	feedbackScale.Scale = Ui.Scale.Scale
end)
Ui.Layout = Layout
Ui.Menu = MenuController
-- Panels other modules can open by name (the plaza's rings: ShopPanel "Spin" / "Merchant", and the
-- right-side quick buttons)
Ui.Panels = {} :: { [string]: GuiObject }
Layout.bind(Ui.root)
player:WaitForChild("PlayerGui").ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
function Ui.bounds(): (Vector2, Vector2)
	return Layout.bounds()
end
-- How much to shrink big one-off screen text (banners, reveals) so it fits a phone: 1 on
-- desktop, ~0.55 on a small landscape phone
function Ui.phoneScale(): number
	if not Ui.Phone then
		return 1
	end
	local _, bounds = Layout.bounds()
	return math.clamp(math.min(bounds.Y / 720, bounds.X / 1280), 0.5, 1)
end
-- Gives a whole ScreenGui (or frame) a UIScale that follows Ui.phoneScale
function Ui.fitPhone(target: Instance)
	if not Ui.Phone then
		return
	end
	local scale = target:FindFirstChild("PhoneScale") :: UIScale?
	if not scale then
		scale = Ui.new("UIScale", { Name = "PhoneScale" }, target)
	end
	(scale :: UIScale).Scale = Ui.phoneScale()
end
function Ui.fitMenu(frame: GuiObject, maximum: Vector2?)
	Layout.fit(frame, maximum)
end

-- Behind menus: nothing that catches taps, so the side buttons stay usable with a menu open
-- (tap Shop while Index is open and it simply switches)
local backdrop = Ui.new("Frame", {
	Name = "MenuBackdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 4,
	Active = false,
}, Ui.gui)
MenuController.Init(Ui.gui, backdrop)
function Ui.registerMenu(frame: GuiObject)
	MenuController.Register(frame)
end
function Ui.menuOpen(): boolean
	return MenuController.IsOpen()
end
-- True while you're really in the hub: not in a round, alive, and not still standing on the round
-- maps (they're far away at x = 3000; a player who died in a round watches from there until they
-- respawn, and the hub buttons popping back over that view looked broken)
function Ui.inHub(): boolean
	if player:GetAttribute("InRound") then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or humanoid.Health <= 0 or not root then
		return false
	end
	return root.Position.X < 1500
end
function Ui.hint(keyboard: string, gamepad: string): string
	if UserInputService.PreferredInput == Enum.PreferredInput.Touch or Ui.Phone then
		return ""
	end
	return ` [{if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then gamepad else keyboard}]`
end
return Ui
