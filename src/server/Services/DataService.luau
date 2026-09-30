--!strict
-- Player save data. Everything that matters (cash, knives, upgrades, luck) lives here and only
-- the server touches it. Saves go through UpdateAsync with retries and a session lock so two
-- servers can never overwrite each other (the classic dupe/rollback bug).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

export type Profile = {
	Cash: number,
	Knives: { string },
	Slots: number,
	SpeedLevel: number,
	Luck: number,
	Tickets: number,
	TotalKills: number,
	RoundsWon: number,
}

local STORE_NAME = "PlayerData_v1"
local LOCK_TIMEOUT = 600 -- a lock older than this belongs to a server that died
local AUTOSAVE_INTERVAL = 120
local MAX_ATTEMPTS = 5

local DataService = {}

local profiles: { [Player]: Profile } = {}
local loadedEvent = Instance.new("BindableEvent")
local changedEvent = Instance.new("BindableEvent")
DataService.PlayerLoaded = loadedEvent.Event -- (player, profile)
DataService.Changed = changedEvent.Event -- (player, profile)

local store = DataStoreService:GetDataStore(STORE_NAME)
-- In Studio without "Enable Studio Access to API Services" we play with throwaway data
local offline = false

local function defaultProfile(): Profile
	return {
		Cash = GameConfig.StartingCash,
		Knives = {},
		Slots = GameConfig.StartingSlots,
		SpeedLevel = 0,
		Luck = 0,
		Tickets = 0,
		TotalKills = 0,
		RoundsWon = 0,
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
	profile.Slots = math.clamp(profile.Slots, GameConfig.StartingSlots, GameConfig.MaxSlots)
	profile.SpeedLevel = math.clamp(profile.SpeedLevel, 0, GameConfig.MaxSpeedLevel)
	profile.Cash = math.max(0, profile.Cash)
	return profile
end

local function key(player: Player): string
	return `u_{player.UserId}`
end

local function isStudioApiError(err: any): boolean
	return RunService:IsStudio() and tostring(err):find("StudioAccessToApisNotAllowed") ~= nil
end

local function loadAsync(player: Player): Profile?
	for attempt = 1, MAX_ATTEMPTS do
		local lockedElsewhere = false
		local forceLock = attempt == MAX_ATTEMPTS -- the other server is probably dead, take over
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

-- Mirror the profile onto the player so the HUD and leaderboard can read it (read-only for clients)
local function publish(player: Player, profile: Profile)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		(leaderstats:FindFirstChild("Cash") :: IntValue).Value = math.floor(profile.Cash)
	end
	player:SetAttribute("Cash", math.floor(profile.Cash))
	player:SetAttribute("Slots", profile.Slots)
	player:SetAttribute("KnifeCount", #profile.Knives)
	player:SetAttribute("SpeedLevel", profile.SpeedLevel)
	player:SetAttribute("Luck", profile.Luck)
	player:SetAttribute("Tickets", profile.Tickets)
	changedEvent:Fire(player, profile)
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Parent = leaderstats
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

function DataService.AddCash(player: Player, amount: number)
	DataService.Update(player, function(profile)
		profile.Cash += amount
	end)
end

function DataService.TrySpend(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or amount < 0 or profile.Cash < amount then
		return false
	end
	DataService.Update(player, function(p)
		p.Cash -= amount
	end)
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
