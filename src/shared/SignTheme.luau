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

-- Art-pack boards (sell, collect, upgrade): the 1024x512 PNG holds a ~4:1 board across its middle
-- with transparent bands above and below. Put it on a 4:1 surface and this blows the picture up
-- (aspect kept, never stretched) so the board fills the surface. Returns the empty area to the
-- right of the corner icon, for live native text.
-- `crop` (CartoonArt.BoardCrops) switches to a 9-slice of just the board, so the surface can be
-- taller than 4:1; `pixelWidth` is the surface's width in GUI pixels (sizes the slice corners).
-- Steal a Brainrot knife label floating over a knife: the name big and white, the rarity in its
-- colour, the money per second big and green, all with thick dark outlines. `top` (optional) is an
-- extra small line above the name (a Murderer power). Sized in studs, so far ones draw small.
function SignTheme.knifeLabel(
	parent: Instance,
	adornee: BasePart,
	name: string,
	rarity: string,
	rarityColor: Color3,
	perSecond: string,
	top: string?,
	maxDistance: number?
): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "KnifeLabel"
	gui.Size = UDim2.fromScale(8, if top then 3.5 else 2.9)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	gui.MaxDistance = maxDistance or 60
	gui.LightInfluence = 0
	gui.Adornee = adornee
	local lines = {
		{ Text = name, Color = Color3.new(1, 1, 1), Weight = 1.15, Font = Enum.Font.GothamBlack },
		{ Text = rarity, Color = rarityColor, Weight = 0.7, Font = Enum.Font.GothamBlack },
		{ Text = perSecond, Color = Color3.fromRGB(70, 255, 70), Weight = 1.15, Font = Enum.Font.GothamBlack },
	}
	if top then
		table.insert(
			lines,
			1,
			{ Text = top, Color = Color3.fromRGB(255, 120, 140), Weight = 0.55, Font = Enum.Font.GothamBold }
		)
	end
	local total = 0
	for _, line in lines do
		total += line.Weight
	end
	local y = 0
	for _, line in lines do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0, y / total)
		label.Size = UDim2.fromScale(1, line.Weight / total)
		label.Font = line.Font
		label.TextScaled = true
		label.TextColor3 = line.Color
		label.Text = line.Text
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(16, 14, 22)
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = label
		label.Parent = gui
		y += line.Weight
	end
	gui.Parent = parent
	return gui
end

-- Tsunami cash pill: a soft mint rounded pill with a thin violet edge and the amount in big bright
-- green, filling a SurfaceGui. Returns the amount label.
function SignTheme.cashPill(gui: Instance): TextLabel
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	pill.Size = UDim2.new(1, -8, 1, -8)
	pill.BackgroundColor3 = Color3.fromRGB(160, 235, 170)
	pill.BackgroundTransparency = 0.15
	pill.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.22, 0)
	corner.Parent = pill
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.fromRGB(120, 100, 210)
	edge.Thickness = 4
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = pill
	local amount = Instance.new("TextLabel")
	amount.Name = "Amount"
	amount.AnchorPoint = Vector2.new(0.5, 0.5)
	amount.Position = UDim2.fromScale(0.5, 0.5)
	amount.Size = UDim2.fromScale(0.9, 0.8)
	amount.BackgroundTransparency = 1
	amount.Font = Enum.Font.GothamBlack
	amount.TextScaled = true
	amount.TextColor3 = Color3.fromRGB(70, 230, 40)
	amount.Text = ""
	amount.Parent = pill
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 80, 20)
	stroke.Thickness = 3
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = amount
	return amount
end

-- A plain SurfaceGui on one face of a part
function SignTheme.face(part: BasePart, face: Enum.NormalId, pixelsPerStud: number, maxDistance: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Gui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.Brightness = 0.95
	gui.MaxDistance = maxDistance
	gui.Parent = part
	return gui
end

return SignTheme
