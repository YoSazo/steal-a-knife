--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local View = {}
function View.Init()
	local player = Players.LocalPlayer
	local note = Theme.text(Ui.gui, "🛡️ COFFIN SAFE", {
		Name = "SavedCoffinStatus",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.fromOffset(260, 44),
		MaximumTextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(120, 255, 150),
		Visible = false,
	})
	local message = Theme.text(Ui.feedback, "Your coffin is safe!\nYou'll come back here after the round.", {
		Name = "SavedCoffinMessage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(650, 110),
		MaximumTextSize = 34,
		TextWrapped = true,
		Visible = false,
	})
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "ChaseResume", false, 90
	gui.IgnoreGuiInset = true
	gui.ScreenInsets, gui.SafeAreaCompatibility, gui.ClipToDeviceSafeArea =
		Enum.ScreenInsets.None, Enum.SafeAreaCompatibility.None, false
	gui.Parent = player.PlayerGui
	local dim = Ui.new("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Visible = false,
		Active = true,
	}, gui)
	local countdown = Theme.text(dim, "", {
		Name = "RunResumeCountdown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.8, 0.4),
		MaximumTextSize = 110,
		TextWrapped = false,
		Visible = false,
	})
	local function layout()
		local _, bounds = Ui.bounds()
		message.Size = UDim2.fromOffset(math.min(650, bounds.X - 24), if Ui.Phone then 100 else 110)
	end
	Ui.Layout.Changed:Connect(layout)
	layout()
	local opening, lastDeadline = false, 0
	ReplicatedStorage.Remotes.Effect.OnClientEvent:Connect(function(kind: string)
		if kind == "RunSaved" then
			opening = true
			message.Visible = true
		end
	end)
	RunService.RenderStepped:Connect(function()
		if player:GetAttribute("InRound") or Ui.gui:GetAttribute("FadeCover") then
			opening = false
		end
		message.Visible = opening and player:GetAttribute("RunSaved") == true
		note.Visible = player:GetAttribute("RunSaved") == true
			and player:GetAttribute("InRound") == true
			and not Ui.menuOpen()
		local deadline = (player:GetAttribute("RunResumeAt") or 0) :: number
		local now = workspace:GetServerTimeNow()
		local left = deadline - now
		if left > 0 then
			lastDeadline = deadline
			dim.Visible, countdown.Visible = true, true
			countdown.Text = tostring(math.ceil(left))
			message.Visible = false
		elseif lastDeadline > 0 and now < lastDeadline + 0.5 then
			dim.Visible, countdown.Visible = true, true
			dim.BackgroundTransparency = 1
			countdown.Text = "RUN!"
		else
			dim.Visible, countdown.Visible = false, false
			dim.BackgroundTransparency = 0.45
		end
	end)
end
return View
