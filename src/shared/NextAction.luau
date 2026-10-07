--!strict
-- THE next thing to do, for the guide (client/Guide): one short instruction a 5-year-old gets, and
-- where it is. Pure: it takes a snapshot of the player's state and returns an action, so it's
-- testable on its own (tests/NextAction.studio.luau). The client turns `Target` into a place
-- (client/Places) and draws the arrows (client/Arrows).
--
-- First match wins. The next step should always be about a minute away: steal another knife from a
-- boss you can outrun; the wheel is the fallback while walls restock.
local Format = require(script.Parent.Format)
local GameConfig = require(script.Parent.Config.GameConfig)

local NextAction = {}

export type State = {
	InRound: boolean,
	Carrying: string?, -- item string, or "Case:<Rarity>"
	InVault: boolean, -- standing inside your own vault
	FreePlate: boolean, -- a "Place Knife" plate is lit (carrying)
	KnifeCount: number,
	Slots: number,
	Rebirths: number,
	Cash: number,
	Income: number, -- per second
	PendingCash: number, -- waiting on your pads
	AutoCollect: boolean,
	Speed: number,
	Training: boolean, -- in your wheel
	BestOwnedRank: number, -- highest knife rarity you own (1 = Common)
	Stocked: { [number]: number? }, -- knives on each boss's wall (nil = not loaded yet)
	Gift: boolean, -- a present waiting at your vault
	IndexClaimable: number, -- Index rewards ready
	WheelCost: number?, -- next Faster Wheel price (nil = maxed)
	TutorialDone: boolean,
}

export type Action = {
	Id: string,
	Text: string, -- RichText
	Target: string?, -- "Plate" | "Home" | "Vault" | "Lair" | "Wheel" | "VaultSign" | "WheelSign" | "Pad" | "Gift"
	Zone: number?, -- for "Lair"
	Ui: string?, -- a button to point at instead ("Index")
}

-- The deepest boss you're fast enough for
function NextAction.Reachable(speed: number): number
	local best = 1
	for i, zone in GameConfig.Zones :: { any } do
		if speed >= (zone.SpeedNeeded or 0) then
			best = i
		end
	end
	return best
end

local function rarity(zone: number): string
	local z = (GameConfig.Zones :: any)[zone]
	local tint = (z.Color :: Color3):Lerp(Color3.new(1, 1, 1), 0.3):ToHex()
	return `<font color="#{tint}"><b>{string.upper(z.Rarity)}</b></font>`
end

local function floorAffordable(s: State): boolean
	return s.Slots < GameConfig.MaxSlots
		and s.Rebirths >= GameConfig.FloorRebirthsFor(s.Slots)
		and s.Cash >= GameConfig.SlotCost(s.Slots)
end

-- Is the money on your pads worth the walk? (enough for the next upgrade, or 30 s of income)
local function worthCollecting(s: State): boolean
	if s.AutoCollect or s.PendingCash <= 0 then
		return false
	end
	local wheel = s.WheelCost
	if wheel and s.Cash < wheel and s.Cash + s.PendingCash >= wheel then
		return true
	end
	return s.PendingCash >= math.max(1, s.Income) * 30
end

function NextAction.Pick(s: State): Action?
	if s.InRound then
		return nil -- the round has its own line (client/Hud: SURVIVE / GET EVERYONE)
	end
	local full = s.KnifeCount >= s.Slots

	-- 1. Carrying something: get it home
	local carrying = s.Carrying
	if carrying and carrying ~= "" then
		if carrying:match("^Case:") then
			return { Id = "carry_case", Text = "Bring your case home!", Target = "Home" }
		end
		if full then
			if floorAffordable(s) then
				return { Id = "carry_bigger", Text = "Your vault is full! Make it <b>bigger</b>!", Target = "VaultSign" }
			end
			return {
				Id = "carry_full",
				Text = "Your vault is full! <b>Sell</b> a knife to make room!",
				Target = "Vault",
			}
		end
		if s.InVault and s.FreePlate then
			return { Id = "carry_place", Text = "Put your knife on the <b>glowing plate</b>!", Target = "Plate" }
		end
		return { Id = "carry_home", Text = "<b>RUN HOME</b> with your knife!", Target = "Plate" }
	end

	-- 2. Something waiting for you
	if s.Gift then
		return { Id = "gift", Text = "🎁 A <b>present</b> at your vault!", Target = "Gift" }
	end

	local reach = NextAction.Reachable(s.Speed)
	local function stockedAt(zone: number): boolean
		local n = s.Stocked[zone]
		return n == nil or n > 0 -- (not loaded yet: assume knives are there)
	end

	-- 3. Fast enough for a new boss: the big moment
	if reach > s.BestOwnedRank and stockedAt(reach) then
		return {
			Id = "new_tier",
			Text = `Fast enough! Steal a {rarity(reach)} knife!`,
			Target = "Lair",
			Zone = reach,
		}
	end

	-- 4. Rewards and upgrades you can take right now
	if s.TutorialDone and s.IndexClaimable > 0 then
		return { Id = "index", Text = "Claim your <b>knife reward</b>!", Ui = "Index" }
	end
	if full then
		if floorAffordable(s) then
			return { Id = "vault_bigger", Text = "Your vault is full! Make it <b>bigger</b>!", Target = "VaultSign" }
		end
		return { Id = "vault_full", Text = "Your vault is full! <b>Sell</b> your worst knife!", Target = "Vault" }
	end
	if s.WheelCost and s.Cash >= s.WheelCost then
		return { Id = "wheel_upgrade", Text = "Get a <b>faster wheel</b>!", Target = "WheelSign" }
	end
	if s.KnifeCount >= s.Slots * 0.8 and floorAffordable(s) then
		return { Id = "vault_bigger", Text = "Make your vault <b>bigger</b>!", Target = "VaultSign" }
	end

	-- 5. Already in the wheel: keep going (it's what you chose), with how far to go
	local nextZone = (GameConfig.Zones :: any)[reach + 1]
	if s.Training and nextZone then
		local left = math.max(0, (nextZone.SpeedNeeded or 0) - s.Speed)
		return {
			Id = "train",
			Text = `Keep running! <b>{Format.Short(left)}</b> Speed to {rarity(reach + 1)} knives`,
			Target = "Wheel",
		}
	end

	-- 6. Money on your pads that's worth the walk
	if worthCollecting(s) then
		return { Id = "collect", Text = "Grab your <b>money</b>!", Target = "Pad" }
	end

	-- 7. Steal another knife: the deepest boss you can outrun that has knives on the wall
	for zone = reach, 1, -1 do
		if stockedAt(zone) then
			return {
				Id = "steal",
				Text = `Steal another {rarity(zone)} knife!`,
				Target = "Lair",
				Zone = zone,
			}
		end
	end

	-- 8. Walls empty for now: get faster in your wheel
	if nextZone then
		return { Id = "train", Text = `Run in your <b>wheel</b> to get faster!`, Target = "Wheel" }
	end
	return { Id = "collect_all", Text = "Grab your <b>money</b>!", Target = "Pad" }
end

return NextAction
