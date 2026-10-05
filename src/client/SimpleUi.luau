--!strict
-- Tsunami-simple menus: a solid header bar in the colour of the button that opened it (voxel icon,
-- white title, red X), a see-through dark body, and big chunky buttons with few words.
local TweenService = game:GetService("TweenService")
local Ui = require(script.Parent.Ui)

local SimpleUi = {}

local INK = Color3.fromRGB(16, 14, 24)

local function outline(parent: Instance, thickness: number?)
	Ui.new("UIStroke", {
		Color = INK,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function shade(parent: Instance, color: Color3)
	Ui.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.22), color:Lerp(Color3.new(0, 0, 0), 0.12)),
	}, parent)
end

function SimpleUi.text(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local options: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		RichText = true,
		ZIndex = ((parent :: any).ZIndex or 5) + 1,
	}
	local maximum = 40
	for key, value in (props or {}) :: { [string]: any } do
		if key == "Max" then
			maximum = value
		else
			options[key] = value
		end
	end
	local label: TextLabel = Ui.new("TextLabel", options, parent)
	Ui.new("UITextSizeConstraint", { MinTextSize = 8, MaxTextSize = maximum }, label)
	Ui.new("UIStroke", {
		Color = INK,
		Thickness = if maximum >= 44 then 3.5 else 2.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, label)
	return label
end

-- A big chunky button in a colour, with a label (and an optional icon on the left)
function SimpleUi.button(
	parent: Instance,
	text: string,
	color: Color3,
	props: { [string]: any },
	action: (() -> ())?,
	icon: string?
): TextButton
	local maximum = props.Max or 34
	props.Max = nil
	local button: TextButton = Ui.new("TextButton", props, parent)
	button.Text, button.AutoButtonColor, button.BackgroundColor3 = "", false, Color3.new(1, 1, 1)
	Ui.corner(button, 12)
	outline(button)
	shade(button, color)
	button:SetAttribute("Color", color)
	if icon then
		local art = Ui.new("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.03, 0.1),
			Size = UDim2.fromScale(1, 0.8),
			Image = icon,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = button.ZIndex + 1,
		}, button)
		Ui.new("UIAspectRatioConstraint", { AspectRatio = 1 }, art)
	end
	local label = SimpleUi.text(button, text, {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(if icon then 0.58 else 0.5, 0.5),
		Size = UDim2.fromScale(if icon then 0.74 else 0.9, 0.7),
		Max = maximum,
	})
	label.Name = "Label"
	local scale = Ui.new("UIScale", {}, button)
	button.Activated:Connect(function()
		-- Greyed out still answers: the click goes through and the server's message says why not
		if button:GetAttribute("Busy") then
			return
		end
		scale.Scale = 0.93
		task.delay(0.08, function()
			scale.Scale = 1
		end)
		if action then
			local run = action :: () -> ()
			button:SetAttribute("Busy", true)
			local ok, message = pcall(function(): any
				run()
				return nil
			end)
			button:SetAttribute("Busy", false)
			if not ok then
				warn("[SimpleUi] " .. tostring(message))
			end
		end
	end)
	return button
end

-- Recolour / relabel / enable a SimpleUi button
function SimpleUi.set(button: TextButton, text: string?, color: Color3?, enabled: boolean?)
	local label = button:FindFirstChild("Label") :: TextLabel?
	if label and text then
		label.Text = text
	end
	local tint = color or button:GetAttribute("Color") :: Color3
	if color then
		button:SetAttribute("Color", color)
	end
	local on = enabled ~= false
	button:SetAttribute("Disabled", not on)
	local gradient = button:FindFirstChildOfClass("UIGradient")
	if gradient then
		local base = if on then tint else Color3.fromRGB(120, 124, 136)
		gradient.Color = ColorSequence.new(base:Lerp(Color3.new(1, 1, 1), 0.22), base:Lerp(Color3.new(0, 0, 0), 0.12))
	end
end

-- The window. `size` is the design size; it scales to fit. Returns (frame, body).
function SimpleUi.window(name: string, title: string, icon: string, color: Color3, size: Vector2): (Frame, Frame)
	local frame: Frame = Ui.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = Color3.fromRGB(14, 16, 26),
		BackgroundTransparency = 0.25, -- see-through, like Tsunami's
		Visible = false,
		ZIndex = 5,
	}, Ui.gui)
	Ui.corner(frame, 14)
	outline(frame, 4)
	local scale = Ui.new("UIScale", { Scale = 1 }, frame)
	local header: Frame = Ui.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 84),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 6,
	}, frame)
	Ui.corner(header, 14)
	outline(header, 4)
	shade(header, color)
	Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.fromOffset(72, 72),
		Image = icon,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 7,
	}, header)
	SimpleUi.text(header, title, {
		Name = "Title",
		Position = UDim2.fromOffset(98, 10),
		Size = UDim2.new(1, -200, 1, -20),
		TextXAlignment = Enum.TextXAlignment.Left,
		Max = 56,
	})
	SimpleUi.button(header, "X", Color3.fromRGB(230, 40, 50), {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(78, 68),
		ZIndex = 8,
		Max = 52,
	}, function()
		frame.Visible = false
	end)
	local body: Frame = Ui.new("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(16, 98),
		Size = UDim2.new(1, -32, 1, -112),
		BackgroundTransparency = 1,
		ZIndex = 6,
	}, frame)
	local function fit()
		local _, bounds = Ui.bounds()
		scale.Scale = math.min(1, (bounds.X - 24) / size.X, (bounds.Y - 24) / size.Y)
	end
	Ui.Layout.Changed:Connect(fit)
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			fit()
			local target = scale.Scale
			scale.Scale = target * 0.95
			TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Quad), { Scale = target }):Play()
		end
	end)
	Ui.registerMenu(frame)
	fit()
	return frame, body
end

return SimpleUi
