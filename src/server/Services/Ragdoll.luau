--!strict
-- Classic murder-game deaths: the body goes limp and collapses to the floor with a death cry.
-- Every Motor6D is swapped for a limited BallSocketConstraint so R15 rigs fold up naturally.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)

local Ragdoll = {}

function Ragdoll.Collapse(model: Model, push: Vector3?)
	for _, motor in model:GetDescendants() do
		-- Current R15 rigs use AnimationConstraints and already carry a BallSocketConstraint per
		-- joint; switching the animation joints off hands the body over to those sockets
		if motor:IsA("AnimationConstraint") then
			motor.Enabled = false
		elseif motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			local a0 = Instance.new("Attachment")
			a0.Name = "RagdollA0"
			a0.CFrame = motor.C0
			a0.Parent = motor.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "RagdollA1"
			a1.CFrame = motor.C1
			a1.Parent = motor.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = 70
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -45
			socket.TwistUpperAngle = 45
			socket.Parent = motor.Part0
			motor.Enabled = false
		end
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			-- Limbs collide so the body lands on the floor instead of sinking through it
			local isLimb = part.Parent == model and part.Name ~= "HumanoidRootPart"
			part.CanCollide = isLimb
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and push then
		root:ApplyImpulse(push * root.AssemblyMass)
	end
end

-- Steal An Egg-style hit: a living player goes limp and is flung, then gets back up after
-- `seconds`. The joints go limp here (replicates to everyone); the fling itself is applied by the
-- player's own client (client/Tumble, from the TumblePush attribute) because their client owns the
-- body's physics - flinging from the server makes it freeze and snap on their screen.
-- Returns false if they're already tumbling (no stacking).
local tumbling: { [Player]: boolean } = {}
function Ragdoll.Tumble(player: Player, push: Vector3, seconds: number): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if tumbling[player] or not character or not humanoid or humanoid.Health <= 0 then
		return false
	end
	tumbling[player] = true
	local root = character:FindFirstChild("HumanoidRootPart")
	local joints: { AnimationConstraint } = {}
	for _, d in character:GetDescendants() do
		if d:IsA("AnimationConstraint") and d.Enabled then
			-- Keep the root joint: it's what ties the body to the (invisible) root part the fling
			-- moves. Without it the root flies off alone and the body flops where it was hit.
			local a0, a1 = d.Attachment0, d.Attachment1
			local onRoot = (a0 ~= nil and a0.Parent == root) or (a1 ~= nil and a1.Parent == root)
			if not onRoot then
				d.Enabled = false
				table.insert(joints, d)
			end
		end
	end
	humanoid.PlatformStand = true
	player:SetAttribute("TumblePush", push)
	player:SetAttribute("Tumbling", workspace:GetServerTimeNow() + seconds)
	task.delay(seconds, function()
		tumbling[player] = nil
		if player.Parent then
			player:SetAttribute("Tumbling", nil)
			player:SetAttribute("TumblePush", nil)
		end
		if not character.Parent or humanoid.Health <= 0 then
			return
		end
		for _, joint in joints do
			joint.Enabled = true
		end
		humanoid.PlatformStand = false
	end)
	return true
end

function Ragdoll.DeathCry(model: Model)
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "DeathCry"
	sound.SoundId = Sounds.Death
	sound.Volume = 0.9
	sound.RollOffMaxDistance = 120
	sound.Parent = head
	sound:Play()
end

return Ragdoll
