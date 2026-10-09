--!strict
-- Sealed characters earn nothing until their owner taps READY.
-- Rounds advance the clock; timers/offline returns mark readiness without auto-opening.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local Format = require(ReplicatedStorage.Shared.Format)
local Net = require(script.Parent.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)
local Analytics = require(script.Parent.Analytics)
local PenMode = require(ReplicatedStorage.Shared.PenMode)
local CoffinState = require(ReplicatedStorage.Shared.CoffinState)

local CoffinService = {}

local CONFIG = GameConfig.Coffins
local target: { [Player]: number } = {} -- the coffin the owner asked to open with Robux
local rng = Random.new()

function CoffinService.On(_player: Player): boolean
	return PenMode.Coffins()
end

-- Mutation / size luck for a knife rolled for this player: rebirths and the 2x Luck pass
function CoffinService.Luck(player: Player, profile: DataService.Profile): number
	local luck = 1 + profile.Rebirths * GameConfig.Rebirth.LuckBonus
	if player:GetAttribute("Pass_Luck") == true then
		luck *= 2
	end
	if player:GetAttribute("WinnerLuck") then
		luck *= CONFIG.WinnerLuck
	end
	luck *= (ReplicatedStorage:GetAttribute("MutationLuckMultiplier") or 1) :: number
	return luck
end

local function roundsText(rounds: number): string
	return if rounds <= 1 then "after the next murder round" else `after {math.ceil(rounds)} murder rounds`
end

-- Seals the knife on `plate` (just deposited). Returns when it opens, for the toast ("in 20s",
-- "after 2 murder rounds").
-- `seconds`: a plain short timer instead (the tutorial's coffin: you see it land and count down)
-- Call only inside DataService.Update, alongside AddKnife: hidden contents never replicate.
function CoffinService.SealInto(profile: DataService.Profile, plate: number, item: string, seconds: number?): string
	local parsed = Items.Parse(item)
	local rarity = if parsed then parsed.Knife.Rarity else "Common"
	local rounds = if seconds then 0 else CONFIG.Rounds[rarity] or 1
	local waitSeconds = seconds
		or (if rounds <= 0 then CONFIG.CommonSeconds else rounds * CONFIG.OfflineSecondsPerRound)
	DataService.Seal(profile, plate, os.time() + waitSeconds, if rounds > 0 then rounds else nil)
	return if rounds <= 0 then `in {Format.Duration(waitSeconds)}` else roundsText(rounds)
end

-- A boss's knife going into your coffin gets one more mutation / size roll with your luck (rebirths,
-- the Luck pass, potions); the better of the two is what's inside. Nobody sees it until it opens.
function CoffinService.LuckyContents(player: Player, item: string, openingLuck: number?): string
	local profile = DataService.Get(player)
	local parsed = Items.Parse(item)
	if not profile or not parsed then
		return item
	end
	local luck = openingLuck or CoffinService.Luck(player, profile)
	if luck <= 1 then
		return item
	end
	local mutation, size = Items.Roll(rng, luck)
	return Items.Make(
		parsed.Name,
		if mutation.Rank > parsed.Mutation.Rank then mutation.Id else parsed.Mutation.Id,
		if size.Income > parsed.Size.Income then size.Id else parsed.Size.Id
	)
end

-- A mystery knife for `player` (a gift, a wheel prize, round loot, the daily streak, the Starter
-- Pack). Coffin servers: it lands in their pen SEALED in a coffin, on the murder-round clock like a
-- boss's (the knife stays a secret till it opens). Vault servers: straight onto the wall.
-- Returns the item, or nil when there's no free plate (the caller pays its worth instead).
-- `source` names it in the toast ("a gift", "the Lucky Wheel") and in analytics; `quiet` skips the
-- toast (the round haul has its own card). With no free plate the caller pays replacement value;
-- paid coffins must not bypass their clock by arriving unsealed in storage.
function CoffinService.Give(player: Player, item: string, source: string, quiet: boolean?): string?
	local profile = DataService.Get(player)
	local parsed = Items.Parse(item)
	if not profile or not parsed or not DataService.FreePlate(profile) then
		return nil
	end
	local rarity = parsed.Knife.Rarity
	if PenMode.Coffins() then
		local plate = 0
		DataService.Update(player, function(p)
			plate = DataService.AddKnife(p, item)
			CoffinService.SealInto(p, plate, item)
		end)
		BaseService.RefreshRack(player)
		Net.Remotes.Effect:FireAllClients("Deposit", player, rarity)
		if not quiet then
			Net.Notify(player, `⚰️ {parsed.Knife.DisplayName} coffin delivered!`, "good")
		end
	else
		local isNew = not table.find(profile.Discovered, parsed.Name)
		DataService.Update(player, function(p)
			DataService.AddKnife(p, item)
			if isNew then
				table.insert(p.Discovered, parsed.Name)
			end
		end)
		BaseService.RefreshRack(player)
		Net.Remotes.Effect:FireAllClients("Deposit", player, rarity)
		if not quiet then
			Net.Notify(
				player,
				`🔪 {if isNew then "NEW! " else ""}{Items.DisplayName(item)} from {source}! +{Format.Cash(
					Items.Income(item)
				)}/s`,
				"good"
			)
		end
	end
	Analytics.Track(player, "coffin.given", { rarity = rarity, source = source, sealed = PenMode.Coffins() })
	return item
end

-- A coffin bought with Robux (the featured coffin): READY the moment it lands, and it opens to
-- exactly `item` (no luck re-roll), so the odds the shop showed are the real ones. Returns false
-- when there's no free plate (the caller pays its worth instead).
function CoffinService.GivePaid(player: Player, item: string, source: string): boolean
	local profile = DataService.Get(player)
	local parsed = Items.Parse(item)
	if not profile or not parsed or not DataService.FreePlate(profile) then
		return false
	end
	DataService.Update(player, function(p)
		local plate = DataService.AddKnife(p, item)
		DataService.Seal(p, plate, os.time(), 0, true)
	end)
	BaseService.RefreshRack(player)
	Net.Remotes.Effect:FireAllClients("Deposit", player, parsed.Knife.Rarity)
	Analytics.Track(
		player,
		"coffin.given",
		{ rarity = parsed.Knife.Rarity, source = source, sealed = true, paid = true }
	)
	return true
end

-- A mystery knife of this rarity (a 4% chance of one rarity up), rolled with the player's luck
function CoffinService.GiveRarity(player: Player, rarity: string, source: string, quiet: boolean?): string?
	local profile = DataService.Get(player)
	if not profile or rarity == "Secret" then
		return nil
	end
	local item = Items.RollKnife(rng, rarity, 1)
	return CoffinService.Give(player, item, source, quiet)
end

-- A coffin of this rarity, or its worth in cash (GameConfig.CoffinValue) when there's no room.
-- Returns what they got, for a toast ("a Rare Coffin" / "$300K (no room for a coffin)").
function CoffinService.GiveOrCash(player: Player, rarity: string, source: string): string
	if CoffinService.GiveRarity(player, rarity, source) then
		return `a {rarity} {if PenMode.Coffins() then "Coffin" else "knife"}`
	end
	local value = GameConfig.CoffinValue[rarity] or GameConfig.CoffinValue.Common
	DataService.AddCash(player, value, "coffin_value")
	return `{Format.Cash(value)} (no room for a {rarity} {if PenMode.Coffins() then "Coffin" else "knife"})`
end

local POP_TIME = 1.1 -- the coffin rattles and its lid swings open this long before the knife shows
local popping: { [string]: boolean } = {}

function CoffinService.Open(player: Player, plate: number, how: string)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local entry = DataService.SealedEntry(profile, plate)
	local index = DataService.IndexOnPlate(profile, plate)
	local key = `{player.UserId}:{plate}`
	if not entry or not index or popping[key] or not CoffinState.Ready(entry.Rounds, entry.ReadyAt, os.time()) then
		return
	end
	popping[key] = true
	local openingItem = profile.Knives[index]
	local openingLuck = if entry.Paid then 1 else CoffinService.Luck(player, profile)
	-- The pop (client/Coffins): everyone sees it shake harder and the lid fly open, then the reveal
	local first = Items.Parse(profile.Knives[index])
	Net.Remotes.Effect:FireAllClients("CoffinPop", player.UserId, plate, if first then first.Knife.Rarity else "Common")
	task.delay(POP_TIME, function()
		popping[key] = nil
		local live = DataService.Get(player)
		local liveIndex = live and DataService.IndexOnPlate(live, plate)
		if
			player.Parent
			and live
			and DataService.SealedEntry(live, plate) == entry
			and liveIndex
			and live.Knives[liveIndex] == openingItem
		then
			CoffinService.Reveal(player, plate, how, openingLuck)
		end
	end)
end

-- The reveal: the knife appears and flies to its owner (CoffinService.Open pops the lid first)
function CoffinService.Reveal(player: Player, plate: number, how: string, openingLuck: number?)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local entry = DataService.SealedEntry(profile, plate)
	local index = DataService.IndexOnPlate(profile, plate)
	if not entry or not index then
		return
	end
	local roundsLeft = entry.Rounds
	local item = if entry.Paid
		then profile.Knives[index]
		else CoffinService.LuckyContents(player, profile.Knives[index], openingLuck)
	local parsed = Items.Parse(item)
	-- (it joins your Index now, not when the coffin landed: what's inside was a secret till now)
	local isNew = parsed ~= nil and not table.find(profile.Discovered, parsed.Name)
	DataService.Update(player, function(p)
		if p.Knives[index] ~= item then
			DataService.RemoveKnife(p, index)
			DataService.AddKnife(p, item, plate)
		else
			DataService.Unseal(p, plate)
		end
		if isNew and parsed then
			table.insert(p.Discovered, parsed.Name)
		end
	end)
	if isNew and parsed then
		Analytics.Milestone(player, "discovered_" .. parsed.Knife.Rarity)
	end
	local rarity = if parsed then parsed.Knife.Rarity else "Common"
	-- (it pops out and flies into your hand, and hops back to its spot once you're in your pen;
	-- the pen leaves it out meanwhile)
	if not player:GetAttribute("InRound") then
		BaseService.HoldHatched(player, plate, item)
	else
		BaseService.RefreshRack(player)
	end
	local base = BaseService.GetBase(player)
	local at = if base and base.SlotCFrames[plate] then base.SlotCFrames[plate].Position else nil
	if at then
		Net.Remotes.Effect:FireAllClients(
			"CoffinOpen",
			at,
			Knives.RarityColors[rarity],
			table.find(Knives.Rarities, rarity) or 1
		)
		-- (Steal an Egg: what hatched pops up and flies into its owner - client Effects CoffinHatch)
		Net.Remotes.Effect:FireAllClients("CoffinHatch", player, item, at)
	end
	Net.Notify(player, `🎉 {Items.DisplayName(item)} unlocked!`, "good")
	-- the big ones are a server moment
	local rank = table.find(Knives.Rarities, rarity) or 1
	if rank >= (table.find(Knives.Rarities, CONFIG.AnnounceFrom) or 5) then
		Net.Announce(
			`🔥 {player.DisplayName}'s coffin had a {Items.DisplayName(item)}!`,
			Knives.RarityColors[rarity] or Color3.new(1, 1, 1),
			2
		)
	end
	Analytics.Track(player, "coffin.open", {
		rarity = rarity,
		how = how, -- timer / round / offline / robux
		rounds_left = roundsLeft, -- (> 0 = opened with Robux before its time)
	})
end

-- Robux "Open now" (MonetizationService grants product CoffinOpen): the coffin they picked, else
-- the one with the longest wait left
function CoffinService.OpenNow(player: Player): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end
	local plate: number? = target[player]
	if not plate or not DataService.SealedEntry(profile, plate) then
		plate = nil
		local latest = -math.huge
		for _, entry in profile.Sealed do
			if entry.ReadyAt > latest then
				plate, latest = entry.Plate, entry.ReadyAt
			end
		end
	end
	target[player] = nil
	if not plate then
		return false
	end
	DataService.Update(player, function(p)
		local entry = DataService.SealedEntry(p, plate :: number)
		if entry then
			entry.Rounds = 0
			entry.ReadyAt = os.time()
		end
	end)
	BaseService.RefreshRack(player)
	Net.Notify(player, "⚰️ READY! Tap to unlock!", "good")
	return true
end

-- This bonus follows the server's round boundary, not a client countdown.
function CoffinService.RoundStarted()
	for _, player in Players:GetPlayers() do
		player:SetAttribute("WinnerLuck", nil)
	end
end
function CoffinService.Winner(player: Player)
	local token = workspace:GetServerTimeNow()
	player:SetAttribute("WinnerLuck", token)
	task.delay(GameConfig.ResultsTime + 0.3, function()
		if player.Parent and player:GetAttribute("WinnerLuck") == token then
			Net.Remotes.Effect:FireClient(player, "Announce", "🍀 WINNER'S LUCK x2!", Color3.fromRGB(90, 255, 130), 1)
		end
	end)
end

-- At results, winners advance twice as far. Due coffins wait for a tap.
function CoffinService.RoundEnded(winners: { [Player]: boolean })
	for _, player in Players:GetPlayers() do
		local profile = DataService.Get(player)
		if not profile or #profile.Sealed == 0 then
			continue
		end
		local step = if winners[player] then CONFIG.WinRounds else 1
		local changed = false
		DataService.Update(player, function(p)
			for _, entry in p.Sealed do
				if entry.Rounds ~= nil and entry.Rounds > 0 then
					entry.Rounds = math.max(0, entry.Rounds - step)
					-- (the offline fallback follows: what's left, in real time from now)
					entry.ReadyAt = os.time() + entry.Rounds * CONFIG.OfflineSecondsPerRound
					changed = true
				end
			end
		end)
		if changed then
			BaseService.RefreshRack(player) -- (the labels: "1 round left")
		end
	end
end

local lastOpen: { [Player]: number } = {}
local function requestOpen(player: Player, plate: unknown): (boolean, string)
	if type(plate) ~= "number" or plate % 1 ~= 0 or plate < 1 or plate > GameConfig.Pens.MaxSlots then
		return false, "Choose a coffin!"
	end
	if os.clock() - (lastOpen[player] or 0) < 0.25 then
		return false, "Wait a moment!"
	end
	lastOpen[player] = os.clock()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if player:GetAttribute("InRound") or player:GetAttribute("Carrying") or not humanoid or humanoid.Health <= 0 then
		return false, "Get home first!"
	end
	local profile = DataService.Get(player)
	local entry = profile and DataService.SealedEntry(profile, plate)
	if not entry or not CoffinState.Ready(entry.Rounds, entry.ReadyAt, os.time()) then
		return false, "Coffin isn't READY!"
	end
	if popping[`{player.UserId}:{plate}`] then
		return false, "Unlocking!"
	end
	CoffinService.Open(player, plate, "tap")
	return true, "Unlocking!"
end

function CoffinService.Init()
	Net.Remotes.OpenCoffin.OnServerInvoke = Analytics.Remote("OpenCoffin", requestOpen)
	BaseService.OnOpenCoffin = function(player, plate)
		local ok, message = requestOpen(player, plate)
		if not ok then
			Net.Notify(player, message, "bad")
		end
	end
	Net.Remotes.CoffinTarget.OnServerEvent:Connect(function(player: Player, plate: unknown)
		if type(plate) == "number" and plate % 1 == 0 then
			target[player] = plate
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		target[player] = nil
		lastOpen[player] = nil
	end)
	-- Back from being away: the rounds you missed passed as real time (OfflineSecondsPerRound each)
	DataService.PlayerLoaded:Connect(function(player: Player)
		local profile = DataService.Get(player)
		if not profile or #profile.Sealed == 0 then
			return
		end
		local now = os.time()
		DataService.Update(player, function(p)
			for _, entry in p.Sealed do
				if entry.Rounds ~= nil then
					entry.Rounds = if entry.ReadyAt <= now
						then 0
						else math.min(
							entry.Rounds,
							math.ceil((entry.ReadyAt - now) / CONFIG.OfflineSecondsPerRound)
						)
				end
			end
		end)
		BaseService.RefreshRack(player)
	end)
	-- Refresh a due timer once so READY labels and the HUD badge update. No free income yet.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local profile = DataService.Get(player)
				if not profile then
					continue
				end
				local count = 0
				for _, entry in profile.Sealed do
					if CoffinState.Ready(entry.Rounds, entry.ReadyAt, os.time()) then
						count += 1
					end
				end
				if count ~= (player:GetAttribute("CoffinsReady") or 0) then
					BaseService.RefreshRack(player)
				end
			end
		end
	end)
end

return CoffinService
