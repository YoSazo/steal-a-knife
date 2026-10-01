--!strict
-- Server entry point. Order matters: the map exists before anything uses it, and DataService
-- starts loading players last so every service is already listening for PlayerLoaded.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Nobody spawns until the world exists (building it takes a few seconds); CombatService handles
-- respawns after that
Players.CharacterAutoLoads = false

local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local Props = require(ReplicatedStorage.Shared.Props)
local Services = script.Parent.Services
local MapService = require(Services.MapService)
local BaseService = require(Services.BaseService)
local StealService = require(Services.StealService)
local GuardService = require(Services.GuardService)
local UpgradeService = require(Services.UpgradeService)
local InventoryService = require(Services.InventoryService)
local CombatService = require(Services.CombatService)
local PowerService = require(Services.PowerService)
local RaidService = require(Services.RaidService)
local Rewards = require(Services.Rewards)
local RoundService = require(Services.RoundService)
local DataService = require(Services.DataService)
local DebugService = require(Services.DebugService)

KnifeModel.Preload() -- Blender mesh knives, before anything puts a knife in the world
Props.Preload() -- Blender props (skulls, sacks, chandeliers...)
MapService.Init()
BaseService.Init()
StealService.Init()
GuardService.Init()
UpgradeService.Init()
InventoryService.Init()
CombatService.Init()
PowerService.Init()
RaidService.Init()
Rewards.Init()
RoundService.Init()
DebugService.Init()

-- BaseService claims the vault on PlayerLoaded before this deferred initial spawn.
DataService.PlayerLoaded:Connect(function(player: Player)
	task.defer(function()
		if player.Parent and not player.Character then
			player:LoadCharacterAsync()
		end
	end)
end)
DataService.Init()

print("[Steal a Knife] server ready")
