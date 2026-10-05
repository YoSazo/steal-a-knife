--!strict
-- The gambling layer, all with odds shown and all earnable for free:
--   * Lucky Wheel: one free spin a day + one per GameConfig.Spin.EarnEvery of play; Robux spin packs
--   * Luck potions: 2x case / lucky block luck for a while (profile.LuckUntil, player attr LuckUntil)
--   * Cash Lucky Blocks: Items.LuckyBlocks bought with in-game cash (GameConfig.LuckyBlockCash)
--   * Mystery Merchant: every GameConfig.Merchant.Rotation seconds a new stock of discounted cases
--     and blocks, sized to your income, each buyable once (a real rotation: the timer never lies)
--   * Gifts: pick a player (Remotes.Gamble "GiftTarget"), then buy a Gift product for them
-- Remotes.Gamble(action, ...) -> (ok, message, extra)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local StealService = require(script.Parent.StealService)
local Analytics = require(script.Parent.Analytics)

local Gamble = {}

local rng = Random.new()
local giftTargets: { [Player]: number } = {}

-- Luck --------------------------------------------------------------------------------------------

-- Extra case / lucky block luck from potions and the Luck pass (StealService.caseLuck multiplies it)
function Gamble.LuckMultiplier(player: Player, profile: DataService.Profile): number
	local luck = 1
	if profile.LuckUntil > os.time() then
		luck *= GameConfig.LuckPotion.Multiplier
	end
	if player:GetAttribute("Pass_Luck") == true then
		luck *= 2
	end
	return luck
end

function Gamble.AddLuck(player: Player, seconds: number)
	DataService.Update(player, function(p)
		p.LuckUntil = math.max(p.LuckUntil, os.time()) + seconds
	end)
	local profile = DataService.Get(player)
	if profile then
		player:SetAttribute("LuckUntil", profile.LuckUntil)
	end
end

local function syncSpins(player: Player, profile: DataService.Profile)
	player:SetAttribute("Spins", profile.Spins)
	player:SetAttribute("FreeSpinDay", profile.FreeSpinDay)
	player:SetAttribute("LuckUntil", profile.LuckUntil)
end

function Gamble.AddSpins(player: Player, count: number)
	DataService.Update(player, function(p)
		p.Spins += count
	end)
	local profile = DataService.Get(player)
	if profile then
		syncSpins(player, profile)
	end
end

-- Lucky Wheel -------------------------------------------------------------------------------------

local function today(): number
	return os.time() // 86400
end

local function spin(player: Player): (boolean, string, number?)
	local profile = DataService.Get(player)
	if not profile then
		return false, "Not loaded yet"
	end
	if player:GetAttribute("InRound") then
		return false, "Not during a round!"
	end
	local free = profile.FreeSpinDay ~= today()
	if not free and profile.Spins <= 0 then
		return false, "No spins left - earn one by playing, or get more in the Store"
	end
	DataService.Update(player, function(p)
		if free then
			p.FreeSpinDay = today()
		else
			p.Spins -= 1
		end
	end)
	-- Pick the prize
	local prizes = GameConfig.Spin.Prizes
	local total = 0
	for _, prize in prizes do
		total += prize.Weight
	end
	local roll = rng:NextNumber() * total
	local index = #prizes
	for i, prize in prizes do
		roll -= prize.Weight
		if roll <= 0 then
			index = i
			break
		end
	end
	local prize = prizes[index]
	-- Pay out once the wheel has stopped on the client
	task.delay(GameConfig.Spin.RevealDelay, function()
		if not player.Parent then
			return
		end
		if prize.Kind == "Cash" then
			local cash = GameConfig.Pay({ Min = 5000, Seconds = prize.Seconds }, BaseService.RackIncome(player))
			DataService.AddCash(player, cash, "wheel")
			Net.Remotes.Effect:FireClient(player, "CashBurst", nil, cash)
			Net.Notify(player, `Lucky Wheel: +{Format.Cash(cash)}!`, "good")
		elseif prize.Kind == "Luck" then
			Gamble.AddLuck(player, prize.Seconds)
			Net.Notify(player, `Lucky Wheel: 2x Luck for {prize.Seconds // 60} minutes!`, "good")
		elseif prize.Kind == "Spin" then
			Gamble.AddSpins(player, prize.Count)
			Net.Notify(player, `Lucky Wheel: +{prize.Count} spins!`, "good")
		elseif prize.Kind == "Case" or prize.Kind == "Lucky" then
			if not StealService.OpenCase(player, prize.Tier, false, prize.Kind == "Lucky") then
				local cash = GameConfig.Pay({ Min = 20000, Seconds = 600 }, BaseService.RackIncome(player))
				DataService.AddCash(player, cash, "wheel")
				Net.Notify(player, `Your wall is full - +{Format.Cash(cash)} instead`, "good")
			end
		end
		local after = DataService.Get(player)
		if after then
			syncSpins(player, after)
		end
	end)
	syncSpins(player, profile)
	return true, if free then "Free daily spin!" else "Spinning...", index
end

-- Cash Lucky Blocks -------------------------------------------------------------------------------

local function buyLuckyBlock(player: Player, tier: unknown): (boolean, string)
	local cost: number? = if type(tier) == "string" then GameConfig.LuckyBlockCash[tier] else nil
	local profile = DataService.Get(player)
	if not cost or not profile or not Items.LuckyBlocks[tier :: string] then
		return false, "Unknown block"
	end
	if player:GetAttribute("InRound") then
		return false, "Not during a round!"
	end
	if #profile.Knives >= profile.Slots then
		return false, "Your wall is full! Sell a knife first."
	end
	if Knives.Rank(tier :: string) > Knives.Rank(GameConfig.RarityReached(profile.Speed)) then
		return false, `Reach the {tier} biome first (train your Speed)!`
	end
	if not DataService.TrySpend(player, cost :: number, "lucky_block") then
		return false, "Not enough cash"
	end
	StealService.OpenCase(player, tier :: string, false, true)
	return true, ""
end

-- Mystery Merchant --------------------------------------------------------------------------------

export type Offer = { Kind: string, Tier: string, Price: number, Full: number, Discount: number }

local function rotation(): (number, number)
	local period = GameConfig.Merchant.Rotation
	local now = os.time()
	return now // period, (now // period + 1) * period
end

-- This rotation's stock for a player: tiers around what they earn, so it's always tempting
function Gamble.MerchantStock(player: Player): { Offer }
	local index = rotation()
	local income = math.max(1, BaseService.RackIncome(player))
	local seeded = Random.new(index * 7919 + player.UserId % 100000)
	local stock: { Offer } = {}
	for slot = 1, GameConfig.Merchant.Slots do
		local lucky = seeded:NextNumber() < 0.5
		local catalog: { [string]: number } = {}
		if lucky then
			catalog = GameConfig.LuckyBlockCash
		else
			for _, entry in GameConfig.CaseShop do
				catalog[entry.Rarity] = entry.Cost
			end
		end
		-- The priciest tier that's within ~MaxMinutes of income (at least the cheapest)
		local best, bestCost = nil :: string?, 0
		local cheapest, cheapestCost = nil :: string?, math.huge
		local reach = income * 60 * GameConfig.Merchant.MaxMinutes * (0.4 + 0.3 * slot)
		for tier, cost in catalog do
			if cost <= reach and cost > bestCost then
				best, bestCost = tier, cost
			end
			if cost < cheapestCost then
				cheapest, cheapestCost = tier, cost
			end
		end
		local tier = best or cheapest :: string
		local full = catalog[tier]
		local discount = seeded:NextInteger(GameConfig.Merchant.MinDiscount, GameConfig.Merchant.MaxDiscount)
		table.insert(stock, {
			Kind = if lucky then "Lucky" else "Case",
			Tier = tier,
			Full = full,
			Discount = discount,
			Price = math.floor(full * (100 - discount) / 100),
		})
	end
	return stock
end

local function merchantInfo(player: Player): any
	local index, endsAt = rotation()
	local profile = DataService.Get(player)
	local bought = {}
	for slot = 1, GameConfig.Merchant.Slots do
		bought[slot] = profile ~= nil and table.find(profile.MerchantBought, `{index}:{slot}`) ~= nil
	end
	return { Stock = Gamble.MerchantStock(player), EndsAt = endsAt, Bought = bought }
end

local function buyMerchant(player: Player, slot: unknown): (boolean, string)
	local index = rotation()
	local profile = DataService.Get(player)
	local stock = Gamble.MerchantStock(player)
	if type(slot) ~= "number" or not profile or not stock[slot] then
		return false, "Gone!"
	end
	local key = `{index}:{slot}`
	if table.find(profile.MerchantBought, key) then
		return false, "Sold out - new stock soon"
	end
	if #profile.Knives >= profile.Slots then
		return false, "Your wall is full! Sell a knife first."
	end
	local offer = stock[slot]
	if not DataService.TrySpend(player, offer.Price, "merchant") then
		return false, "Not enough cash"
	end
	DataService.Update(player, function(p)
		-- Only this rotation's purchases matter
		local kept = {}
		for _, k in p.MerchantBought do
			if k:match("^(%d+):") == tostring(index) then
				table.insert(kept, k)
			end
		end
		table.insert(kept, key)
		p.MerchantBought = kept
	end)
	StealService.OpenCase(player, offer.Tier, false, offer.Kind == "Lucky")
	return true, ""
end

-- Gifts -------------------------------------------------------------------------------------------

function Gamble.GiftTarget(buyer: Player): Player?
	local id = giftTargets[buyer]
	local target = id and Players:GetPlayerByUserId(id)
	return if target and target ~= buyer then target else nil
end

-- Setup -------------------------------------------------------------------------------------------

function Gamble.Init()
	StealService.LuckMultiplier = Gamble.LuckMultiplier
	local handle: (Player, unknown, unknown) -> (any, any, any)
	Net.Remotes.Gamble.OnServerInvoke = Analytics.Remote(
		"Gamble",
		function(player: Player, action: unknown, arg: unknown): any
			local ok, message, extra = handle(player, action, arg)
			if ok == false and type(message) == "string" and message ~= "" then
				Net.Notify(player, message, "bad")
			end
			return ok, message, extra
		end,
		1
	)
	handle = function(player: Player, action: unknown, arg: unknown): (any, any, any)
		if action == "Spin" then
			return spin(player)
		elseif action == "LuckyBlock" then
			return buyLuckyBlock(player, arg)
		elseif action == "Merchant" then
			return true, "", merchantInfo(player)
		elseif action == "BuyMerchant" then
			return buyMerchant(player, arg)
		elseif action == "GiftTarget" then
			if type(arg) == "number" and Players:GetPlayerByUserId(arg) then
				giftTargets[player] = arg
				return true, ""
			end
			return false, "They're not in this server"
		end
		return false, "?"
	end
	DataService.PlayerLoaded:Connect(function(player: Player, profile: DataService.Profile)
		syncSpins(player, profile)
	end)
	Players.PlayerRemoving:Connect(function(player)
		giftTargets[player] = nil
	end)
	-- Spins earned by playing
	task.spawn(function()
		local played: { [Player]: number } = {}
		while true do
			task.wait(10)
			for _, player in Players:GetPlayers() do
				played[player] = (played[player] or 0) + 10
				if played[player] >= GameConfig.Spin.EarnEvery then
					played[player] = 0
					Gamble.AddSpins(player, 1)
					Net.Notify(player, "You earned a Lucky Wheel spin!", "good")
				end
			end
			for player in played do
				if not player.Parent then
					played[player] = nil
				end
			end
		end
	end)
end

local _ = Knives
return Gamble
