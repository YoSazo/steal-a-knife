--!strict
-- Safe-area geometry, independent of whether a keyboard/controller is attached.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Layout = {}
Layout.KnifeSize = require(script.Parent.KnifeAim).ButtonSize
local changed = Instance.new("BindableEvent")
Layout.Changed = changed.Event
local root: GuiObject? = nil

function Layout.metrics(size: Vector2)
	return {
		Compact = size.X < 900 or size.Y < 500,
		Short = size.Y < 420,
		Menu = Vector2.new(math.min(960, math.max(0, size.X - 24)), math.min(650, math.max(0, size.Y - 24))),
		NavigationWidth = if size.Y < 420 then 232 else 112,
	}
end
function Layout.bind(frame: GuiObject)
	root = frame
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		changed:Fire()
	end)
	frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		changed:Fire()
	end)
end
-- Studio phone emulator: ReplicatedStorage DebugSafe = Vector2(w, h) shrinks the HUD's safe area to
-- that phone's (iPhone 13 landscape ~750 x 340, SE ~667 x 335) in the top-left corner, next to
-- Roblox's own buttons like on the phone, and Layout.viewport() pretends the screen ends just
-- past it (a notch's width), so things placed against the screen edge land there too.
-- (Use with DebugPhone = true for the touch layout.)
function Layout.debugSafe(): Vector2?
	local sim = ReplicatedStorage:GetAttribute("DebugSafe")
	return if RunService:IsStudio() and typeof(sim) == "Vector2" then sim else nil
end
function Layout.viewport(): Vector2
	local sim = Layout.debugSafe()
	if sim and root then
		return root.AbsolutePosition + sim + Vector2.new(47, 21)
	end
	return workspace.CurrentCamera.ViewportSize
end

function Layout.bounds(): (Vector2, Vector2)
	if root then
		return root.AbsolutePosition, root.AbsoluteSize
	end
	return Vector2.zero, workspace.CurrentCamera.ViewportSize
end
function Layout.get()
	local _, size = Layout.bounds()
	return Layout.metrics(size)
end
function Layout.touchBounds(): (Vector2, Vector2)
	local origin, size = Layout.bounds()
	local jump = Players.LocalPlayer.PlayerGui:FindFirstChild("JumpButton", true)
	if jump and jump:IsA("GuiObject") and jump.Visible and jump.AbsoluteSize.X > 0 then
		return jump.AbsolutePosition - origin, jump.AbsoluteSize
	end
	local diameter = if size.Y < 500 then 70 else 120
	return Vector2.new(size.X - diameter * 1.5 + 10, size.Y - diameter - 20), Vector2.one * diameter
end
function Layout.knifePosition(): Vector2
	local _, size = Layout.bounds()
	local jump = Layout.touchBounds()
	return Vector2.new(
		math.clamp(jump.X - Layout.KnifeSize - 12, 12, math.max(12, size.X - Layout.KnifeSize - 12)),
		math.clamp(jump.Y - 12, 64, math.max(64, size.Y - Layout.KnifeSize - 12))
	)
end
function Layout.fit(frame: GuiObject, maximum: Vector2?)
	local function resize()
		local size = Layout.get().Menu
		local maxSize = maximum or Vector2.new(960, 650)
		maxSize = Vector2.new(
			(frame:GetAttribute("MaximumWidth") or maxSize.X) :: number,
			(frame:GetAttribute("MaximumHeight") or maxSize.Y) :: number
		)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.fromOffset(
			math.min(size.X, maxSize.X),
			math.min(size.Y, maxSize.Y, (frame:GetAttribute("PreferredHeight") or maxSize.Y) :: number)
		)
	end
	local connection = Layout.Changed:Connect(resize)
	frame:GetAttributeChangedSignal("PreferredHeight"):Connect(resize)
	frame:GetAttributeChangedSignal("MaximumWidth"):Connect(resize)
	frame:GetAttributeChangedSignal("MaximumHeight"):Connect(resize)
	frame.Destroying:Connect(function()
		connection:Disconnect()
	end)
	resize()
end
-- Studio-only virtual safe area, for repeatable layout checks without changing world scale.
function Layout.preview(size: Vector2?)
	assert(RunService:IsStudio(), "Preview is Studio-only")
	if root then
		root.Size = if size then UDim2.fromOffset(size.X, size.Y) else UDim2.fromScale(1, 1)
		changed:Fire()
	end
end
return Layout
