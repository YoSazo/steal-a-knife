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
local CoffinService = require(Services.CoffinService)
local PenPrototype = require(Services.PenPrototype)
local GuardService = require(Services.GuardService)
local UpgradeService = require(Services.UpgradeService)
local InventoryService = require(Services.InventoryService)
local CombatService = require(Services.CombatService)
local PowerService = require(Services.PowerService)
local RaidService = require(Services.RaidService)
local Rewards = require(Services.Rewards)
local NotifyService = require(Services.NotifyService)
local ShopNPCs = require(Services.ShopNPCs)
local MapVote = require(Services.MapVote)
local MonetizationService = require(Services.MonetizationService)
local Gamble = require(Services.Gamble)
local SurpriseGifts = require(Services.SurpriseGifts)
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

-- (Knives build on demand and Blender props stream in behind: neither holds up the first spawn)
timed("Meshes", function()
	KnifeModel.Preload()
	task.spawn(Props.Preload)
end)
timed("Social", Social.Init)
timed("Events", ServerEvents.Init)
timed("Map", MapService.Init)
timed("Base", BaseService.Init)
timed("Steal", StealService.Init)
timed("Coffins", CoffinService.Init)
timed("PenPrototype", PenPrototype.Init)
-- The bosses and the biome art are out in the arena, far from the vaults: they build while the
-- first players are already spawning (a fresh server used to make everyone wait for them)
task.spawn(function()
	local t = os.clock()
	Props.WaitReady(5) -- the bosses wear Blender hair and hats (Frank is the tutorial's first stop: not long)
	GuardService.Init()
	local guards = os.clock() - t
	MapService.BuildBiomeShells() -- after the lairs
	print(
		string.format(
			"[Steal and Murder] bosses %.1fs, biomes %.1fs (built after spawning)",
			guards,
			os.clock() - t - guards
		)
	)
end)
timed("Upgrade", UpgradeService.Init)
timed("Inventory", InventoryService.Init)
timed("Combat", CombatService.Init)
timed("Power", PowerService.Init)
timed("Raid", RaidService.Init)
timed("Rewards", Rewards.Init)
timed("Shops", ShopNPCs.Init)
timed("MapVote", MapVote.Init)
timed("Gamble", Gamble.Init)
timed("Gifts", SurpriseGifts.Init)
timed("Notify", NotifyService.Init)
timed("Monetization", MonetizationService.Init)
timed("Round", RoundService.Init)
timed("Trade", TradeService.Init)
timed("Debug", DebugService.Init)
timed("Analytics", Analytics.Init) -- before DataService: it listens for PlayerLoaded

-- BaseService claims the vault on PlayerLoaded before this deferred initial spawn.
DataService.PlayerLoaded:Connect(function(player: Player)
	task.defer(function()
		if player.Parent and not player.Character then
			BaseService.LoadCharacter(player) -- (streams the vault in first)
		end
	end)
end)
DataService.Init()

print(
	string.format("[Steal and Murder] server ready in %.1fs (%s)", os.clock() - startedAt, table.concat(timings, ", "))
)
