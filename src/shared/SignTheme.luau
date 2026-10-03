--!strict
-- World-space counterparts of the illustrated menus. Presentation only.
local Art = require(script.Parent.Config.MenuArtwork)
local Textures = require(script.Parent.Config.Textures)
local SignTheme = {}
SignTheme.Green = Color3.fromRGB(45, 244, 15)
SignTheme.Gold = Color3.fromRGB(255, 207, 28)
local black = Color3.fromRGB(4, 7, 12)

function SignTheme.surface(panel: Frame, color: Color3)
	panel.BackgroundColor3 = color
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 9)
	corner.Parent = panel
	local edge = Instance.new("UIStroke")
	edge.Color, edge.Thickness, edge.ApplyStrokeMode = black, 3, Enum.ApplyStrokeMode.Border
	edge.Parent = panel
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.18), color:Lerp(Color3.new(0, 0, 0), 0.14))
	gradient.Parent = panel
	local studs = Instance.new("ImageLabel")
	studs.Name = "Studs"
	studs.BackgroundTransparency = 1
	studs.Size = UDim2.fromScale(1, 1)
	studs.Image = Textures.Toy.Stud
	studs.ScaleType, studs.TileSize = Enum.ScaleType.Tile, UDim2.fromOffset(44, 44)
	studs.ImageTransparency = 0.28
	studs.Parent = panel
end

-- Big chunky numbers (cash, prices): the heavy Steal An Egg face
SignTheme.NumberFont = Enum.Font.LuckiestGuy

function SignTheme.text(label: TextLabel, maximum: number, font: Enum.Font?)
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	-- (TextWrapped = false would switch TextScaled back off: Roblox ties the two together)
	label.TextScaled = true
	label.ZIndex = 2
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize, constraint.MaxTextSize = 10, maximum
	constraint.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.Thickness = black, if maximum >= 60 then 5 else 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
end

function SignTheme.cashIcon(parent: Instance, position: UDim2, size: UDim2)
	local icon = Instance.new("ImageLabel")
	icon.Name = "CashArt"
	icon.BackgroundTransparency = 1
	icon.Position, icon.Size = position, size
	icon.Image = Art.Icons
	local cell = Art.IconSize / 3
	icon.ImageRectOffset, icon.ImageRectSize = Vector2.new(0, cell.Y), cell
	icon.ScaleType, icon.ZIndex = Enum.ScaleType.Fit, 2
	icon.Parent = parent
	return icon
end

return SignTheme
