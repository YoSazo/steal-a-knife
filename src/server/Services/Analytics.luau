--!strict
-- Our own product analytics (docs/ANALYTICS.md). Every service reports what players do through
-- Analytics.Track; events are batched and POSTed as JSON to our own ingest server (analytics/ in this
-- repo: Render + Neon Postgres), signed with a secret header.
--
-- Every event carries the player's state at that moment (Analytics.context): key events get the whole
-- of it (progress, economy, where they are, what they're doing, device, A/B groups, first-touch
-- source), the rest a compact core, and the server keeps device / source per session, so any funnel
-- can be broken down by any variable. Nothing is pre-aggregated away except the money flow (summed per
-- reason, flushed with each heartbeat) and per-second spam (shots, stabs).
--
-- Privacy: no names, no chat, no raw UserIds. distinct_id is a salted hash of the UserId.
-- Roblox's own dashboard gets the onboarding funnel too (AnalyticsService), as a free backup.

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local Net = require(script.Parent.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)

-- Where events go: our ingest server (analytics/, e.g. "https://stats.yourdomain.com/ingest").
-- The key: Creator Hub > your experience > Secrets, named "ingest_key" (never in the repo). KEY below
-- is only a fallback for Studio tests. Server-only module: clients never see either.
local URL = "https://steal-and-murder-analytics.onrender.com/ingest"
local KEY = ""
local SECRET_NAME = "ingest_key"
local SALT = "steal-a-knife:7f3c" -- changing it splits every player into a new id: don't
local SEND_IN_STUDIO = false -- Studio playtests stay out of the real data unless this is on
local FLUSH_EVERY = 10 -- seconds
local MAX_BATCH = 250
local MAX_QUEUE = 6000
local HEARTBEAT_EVERY = 60

-- A/B tests: name -> variants. Every player lands in one variant per test for good (hash of their
-- id), it rides on every event as ab_<name>, and game code asks Analytics.Variant(player, name).
local EXPERIMENTS: { [string]: { string } } = {}

-- The first-session funnel, in order. Each step is a milestone (Analytics.Milestone); the same
-- steps go to Roblox's onboarding funnel (Creator Dashboard > Analytics > Funnels).
-- The onboarding funnel (here, Roblox's Creator Dashboard funnel and our dashboard: analytics/src/
-- queries.js FIRST_SESSION - keep the two lists the same). The order a new player meets them TODAY:
-- the 4-step guide (Frank, run home, cash pad, wheel), then their first murder round (where they're
-- the Murderer), staying for a second one, and going deeper. (Rebuilt 2026-10-06: the Upgrades and
-- equip steps are gone from the guide.)
local ONBOARDING = {
	"joined",
	"spawned",
	"tutorial_1", -- go to Frank's stash
	"steal_started",
	"tutorial_2", -- run home
	"knife_home",
	"tutorial_3", -- collect the cash pad
	"cash_collected",
	"tutorial_4", -- train speed on the wheel
	"wheel_trained",
	"tutorial_done",
	"round_played", -- the first murder round (a new player is the Murderer)
	"second_round", -- stayed for another round
	"second_knife_home",
	"first_upgrade", -- wheel upgrade, next vault floor...
	"zone_2",
	"session_2",
}
local ONBOARDING_INDEX: { [string]: number } = {}
for i, name in ONBOARDING do
	ONBOARDING_INDEX[name] = i
end

local Analytics = {}

type Session = {
	Id: string,
	Started: number, -- os.clock()
	StartedAt: number, -- os.time()
	Number: number,
	Device: { [string]: any },
	Zone: number, -- 0 = plaza / vaults, -1 = in a round map
	ZoneSince: number,
	ZoneTime: { [number]: number },
	Flow: { [string]: number }, -- money by reason since the last heartbeat (+ in, - out)
	Earned: number,
	Spent: number,
	Robux: number,
	Counts: { [string]: number }, -- per-second actions, summed (shots, stabs, throws)
	Last: string, -- the last thing that happened to them (for session.end: what made them leave?)
	LastAt: number,
	Friction: { [string]: number }, -- message -> os.clock() last logged (throttle)
	Source: { [string]: any },
	Rate: { number }, -- client event timestamps (rate limit)
	KnivesHome: number,
}

local sessions: { [Player]: Session } = {}
local queue: { any } = {}
local recent: { any } = {} -- last few hundred events, for DebugService ("Analytics")
local sending = false

local function isStudio(): boolean
	return RunService:IsStudio()
end

-- FNV-1a, 32 bit (bit32 keeps it exact): two of them make a 64-bit id
local function fnv(text: string, seed: number): number
	local h = seed
	for i = 1, #text do
		h = bit32.bxor(h, string.byte(text, i))
		h = (bit32.lshift(h, 24) + h * 403) % 4294967296 -- h * 16777619 (= 2^24 + 403), exact
	end
	return h
end

local idCache: { [number]: string } = {}
function Analytics.IdOf(userId: number): string
	local cached = idCache[userId]
	if cached then
		return cached
	end
	local text = tostring(userId)
	local id = string.format("%08x%08x", fnv(SALT .. text, 2166136261), fnv(text .. SALT, 3735928559))
	idCache[userId] = id
	return id
end

local function bucket(value: number): number
	-- order of magnitude: 0 for < 10, 3 for thousands, 18 for quintillions
	return if value >= 10 then math.floor(math.log10(value)) else 0
end

local function finite(value: number): number
	return if value == value and value > -math.huge and value < math.huge then value else 0
end

-- "Re-rolling this knife costs $1.2M" -> "Re-rolling this knife costs $#": groups the same message
local function normalize(text: string): string
	text = text:gsub("%b<>", "") -- rich text tags
	text = text:gsub("%$?%d[%d%.,]*%s?[KMBTQSONDkmbtqsond][a-z]?%f[%A]", "#")
	text = text:gsub("%$?%d[%d%.,]*", "#")
	return text:sub(1, 80)
end
Analytics.Normalize = normalize

local function experimentVariant(player: Player, name: string): string?
	local variants = EXPERIMENTS[name]
	if not variants or #variants == 0 then
		return nil
	end
	return variants[fnv(name .. ":" .. tostring(player.UserId), 2166136261) % #variants + 1]
end
function Analytics.Variant(player: Player, name: string): string?
	return experimentVariant(player, name)
end

local function bestRarity(knives: { string }): number
	local best = 0
	for _, item in knives do
		local parsed = Items.Parse(item)
		local rank = parsed and parsed.Knife and table.find(Knives.Rarities, parsed.Knife.Rarity) or 0
		if rank > best then
			best = rank
		end
	end
	return best
end

-- The player's whole state, attached to every event (the "every variable" part)
-- Key events carry everything; the rest a compact core (the server keeps device and source on the
-- session, so those are always one join away)
local FULL_EVENTS = {
	["session.start"] = true,
	["session.heartbeat"] = true,
	["session.end"] = true,
	["milestone"] = true,
	["purchase.product"] = true,
	["purchase.pass"] = true,
	["round.end"] = true,
	["rebirth"] = true,
}

local function compact(player: Player): { [string]: any }
	local session = sessions[player]
	local profile = DataService.Get(player)
	local income = (player:GetAttribute("Income") or 0) :: number
	return {
		session_s = if session then math.floor(os.clock() - session.Started) else nil,
		session_n = if session then session.Number else nil,
		zone = if session then session.Zone else nil,
		rebirths = if profile then profile.Rebirths else nil,
		cash_mag = if profile then bucket(profile.Cash) else nil,
		income_mag = bucket(income),
		knives = if profile then #profile.Knives else nil,
		best_rarity = if profile then bestRarity(profile.Knives) else nil,
		speed_reach = if profile then GameConfig.RarityReached(profile.Speed) else nil,
		tutorial_done = if profile then profile.TutorialDone else nil,
		payer = if profile then profile.RobuxSpent > 0 else nil,
		power_level = player:GetAttribute("PowerLevel"),
		in_round = player:GetAttribute("InRound") == true,
		carrying = player:GetAttribute("Carrying") ~= nil and player:GetAttribute("Carrying") ~= false,
		phase = ReplicatedStorage:GetAttribute("Phase"),
	}
end

local function context(player: Player): { [string]: any }
	local session = sessions[player]
	local profile = DataService.Get(player)
	local props: { [string]: any } = {
		place_version = game.PlaceVersion,
		server_players = #Players:GetPlayers(),
		studio = isStudio() or nil,
		phase = ReplicatedStorage:GetAttribute("Phase"),
	}
	if session then
		props.session_s = math.floor(os.clock() - session.Started)
		props.session_n = session.Number
		props.zone = session.Zone
		for key, value in session.Device do
			props[key] = value
		end
		for key, value in session.Source do
			props[key] = value
		end
		props.robux_session = session.Robux
	end
	if profile then
		local first = profile.FirstSeen
		props.days_since_first = if first > 0 then math.floor((os.time() - first) / 86400) else 0
		props.playtime_min = math.floor(profile.PlayTime / 60)
		props.rebirths = profile.Rebirths
		props.cash = finite(profile.Cash)
		props.cash_mag = bucket(profile.Cash)
		local income = (player:GetAttribute("Income") or 0) :: number
		props.income = finite(income)
		props.income_mag = bucket(income)
		props.knives = #profile.Knives
		props.slots = profile.Slots
		props.best_rarity = bestRarity(profile.Knives)
		props.speed = math.floor(profile.Speed)
		props.speed_reach = GameConfig.RarityReached(profile.Speed)
		props.heat = profile.Heat
		props.health_level = profile.HealthLevel
		props.trail_level = profile.TrailLevel
		props.tutorial_done = profile.TutorialDone
		props.tutorial_step = profile.TutorialStep
		props.cases_opened = profile.CasesOpened
		props.kills_total = profile.TotalKills
		props.wins_total = profile.RoundsWon
		props.daily_streak = profile.DailyStreak
		props.robux_total = profile.RobuxSpent
		props.payer = profile.RobuxSpent > 0
		props.luck = profile.Luck
	end
	props.power = player:GetAttribute("PowerId")
	props.power_level = player:GetAttribute("PowerLevel")
	props.in_round = player:GetAttribute("InRound") == true
	props.carrying = player:GetAttribute("Carrying") ~= nil and player:GetAttribute("Carrying") ~= false
	props.training = player:GetAttribute("Training") == true
	props.shielded = player:GetAttribute("Shielded") == true
	for name in EXPERIMENTS do
		props["ab_" .. name] = experimentVariant(player, name)
	end
	return props
end

local function push(event: { [string]: any })
	table.insert(recent, event)
	if #recent > 400 then
		table.remove(recent, 1)
	end
	if ReplicatedStorage:GetAttribute("DebugAnalytics") then
		print(`[Analytics] {event.event} {HttpService:JSONEncode(event.props)}`)
	end
	if URL == "" or (isStudio() and not SEND_IN_STUDIO) then
		return
	end
	table.insert(queue, event)
	if #queue > MAX_QUEUE then
		table.remove(queue, 1) -- the endpoint's been down a while: lose the oldest, not the server
	end
end

-- One event. `props` are the event's own fields; the player's state is added to them.
function Analytics.Track(player: Player?, name: string, props: { [string]: any }?)
	local properties: { [string]: any } = if player
		then (if FULL_EVENTS[name] then context(player) else compact(player))
		else {
			place_version = game.PlaceVersion,
			server_players = #Players:GetPlayers(),
			studio = isStudio() or nil,
		}
	if props then
		for key, value in props do
			if type(value) == "number" then
				value = finite(value)
			end
			properties[key] = value
		end
	end
	local session = player and sessions[player]
	if session and name ~= "session.heartbeat" and name ~= "economy.flow" then
		session.Last, session.LastAt = name, os.clock()
	end
	push({
		event = name,
		player = if player then Analytics.IdOf(player.UserId) else "server",
		session = if session then session.Id else nil,
		server = string.sub(game.JobId, 1, 8),
		studio = isStudio() or nil,
		ts = DateTime.now():ToIsoDate(),
		props = properties,
	})
end

-- A first-time-ever moment (first steal, first round, zone 3 reached...): logged once per player
-- for good, with how long it took (play time) - the backbone of the onboarding funnel
function Analytics.Milestone(player: Player, name: string, props: { [string]: any }?)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local firsts = profile.Firsts
	if firsts[name] then
		return
	end
	firsts[name] = profile.PlayTime
	local fields: { [string]: any } = { milestone = name, playtime_s = profile.PlayTime }
	if props then
		for key, value in props do
			fields[key] = value
		end
	end
	Analytics.Track(player, "milestone", fields)
	local step = ONBOARDING_INDEX[name]
	if step then
		pcall(function()
			AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
		end)
	end
end

-- Money in (+) or out (-), summed per reason and sent with each heartbeat (DataService calls this
-- for every AddCash / TrySpend that names a reason)
function Analytics.Cash(player: Player, amount: number, reason: string?)
	local session = sessions[player]
	if not session or amount == 0 or amount ~= amount then
		return
	end
	local key = reason or (if amount > 0 then "other_in" else "other_out")
	session.Flow[key] = (session.Flow[key] or 0) + amount
	if amount > 0 then
		session.Earned += amount
	else
		session.Spent -= amount
	end
end

-- Per-second actions (shots, stabs, throws): just counted, sent with the heartbeat
function Analytics.Count(player: Player, name: string, n: number?)
	local session = sessions[player]
	if session then
		session.Counts[name] = (session.Counts[name] or 0) + (n or 1)
	end
end

function Analytics.Robux(player: Player, robux: number)
	local session = sessions[player]
	if session then
		session.Robux += robux
	end
	DataService.Update(player, function(p)
		p.RobuxSpent += robux
	end)
end

local function short(value: any): any
	if type(value) == "string" then
		return value:sub(1, 48)
	elseif type(value) == "number" then
		return finite(value)
	elseif type(value) == "boolean" then
		return value
	elseif typeof(value) == "EnumItem" then
		return tostring(value)
	end
	return nil
end

-- Wraps a RemoteFunction handler: every request a client makes is an "action.<Name>" event with
-- what they asked for and what the server answered (the failure messages are where people get
-- stuck). `args` = how many arguments to log (default 2).
function Analytics.Remote(name: string, handler: (Player, ...any) -> ...any, args: number?): (Player, ...any) -> ...any
	local count = args or 2
	return function(player: Player, ...: any): ...any
		local results = table.pack(handler(player, ...))
		local input = table.pack(...)
		local props: { [string]: any } = {}
		for i = 1, math.min(count, input.n) do
			props["arg" .. i] = short(input[i])
		end
		local first = results[1]
		if type(first) == "boolean" then
			props.ok = first
		elseif first ~= nil then
			props.ok = true
		end
		if type(results[2]) == "string" then
			props.reply = normalize(results[2])
		end
		Analytics.Track(player, "action." .. name, props)
		return table.unpack(results, 1, results.n)
	end
end

-- Client-side events (Remotes.Track): only these names, only these fields, rate limited
local CLIENT_EVENTS: { [string]: { string } } = {
	["client.device"] = {
		"touch",
		"keyboard",
		"mouse",
		"gamepad",
		"vr",
		"phone",
		"screen_w",
		"screen_h",
		"quality",
		"locale",
	},
	["client.loaded"] = { "seconds", "first_frame" },
	["ui.menu"] = { "menu", "seconds" },
	["ui.click"] = { "button", "menu" },
	["store.prompt"] = { "kind", "key", "source", "menu" },
	["store.result"] = { "kind", "key", "bought", "seconds" },
	["offer.click"] = { "key" },
	["offer.close"] = { "key", "seconds", "how" },
	["offer.blocked"] = { "key", "why" },
	["perf"] = { "fps", "fps_min", "ping", "memory", "quality" },
	["tip.shown"] = { "tip" },
	["spectate"] = { "on" },
	["shiftlock"] = { "on" },
	["tutorial.replay"] = {},
	["round.intro"] = { "seconds" },
	["welcome.close"] = { "seconds", "claimed" },
	["favorite.prompt"] = { "result" }, -- (asked after your first knife lands on your wall)
	["goal.shown"] = { "kind", "zone" }, -- the "Next:" line once the tutorial is done
	-- The guide's DO line (client/Guide): what it asked, how long until it changed, and where players
	-- sat on one instruction for a minute without moving (confusion)
	["guide.shown"] = { "id", "zone" },
	["guide.done"] = { "id", "seconds" },
	["guide.stuck"] = { "id" },
}
local DEVICE_KEYS = { "touch", "keyboard", "mouse", "gamepad", "vr", "phone", "screen_w", "screen_h", "quality" }

local function onClientEvent(player: Player, name: unknown, props: unknown)
	local session = sessions[player]
	if not session or type(name) ~= "string" then
		return
	end
	local allowed = CLIENT_EVENTS[name]
	if not allowed then
		return
	end
	local now = os.clock()
	local rate = session.Rate
	while rate[1] and now - rate[1] > 10 do
		table.remove(rate, 1)
	end
	if #rate >= 40 then
		return
	end
	table.insert(rate, now)
	local clean: { [string]: any } = {}
	if type(props) == "table" then
		for _, key in allowed do
			local value = short((props :: any)[key])
			if value ~= nil then
				clean[key] = value
			end
		end
	end
	if name == "client.device" then
		-- remembered for the session: rides on every later event as device fields
		for _, key in DEVICE_KEYS do
			session.Device["device_" .. key] = clean[key]
		end
		session.Device.platform = if clean.vr
			then "vr"
			elseif clean.gamepad and not clean.keyboard then "console"
			elseif clean.touch and not clean.keyboard then (if clean.phone then "phone" else "tablet")
			else "pc"
		clean.platform = session.Device.platform
	end
	Analytics.Track(player, name, clean)
end

-- Where are they? 0 = the plaza / vaults, 1..8 = a biome, -1 = in a round
local function zoneOf(player: Player): number
	if player:GetAttribute("InRound") then
		return -1
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return 0
	end
	for _, zone in MapService.Zones do
		if MapService.InBounds(zone.Bounds, root.Position) then
			return zone.Index
		end
	end
	return 0
end

local function stepZones()
	local now = os.clock()
	for player, session in sessions do
		local zone = zoneOf(player)
		if zone ~= session.Zone then
			session.ZoneTime[session.Zone] = (session.ZoneTime[session.Zone] or 0) + (now - session.ZoneSince)
			local from = session.Zone
			session.Zone, session.ZoneSince = zone, now
			if zone > 0 then
				Analytics.Track(player, "zone.enter", { from = from, to = zone })
				Analytics.Milestone(player, "zone_" .. zone)
			end
		end
	end
end

local function zoneSeconds(session: Session): { [string]: number }
	local out = {}
	local now = os.clock()
	for zone, seconds in session.ZoneTime do
		out["time_zone_" .. (if zone < 0 then "round" elseif zone == 0 then "hub" else tostring(zone))] =
			math.floor(seconds)
	end
	local key = "time_zone_"
		.. (if session.Zone < 0 then "round" elseif session.Zone == 0 then "hub" else tostring(session.Zone))
	out[key] = (out[key] or 0) + math.floor(now - session.ZoneSince)
	return out
end

local function heartbeat(player: Player, session: Session)
	local props: { [string]: any } = {}
	for key, value in session.Counts do
		props["n_" .. key] = value
	end
	table.clear(session.Counts)
	Analytics.Track(player, "session.heartbeat", props)
	if next(session.Flow) then
		local flow: { [string]: any } = {}
		for reason, amount in session.Flow do
			flow[(if amount >= 0 then "in_" else "out_") .. reason] = math.abs(amount)
		end
		table.clear(session.Flow)
		Analytics.Track(player, "economy.flow", flow)
	end
end

local function sourceOf(player: Player): { [string]: any }
	local ok, join = pcall(function()
		return player:GetJoinData()
	end)
	local source: { [string]: any } = {}
	if ok and type(join) == "table" then
		local data = join :: any
		local launch = data.LaunchData
		-- Ad / share links: roblox.com/games/start?placeId=...&launchData=utm_source%3Dmeta%26utm_campaign%3Dx
		if type(launch) == "string" and launch ~= "" then
			for key, value in string.gmatch(launch :: string, "([%w_]+)=([^&]*)") do
				if (key :: string):sub(1, 4) == "utm_" or key == "ref" then
					source[key :: string] = (value :: string):sub(1, 48)
				end
			end
			if not next(source) then
				source.launch = launch:sub(1, 48)
			end
		end
		if data.ReferredByPlayerId and data.ReferredByPlayerId ~= 0 then
			source.referred = true
		end
		if data.SourcePlaceId and data.SourcePlaceId ~= 0 then
			source.from_place = data.SourcePlaceId
		end
	end
	if player.FollowUserId ~= 0 then
		source.followed_friend = true
	end
	return source
end

local function onLoaded(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local p = profile
	local firstSession = p.Sessions == 0
	local sinceLast = if p.LastSeen > 0 then os.time() - p.LastSeen else nil
	DataService.Update(player, function(d)
		d.Sessions += 1
		if d.FirstSeen == 0 then
			d.FirstSeen = os.time()
		end
	end)
	local source = sourceOf(player)
	-- First touch sticks for life (which ad / link brought them in the first time)
	if firstSession and next(source) then
		DataService.Update(player, function(data)
			data.Source = HttpService:JSONEncode(source)
		end)
	end
	local firstTouch = {}
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, p.Source)
	if ok and type(decoded) == "table" then
		for key, value in decoded do
			firstTouch["first_" .. key] = value
		end
	end
	for key, value in source do
		firstTouch[key] = value
	end
	sessions[player] = {
		Id = `{Analytics.IdOf(player.UserId):sub(1, 8)}-{string.format("%x", os.time())}`,
		Started = os.clock(),
		StartedAt = os.time(),
		Number = p.Sessions,
		Device = {},
		Zone = 0,
		ZoneSince = os.clock(),
		ZoneTime = {},
		Flow = {},
		Earned = 0,
		Spent = 0,
		Robux = 0,
		Counts = {},
		Last = "session.start",
		LastAt = os.clock(),
		Friction = {},
		Source = firstTouch,
		Rate = {},
		KnivesHome = 0,
	}
	Analytics.Track(player, "session.start", {
		new_user = firstSession,
		hours_away = if sinceLast then math.floor(sinceLast / 360) / 10 else nil,
		friends_here = player:GetAttribute("FriendsHere"),
	})
	Analytics.Milestone(player, "joined")
	if p.Sessions >= 2 then
		Analytics.Milestone(player, "session_2")
	end
	if p.Sessions >= 5 then
		Analytics.Milestone(player, "session_5")
	end
	player.CharacterAdded:Connect(function()
		Analytics.Milestone(player, "spawned")
	end)
	if player.Character then
		Analytics.Milestone(player, "spawned")
	end
end

local function onRemoving(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	heartbeat(player, session)
	local props: { [string]: any } = zoneSeconds(session)
	props.seconds = math.floor(os.clock() - session.Started)
	props.earned = session.Earned
	props.spent = session.Spent
	props.robux = session.Robux
	props.knives_home = session.KnivesHome
	props.last_event = session.Last
	props.last_event_ago = math.floor(os.clock() - session.LastAt)
	Analytics.Track(player, "session.end", props)
	sessions[player] = nil
end

-- The secret from Creator Hub (a Secret can only go into headers / the URL, which is all we need)
local secret: any = nil
local function auth(): any
	if secret == nil then
		local ok, value = pcall(function()
			return (HttpService :: any):GetSecret(SECRET_NAME)
		end)
		secret = if ok and value then value else KEY
	end
	return secret
end

local function send(batch: { any }): boolean
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = URL,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json", ["X-Ingest-Key"] = auth() },
			Body = HttpService:JSONEncode({ batch = batch }),
		})
	end)
	return ok and (response :: any).Success == true
end

local failures = 0
local function flush()
	if sending or #queue == 0 then
		return
	end
	sending = true
	local batch = {}
	for i = 1, math.min(MAX_BATCH, #queue) do
		batch[i] = queue[i]
	end
	if send(batch) then
		for _ = 1, #batch do
			table.remove(queue, 1)
		end
		failures = 0
	else
		failures += 1
		if failures == 1 or failures % 30 == 0 then
			warn(`[Analytics] sending failed ({#queue} events waiting) - is HTTP enabled and the URL right?`)
		end
	end
	sending = false
end

-- For DebugService: the last events (newest last)
function Analytics.Recent(n: number?): { any }
	local out = {}
	local count = math.min(n or 50, #recent)
	for i = #recent - count + 1, #recent do
		table.insert(out, recent[i])
	end
	return out
end

function Analytics.Init()
	-- Every "bad" message a player gets is a moment they were stopped from doing something
	Net.SetNotifyHook(function(player: Player, text: string, kind: string)
		if kind ~= "bad" then
			return
		end
		local session = sessions[player]
		if not session then
			return
		end
		local message = normalize(text)
		local now = os.clock()
		if now - (session.Friction[message] or -60) < 8 then
			return
		end
		session.Friction[message] = now
		Analytics.Track(player, "notify.bad", { message = message })
	end)
	DataService.SetCashHook(Analytics.Cash)
	Net.Remotes.Track.OnServerEvent:Connect(onClientEvent)

	-- Fire-and-forget remotes worth counting
	Net.Remotes.Shoot.OnServerEvent:Connect(function(player)
		Analytics.Count(player, "shots")
	end)
	Net.Remotes.Stab.OnServerEvent:Connect(function(player)
		Analytics.Count(player, "stabs")
	end)
	Net.Remotes.Ability.OnServerEvent:Connect(function(player)
		Analytics.Count(player, if player:GetAttribute("InRound") then "round_abilities" else "hub_throws")
	end)
	Net.Remotes.UsePower.OnServerEvent:Connect(function(player, id)
		Analytics.Track(player, "power.use", { id = short(id) })
	end)
	Net.Remotes.SlowMode.OnServerEvent:Connect(function(player, on)
		Analytics.Track(player, "setting.slow", { on = on == true })
	end)
	Net.Remotes.TeamUp.OnServerEvent:Connect(function(player, action)
		Analytics.Track(player, "social.teamup", { action = short(action) })
	end)
	Net.Remotes.Tutorial.OnServerEvent:Connect(function(player, step, at)
		if step == "Step" and type(at) == "number" and at == at then
			local n = math.clamp(math.floor(at), 1, 10)
			Analytics.Track(player, "tutorial.step", { step = n })
			Analytics.Milestone(player, "tutorial_" .. n)
		elseif step == "Done" or step == "Skip" then
			Analytics.Track(player, "tutorial." .. string.lower(step))
			Analytics.Milestone(player, if step == "Done" then "tutorial_done" else "tutorial_skipped")
		elseif step == "Tip" and type(at) == "string" then
			Analytics.Track(player, "tip.shown", { tip = at:sub(1, 24) })
		end
	end)

	DataService.PlayerLoaded:Connect(onLoaded)
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("DataLoaded") then
			task.spawn(onLoaded, player)
		end
	end
	Players.PlayerRemoving:Connect(onRemoving)

	task.spawn(function()
		local sinceBeat = 0
		while true do
			task.wait(1)
			stepZones()
			sinceBeat += 1
			if sinceBeat >= HEARTBEAT_EVERY then
				sinceBeat = 0
				for player, session in sessions do
					heartbeat(player, session)
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(FLUSH_EVERY)
			flush()
		end
	end)
	game:BindToClose(function()
		for player in sessions do
			onRemoving(player)
		end
		local started = os.clock()
		while #queue > 0 and os.clock() - started < 20 do
			sending = false
			local before = #queue
			flush()
			if #queue == before then
				break
			end
		end
	end)
end

return Analytics
