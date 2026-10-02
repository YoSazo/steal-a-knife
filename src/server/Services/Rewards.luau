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

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local Props = require(ReplicatedStorage.Shared.Props)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local Offers = require(script.Parent.Offers)
local StealService = require(script.Parent.StealService)

local Rewards = {}

local rng = Random.new()
-- Beside the Knife Merchant's stall
local CHEST_AT = CFrame.new(-49, 1.4, -34) * CFrame.Angles(0, math.rad(130), 0)

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
	if #profile.Knives >= profile.Slots then
		Offers.Show(player, "Mount", "Your wall is full! Add another mount instantly.")
		return false, "Your wall is full! Sell a knife or buy a mount first."
	end
	if not DataService.TrySpend(player, entry.Cost) then
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
	DataService.AddCash(player, cost)
	return `{Format.Cash(cost)} (your wall was full, so you got the {rarity} Case's value)`
end

local function claimDaily(player: Player): (boolean, string)
	local profile = DataService.Get(player)
	if not profile then
		return false, "Still loading..."
	end
	local day = dailyDay(profile)
	if not day then
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
		DataService.AddCash(player, cash)
		got = `{Format.Cash(cash)}`
	end
	Net.Notify(player, `Day {day} reward: {got}!`, "good")
	return true, got
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
	if away >= config.MinAway then
		local seconds = math.min(away, config.MaxHours * 3600)
		earned = math.floor(BaseService.RackIncome(player) * seconds * config.Fraction)
		if earned > 0 then
			DataService.AddCash(player, earned)
		end
	end
	local day = dailyDay(profile)
	Net.Remotes.Welcome:FireClient(player, {
		Offline = earned,
		Away = away,
		Streak = day or profile.DailyStreak,
		DailyReady = day ~= nil,
		Shielded = DataService.IsNewPlayer(player),
	})
end

-- Free chest ---------------------------------------------------------------------------------

local function claimFreeChest(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local now = os.time()
	if now < profile.NextFreeChest then
		Net.Notify(player, `The chest refills in {math.ceil((profile.NextFreeChest - now) / 60)} min`, "bad")
		Offers.Show(player, "ChestRefill", "Can't wait? Refill your chest right now.")
		return
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
		DataService.AddCash(player, cash)
		Net.Notify(player, `FREE CHEST: +{Format.Cash(cash)}!`, "good")
		Net.Remotes.Effect:FireClient(player, "CashBurst", CHEST_AT.Position, cash)
	end
end

local function buildChest(parent: Instance)
	local chest = Props.Build("Chest", true)
	chest.Name = "FreeChest"
	chest:ScaleTo(1.6)
	chest:PivotTo(CHEST_AT)
	for _, d in chest:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name == "Lock" or d.Name == "Seam" then
				d.Color = Color3.fromRGB(255, 220, 80)
			elseif d.Name == "Iron" then
				d.Color = Color3.fromRGB(235, 185, 60)
			elseif d.Name == "Wood" then
				d.Color = Color3.fromRGB(190, 40, 40)
			end
		end
	end
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
	-- "FREE!" floats over it; clients swap in their own countdown (see client/Hud)
	local gui = Instance.new("BillboardGui")
	gui.Name = "FreeLabel"
	gui.Size = UDim2.fromOffset(220, 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
	gui.MaxDistance = 160
	gui.Adornee = root
	gui.Parent = root
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(120, 255, 140)
	label.TextStrokeTransparency = 0
	label.Text = "FREE!"
	label.Parent = gui
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

local function claimIndex(player: Player, which: unknown): boolean
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
	DataService.Update(player, function(p)
		for _, name in names do
			table.insert(p.IndexClaimed, name)
		end
		p.Cash += cash
		p.Speed += speed
	end)
	Net.Notify(player, `Index reward: +{Format.Cash(cash)} and +{Format.Short(speed)} Speed!`, "good")
	Net.Remotes.Effect:FireClient(player, "IndexClaim", cash, speed)
	return true
end

function Rewards.Init()
	local folder = Instance.new("Folder")
	folder.Name = "PlazaRewards"
	folder.Parent = workspace:FindFirstChild("Map")
	buildChest(folder)

	Net.Remotes.ClaimIndex.OnServerInvoke = claimIndex
	Net.Remotes.ClaimDaily.OnServerInvoke = claimDaily
	DataService.PlayerLoaded:Connect(function(player: Player)
		-- After the vault is assigned and the client has its UI up
		task.delay(4, function()
			if player.Parent then
				welcome(player)
			end
		end)
	end)
	Net.Remotes.Tutorial.OnServerEvent:Connect(function(player: Player, step: unknown)
		local profile = DataService.Get(player)
		if step == "Done" and profile and not profile.TutorialDone then
			DataService.Update(player, function(p)
				p.TutorialDone = true
				p.Cash += GameConfig.TutorialReward
			end)
			Net.Notify(player, `Guide complete! +{Format.Cash(GameConfig.TutorialReward)}`, "good")
		elseif step == "Skip" and profile then
			DataService.Update(player, function(p)
				p.TutorialDone = true
			end)
		end
	end)
end

return Rewards
