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
local KnifePowers = require(ReplicatedStorage.Shared.Config.KnifePowers)
local Offers = require(script.Parent.Offers)
local Analytics = require(script.Parent.Analytics)

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
	local had = profile.Heat
	Fuel.AddHeat(player, math.floor(profile.Heat / 2) - profile.Heat, reason)
	if had >= 4 then
		Offers.Later(
			player,
			"HeatRefill",
			`You lost {had - math.floor(had / 2)} Heat. Jump straight back to full 🔥?`
		)
	end
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
	local luck = math.min(Fuel.PowerLuck(player) * (1 + rarityIndex * CONFIG.RarityLuck), CONFIG.MaxPowerLuck)
	local power = Items.RollPower(rng, luck)
	-- Bad-luck protection now counts knives in a row below Epic
	local entry = KnifePowers.ById[power]
	local good = entry ~= nil and KnifePowers.TierRank(entry.Tier) >= KnifePowers.TierRank("Epic")
	Analytics.Track(player, "power.rolled", {
		power = power,
		tier = entry and entry.Tier,
		one_in = Items.PowerOneIn(power),
		pity = (DataService.Get(player) :: DataService.Profile).PowerPity,
		luck = luck,
		rarity = parsed.Knife.Rarity,
	})
	DataService.Update(player, function(p)
		p.PowerPity = if good then 0 else p.PowerPity + 1
	end)
	return Items.WithPower(item, power)
end

-- Every knife carries a power now: older knives without one roll one (plain luck) when the save
-- loads. Keeps Equipped pointing at the same knife.
function Fuel.EnsurePowers(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local changed = false
	local knives = table.clone(profile.Knives)
	local equipped = profile.Equipped
	for i, item in knives do
		local parsed = Items.Parse(item)
		if parsed and not parsed.Perk then
			local rolled = Items.WithPower(item, Items.RollPower(rng, 1))
			if equipped == item then
				equipped = rolled
			end
			knives[i] = rolled
			changed = true
		end
	end
	if changed then
		DataService.Update(player, function(p)
			for i, item in knives do
				p.Knives[i] = item
			end
			p.Equipped = equipped
		end)
	end
end

-- Power XP for the knife power you fight with (player PowerId, set by PowerService). Level-ups get a
-- popup; every 25th level the whole server hears it.
function Fuel.GivePowerXP(player: Player, amount: number)
	local id = player:GetAttribute("PowerId")
	if type(id) ~= "string" or amount <= 0 then
		return
	end
	local before, after = DataService.AddPowerXP(player, id, amount)
	if after > before then
		Analytics.Track(player, "power.level_up", { power = id, level = after })
		Analytics.Milestone(
			player,
			"power_lv_"
				.. (
					if after >= 100
						then 100
						elseif after >= 50 then 50
						elseif after >= 25 then 25
						elseif after >= 10 then 10
						else 2
				)
		)
		local name = Items.PowerName(id)
		Net.Notify(player, `⚡ {name} reached Lv {after}!`, "good")
		if after % 25 == 0 then
			Net.Announce(
				`⚡ {player.DisplayName}'s {name} reached Lv {after}!`,
				Color3.fromRGB(255, 215, 70),
				if after >= 100 then 4 else 3
			)
		end
	end
end

return Fuel
