--!strict
-- The featured paid coffin (PLAN item 21, owner's choices): one fixed Mythic Inferno character a
-- week, sold in 1 / 3 / 10 bundles (Monetization products FeaturedCoffin1/3/10), READY the moment
-- it lands, with these exact mutation odds shown on the shop tile (size is always normal, so the
-- odds below are the whole roll). Godly and up stay earned only.
--
-- Weeks: each row is on sale from its Starts (os.time, UTC) until the next row's Starts; the last
-- row runs 7 days. A week that has passed never comes back (no fake scarcity, no reruns). Weeks
-- turn over with the Saturday event (3 PM US Eastern = 19:00 UTC in summer time, 20:00 in winter).
-- Add a row a week (the weekly drop); with no current row the tile hides itself.

export type Week = { Knife: string, Starts: number }

local Featured = {
	Rarity = "Mythic",
	-- Mutation id ("" = none) -> chance in percent. Must add up to 100.
	Odds = {
		{ Mutation = "", Chance = 60 },
		{ Mutation = "Gold", Chance = 25 },
		{ Mutation = "Diamond", Chance = 10 },
		{ Mutation = "Rainbow", Chance = 4 },
		{ Mutation = "Void", Chance = 1 },
	},
	Weeks = {
		{ Knife = "InfernoFang", Starts = 1791658800 }, -- Sat 2026-10-10 19:00 UTC (Lenny)
		{ Knife = "MagmaCleaver", Starts = 1792263600 }, -- Sat 2026-10-17 (Hank)
		{ Knife = "DemonHorn", Starts = 1792868400 }, -- Sat 2026-10-24 (Nina), until 10-31
	} :: { Week },
}

return Featured
