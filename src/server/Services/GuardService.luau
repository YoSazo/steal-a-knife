--!strict
-- NPC guards. They wander their zone and chase anyone carrying a knife. Moved by the server
-- (anchored, no physics) so exploiters can't fling or push them. Deeper zones = faster guards,
-- which is what the Speed upgrade is for. Guards never enter bases, which are safe zones.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local BaseService = require(script.Parent.BaseService)
local MapService = require(script.Parent.MapService)
local StealService = require(script.Parent.StealService)

type Guard = {
	Model: Model,
	Zone: MapService.Zone,
	Speed: number,
	Detect: number,
	Position: Vector3,
	Home: Vector3,
	Wander: Vector3,
	Target: Player?,
}

local GuardService = {}

local HEIGHT = 2.5 -- body center above the floor
local LEASH = 1.5 -- how many zone-depths a guard will chase away from its zone
local guards: { Guard } = {}
local rng = Random.new()

local function buildGuardModel(color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "Guard"
	local function piece(name: string, size: Vector3, offset: Vector3, c: Color3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = CFrame.new(offset)
		p.Color = c
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local body = piece("Body", Vector3.new(3, 3.4, 2), Vector3.zero, color)
	piece("Head", Vector3.new(2.4, 2.2, 2.2), Vector3.new(0, 2.9, 0), Color3.fromRGB(255, 220, 170))
	piece("Hat", Vector3.new(2.8, 0.8, 2.6), Vector3.new(0, 4.3, 0), Color3.fromRGB(30, 40, 80))
	piece("Badge", Vector3.new(0.6, 0.6, 0.2), Vector3.new(0.7, 0.8, -1.05), Color3.fromRGB(255, 215, 0))
	piece("EyeL", Vector3.new(0.4, 0.5, 0.2), Vector3.new(-0.5, 3.1, -1.1), Color3.new(0, 0, 0))
	piece("EyeR", Vector3.new(0.4, 0.5, 0.2), Vector3.new(0.5, 3.1, -1.1), Color3.new(0, 0, 0))
	piece("LegL", Vector3.new(1.2, 1.6, 1.4), Vector3.new(-0.8, -2.4, 0), Color3.fromRGB(30, 40, 80))
	piece("LegR", Vector3.new(1.2, 1.6, 1.4), Vector3.new(0.8, -2.4, 0), Color3.fromRGB(30, 40, 80))
	model.PrimaryPart = body
	return model
end

local function randomPointIn(b: MapService.Bounds): Vector3
	return Vector3.new(rng:NextNumber(b.MinX + 8, b.MaxX - 8), HEIGHT, rng:NextNumber(b.MinZ + 8, b.MaxZ - 8))
end

local function findTarget(guard: Guard, carriers: { [Player]: any }): Player?
	local best, bestDist = nil, guard.Detect
	for player in carriers do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local dist = (root.Position - guard.Position).Magnitude
			if dist < bestDist then
				best, bestDist = player, dist
			end
		end
	end
	return best
end

local function step(guard: Guard, dt: number, carriers: { [Player]: any })
	local arena = MapService.Arena :: MapService.Bounds
	local destination: Vector3
	local speed = GameConfig.GuardPatrolSpeed

	-- Drop the target if they stopped carrying, got home, or dragged us too far from our zone
	local target = guard.Target
	local targetRoot: BasePart? = nil
	if target then
		local character = target.Character
		targetRoot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local tooFar = (guard.Position - guard.Home).Magnitude > GameConfig.ZoneDepth * LEASH
		if not carriers[target] or not targetRoot or tooFar or BaseService.IsInAnyBase(targetRoot.Position) then
			guard.Target = nil
			targetRoot = nil
		end
	end
	if not guard.Target then
		guard.Target = findTarget(guard, carriers)
		local character = guard.Target and guard.Target.Character
		targetRoot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	end

	if guard.Target and targetRoot then
		destination = Vector3.new(targetRoot.Position.X, HEIGHT, targetRoot.Position.Z)
		speed = guard.Speed
		if (targetRoot.Position - guard.Position).Magnitude <= GameConfig.CatchRadius then
			StealService.Catch(guard.Target)
			guard.Target = nil
			return
		end
	else
		if (guard.Wander - guard.Position).Magnitude < 3 then
			guard.Wander = randomPointIn(guard.Zone.Bounds)
		end
		destination = guard.Wander
	end

	local offset = destination - guard.Position
	local distance = offset.Magnitude
	if distance < 0.05 then
		return
	end
	local move = offset.Unit * math.min(distance, speed * dt)
	local nextPos = guard.Position + move
	-- Stay inside the arena walls; the open front edge is where bases begin, so stop short of it
	nextPos = Vector3.new(
		math.clamp(nextPos.X, arena.MinX + 2, arena.MaxX - 2),
		HEIGHT,
		math.clamp(nextPos.Z, arena.MinZ - 6, arena.MaxZ - 2)
	)
	guard.Position = nextPos
	guard.Model:PivotTo(CFrame.lookAt(nextPos, nextPos + Vector3.new(offset.X, 0, offset.Z)))
end

function GuardService.Init()
	local folder = Instance.new("Folder")
	folder.Name = "Guards"
	folder.Parent = workspace:FindFirstChild("Map")

	for i, zoneConfig in GameConfig.Zones do
		local zone = MapService.Zones[i]
		for _ = 1, zoneConfig.Guards do
			local spawn = randomPointIn(zone.Bounds)
			local model = buildGuardModel(zoneConfig.Color:Lerp(Color3.new(0, 0, 0), 0.25))
			model:PivotTo(CFrame.new(spawn))
			model.Parent = folder
			table.insert(guards, {
				Model = model,
				Zone = zone,
				Speed = zoneConfig.GuardSpeed,
				Detect = zoneConfig.Detect,
				Position = spawn,
				Home = Vector3.new(0, HEIGHT, (zone.Bounds.MinZ + zone.Bounds.MaxZ) / 2),
				Wander = randomPointIn(zone.Bounds),
				Target = nil,
			})
		end
	end

	RunService.Heartbeat:Connect(function(dt)
		local carriers = StealService.GetCarriers()
		for _, guard in guards do
			step(guard, dt, carriers)
		end
	end)
end

return GuardService
