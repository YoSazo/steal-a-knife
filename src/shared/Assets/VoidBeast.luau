--!strict
-- Art only. No autonomous animation, Humanoid, physics, lights, or gameplay hooks.
local Data = require(script.Parent.Parent.Config.ToyGeometry.VoidBeast)
local Assets = {}

function Assets.SetPose(model: Model, pose: string, blend: number?)
	assert(pose == "Awake" or pose == "Asleep" or pose == "Waking", "Unknown creature pose")
	local awake = if pose == "Awake" then 1 elseif pose == "Asleep" then 0 else math.clamp(blend or 0.5, 0, 1)
	local scale = model:GetScale()
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "Root" then
			local group = p:GetAttribute("JointGroup") :: string
			local joint = (Data.Joints :: any)[group]
			local localFrame = joint.Asleep:Lerp(joint.Awake, awake)
			local offset = p:GetAttribute("RestOffset") :: Vector3
			local size = p:GetAttribute("RestSize") :: Vector3
			local legY = if string.sub(group, 1, 3) == "Leg" then 0.25 + 0.75 * awake else 1
			local squash = Vector3.new(1, legY, 1)
			p.Size = size * squash * scale
			local rotation = CFrame.Angles(0, 0, math.rad(p:GetAttribute("RestAngle") :: number))
			p.CFrame = model:GetPivot()
				* CFrame.new(localFrame.Position * scale)
				* localFrame.Rotation
				* CFrame.new(offset * squash * scale)
				* rotation
			local state = p:GetAttribute("PoseVisibility")
			p.Transparency = if state == "Awake" and awake < 0.5 or state == "Asleep" and awake >= 0.5 then 1 else 0
			if p:GetAttribute("Role") == "EyeLeft" or p:GetAttribute("Role") == "EyeRight" then
				p:SetAttribute("Closed", awake < 0.5)
			end
		end
	end
	model:SetAttribute("Pose", pose)
	model:SetAttribute("AwakeBlend", awake)
end

-- Reference only: call with phase in radians. Diagonal leg pairs swing in opposition.
function Assets.SetRunPhase(model: Model, phase: number)
	Assets.SetPose(model, "Awake")
	local scale = model:GetScale()
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local group = p:GetAttribute("JointGroup")
			if typeof(group) == "string" and string.sub(group, 1, 3) == "Leg" then
				local joint = (Data.Joints :: any)[group].Awake :: CFrame
				local sign = if group == "LegFrontLeft" or group == "LegBackRight" then 1 else -1
				local hinge = model:GetPivot() * CFrame.new(joint.Position * scale)
				p.CFrame = hinge
					* CFrame.Angles(math.sin(phase) * math.rad(22) * sign, 0, 0)
					* hinge:Inverse()
					* p.CFrame
			end
		end
	end
end

function Assets.Build(parent: Instance?, frame: CFrame?, pose: string?): Model
	local model = Instance.new("Model")
	model.Name = "VoidBeast"
	local root = Instance.new("Part")
	root.Name, root.Size, root.Transparency = "Root", Vector3.one * 0.01, 1
	root.Anchored, root.CanCollide, root.CanQuery, root.CanTouch = true, false, false, false
	root:SetAttribute("Role", "Root")
	root.Parent = model
	model.PrimaryPart = root
	for _, spec in Data.Blocks do
		local p = Instance.new("Part")
		p.Name, p.Size, p.Color = spec.Name, spec.Size, spec.Color
		p.Material = if spec.Neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = true, false, false, false, true
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p:SetAttribute("Role", spec.Role)
		p:SetAttribute("JointGroup", spec.Group)
		p:SetAttribute("RestOffset", spec.Offset)
		p:SetAttribute("RestSize", spec.Size)
		p:SetAttribute("RestAngle", spec.Angle)
		p:SetAttribute("PoseVisibility", spec.State)
		p.Parent = model
	end
	model:SetAttribute("FrontAxis", "-Z")
	model:SetAttribute("StandHeight", Data.StandHeight)
	model:SetAttribute("WalkPivot", Data.WalkPivot)
	model:SetAttribute("ArtOnly", true)
	model:SetAttribute("Zone", 8)
	model:SetAttribute("Origin", "floor centre under torso")
	model:PivotTo(frame or CFrame.identity)
	Assets.SetPose(model, pose or "Asleep")
	model.Parent = parent
	return model
end

return Assets
