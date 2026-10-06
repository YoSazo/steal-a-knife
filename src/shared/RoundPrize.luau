--!strict
-- The round prize (shared): every round plays for one prize type, the same for the whole server, in
-- each player's own numbers - "If Innocents win: +$4.2M", "If the Murderer wins: a Cleaver that
-- makes $25K/s". The client shows it (a line 60 s before the round, the big red countdown at 10 s)
-- and the server pays it (RoundService, once winners are home) with the SAME numbers: both read the
-- player's Income / Speed / Knives attributes through this module. Why: 83% of new players left
-- within 4 minutes of a round ending - the round has to feed back into the hub, visibly.
local Items = require(script.Parent.Items)
local Knives = require(script.Parent.Config.Knives)
local Format = require(script.Parent.Format)
local GameConfig = require(script.Parent.Config.GameConfig)

local RoundPrize = {}

export type Stats = { Income: number, Speed: number, BestRank: number }
export type Prize = { Kind: string, Amount: number, Knife: string?, Text: string }

local CONFIG = GameConfig.RoundPrize

-- What the player has now (attributes the server keeps up to date)
function RoundPrize.Stats(player: Player): Stats
	local best = 1
	local knives = player:GetAttribute("Knives")
	if type(knives) == "string" then
		for _, item in string.split(knives, ",") do
			local parsed = item ~= "" and Items.Parse(item) or nil
			if parsed then
				best = math.max(best, Knives.Rank(parsed.Knife.Rarity))
			end
		end
	end
	return {
		Income = math.max(1, (player:GetAttribute("Income") or 0) :: number),
		Speed = math.max(0, (player:GetAttribute("Speed") or 0) :: number),
		BestRank = best,
	}
end

-- The knife a player would get: a step (or two) above their best rarity, picked by the round's seed
-- so the name they're shown is the knife they get
local function knifeFor(side: string, jackpot: boolean, stats: Stats, seed: number): string
	local step = CONFIG.KnifeStep[side] + (if jackpot then 1 else 0)
	local rank = math.clamp(stats.BestRank + step, 1, #Knives.Rarities)
	local pool = Knives.ByRarity[Knives.Rarities[rank]]
	local knife = pool[(seed % #pool) + 1]
	return knife.Name
end

-- side: "Innocent" | "Murderer"; doubled: bought "Double your prize"
function RoundPrize.For(
	kind: string,
	side: string,
	jackpot: boolean,
	seed: number,
	stats: Stats,
	doubled: boolean?
): Prize
	local x = (if jackpot then CONFIG.JackpotMultiplier else 1) * (if doubled then 2 else 1)
	if kind == "Cash" then
		local amount = math.floor(stats.Income * 60 * CONFIG.CashMinutes[side] * x)
		amount = math.max(amount, CONFIG.MinCash[side])
		return { Kind = kind, Amount = amount, Text = `+{Format.Cash(amount)}` }
	elseif kind == "Speed" then
		local amount = math.floor(math.max(stats.Speed * CONFIG.SpeedShare[side], CONFIG.MinSpeed[side]) * x)
		return { Kind = kind, Amount = amount, Text = `+{Format.Short(amount)} Speed` }
	elseif kind == "Knife" then
		local name = knifeFor(side, jackpot, stats, seed)
		local count = if doubled then 2 else 1
		local income = Format.Cash(Items.Income(name))
		local shown = Items.DisplayName(name)
		return {
			Kind = kind,
			Amount = count,
			Knife = name,
			Text = if count > 1 then `2 {shown}s that make {income}/s` else `a {shown} that makes {income}/s`,
		}
	elseif kind == "Boost" then
		local minutes = math.floor(CONFIG.BoostMinutes[side] * x)
		return { Kind = kind, Amount = minutes * 60, Text = `2x cash for {minutes} min` }
	else
		local spins = math.floor(CONFIG.Spins[side] * x)
		return { Kind = "Spins", Amount = spins, Text = `+{spins} free spins` }
	end
end

-- Pick this round's prize type (weighted) and whether it's a jackpot round
function RoundPrize.Roll(rng: Random): (string, boolean, number)
	local total = 0
	for _, entry in CONFIG.Kinds do
		total += entry.Weight
	end
	local pick = rng:NextNumber() * total
	local kind = CONFIG.Kinds[1].Kind
	for _, entry in CONFIG.Kinds do
		pick -= entry.Weight
		if pick <= 0 then
			kind = entry.Kind
			break
		end
	end
	return kind, rng:NextNumber() < CONFIG.JackpotChance, rng:NextInteger(1, 1000000)
end

return RoundPrize
