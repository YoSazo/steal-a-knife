--!strict
-- Coffins: Steal an Egg's egg, in our theme. A stolen boss knife lands on its plate SEALED in a
-- coffin (profile.Sealed). While sealed it earns nothing and can't be equipped or sold (BaseService
-- / InventoryService check DataService.IsSealedIndex).
--
-- THE MURDER ROUNDS ARE THE CLOCK: a coffin opens after GameConfig.Coffins.Rounds[rarity] murder
-- rounds (a Common after CommonSeconds). Every round that ends counts for everyone online, a
-- round you WIN counts WinRounds. All the coffins due open together right after the results - the
-- opening ceremony: every pen pops at once, the rare ones announced to the server. Offline there
-- are no rounds, so each round still owed is OfflineSecondsPerRound of real time (ReadyAt), and a
-- coffin that finished while you were away opens when you're back.
-- The owner can open one now for Robux (product CoffinOpen; the client names the coffin first with
-- Remotes.CoffinTarget). Opening = a burst and the knife on its plate.
-- Every other mystery knife (gifts, Lucky Wheel prizes, round loot, the daily streak, the Starter
-- Pack) also arrives as a coffin: CoffinService.Give / GiveRarity. On vault servers (coffins off)
-- the knife goes straight onto the wall.
-- Off unless GameConfig.Coffins.Enabled (Studio: ReplicatedStorage attribute DebugCoffins).
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
	return luck
end

local function roundsText(rounds: number): string
	return if rounds <= 1 then "after the next murder round" else `after {math.ceil(rounds)} murder rounds`
end

-- Seals the knife on `plate` (just deposited). Returns when it opens, for the toast ("in 20s",
-- "after 2 murder rounds").
-- `seconds`: a plain short timer instead (the tutorial's coffin: you see it land and count down)
function CoffinService.Seal(player: Player, plate: number, item: string, seconds: number?): string
	local parsed = Items.Parse(item)
	local rarity = if parsed then parsed.Knife.Rarity else "Common"
	local rounds = if seconds then 0 else CONFIG.Rounds[rarity] or 1
	if seconds then
		DataService.Update(player, function(p)
			DataService.Seal(p, plate, os.time() + seconds, nil)
		end)
		Analytics.Track(player, "coffin.sealed", { rarity = rarity, rounds = 0, tutorial = true })
		return `in {Format.Duration(seconds)}`
	end
	DataService.Update(player, function(p)
		if rounds <= 0 then
			DataService.Seal(p, plate, os.time() + CONFIG.CommonSeconds, nil)
		else
			DataService.Seal(p, plate, os.time() + rounds * CONFIG.OfflineSecondsPerRound, rounds)
		end
	end)
	Analytics.Track(player, "coffin.sealed", { rarity = rarity, rounds = rounds })
	return if rounds <= 0 then `in {Format.Duration(CONFIG.CommonSeconds)}` else roundsText(rounds)
end

-- A boss's knife going into your coffin gets one more mutation / size roll with your luck (rebirths,
-- the Luck pass, potions); the better of the two is what's inside. Nobody sees it until it opens.
function CoffinService.LuckyContents(player: Player, item: string): string
	local profile = DataService.Get(player)
	local parsed = Items.Parse(item)
	if not profile or not parsed then
		return item
	end
	local luck = CoffinService.Luck(player, profile)
	if luck <= 1 then
		return item
	end
	local mutation, size = Items.Roll(rng, luck)
	local candidate = Items.Make(parsed.Name, mutation.Id, size.Id)
	return if Items.Income(candidate) > Items.Income(item) then candidate else item
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
		end)
		local when = CoffinService.Seal(player, plate, item)
		BaseService.RefreshRack(player)
		Net.Remotes.Effect:FireAllClients("Deposit", player, rarity)
		if not quiet then
			Net.Notify(player, `⚰️ A {rarity} Coffin from {source} is in your pen! It opens {when}.`, "good")
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

-- A mystery knife of this rarity (a 4% chance of one rarity up), rolled with the player's luck
function CoffinService.GiveRarity(player: Player, rarity: string, source: string, quiet: boolean?): string?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local item = Items.RollKnife(rng, rarity, CoffinService.Luck(player, profile))
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
	if not entry or not index or popping[key] then
		return
	end
	popping[key] = true
	-- The pop (client/Coffins): everyone sees it shake harder and the lid fly open, then the reveal
	local first = Items.Parse(profile.Knives[index])
	Net.Remotes.Effect:FireAllClients("CoffinPop", player.UserId, plate, if first then first.Knife.Rarity else "Common")
	task.delay(POP_TIME, function()
		popping[key] = nil
		if player.Parent then
			CoffinService.Reveal(player, plate, how)
		end
	end)
end

-- The reveal: the knife appears and flies to its owner (CoffinService.Open pops the lid first)
function CoffinService.Reveal(player: Player, plate: number, how: string)
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
	local item = profile.Knives[index]
	local parsed = Items.Parse(item)
	-- (it joins your Index now, not when the coffin landed: what's inside was a secret till now)
	local isNew = parsed ~= nil and not table.find(profile.Discovered, parsed.Name)
	DataService.Update(player, function(p)
		DataService.Unseal(p, plate)
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
	BaseService.HoldHatched(player, plate, item)
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
	Net.Notify(
		player,
		`🎉 Your coffin opened: {if isNew then "NEW! " else ""}{Items.DisplayName(item)}! +{Format.Cash(
			Items.Income(item)
		)}/s`,
		"good"
	)
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
	CoffinService.Open(player, plate, "robux")
	return true
end

-- Opens every coffin of this player that's due (round-based ones at 0 rounds left), one after the
-- other so each gets its moment
local function openDue(player: Player, how: string)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local due = {}
	for _, entry in profile.Sealed do
		if entry.Rounds ~= nil and entry.Rounds <= 0 then
			table.insert(due, entry.Plate)
		end
	end
	for i, plate in due do
		task.delay((i - 1) * 0.6, function()
			if player.Parent then
				CoffinService.Open(player, plate, how)
			end
		end)
	end
end

-- A murder round just ended (RoundService, at the results): one round off every online player's
-- coffins, WinRounds for the winners; after the results, the opening ceremony.
function CoffinService.RoundEnded(winners: { [Player]: boolean })
	local anyDue = false
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
					anyDue = anyDue or entry.Rounds == 0
				end
			end
		end)
		if changed then
			BaseService.RefreshRack(player) -- (the labels: "1 round left")
		end
	end
	if anyDue then
		-- everyone's back in the hub by then: every pen pops at once
		task.delay(GameConfig.ResultsTime + 3, function()
			for _, player in Players:GetPlayers() do
				openDue(player, "round")
			end
		end)
	end
end

function CoffinService.Init()
	Net.Remotes.CoffinTarget.OnServerEvent:Connect(function(player: Player, plate: unknown)
		if type(plate) == "number" and plate % 1 == 0 then
			target[player] = plate
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		target[player] = nil
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
		task.delay(4, openDue, player, "offline") -- (once they've landed: a welcome-back reveal)
	end)
	-- Commons (a timer, not rounds), and anything due left over (never during a round)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for _, player in Players:GetPlayers() do
				local profile = DataService.Get(player)
				if not profile or #profile.Sealed == 0 or player:GetAttribute("InRound") then
					continue
				end
				for _, entry in table.clone(profile.Sealed) do
					if entry.Rounds == nil and entry.ReadyAt <= now then
						CoffinService.Open(player, entry.Plate, "timer")
					end
				end
			end
		end
	end)
end

return CoffinService
