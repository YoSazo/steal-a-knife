--!strict
-- Thrown knives that hit a wall, door or floor stay stuck in it for a while (hub throws, boss
-- throws). Round knives live in the round's own folder instead and stay until the round ends.
-- Capped so a busy server never piles up hundreds of them.

local Debris = game:GetService("Debris")

local StuckKnives = {}

local MAX = 60
local folder: Folder? = nil
local stuck: { Model } = {}

-- Leaves `model` embedded where it hit: point first, a little way into the surface
function StuckKnives.Stick(model: Model, at: Vector3, direction: Vector3, seconds: number, parent: Instance?)
	model:PivotTo(CFrame.lookAt(at, at + direction) * CFrame.Angles(-math.pi / 2, 0, 0))
	-- Slide it back so only the very tip is in the wall: find how far the model reaches along the
	-- throw, and put that point just past the surface
	local reach = -math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local half = d.Size / 2
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						local corner = d.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
						reach = math.max(reach, (corner - at):Dot(direction))
					end
				end
			end
		end
	end
	if reach > -math.huge then
		model:PivotTo(model:GetPivot() - direction * (reach - 0.3))
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("Trail") or d:IsA("ParticleEmitter") or d:IsA("Fire") then
			(d :: any).Enabled = false
		end
	end
	if parent then
		model.Parent = parent
		return
	end
	if not folder or not folder.Parent then
		local created = Instance.new("Folder")
		created.Name = "StuckKnives"
		created.Parent = workspace
		folder = created
	end
	model.Parent = folder
	table.insert(stuck, model)
	while #stuck > MAX do
		local oldest = table.remove(stuck, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	Debris:AddItem(model, seconds)
end

return StuckKnives
