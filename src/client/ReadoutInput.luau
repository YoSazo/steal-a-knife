--!strict
-- Readouts share the thumbstick's screen area. They observe taps without consuming movement.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Ui = require(script.Parent.Ui)
local Input = {}

function Input.Bind(stats: Frame, speed: TextButton, cash: TextButton)
	local controls: any = nil
	task.spawn(function()
		local module = Players.LocalPlayer.PlayerScripts:WaitForChild("PlayerModule", 4) :: ModuleScript?
		if module then
			controls = (require :: any)(module):GetControls()
		end
	end)
	local function moving(): boolean
		if controls then
			return controls:GetMoveVector().Magnitude > 0.01
		end
		local humanoid = Players.LocalPlayer.Character
			and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		return humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.01
	end
	local function available(): boolean
		return stats.Visible and not Ui.menuOpen() and Ui.gui:GetAttribute("Presenting") ~= true
	end
	local function inside(button: GuiObject, point: Vector2): boolean
		local at, size = button.AbsolutePosition, button.AbsoluteSize
		return button.Visible
			and point.X >= at.X
			and point.Y >= at.Y
			and point.X <= at.X + size.X
			and point.Y <= at.Y + size.Y
	end
	local function position(input: InputObject): Vector2
		return Vector2.new(input.Position.X, input.Position.Y)
	end
	local function open(button: TextButton)
		if available() and Ui.OpenShop then
			Ui.OpenShop(if button == speed then "Speed" else "Money")
		end
	end
	for _, button in { speed, cash } do
		button.Active = not Ui.Phone
		button.Activated:Connect(function(input: InputObject)
			if not Ui.Phone and input.UserInputType ~= Enum.UserInputType.Touch then
				open(button)
			end
		end)
	end
	type Touch = { Button: TextButton, Start: Vector2, At: number, Dragged: boolean }
	local touches: { [InputObject]: Touch } = {}
	local mouse: InputObject? = nil
	UserInputService.InputBegan:Connect(function(input: InputObject)
		local touch = input.UserInputType == Enum.UserInputType.Touch
		local previewMouse = Ui.Phone and input.UserInputType == Enum.UserInputType.MouseButton1
		if not (touch or previewMouse) or not available() or moving() then
			return
		end
		local point = position(input)
		for _, button in { speed, cash } do
			if inside(button, point) then
				touches[input] = { Button = button, Start = point, At = os.clock(), Dragged = false }
				if previewMouse then
					mouse = input
				end
				break
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local key = if input.UserInputType == Enum.UserInputType.MouseMovement then mouse else input
		local entry = key and touches[key]
		if entry and ((position(input) - entry.Start).Magnitude > 8 or moving()) then
			entry.Dragged = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local entry = touches[input]
		touches[input] = nil
		if mouse == input then
			mouse = nil
		end
		if not entry or entry.Dragged or moving() or os.clock() - entry.At > 0.45 then
			return
		end
		local point = position(input)
		if (point - entry.Start).Magnitude <= 8 and inside(entry.Button, point) then
			open(entry.Button)
		end
	end)
end

return Input
