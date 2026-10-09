--!strict
-- More -> Codes: one big box, one big REDEEM button, one line saying what happened (PLAN item 26;
-- the server checks the code: server/Services/CodesService).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)

local View = {}

function View.Build(): Frame
	local frame, body = Theme.shell("Codes", "Codes", Theme.Gold, "Shop", 420, 760)
	local box: TextBox = Ui.new("TextBox", {
		Name = "Code",
		Position = UDim2.fromScale(0.04, 0.06),
		Size = UDim2.fromScale(0.92, 0.34),
		BackgroundColor3 = Color3.new(1, 1, 1),
		PlaceholderText = "Type a code",
		PlaceholderColor3 = Color3.fromRGB(150, 150, 160),
		Text = "",
		ClearTextOnFocus = false,
		Font = Enum.Font.FredokaOne,
		TextColor3 = Color3.fromRGB(20, 20, 30),
		TextScaled = true,
		ZIndex = 8,
	}, body)
	Ui.corner(box, 12)
	Theme.outline(box, Theme.Black, 3)
	Ui.new("UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = 52 }, box)
	local result = Theme.text(body, "", {
		Name = "Result",
		Position = UDim2.fromScale(0.04, 0.78),
		Size = UDim2.fromScale(0.92, 0.2),
		MaximumTextSize = 34,
	})
	local busy = false
	Theme.button(body, "REDEEM", Theme.Green, {
		Name = "Redeem",
		Position = UDim2.fromScale(0.2, 0.46),
		Size = UDim2.fromScale(0.6, 0.28),
		MaximumTextSize = 52,
	}, function()
		if busy or box.Text == "" then
			return
		end
		busy = true
		local ok, okOrErr, message =
			pcall(ReplicatedStorage.Remotes.RedeemCode.InvokeServer, ReplicatedStorage.Remotes.RedeemCode, box.Text)
		busy = false
		local worked = ok and okOrErr == true
		result.Text = if ok and type(message) == "string" then message else "Try again!"
		result.TextColor3 = if worked then Color3.fromRGB(120, 255, 140) else Color3.fromRGB(255, 120, 120)
		if worked then
			box.Text = ""
		end
	end)
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			result.Text = ""
		end
	end)
	return frame
end

return View
