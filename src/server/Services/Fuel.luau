--!strict
-- The fuel that makes both games feed each other, kept to two numbers players can see:
--
--   🔥 Heat (0-10): everything good you do in EITHER game adds to it - stealing from a boss,
--      surviving a round, winning as the Murderer. Each point boosts BOTH games: your vault's
--      income and your luck on rare Murderer powers. Dying in a round halves it; getting caught by
--      a boss knocks one off. So every round matters more the hotter you are.
--
--   🔪 Murderer meter (profile.Luck): playing fills it (every round you're not the Murderer, every
--      steal, every survival); dying early or getting caught takes a little off. Your chance to be
--      the Murderer is your meter against everyone else's, capped so nobody hogs it, and it empties
--      when you're picked. Shown as "Your chance to be the Murderer: X%".
--
-- Rare powers (Items.Powers) are rolled when a knife reaches your vault; Heat, deeper zones and
-- bad-luck protection raise the odds, and losing a power to a Sheriff gives you "revenge" luck.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local Net = require(script.Parent.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local ServerEvents = require(script.Parent.ServerEvents)
local Social = require(script.Parent.Social)

local Fuel = {}

local CONFIG = GameConfig.Fuel
local rng = Random.new()

function Fuel.Heat(player: Player): number
	local profile = DataService.Get(player)
	return if profile then profile.Heat else 0
end

-- Vault income multiplier from Heat
function Fuel.IncomeMultiplier(player: Player): number
	return 1 + Fuel.Heat(player) * CONFIG.HeatIncome
end

-- Power-roll luck: Heat, bad-luck protection, revenge after losing one
function Fuel.PowerLuck(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return 1
	end
	local luck = 1 + profile.Heat * CONFIG.HeatLuck
	luck *= 1 + profile.PowerPity / CONFIG.PityPer
	if profile.RevengeUntil > os.time() then
		luck *= CONFIG.RevengeLuck
	end
	-- Playing together: friends here, and the server's Lucky Rush
	luck *= Social.FriendsMultiplier(player)
	if ServerEvents.Active("LuckyRush") then
		luck *= 2
	end
	return luck
end

-- +/- Heat with a little pop on the owner's screen (client/Hud "Heat")
function Fuel.AddHeat(player: Player, delta: number, reason: string)
	local profile = DataService.Get(player)
	if not profile or delta == 0 then
		return
	end
	local before = profile.Heat
	if delta > 0 and ServerEvents.Active("HeatWave") then
		delta *= 2
	end
	local after = math.clamp(before + delta, 0, CONFIG.MaxHeat)
	if after == before then
		return
	end
	DataService.Update(player, function(p)
		p.Heat = after
	end)
	Net.Remotes.Effect:FireClient(player, "Heat", after, after - before, reason)
	-- Maxed out: the whole server catches fire
	if after == CONFIG.MaxHeat and before < CONFIG.MaxHeat then
		ServerEvents.Start("HeatWave", player.DisplayName)
	end
end

-- Dying in a round: half your Heat goes
function Fuel.HalveHeat(player: Player, reason: string)
	local profile = DataService.Get(player)
	if not profile or profile.Heat <= 0 then
		return
	end
	Fuel.AddHeat(player, math.floor(profile.Heat / 2) - profile.Heat, reason)
end

function Fuel.AddMeter(player: Player, delta: number)
	DataService.Update(player, function(p)
		p.Luck = math.max(0, p.Luck + delta)
	end)
end

-- Gives a "?" knife its power (or none), using this player's luck. Deeper-zone knives roll better.
-- Returns the finished item string.
function Fuel.RollPower(player: Player, item: string): string
	local parsed = Items.Parse(item)
	if not parsed or not parsed.Unrolled then
		return item
	end
	local rarityIndex = (table.find(Knives.Rarities, parsed.Knife.Rarity) or 1) - 1
	local luck = Fuel.PowerLuck(player) * (1 + rarityIndex * CONFIG.RarityLuck)
	local power = Items.RollPower(rng, luck)
	DataService.Update(player, function(p)
		p.PowerPity = if power == "" then p.PowerPity + 1 else 0
	end)
	return Items.WithPower(item, power)
end

return Fuel
