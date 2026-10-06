--!strict
-- The round prize (shared): ONE simple promise, the same for everyone - "Win the round: +1.9K
-- Speed". Whoever ends up on the winning side gets it (Murderer, Sheriff, Innocent, even if you died),
-- in your own numbers: a share of the way to the next boss you can't outrun yet, so a win makes your
-- stealing better ("enough to outrun Ivy!"). The client shows it (a line 60 s before the round) and
-- the server pays it (RoundService, once winners are home) with the SAME numbers: both read the
-- player's Speed attribute through this module.
--
-- Size: a fixed share (GameConfig.RoundPrize.StepShare) of the step from the last boss's Speed to the
-- next one's - so every win on the way to a boss is worth the same, about 1/StepShare wins per boss
-- (not a share of what's LEFT, which shrank as you got close).
--
-- (Was five prize types with a different prize per side - cash, speed, a knife, a boost, spins -
-- too much to follow, and the knives skipped players past bosses they hadn't beaten yet.)
local Items = require(script.Parent.Items)
local Knives = require(script.Parent.Config.Knives)
local Format = require(script.Parent.Format)
local GameConfig = require(script.Parent.Config.GameConfig)

local RoundPrize = {}

export type Stats = { Income: number, Speed: number, BestRank: number }
export type Prize = {
	Kind: string,
	Amount: number,
	Knife: string?,
	Text: string,
	Boss: string?, -- the next boss you can't outrun yet (what this Speed is for)
	Zone: number?, -- that boss's zone
	Reaches: boolean, -- this prize gets you fast enough for them
	Left: number, -- Speed still missing for them after the prize (0 when it reaches)
}

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
		BestRank = best, -- (client/Hud's next goal reads this)
	}
end

-- The next boss you can't outrun yet: (its Speed, its name, its zone, the boss before's Speed),
-- or nil past the last one
local function nextBoss(speed: number): (number?, string?, number?, number)
	local previous = 0
	for i, zone in GameConfig.Zones :: { any } do
		local need = (zone.SpeedNeeded or 0) :: number
		if need > speed then
			return need, zone.Boss, i, previous
		end
		previous = need
	end
	return nil, nil, nil, previous
end

-- The prize for this player. (`kind` and `side` are kept for callers; every winner gets the same.)
function RoundPrize.For(
	_kind: string,
	_side: string,
	jackpot: boolean,
	_seed: number,
	stats: Stats,
	doubled: boolean?
): Prize
	local x = (if jackpot then CONFIG.JackpotMultiplier else 1) * (if doubled then 2 else 1)
	local need, boss, zone, previous = nextBoss(stats.Speed)
	local base = if need then (need - previous) * CONFIG.StepShare else stats.Speed * CONFIG.PastLastShare
	local amount = math.floor(math.max(base, CONFIG.MinSpeed) * x)
	local left = if need then math.max(0, need - (stats.Speed + amount)) else 0
	return {
		Kind = "Speed",
		Amount = amount,
		Text = `+{Format.Short(amount)} Speed`,
		Boss = boss,
		Zone = zone,
		Reaches = need ~= nil and left == 0,
		Left = left,
	}
end

-- This round's prize: always Speed; sometimes a JACKPOT (x3)
function RoundPrize.Roll(rng: Random): (string, boolean, number)
	return "Speed", rng:NextNumber() < CONFIG.JackpotChance, rng:NextInteger(1, 1000000)
end

return RoundPrize
