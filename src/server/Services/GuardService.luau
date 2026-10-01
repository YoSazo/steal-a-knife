--!strict
-- The Manor's night watchmen. Real R15 characters (blocky, named, animated) but anchored and
-- moved by the server, so exploiters can't push or fling them.
--
-- Each guard holds a random knife from its zone's pool - that knife is the loot. Guards attack
-- anyone who comes close inside their zone, fight back when hit, and anyone who picks up a knife
-- gets every guard in that zone (and the one in front) on their tail. Epic+ guards also wind up
-- and throw knives in a straight line. Kill one and it collapses, drops its knife, and a new
-- watchman takes its place a little later. Guards never leave the arena or enter the vaults.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimLibrary = require(ReplicatedStorage.Shared.AnimLibrary)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local Disguises = require(script.Parent.Disguises)
local MapService = require(script.Parent.MapService)
local Obstacles = require(script.Parent.Obstacles)
local Ragdoll = require(script.Parent.Ragdoll)
local StealService = require(script.Parent.StealService)

type ZoneConfig = {
	Rarity: string,
	Guards: number,
	GuardSpeed: number,
	Detect: number,
	Health: number,
	Damage: number,
	Reward: number,
	Respawn: number,
	Throws: boolean?,
	Color: Color3,
}

export type Guard = {
	Model: Model,
	Zone: MapService.Zone,
	Config: ZoneConfig,
	Position: Vector3,
	Wander: Vector3,
	Target: Player?,
	AlertUntil: number, -- spotted someone; frozen with a "!" until this time
	Alert: BillboardGui,
	HealthFill: Frame,
	HealthBar: BillboardGui,
	Health: number,
	Dead: boolean,
	KnifeName: string,
	Knife: Model,
	LastAttack: number,
	ThrowReadyAt: number,
	WindupUntil: number, -- winding up a throw; frozen, knife glowing, until this time
	Tracks: { [string]: AnimationTrack },
	Playing: string?,
	BusyUntil: number, -- mid-stab or staggered: stands still until this time
	Lure: BasePart?, -- a Decoy it's chasing instead of a player
	LureUntil: number,
	OnLureReached: (() -> ())?,
}

type Projectile = { Model: Model, Position: Vector3, Direction: Vector3, Traveled: number, Damage: number }

local GuardService = {}

local HEIGHT = 3 -- HumanoidRootPart centre above the floor (set from a probe rig in Init)
local LEASH = 0.8 -- how far (in zone depths) a guard will chase out of its own zone
local GUARD_NAMES = {
	"Gerald",
	"Otis",
	"Barnaby",
	"Mortimer",
	"Edgar",
	"Humphrey",
	"Silas",
	"Victor",
	"Rupert",
	"Ambrose",
	"Cornelius",
	"Percy",
	"Wendell",
	"Horace",
	"Ezra",
	"Clyde",
	"Basil",
	"Jasper",
	"Neville",
	"Ignatius",
	"Thaddeus",
	"Winston",
}
-- Standard R15 animations (Roblox's own, public)
local ANIMATIONS: { [string]: string } = {
	Idle = "rbxassetid://507766388",
	Walk = "rbxassetid://507777826",
	Run = "rbxassetid://507767714",
}

local guards: { Guard } = {}
local guardByModel: { [Model]: Guard } = {}
local projectiles: { Projectile } = {}
local projectileFolder: Folder
local guardFolder: Folder
local rng = Random.new()
local nameCursor = 0

-- Building a watchman -----------------------------------------------------------------------

local function weldTo(part: BasePart, to: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = to
	weld.Part1 = part
	weld.Parent = part
end

local function attach(
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	to: BasePart,
	offset: CFrame,
	parent: Instance
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CFrame = to.CFrame * offset
	weldTo(p, to)
	p.Parent = parent
	return p
end

local function nextName(): string
	nameCursor += 1
	return GUARD_NAMES[(nameCursor - 1) % #GUARD_NAMES + 1]
end

local function randomKnife(rarity: string): string
	local pool = Knives.ByRarity[rarity]
	return pool[rng:NextInteger(1, #pool)].Name
end

local function healthBar(head: BasePart): (BillboardGui, Frame)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.fromOffset(90, 10)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 90
	gui.Enabled = false
	gui.Adornee = head
	gui.Parent = head
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(40, 10, 10)
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(230, 50, 50)
	fill.BorderSizePixel = 0
	fill.Parent = back
	return gui, fill
end

local function buildRig(zoneColor: Color3, knifeName: string): Model
	local description = Instance.new("HumanoidDescription")
	local coat = Color3.fromRGB(34, 32, 44)
	description.HeadColor = Color3.fromRGB(234, 184, 146)
	description.TorsoColor = coat
	description.LeftArmColor = coat
	description.RightArmColor = coat
	description.LeftLegColor = Color3.fromRGB(22, 22, 28)
	description.RightLegColor = Color3.fromRGB(22, 22, 28)
	local rig = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	rig.Name = "Guard"
	rig:AddTag("Guard") -- clients animate these (idle fidgets, stabs, throws)
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = nextName()
	humanoid.NameDisplayDistance = 80
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.BreakJointsOnDeath = false
	humanoid.EvaluateStateMachine = false -- the server moves them; no physics states needed
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			-- CanQuery stays on so thrown knives can hit them
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	rig.PrimaryPart = root

	local head = rig:FindFirstChild("Head") :: BasePart
	Disguises.AddHat(head, "Cap", Color3.fromRGB(20, 20, 26))
	local leftArm = rig:FindFirstChild("LeftUpperArm") :: BasePart
	attach(
		"Armband",
		leftArm.Size * Vector3.new(1.1, 0.3, 1.1),
		zoneColor,
		Enum.Material.Neon,
		leftArm,
		CFrame.new(0, 0.1, 0),
		rig
	)

	-- Lantern in the left hand, flashlight beam from the head
	local leftHand = rig:FindFirstChild("LeftHand") :: BasePart
	local lantern = attach(
		"Lantern",
		Vector3.new(0.6, 0.8, 0.6),
		Color3.fromRGB(255, 190, 110),
		Enum.Material.Neon,
		leftHand,
		CFrame.new(0, -0.6, 0),
		rig
	)
	local lanternLight = Instance.new("PointLight")
	lanternLight.Color = Color3.fromRGB(255, 190, 110)
	lanternLight.Range = 14
	lanternLight.Brightness = 1.5
	lanternLight.Parent = lantern
	local beam = Instance.new("SpotLight")
	beam.Face = Enum.NormalId.Front
	beam.Angle = 50
	beam.Range = 28
	beam.Brightness = 3
	beam.Color = Color3.fromRGB(255, 235, 200)
	beam.Parent = head

	-- The knife it guards, held in the right hand, blade forward. This is what drops on death.
	local rightHand = rig:FindFirstChild("RightHand") :: BasePart
	local knife = KnifeModel.Build(knifeName, false)
	KnifeModel.FitLength(knife, 2.4)
	knife:PivotTo(rightHand.CFrame * CFrame.new(0, -0.3, 0) * CFrame.Angles(math.rad(-90), 0, 0))
	for _, d in knife:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	weldTo(knife.PrimaryPart :: BasePart, rightHand)
	knife.Name = "Knife"
	knife.Parent = rig

	-- The loot: a sealed case of its zone's rarity strapped to its back
	local torso = rig:FindFirstChild("UpperTorso") :: BasePart?
	local rarity = Knives.ByName[knifeName].Rarity
	if torso then
		local case = KnifeModel.BuildCase(rarity, false)
		case:ScaleTo(0.42)
		case:PivotTo(torso.CFrame * CFrame.new(0, 0.1, torso.Size.Z / 2 + 0.45) * CFrame.Angles(0, math.pi, 0))
		for _, d in case:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Massless = true
			elseif d:IsA("ParticleEmitter") or d:IsA("PointLight") then
				d:Destroy()
			end
		end
		weldTo(case.PrimaryPart :: BasePart, torso)
		case.Name = "BackCase"
		case.Parent = rig
	end

	local alert = Instance.new("BillboardGui")
	alert.Name = "Alert"
	alert.Size = UDim2.fromScale(3, 3)
	alert.StudsOffset = Vector3.new(0, 4.5, 0)
	alert.Enabled = false
	alert.Adornee = head
	alert.Parent = head
	local mark = Instance.new("TextLabel")
	mark.Size = UDim2.fromScale(1, 1)
	mark.BackgroundTransparency = 1
	mark.Font = Enum.Font.FredokaOne
	mark.Text = "!"
	mark.TextScaled = true
	mark.TextColor3 = Color3.fromRGB(255, 60, 60)
	mark.TextStrokeTransparency = 0
	mark.Parent = alert
	return rig
end

local function loadTracks(rig: Model): { [string]: AnimationTrack }
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	local animator: Animator = humanoid:FindFirstChildOfClass("Animator")
		or (function()
			local created = Instance.new("Animator")
			created.Parent = humanoid
			return created
		end)()
	local tracks: { [string]: AnimationTrack } = {}
	for key, id in ANIMATIONS do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(animator.LoadAnimation, animator, animation)
		if ok then
			track.Looped = true
			tracks[key] = track
		end
	end
	return tracks
end

-- Plays one looping animation at a time (idle / walk / run)
local function animate(guard: Guard, key: string, speed: number?)
	local track = guard.Tracks[key]
	if guard.Playing ~= key then
		local old = guard.Playing and guard.Tracks[guard.Playing]
		if old then
			old:Stop(0.2)
		end
		if track then
			track:Play(0.2)
		end
		guard.Playing = key
	end
	if track and speed then
		track:AdjustSpeed(speed)
	end
end

local function randomPointIn(b: MapService.Bounds): Vector3
	return Vector3.new(rng:NextNumber(b.MinX + 8, b.MaxX - 8), HEIGHT, rng:NextNumber(b.MinZ + 6, b.MaxZ - 6))
end

local spawnGuard: (MapService.Zone, ZoneConfig, Guard?) -> ()

-- Targets, combat, death --------------------------------------------------------------------

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Someone worth attacking: alive, not in a round, inside the arena, not safe in a vault
local function validTarget(player: Player): BasePart?
	local root = rootOf(player)
	if not root or player:GetAttribute("InRound") then
		return nil
	end
	if player:GetAttribute("Invisible") or player:GetAttribute("Mimic") then
		return nil -- Vanish / Mimic: they can't see you
	end
	if not MapService.InBounds(MapService.Arena :: MapService.Bounds, root.Position, 4) then
		return nil
	end
	if BaseService.IsInAnyBase(root.Position) or MapService.IsInHideaway(root.Position) then
		return nil -- safe in a vault or a hideaway nook
	end
	return root
end

local function findTarget(guard: Guard): Player?
	local best, bestScore = nil, math.huge
	local carriers = StealService.GetCarriers()
	for _, player in Players:GetPlayers() do
		local root = validTarget(player)
		if root then
			local dist = (root.Position - guard.Position).Magnitude
			if dist < guard.Config.Detect then
				-- Carriers first, then whoever is closest
				local score = dist - (if carriers[player] then 1000 else 0)
				if score < bestScore then
					best, bestScore = player, score
				end
			end
		end
	end
	return best
end

local function setTarget(guard: Guard, player: Player?)
	if guard.Target ~= player then
		guard.Target = player
		if player then
			guard.AlertUntil = os.clock() + GameConfig.GuardAlertTime
			Net.Animate(guard.Model, "Alert")
		end
	end
end

local function setKnifeGlow(guard: Guard, on: boolean)
	local blade = guard.Knife:FindFirstChild("Blade") :: BasePart?
	if blade then
		local knife = Knives.ByName[guard.KnifeName]
		blade.Material = if on or knife.Neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		blade.Color = if on then Color3.fromRGB(255, 40, 40) else knife.BladeColor
	end
end

local function hurtPlayer(player: Player, amount: number, from: Vector3)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootOf(player)
	if not character or not humanoid or not root then
		return
	end
	-- Shield power: blocks this hit and pops
	local shieldUntil = character:GetAttribute("ShieldUntil")
	if type(shieldUntil) == "number" and workspace:GetServerTimeNow() < shieldUntil then
		character:SetAttribute("ShieldUntil", nil)
		Net.Remotes.Effect:FireAllClients("Shield", root.Position)
		return
	end
	humanoid:TakeDamage(amount)
	Net.Remotes.Effect:FireAllClients("Hit", root.Position)
	Net.Remotes.Effect:FireClient(player, "Hurt", from)
	if humanoid.Health > 0 then
		Net.Animate(character :: Model, "Hurt")
	end
end

local function die(guard: Guard, killer: Player?)
	guard.Dead = true
	guard.HealthBar.Enabled = false
	guard.Alert.Enabled = false
	for _, track in guard.Tracks do
		track:Stop(0.1)
	end
	local model = guard.Model
	-- The sealed case strapped to its back hits the floor for whoever wants it
	guard.Knife:Destroy()
	local backCase = model:FindFirstChild("BackCase")
	if backCase then
		backCase:Destroy()
	end
	StealService.DropCase(guard.Config.Rarity, guard.Position)

	-- Collapse like a Mad Murderer body: death cry, go limp, fall over
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
	Ragdoll.DeathCry(model)
	local killerRoot = killer and rootOf(killer)
	local push = Vector3.new(0, 6, 0)
	if killerRoot then
		local away = (guard.Position - killerRoot.Position) * Vector3.new(1, 0, 1)
		if away.Magnitude > 0.1 then
			push += away.Unit * 18
		end
	end
	Ragdoll.Collapse(model, push)
	local root = model.PrimaryPart
	if root then
		pcall(root.SetNetworkOwner, root, nil)
	end
	game:GetService("Debris"):AddItem(model, 6)
	guardByModel[model] = nil

	if killer then
		DataService.AddCash(killer, guard.Config.Reward)
		Net.Notify(killer, `Took down a {guard.Config.Rarity} watchman! +${guard.Config.Reward}`, "good")
	end
	task.delay(guard.Config.Respawn, function()
		spawnGuard(guard.Zone, guard.Config, guard)
	end)
end

-- Called by CombatService (swings and thrown knives)
function GuardService.Damage(guard: Guard, amount: number, attacker: Player?)
	if guard.Dead then
		return
	end
	guard.Health -= amount
	guard.HealthBar.Enabled = true
	guard.HealthFill.Size = UDim2.fromScale(math.max(0, guard.Health / guard.Config.Health), 1)
	local head = guard.Model:FindFirstChild("Head") :: BasePart?
	Net.Remotes.Effect:FireAllClients("Hit", if head then head.Position else guard.Position)
	if attacker then
		Net.Remotes.Effect:FireClient(attacker, "Damage", guard.Position + Vector3.new(0, 3, 0), amount)
	end
	if guard.Health <= 0 then
		die(guard, attacker)
		return
	end
	-- Stagger back a step, away from whoever hit it
	Net.Animate(guard.Model, "GuardHurt")
	guard.BusyUntil = math.max(guard.BusyUntil, os.clock() + 0.25)
	guard.Model:SetAttribute("ChargeStart", nil) -- a hit interrupts a throw wind-up
	guard.WindupUntil = 0
	local attackerRoot = attacker and rootOf(attacker)
	if attackerRoot then
		local away = (guard.Position - attackerRoot.Position) * Vector3.new(1, 0, 1)
		if away.Magnitude > 0.1 then
			local arena = MapService.Arena :: MapService.Bounds
			local pushed = guard.Position + away.Unit * 1.6
			guard.Position = Vector3.new(
				math.clamp(pushed.X, arena.MinX + 2, arena.MaxX - 2),
				HEIGHT,
				math.clamp(pushed.Z, arena.MinZ + 1, arena.MaxZ - 2)
			)
			guard.Model:PivotTo(CFrame.lookAt(guard.Position, guard.Position - away))
		end
	end
	if attacker and guard.Target ~= attacker and validTarget(attacker) then
		-- Fight back, no hesitation
		guard.Target = attacker
		guard.AlertUntil = 0
	end
end

-- How high a rig's HumanoidRootPart sits above the floor (burglars use the same rigs)
function GuardService.RootHeight(): number
	return HEIGHT
end

-- Every live guard (traps and Radar look through these)
function GuardService.All(): { Guard }
	local alive = {}
	for _, guard in guards do
		if not guard.Dead then
			table.insert(alive, guard)
		end
	end
	return alive
end

-- Bear Trap: the guard is stuck in place for a while
function GuardService.Stun(guard: Guard, seconds: number)
	if guard.Dead then
		return
	end
	guard.BusyUntil = math.max(guard.BusyUntil, os.clock() + seconds)
	guard.WindupUntil = 0
	guard.Model:SetAttribute("ChargeStart", nil)
	Net.Animate(guard.Model, "GuardHurt")
end

-- Decoy: guards hunting `owner` (or close to the decoy) chase `part` instead until it's caught
function GuardService.Lure(owner: Player, part: BasePart, duration: number, onReached: () -> ())
	local until_ = os.clock() + duration
	for _, guard in guards do
		if guard.Dead then
			continue
		end
		local close = (guard.Position - part.Position).Magnitude < guard.Config.Detect
		if guard.Target == owner or close then
			guard.Lure = part
			guard.LureUntil = until_
			guard.OnLureReached = onReached
			if guard.Target == owner then
				guard.Target = nil
			end
		end
	end
end

-- The live guard a part belongs to (for hit detection)
function GuardService.FromPart(part: Instance): Guard?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local guard = guardByModel[model]
		if guard then
			return guard
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- The closest live guard in front of a position within range (for melee swings)
function GuardService.InReach(position: Vector3, look: Vector3, range: number): Guard?
	local best, bestDist = nil, range
	for _, guard in guards do
		if not guard.Dead then
			local offset = guard.Position - position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local dist = flat.Magnitude
			local facing = if dist > 0.1 then look:Dot(flat.Unit) else 1
			if dist < bestDist and facing > -0.1 then
				best, bestDist = guard, dist
			end
		end
	end
	return best
end

-- Thrown knives -----------------------------------------------------------------------------

local function throwAt(guard: Guard, aim: Vector3)
	local hand = guard.Model:FindFirstChild("RightHand") :: BasePart?
	local origin = if hand then hand.Position else guard.Position + Vector3.new(0, 1, 0)
	local flat = Vector3.new(aim.X - origin.X, 0, aim.Z - origin.Z)
	if flat.Magnitude < 0.1 then
		return
	end
	local model = KnifeModel.Build(guard.KnifeName, true)
	KnifeModel.FitLength(model, 2.6)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
		elseif d:IsA("Trail") then
			d.Enabled = true
		end
	end
	model.Parent = projectileFolder
	table.insert(projectiles, {
		Model = model,
		Position = origin,
		Direction = flat.Unit,
		Traveled = 0,
		Damage = guard.Config.Damage,
	})
	Net.Remotes.Effect:FireAllClients("Dash", origin)
end

-- Straight line, hurts the first player it passes; stops at walls
local function stepProjectiles(dt: number)
	local config = GameConfig.GuardThrow
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { projectileFolder, guardFolder }
	for i = #projectiles, 1, -1 do
		local p = projectiles[i]
		local stepLength = config.Speed * dt
		local nextPosition = p.Position + p.Direction * stepLength
		local done = false
		for _, player in Players:GetPlayers() do
			local root = validTarget(player)
			if root then
				local ab = nextPosition - p.Position
				local t = math.clamp((root.Position - p.Position):Dot(ab) / ab:Dot(ab), 0, 1)
				if (root.Position - (p.Position + ab * t)).Magnitude < config.HitRadius + 1 then
					hurtPlayer(player, p.Damage, p.Position)
					done = true
					break
				end
			end
		end
		if not done then
			local hit = workspace:Raycast(p.Position, nextPosition - p.Position, params)
			if hit and not Players:GetPlayerFromCharacter(hit.Instance:FindFirstAncestorOfClass("Model")) then
				done = true
			end
		end
		p.Position = nextPosition
		p.Traveled += stepLength
		if done or p.Traveled > config.MaxRange + 10 then
			p.Model:Destroy()
			table.remove(projectiles, i)
		else
			local spin = p.Traveled * 0.5
			p.Model:PivotTo(CFrame.lookAt(p.Position, p.Position + p.Direction) * CFrame.Angles(-spin, 0, 0))
		end
	end
end

-- Per-frame brain ---------------------------------------------------------------------------

local function face(guard: Guard, point: Vector3)
	local look = Vector3.new(point.X, HEIGHT, point.Z)
	if (look - guard.Position).Magnitude > 0.1 then
		guard.Model:PivotTo(CFrame.lookAt(guard.Position, look))
	end
end

local function step(guard: Guard, dt: number)
	if guard.Dead then
		return
	end
	local arena = MapService.Arena :: MapService.Bounds
	local zone = guard.Zone.Bounds
	local speed = GameConfig.GuardPatrolSpeed
	local now = os.clock()

	-- Drop the target if they left, died, got home, or dragged us too far from our zone
	local targetRoot: BasePart? = nil
	if guard.Target then
		targetRoot = validTarget(guard.Target)
		local leash = GameConfig.ZoneDepth * LEASH
		local tooFar = guard.Position.Z < zone.MinZ - leash or guard.Position.Z > zone.MaxZ + leash
		if not targetRoot or tooFar then
			setTarget(guard, nil)
			targetRoot = nil
		end
	end
	if not guard.Target then
		setTarget(guard, findTarget(guard))
		targetRoot = if guard.Target then validTarget(guard.Target) else nil
	end
	guard.Alert.Enabled = guard.Target ~= nil

	-- Mid-stab or staggered
	if now < guard.BusyUntil then
		if targetRoot then
			face(guard, targetRoot.Position)
		end
		animate(guard, "Idle")
		return
	end

	-- The "!" beat: a fair moment to start running before the chase begins
	if targetRoot and now < guard.AlertUntil then
		face(guard, targetRoot.Position)
		animate(guard, "Idle")
		return
	end

	-- Winding up a throw: stand still facing the target, then let go at where they are *now*
	if guard.WindupUntil > 0 then
		if now < guard.WindupUntil then
			if targetRoot then
				face(guard, targetRoot.Position)
			end
			animate(guard, "Idle")
			return
		end
		guard.WindupUntil = 0
		setKnifeGlow(guard, false)
		guard.Model:SetAttribute("ChargeStart", nil)
		if targetRoot then
			local aim = targetRoot.Position
			Net.Animate(guard.Model, "Throw")
			guard.BusyUntil = now + 0.3
			task.delay(AnimLibrary.Clips.Throw.Release or 0.07, function()
				if not guard.Dead then
					throwAt(guard, aim)
				end
			end)
			return
		end
	end

	local destination: Vector3
	local target = guard.Target
	local lure = guard.Lure
	if lure and (now > guard.LureUntil or not lure.Parent) then
		guard.Lure = nil
		lure = nil
	end
	if lure then
		-- Chasing a Decoy: run at it, and when it's caught it pops
		destination = Vector3.new(lure.Position.X, HEIGHT, lure.Position.Z)
		speed = guard.Config.GuardSpeed
		if (lure.Position - guard.Position).Magnitude <= GameConfig.GuardAttackRange then
			guard.Lure = nil
			Net.Animate(guard.Model, "GuardStab")
			guard.BusyUntil = now + 0.5
			local reached = guard.OnLureReached
			guard.OnLureReached = nil
			if reached then
				reached()
			end
			return
		end
	elseif target and targetRoot then
		destination = Vector3.new(targetRoot.Position.X, HEIGHT, targetRoot.Position.Z)
		speed = guard.Config.GuardSpeed
		local range = (targetRoot.Position - guard.Position).Magnitude
		if range <= GameConfig.GuardAttackRange then
			-- In reach: stab on a cooldown
			face(guard, targetRoot.Position)
			animate(guard, "Idle")
			if now - guard.LastAttack >= GameConfig.GuardAttackCooldown then
				guard.LastAttack = now
				-- Wind up and bring the knife down; it only hurts if you're still in reach on impact
				local clip = AnimLibrary.Clips.GuardStab
				Net.Animate(guard.Model, "GuardStab")
				guard.BusyUntil = now + clip.Length * 0.8
				local model = guard.Model
				task.delay(clip.Impact or 0.3, function()
					if guard.Dead or guard.Model ~= model then
						return
					end
					Net.Remotes.Effect:FireAllClients("Swing", guard.Position)
					local root = validTarget(target)
					if root and (root.Position - guard.Position).Magnitude <= GameConfig.GuardAttackRange + 2 then
						hurtPlayer(target, guard.Config.Damage, guard.Position)
					end
				end)
			end
			return
		end
		local config = GameConfig.GuardThrow
		if
			guard.Config.Throws
			and now >= guard.ThrowReadyAt
			and range > config.MinRange
			and range < config.MaxRange
		then
			guard.WindupUntil = now + config.Windup
			guard.ThrowReadyAt = guard.WindupUntil + config.Cooldown
			setKnifeGlow(guard, true)
			-- Clients crank the arm back over the wind-up
			guard.Model:SetAttribute("ChargeTime", config.Windup)
			guard.Model:SetAttribute("ChargeStart", workspace:GetServerTimeNow())
			return
		end
	else
		if (guard.Wander - guard.Position).Magnitude < 3 then
			guard.Wander = randomPointIn(zone)
		end
		destination = guard.Wander
	end

	local offset = destination - guard.Position
	local distance = offset.Magnitude
	if distance < 0.05 then
		animate(guard, "Idle")
		return
	end
	-- Walk while patrolling, run while chasing; speed the animation up to match the feet
	if speed > GameConfig.GuardPatrolSpeed then
		animate(guard, "Run", speed / 16)
	else
		animate(guard, "Walk", speed / 10)
	end
	local nextPos = guard.Position + offset.Unit * math.min(distance, speed * dt)
	-- Stay inside the arena; the open front edge is where the vaults begin, so stop short of it
	nextPos = Vector3.new(
		math.clamp(nextPos.X, arena.MinX + 2, arena.MaxX - 2),
		HEIGHT,
		math.clamp(nextPos.Z, arena.MinZ + 1, arena.MaxZ - 2)
	)
	-- A Barricade in the way: stop and smash it
	local obstacle = Obstacles.Blocks(guard.Position, nextPos, 1.5)
	if obstacle then
		face(guard, obstacle.Part.Position)
		animate(guard, "Idle")
		if now - guard.LastAttack >= GameConfig.GuardAttackCooldown then
			guard.LastAttack = now
			Net.Animate(guard.Model, "GuardStab")
			guard.BusyUntil = now + 0.6
			task.delay(AnimLibrary.Clips.GuardStab.Impact or 0.3, function()
				if not guard.Dead and obstacle.Part.Parent then
					obstacle.Hit("Guard")
				end
			end)
		end
		return
	end
	guard.Position = nextPos
	guard.Model:PivotTo(CFrame.lookAt(nextPos, nextPos + Vector3.new(offset.X, 0, offset.Z)))
end

-- Spawning ----------------------------------------------------------------------------------

-- Creates a watchman in a zone; `replacing` reuses the slot of one that died
spawnGuard = function(zone: MapService.Zone, config: ZoneConfig, replacing: Guard?)
	local knifeName = randomKnife(config.Rarity)
	local model = buildRig(config.Color, knifeName)
	local position = randomPointIn(zone.Bounds)
	model:PivotTo(CFrame.new(position))
	local head = model:FindFirstChild("Head") :: BasePart
	local bar, fill = healthBar(head)
	local guard: Guard = replacing or ({} :: any)
	guard.Model = model
	guard.Zone = zone
	guard.Config = config
	guard.Position = position
	guard.Wander = randomPointIn(zone.Bounds)
	guard.Target = nil
	guard.AlertUntil = 0
	guard.Alert = head:FindFirstChild("Alert") :: BillboardGui
	guard.HealthBar = bar
	guard.HealthFill = fill
	guard.Health = config.Health
	guard.Dead = false
	guard.KnifeName = knifeName
	guard.Knife = model:FindFirstChild("Knife") :: Model
	guard.LastAttack = 0
	guard.ThrowReadyAt = 0
	guard.WindupUntil = 0
	guard.BusyUntil = 0
	guard.Lure = nil
	guard.LureUntil = 0
	guard.OnLureReached = nil
	guard.Playing = nil
	model.Parent = guardFolder
	guard.Tracks = loadTracks(model)
	guardByModel[model] = guard
	if not replacing then
		table.insert(guards, guard)
	end
end

function GuardService.Init()
	guardFolder = Instance.new("Folder")
	guardFolder.Name = "Guards"
	guardFolder.Parent = workspace:FindFirstChild("Map")
	projectileFolder = Instance.new("Folder")
	projectileFolder.Name = "GuardKnives"
	projectileFolder.Parent = workspace:FindFirstChild("Map")

	-- Work out how high the rig's root sits so feet touch the floor
	local probe = buildRig(Color3.new(), GameConfig.StarterKnife)
	local probeHumanoid = probe:FindFirstChildOfClass("Humanoid") :: Humanoid
	HEIGHT = probeHumanoid.HipHeight + (probe.PrimaryPart :: BasePart).Size.Y / 2
	probe:Destroy()
	nameCursor = rng:NextInteger(0, #GUARD_NAMES - 1)

	for i, config in GameConfig.Zones do
		for _ = 1, config.Guards do
			spawnGuard(MapService.Zones[i], config :: ZoneConfig, nil)
		end
	end

	-- Picking up a knife: every guard in that zone and the next one towards the vaults comes running
	StealService.OnPickup = function(player: Player, zoneIndex: number)
		for _, guard in guards do
			local index = guard.Zone.Index
			if not guard.Dead and index <= zoneIndex and index >= zoneIndex - GameConfig.AlertZonesBehind then
				setTarget(guard, player)
			end
		end
	end

	RunService.Heartbeat:Connect(function(dt)
		for _, guard in guards do
			step(guard, dt)
		end
		stepProjectiles(dt)
	end)
end

return GuardService
