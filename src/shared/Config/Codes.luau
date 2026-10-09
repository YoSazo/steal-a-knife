--!strict
-- Codes for the game description, the group and videos (PLAN item 26). Typed in More -> Codes;
-- each works once per player (profile.Claimed "code:<CODE>"). Codes are matched in capitals, so
-- write them in capitals here. Rewards are sized to the player like every other free reward
-- (server/Services/FreeRewards): Speed = a share of the way to the next monster you can't outrun
-- yet, Cash = seconds of your own income, Coffin = one coffin of that rarity.
-- Ends (optional) = os.time() after which the code stops working; nil = never.

export type Reward = {
	Speed: number?, -- share of the gap to the next zone's SpeedNeeded (0.1 = a tenth of the way)
	Cash: number?, -- seconds of the player's income (at least Min)
	Coffin: string?, -- rarity
}

export type Code = { Reward: Reward, Ends: number? }

local Codes: { [string]: Code } = {
	RELEASE = { Reward = { Speed = 0.15, Cash = 300 } },
	MURDER = { Reward = { Coffin = "Rare" } },
}

return Codes
