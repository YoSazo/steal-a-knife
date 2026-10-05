--!strict
-- Your Haunted Wheel, Steal An Egg style: the moment you step into it you're snapped to its centre,
-- facing the way the tread rolls, and held there running (Moves plays the run while the server's
-- Training attribute is on) until you push to leave or jump. Then you step out and it won't grab
-- you again until you've left it. Client side, so it's instant; the server still decides Training
-- from where you stand (BaseService), and you stand right in the middle.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local TreadmillLock = {}

local EXIT_STEP = 5.5 -- studs: where you land when you step out

local function myBelt(): BasePart?
	local index = player:GetAttribute("VaultIndex")
	local map = workspace:FindFirstChild("Map")
	local bases = map and map:FindFirstChild("Bases")
	local base = bases and type(index) == "number" and bases:FindFirstChild(`Base{index}`)
	local belt = base and base:FindFirstChild("WheelFloor", true)
	return if belt and belt:IsA("BasePart") then belt else nil
end

local function inside(belt: BasePart, position: Vector3, margin: number): boolean
	local at = belt.CFrame:PointToObjectSpace(position)
	return math.abs(at.X) < belt.Size.X / 2 + margin
		and math.abs(at.Z) < belt.Size.Z / 2 + margin
		and at.Y > -1
		and at.Y < 7
end

function TreadmillLock.Init()
	local locked = false
	local latched = false -- just stepped out: don't grab again until they've left the wheel
	-- Once you're in, movement only counts after you've let go of it once: walking in while
	-- holding forward (on purpose or not) keeps you in; a fresh push or jump takes you out
	local armed = false
	local belt: BasePart? = nil
	local lastLookup = 0
	RunService.PreSimulation:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if
			not root
			or not humanoid
			or humanoid.Health <= 0
			or player:GetAttribute("InRound")
			or player:GetAttribute("RoundTeleport")
		then
			locked = false
			return
		end
		if not belt or not belt.Parent or os.clock() - lastLookup > 3 then
			belt = myBelt()
			lastLookup = os.clock()
		end
		local wheel = belt
		if not wheel then
			locked = false
			return
		end
		local within = inside(wheel, root.Position, 0.6)
		if latched then
			if not inside(wheel, root.Position, 1.5) then
				latched = false
			end
			return
		end
		if not locked and within then
			locked = true
			armed = false
		end
		if not locked then
			return
		end
		-- Facing the way the rungs roll (the server's run direction: the wheel's +Z)
		local forward = wheel.CFrame.ZVector
		local center = wheel.Position + Vector3.new(0, wheel.Size.Y / 2 + humanoid.HipHeight + root.Size.Y / 2, 0)
		-- Push any way (or jump) to leave
		local push = humanoid.MoveDirection
		local pushing = push.Magnitude > 0.2 or humanoid.Jump
		if not armed then
			armed = not pushing
		end
		if armed and pushing then
			locked = false
			latched = true
			-- Out through the wheel's open side (along its axle), the side you pushed toward;
			-- forwards or back would put you in the ring
			local side = wheel.CFrame.XVector
			local away = if push:Dot(side) < 0 then -side else side
			local out = center + away * (wheel.Size.X / 2 + EXIT_STEP - 2.5)
			root.CFrame = CFrame.lookAt(out, out + away)
			return
		end
		root.CFrame = CFrame.lookAt(center, center + forward)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end)
	player.CharacterAdded:Connect(function()
		locked, latched = false, false
	end)
end

return TreadmillLock
