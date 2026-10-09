--!strict
-- The featured paid coffin this week (Config/Featured), for the shop tile (client) and the grant
-- (server MonetizationService). Pure functions of the clock: every server and client agree.
local Config = require(script.Parent.Config.Featured)

local FeaturedCoffin = {}

local WEEK = 7 * 86400

-- This week's knife name and when its week ends (os.time), or nil when nothing is on sale
function FeaturedCoffin.Current(now: number): (string?, number?)
	local weeks = Config.Weeks
	for i, week in weeks do
		local ends = if weeks[i + 1] then weeks[i + 1].Starts else week.Starts + WEEK
		if now >= week.Starts and now < ends then
			return week.Knife, ends
		end
	end
	return nil, nil
end

-- One roll of the shown odds: a mutation id ("" = none)
function FeaturedCoffin.RollMutation(rng: Random): string
	local pick = rng:NextNumber() * 100
	for _, entry in Config.Odds do
		pick -= entry.Chance
		if pick < 0 then
			return entry.Mutation
		end
	end
	return Config.Odds[1].Mutation
end

FeaturedCoffin.Odds = Config.Odds
FeaturedCoffin.Rarity = Config.Rarity

return FeaturedCoffin
