--!strict
-- Player funnel and "why did they leave" telemetry, on Roblox's own AnalyticsService (so it
-- shows up in Creator Hub > Analytics, free, with no external server).
--
--   * First-session funnel (FTUE): nine steps from joining to finishing the guide, each logged once
--     per player ever (profile.Funnel remembers them), with the player's lifetime play time when
--     they got there, so "how long to the first knife on a plate" is a number, not a feeling.
--   * Loop events: steals (started / caught / deposited), round results, looted, robbed, upgrades,
--     blocked-by-cash, offers shown, Robux purchases and cancelled prompts.
--   * Session end, with the last bad thing that happened to them and how long before they left:
--     the closest thing to a reason a server can know ("robbed_30s" = left within 30s of a robbery).
--
-- Everything is server-side, counts only (no chat, no names), and wrapped so a telemetry error can
-- never break the game. See docs/ANALYTICS.md for every event and how to read it.

local AnalyticsService = game:GetService("AnalyticsService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local DataService = require(script.Parent.DataService)
local Net = require(script.Parent.Parent.Remotes)

local Analytics = {}

-- The first-session funnel, in the order a new player normally meets it
local STEPS = {
	"joined",
	"grabbed_knife",
	"placed_knife",
	"collected_cash",
	"trained_speed",
	"entered_round",
	"finished_round",
	"bought_upgrade",
	"guide_finished",
}
local STEP_INDEX: { [string]: number } = {}
for index, key in STEPS do
	STEP_INDEX[key] = index
end
Analytics.Steps = STEPS

local FIELD_1 = Enum.AnalyticsCustomFieldKeys.CustomField01.Name
local FIELD_2 = Enum.AnalyticsCustomFieldKeys.CustomField02.Name
local FIELD_3 = Enum.AnalyticsCustomFieldKeys.CustomField03.Name

local MAX_EVENTS_PER_MINUTE = 90 -- per player; telemetry must never become the load
local MAX_FIELD_LENGTH = 40

local joinedAt: { [Player]: number } = {}
local stepsDone: { [Player]: number } = {}
local roundsThisSession: { [Player]: number } = {}
local enteredRoundAt: { [Player]: number } = {}
local lastRoundSeconds: { [Player]: number } = {}
local lastNegative: { [Player]: { Kind: string, At: number } } = {}
local window: { [Player]: { Start: number, Count: number } } = {}
local warned = false

local function debugging(): boolean
	return ReplicatedStorage:GetAttribute("DebugAnalytics") == true
end

local function safely(fn: () -> ...any)
	local ok, err = pcall(fn)
	if not ok and not warned then
		warned = true
		warn(`[Analytics] telemetry call failed (further failures are silent): {err}`)
	end
end

local function clip(text: string): string
	return string.sub(text, 1, MAX_FIELD_LENGTH)
end

local function allowed(player: Player): boolean
	local now = os.clock()
	local entry = window[player]
	if not entry or now - entry.Start > 60 then
		window[player] = { Start = now, Count = 1 }
		return true
	end
	entry.Count += 1
	return entry.Count <= MAX_EVENTS_PER_MINUTE
end

-- One custom event: a name, a number, and up to three short labels
function Analytics.Event(player: Player, name: string, value: number?, f1: string?, f2: string?, f3: string?)
	if not allowed(player) then
		return
	end
	local fields: { [string]: any } = {}
	if f1 then
		fields[FIELD_1] = clip(f1)
	end
	if f2 then
		fields[FIELD_2] = clip(f2)
	end
	if f3 then
		fields[FIELD_3] = clip(f3)
	end
	if debugging() then
		print(`[Analytics] {name} value={value} | {f1 or ""} | {f2 or ""} | {f3 or ""}`)
	end
	safely(function()
		AnalyticsService:LogCustomEvent(player, name, value, if next(fields) then fields else nil)
	end)
end

-- Something bad happened to them: remembered, so session_end can say "left right after X"
function Analytics.Negative(player: Player, kind: string)
	lastNegative[player] = { Kind = kind, At = os.clock() }
end

-- A funnel step, once per player ever. `value` = their lifetime play time (seconds) when they got there.
function Analytics.Step(player: Player, key: string)
	local index = STEP_INDEX[key]
	local profile = DataService.Get(player)
	if not index or not profile or table.find(profile.Funnel, key) then
		return
	end
	DataService.Update(player, function(p)
		table.insert(p.Funnel, key)
	end)
	stepsDone[player] = #profile.Funnel
	safely(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, index, key)
	end)
	Analytics.Event(player, "ftue_step", profile.PlayTime, key, `{#profile.Funnel}/{#STEPS}`)
end

-- Steals: outcome "started" | "caught" | "deposited"; source "boss1".."boss8" | "raid" | "case"
function Analytics.Steal(player: Player, outcome: string, source: string, rarity: string?)
	Analytics.Event(player, "steal", nil, outcome, source, rarity)
	if outcome == "caught" then
		Analytics.Negative(player, "boss_caught")
	end
end

function Analytics.Robbed(owner: Player, rarity: string)
	local profile = DataService.Get(owner)
	Analytics.Event(owner, "robbed", nil, rarity, `walls{if profile then profile.WallLevel else 0}`)
	Analytics.Negative(owner, "robbed")
end

-- A knife taken in a round: returned (the Murderer was stopped) or kept
function Analytics.Looted(owner: Player, returned: boolean)
	Analytics.Event(owner, "looted", nil, if returned then "returned" else "kept")
	if not returned then
		Analytics.Negative(owner, "looted")
	end
end

function Analytics.Upgrade(player: Player, kind: string)
	Analytics.Event(player, "upgrade", nil, kind)
	Analytics.Step(player, "bought_upgrade")
end

-- Not enough cash for something they tried to buy: how far off they were is the pacing question
function Analytics.Blocked(player: Player, kind: string, cost: number, cash: number)
	local ratio = if cash > 0 then cost / cash else math.huge
	Analytics.Event(
		player,
		"blocked_cash",
		nil,
		kind,
		if ratio < 2 then "<2x" elseif ratio < 10 then "<10x" else "10x+"
	)
	Analytics.Negative(player, "short_cash")
end

local function reasonShape(reason: string): string
	-- "Only 1.2K short?..." -> "Only N short?..." so the number does not make every offer unique
	return (string.gsub(reason, "%d[%d%.,]*%a*", "N"))
end

function Analytics.Offer(player: Player, key: string, reason: string)
	Analytics.Event(player, "offer_shown", nil, key, reasonShape(reason))
end

-- A Robux purchase that was granted (kind "product" | "pass")
function Analytics.Purchased(player: Player, key: string, price: number, kind: string)
	Analytics.Event(player, "robux_purchase", price, key, kind)
end

-- A round's result for every real player in it
export type RoundSummary = {
	Innocents: { Player },
	Killers: { [Player]: boolean },
	Alive: { [Player]: boolean },
	InnocentsWon: boolean,
	Classic: boolean,
	Double: boolean,
}

function Analytics.RoundEnded(summary: RoundSummary)
	local mode = if summary.Classic then "classic" elseif summary.Double then "double" else "normal"
	local function seconds(player: Player): number
		local entered = enteredRoundAt[player]
		if entered then
			return os.clock() - entered
		end
		return lastRoundSeconds[player] or 0
	end
	for _, player in summary.Innocents do
		if player.Parent then
			local survived = summary.Alive[player] == true
			Analytics.Event(
				player,
				"round_result",
				seconds(player),
				"innocent",
				if survived then "survived" else "died",
				mode
			)
			if not survived then
				Analytics.Negative(player, "died_round")
			end
			Analytics.Step(player, "finished_round")
		end
	end
	for player in summary.Killers do
		if player.Parent then
			Analytics.Event(
				player,
				"round_result",
				seconds(player),
				"murderer",
				if summary.InnocentsWon then "lost" else "won",
				mode
			)
			Analytics.Step(player, "finished_round")
		end
	end
end

local function sessionEnd(player: Player)
	local started = joinedAt[player]
	if started then
		local now = os.clock()
		local last = lastNegative[player]
		local clue = "none"
		if last then
			local ago = now - last.At
			clue = `{last.Kind}_{if ago < 30 then "30s" elseif ago < 120 then "2m" else "older"}`
		end
		Analytics.Event(
			player,
			"session_end",
			now - started,
			clue,
			`{stepsDone[player] or 0}/{#STEPS}`,
			`rounds{roundsThisSession[player] or 0}`
		)
	end
	joinedAt[player] = nil
	stepsDone[player] = nil
	roundsThisSession[player] = nil
	enteredRoundAt[player] = nil
	lastRoundSeconds[player] = nil
	lastNegative[player] = nil
	window[player] = nil
end

local function onLoaded(player: Player, profile: DataService.Profile)
	joinedAt[player] = os.clock()
	stepsDone[player] = #profile.Funnel
	roundsThisSession[player] = 0
	-- New, or back after N days away (0 for a first visit)
	local away = DataService.AwaySince[player] or 0
	local days = if away > 0 then math.floor((os.time() - away) / 86400) else 0
	Analytics.Event(
		player,
		"session_start",
		days,
		if profile.PlayTime == 0 then "new" else "returning",
		`rebirths{profile.Rebirths}`
	)
	Analytics.Step(player, "joined")

	player:GetAttributeChangedSignal("Carrying"):Connect(function()
		if player:GetAttribute("Carrying") ~= nil then
			Analytics.Step(player, "grabbed_knife")
		end
	end)
	player:GetAttributeChangedSignal("Training"):Connect(function()
		if player:GetAttribute("Training") == true then
			Analytics.Step(player, "trained_speed")
		end
	end)
	player:GetAttributeChangedSignal("InRound"):Connect(function()
		if player:GetAttribute("InRound") then
			enteredRoundAt[player] = os.clock()
			roundsThisSession[player] = (roundsThisSession[player] or 0) + 1
			Analytics.Step(player, "entered_round")
		else
			local entered = enteredRoundAt[player]
			if entered then
				lastRoundSeconds[player] = os.clock() - entered
				enteredRoundAt[player] = nil
			end
		end
	end)
end

function Analytics.Init()
	DataService.PlayerLoaded:Connect(onLoaded)
	Players.PlayerRemoving:Connect(sessionEnd)

	-- The guide moved on: "Done" or "Skip" (anything else is a client step we do not log)
	Net.Remotes.Tutorial.OnServerEvent:Connect(function(player: Player, step: unknown)
		if step == "Done" or step == "Skip" then
			local profile = DataService.Get(player)
			Analytics.Event(player, "guide", if profile then profile.PlayTime else nil, step :: string)
			Analytics.Step(player, "guide_finished")
		end
	end)

	-- A Robux prompt closed without a purchase: the price (or the moment) said no. Granted
	-- purchases are logged where they are granted (MonetizationService), once.
	local productKeys: { [number]: string } = {}
	for _, product in Monetization.Products do
		if product.Id ~= 0 then
			productKeys[product.Id] = product.Key
		end
	end
	local passKeys: { [number]: string } = {}
	for _, pass in Monetization.Passes do
		if pass.Id ~= 0 then
			passKeys[pass.Id] = pass.Key
		end
	end
	MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, productId: number, purchased: boolean)
			local player = Players:GetPlayerByUserId(userId)
			local key = productKeys[productId]
			if player and key and not purchased then
				local product = Monetization.ProductByKey[key]
				Analytics.Event(player, "robux_cancelled", product.Price, key, "product")
			end
		end
	)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			local key = passKeys[passId]
			if key and not purchased then
				local pass = Monetization.PassByKey[key]
				Analytics.Event(player, "robux_cancelled", pass.Price, key, "pass")
			end
		end
	)
end

return Analytics
