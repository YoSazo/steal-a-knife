--!strict
-- Phone layout, Steal An Egg style: a slim column of small buttons on the left, small square icon
-- buttons down the right, and the middle and top of the screen left clear for the game. Runs after
-- every other HUD module has built its pieces and re-applies on every safe-area change.
local Ui = require(script.Parent.Ui)

local PhoneHud = {}

-- Steal An Egg sizes: about half of what we had (easy to tap, but the world stays the star)
local NAV_W, NAV_H, NAV_GAP = 112, 40, 6
local SQUARE, SQUARE_GAP = 46, 6
-- Phones: a small outlined word under each square ("how do I upgrade?" - icons alone weren't enough)
local CAPTION = 14
local CAPTIONS: { [string]: string } = {
	UpgradesButton = "Upgrades",
	SpinButton = "Spin",
	MerchantButton = "Merchant",
}

local function caption(button: GuiObject, text: string)
	if button:FindFirstChild("Caption") then
		return
	end
	local label = Instance.new("TextLabel")
	label.Name = "Caption"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 1, 1)
	label.Size = UDim2.new(1.6, 0, 0, CAPTION)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.ZIndex = button.ZIndex + 3
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(20, 18, 30)
	stroke.Parent = label
	label.Parent = button
end

-- A Theme.button turned into a square icon button (the label hides, the picture fills it)
local function squareIcon(button: GuiObject)
	if button:GetAttribute("HudSkinned") then
		return -- HudSkin lays its own tile out as a square
	end
	local label = button:FindFirstChild("Label")
	if label and label:IsA("GuiObject") then
		label.Visible = false
	end
	for _, child in button:GetChildren() do
		if child:IsA("ImageLabel") and child.Name ~= "Studs" and child.Name ~= "Badge" then
			child.AnchorPoint = Vector2.new(0.5, 0.5)
			child.Position = UDim2.fromScale(0.5, 0.5)
			child.Size = UDim2.fromScale(0.8, 0.8)
		end
	end
end

function PhoneHud.Init()
	local phone = Ui.Phone
	local gui = Ui.root or Ui.gui
	local right: { GuiObject } = {}
	-- the free chest pill first (only shown when it's ready), then the buttons
	local timers = gui:FindFirstChild("Timers", true)
	for _, name in { "UpgradesButton", "SpinButton", "MerchantButton" } do
		local button = gui:FindFirstChild(name, true)
		if button and button:IsA("GuiObject") then
			if phone then
				squareIcon(button)
				caption(button, CAPTIONS[name])
			end
			table.insert(right, button)
		end
	end
	local chest = timers and timers:FindFirstChild("ChestPill")
	if chest and chest:IsA("GuiObject") and not chest:GetAttribute("HudSkinned") then
		for _, child in chest:GetChildren() do
			local keep = child.Name == "Badge" or child.Name == "Studs"
			if child:IsA("TextLabel") and not keep then
				child.Visible = false
			end
			if child:IsA("ImageLabel") and not keep then
				child.AnchorPoint = Vector2.new(0.5, 0.5)
				child.Position = UDim2.fromScale(0.5, 0.5)
				child.Size = UDim2.fromScale(0.85, 0.85)
			end
		end
	end
	local function layout()
		local origin, bounds = Ui.bounds()
		-- The HUD lives inside the safe area; reach past it to sit right against the screen edges
		local viewport = workspace.CurrentCamera.ViewportSize
		local leftEdge = -origin.X + 8
		local rightEdge = (viewport.X - (origin.X + bounds.X)) - 8
		-- Left: one slim column against the left edge, a third of the way down
		local nav = Ui.Navigation :: GuiObject?
		if nav and phone then
			-- (Slow mode is the little switch under the column: Menus SlowToggle)
			local shown = 0
			for _, child in nav:GetChildren() do
				if child:IsA("GuiObject") and child.Visible then
					shown += 1
				end
			end
			local grid = nav:FindFirstChildOfClass("UIGridLayout")
			if grid then
				grid.CellSize = UDim2.fromOffset(NAV_W, NAV_H)
				grid.CellPadding = UDim2.fromOffset(NAV_GAP, NAV_GAP)
				grid.FillDirectionMaxCells = 1
			end
			nav.AnchorPoint = Vector2.zero
			nav.Position = UDim2.fromOffset(leftEdge, math.floor(bounds.Y * 0.22))
			nav.Size = UDim2.fromOffset(NAV_W, shown * (NAV_H + NAV_GAP))
		end
		-- Right: a column centred on the right edge (phones: squares, kept above the jump button;
		-- desktop: the labelled buttons, same height each)
		local count = #right + (if timers then 1 else 0)
		local bottomLimit = if phone then Ui.Layout.touchBounds().Y - 12 else bounds.Y - 12
		local gap = if phone then SQUARE_GAP + CAPTION else SQUARE_GAP
		local square = if phone then math.clamp(math.floor((bottomLimit - 10) / count - gap), 32, SQUARE) else 52
		local width = if phone then square else 150
		local total = count * square + (count - 1) * gap
		local y = math.floor((bounds.Y - total) / 2)
		y = math.max(10, math.min(y, bottomLimit - total))
		local edge = if phone then rightEdge else -12
		local function place(item: GuiObject)
			item.AnchorPoint = Vector2.new(1, 0)
			item.Position = UDim2.new(1, edge, 0, y)
			item.Size = UDim2.fromOffset(width, square)
			y += square + gap
		end
		if timers and timers:IsA("GuiObject") then
			place(timers)
			if chest and chest:IsA("GuiObject") then
				chest.Size = UDim2.fromOffset(width, square)
			end
		end
		for _, button in right do
			place(button)
		end
	end
	Ui.Layout.Changed:Connect(function()
		task.defer(layout) -- after the modules' own layout handlers
	end)
	task.defer(layout)
end

return PhoneHud
