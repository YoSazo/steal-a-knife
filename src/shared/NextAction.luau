--!strict
-- THE next thing to do, for the guide (client/Guide): one short instruction a 5-year-old gets, and
-- where it is. Pure: it takes a snapshot of the player's state and returns an action, so it's
-- testable on its own (tests/NextAction.studio.luau). The client turns `Target` into a place
-- (client/Places) and draws the arrows (client/Arrows).
--
-- First match wins. The next step should always be about a minute away: steal another knife from a
-- monster you can outrun; rounds earn Speed while stashes restock.
local GameConfig = require(script.Parent.Config.GameConfig)
local PenMode = require(script.Parent.PenMode)

local NextAction = {}

export type State = {
	InRound: boolean,
	Carrying: string?, -- the item string
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
	BestOwnedRank: number, -- highest knife rarity you own (1 = Common)
	Stocked: { [number]: number? }, -- knives on each boss's wall (nil = not loaded yet)
	Gift: boolean, -- a present waiting at your vault
	GiftNearby: boolean?,
	Committed: boolean?, -- finish the current short task before choosing a gift
	IndexClaimable: number, -- Index rewards ready
	TutorialDone: boolean,
	NewTier: number?,
	Spare: boolean?,
	BetterReplacement: boolean?,
	CanRebirth: boolean?,
}

export type Action = {
	Id: string,
	Text: string, -- RichText
	Short: string?,
	Target: string?, -- "Plate" | "Home" | "Vault" | "Lair" | "VaultSign" | "Pad" | "Gift"
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

-- A goal is a monster you can see ("the FLOWER TOAD"), never a knife category ("RARE knives")
local function monster(zone: number): string
	local z = (GameConfig.Zones :: any)[zone]
	local tint = (z.Color :: Color3):Lerp(Color3.new(1, 1, 1), 0.3):ToHex()
	return `<font color="#{tint}"><b>{string.upper(GameConfig.MonsterName(zone))}</b></font>`
end

local function floorAffordable(s: State): boolean
	local cost, _, rebirths = PenMode.RoomUpgrade(s.Slots)
	return s.Slots < PenMode.MaxSlots() and s.Rebirths >= rebirths and s.Cash >= cost
end

-- Is the money on your pads worth the walk? It enables an upgrade, or you're already home.
local function worthCollecting(s: State): boolean
	if s.AutoCollect or s.PendingCash <= 0 then
		return false
	end
	return s.InVault
end

function NextAction.Pick(s: State): Action?
	if s.InRound then
		return nil -- the round has its own line (client/Hud: SURVIVE / GET EVERYONE)
	end
	local full = s.KnifeCount >= s.Slots

	-- 1. Carrying something: get it home
	local carrying = s.Carrying
	if carrying and carrying ~= "" then
		if full then
			if floorAffordable(s) then
				return {
					Id = "carry_bigger",
					Text = PenMode.Words("Your vault is full! Make it <b>bigger</b>!"),
					Target = "VaultSign",
				}
			end
			return {
				Id = "carry_full",
				Text = PenMode.Words("Your vault is full! <b>Sell</b> a knife to make room!"),
				Target = if s.Spare ~= false then "Sell" else nil,
				Ui = if s.Spare == false then "Knives" else nil,
			}
		end
		if s.InVault then
			return {
				Id = "carry_place",
				Text = "<b>Tap</b> where you want to put it!",
				Short = "Tap where to put it!",
				Target = "Home",
			}
		end
		return {
			Id = "carry_home",
			Text = if PenMode.Coffins()
				then "<b>RUN HOME</b> with your coffin!"
				else "<b>RUN HOME</b> with your knife!",
			Short = if PenMode.Coffins() then "RUN HOME with your coffin!" else "RUN HOME with your knife!",
			Target = "Home",
		}
	end

	-- 2. Something waiting for you
	if s.Gift and (s.InVault or s.GiftNearby) and not s.Committed then
		return { Id = "gift", Text = "Open your <b>gift</b>!", Target = "Gift" }
	end

	local reach = NextAction.Reachable(s.Speed)
	local function stockedAt(zone: number): boolean
		local n = s.Stocked[zone]
		return n == nil or n > 0 -- (not loaded yet: assume knives are there)
	end

	-- 3. Fast enough for a new boss: the big moment
	local freshTier = s.NewTier or (if reach > s.BestOwnedRank then reach else nil)
	if not full and freshTier and freshTier <= reach and stockedAt(freshTier) then
		return {
			Id = "new_tier",
			Text = `Fast enough! Steal from the {monster(freshTier)}!`,
			Short = `Steal from the {monster(freshTier)}!`,
			Target = "Lair",
			Zone = freshTier,
		}
	end

	-- 4. Rewards and upgrades you can take right now
	if s.TutorialDone and s.IndexClaimable > 0 then
		return {
			Id = "index",
			Text = "Open <b>Index</b> for free cash + Speed!",
			Short = "Index → free cash + Speed!",
			Ui = "Index",
		}
	end
	if full then
		if floorAffordable(s) then
			return {
				Id = "vault_bigger",
				Text = PenMode.Words("Your vault is full! Make it <b>bigger</b>!"),
				Target = "VaultSign",
			}
		end
		if s.CanRebirth then
			return {
				Id = "rebirth",
				Text = "<b>Rebirth</b> = earn more forever! (More → Rebirth)",
				Short = "Rebirth = earn more forever!",
				Ui = "Rebirth",
			}
		end
		if s.BetterReplacement ~= false then
			return {
				Id = "vault_full",
				Text = PenMode.Words("Vault full! <b>Sell</b> a knife to make room!"),
				Short = PenMode.Words("Vault full! Sell a knife!"),
				Target = if s.Spare ~= false then "Sell" else nil,
				Ui = if s.Spare == false then "Knives" else nil,
			}
		end
	end
	if s.KnifeCount >= s.Slots * 0.8 and floorAffordable(s) then
		return { Id = "vault_bigger", Text = "Make your vault <b>bigger</b>!", Target = "VaultSign" }
	end

	local nextZone = (GameConfig.Zones :: any)[reach + 1]

	-- 6. Money on your pads that's worth the walk
	if worthCollecting(s) then
		return { Id = "collect", Text = "Grab your <b>money</b>!", Target = "Pad" }
	end

	-- 7. Steal another knife: the deepest boss you can outrun that has knives on the wall
	for zone = if full then 0 else reach, 1, -1 do
		if stockedAt(zone) then
			return {
				Id = "steal",
				Text = `Steal another coffin from the {monster(zone)}!`,
				Target = "Lair",
				Zone = zone,
			}
		end
	end

	-- 8. Empty stashes: survive the next round for Speed.
	if nextZone then
		return { Id = "round_wait", Text = "SURVIVE for Speed!" }
	end
	if s.PendingCash > 0 and not s.AutoCollect then
		return { Id = "collect_all", Text = "Grab your <b>money</b>!", Target = "Pad" }
	end
	if s.CanRebirth then
		return {
			Id = "rebirth",
			Text = "More → Rebirth: see what starting over gives you",
			Short = "More → Rebirth: your rewards",
			Ui = "Rebirth",
		}
	end
	return { Id = "round_wait", Text = "SURVIVE for Speed!" }
end

return NextAction
