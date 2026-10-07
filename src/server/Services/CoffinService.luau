--!strict
-- Coffins: Steal an Egg's egg, in our theme. A stolen boss knife lands on its plate SEALED in a
-- coffin (profile.Sealed) and opens after GameConfig.Coffins.HatchSeconds[rarity] - an appointment
-- that keeps running while you're offline (the "come back and see what you got" pull). While sealed
-- it earns nothing and can't be equipped or sold (BaseService / InventoryService check
-- DataService.IsSealedIndex). The owner can open it now for Robux (product CoffinOpen; the client
-- names the coffin first with Remotes.CoffinTarget). Opening = a burst, the knife on its plate,
-- its power revealed (StealService sets OnOpened).
-- Off unless GameConfig.Coffins.Enabled (Studio: ReplicatedStorage attribute DebugCoffins).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local Format = require(ReplicatedStorage.Shared.Format)
local Net = require(script.Parent.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)
local Analytics = require(script.Parent.Analytics)

local CoffinService = {}
CoffinService.OnOpened = nil :: ((Player, string) -> ())? -- (StealService: reveal its power)

local CONFIG = GameConfig.Coffins
local target: { [Player]: number } = {} -- the coffin the owner asked to open with Robux

function CoffinService.On(_player: Player): boolean
	return CONFIG.Enabled or (RunService:IsStudio() and ReplicatedStorage:GetAttribute("DebugCoffins") == true)
end

-- Seals the knife on `plate` (just deposited). Returns the seconds until it opens.
function CoffinService.Seal(player: Player, plate: number, item: string): number
	local parsed = Items.Parse(item)
	local rarity = if parsed then parsed.Knife.Rarity else "Common"
	local seconds = CONFIG.HatchSeconds[rarity] or 60
	DataService.Update(player, function(p)
		DataService.Seal(p, plate, os.time() + seconds)
	end)
	Analytics.Track(player, "coffin.sealed", { rarity = rarity, seconds = seconds })
	return seconds
end

function CoffinService.Open(player: Player, plate: number, how: string)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local readyAt = DataService.SealedReadyAt(profile, plate)
	local index = DataService.IndexOnPlate(profile, plate)
	if not readyAt or not index then
		return
	end
	local item = profile.Knives[index]
	DataService.Update(player, function(p)
		DataService.Unseal(p, plate)
	end)
	local parsed = Items.Parse(item)
	local rarity = if parsed then parsed.Knife.Rarity else "Common"
	BaseService.RefreshRack(player)
	local base = BaseService.GetBase(player)
	local at = if base and base.SlotCFrames[plate] then base.SlotCFrames[plate].Position else nil
	if at then
		Net.Remotes.Effect:FireAllClients("CoffinOpen", at, Knives.RarityColors[rarity])
	end
	Net.Notify(
		player,
		`🎉 Your coffin opened: {Items.DisplayName(item)}! +{Format.Cash(Items.Income(item))}/s`,
		"good"
	)
	if CoffinService.OnOpened then
		CoffinService.OnOpened(player, item)
	end
	Analytics.Track(player, "coffin.open", {
		rarity = rarity,
		how = how,
		early_s = math.max(0, readyAt - os.time()), -- (> 0 = opened with Robux before its time)
	})
end

-- Robux "Open now" (MonetizationService grants product CoffinOpen): the coffin they picked, else
-- the one with the longest wait left
function CoffinService.OpenNow(player: Player): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end
	local plate: number? = target[player]
	if not plate or not DataService.SealedReadyAt(profile, plate) then
		plate = nil
		local latest = -math.huge
		for _, entry in profile.Sealed do
			if entry.ReadyAt > latest then
				plate, latest = entry.Plate, entry.ReadyAt
			end
		end
	end
	target[player] = nil
	if not plate then
		return false
	end
	CoffinService.Open(player, plate, "robux")
	return true
end

function CoffinService.Init()
	Net.Remotes.CoffinTarget.OnServerEvent:Connect(function(player: Player, plate: unknown)
		if type(plate) == "number" and plate % 1 == 0 then
			target[player] = plate
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		target[player] = nil
	end)
	-- Due coffins open (also the ones that finished while their owner was away, as soon as they're back)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for _, player in Players:GetPlayers() do
				local profile = DataService.Get(player)
				if not profile or #profile.Sealed == 0 or player:GetAttribute("InRound") then
					continue
				end
				for _, entry in table.clone(profile.Sealed) do
					if entry.ReadyAt <= now then
						CoffinService.Open(player, entry.Plate, "timer")
					end
				end
			end
		end
	end)
end

return CoffinService
