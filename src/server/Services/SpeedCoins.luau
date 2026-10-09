--!strict
-- The same +1 Speed Blender token in every biome and along the safe hub walkways.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Coin = require(ReplicatedStorage.Shared.SpeedCoinModel)
local MapService = require(script.Parent.MapService)
local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)
local Net = require(script.Parent.Parent.Remotes)
local SpeedCoins = {}
local folder: Folder
local rng = Random.new()
local lastPickup: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local function spawn(at: Vector3)
	local model, hitbox = Coin.Build(CFrame.new(at), false)
	model:AddTag("Coin")
	model.Parent = folder
	local taken = false
	hitbox.Touched:Connect(function(other: BasePart)
		local player = Players:GetPlayerFromCharacter(other.Parent)
		local character = player and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if
			taken
			or not player
			or not root
			or not humanoid
			or humanoid.Health <= 0
			or player:GetAttribute("InRound")
			or ((player:GetAttribute("RunResumeAt") or 0) :: number) > workspace:GetServerTimeNow()
			or (root.Position - hitbox.Position).Magnitude > 6
			or not DataService.Get(player)
			or os.clock() - (lastPickup[player] or 0) < 0.15
		then
			return
		end
		taken = true
		lastPickup[player] = os.clock()
		DataService.Update(player, function(profile)
			profile.Speed += 1
		end)
		BaseService.RefreshWalkSpeed(player)
		Net.Remotes.Effect:FireClient(player, "SpeedPickup", hitbox.Position)
		model:Destroy()
		task.delay(12, function()
			if folder.Parent then
				spawn(at)
			end
		end)
	end)
end
function SpeedCoins.Init()
	folder = Instance.new("Folder")
	folder.Name, folder.Parent = "SpeedCoins", workspace:FindFirstChild("Map")
	local points: { Vector3 } = {}
	local function add(at: Vector3): boolean
		for _, previous in points do
			if (previous - at).Magnitude < 6.5 then
				return false
			end
		end
		table.insert(points, at)
		spawn(at)
		return true
	end
	-- Scatter them across the usable walkway rather than placing perfect rows.
	local hubCount = 0
	for _ = 1, 600 do
		if hubCount >= 40 then
			break
		end
		local z = rng:NextNumber(-83, -18)
		local x = rng:NextNumber(if z > -62 then -12 else -100, if z > -62 then 12 else 100)
		local at = Vector3.new(x, 2.3, z)
		local clear = (Vector2.new(x, z) - Vector2.new(-12, -72)).Magnitude > 8
		for _, base in MapService.Bases do
			local gate = (base.Frame * CFrame.new(0, 0, GameConfig.Pens.Depth / 2 + 8)).Position
			if (Vector2.new(x, z) - Vector2.new(gate.X, gate.Z)).Magnitude < 7 then
				clear = false
			end
		end
		if clear and add(at) then
			hubCount += 1
		end
	end
	for i, zone in MapService.Zones do
		local bounds = zone.Bounds
		local lair = GameConfig.BossLairCenter(i)
		for _ = 1, 26 do
			for _ = 1, 80 do
				local at = Vector3.new(rng:NextNumber(-58, 58), 2.3, rng:NextNumber(bounds.MinZ + 8, bounds.MaxZ - 8))
				if
					math.abs(at.X - lair.X) > GameConfig.BossLair.Depth / 2 + 8
					or math.abs(at.Z - lair.Z) > GameConfig.BossLair.Width / 2 + 8
				then
					if add(at) then
						break
					end
				end
			end
		end
	end
end
return SpeedCoins
