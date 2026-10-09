--!strict
-- Stand-ins for missing players in Studio test rounds: disguised R15 NPCs that wander the round
-- map, run from the Murderer, or play the Murderer themselves. RoundService decides where each one
-- wants to go and who it stabs; this module builds them, walks them around furniture
-- (pathfinding, or straight at the goal when nothing is in the way), animates and kills them.

local PathfindingService = game:GetService("PathfindingService")

local KnifeModel = require(game:GetService("ReplicatedStorage").Shared.KnifeModel)
local Disguises = require(script.Parent.Disguises)
local Ragdoll = require(script.Parent.Ragdoll)
local Net = require(script.Parent.Parent.Remotes)

local RoundBots = {}

export type Bot = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Name: string,
	Role: string, -- "Murderer" | "Innocent"
	Alive: boolean,
	Goal: Vector3?,
	Waypoints: { Vector3 },
	NextWaypoint: number,
	PathGoal: Vector3?, -- the goal the current waypoints lead to
	PathAt: number,
	Computing: boolean,
	Tracks: { [string]: AnimationTrack },
	Playing: string?,
	NextThink: number, -- RoundService's per-bot timers
	NextStab: number,
	IdleUntil: number,
	Knife: Model?,
	Gun: Tool?, -- the Revolver, when this bot is the Sheriff
	NextShot: number,
	AimUntil: number, -- 0 = not aiming
	NextJump: number, -- os.clock() of its next hop (players hop around; bots do too)
	StuckSince: number?, -- walking somewhere but not moving: jump over it
}

-- Roblox's own R15 idle / run (the same ones the guards use)
local ANIMATIONS: { [string]: string } = {
	Idle = "rbxassetid://507766388",
	Run = "rbxassetid://507767714",
	Jump = "rbxassetid://507765000",
}

local rng = Random.new()

local mapParams = RaycastParams.new()
mapParams.FilterType = Enum.RaycastFilterType.Include

-- Line-of-sight checks only look at the round map's walls and furniture
function RoundBots.SetMap(map: Instance)
	mapParams.FilterDescendantsInstances = { map }
end

local function loadTracks(humanoid: Humanoid): { [string]: AnimationTrack }
	local animator = humanoid:FindFirstChildOfClass("Animator") :: Animator?
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local tracks: { [string]: AnimationTrack } = {}
	for key, id in ANIMATIONS do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall((animator :: Animator).LoadAnimation, animator :: Animator, animation)
		if ok then
			track.Looped = key ~= "Jump" -- (the hop plays once, over the run)
			if key == "Jump" then
				track.Priority = Enum.AnimationPriority.Action
			end
			tracks[key] = track
		end
	end
	return tracks
end

function RoundBots.Spawn(at: CFrame, role: string, taken: { [string]: boolean }, parent: Instance): Bot
	local rig, name = Disguises.BuildBot(taken)
	taken[name] = true
	rig.Name = name
	rig.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- streams in whole, never half a body
	rig:SetAttribute("Role", role) -- Radar finds a Murderer bot by this
	rig:AddTag("RoundBot") -- clients animate these like players (Moves)
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = name
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.WalkSpeed = 10
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	for _, d in rig:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	rig.PrimaryPart = root
	rig:PivotTo(at)
	rig.Parent = parent
	root:SetNetworkOwner(nil) -- the server walks them
	return {
		Model = rig,
		Humanoid = humanoid,
		Root = root,
		Name = name,
		Role = role,
		Alive = true,
		Goal = nil,
		Waypoints = {},
		NextWaypoint = 1,
		PathGoal = nil,
		PathAt = 0,
		Computing = false,
		Tracks = loadTracks(humanoid),
		Playing = nil,
		NextThink = 0,
		NextStab = 0,
		IdleUntil = 0,
		Knife = nil,
		Gun = nil,
		NextShot = 0,
		AimUntil = 0,
		NextJump = os.clock() + rng:NextNumber(2, 8),
		StuckSince = nil,
	}
end

-- The Murderer bot's knife, welded into its right hand blade-up (same grip as a held Tool)
function RoundBots.GiveKnife(bot: Bot, knifeName: string)
	bot.Model:SetAttribute("KnifeOut", true)
	local hand = bot.Model:FindFirstChild("RightHand") :: BasePart?
	if not hand or bot.Knife then
		return
	end
	local knife = KnifeModel.Build(knifeName, false)
	KnifeModel.FitLength(knife, 1.7)
	knife:PivotTo(hand.CFrame * CFrame.new(0, -0.3, 0) * CFrame.Angles(math.rad(-90), 0, 0))
	for _, d in knife:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = knife.PrimaryPart :: BasePart
	weld.Parent = knife
	knife.Name = "Knife"
	knife.Parent = bot.Model
	bot.Knife = knife
	Net.Animate(bot.Model, "Draw")
end

function RoundBots.WalkTo(bot: Bot, goal: Vector3?)
	bot.Goal = goal
end

local function clearPath(from: Vector3, to: Vector3): boolean
	-- Two rays: chest height (walls) and knee height (tables, beds)
	for _, height in { 0, -1.8 } do
		local origin = from + Vector3.new(0, height, 0)
		local target = Vector3.new(to.X, origin.Y, to.Z)
		if workspace:Raycast(origin, target - origin, mapParams) then
			return false
		end
	end
	return true
end

local function computePath(bot: Bot, goal: Vector3)
	bot.Computing = true
	bot.PathAt = os.clock()
	task.spawn(function()
		local path = PathfindingService:CreatePath({ AgentRadius = 1.6, AgentHeight = 5, AgentCanJump = false })
		local ok = pcall(path.ComputeAsync, path, bot.Root.Position, goal)
		bot.Computing = false
		if not bot.Alive then
			return
		end
		bot.Waypoints = {}
		if ok and path.Status == Enum.PathStatus.Success then
			for _, waypoint in path:GetWaypoints() do
				table.insert(bot.Waypoints, waypoint.Position)
			end
		end
		bot.NextWaypoint = 2 -- the first one is where it's standing
		bot.PathGoal = goal
	end)
end

local function play(bot: Bot, key: string, speed: number)
	local track = bot.Tracks[key]
	if bot.Playing ~= key then
		local old = bot.Playing and bot.Tracks[bot.Playing]
		if old then
			old:Stop(0.2)
		end
		if track then
			track:Play(0.2)
		end
		bot.Playing = key
	end
	if track then
		track:AdjustSpeed(speed)
	end
end

-- Called a few times a second: steer toward the goal and pick the matching animation
function RoundBots.Step(bot: Bot)
	if not bot.Alive then
		return
	end
	local root, humanoid = bot.Root, bot.Humanoid
	local goal = bot.Goal
	if not goal then
		humanoid:MoveTo(root.Position)
	elseif clearPath(root.Position, goal) then
		bot.Waypoints = {}
		humanoid:MoveTo(goal)
	else
		local stale = not bot.PathGoal
			or ((bot.PathGoal :: Vector3) - goal).Magnitude > 5
			or os.clock() - bot.PathAt > 2
			or bot.NextWaypoint > #bot.Waypoints
		if stale and not bot.Computing then
			computePath(bot, goal)
		end
		local waypoint = bot.Waypoints[bot.NextWaypoint]
		if waypoint then
			local flat = Vector3.new(waypoint.X - root.Position.X, 0, waypoint.Z - root.Position.Z)
			if flat.Magnitude < 2.5 then
				bot.NextWaypoint += 1
				waypoint = bot.Waypoints[bot.NextWaypoint]
			end
		end
		humanoid:MoveTo(waypoint or goal)
	end
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	-- Hop like a player: now and then while running (more when running for its life), and
	-- straight away when it's walking into something and not getting anywhere
	local now = os.clock()
	local moving = goal ~= nil
	if moving and speed < 1 then
		bot.StuckSince = bot.StuckSince or now
	else
		bot.StuckSince = nil
	end
	local stuck = bot.StuckSince ~= nil and now - (bot.StuckSince :: number) > 0.8
	if moving and humanoid.FloorMaterial ~= Enum.Material.Air and (stuck or (speed > 6 and now >= bot.NextJump)) then
		humanoid.Jump = true
		local hop = bot.Tracks.Jump
		if hop then
			hop:Play(0.1)
		end
		local fleeing = humanoid.WalkSpeed >= 14
		bot.NextJump = now + (if fleeing then rng:NextNumber(1.5, 4.5) else rng:NextNumber(3, 9))
		bot.StuckSince = nil
	end
	if speed > 1 then
		play(bot, "Run", math.max(0.6, speed / 16))
	else
		play(bot, "Idle", 1)
	end
end

function RoundBots.Reached(bot: Bot, within: number): boolean
	local goal = bot.Goal
	if not goal then
		return true
	end
	local flat = Vector3.new(goal.X - bot.Root.Position.X, 0, goal.Z - bot.Root.Position.Z)
	return flat.Magnitude < within
end

function RoundBots.Face(bot: Bot, point: Vector3)
	local at = bot.Root.Position
	local flat = Vector3.new(point.X, at.Y, point.Z)
	if (flat - at).Magnitude > 0.1 then
		bot.Root.CFrame = CFrame.lookAt(at, flat)
	end
end

-- Collapse with a death cry; the body stays (frozen into `bodies`) like a player's would
function RoundBots.Kill(bot: Bot, push: Vector3?, bodies: Instance)
	if not bot.Alive then
		return
	end
	bot.Alive = false
	bot.Goal = nil
	for _, track in bot.Tracks do
		track:Stop(0)
	end
	bot.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	bot.Humanoid.Health = 0
	Ragdoll.Collapse(bot.Model, push)
	Ragdoll.DeathCry(bot.Model)
	local model = bot.Model
	task.delay(2.5, function()
		if not model.Parent or not bodies.Parent then
			return
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		model.Parent = bodies
	end)
end

return RoundBots
