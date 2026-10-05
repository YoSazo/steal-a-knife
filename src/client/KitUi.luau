--!strict
-- Builds menus out of the CleanKit pieces (cut from the original UI mockups), so every screen
-- matches the reference: navy block-cornered windows, a blue title plate with a big outlined
-- title, green / blue chunky buttons, the red X, framed cards, progress bars and currency pills.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Ui = require(script.Parent.Ui)
local Kit = require(ReplicatedStorage.Shared.Config.CleanKit)

local KitUi = {}

KitUi.Navy = Color3.fromRGB(14, 27, 52)
KitUi.Ink = Color3.fromRGB(8, 14, 30)

-- A 9-sliced kit picture filling `parent` (or with the given props)
function KitUi.skin(parent: Instance, piece: Kit.Piece, props: { [string]: any }?): ImageLabel
	local options: { [string]: any } = {
		Name = "Skin",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Image = piece.Image,
		ScaleType = if piece.Slice then Enum.ScaleType.Slice else Enum.ScaleType.Fit,
		SliceCenter = piece.Slice or Rect.new(0, 0, 0, 0),
		ZIndex = (parent :: any).ZIndex or 1,
	}
	for key, value in (props or {}) :: { [string]: any } do
		options[key] = value
	end
	return Ui.new("ImageLabel", options, parent)
end

-- Chunky outlined text (the mockups' white title / button lettering)
function KitUi.text(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local options: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		ZIndex = ((parent :: any).ZIndex or 1) + 1,
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
		Color = KitUi.Ink,
		Thickness = if maximum >= 50 then 4 else 2.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, label)
	return label
end

-- A button: "Primary" (green), "Secondary" (blue). Disabled ones dim; Busy guards double taps.
function KitUi.button(
	parent: Instance,
	kind: string,
	text: string,
	props: { [string]: any },
	action: (() -> ())?
): TextButton
	local maximum = props.Max or 30
	props.Max = nil
	local button: TextButton = Ui.new("TextButton", props, parent)
	button.Text, button.BackgroundTransparency, button.AutoButtonColor = "", 1, false
	KitUi.skin(button, if kind == "Primary" then Kit.PrimaryButton else Kit.SecondaryButton)
	local label = KitUi.text(button, text, {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromScale(0.84, 0.62),
		Max = maximum,
	})
	label.Name = "Label"
	local scale = Ui.new("UIScale", {}, button)
	button.Activated:Connect(function()
		if button:GetAttribute("Disabled") or button:GetAttribute("Busy") then
			return
		end
		scale.Scale = 0.93
		task.delay(0.08, function()
			scale.Scale = 1
		end)
		if action then
			button:SetAttribute("Busy", true)
			local run = action :: () -> ()
			local ok, message = pcall(function(): any
				run()
				return nil
			end)
			button:SetAttribute("Busy", false)
			if not ok then
				warn("[KitUi] " .. tostring(message))
			end
		end
	end)
	return button
end

function KitUi.setEnabled(button: TextButton, enabled: boolean, text: string?)
	button:SetAttribute("Disabled", not enabled)
	local skin = button:FindFirstChild("Skin") :: ImageLabel?
	if skin then
		skin.ImageColor3 = if enabled then Color3.new(1, 1, 1) else Color3.fromRGB(120, 125, 140)
	end
	local label = button:FindFirstChild("Label") :: TextLabel?
	if label and text then
		label.Text = text
	end
end

-- A framed card (navy with cyan block corners)
function KitUi.card(parent: Instance, props: { [string]: any }?): Frame
	local options: { [string]: any } = { BackgroundTransparency = 1, ZIndex = 7 }
	for key, value in (props or {}) :: { [string]: any } do
		options[key] = value
	end
	local frame: Frame = Ui.new("Frame", options, parent)
	KitUi.skin(frame, Kit.Card, { SliceScale = 0.6 })
	return frame
end

-- A progress bar; returns a setter (0..1, optional caption)
function KitUi.bar(parent: Instance, props: { [string]: any }): (number, string?) -> ()
	local track: Frame = Ui.new("Frame", props, parent)
	track.BackgroundTransparency = 1
	KitUi.skin(track, Kit.ProgressTrack)
	local fill = KitUi.skin(track, Kit.ProgressFill, {
		Name = "Fill",
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(0, 0, 1, -6),
		ZIndex = track.ZIndex + 1,
	})
	local caption =
		KitUi.text(track, "", { Size = UDim2.fromScale(1, 0.8), Position = UDim2.fromScale(0, 0.1), Max = 18 })
	caption.ZIndex = track.ZIndex + 2
	return function(fraction: number, text: string?)
		fill.Size = UDim2.new(math.clamp(fraction, 0, 1), -6 * math.clamp(fraction, 0, 1), 1, -6)
		fill.Visible = fraction > 0
		caption.Text = text or ""
	end
end

-- A currency pill: icon + live amount; returns the amount label
function KitUi.pill(parent: Instance, icon: string, props: { [string]: any }): TextLabel
	local pill: Frame = Ui.new("Frame", props, parent)
	pill.BackgroundTransparency = 1
	KitUi.skin(pill, Kit.CurrencyPill)
	Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.04, 0.1),
		Size = UDim2.fromScale(0.26, 0.8),
		Image = icon,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = pill.ZIndex + 1,
	}, pill)
	return KitUi.text(
		pill,
		"",
		{ Position = UDim2.fromScale(0.32, 0.18), Size = UDim2.fromScale(0.62, 0.64), Max = 34 }
	)
end

-- A window: navy block frame, the blue title plate with icon + title, the red X. `size` is the
-- design size; it scales down to fit the safe area. Returns (frame, body).
function KitUi.window(name: string, title: string, icon: string, size: Vector2): (Frame, Frame, Frame)
	local frame: Frame = Ui.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
	}, Ui.gui)
	KitUi.skin(frame, Kit.Card, { ImageColor3 = Color3.fromRGB(205, 215, 235), ZIndex = 5 })
	local scale = Ui.new("UIScale", { Scale = 1 }, frame)
	local header: Frame = Ui.new("Frame", {
		Name = "Header",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(0.55, 0, 0, 86),
		BackgroundTransparency = 1,
		ZIndex = 6,
	}, frame)
	KitUi.skin(header, Kit.TitlePlate, { ZIndex = 6 })
	Ui.new("ImageLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 8),
		Size = UDim2.fromOffset(70, 70),
		Image = icon,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 7,
	}, header)
	KitUi.text(header, title:upper(), {
		Name = "Title",
		Position = UDim2.fromOffset(96, 8),
		Size = UDim2.new(1, -110, 1, -16),
		TextXAlignment = Enum.TextXAlignment.Left,
		Max = 64,
	})
	local close: TextButton = Ui.new("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(80, 75),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 8,
	}, frame)
	KitUi.skin(close, Kit.CloseButton, { ZIndex = 8 })
	close.Activated:Connect(function()
		frame.Visible = false
	end)
	local body: Frame = Ui.new("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(18, 108),
		Size = UDim2.new(1, -36, 1, -126),
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
	return frame, body, header
end

return KitUi
