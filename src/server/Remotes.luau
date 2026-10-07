--!strict
-- All client<->server traffic. Clients can only ask; the server validates and decides everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = Instance.new("Folder")
folder.Name = "Remotes"
folder.Parent = ReplicatedStorage

local function event(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local function func(name: string): RemoteFunction
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local Remotes = {
	Notify = event("Notify"), -- server -> client: (text, kind)
	Role = event("Role"), -- server -> client: ("Murderer" | "Innocent", disguiseName)
	Purchase = func("Purchase"), -- client -> server: (kind) -> (ok, message)
	Equip = func("Equip"), -- client -> server: (knifeName) -> ok
	Sell = func("Sell"), -- client -> server: (rackIndex) -> ok
	Ability = event("Ability"), -- client -> server: (aimDirection: Vector3)
	Shoot = event("Shoot"), -- client -> server: (aimPosition: Vector3) while holding the Revolver
	Stab = event("Stab"), -- client -> server: (target: Model?) who the Murderer's swing is aimed at; only a hint the server re-checks
	AbilityState = event("AbilityState"), -- server -> client: (name?, cooldownEndsAt?) name=nil hides it
	Effect = event("Effect"), -- server -> all clients: (kind, ...) cosmetic only
	Anim = event("Anim"), -- server -> clients: (model, clipName) play an AnimLibrary clip
	Charge = event("Charge"), -- client -> server: (charging: boolean) winding up a throw
	Power = func("Power"), -- client -> server: (action "Buy" | "Equip" | "Unequip" | "Slot", powerId?) -> ok
	UsePower = event("UsePower"), -- client -> server: (powerId, aimDirection)
	Debug = func("Debug"), -- Studio-only client -> server test commands
	Tutorial = event("Tutorial"), -- client -> server: (step) the first-minute guide moved on
	RepairGate = event("RepairGate"), -- client -> server: () hold-to-repair your gate in a raid
	ClaimIndex = func("ClaimIndex"), -- client -> server: (knifeName | "All") -> ok
	Welcome = event("Welcome"), -- server -> client: ({ Offline, Away, Streak, DailyReady }) on join
	ClaimDaily = func("ClaimDaily"), -- client -> server: () -> (ok, message) today's login-streak reward
	ClaimFreeChest = func("ClaimFreeChest"), -- client -> server: () -> ok; same as walking up and pressing E
	Offer = event("Offer"), -- server -> client: (storeKey, reason) a contextual store offer
	OfferShown = event("OfferShown"), -- client -> server: (key, token) acknowledge a pending offer
	TeamUp = event("TeamUp"), -- client -> server: ("Invite" | "Accept" | "Decline", userId) / ("Leave")
	Trade = func("Trade"), -- client -> server: (action, ...) -> ok, see TradeService
	SellSign = event("SellSign"), -- client -> server: (sign: BasePart) tapped a Sell sign with a tool in hand
	SlowMode = event("SlowMode"), -- client -> server: (on: boolean) walk at normal speed in the hub
	MapVote = event("MapVote"), -- client -> server: (mapName) vote for the next murder map (the vote card)
	PlaceAt = event("PlaceAt"), -- client -> server: (position) put what you carry down here in your pen
	CoffinTarget = event("CoffinTarget"), -- client -> server: (plate) the coffin "Open now" (Robux) is for
	NotifyAsked = event("NotifyAsked"), -- client -> server: () Roblox's notifications opt-in was shown
	PrizePick = event("PrizePick"), -- client -> server: ("Cash" | "Speed") your prize if you win the next round
	Drop = event("Drop"), -- client -> server: () put down what you're carrying (boss knives go back on the wall)
	Gamble = func("Gamble"), -- client -> server: (action, arg) -> (ok, message, extra), see Gamble
	StoreTest = func("StoreTest"), -- client -> server: (kind, key) Studio-only fake purchase for unset ids
	Track = event("Track"), -- client -> server: (event, props) analytics from the client (server/Analytics whitelists)
}

-- Analytics listens to every message (the "bad" ones are where players get stuck)
local notifyHook: ((Player, string, string) -> ())? = nil
-- ("vault" -> "pen" in every message when pens are on: Shared/PenMode)
local function words(text: string): string
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild("PenMode")
	if not module then
		return text
	end
	return (require :: any)(module).Words(text)
end

return {
	Remotes = Remotes,
	-- kind: "info" | "good" | "bad"
	Notify = function(player: Player, text: string, kind: string?)
		text = words(text)
		Remotes.Notify:FireClient(player, text, kind or "info")
		if notifyHook then
			task.spawn(notifyHook, player, text, kind or "info")
		end
	end,
	SetNotifyHook = function(hook: (Player, string, string) -> ())
		notifyHook = hook
	end,
	-- A big banner across everyone's screen (rare unboxes, raids, thefts). hype 1..4 = how loud.
	Announce = function(text: string, color: Color3, hype: number?)
		Remotes.Effect:FireAllClients("Announce", words(text), color, hype or 1)
	end,
	-- Plays an AnimLibrary clip on a character/guard for everyone. `except` is the player who
	-- already started it locally (their own swing), so they don't see it twice.
	Animate = function(model: Model, clip: string, except: Player?)
		for _, player in game:GetService("Players"):GetPlayers() do
			if player ~= except then
				Remotes.Anim:FireClient(player, model, clip)
			end
		end
	end,
}
