--!strict
-- Shift lock, MM2 style: a padlock button in the top bar (next to Roblox's own buttons) that works
-- on phones too. While it's on, the camera sits over your right shoulder and you always face where
-- it looks; with a mouse the pointer is locked to the middle (the crosshair sits there). Shift
-- toggles it on a keyboard (Roblox's own shift lock is switched off in default.project.json).
-- It lets go while a menu is open, while the knife joystick owns the camera (Scriptable), on your
-- wheel and while a boss hit tumbles you.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Ui = require(script.Parent.Ui)
local Icons2 = require(ReplicatedStorage.Shared.Config.VoxelIcons2).Icons :: { [string]: string }

local player = Players.LocalPlayer
local ShiftLock = {}

local OFFSET = Vector3.new(1.75, 0.25, 0) -- over the right shoulder

function ShiftLock.Init()
	local on = false
	local applied = false

	local gui = Instance.new("ScreenGui")
	gui.Name = "ShiftLock"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")
	local button = Instance.new("ImageButton")
	button.Name = "ShiftLockButton"
	button.AutoButtonColor = true
	button.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	button.BackgroundTransparency = 0.3
	button.Image = ""
	button.Parent = gui
	Instance.new("UICorner", button).CornerRadius = UDim.new(1, 0)
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.72, 0.72)
	icon.Image = Icons2.Padlock or ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = button
	local ring = Instance.new("UIStroke")
	ring.Color = Color3.fromRGB(80, 180, 255)
	ring.Thickness = 3
	ring.Enabled = false
	ring.Parent = button

	-- Top right of the screen, the same height as Roblox's topbar buttons
	local function place()
		local inset = GuiService.TopbarInset
		local height = math.max(32, inset.Height - 8)
		button.Size = UDim2.fromOffset(height, height)
		-- Top right, at the far end of the topbar's free space: on the left it sat under Roblox's voice
		-- chat icon and in the way of the top line (tutorial, notices) in the middle
		-- (the Studio phone emulator moves the screen's right edge in: Layout.debugSafe)
		local sim = Ui.Layout.debugSafe()
		local right = if sim then sim.X + 47 else inset.Max.X
		button.Position = UDim2.fromOffset(right - height - 8, inset.Min.Y + (inset.Height - height) / 2)
	end
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(place)
	ReplicatedStorage:GetAttributeChangedSignal("DebugSafe"):Connect(place)
	place()

	local function humanoidOf(): Humanoid?
		local character = player.Character
		return character and character:FindFirstChildOfClass("Humanoid")
	end

	local function release()
		if not applied then
			return
		end
		applied = false
		local humanoid = humanoidOf()
		if humanoid then
			humanoid.CameraOffset = Vector3.zero
			humanoid.AutoRotate = not player:GetAttribute("Training")
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end

	local function set(value: boolean)
		on = value
		ring.Enabled = on
		button.BackgroundColor3 = if on then Color3.fromRGB(30, 90, 160) else Color3.fromRGB(18, 18, 22)
		if not on then
			release()
		end
	end
	button.Activated:Connect(function()
		set(not on)
	end)
	ContextActionService:BindAction("ShiftLockToggle", function(_, state)
		if state == Enum.UserInputState.Begin then
			set(not on)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)
	player.CharacterAdded:Connect(function()
		applied = false
	end)

	-- After the camera has moved: face where it looks
	RunService:BindToRenderStep("ShiftLock", Enum.RenderPriority.Camera.Value + 2, function()
		local camera = workspace.CurrentCamera
		local humanoid = humanoidOf()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local active = on
			and humanoid ~= nil
			and root ~= nil
			and humanoid.Health > 0
			-- (or the knife stick's aim camera: letting go of shift lock there centred you)
			and (camera.CameraType == Enum.CameraType.Custom or camera:GetAttribute("KnifeAim") == true)
			and not Ui.menuOpen()
			and not player:GetAttribute("Training")
			and not player:GetAttribute("Spectating")
			and not player:GetAttribute("Tumbling")
		if not active then
			release()
			return
		end
		local hum, part = humanoid :: Humanoid, root :: BasePart
		applied = true
		hum.AutoRotate = false
		hum.CameraOffset = OFFSET
		if UserInputService.MouseEnabled then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.05 then
			part.CFrame = CFrame.lookAt(part.Position, part.Position + flat)
		end
	end)
end

return ShiftLock
