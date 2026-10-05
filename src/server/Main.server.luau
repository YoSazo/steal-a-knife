--!strict
-- Server entry point. Order matters: the map exists before anything uses it, and DataService
-- starts loading players last so every service is already listening for PlayerLoaded.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Nobody spawns until the world exists (building it takes a few seconds); CombatService handles
-- respawns after that
Players.CharacterAutoLoads = false
-- MM2-style camera: Classic (it never swings round behind you on its own; Follow yanked the camera
-- after the knife joystick let go) and our own shift lock (client/ShiftLock) instead of Roblox's
local function cameraSettings(player: Player)
	player.DevTouchCameraMode = Enum.DevTouchCameraMovementMode.Classic
	player.DevComputerCameraMode = Enum.DevComputerCameraMovementMode.Classic
	player.DevEnableMouseLock = false
end
Players.PlayerAdded:Connect(cameraSettings)
for _, player in Players:GetPlayers() do
	cameraSettings(player)
end

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
local ShopNPCs = require(Services.ShopNPCs)
local MonetizationService = require(Services.MonetizationService)
local Gamble = require(Services.Gamble)
local RoundService = require(Services.RoundService)
local ServerEvents = require(Services.ServerEvents)
local Social = require(Services.Social)
local TradeService = require(Services.TradeService)
local DataService = require(Services.DataService)
local Analytics = require(Services.Analytics)
local DebugService = require(Services.DebugService)

-- Each step is timed; the summary prints once the server is ready (startup time is how long the
-- first players wait for a character)
local timings: { string } = {}
local startedAt = os.clock()
local function timed(name: string, fn: () -> ())
	local t = os.clock()
	fn()
	table.insert(timings, string.format("%s %.0fms", name, (os.clock() - t) * 1000))
end

-- Blender mesh knives and props download side by side (both before anything uses them): the
-- slowest part of a server start, and the first players are waiting on it
timed("Meshes", function()
	local done = 0
	task.spawn(function()
		KnifeModel.Preload()
		done += 1
	end)
	task.spawn(function()
		Props.Preload()
		done += 1
	end)
	while done < 2 do
		task.wait()
	end
end)
timed("Social", Social.Init)
timed("Events", ServerEvents.Init)
timed("Map", MapService.Init)
timed("Base", BaseService.Init)
timed("Steal", StealService.Init)
timed("Guard", GuardService.Init)
timed("Shells", MapService.BuildBiomeShells) -- after the lairs
timed("Upgrade", UpgradeService.Init)
timed("Inventory", InventoryService.Init)
timed("Combat", CombatService.Init)
timed("Power", PowerService.Init)
timed("Raid", RaidService.Init)
timed("Rewards", Rewards.Init)
timed("Shops", ShopNPCs.Init)
timed("Gamble", Gamble.Init)
timed("Monetization", MonetizationService.Init)
timed("Round", RoundService.Init)
timed("Trade", TradeService.Init)
timed("Debug", DebugService.Init)
timed("Analytics", Analytics.Init) -- before DataService: it listens for PlayerLoaded

-- BaseService claims the vault on PlayerLoaded before this deferred initial spawn.
DataService.PlayerLoaded:Connect(function(player: Player)
	task.defer(function()
		if player.Parent and not player.Character then
			player:LoadCharacterAsync()
		end
	end)
end)
DataService.Init()

print(string.format("[Steal a Knife] server ready in %.1fs (%s)", os.clock() - startedAt, table.concat(timings, ", ")))
