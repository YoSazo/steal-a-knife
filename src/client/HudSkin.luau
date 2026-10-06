--!strict
-- Gives every HUD button one universal look: a bright solid rounded button in its own colour (the
-- HUD floats over a sunny world, so it stays light; menus keep the navy voxel theme) with Codex's
-- voxel icon (VoxelUi.Hud). Runs after the HUD modules built their buttons: it only changes how they look
-- (backgrounds, icons, label placement); clicks, badges and layouts stay theirs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ui = require(script.Parent.Ui)
local VoxelUi = require(ReplicatedStorage.Shared.Config.VoxelUi)

local HudSkin = {}

local function restyle(button: GuiObject, icon: string, color: Color3)
	if button:GetAttribute("HudSkinned") then
		return
	end
	button:SetAttribute("HudSkinned", true)
	button.BackgroundTransparency = 1
	for _, child in button:GetChildren() do
		local name = child.Name
		if name == "Badge" or name == "Label" or name == "Tap" then
			continue
		end
		if child:IsA("UIGradient") or child:IsA("UICorner") then
			child:Destroy()
		elseif child:IsA("UIStroke") then
			child.Enabled = false
		elseif child:IsA("GuiObject") then
			child.Visible = false -- old studs, shine, skins and emoji/flat icons
		end
	end
	-- Bright and simple over the world (Steal An Egg / our cash pills): a solid rounded button in
	-- its own colour, light-to-dark gradient, thick dark outline and a soft shine
	local tile: Frame = Ui.new("Frame", {
		Name = "Tile",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = button.ZIndex,
	}, button)
	Ui.new("UICorner", { CornerRadius = UDim.new(0.22, 0) }, tile)
	Ui.new("UIStroke", {
		Color = Color3.fromRGB(20, 16, 28),
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, tile)
	Ui.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.2), color:Lerp(Color3.new(0, 0, 0), 0.12)),
	}, tile)
	local shine: Frame = Ui.new("Frame", {
		Position = UDim2.fromOffset(5, 4),
		Size = UDim2.new(1, -10, 0.36, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.8,
		ZIndex = button.ZIndex,
	}, tile)
	Ui.new("UICorner", { CornerRadius = UDim.new(0.4, 0) }, shine)
	local art = Ui.new("ImageLabel", {
		Name = "VoxelIcon",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromScale(1, 0.92),
		Image = icon,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = button.ZIndex + 2,
	}, button)
	Ui.new("UIAspectRatioConstraint", { AspectRatio = 1 }, art)
	local label = button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Visible = true
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Position = UDim2.new(0, button.AbsoluteSize.Y + 2, 0.5, 0)
		label.Size = UDim2.new(1, -(button.AbsoluteSize.Y + 8), 0.7, 0)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.ZIndex = button.ZIndex + 2
		for _, d in label:GetChildren() do
			if d:IsA("UIPadding") then
				d:Destroy()
			end
		end
	end
	-- Square (icon-only) buttons: centre the icon
	button:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local size = button.AbsoluteSize
		local square = size.X < size.Y * 1.5
		art.AnchorPoint = if square then Vector2.new(0.5, 0.5) else Vector2.new(0, 0.5)
		art.Position = if square then UDim2.fromScale(0.5, 0.5) else UDim2.new(0, 4, 0.5, 0)
		art.Size = UDim2.fromScale(1, if square then 0.78 else 0.92)
		if label and label:IsA("TextLabel") then
			label.Visible = not square
			label.Position = UDim2.new(0, size.Y + 2, 0.5, 0)
			label.Size = UDim2.new(1, -(size.Y + 8), 0.7, 0)
		end
	end)
end

function HudSkin.Init()
	local root = Ui.root or Ui.gui
	local hud = VoxelUi.Hud
	local nav = Ui.Navigation :: Instance?
	if nav then
		for _, button in nav:GetChildren() do
			if button:IsA("TextButton") then
				local label = button:FindFirstChild("Label", true)
				local text = if label and label:IsA("TextLabel") then label.Text else ""
				local icon, color = nil :: string?, Color3.new()
				if button.Name == "StoreButton" then
					icon, color = hud.Shop, Color3.fromRGB(70, 210, 60)
				elseif text:find("Index") then
					icon, color = hud.Index, Color3.fromRGB(40, 170, 255)
				elseif text:find("More") then
					icon, color = hud.More, Color3.fromRGB(150, 90, 240)
				elseif button.Name == "Slow" then
					icon, color = hud.Speed, Color3.fromRGB(140, 145, 160)
				end
				if icon then
					restyle(button, icon, color)
				end
			end
		end
	end
	local right: { [string]: { Icon: string, Color: Color3 } } = {
		KnivesButton = { Icon = hud.Knives, Color = Color3.fromRGB(255, 190, 40) },
		PowersButton = { Icon = hud.Powers, Color = Color3.fromRGB(255, 148, 28) },
	}
	for name, look in right do
		local button = root:FindFirstChild(name, true)
		if button and button:IsA("GuiObject") then
			restyle(button, look.Icon, look.Color)
		end
	end
	local chest = root:FindFirstChild("ChestPill", true)
	if chest and chest:IsA("GuiObject") then
		restyle(chest, hud.FreeChest, Color3.fromRGB(255, 190, 40))
	end
end

return HudSkin
