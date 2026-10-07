--!strict
-- Little reasons to come back and look around the plaza:
--   * the Case Shop: sealed cases for cash, opened on the spot
--   * the free chest on the plaza: every FreeChest.Cooldown, cash (scaled to your income) or a case
--   * the Index: a one-time reward for every knife you've ever owned (Remotes.ClaimIndex)
--   * the first-minute guide: a little reward for finishing it (Remotes.Tutorial)
--   * coming back: the vault's offline earnings and the 7-day login streak (Remotes.Welcome on
--     join, Remotes.ClaimDaily)
-- The Case Shop goes through UpgradeService's Purchase remote ("Case:<Rarity>").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local WorldSignModel = require(ReplicatedStorage.Shared.WorldSignModel)

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local ToyBlockModel = require(ReplicatedStorage.Shared.ToyBlockModel)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local Offers = require(script.Parent.Offers)
local StealService = require(script.Parent.StealService)
local Analytics = require(script.Parent.Analytics)

local Rewards = {}

local rng = Random.new()
-- Beside the Knife Merchant's stall
local CHEST_AT = CFrame.new(-49, 1.4, -34) * CFrame.Angles(0, math.rad(130 + 180), 0) -- lid faces the plaza

-- Case Shop -----------------------------------------------------------------------------------

function Rewards.BuyCase(player: Player, rarity: string): (boolean, string)
	local entry = nil
	for _, e in GameConfig.CaseShop do
		if e.Rarity == rarity then
			entry = e
		end
	end
	local profile = DataService.Get(player)
	if not entry or not profile then
		return false, "Unknown case"
	end
	if player:GetAttribute("InRound") then
		return false, "Not during a round!"
	end
	-- Cash can't skip the climb: only cases up to the deepest biome your Speed reaches
	local reached = GameConfig.RarityReached(profile.Speed)
	if Knives.Rank(rarity) > Knives.Rank(reached) then
		return false, `Reach the {rarity} biome first (train your Speed)!`
	end
	if #profile.Knives >= profile.Slots then
		Offers.Show(player, "Mount", "Your vault is full! Get more room right now.")
		return false, "Your vault is full! Sell a knife first."
	end
	if not DataService.TrySpend(player, entry.Cost, "case_shop") then
		Offers.Cash(player, entry.Cost - profile.Cash, BaseService.RackIncome(player))
		return false, "Not enough cash"
	end
	StealService.OpenCase(player, rarity)
	return true, `Opening a {rarity} Case...`
end

-- Coming back ---------------------------------------------------------------------------------

local function today(): number
	return math.floor(os.time() / 86400)
end

-- Which streak day they'd claim today, or nil if today's is already claimed. Missing a day starts
-- the streak over; after day 7 it wraps back to day 1.
local function dailyDay(profile: DataService.Profile): number?
	local day = today()
	if profile.LastDaily == day then
		return nil
	end
	if profile.LastDaily == day - 1 and profile.DailyStreak > 0 then
		return profile.DailyStreak % #GameConfig.Daily + 1
	end
	return 1
end

-- A case they can't fit on the wall turns into cash instead (what the Case Shop charges for it)
local function giveCase(player: Player, rarity: string): string
	local profile = DataService.Get(player)
	if profile and #profile.Knives < profile.Slots then
		StealService.OpenCase(player, rarity)
		return `a {rarity} Case`
	end
	local cost = 250
	for _, entry in GameConfig.CaseShop do
		if entry.Rarity == rarity then
			cost = entry.Cost
		end
	end
	DataService.AddCash(player, cost, "case_value")
	return `{Format.Cash(cost)} (your wall was full, so you got the {rarity} Case's value)`
end

local function claimDaily(player: Player): (boolean, string)
	local profile = DataService.Get(player)
	if not profile then
		return false, "Still loading..."
	end
	local day = dailyDay(profile)
	if not day then
		Net.Notify(player, "Already claimed today - come back tomorrow!", "info")
		return false, "Already claimed today - come back tomorrow!"
	end
	local reward = GameConfig.Daily[day]
	DataService.Update(player, function(p)
		p.DailyStreak = day
		p.LastDaily = today()
	end)
	local got
	if reward.Kind == "Case" then
		got = giveCase(player, reward.Rarity or "Common")
	elseif reward.Kind == "Tickets" then
		local amount = reward.Amount or 1
		DataService.Update(player, function(p)
			p.Tickets = math.min(GameConfig.MaxTickets, p.Tickets + amount)
		end)
		got = `{amount} Murderer Tickets`
	else
		local cash =
			GameConfig.Pay({ Min = reward.Min or 100, Seconds = reward.Seconds or 60 }, BaseService.RackIncome(player))
		DataService.AddCash(player, cash, "daily")
		got = `{Format.Cash(cash)}`
	end
	Net.Notify(player, `Day {day} reward: {got}!`, "good")
	return true, got
end

-- Robux "Save My Streak": the streak a missed day broke carries on as if they hadn't missed it
function Rewards.RestoreStreak(player: Player): boolean
	local profile = DataService.Get(player)
	if not profile or profile.LostStreak <= 0 then
		return false
	end
	local lost = profile.LostStreak
	DataService.Update(player, function(p)
		if p.LastDaily == today() then
			-- Already claimed day 1 today: that claim becomes the next day of the old streak
			p.DailyStreak = lost % #GameConfig.Daily + 1
		else
			-- Not claimed yet: as if yesterday was claimed, so today continues the streak
			p.DailyStreak = lost
			p.LastDaily = today() - 1
		end
		p.LostStreak = 0
	end)
	return true
end

-- On join: pay what the vault earned while they were away, and tell the client about it and
-- about today's streak reward (it shows the welcome-back card)
local function welcome(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local awaySince = DataService.AwaySince[player] or 0
	local away = if awaySince > 0 then os.time() - awaySince else 0
	local earned = 0
	local config = GameConfig.Offline
	-- (passes are checked asynchronously on join)
	for _ = 1, 20 do
		if player:GetAttribute("PassesChecked") then
			break
		end
		task.wait(0.25)
	end
	local plus = player:GetAttribute("Pass_OfflinePlus") == true
	if away >= config.MinAway then
		local seconds = math.min(away, (if plus then 24 else config.MaxHours) * 3600)
		earned = math.floor(BaseService.RackIncome(player) * seconds * (if plus then 1 else config.Fraction))
		if earned > 0 then
			DataService.AddCash(player, earned, "offline")
		end
	end
	-- What Double Offline Earnings would pay again (only this visit's payout)
	DataService.Update(player, function(p)
		p.LastOffline = earned
	end)
	-- Missed a day with a streak going: remember it, Save My Streak brings it back
	local day = dailyDay(profile)
	local lostStreak = 0
	if day == 1 and profile.DailyStreak >= 2 and profile.LastDaily < today() - 1 then
		lostStreak = profile.DailyStreak
		DataService.Update(player, function(p)
			p.LostStreak = lostStreak
		end)
	end
	Analytics.Track(player, "reward.welcome", {
		offline = earned,
		away_h = math.floor(away / 360) / 10,
		streak_day = day or profile.DailyStreak,
		daily_ready = day ~= nil,
		lost_streak = lostStreak,
	})
	Net.Remotes.Welcome:FireClient(player, {
		Offline = earned,
		Away = away,
		Streak = day or profile.DailyStreak,
		DailyReady = day ~= nil,
		LostStreak = if lostStreak > 0 then lostStreak else nil,
		Shielded = DataService.IsNewPlayer(player),
	})
end

-- Free chest ---------------------------------------------------------------------------------

local function claimFreeChest(player: Player): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end
	local now = os.time()
	if now < profile.NextFreeChest then
		Net.Notify(player, `The chest refills in {math.ceil((profile.NextFreeChest - now) / 60)} min`, "bad")
		Offers.Show(player, "ChestRefill", "Can't wait? Refill your chest right now.")
		return false
	end
	local config = GameConfig.FreeChest
	DataService.Update(player, function(p)
		-- VIP: the chest refills twice as fast
		p.NextFreeChest = now + (if player:GetAttribute("Pass_VIP") then config.Cooldown / 2 else config.Cooldown)
	end)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		Net.Remotes.Effect:FireAllClients("ChestOpen", CHEST_AT.Position, player)
	end
	-- Sometimes a case (better the further you've got), otherwise a pile of cash
	if rng:NextNumber() < config.CaseChance and #profile.Knives < profile.Slots then
		local best = 1
		for _, item in profile.Knives do
			local name = item:match("^[^|]+") or item
			local knife = Knives.ByName[name]
			best = math.max(best, if knife then table.find(Knives.Rarities, knife.Rarity) or 1 else 1)
		end
		local rarityIndex = math.clamp(best - (if rng:NextNumber() < 0.7 then 1 else 0), 1, #Knives.Rarities)
		local rarity = Knives.Rarities[rarityIndex]
		Net.Notify(player, `FREE CHEST: a {rarity} Case!`, "good")
		StealService.OpenCase(player, rarity)
	else
		local cash = math.max(
			config.MinCash,
			math.floor(BaseService.RackIncome(player) * config.IncomeSeconds * rng:NextNumber(0.8, 1.4))
		)
		DataService.AddCash(player, cash, "free_chest")
		Net.Notify(player, `FREE CHEST: +{Format.Cash(cash)}!`, "good")
		Net.Remotes.Effect:FireClient(player, "CashBurst", CHEST_AT.Position, cash)
	end
	return true
end

local function buildChest(parent: Instance)
	local chest = ToyBlockModel.Build("FreeChest", true)
	chest.Name = "FreeChest"
	chest:ScaleTo(1.6)
	chest:PivotTo(CHEST_AT)
	chest:AddTag("FreeChest")
	chest.Parent = parent
	local root = chest.PrimaryPart :: BasePart
	-- A glowing ring on the floor around it
	local ring = Instance.new("Part")
	ring.Name = "ChestRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(120, 255, 140)
	ring.Transparency = 0.55
	ring.Size = Vector3.new(0.15, 9, 9)
	ring.CFrame = CFrame.new(CHEST_AT.Position.X, 0.25, CHEST_AT.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = chest
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 120)
	light.Range = 16
	light.Brightness = 2
	light.Parent = root
	local plaque = Instance.new("Part")
	plaque.Name, plaque.Size = "FreeChestSign", Vector3.new(8, 5, 0.2)
	plaque.CFrame = root.CFrame * CFrame.new(0, 6.5, 0)
	plaque.Anchored, plaque.CanCollide, plaque.CanQuery, plaque.CanTouch = true, false, false, false
	plaque.Parent = chest
	local _, liveFace = WorldSignModel.Attach("FreeChestLabel", plaque, Enum.NormalId.Front)
	WorldSignModel.LiveText(
		WorldSignModel.Surface(plaque, liveFace, "FreeLabel", 160),
		"Text",
		"FREE!",
		Color3.fromRGB(120, 255, 140)
	)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = "Free Chest"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(claimFreeChest)
end

-- Index rewards -------------------------------------------------------------------------------

local function claimIndex(player: Player, which: unknown): (boolean, { string }?)
	local profile = DataService.Get(player)
	if not profile or type(which) ~= "string" then
		return false
	end
	local names = {}
	for _, name in profile.Discovered do
		if not table.find(profile.IndexClaimed, name) and (which == "All" or which == name) then
			table.insert(names, name)
		end
	end
	if #names == 0 then
		Net.Notify(player, "Find new knives to get rewards!", "info")
		return false
	end
	local cash, speed = 0, 0
	for _, name in names do
		local knife = Knives.ByName[name]
		local reward = knife and GameConfig.IndexRewards[knife.Rarity]
		if reward then
			cash += reward.Cash
			speed += reward.Speed
		end
	end
	DataService.CashFlow(player, cash, "index")
	DataService.Update(player, function(p)
		for _, name in names do
			table.insert(p.IndexClaimed, name)
		end
		p.Cash += cash
		p.Speed += speed
	end)
	Net.Notify(player, `Index reward: +{Format.Cash(cash)} and +{Format.Short(speed)} Speed!`, "good")
	Net.Remotes.Effect:FireClient(player, "IndexClaim", cash, speed)
	DataService.LearnGuidance(player, "index")
	return true, table.clone(profile.IndexClaimed)
end

function Rewards.Init()
	local function watchDeliveries(player: Player)
		player:GetAttributeChangedSignal("KnifePlacementSerial"):Connect(function()
			DataService.LearnGuidance(player, "delivery")
		end)
	end
	Players.PlayerAdded:Connect(watchDeliveries)
	for _, player in Players:GetPlayers() do
		watchDeliveries(player)
	end
	local folder = Instance.new("Folder")
	folder.Name = "PlazaRewards"
	folder.Parent = workspace:FindFirstChild("Map")
	buildChest(folder)

	Net.Remotes.ClaimIndex.OnServerInvoke = Analytics.Remote("ClaimIndex", claimIndex)
	Net.Remotes.ClaimDaily.OnServerInvoke = Analytics.Remote("ClaimDaily", claimDaily)
	Net.Remotes.ClaimFreeChest.OnServerInvoke = Analytics.Remote("ClaimFreeChest", function(player: Player)
		return claimFreeChest(player)
	end)
	DataService.PlayerLoaded:Connect(function(player: Player)
		-- After the vault is assigned and the client has its UI up
		task.delay(4, function()
			if player.Parent then
				welcome(player)
			end
		end)
	end)
	Net.Remotes.Tutorial.OnServerEvent:Connect(function(player: Player, step: unknown, at: unknown)
		local profile = DataService.Get(player)
		if step == "GuideMode" and profile and (at == "Auto" or at == "On" or at == "Off") then
			DataService.Update(player, function(p)
				p.GuidanceMode = at :: string
			end)
		elseif step == "GuideLearn" and type(at) == "string" and at ~= "delivery" then
			-- These only retire help on this player's screen; no rewards or gameplay advantages.
			DataService.LearnGuidance(player, at)
		elseif step == "Done" and profile and not profile.TutorialDone then
			DataService.Update(player, function(p)
				p.TutorialDone = true
				p.Cash += GameConfig.TutorialReward
			end)
			DataService.CashFlow(player, GameConfig.TutorialReward, "tutorial")
			Net.Notify(player, `You did it! +{Format.Cash(GameConfig.TutorialReward)}`, "good")
		elseif step == "Skip" and profile then
			DataService.Update(player, function(p)
				p.TutorialDone = true
			end)
		elseif step == "Step" and profile and not profile.TutorialDone and type(at) == "number" and at == at then
			-- A delayed client step must not undo a server-confirmed placement or later progress.
			DataService.Update(player, function(p)
				p.TutorialStep = math.max(p.TutorialStep, math.clamp(math.floor(at), 1, 10))
			end)
		elseif step == "Tip" and profile and type(at) == "string" and #at <= 24 and #profile.Tips < 60 then
			-- a one-time tip was shown (client/Tips): never again
			if not table.find(profile.Tips, at) then
				DataService.Update(player, function(p)
					table.insert(p.Tips, at)
				end)
			end
		end
	end)
end

return Rewards
