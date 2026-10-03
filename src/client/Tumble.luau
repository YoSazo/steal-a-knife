--!strict
-- The fling half of a Steal An Egg-style hit (server Ragdoll.Tumble goes limp and sets these):
-- player attribute TumblePush (Vector3) = the launch velocity, Tumbling = when it ends. This client
-- owns its character's physics, so the throw is applied here: smooth on every screen.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local Tumble = {}

function Tumble.Init()
	player:GetAttributeChangedSignal("Tumbling"):Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not root then
			return
		end
		if player:GetAttribute("Tumbling") then
			local push = player:GetAttribute("TumblePush")
			-- Physics state: the walk controller lets go of the body, so the push isn't eaten
			humanoid.PlatformStand = true
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			if typeof(push) == "Vector3" then
				local spin = Vector3.new(math.random(-6, 6), math.random(-3, 3), math.random(-6, 6))
				-- Held for a few frames so nothing (landing, the controller waking up) cancels it
				-- Every limb gets the push (they're loose pieces while limp, and would drag the rest back)
				local parts: { BasePart } = {}
				for _, d in character:GetDescendants() do
					if d:IsA("BasePart") and not d.Anchored then
						table.insert(parts, d)
					end
				end
				for _ = 1, 4 do
					if not player:GetAttribute("Tumbling") then
						break
					end
					for _, part in parts do
						part.AssemblyLinearVelocity = push
					end
					root.AssemblyAngularVelocity = spin
					RunService.Heartbeat:Wait()
				end
			end
		else
			-- Back on your feet
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

return Tumble
