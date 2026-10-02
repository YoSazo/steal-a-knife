--!strict
-- Knife trading between two players, made scam-proof the simple way:
--   1. A asks B to trade, B accepts: a trade window opens on both screens.
--   2. Each puts up to 6 of their knives in. ANY change un-readies BOTH sides.
--   3. Both press Ready -> a 3 second countdown both can see (cancel any time) -> swap.
-- The server checks everything again at the swap (still owned, room on both walls, nobody in a
-- round or carrying anything). Remote Trade (function):
--   ("Request", userId) ("Accept", userId) ("Decline", userId) ("Offer", { item }) ("Ready") ("Cancel")
-- Clients hear Effect "TradeRequest" (fromId, name), "TradeState" (state) and "TradeClosed" (why).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)

local TradeService = {}

local MAX_ITEMS = 6
local COUNTDOWN = 3

type Side = { Player: Player, Offer: { string }, Ready: boolean }
type Session = { A: Side, B: Side, Version: number, CountdownEnds: number? }

local sessions: { [Player]: Session } = {}
local requests: { [Player]: { [number]: number } } = {} -- target -> requester UserId -> when
local lastCall: { [Player]: number } = {}

local function sideOf(session: Session, player: Player): (Side, Side)
	if session.A.Player == player then
		return session.A, session.B
	end
	return session.B, session.A
end

local function push(session: Session)
	for _, side in { session.A, session.B } do
		local mine, theirs = sideOf(session, side.Player)
		Net.Remotes.Effect:FireClient(side.Player, "TradeState", {
			OtherName = theirs.Player.DisplayName,
			Mine = mine.Offer,
			Theirs = theirs.Offer,
			MyReady = mine.Ready,
			TheirReady = theirs.Ready,
			CountdownEnds = session.CountdownEnds,
		})
	end
end

local function close(session: Session, why: string)
	for _, side in { session.A, session.B } do
		if sessions[side.Player] == session then
			sessions[side.Player] = nil
			if side.Player.Parent then
				Net.Remotes.Effect:FireClient(side.Player, "TradeClosed", why)
			end
		end
	end
end

local function busy(player: Player): string?
	if player:GetAttribute("InRound") then
		return "in a round"
	end
	if player:GetAttribute("Carrying") then
		return "carrying something"
	end
	return nil
end

-- Does `player` own every item in `offer` (counting duplicates)?
local function owns(player: Player, offer: { string }): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end
	local have: { [string]: number } = {}
	for _, item in profile.Knives do
		have[item] = (have[item] or 0) + 1
	end
	for _, item in offer do
		if (have[item] or 0) <= 0 then
			return false
		end
		have[item] -= 1
	end
	return true
end

local function swap(session: Session)
	local a, b = session.A, session.B
	local pa, pb = DataService.Get(a.Player), DataService.Get(b.Player)
	if not pa or not pb then
		return close(session, "Someone left.")
	end
	local why = busy(a.Player) or busy(b.Player)
	if why then
		return close(session, `Trade cancelled: someone is {why}.`)
	end
	if not owns(a.Player, a.Offer) or not owns(b.Player, b.Offer) then
		return close(session, "Trade cancelled: a knife is gone.")
	end
	if #pa.Knives - #a.Offer + #b.Offer > pa.Slots or #pb.Knives - #b.Offer + #a.Offer > pb.Slots then
		return close(session, "Trade cancelled: not enough room on someone's wall.")
	end
	local function move(profile: DataService.Profile, give: { string }, get: { string })
		for _, item in give do
			local index = table.find(profile.Knives, item)
			if index then
				table.remove(profile.Knives, index)
				if profile.Equipped == item and not table.find(profile.Knives, item) then
					profile.Equipped = ""
				end
			end
		end
		for _, item in get do
			table.insert(profile.Knives, item)
			local parsed = Items.Parse(item)
			if parsed and not table.find(profile.Discovered, parsed.Name) then
				table.insert(profile.Discovered, parsed.Name)
			end
		end
	end
	DataService.Update(a.Player, function(p)
		move(p, a.Offer, b.Offer)
	end)
	DataService.Update(b.Player, function(p)
		move(p, b.Offer, a.Offer)
	end)
	-- Trades are worth saving straight away
	task.spawn(DataService.SaveNow, a.Player)
	task.spawn(DataService.SaveNow, b.Player)
	BaseService.RefreshRack(a.Player)
	BaseService.RefreshRack(b.Player)
	close(session, "Trade complete! 🤝")
end

local function handle(player: Player, action: unknown, arg: unknown): boolean
	local now = os.clock()
	if now - (lastCall[player] or 0) < 0.2 then
		return false
	end
	lastCall[player] = now
	local session = sessions[player]

	if action == "Request" and type(arg) == "number" then
		local other = Players:GetPlayerByUserId(arg)
		if not other or other == player or sessions[other] or session then
			Net.Notify(player, "They can't trade right now.", "bad")
			return false
		end
		local why = busy(player) or busy(other)
		if why then
			Net.Notify(player, `Can't trade while someone is {why}.`, "bad")
			return false
		end
		local pending = requests[other] or {}
		pending[player.UserId] = now
		requests[other] = pending
		Net.Remotes.Effect:FireClient(other, "TradeRequest", player.UserId, player.DisplayName)
		Net.Notify(player, `Trade request sent to {other.DisplayName}!`, "info")
		return true
	elseif (action == "Accept" or action == "Decline") and type(arg) == "number" then
		local other = Players:GetPlayerByUserId(arg)
		local mine = requests[player]
		local sent = mine and mine[arg]
		if mine then
			mine[arg] = nil
		end
		if action == "Decline" then
			if other then
				Net.Notify(other, `{player.DisplayName} doesn't want to trade.`, "info")
			end
			return true
		end
		if not other or not sent or now - sent > 60 or session or sessions[other] then
			Net.Notify(player, "That trade request expired.", "bad")
			return false
		end
		local fresh: Session = {
			A = { Player = other, Offer = {}, Ready = false },
			B = { Player = player, Offer = {}, Ready = false },
			Version = 0,
			CountdownEnds = nil,
		}
		sessions[player] = fresh
		sessions[other] = fresh
		push(fresh)
		return true
	end

	if not session then
		return false
	end
	local mine = sideOf(session, player)
	if action == "Cancel" then
		close(session, `{player.DisplayName} cancelled the trade.`)
		return true
	elseif action == "Offer" and type(arg) == "table" then
		local offer: { string } = {}
		for i, item in arg :: { any } do
			if i > MAX_ITEMS or type(item) ~= "string" then
				return false
			end
			table.insert(offer, item)
		end
		if not owns(player, offer) then
			return false
		end
		mine.Offer = offer
		-- Any change: both have to look again
		session.A.Ready = false
		session.B.Ready = false
		session.CountdownEnds = nil
		session.Version += 1
		push(session)
		return true
	elseif action == "Ready" then
		mine.Ready = not mine.Ready
		session.CountdownEnds = nil
		session.Version += 1
		if session.A.Ready and session.B.Ready then
			local version = session.Version
			session.CountdownEnds = workspace:GetServerTimeNow() + COUNTDOWN
			task.delay(COUNTDOWN, function()
				-- Nothing changed during the countdown: swap
				if
					sessions[player] == session
					and session.Version == version
					and session.A.Ready
					and session.B.Ready
				then
					swap(session)
				end
			end)
		end
		push(session)
		return true
	end
	return false
end

function TradeService.Init()
	Net.Remotes.Trade.OnServerInvoke = handle
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			close(session, `{player.DisplayName} left.`)
		end
		requests[player] = nil
		lastCall[player] = nil
	end)
	-- A round starting or a knife being picked up ends any trade in progress
	local function watch(player: Player)
		for _, attribute in { "InRound", "Carrying" } do
			player:GetAttributeChangedSignal(attribute):Connect(function()
				local session = sessions[player]
				if session and player:GetAttribute(attribute) then
					close(session, "Trade cancelled.")
				end
			end)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return TradeService
