--!strict
-- Where things are, for the tutorial and the guide (client/Tutorial, client/Guide): your vault, its
-- free plates and cash pads, your wheel, your signs, and each boss's wall. Prompts are kept in an
-- index as they stream in (no scanning the whole map every second).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local player = Players.LocalPlayer
local Places = {}

local stealPrompts: { [ProximityPrompt]: boolean } = {} -- boss wall slots (attribute BossSteal)
local placePrompts: { [ProximityPrompt]: boolean } = {} -- "Place Knife" on vault plates (attribute Place)

local function index(d: Instance)
	if d:IsA("ProximityPrompt") then
		if d:GetAttribute("BossSteal") then
			stealPrompts[d] = true
		elseif d:GetAttribute("Place") then
			placePrompts[d] = true
		end
	end
end
local function unindex(d: Instance)
	if d:IsA("ProximityPrompt") then
		stealPrompts[d] = nil
		placePrompts[d] = nil
	end
end
local started = false
function Places.Init()
	if started then
		return
	end
	started = true
	for _, d in workspace:GetDescendants() do
		index(d)
	end
	workspace.DescendantAdded:Connect(index)
	workspace.DescendantRemoving:Connect(unindex)
end

function Places.Root(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Places.Vault(): Model?
	local index_ = player:GetAttribute("VaultIndex")
	local map = workspace:FindFirstChild("Map")
	local bases = map and map:FindFirstChild("Bases")
	return bases and bases:FindFirstChild(`Base{index_}`) :: Model?
end

function Places.VaultDoor(): Vector3?
	local vault = Places.Vault()
	local floor = vault and vault:FindFirstChild("Floor") :: BasePart?
	return floor and floor.Position
end

-- Just outside your own vault: your vault's spawn spot (BaseService's VaultSpawn<n>)
function Places.HomeSpot(): Vector3?
	local i = player:GetAttribute("VaultIndex")
	local map = workspace:FindFirstChild("Map")
	local spawnPad = map and type(i) == "number" and map:FindFirstChild(`VaultSpawn{i}`) :: BasePart?
	return if spawnPad then spawnPad.Position + Vector3.new(0, 3, 0) else Places.VaultDoor()
end

-- Inside your vault? (its floor's footprint, any storey)
function Places.InVault(at: Vector3): boolean
	local vault = Places.Vault()
	local floor = vault and vault:FindFirstChild("Floor") :: BasePart?
	if not floor then
		return false
	end
	local offset = floor.CFrame:PointToObjectSpace(at)
	return math.abs(offset.X) <= floor.Size.X / 2 + 1 and math.abs(offset.Z) <= floor.Size.Z / 2 + 1
end

-- A cash pad with money waiting on it (its pill shows a number), else the vault
function Places.CashPad(): Vector3?
	local vault = Places.Vault()
	if not vault then
		return nil
	end
	for _, d in vault:GetDescendants() do
		if d:IsA("BasePart") and d.Name:match("^CashPadArt%d+$") then
			for _, label in d:GetDescendants() do
				if label:IsA("TextLabel") and label.Text ~= "" and label.Text:find("%$") then
					return d.Position
				end
			end
		end
	end
	return Places.VaultDoor()
end

function Places.Wheel(): Vector3?
	local vault = Places.Vault()
	local plate = vault and vault:FindFirstChild("WheelFloor") :: BasePart?
	return plate and plate.Position
end

-- Your Bigger Vault ("UpgradeSign") or Faster Wheel ("WheelUpgradeSign") sign
function Places.Sign(name: string): Vector3?
	local vault = Places.Vault()
	local sign = vault and vault:FindFirstChild(name)
	if sign and sign:IsA("Model") then
		return sign:GetPivot().Position
	elseif sign and sign:IsA("BasePart") then
		return sign.Position
	end
	return nil
end

-- Your first free plate: its "Place Knife" prompt is on while you carry a knife. Returns the
-- plate's glowing model (to light up) and where to point. Lowest floor, nearest the door.
function Places.FreePlate(): (Instance?, Vector3?)
	local vault = Places.Vault()
	if not vault then
		return nil, nil
	end
	local best: BasePart? = nil
	local home = Places.HomeSpot()
	for prompt in placePrompts do
		if prompt.Parent and prompt.Enabled and prompt:GetAttribute("Owner") == player.UserId then
			local pad = prompt.Parent
			if pad and pad:IsA("BasePart") then
				if
					not best
					or pad.Position.Y < best.Position.Y - 2
					or (
						math.abs(pad.Position.Y - best.Position.Y) <= 2
						and home
						and (pad.Position - home).Magnitude < (best.Position - home).Magnitude
					)
				then
					best = pad
				end
			end
		end
	end
	if not best then
		return nil, nil
	end
	local plate: Instance? = nil
	local closest = 6
	for _, model in vault:GetDescendants() do
		if model:IsA("Model") and model.Name:match("^PlateDetails%d+$") then
			local distance = (model:GetPivot().Position - best.Position).Magnitude
			if distance < closest then
				plate, closest = model, distance
			end
		end
	end
	return plate or best, best.Position
end

-- The spot in front of a boss's wall, on the runway side (the tutorial's glowing ring)
function Places.LairSpot(zone: number): Vector3
	local lair = GameConfig.BossLairCenter(zone)
	local inward = if lair.X < 0 then 1 else -1 -- toward the middle of the runway
	return lair + Vector3.new(inward * (GameConfig.BossLair.Depth / 2 + 7), 0, 0)
end

-- A stocked knife on that boss's wall (its Steal prompt is on), nearest the ring. `notMiddle`: never
-- the slot in the middle that the boss stands in front of.
function Places.LairKnife(zone: number, notMiddle: boolean?): BasePart?
	local spot = Places.LairSpot(zone)
	local lair = GameConfig.BossLairCenter(zone)
	local best, bestDistance = nil, 60
	for prompt in stealPrompts do
		if prompt.Parent and prompt.Enabled then
			local pad = prompt.Parent
			if pad and pad:IsA("BasePart") and (not notMiddle or math.abs(pad.Position.Z - lair.Z) > 6) then
				local distance = (pad.Position - spot).Magnitude
				if distance < bestDistance then
					best, bestDistance = pad, distance
				end
			end
		end
	end
	return best
end

-- How many knives are on that boss's wall right now (server GuardService: Lair<zone> Stocked);
-- nil if that lair hasn't streamed in yet
function Places.Stocked(zone: number): number?
	local map = workspace:FindFirstChild("Map")
	local guards = map and map:FindFirstChild("Guards")
	local lair = guards and guards:FindFirstChild(`Lair{zone}`)
	local stocked = lair and lair:GetAttribute("Stocked")
	return if type(stocked) == "number" then stocked else nil
end

-- The floating knife over a wall slot (the server's display model, tagged Spin)
function Places.KnifeOver(pad: BasePart): Instance?
	for _, model in CollectionService:GetTagged("Spin") do
		if model:IsA("Model") then
			local at = model:GetPivot().Position
			if math.abs(at.X - pad.Position.X) < 3 and math.abs(at.Z - pad.Position.Z) < 3 then
				return model
			end
		end
	end
	return pad.Parent
end

-- Your surprise gift, if one is waiting (server SurpriseGifts: tag SurpriseGift, Owner)
function Places.Gift(): Vector3?
	for _, gift in CollectionService:GetTagged("SurpriseGift") do
		if gift:GetAttribute("Owner") == player.UserId then
			if gift:IsA("Model") then
				return gift:GetPivot().Position
			elseif gift:IsA("BasePart") then
				return gift.Position
			end
		end
	end
	return nil
end

-- Where to aim the arrows on the way to `target`: into your vault through its gate (the outside
-- spot first), otherwise straight there
function Places.Aim(from: Vector3, target: Vector3): Vector3
	if Places.InVault(target) and not Places.InVault(from) then
		local home = Places.HomeSpot()
		if home and (Vector3.new(from.X, 0, from.Z) - Vector3.new(home.X, 0, home.Z)).Magnitude > 6 then
			return home
		end
	end
	return target
end

return Places
