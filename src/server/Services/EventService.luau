--!strict
-- Weekly events (PLAN item 25, Config/Events). Every server works out the Saturday slot from the
-- clock by itself (no one has to be online); the owner's "/event <kind> [minutes]" chat command
-- starts one now on every server (MessagingService), "/event stop" ends it. State goes on
-- ReplicatedStorage attributes: EventKind / EventEndsAt (os.time) for the running one,
-- NextEventKind / NextEventAt for the events board's countdown, and the running kind's multiplier
-- attribute (Config/Events Channel: RoundSpeedMultiplier, MutationLuckMultiplier, CashMultiplier).

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config.Events)
local Net = require(script.Parent.Parent.Remotes)
local Analytics = require(script.Parent.Analytics)

local EventService = {}

local TOPIC = "AdminEvent"
local GOLD = Color3.fromRGB(255, 215, 80)

-- Admin override (from /event on any server): kind + when it ends (os.time)
local override: { Kind: string?, EndsAt: number }? = nil

-- Calendar maths in whole days since 1970-01-01 (H. Hinnant's civil-date algorithms): Luau has
-- no time zones, so US Eastern daylight saving is worked out here
local function daysFromCivil(y: number, m: number, d: number): number
	y = if m <= 2 then y - 1 else y
	local era = (if y >= 0 then y else y - 399) // 400
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = (153 * mp + 2) // 5 + d - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return era * 146097 + doe - 719468
end

local function civilFromDays(z: number): (number, number, number)
	z += 719468
	local era = (if z >= 0 then z else z - 146096) // 146097
	local doe = z - era * 146097
	local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
	local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
	local mp = (5 * doy + 2) // 153
	local d = doy - (153 * mp + 2) // 5 + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	local y = yoe + era * 400
	return (if m <= 2 then y + 1 else y), m, d
end

local function weekday(days: number): number -- 1 = Sunday .. 7 = Saturday (os.date's wday)
	return (days + 4) % 7 + 1
end

-- The n-th Sunday of a month (as a day number)
local function nthSunday(y: number, m: number, n: number): number
	local first = daysFromCivil(y, m, 1)
	return first + (8 - weekday(first)) % 7 + (n - 1) * 7
end

-- US Eastern is UTC-4 from the 2nd Sunday of March to the 1st Sunday of November, else UTC-5
-- (the slot is mid-afternoon, so the 2 AM switch never matters)
local function easternOffsetHours(days: number): number
	local y = civilFromDays(days)
	local dst = days >= nthSunday(y, 3, 2) and days < nthSunday(y, 11, 1)
	return if dst then -4 else -5
end

-- The weekly slot on a given day (or nil if it isn't the slot's weekday): start (os.time), kind
local function slotOn(days: number): (number?, string?)
	if weekday(days) ~= Config.Weekly.Weekday then
		return nil, nil
	end
	local start = days * 86400 + (Config.Weekly.Hour - easternOffsetHours(days)) * 3600 + Config.Weekly.Minute * 60
	local kind = Config.Order[(days // 7) % #Config.Order + 1]
	return start, kind
end

-- (running kind?, ends at, next kind, next start)
local function schedule(now: number): (string?, number, string, number)
	local today = now // 86400
	local running: string?, endsAt = nil, 0
	local nextKind, nextAt = Config.Order[1], math.huge
	for d = today - 1, today + 8 do
		local start, kind = slotOn(d)
		if start and kind then
			local finish = start + Config.Weekly.Minutes * 60
			if now >= start and now < finish then
				running, endsAt = kind, finish
			elseif start > now and start < nextAt then
				nextKind, nextAt = kind, start
			end
		end
	end
	if override and override.EndsAt > now then
		if override.Kind then
			running, endsAt = override.Kind, override.EndsAt
		else
			running, endsAt = nil, 0 -- "/event stop" also holds off the weekly one for a while
		end
	end
	return running, endsAt, nextKind, nextAt
end

local lastKind: string? = nil
local warned = 0

local function tick()
	local now = os.time()
	local kind, endsAt, nextKind, nextAt = schedule(now)
	ReplicatedStorage:SetAttribute("EventKind", kind)
	ReplicatedStorage:SetAttribute("EventEndsAt", if kind then endsAt else nil)
	ReplicatedStorage:SetAttribute("NextEventKind", nextKind)
	ReplicatedStorage:SetAttribute("NextEventAt", if nextAt < math.huge then nextAt else nil)
	for key, def in Config.Kinds do
		ReplicatedStorage:SetAttribute(def.Channel, if key == kind then def.Multiplier else nil)
	end
	if kind ~= lastKind then
		if kind then
			local def = Config.Kinds[kind]
			Net.Announce(`{def.Title} ({math.ceil((endsAt - now) / 60)} min)`, GOLD, 3)
			Analytics.Track(nil, "event.start", { kind = kind, players = #Players:GetPlayers() })
		elseif lastKind then
			Net.Announce("The event is over. See you Saturday!", GOLD, 1)
		end
		lastKind = kind
	end
	local warnAt = nextAt - Config.WarnMinutes * 60
	if not kind and now >= warnAt and now < nextAt and warned ~= nextAt then
		warned = nextAt
		local def = Config.Kinds[nextKind]
		Net.Announce(`In {Config.WarnMinutes} minutes: {def.Title}`, GOLD, 2)
	end
end

local function apply(data: any)
	if type(data) ~= "table" or type(data.EndsAt) ~= "number" then
		return
	end
	local kind = data.Kind
	if kind ~= nil and (type(kind) ~= "string" or not Config.Kinds[kind]) then
		return
	end
	override = { Kind = kind, EndsAt = data.EndsAt }
	tick()
end

local function isAdmin(player: Player): boolean
	return player.UserId > 0 and table.find(Config.AdminUserIds, player.UserId) ~= nil
end

-- "/event golden 30", "/event luck", "/event stop"
local function onChat(player: Player, message: string)
	local words = string.split(string.lower(message), " ")
	if words[1] ~= "/event" or not isAdmin(player) then
		return
	end
	local now = os.time()
	local data
	if words[2] == "stop" then
		data = { EndsAt = now + Config.MaxAdminMinutes * 60 }
	else
		local kind: string? = nil
		for key in Config.Kinds do
			if string.lower(key) == words[2] then
				kind = key
			end
		end
		if not kind then
			Net.Notify(player, "Try: /event golden 30, /event luck, /event cash, /event stop", "info")
			return
		end
		local minutes = math.clamp(tonumber(words[3]) or 30, 1, Config.MaxAdminMinutes)
		data = { Kind = kind, EndsAt = now + math.floor(minutes * 60) }
	end
	Analytics.Track(player, "event.admin", { kind = data.Kind or "stop" })
	apply(data)
	local ok, err = pcall(MessagingService.PublishAsync, MessagingService, TOPIC, data)
	if not ok and not RunService:IsStudio() then
		warn(`[EventService] couldn't tell the other servers: {err}`)
	end
	Net.Notify(player, if data.Kind then `Started {data.Kind} on every server.` else "Event stopped.", "good")
end

function EventService.Init()
	local function watch(player: Player)
		player.Chatted:Connect(function(message)
			onChat(player, message)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	task.spawn(function()
		local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, function(message)
			apply(message.Data)
		end)
		if not ok and not RunService:IsStudio() then
			warn(`[EventService] no cross-server events: {err}`)
		end
	end)
	task.spawn(function()
		while true do
			tick()
			task.wait(5)
		end
	end)
end

-- (for tests: the weekly schedule at a given time)
EventService.Schedule = schedule

return EventService
