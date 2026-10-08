--!strict
-- Little reasons to come back:
--   * the Index: a one-time reward for every knife you've ever owned (Remotes.ClaimIndex)
--   * the first-minute guide: a little reward for finishing it (Remotes.Tutorial)
--   * coming back: the vault's offline earnings and the 7-day login streak (Remotes.Welcome on
--     join, Remotes.ClaimDaily)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local Net = require(script.Parent.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)
local CoffinService = require(script.Parent.CoffinService)
local Analytics = require(script.Parent.Analytics)

local Rewards = {}

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
	if reward.Kind == "Coffin" then
		got = CoffinService.GiveOrCash(player, reward.Rarity or "Common", "your daily streak")
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
	Net.Remotes.ClaimIndex.OnServerInvoke = Analytics.Remote("ClaimIndex", claimIndex)
	Net.Remotes.ClaimDaily.OnServerInvoke = Analytics.Remote("ClaimDaily", claimDaily)
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
