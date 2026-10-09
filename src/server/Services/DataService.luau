--!strict
-- Player save data. Everything that matters (cash, knives, upgrades, luck) lives here and only
-- the server touches it. Saves go through UpdateAsync with retries and a session lock so two
-- servers can never overwrite each other (the classic dupe/rollback bug).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local GuidePolicy = require(ReplicatedStorage.Shared.GuidePolicy)
local CoffinState = require(ReplicatedStorage.Shared.CoffinState)

export type Profile = {
	Cash: number,
	Knives: { string }, -- item strings (Items): "Katana", "Katana|Gold|Huge"
	Plates: { number }, -- Plates[i] = the vault plate Knives[i] sits on (DataService.AddKnife/RemoveKnife)
	Slots: number,
	Luck: number,
	Tickets: number,
	TotalKills: number,
	RoundsWon: number,
	RoundsPlayed: number, -- murder rounds taken part in (a new player's first one: they're the Murderer)
	-- where you put each knife / coffin down in your pen (pen-local X/Z, keyed by plate as a string)
	Spots: { [string]: { number } },
	NotifyAsked: boolean, -- shown Roblox's notifications opt-in (NotifyService plans "come back" messages)
	-- knives still in their coffin (CoffinService): Rounds = murder rounds left (nil = a plain timer);
	-- ReadyAt (os.time) = when it opens anyway, the offline fallback
	Sealed: { { Plate: number, ReadyAt: number, Rounds: number?, Paid: boolean? } },
	Equipped: string, -- item you fight with / bring into rounds as the Murderer; "" = best owned
	Discovered: { string }, -- every catalog knife ever owned (plain names), for the collection book
	-- (old saves: the cut Innocent Powers, kept only so InventoryService can refund them once)
	Speed: number, -- trained on the vault treadmill; turned into walk speed by GameConfig.WalkSpeedFor
	Rebirths: number,
	TutorialDone: boolean,
	KnivesStolen: number, -- from other players' vaults in raids
	IndexClaimed: { string }, -- knives whose Index reward was collected
	LastSeen: number, -- os.time() of the last save (offline earnings count from here)
	PlayTime: number, -- seconds played in total (the new-player shield runs out on this)
	DailyStreak: number, -- day of the 7-day login streak last claimed (0 = none yet)
	LastDaily: number, -- the UTC day number it was claimed on
	TrailLevel: number, -- highest knife trail bought (GameConfig.Trails), 0 = none
	Receipts: { string }, -- recent Robux PurchaseIds already granted (ProcessReceipt is idempotent)
	Bought: { string }, -- one-time Robux products already bought (Starter Pack)
	Claimed: { string }, -- one-time free rewards taken: codes ("code:RELEASE"), the group gift ("gift:group")
	Pending: { number }, -- money waiting on each slot's cash pad (BaseService), collected by walking over it
	Boosts: { [string]: number }, -- Robux timed boosts: name (Speed/Cash/Training) -> os.time() it ends
	Charges: { [string]: number }, -- Robux charges: name (Escape/Insurance) -> how many left
	LastOffline: number, -- the last offline payout (Double Offline Earnings pays it again, once)
	LostStreak: number, -- the daily streak day a missed day broke (Save My Streak restores it)
	TutorialStep: number, -- how far the first-minutes guide got (resumes there)
	Tips: { string }, -- one-time tips already shown (client/Tips)
	GuidanceMode: string, -- Auto / On / Off
	GuidanceLearned: { [string]: number }, -- demonstrated controls and deliveries; survives rejoining
	-- Analytics (docs/ANALYTICS.md)
	FirstSeen: number, -- os.time() of their first ever join
	Sessions: number, -- visits so far (this one included once loaded)
	Firsts: { [string]: number }, -- milestone -> PlayTime when first reached (Analytics.Milestone)
	RobuxSpent: number, -- lifetime Robux spent in the game
	Source: string, -- first-touch join source (JSON: utm_* from launchData, referred, friend)
}

local STORE_NAME = "PlayerData_v4" -- v1-v3 = saves before the resets (2026-10-03, 2026-10-04: new pacing + knife powers), kept, not deleted
local LOCK_TIMEOUT = 600 -- a lock older than this belongs to a server that died
local AUTOSAVE_INTERVAL = 120
local MAX_ATTEMPTS = 5

local DataService = {}

local profiles: { [Player]: Profile } = {}
-- When each player was last seen before this visit (os.time(), 0 = never), for offline earnings
DataService.AwaySince = {} :: { [Player]: number }
local loadedEvent = Instance.new("BindableEvent")
local changedEvent = Instance.new("BindableEvent")
DataService.PlayerLoaded = loadedEvent.Event -- (player, profile)
DataService.Changed = changedEvent.Event -- (player, profile)

-- In Studio without API access (or in an unpublished place) we play with throwaway data.
-- GetDataStore itself throws in an unpublished place, so it has to be guarded too.
local storeOk, storeOrErr = pcall(DataStoreService.GetDataStore, DataStoreService, STORE_NAME)
local store: DataStore = if storeOk then storeOrErr else nil :: any
local offline = not storeOk
if offline then
	warn(`[DataService] no DataStore ({storeOrErr}) - using temporary data`)
end

local function defaultProfile(): Profile
	return {
		Cash = GameConfig.StartingCash,
		Knives = {},
		Plates = {},
		Slots = GameConfig.StartingSlots,
		Luck = 0,
		Tickets = 0,
		TotalKills = 0,
		RoundsWon = 0,
		RoundsPlayed = 0,
		NotifyAsked = false,
		Spots = {},
		Sealed = {},
		Equipped = "",
		Discovered = {},
		Speed = 0,
		Rebirths = 0,
		TutorialDone = false,
		KnivesStolen = 0,
		IndexClaimed = {},
		LastSeen = 0,
		PlayTime = 0,
		DailyStreak = 0,
		LastDaily = 0,
		Receipts = {},
		Bought = {},
		Claimed = {},
		TrailLevel = 0,
		Pending = {},
		Boosts = {},
		Charges = {},
		LastOffline = 0,
		LostStreak = 0,
		TutorialStep = 1,
		Tips = {},
		GuidanceMode = "Auto",
		GuidanceLearned = {},
		FirstSeen = 0,
		Sessions = 0,
		Firsts = {},
		RobuxSpent = 0,
		Source = "",
	}
end

-- Fill in fields added after a player's last save, and clamp anything nonsensical
local function reconcile(data: any): Profile
	local profile = defaultProfile()
	if type(data) == "table" then
		for key, value in pairs(profile :: any) do
			if type(data[key]) == type(value) then
				(profile :: any)[key] = data[key]
			end
		end
	end
	profile.Slots = math.clamp(math.floor(profile.Slots), GameConfig.StartingSlots, GameConfig.Pens.MaxSlots)
	-- One number per slot, never negative or broken (a dense array saves cleanly)
	local pending: { number } = {}
	for slot = 1, GameConfig.Pens.MaxSlots + GameConfig.Pens.Bag do
		local value = profile.Pending[slot]
		pending[slot] = if type(value) == "number"
				and value == value
				and value >= 0
				and value < math.huge
			then value
			else 0
	end
	profile.Pending = pending
	local boosts, charges = {}, {}
	for name, value in profile.Boosts do
		if type(name) == "string" and type(value) == "number" and value > os.time() then
			boosts[name] = math.floor(value)
		end
	end
	for name, value in profile.Charges do
		if type(name) == "string" and type(value) == "number" and value >= 1 then
			charges[name] = math.floor(value)
		end
	end
	profile.Boosts, profile.Charges = boosts, charges
	profile.LastOffline = math.max(0, profile.LastOffline)
	profile.LostStreak = math.max(0, math.floor(profile.LostStreak))
	profile.TutorialStep = math.clamp(math.floor(profile.TutorialStep), 1, 10)
	local tips = {}
	for _, tip in profile.Tips do
		if type(tip) == "string" and #tip <= 24 and #tips < 60 then
			table.insert(tips, tip)
		end
	end
	profile.Tips = tips
	local claimed = {}
	for _, key in profile.Claimed do
		if type(key) == "string" and #key <= 40 and #claimed < 300 then
			table.insert(claimed, key)
		end
	end
	profile.Claimed = claimed
	local firsts = {}
	for name, at in profile.Firsts do
		if type(name) == "string" and #name <= 32 and type(at) == "number" and at == at then
			firsts[name] = math.floor(at)
		end
	end
	profile.Firsts = firsts
	if profile.GuidanceMode ~= "On" and profile.GuidanceMode ~= "Off" then
		profile.GuidanceMode = "Auto"
	end
	local learned: { [string]: number } = {}
	for skill, count in profile.GuidanceLearned do
		local limit = if type(skill) == "string" then GuidePolicy.Limit(skill) else nil
		if limit and type(count) == "number" and count == count then
			learned[skill] = math.clamp(math.floor(count), 0, limit)
		end
	end
	profile.GuidanceLearned = learned
	profile.Source = profile.Source:sub(1, 300)
	profile.Speed = math.max(0, profile.Speed)
	profile.Cash = math.max(0, profile.Cash)
	profile.Rebirths = math.clamp(math.floor(profile.Rebirths), 0, GameConfig.Rebirth.Max)
	profile.TrailLevel = math.clamp(math.floor(profile.TrailLevel), 0, #GameConfig.Trails)
	-- Drop knives that were removed from the catalog so nothing downstream sees an unknown name
	-- Each kept knife keeps its plate (older saves: plates in list order); duplicates or bad plates
	-- get the first free one
	local items, plates, used = {}, {}, {}
	for i, item in profile.Knives do
		if Items.Valid(item) then
			table.insert(items, item)
			local plate = profile.Plates[i]
			if
				type(plate) == "number"
				and plate >= 1
				and plate <= GameConfig.Pens.MaxSlots + GameConfig.Pens.Bag
				and not used[plate]
			then
				plate = math.floor(plate)
			else
				plate = 0
			end
			table.insert(plates, plate)
			if plate > 0 then
				used[plate] = true
			end
		end
	end
	for i, plate in plates do
		if plate == 0 then
			local free = 1
			while used[free] do
				free += 1
			end
			plates[i] = free
			used[free] = true
		end
	end
	profile.Knives = items
	profile.Plates = plates
	local discovered = {}
	for _, name in profile.Discovered do
		local base = if type(name) == "string" then Items.Name(name) else ""
		if Knives.ByName[base] and not table.find(discovered, base) then
			table.insert(discovered, base)
		end
	end
	profile.Discovered = discovered
	if profile.Equipped ~= "" and not table.find(profile.Knives, profile.Equipped) then
		profile.Equipped = ""
	end
	return profile
end

-- Knives and the plates they sit on --------------------------------------------------------------
-- Every change to a profile's Knives goes through these, so Plates stays lined up with it.

-- The first empty plate (1..), or nil when every unlocked plate is taken
function DataService.FreePlate(profile: Profile): number?
	for plate = 1, profile.Slots do
		if not table.find(profile.Plates, plate) then
			return plate
		end
	end
	return nil
end

-- Adds a knife, on `plate` if that one is free, else on the first free plate (or past the
-- unlocked ones if the wall is full - it shows up once a new floor is bought). Returns the plate.
function DataService.AddKnife(profile: Profile, item: string, plate: number?): number
	local target = if plate and plate >= 1 and not table.find(profile.Plates, plate) then plate else nil
	if not target then
		target = DataService.FreePlate(profile)
	end
	if not target then
		local n = profile.Slots + 1
		while table.find(profile.Plates, n) do
			n += 1
		end
		target = n
	end
	table.insert(profile.Knives, item)
	table.insert(profile.Plates, target :: number)
	return target :: number
end

-- Removes the knife at list index `index` (and its plate); returns the item
-- Robux consumables ----------------------------------------------------------------------------

-- Whether a timed boost (Speed / Cash / Training) is running for this profile
function DataService.BoostActive(profile: Profile, name: string): boolean
	return (profile.Boosts[name] or 0) > os.time()
end

-- Adds time to a boost (stacks onto what's left)
function DataService.AddBoost(player: Player, name: string, seconds: number)
	DataService.Update(player, function(p)
		p.Boosts[name] = math.max(p.Boosts[name] or 0, os.time()) + seconds
	end)
end

function DataService.AddCharge(player: Player, name: string, count: number)
	DataService.Update(player, function(p)
		p.Charges[name] = (p.Charges[name] or 0) + count
	end)
end

-- Uses one charge if they have any
function DataService.UseCharge(player: Player, name: string): boolean
	local profile = DataService.Get(player)
	if not profile or (profile.Charges[name] or 0) < 1 then
		return false
	end
	DataService.Update(player, function(p)
		p.Charges[name] = (p.Charges[name] or 0) - 1
		if p.Charges[name] <= 0 then
			p.Charges[name] = nil
		end
	end)
	return true
end

function DataService.RemoveKnife(profile: Profile, index: number): string?
	local plate = profile.Plates[index]
	local item = table.remove(profile.Knives, index)
	table.remove(profile.Plates, index)
	if plate then
		DataService.Unseal(profile, plate) -- (a coffin that leaves takes its timer with it)
	end
	return item
end

-- Coffins (CoffinService): a knife on its plate that hasn't opened yet. While sealed it earns
-- nothing and can't be equipped, sold or fought with.
function DataService.SealedReadyAt(profile: Profile, plate: number): number?
	for _, entry in profile.Sealed do
		if entry.Plate == plate then
			return entry.ReadyAt
		end
	end
	return nil
end

function DataService.IsSealedIndex(profile: Profile, index: number): boolean
	local plate = profile.Plates[index]
	return plate ~= nil and DataService.SealedReadyAt(profile, plate) ~= nil
end

function DataService.Seal(profile: Profile, plate: number, readyAt: number, rounds: number?, paid: boolean?)
	DataService.Unseal(profile, plate)
	table.insert(profile.Sealed, { Plate = plate, ReadyAt = readyAt, Rounds = rounds, Paid = paid })
end

function DataService.SealedEntry(
	profile: Profile,
	plate: number
): { Plate: number, ReadyAt: number, Rounds: number?, Paid: boolean? }?
	for _, entry in profile.Sealed do
		if entry.Plate == plate then
			return entry
		end
	end
	return nil
end

function DataService.Unseal(profile: Profile, plate: number): boolean
	for i, entry in profile.Sealed do
		if entry.Plate == plate then
			table.remove(profile.Sealed, i)
			return true
		end
	end
	return false
end

function DataService.PlateOf(profile: Profile, index: number): number
	return profile.Plates[index] or index
end

-- Which knife (list index) sits on `plate`, if any
function DataService.IndexOnPlate(profile: Profile, plate: number): number?
	return table.find(profile.Plates, plate)
end

-- Coffins that are READY to tap (a knife on the plate and its clock done). BaseService shows this
-- as CoffinsReady; CoffinService's check compares against it, so both must count the same way.
function DataService.ReadyCoffins(profile: Profile, now: number): number
	local count = 0
	for _, entry in profile.Sealed do
		if DataService.IndexOnPlate(profile, entry.Plate) and CoffinState.Ready(entry.Rounds, entry.ReadyAt, now) then
			count += 1
		end
	end
	return count
end

local function key(player: Player): string
	return `u_{player.UserId}`
end

local function isStudioApiError(err: any): boolean
	local message = string.lower(tostring(err))
	return RunService:IsStudio()
		and (
			message:find("studioaccesstoapisnotallowed", 1, true) ~= nil
			or message:find("api access is not enabled", 1, true) ~= nil
			or message:find("publish", 1, true) ~= nil
		)
end

local function loadAsync(player: Player): Profile?
	-- Studio: ServerStorage attribute DebugFresh = true plays as a brand-new player on temporary
	-- data (nothing is saved, your real save is untouched) - for testing the first minutes
	if RunService:IsStudio() and game:GetService("ServerStorage"):GetAttribute("DebugFresh") then
		offline = true
	end
	if offline then
		local fresh = defaultProfile()
		-- (Studio: DebugTutorialDone = true skips the tutorial, to test what comes after it)
		if RunService:IsStudio() and game:GetService("ServerStorage"):GetAttribute("DebugTutorialDone") then
			fresh.TutorialDone = true
			fresh.TutorialStep = 5
		end
		return fresh
	end
	for attempt = 1, MAX_ATTEMPTS do
		local lockedElsewhere = false
		-- The other server is probably dead: take over. In Studio the "other server" is always the
		-- previous playtest that was stopped before it could release, so don't make testers wait.
		local forceLock = attempt == MAX_ATTEMPTS or (RunService:IsStudio() and attempt >= 2)
		local ok, result = pcall(function()
			return store:UpdateAsync(key(player), function(old: any)
				old = old or {}
				local lock = old.Lock
				if not forceLock and lock and lock.JobId ~= game.JobId and os.time() - lock.Time < LOCK_TIMEOUT then
					lockedElsewhere = true
					return nil
				end
				old.Lock = { JobId = game.JobId, Time = os.time() }
				return old
			end)
		end)
		if ok and not lockedElsewhere then
			return reconcile(result and result.Data)
		elseif not ok and isStudioApiError(result) then
			warn(
				"[DataService] Studio has no DataStore access - using temporary data (Game Settings > Security to enable)"
			)
			offline = true
			return defaultProfile()
		end
		warn(
			`[DataService] load attempt {attempt} for {player.Name} failed: {if ok
				then "locked by another server"
				else result}`
		)
		task.wait(if lockedElsewhere then 4 else attempt)
	end
	return nil
end

local function saveAsync(player: Player, profile: Profile, release: boolean): boolean
	if offline then
		return true
	end
	for attempt = 1, MAX_ATTEMPTS do
		local lostLock = false
		local ok, err = pcall(function()
			store:UpdateAsync(key(player), function(old: any)
				old = old or {}
				if old.Lock and old.Lock.JobId ~= game.JobId then
					lostLock = true -- someone else owns this save now; writing would roll them back
					return nil
				end
				profile.LastSeen = os.time()
				old.Data = profile
				old.Lock = if release then nil else { JobId = game.JobId, Time = os.time() }
				return old
			end)
		end)
		if ok then
			if lostLock then
				warn(`[DataService] {player.Name}'s save is locked by another server, skipped`)
			end
			return not lostLock
		end
		warn(`[DataService] save attempt {attempt} for {player.Name} failed: {err}`)
		task.wait(attempt)
	end
	return false
end

local BOOSTS = { "Speed", "Cash", "RoundSpeed" }
local CHARGES = { "Escape", "Insurance", "DoublePrize" }

-- Mirror the profile onto the player so the HUD and leaderboard can read it (read-only for clients)
local function publish(player: Player, profile: Profile)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		(leaderstats:FindFirstChild("Cash") :: IntValue).Value = math.floor(profile.Cash);
		(leaderstats:FindFirstChild("Rebirths") :: IntValue).Value = profile.Rebirths;
		(leaderstats:FindFirstChild("Stolen") :: IntValue).Value = profile.KnivesStolen
	end
	player:SetAttribute("Cash", math.floor(profile.Cash))
	player:SetAttribute("Slots", profile.Slots)
	player:SetAttribute("KnifeCount", #profile.Knives)
	player:SetAttribute("KnifePlates", table.concat(profile.Plates, ","))
	player:SetAttribute("Speed", math.floor(profile.Speed))
	player:SetAttribute("Luck", profile.Luck)
	player:SetAttribute("Tickets", profile.Tickets)
	local publicKnives, sealed = {}, {}
	for index, item in profile.Knives do
		local hidden = DataService.IsSealedIndex(profile, index)
		table.insert(publicKnives, if hidden then Items.Name(item) else item)
		if hidden then
			table.insert(sealed, index)
		end
	end
	player:SetAttribute("SealedKnives", table.concat(sealed, ","))
	player:SetAttribute("Knives", table.concat(publicKnives, ","))
	player:SetAttribute("Equipped", profile.Equipped)
	player:SetAttribute("Discovered", table.concat(profile.Discovered, ","))
	player:SetAttribute("Kills", profile.TotalKills)
	player:SetAttribute("Wins", profile.RoundsWon)
	player:SetAttribute("RoundsPlayed", profile.RoundsPlayed)
	player:SetAttribute("Rebirths", profile.Rebirths)
	player:SetAttribute("Title", GameConfig.RebirthTitle(profile.Rebirths))
	player:SetAttribute("TutorialDone", profile.TutorialDone)
	player:SetAttribute("KnivesStolen", profile.KnivesStolen)
	player:SetAttribute("IndexClaimed", table.concat(profile.IndexClaimed, ","))
	player:SetAttribute("DailyStreak", profile.DailyStreak)
	player:SetAttribute("TrailLevel", profile.TrailLevel)
	for _, bought in profile.Bought do
		-- ("Pass:<key>" entries only record a pass bought outside the game: attribute names can't
		-- hold ":", and Pass_<key> already says they own it)
		if not bought:find(":", 1, true) then
			player:SetAttribute("Bought_" .. bought, true)
		end
	end
	player:SetAttribute("LastDaily", profile.LastDaily)
	for _, name in BOOSTS do
		player:SetAttribute("Boost_" .. name, profile.Boosts[name])
	end
	for _, name in CHARGES do
		player:SetAttribute("Charge_" .. name, profile.Charges[name] or 0)
	end
	player:SetAttribute("LastOffline", profile.LastOffline)
	player:SetAttribute("LostStreak", profile.LostStreak)
	player:SetAttribute("TutorialStep", profile.TutorialStep)
	player:SetAttribute("TipsSeen", table.concat(profile.Tips, ","))
	player:SetAttribute("GuidanceMode", profile.GuidanceMode)
	local learned = {}
	for skill, count in profile.GuidanceLearned do
		table.insert(learned, `{skill}={count}`)
	end
	table.sort(learned)
	player:SetAttribute("GuidanceLearned", table.concat(learned, ","))
	local shielded = DataService.IsNewPlayer(player, profile)
	player:SetAttribute("Shielded", shielded or nil)
	player:SetAttribute("ShieldLeft", if shielded then GameConfig.NewPlayerShield - profile.PlayTime else nil)
	changedEvent:Fire(player, profile)
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	for _, stat in { "Cash", "Rebirths", "Stolen" } do
		local value = Instance.new("IntValue")
		value.Name = stat
		value.Parent = leaderstats
	end
	leaderstats.Parent = player

	local profile = loadAsync(player)
	if not player.Parent then
		if profile then
			saveAsync(player, profile, true) -- they left while loading; release the lock
		end
		return
	end
	if not profile then
		player:Kick("We couldn't load your data (Roblox servers are busy). Please rejoin!")
		return
	end
	profiles[player] = profile
	DataService.AwaySince[player] = profile.LastSeen
	publish(player, profile)
	player:SetAttribute("DataLoaded", true)
	loadedEvent:Fire(player, profile)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		saveAsync(player, profile, true)
		profiles[player] = nil
	end
	DataService.AwaySince[player] = nil
end

-- New players' knives can't be taken (break-ins, burglars, Murderer loot) for their first
-- GameConfig.NewPlayerShield seconds of play. In Studio everyone is new every session, so the
-- shield is off there unless ReplicatedStorage has DebugShield = true.
function DataService.IsNewPlayer(player: Player, profile: Profile?): boolean
	if RunService:IsStudio() and not ReplicatedStorage:GetAttribute("DebugShield") then
		return false
	end
	local p = profile or profiles[player]
	return p ~= nil and p.Rebirths == 0 and p.PlayTime < GameConfig.NewPlayerShield
end

function DataService.Get(player: Player): Profile?
	return profiles[player]
end

-- The only way game code changes data: mutate inside fn, then everything is re-published
function DataService.Update(player: Player, fn: (Profile) -> ())
	local profile = profiles[player]
	if not profile then
		return
	end
	fn(profile)
	publish(player, profile)
end

-- Preferences only: record demonstrated lessons without changing rewards or game progression.
function DataService.LearnGuidance(player: Player, skill: string)
	local profile = profiles[player]
	local limit = GuidePolicy.Limit(skill)
	local entries = 0
	if profile and profile.GuidanceLearned[skill] == nil then
		for _ in profile.GuidanceLearned do
			entries += 1
		end
	end
	if profile and limit and #skill <= 40 and entries < 64 and (profile.GuidanceLearned[skill] or 0) < limit then
		DataService.Update(player, function(p)
			p.GuidanceLearned[skill] = math.min(limit, (p.GuidanceLearned[skill] or 0) + 1)
		end)
	end
end

-- Write this player's save right now (after a Robux purchase); true if it stuck
function DataService.SaveNow(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and saveAsync(player, profile, false)
end

-- Analytics hears about every cash change made here: (player, +in / -out, reason)
local cashHook: ((Player, number, string?) -> ())? = nil
function DataService.SetCashHook(hook: (Player, number, string?) -> ())
	cashHook = hook
end
-- For cash changed inside an Update (sells, refunds): tell Analytics where it came from
function DataService.CashFlow(player: Player, amount: number, reason: string)
	if cashHook then
		cashHook(player, amount, reason)
	end
end

-- `reason` names the source for analytics ("income", "round_pay", "daily"...)
function DataService.AddCash(player: Player, amount: number, reason: string?)
	DataService.Update(player, function(profile)
		profile.Cash += amount
	end)
	if cashHook and profiles[player] then
		cashHook(player, amount, reason)
	end
end

-- `reason` names the sink for analytics ("upgrade_speed", "upgrade_wheel"...)
function DataService.TrySpend(player: Player, amount: number, reason: string?): boolean
	local profile = profiles[player]
	if not profile or amount < 0 or profile.Cash < amount then
		return false
	end
	DataService.Update(player, function(p)
		p.Cash -= amount
	end)
	if cashHook then
		cashHook(player, -amount, reason)
	end
	return true
end

function DataService.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, profile in profiles do
				task.spawn(saveAsync, player, profile, false)
			end
		end
	end)

	-- Play time (and with it the new-player shield running out)
	task.spawn(function()
		while true do
			task.wait(30)
			for player, profile in profiles do
				local wasNew = DataService.IsNewPlayer(player, profile)
				profile.PlayTime += 30
				if DataService.IsNewPlayer(player, profile) then
					player:SetAttribute("ShieldLeft", GameConfig.NewPlayerShield - profile.PlayTime)
				elseif wasNew then
					player:SetAttribute("Shielded", nil)
					player:SetAttribute("ShieldLeft", nil)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player, profile in profiles do
			pending += 1
			task.spawn(function()
				saveAsync(player, profile, true)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
