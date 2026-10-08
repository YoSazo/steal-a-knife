--!strict
-- The Murderer's Decoy perk (RoundService): a copy of the Murderer that sprints off for a while,
-- turning when something's in the way, then vanishes in a puff of smoke.
local RunService = game:GetService("RunService")

local Net = require(script.Parent.Parent.Remotes)

local Decoy = {}

local folder: Folder? = nil

local function effectsFolder(): Folder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "DecoyEffects"
		f.Parent = workspace
		folder = f
	end
	return folder :: Folder
end

function Decoy.Run(player: Player, duration: number)
	local character = player.Character
	local humanoidAlive = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root or not humanoidAlive or humanoidAlive.Health <= 0 then
		return
	end
	character.Archivable = true
	local ok, clone = pcall(character.Clone, character)
	local model = (clone :: any) :: Model?
	if not ok or not model then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("Tool") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	local decoyRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart
	decoyRoot.Anchored = true
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.EvaluateStateMachine = false
	model.Name = `Decoy_{player.Name}`
	model.Parent = effectsFolder()

	-- Off at an angle, so it doesn't run in a straight line from you
	local look = CFrame.Angles(0, math.rad(math.random(-50, 50)), 0) * root.CFrame.LookVector
	local direction = Vector3.new(look.X, 0, look.Z).Unit

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local animation = Instance.new("Animation")
		animation.AnimationId = "rbxassetid://507767714" -- R15 run
		local trackOk, track = pcall(animator.LoadAnimation, animator, animation)
		if trackOk then
			track.Looped = true
			track:Play()
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model, character }
	local speed = 18
	local position = decoyRoot.Position
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		if os.clock() - started > duration or not model.Parent then
			connection:Disconnect()
			if model.Parent then
				Net.Remotes.Effect:FireAllClients("Smoke", decoyRoot.Position)
				model:Destroy()
			end
			return
		end
		-- Turn when something's in the way
		if workspace:Raycast(position, direction * 4, params) then
			direction = (CFrame.Angles(0, math.rad(if math.random() < 0.5 then 90 else -90), 0) * direction)
		end
		position += direction * speed * dt
		decoyRoot.CFrame = CFrame.lookAt(position, position + direction)
	end)
end

return Decoy
