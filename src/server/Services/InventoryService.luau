--!strict
-- The knife menu: pick which owned knife you bring into rounds as the Murderer, and sell knives
-- off the rack to make room for better ones. Clients send a name or a rack index; the server
-- checks ownership against the profile.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local Analytics = require(script.Parent.Analytics)

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
		Net.Notify(player, "That knife is gone", "bad")
		return false
	end
	DataService.Update(player, function(p)
		p.Equipped = name
	end)
	-- The knife flies off its plate into your hand, with a flourish (client Effects "Equipped")
	local base = BaseService.GetBase(player)
	local index = if name ~= "" then table.find(profile.Knives, name) else nil
	local slot = if index then DataService.PlateOf(profile, index) else nil
	local from = if base and slot and base.SlotCFrames[slot] then base.SlotCFrames[slot].Position else nil
	if name ~= "" then
		Net.Remotes.Effect:FireAllClients("Equipped", player, name, from)
		if player.Character then
			Net.Animate(player.Character, "Draw")
		end
	end
	-- (a picked knife gets the big "EQUIPPED" banner with its name and Murderer power from the
	-- Equipped effect above; toasts on top of it were the same words twice more)
	return true
end

local function sell(player: Player, index: unknown): boolean
	local profile = DataService.Get(player)
	if not profile or type(index) ~= "number" or throttled(player) then
		return false
	end
	local name = profile.Knives[index]
	if not name or index % 1 ~= 0 then
		Net.Notify(player, "That knife is gone", "bad")
		return false
	end
	local price = InventoryService.SellPrice(name)
	DataService.CashFlow(player, price, "sell")
	local soldParsed = Items.Parse(name)
	Analytics.Track(player, "knife.sold", {
		knife = Items.Name(name),
		rarity = if soldParsed then soldParsed.Knife.Rarity else nil,
		power = if soldParsed then soldParsed.Perk else nil,
		price = price,
	})
	DataService.Update(player, function(p)
		DataService.RemoveKnife(p, index)
		p.Cash += price
		if p.Equipped == name and not table.find(p.Knives, name) then
			p.Equipped = ""
		end
	end)
	BaseService.RefreshRack(player)
	Net.Notify(player, `Sold {Items.DisplayName(name)} for {Format.Cash(price)}`, "good")
	return true
end

function InventoryService.Init()
	Net.Remotes.Equip.OnServerInvoke = Analytics.Remote("Equip", equip, 1)
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
