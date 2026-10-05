--!strict
-- The same block geometry is used by the Blender previews and the playable wheels.
-- Only Rotor is tagged/spun; the pedestal, machinery and emblems stay stationary.
local Geometry = require(script.Parent.Config.WheelGeometry)

local WheelModel = {}
export type Built = { Rotor: Model, Stand: Model }

local function populate(model: Model, rows: { Geometry.Row }, palette: { Color3 }, pivot: CFrame)
	for _, row in rows do
		local part = Instance.new("Part")
		part.Name = row[1]
		part.Size = Vector3.new(row[2], row[3], row[4])
		part.CFrame = pivot * CFrame.new(row[5], row[6], row[7]) * CFrame.Angles(row[8], row[9], row[10])
		part.Color = palette[row[11]]
		part.Material = if row[12] then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.Anchored = true
		part.Massless = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CastShadow = false
		part.Parent = model
	end
end

function WheelModel.Build(level: number, pivot: CFrame): Built
	level = math.clamp(math.floor(level), 1, #Geometry)
	local tier = Geometry[level]
	local rotor = Instance.new("Model")
	rotor.Name = "HauntedWheel"
	rotor.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local hub = Instance.new("Part")
	hub.Name = "Hub"
	hub.Size = Vector3.one * 0.1
	hub.CFrame = pivot
	hub.Transparency = 1
	hub.Anchored = true
	hub.CanCollide = false
	hub.CanTouch = false
	hub.CanQuery = false
	hub.Parent = rotor
	rotor.PrimaryPart = hub
	rotor:SetAttribute("Pivot", pivot)
	rotor:SetAttribute("Tier", level)
	rotor:SetAttribute("DesignName", tier.Name)
	populate(rotor, tier.Rotor, tier.Palette, pivot)
	local stand = Instance.new("Model")
	stand.Name = "WheelDetails"
	stand.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	stand:SetAttribute("Tier", level)
	populate(stand, tier.Stand, tier.Palette, pivot)
	return { Rotor = rotor, Stand = stand }
end

return WheelModel
