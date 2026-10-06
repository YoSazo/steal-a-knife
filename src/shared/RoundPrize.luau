--!strict
-- The round prize (shared): ONE simple promise, the same for everyone - "Win the round: +1.9K
-- Speed". Whoever ends up on the winning side gets it (Murderer, Sheriff, Innocent, even if you died),
-- in your own numbers: a share of the way to the next boss you can't outrun yet, so a win makes your
-- stealing better ("enough to outrun Ivy!"). The client shows it (a line 60 s before the round) and
-- the server pays it (RoundService, once winners are home) with the SAME numbers: both read the
-- player's Speed attribute through this module.
--
-- (Was five prize types with a different prize per side - cash, speed, a knife, a boost, spins -
-- too much to follow, and the knives skipped players past bosses they hadn't beaten yet.)
local Format = require(script.Parent.Format)
local GameConfig = require(script.Parent.Config.GameConfig)

local RoundPrize = {}

export type Stats = { Income: number, Speed: number, BestRank: number }
export type Prize = {
	Kind: string,
	Amount: number,
	Knife: string?,
	Text: string,
	Boss: string?, -- the boss this prize lets you outrun (if it gets you there)
}

local CONFIG = GameConfig.RoundPrize

-- What the player has now (attributes the server keeps up to date)
function RoundPrize.Stats(player: Player): Stats
	return {
		Income = math.max(1, (player:GetAttribute("Income") or 0) :: number),
		Speed = math.max(0, (player:GetAttribute("Speed") or 0) :: number),
		BestRank = 1,
	}
end

-- The next boss you can't outrun yet: (its Speed, its name), or nil past the last one
local function nextBoss(speed: number): (number?, string?)
	for _, zone in GameConfig.Zones :: { any } do
		local need = (zone.SpeedNeeded or 0) :: number
		if need > speed then
			return need, zone.Boss
		end
	end
	return nil, nil
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
	local need, boss = nextBoss(stats.Speed)
	local base = if need then (need - stats.Speed) * CONFIG.GapShare else stats.Speed * CONFIG.PastLastShare
	local amount = math.floor(math.max(base, CONFIG.MinSpeed) * x)
	local reaches = need ~= nil and stats.Speed + amount >= need
	return {
		Kind = "Speed",
		Amount = amount,
		Text = `+{Format.Short(amount)} Speed`,
		Boss = if reaches then boss else nil,
	}
end

-- This round's prize: always Speed; sometimes a JACKPOT (x3)
function RoundPrize.Roll(rng: Random): (string, boolean, number)
	return "Speed", rng:NextNumber() < CONFIG.JackpotChance, rng:NextInteger(1, 1000000)
end

return RoundPrize
