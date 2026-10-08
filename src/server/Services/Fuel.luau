--!strict
-- The fuel that makes both games feed each other, kept to two numbers players can see:
--
--   🔥 Heat (0-10): everything good you do in EITHER game adds to it - stealing from a boss,
--      surviving a round, winning as the Murderer. Each point boosts your vault's income. Getting
--      caught by a boss knocks one off. So every round matters more the hotter you are.
--
--   🔪 Murderer meter (profile.Luck): playing fills it (every round you're not the Murderer, every
--      steal, every survival); dying early or getting caught takes a little off. Your chance to be
--      the Murderer is your meter against everyone else's, capped so nobody hogs it, and it empties
--      when you're picked. Shown as "Your chance to be the Murderer: X%".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(script.Parent.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local Offers = require(script.Parent.Offers)

local Fuel = {}

local CONFIG = GameConfig.Fuel

function Fuel.Heat(player: Player): number
	local profile = DataService.Get(player)
	return if profile then profile.Heat else 0
end

-- Vault income multiplier from Heat
function Fuel.IncomeMultiplier(player: Player): number
	return 1 + Fuel.Heat(player) * CONFIG.HeatIncome
end

-- +/- Heat with a little pop on the owner's screen (client/Hud "Heat")
function Fuel.AddHeat(player: Player, delta: number, reason: string)
	local profile = DataService.Get(player)
	if not profile or delta == 0 then
		return
	end
	local before = profile.Heat
	local after = math.clamp(before + delta, 0, CONFIG.MaxHeat)
	if after == before then
		return
	end
	DataService.Update(player, function(p)
		p.Heat = after
	end)
	Net.Remotes.Effect:FireClient(player, "Heat", after, after - before, reason)
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

return Fuel
