--!strict
-- The Lucky Wheel and luck, odds shown and earnable for free:
--   * Lucky Wheel: one free spin a day + one per GameConfig.Spin.EarnEvery of play; Robux spin packs.
--     Knife prizes are coffins (CoffinService.GiveRarity).
--   * Luck potions: 2x coffin luck for a while (profile.LuckUntil, player attr LuckUntil)
-- Remotes.Gamble("Spin") -> (ok, message, prizeIndex)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local CoffinService = require(script.Parent.CoffinService)
local Analytics = require(script.Parent.Analytics)

local Gamble = {}

local rng = Random.new()

-- Luck --------------------------------------------------------------------------------------------

-- Extra coffin luck from potions (CoffinService.Luck multiplies it in, with the Luck pass)
function Gamble.LuckMultiplier(_player: Player, profile: DataService.Profile): number
	local luck = 1
	if profile.LuckUntil > os.time() then
		luck *= GameConfig.LuckPotion.Multiplier
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
			Net.Notify(player, `Lucky Wheel: better coffins for {prize.Seconds // 60} minutes!`, "good")
		elseif prize.Kind == "Spin" then
			Gamble.AddSpins(player, prize.Count)
			Net.Notify(player, `Lucky Wheel: +{prize.Count} spins!`, "good")
		elseif prize.Kind == "Coffin" then
			if not CoffinService.GiveRarity(player, prize.Tier, "the Lucky Wheel") then
				local cash = GameConfig.Pay({ Min = 20000, Seconds = 600 }, BaseService.RackIncome(player))
				DataService.AddCash(player, cash, "wheel")
				Net.Notify(player, `No room for a coffin - +{Format.Cash(cash)} instead`, "good")
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

-- Setup -------------------------------------------------------------------------------------------

function Gamble.Init()
	CoffinService.LuckMultiplier = Gamble.LuckMultiplier
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
		end
		return false, "?"
	end
	DataService.PlayerLoaded:Connect(function(player: Player, profile: DataService.Profile)
		syncSpins(player, profile)
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

return Gamble
