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
