--!strict
-- Footsteps you can hear: a soft step at every stride for everyone walking near you (yourself
-- included), picked at random from Config/Sounds.Steps with a little pitch wobble so it never
-- sounds like a loop. Roblox's own "Running" shuffle is muted. Strides get longer the faster you
-- go, so sprinting on a big Speed stat sounds quick, not machine-gun.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local Lod = require(script.Parent.Lod)

local Footsteps = {}

local RANGE = 70 -- only characters this close step out loud
local VOLUME = 0.32

type Walker = { Root: BasePart, Humanoid: Humanoid, Pool: { Sound }, Travelled: number, Last: Vector3 }
local walkers: { [Model]: Walker } = {}
local rng = Random.new()

local function mute(sound: Instance)
	if sound:IsA("Sound") and sound.Name == "Running" then
		sound.Volume = 0
	end
end

local function track(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root or not character.Parent then
		return
	end
	local pool: { Sound } = {}
	for _, id in Sounds.Steps do
		local sound = Instance.new("Sound")
		sound.Name = "Step"
		sound.SoundId = id
		sound.Volume = VOLUME
		sound.RollOffMinDistance = 6
		sound.RollOffMaxDistance = RANGE
		sound.Parent = root
		table.insert(pool, sound)
	end
	for _, d in root:GetChildren() do
		mute(d)
	end
	root.ChildAdded:Connect(mute)
	walkers[character] = { Root = root, Humanoid = humanoid, Pool = pool, Travelled = 0, Last = root.Position }
	character.Destroying:Connect(function()
		walkers[character] = nil
	end)
	humanoid.Died:Connect(function()
		walkers[character] = nil
	end)
end

local function watch(owner: Player)
	owner.CharacterAdded:Connect(track)
	if owner.Character then
		task.spawn(track, owner.Character)
	end
end

function Footsteps.Init()
	for _, owner in Players:GetPlayers() do
		watch(owner)
	end
	Players.PlayerAdded:Connect(watch)
	RunService.Heartbeat:Connect(function()
		for character, walker in walkers do
			if not character.Parent then
				walkers[character] = nil
				continue
			end
			local here = walker.Root.Position
			local moved = Vector3.new(here.X - walker.Last.X, 0, here.Z - walker.Last.Z).Magnitude
			walker.Last = here
			local grounded = walker.Humanoid.FloorMaterial ~= Enum.Material.Air
			-- (teleports and flings aren't steps)
			if not grounded or moved > 8 or not Lod.Near(here, RANGE) then
				walker.Travelled = 0
				continue
			end
			walker.Travelled += moved
			local speed = walker.Root.AssemblyLinearVelocity.Magnitude
			local stride = math.clamp(speed * 0.32, 4.5, 9)
			if walker.Travelled >= stride then
				walker.Travelled = 0
				local sound = walker.Pool[rng:NextInteger(1, #walker.Pool)]
				sound.PlaybackSpeed = rng:NextNumber(0.9, 1.12)
				sound:Play()
			end
		end
	end)
end

return Footsteps
