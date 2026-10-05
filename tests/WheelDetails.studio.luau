--!strict
-- Runs as a command-bar audit in Edit mode. Fixtures stay detached from the game.
local Shared = game:GetService("ReplicatedStorage").Shared
-- Clone modules to avoid the command bar's require cache after a design iteration.
local copies = Instance.new("Folder")
copies.Name = "DetachedWheelAudit"
local geometry = Shared.Config.WheelGeometry:Clone()
local config = Instance.new("Folder")
config.Name = "Config"
config.Parent = copies
geometry.Parent = config
local tierCopies = Shared.Config.WheelTiers:Clone()
tierCopies.Parent = config
local factory = Shared.WheelModel:Clone()
factory.Parent = copies
local WheelModel = require(factory)
local Geometry = require(geometry)
local GameConfig = require(Shared.Config.GameConfig)
local passed = 0
local counts = {}
local function check(ok: boolean, message: string)
	assert(ok, message)
	passed += 1
end
check(#Geometry == #GameConfig.Treadmills, "Every economy tier needs a matching 3D wheel")
for level, tier in Geometry do
	check(tier.Name == GameConfig.Treadmills[level].Name, `Tier {level}: wrong progression order`)
	local pivot = CFrame.new(39, 6.6, -92) * CFrame.Angles(0, math.rad(90), 0)
	local built = WheelModel.Build(level, pivot)
	local rotor, stand = built.Rotor, built.Stand
	check(rotor:GetPivot() == pivot, `Tier {level}: misplaced hub`)
	check(rotor:GetAttribute("Pivot") == pivot, `Tier {level}: missing resting animation pivot`)
	check(rotor:GetAttribute("Tier") == level, `Tier {level}: missing tier`)
	check(rotor.ModelStreamingMode == Enum.ModelStreamingMode.Atomic, `Tier {level}: rotor must stream atomically`)
	check(stand.ModelStreamingMode == Enum.ModelStreamingMode.Atomic, `Tier {level}: support must stream atomically`)
	check(#rotor:GetChildren() == #tier.Rotor + 1, `Tier {level}: rotating blocks missing`)
	check(#stand:GetChildren() == #tier.Stand, `Tier {level}: fixed blocks missing`)
	local support = stand:GetChildren()[1] :: BasePart
	local supportFrame = support.CFrame
	for _, model in { rotor, stand } do
		for _, part in model:GetChildren() do
			check(part:IsA("BasePart"), `Tier {level}: unexpected model child`)
			local block = part :: BasePart
			check(
				block.Anchored and not block.CanCollide and not block.CanTouch and not block.CanQuery,
				`Tier {level}: {block.Name} obstructs movement or combat`
			)
			check(block.Size.X > 0 and block.Size.Y > 0 and block.Size.Z > 0, `Tier {level}: zero-size block`)
		end
	end
	-- Sweep the running drum: its decor must stay outside a 5.6-stud-wide runner lane.
	for step = 0, 7 do
		local turned = pivot * CFrame.Angles(step * math.pi / 4, 0, 0)
		rotor:PivotTo(turned)
		check(support.CFrame == supportFrame, `Tier {level}: stationary supports rotated`)
		for _, child in rotor:GetChildren() do
			local part = child :: BasePart
			if part.Name == "Hub" then
				check(part.Transparency == 1 and not part.CanCollide, "Axle crosses the runner")
				continue
			end
			local localFrame = pivot:ToObjectSpace(part.CFrame)
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner =
						localFrame:PointToWorldSpace(Vector3.new(0, sy * part.Size.Y / 2, sz * part.Size.Z / 2))
					if math.abs(corner.X) < 2.8 then
						check(
							Vector2.new(corner.Y, corner.Z).Magnitude > 5.25,
							`Tier {level}: {part.Name} enters running space`
						)
					end
				end
			end
		end
	end
	counts[tier.Name] = { Rotor = #tier.Rotor, Stand = #tier.Stand }
	rotor:Destroy()
	stand:Destroy()
end
-- Exercise the actual map's swap contract using a detached vault fixture.
local MapService = require(game:GetService("ServerScriptService").Server.Services.MapService)
local folder = Instance.new("Folder")
local pivot = CFrame.new(10, 6.6, 20) * CFrame.Angles(0, math.pi / 2, 0)
local made = WheelModel.Build(1, pivot)
made.Rotor.Parent = folder
made.Stand.Parent = folder
local label = Instance.new("TextLabel")
local floor = Instance.new("Part")
floor.CFrame = CFrame.new(10, 0.8, 20)
local savedFloor = floor.CFrame
local base = { Folder = folder, Wheel = made.Rotor, TreadmillSign = label, Treadmill = floor }
made.Rotor:SetAttribute("Spinning", true)
made.Rotor:SetAttribute("SpinRate", 3.6)
MapService.SetWheelTier(base :: any, 1)
check(base.Wheel == made.Rotor, "Same-tier refresh rebuilt the wheel")
for _, level in { 5, 13, 1 } do
	local old = base.Wheel
	local oldStand = folder:FindFirstChild("WheelDetails") :: Model
	MapService.SetWheelTier(base :: any, level)
	check(base.Wheel ~= old and old.Parent == nil, "Old drum not replaced")
	check(oldStand.Parent == nil, "Old decorations leaked")
	check(base.Wheel:GetAttribute("Tier") == level, "Upgrade/reset tier wrong")
	check(base.Wheel:GetAttribute("Pivot") == pivot, "Rotated vault axle changed")
	check(base.Wheel:GetAttribute("Spinning") == true, "Upgrade stopped active training")
	check(base.Wheel:GetAttribute("SpinRate") == 3.6, "Animation rate lost")
	check(floor.CFrame == savedFloor, "Training pad moved")
	check(label.Text == GameConfig.Treadmills[level].Name, "Upgrade/reset sign wrong")
	local n = 0
	for _, child in folder:GetChildren() do
		if child.Name == "WheelDetails" then
			n += 1
		end
	end
	check(n == 1, "Duplicate fixed supports")
end
folder:Destroy()
label:Destroy()
floor:Destroy()
copies:Destroy()
return { Passed = passed, Counts = counts, UpgradeLifecycle = true }
