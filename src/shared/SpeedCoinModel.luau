--!strict
local Props = require(script.Parent.Props)
local Art = require(script.Parent.Config.CartoonArt)
local Coin = {}
-- A real Blender token; the small shoe marker is measured in studs and shrinks with distance.
function Coin.Build(at: CFrame, roundOnly: boolean): (Model, BasePart)
	local model = Props.Build("SpeedCoin", true)
	model.Name = "Coin"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("RoundOnly", roundOnly)
	model:SetAttribute("SpeedValue", 1)
	model:PivotTo(at)
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.one * 3.4
	hitbox.CFrame = at
	hitbox.Anchored = true
	hitbox.CanCollide, hitbox.CanQuery = false, false
	hitbox.Transparency = 1
	hitbox.Parent = model
	model.PrimaryPart = hitbox
	local gui = Instance.new("BillboardGui")
	gui.Name = "ShoeMarker"
	gui.Size = UDim2.fromScale(0.8, 0.8)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1.9, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.Parent = hitbox
	local art = Instance.new("ImageLabel")
	art.Size = UDim2.fromScale(1, 1)
	art.BackgroundTransparency = 1
	art.Image = Art.Speed
	art.Parent = gui
	return model, hitbox
end

return Coin
