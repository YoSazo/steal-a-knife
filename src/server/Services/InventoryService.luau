--!strict
-- The knife menu: pick which owned knife you bring into rounds as the Murderer, and sell knives
-- off the rack to make room for better ones. Clients send a name or a rack index; the server
-- checks ownership against the profile.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)

local InventoryService = {}

local lastRequest: { [Player]: number } = {}

local function throttled(player: Player): boolean
	local now = os.clock()
	if now - (lastRequest[player] or 0) < 0.3 then
		return true
	end
	lastRequest[player] = now
	return false
end

function InventoryService.SellPrice(item: string): number
	return math.floor(Items.Income(item) * GameConfig.SellSeconds)
end

local function equip(player: Player, name: unknown): boolean
	local profile = DataService.Get(player)
	if not profile or type(name) ~= "string" or throttled(player) then
		return false
	end
	if player:GetAttribute("InRound") then
		Net.Notify(player, "You can't switch knives during a round", "bad")
		return false
	end
	if name ~= "" and not table.find(profile.Knives, name) then
		return false
	end
	DataService.Update(player, function(p)
		p.Equipped = name
	end)
	Net.Notify(
		player,
		if name ~= "" then `{Items.DisplayName(name)} equipped!` else "Auto-equip: your best knife",
		"good"
	)
	return true
end

local function sell(player: Player, index: unknown): boolean
	local profile = DataService.Get(player)
	if not profile or type(index) ~= "number" or throttled(player) then
		return false
	end
	local name = profile.Knives[index]
	if not name or index % 1 ~= 0 then
		return false
	end
	local price = InventoryService.SellPrice(name)
	DataService.Update(player, function(p)
		table.remove(p.Knives, index)
		p.Cash += price
		if p.Equipped == name and not table.find(p.Knives, name) then
			p.Equipped = ""
		end
	end)
	BaseService.RefreshRack(player)
	Net.Notify(player, `Sold {Items.DisplayName(name)} for ${price}`, "good")
	return true
end

function InventoryService.Init()
	Net.Remotes.Equip.OnServerInvoke = equip
	Net.Remotes.Sell.OnServerInvoke = sell
	BaseService.OnSellPrompt = function(player, slot)
		sell(player, slot)
	end
	BaseService.OnEquipPrompt = function(player, name)
		equip(player, name)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return InventoryService
