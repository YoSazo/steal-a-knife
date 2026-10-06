--!strict
-- Presentation-only caps; never change adornee, range, prompts or Enabled state.
local CollectionService = game:GetService("CollectionService")
local Ui = require(script.Parent.Ui)
local WorldLabels = {}
local originals: { [BillboardGui]: UDim2 } = {}
local function resize(gui: BillboardGui)
	-- Sized in studs: already shrinks with distance, nothing to cap
	if originals[gui].X.Scale > 0 then
		return
	end
	if not Ui.Phone then
		gui.Size = originals[gui]
		return
	end
	local _, bounds = Ui.bounds()
	local shop = gui:GetAttribute("LabelCategory") == "Shop"
	local width = if shop then math.min(220, bounds.X * 0.28) else 160
	-- (a label with two lines - VIP over cash - sets Lines = 2 and gets room for both)
	local height = (if shop then 42 else 32) * ((gui:GetAttribute("Lines") or 1) :: number)
	local original = originals[gui]
	gui.Size = UDim2.fromOffset(math.min(width, original.X.Offset), math.min(height, original.Y.Offset))
end
function WorldLabels.Init()
	local function add(instance: Instance)
		if not instance:IsA("BillboardGui") then
			return
		end
		originals[instance] = instance.Size
		resize(instance)
	end
	for _, gui in CollectionService:GetTagged("ResponsiveWorldLabel") do
		add(gui)
	end
	CollectionService:GetInstanceAddedSignal("ResponsiveWorldLabel"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("ResponsiveWorldLabel"):Connect(function(instance)
		if instance:IsA("BillboardGui") then
			originals[instance] = nil
		end
	end)
	Ui.Layout.Changed:Connect(function()
		for gui in originals do
			resize(gui)
		end
	end)
end
return WorldLabels
