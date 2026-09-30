--!strict
-- Server entry point. Order matters: the map exists before anything uses it, and DataService
-- starts loading players last so every service is already listening for PlayerLoaded.

local Services = script.Parent.Services
local MapService = require(Services.MapService)
local BaseService = require(Services.BaseService)
local StealService = require(Services.StealService)
local GuardService = require(Services.GuardService)
local UpgradeService = require(Services.UpgradeService)
local RoundService = require(Services.RoundService)
local DataService = require(Services.DataService)

MapService.Init()
BaseService.Init()
StealService.Init()
GuardService.Init()
UpgradeService.Init()
RoundService.Init()
DataService.Init()

print("[Steal a Knife] server ready")
