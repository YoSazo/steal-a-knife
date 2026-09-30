--!strict
-- Each player gets a vault: a safe zone with a knife rack that pays cash every second.
-- Also owns character placement and walk speed, since both depend on where the player "lives".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)

local BaseService = {}

local owners: { [number]: Player } = {} -- base index -> player
local baseOf: { [Player]: MapService.BaseSite } = {}
local rackModels: { [Player]: Folder } = {}

local function rackIncome(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	local total = 0
	for i, name in profile.Knives do
		if i > profile.Slots then
			break
		end
		local knife = Knives.ByName[name]
		total += if knife then knife.Income else 0
	end
	return total
end

function BaseService.GetBase(player: Player): MapService.BaseSite?
	return baseOf[player]
end

function BaseService.IsInOwnBase(player: Player, position: Vector3): boolean
	local base = baseOf[player]
	return base ~= nil and MapService.InBounds(base.Bounds, position)
end

function BaseService.IsInAnyBase(position: Vector3): boolean
	for _, base in MapService.Bases do
		if MapService.InBounds(base.Bounds, position, 2) then
			return true
		end
	end
	return false
end

function BaseService.TeleportHome(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local base = baseOf[player]
	character:PivotTo(if base then base.Spawn else MapService.LobbySpawn)
end

-- Single source of truth for walk speed: round > carrying > upgrades
function BaseService.RefreshWalkSpeed(player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local profile = DataService.Get(player)
	local speed = GameConfig.WalkSpeed(if profile then profile.SpeedLevel else 0)
	if player:GetAttribute("InRound") then
		speed = if player:GetAttribute("Role") == "Murderer"
			then GameConfig.MurdererWalkSpeed
			else GameConfig.RoundWalkSpeed
	elseif player:GetAttribute("Carrying") then
		speed *= GameConfig.CarrySpeedMultiplier
	end
	humanoid.WalkSpeed = speed
end

function BaseService.RefreshRack(player: Player)
	local base = baseOf[player]
	local profile = DataService.Get(player)
	if not base or not profile then
		return
	end
	local folder = rackModels[player]
	folder:ClearAllChildren()
	for slot, pad in base.SlotPads do
		local unlocked = slot <= profile.Slots
		pad.Color = if unlocked then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(70, 70, 80)
		pad.Material = if unlocked then Enum.Material.SmoothPlastic else Enum.Material.Slate
		local name = profile.Knives[slot]
		if unlocked and name and Knives.ByName[name] then
			local model = KnifeModel.Build(name, true)
			model:PivotTo(base.SlotCFrames[slot])
			model.Parent = folder
		end
	end
	player:SetAttribute("Income", rackIncome(player))
end

local function claimBase(player: Player)
	for i, base in MapService.Bases do
		if not owners[i] then
			owners[i] = player
			baseOf[player] = base
			base.Sign.Text = `{player.DisplayName}'s Vault`
			local folder = Instance.new("Folder")
			folder.Name = `Rack_{player.Name}`
			folder.Parent = workspace:FindFirstChild("Map")
			rackModels[player] = folder
			BaseService.RefreshRack(player)
			return
		end
	end
	warn(`[BaseService] no free base for {player.Name} - set the place's max players to {MapService.MaxBases}`)
end

local function releaseBase(player: Player)
	local base = baseOf[player]
	if base then
		owners[base.Index] = nil
		base.Sign.Text = "Empty Vault"
		for _, pad in base.SlotPads do
			pad.Color = Color3.fromRGB(70, 70, 80)
		end
	end
	if rackModels[player] then
		rackModels[player]:Destroy()
	end
	baseOf[player] = nil
	rackModels[player] = nil
end

local function onCharacterAdded(player: Player, character: Model)
	character:WaitForChild("HumanoidRootPart")
	task.defer(function()
		if not player:GetAttribute("InRound") then
			BaseService.TeleportHome(player)
		end
		BaseService.RefreshWalkSpeed(player)
	end)
end

function BaseService.Init()
	DataService.PlayerLoaded:Connect(function(player: Player)
		claimBase(player)
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end)
	local function watchCharacters(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end
	Players.PlayerAdded:Connect(watchCharacters)
	for _, player in Players:GetPlayers() do
		watchCharacters(player)
	end
	Players.PlayerRemoving:Connect(releaseBase)
	DataService.Changed:Connect(function(player: Player)
		BaseService.RefreshWalkSpeed(player)
	end)

	-- Pay every rack once a second
	task.spawn(function()
		while true do
			task.wait(1)
			for player in baseOf do
				local income = rackIncome(player)
				if income > 0 then
					DataService.AddCash(player, income)
				end
			end
		end
	end)
end

return BaseService
