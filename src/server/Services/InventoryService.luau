--!strict
-- The knife menu: pick which owned knife you bring into rounds as the Murderer, and sell knives
-- off the rack to make room for better ones. Clients send a name or a rack index; the server
-- checks ownership against the profile. Also publishes the Murderer power on the knife you fight
-- with (player attributes PowerId / FightingKnife / PowerName: knife cards, the tutorial's showcase).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local KnifePowers = require(ReplicatedStorage.Shared.Config.KnifePowers)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local Analytics = require(script.Parent.Analytics)
local Fuel = require(script.Parent.Fuel)

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
	if name ~= "" then
		local usable = false
		for i, item in profile.Knives do
			if item == name and not DataService.IsSealedIndex(profile, i) then
				usable = true
			end
		end
		if not usable then
			Net.Notify(player, "It's still in its coffin!", "bad")
			return false
		end
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
	if DataService.IsSealedIndex(profile, index) then
		Net.Notify(player, "It's still in its coffin!", "bad")
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

-- The power on the knife you fight with (the Murderer side in rounds) and its level
local function publishKnifePower(player: Player)
	local profile = DataService.Get(player)
	local item = BaseService.ProtectedItem(player)
	local parsed = item and Items.Parse(item)
	local id = parsed and parsed.Perk
	local entry = id and KnifePowers.ById[id]
	local xp = if profile and id then profile.PowerXP[id] or 0 else 0
	local function set(name: string, value: any)
		if player:GetAttribute(name) ~= value then
			player:SetAttribute(name, value)
		end
	end
	set("PowerId", id)
	set("FightingKnife", item)
	set("PowerName", if entry then entry.Name else nil)
	set("PowerLevel", GameConfig.PowerLevelFor(xp))
	set("PowerXP", xp)
end

-- Old saves: Innocent Powers were once bought with cash (and later cut). That cash comes back once.
-- (their prices, frozen here: cost x 8^level per level, and the third loadout slot)
local OLD_POWER_COSTS: { [string]: number } = {
	Vanish = 150000,
	Radar = 25000,
	Trap = 900000,
	Shield = 6000000,
	Decoy = 250000000,
	Flash = 40000000,
	Barricade = 2000000000,
	Mimic = 15000000000,
}
local function refundOldPowers(player: Player, profile: DataService.Profile)
	if table.find(profile.Bought, "PowerRefund") then
		return
	end
	local refund = 0
	for id, level in profile.Powers do
		local cost = OLD_POWER_COSTS[id]
		if cost then
			for l = 0, level - 1 do
				refund += cost * 8 ^ l
			end
		end
	end
	refund += math.max(0, profile.PowerSlots - 2) * 25000000
	DataService.CashFlow(player, refund, "power_refund")
	DataService.Update(player, function(p)
		table.insert(p.Bought, "PowerRefund")
		p.Powers = {}
		p.Loadout = {}
		p.Cash += refund
	end)
	if refund > 0 then
		task.delay(8, function()
			if player.Parent then
				Net.Notify(player, `Old powers refunded: +{Format.Cash(refund)}!`, "good")
			end
		end)
	end
end
InventoryService.DebugRefund = refundOldPowers

function InventoryService.Init()
	DataService.PlayerLoaded:Connect(function(player: Player, profile: DataService.Profile)
		refundOldPowers(player, profile)
		Fuel.EnsurePowers(player)
		publishKnifePower(player)
	end)
	DataService.Changed:Connect(function(player: Player)
		publishKnifePower(player)
	end)
	local function watch(player: Player)
		-- (leaving a round can change the knife you fight with)
		player:GetAttributeChangedSignal("InRound"):Connect(function()
			if not player:GetAttribute("InRound") then
				publishKnifePower(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
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
