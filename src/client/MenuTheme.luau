--!strict
-- The illustrated concept's shared surfaces, typography and sprite assets.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Ui = require(script.Parent.Ui)
local Art = require(ReplicatedStorage.Shared.Config.MenuArtwork)
local Textures = require(ReplicatedStorage.Shared.Config.Textures)
local CartoonArt = require(ReplicatedStorage.Shared.Config.CartoonArt)
local Kit = require(ReplicatedStorage.Shared.Config.CleanKit)
local KnifeIcons = require(ReplicatedStorage.Shared.Config.KnifeIcons)
local Theme = {}
Theme.Navy = Color3.fromRGB(12, 29, 48)
Theme.Green = Color3.fromRGB(45, 244, 15)
Theme.Cyan = Color3.fromRGB(0, 203, 255)
Theme.Purple = Color3.fromRGB(190, 31, 250)
Theme.Gold = Color3.fromRGB(255, 207, 28)
Theme.Red = Color3.fromRGB(255, 46, 57)
Theme.Black = Color3.fromRGB(4, 7, 12)
local icons = {
	CaseLegendary = 1,
	CaseEpic = 2,
	CaseGodly = 3,
	Cash = 4,
	Index = 5,
	Rebirth = 6,
	Speed = 7,
	Training = 8,
	Luck = 9,
}

function Theme.outline(parent: Instance, color: Color3?, thickness: number?)
	return Ui.new(
		"UIStroke",
		{ Color = color or Theme.Black, Thickness = thickness or 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
		parent
	)
end

function Theme.text(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local options: { [string]: any } = {
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.FredokaOne,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		ZIndex = 8,
	}
	local maximum = 32
	for key, value in (props or {}) :: { [string]: any } do
		if key == "MaximumTextSize" then
			maximum = value
		else
			options[key] = value
		end
	end
	local label: TextLabel = Ui.new("TextLabel", options, parent)
	if label.TextScaled then
		Ui.new("UITextSizeConstraint", { MinTextSize = 10, MaxTextSize = maximum }, label)
	end
	Ui.new("UIStroke", {
		Color = Theme.Black,
		Thickness = if maximum >= 48 then 4 else 2.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, label)
	return label
end

function Theme.studs(parent: GuiObject)
	-- (no checker texture: plain, Tsunami-simple surfaces)
	if true then
		return
	end
	Ui.new("ImageLabel", {
		Name = "Studs",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = Textures.Toy.Stud,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(44, 44),
		ImageTransparency = 0.28,
		ZIndex = parent.ZIndex,
		Active = false,
	}, parent)
end

function Theme.surface(parent: Instance, props: { [string]: any }, color: Color3, edge: Color3?): Frame
	props.BackgroundColor3 = color
	props.ZIndex = props.ZIndex or 6
	local frame: Frame = Ui.new("Frame", props, parent)
	Ui.corner(frame, 9)
	Theme.outline(frame, edge, 3)
	Ui.gradient(frame, color:Lerp(Color3.new(1, 1, 1), 0.12), color:Lerp(Color3.new(0, 0, 0), 0.12))
	Theme.studs(frame)
	local studs = frame:FindFirstChild("Studs") :: ImageLabel?
	if studs then
		studs.ImageTransparency = 0.8
	end
	return frame
end

-- Small utility symbols stay native so they remain sharp at every HUD scale.
local symbols =
	{ More = true, Upgrades = true, Players = true, Stats = true, Health = true, Walls = true, Floor = true }
local function symbol(parent: Instance, name: string, props: { [string]: any }?): ImageLabel
	local options: { [string]: any } = {
		Name = name .. "Art",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 8,
	}
	for key, value in (props or {}) :: { [string]: any } do
		options[key] = value
	end
	local root: ImageLabel = Ui.new("ImageLabel", options, parent)
	local square = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		BackgroundTransparency = 1,
		ZIndex = root.ZIndex,
	}, root)
	Ui.new("UIAspectRatioConstraint", { AspectRatio = 1 }, square)
	local color = if name == "Health"
		then Theme.Red
		elseif name == "Floor" then Theme.Gold
		elseif name == "Upgrades" then Theme.Green
		else Theme.Cyan
	local function shape(x: number, y: number, w: number, h: number, round: boolean?): Frame
		local part: Frame = Ui.new("Frame", {
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(w, h),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = root.ZIndex,
		}, square)
		Ui.corner(part, if round then 100 else 2)
		Theme.outline(part, Theme.Black, 2)
		return part
	end
	if name == "More" then
		for i = 0, 2 do
			shape(0.08, 0.12 + i * 0.3, 0.84, 0.18)
		end
	elseif name == "Upgrades" then
		shape(0.37, 0.37, 0.26, 0.52)
		local tip = shape(0.25, 0.16, 0.5, 0.5)
		tip.Rotation = 45
		shape(0.37, 0.32, 0.26, 0.24)
	elseif name == "Players" then
		shape(0.05, 0.46, 0.5, 0.4, true)
		shape(0.45, 0.46, 0.5, 0.4, true)
		shape(0.13, 0.12, 0.33, 0.33, true)
		shape(0.53, 0.12, 0.33, 0.33, true)
	elseif name == "Stats" then
		shape(0.06, 0.55, 0.22, 0.35)
		shape(0.39, 0.32, 0.22, 0.58)
		shape(0.72, 0.08, 0.22, 0.82)
	elseif name == "Walls" then
		for row = 0, 2 do
			for col = 0, 1 do
				shape(0.08 + col * 0.44, 0.12 + row * 0.27, 0.4, 0.23)
			end
		end
	else
		shape(0.35, 0.08, 0.3, 0.84)
		shape(0.08, 0.35, 0.84, 0.3)
	end
	return root
end

local VoxelHud = require(ReplicatedStorage.Shared.Config.VoxelUi).Hud :: { [string]: string }
local VoxelCases = require(ReplicatedStorage.Shared.Config.VoxelUi).Cases :: { [string]: string }
local VoxelLuckyBlocks = require(ReplicatedStorage.Shared.Config.VoxelUi).LuckyBlocks :: { [string]: string }
local Icons2 = require(ReplicatedStorage.Shared.Config.VoxelIcons2).Icons :: { [string]: string }
local VOXEL_ALIAS: { [string]: string } = {
	Upgrades = "Upgrades",
	Index = "Index",
	Rebirth = "Rebirth",
	Stats = "Stats",
	Players = "Players",
	Powers = "Powers",
	More = "More",
	Speed = "Speed",
	Training = "Speed",
	Trophy = "Stats",
	Spin = "Spin",
	Merchant = "Merchant",
	Knives = "Knives",
	Cash = "Cash",
	FreeChest = "FreeChest",
	Heat = "Heat",
}
function Theme.image(parent: Instance, name: string, props: { [string]: any }?): ImageLabel
	-- Codex's voxel art (headers AND buttons/tiles now - the Powers menu is the bar every icon
	-- should clear, so anything with a real icon here uses it instead of the old sprite sheet).
	local caseRarity = name:match("^Case(%a+)$")
	local luckyRarity = name:match("^Lucky(%a+)$")
	local voxel = (VOXEL_ALIAS[name] and VoxelHud[VOXEL_ALIAS[name]])
		or Icons2[name]
		or (caseRarity and VoxelCases[caseRarity])
		or (luckyRarity and VoxelLuckyBlocks[luckyRarity])
	if voxel then
		local options: { [string]: any } = {
			Name = name .. "Art",
			Image = voxel,
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 8,
		}
		for key, value in (props or {}) :: { [string]: any } do
			options[key] = value
		end
		return Ui.new("ImageLabel", options, parent)
	end
	-- Art-pack pictures (single PNGs, no atlas)
	local packed = ({ Trophy = CartoonArt.Trophy, LootBag = CartoonArt.LootBag } :: { [string]: string })[name]
	if packed then
		local options: { [string]: any } = {
			Name = name .. "Art",
			Image = packed,
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 8,
		}
		for key, value in (props or {}) :: { [string]: any } do
			options[key] = value
		end
		return Ui.new("ImageLabel", options, parent)
	end
	if symbols[name] then
		return symbol(parent, name, props)
	end
	-- Knives use their own single picture: the shared knife sheet's art runs to the edge of every
	-- cell, so cropping one out clipped the blade tips
	if KnifeIcons[name] then
		local options: { [string]: any } = { Name = name .. "Art", ZIndex = 8 }
		for key, value in (props or {}) :: { [string]: any } do
			options[key] = value
		end
		return Ui.art(parent, name, options)
	end
	local icon = icons[name]
	local knife = table.find(Art.KnifeNames, name)
	local asset = if icon then Art.Icons else Art.Knives
	local index = icon or knife
	if not index or asset == "" then
		return Ui.art(parent, name, props)
	end
	local columns = if icon then 3 else 6
	local rows = if icon then 3 else 4
	local size = if icon then Art.IconSize else Art.KnifeSize
	local cell = Vector2.new(size.X / columns, size.Y / rows)
	-- The Art.Knives sheet is disabled (Art.Knives == ""), so that branch never actually renders;
	-- only the small Art.Icons sheet (Cash/Speed/Rebirth/Luck/...) reaches here now, and most of
	-- its icons already moved to Codex's clean individual PNGs above via VOXEL_ALIAS/Icons2. The
	-- few still on the old sheet (Luck, the case-tier icons) bled a sliver of the next cell in at
	-- the boundary; a small inset trims that without visibly cropping these simple icons.
	local inset = if icon then Vector2.new(6, 6) else Vector2.zero
	local options: { [string]: any } = {
		Name = name .. "Art",
		Image = asset,
		ImageRectOffset = Vector2.new(((index - 1) % columns) * cell.X, math.floor((index - 1) / columns) * cell.Y)
			+ inset,
		ImageRectSize = cell - inset * 2,
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 8,
	}
	for key, value in (props or {}) :: { [string]: any } do
		options[key] = value
	end
	return Ui.new("ImageLabel", options, parent)
end

function Theme.button(
	parent: Instance,
	text: string,
	color: Color3,
	props: { [string]: any },
	action: (() -> ())?,
	icon: string?
): TextButton
	local maximum = props.MaximumTextSize or 36
	props.MaximumTextSize = nil
	props.Text, props.BackgroundColor3, props.AutoButtonColor = "", color, false
	props.ZIndex = props.ZIndex or 8
	local button: TextButton = Ui.new("TextButton", props, parent)
	-- The reference mockup's own buttons (CleanKit) for green / blue / red-X; other colours keep
	-- the drawn style
	local piece: any = nil -- (one plain style for every button)
	local shine: Frame
	if piece then
		button.BackgroundTransparency = 1
		Ui.new("ImageLabel", {
			Name = "Skin",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = piece.Image,
			ScaleType = if piece.Slice then Enum.ScaleType.Slice else Enum.ScaleType.Stretch,
			SliceCenter = piece.Slice or Rect.new(0, 0, 0, 0),
			ZIndex = button.ZIndex,
		}, button)
		shine = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(0, 0) }, button)
		-- (callers recolour a button's UIStroke for selection: keep one, drawn as a thin highlight)
		Ui.new(
			"UIStroke",
			{ Color = Theme.Black, Thickness = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
			button
		)
	else
		Ui.corner(button, 9)
		Theme.outline(button)
		Ui.gradient(button, color:Lerp(Color3.new(1, 1, 1), 0.18), color:Lerp(Color3.new(0, 0, 0), 0.14))
		Theme.studs(button)
		shine = Ui.new("Frame", {
			Position = UDim2.fromOffset(5, 4),
			Size = UDim2.new(1, -10, 0.38, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.85,
			ZIndex = button.ZIndex,
		}, button)
		Ui.corner(shine, 5)
	end
	local label = Theme.text(button, text, {
		Name = "Label",
		Position = UDim2.new(if icon then 0.24 else 0, 6, 0, 4),
		Size = UDim2.new(if icon then 0.76 else 1, -12, 1, -8),
		MaximumTextSize = maximum,
		ZIndex = button.ZIndex + 1,
	})
	if icon then
		Theme.image(
			button,
			icon,
			{ Position = UDim2.fromOffset(3, 2), Size = UDim2.new(0.25, 0, 1, -4), ZIndex = button.ZIndex + 1 }
		)
	end
	button.MouseEnter:Connect(function()
		if button:GetAttribute("Disabled") ~= true then
			shine.BackgroundTransparency = 0.72
		end
	end)
	button.MouseLeave:Connect(function()
		shine.BackgroundTransparency = 0.85
	end)
	button.Activated:Connect(function()
		-- A greyed-out button still answers: the click goes through and the server says why not
		-- ("Not enough cash", "No spins left"...). Only a click already in flight is ignored.
		if button:GetAttribute("Busy") == true then
			return
		end
		if action then
			button:SetAttribute("Busy", true)
			local ok, message = pcall(function(): any
				action()
				return nil
			end)
			button:SetAttribute("Busy", false)
			if not ok then
				warn("[Menu] " .. tostring(message))
			end
		end
	end)
	label.Name = "Label"
	if piece == Kit.CloseButton then
		label.Visible = false -- the X is part of the picture
	end
	return button
end

function Theme.enabled(button: TextButton, enabled: boolean, label: string?)
	button:SetAttribute("Disabled", not enabled)
	button.Selectable = enabled
	local veil = button:FindFirstChild("DisabledVeil") :: Frame?
	if not veil then
		local created: Frame = Ui.new("Frame", {
			Name = "DisabledVeil",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.Navy,
			BackgroundTransparency = 0.48,
			ZIndex = button.ZIndex + 3,
			Visible = false,
		}, button)
		Ui.corner(created, 9)
		veil = created
	end
	(veil :: Frame).Visible = not enabled
	if label then
		(button:FindFirstChild("Label") :: TextLabel).Text = label
	end
end

function Theme.badge(parent: GuiObject): TextLabel
	local badge = Theme.text(parent, "", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		-- inside the button's right edge, so buttons hugging the screen edge don't cut it off
		Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Red,
		MaximumTextSize = 14,
		Visible = false,
		ZIndex = parent.ZIndex + 5,
	})
	Ui.corner(badge, 100)
	Theme.outline(badge, Color3.new(1, 1, 1), 2)
	Ui.floatBadge(badge, parent) -- (on top of every button, not under the next one)
	return badge
end

function Theme.burst(parent: GuiObject, color: Color3)
	local glow: Frame = Ui.new("Frame", {
		Name = "Burst",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = parent.ZIndex + 1,
	}, parent)
	for angle = 0, 330, 30 do
		local ray = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.09, 0.8),
			Rotation = angle,
			BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.65),
			BorderSizePixel = 0,
			ZIndex = glow.ZIndex,
		}, glow)
		Ui.new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.65, 0.65),
				NumberSequenceKeypoint.new(1, 0.2),
			}),
		}, ray)
	end
	return glow
end

function Theme.arrow(parent: Instance, props: { [string]: any })
	props.BackgroundTransparency, props.ZIndex = 1, 8
	local arrow = Ui.new("Frame", props, parent)
	local stem = Ui.new("Frame", {
		Position = UDim2.new(0, 4, 0.5, -12),
		Size = UDim2.new(0.6, 0, 0, 24),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 8,
	}, arrow)
	Ui.corner(stem, 2)
	Theme.outline(stem)
	local clip = Ui.new("Frame", {
		Position = UDim2.fromScale(0.45, 0),
		Size = UDim2.fromScale(0.55, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 9,
	}, arrow)
	local tip = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(40, 40),
		Rotation = 45,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 9,
	}, clip)
	Theme.outline(tip)
	Ui.new("Frame", {
		Position = UDim2.new(0.42, 0, 0.5, -9),
		Size = UDim2.new(0.15, 0, 0, 18),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 10,
	}, arrow)
	return arrow
end

function Theme.shell(
	name: string,
	title: string,
	color: Color3,
	icon: string,
	height: number,
	width: number?
): (Frame, Frame, Frame)
	local designWidth = width or 1000
	local frame: Frame = Ui.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(designWidth, height),
		BackgroundColor3 = Color3.fromRGB(14, 16, 26),
		BackgroundTransparency = 0.25, -- see-through, Tsunami-simple
		Visible = false,
		ZIndex = 5,
	}, Ui.gui)
	Ui.corner(frame, 14)
	Theme.outline(frame, Theme.Black, 4)
	local scale = Ui.new("UIScale", { Scale = 1 }, frame)
	local header = Theme.surface(frame, { Name = "Header", Size = UDim2.new(1, 0, 0, 88), ZIndex = 6 }, color)
	local headerCorner = header:FindFirstChildOfClass("UICorner") :: UICorner
	headerCorner.CornerRadius = UDim.new(0, 14)
	local headerStuds = header:FindFirstChild("Studs") :: ImageLabel?
	if headerStuds then
		headerStuds.ImageTransparency = 0.8 -- just a hint of texture
	end
	Theme.image(header, icon, { Position = UDim2.fromOffset(8, 2), Size = UDim2.fromOffset(104, 84) })
	Theme.text(header, title, {
		Name = "Title",
		Position = UDim2.fromOffset(112, 2),
		Size = UDim2.new(1, -212, 0, 80),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaximumTextSize = 72,
	})
	Theme.button(
		header,
		"X",
		Theme.Red,
		{ Name = "Close", Position = UDim2.new(1, -78, 0, 10), Size = UDim2.fromOffset(66, 66), MaximumTextSize = 58 },
		function()
			frame.Visible = false
		end
	)
	local body: Frame = Ui.new("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(12, 100),
		Size = UDim2.new(1, -24, 1, -112),
		BackgroundTransparency = 1,
		ZIndex = 6,
	}, frame)
	local function fit()
		local _, bounds = Ui.bounds()
		scale.Scale =
			math.min(1.15, math.max(0.1, (bounds.X - 24) / designWidth), math.max(0.1, (bounds.Y - 24) / height))
	end
	local connection = Ui.Layout.Changed:Connect(fit)
	frame.Destroying:Connect(function()
		connection:Disconnect()
	end)
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			fit()
			local target = scale.Scale
			scale.Scale = target * 0.96
			TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Quad), { Scale = target }):Play()
		end
	end)
	Ui.registerMenu(frame)
	fit()
	return frame, body, header
end

return Theme
