--!strict
-- Little reasons to come back and look around the plaza:
--   * the Case Shop: sealed cases for cash, opened on the spot
--   * the free chest on the plaza: every FreeChest.Cooldown, cash (scaled to your income) or a case
--   * the Index: a one-time reward for every knife you've ever owned (Remotes.ClaimIndex)
--   * the first-minute guide: a little reward for finishing it (Remotes.Tutorial)
--   * leaderboards on the plaza's back wall: Most Money/s and Top Thieves
--   * coming back: the vault's offline earnings and the 7-day login streak (Remotes.Welcome on
--     join, Remotes.ClaimDaily)
-- The Case Shop goes through UpgradeService's Purchase remote ("Case:<Rarity>").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local Props = require(ReplicatedStorage.Shared.Props)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local StealService = require(script.Parent.StealService)

local Rewards = {}

local rng = Random.new()
local CHEST_AT = CFrame.new(-17, 1.4, -174) * CFrame.Angles(0, math.rad(25), 0)

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
		return false, "Your wall is full! Sell a knife or buy a mount first."
	end
	if not DataService.TrySpend(player, entry.Cost) then
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
	return `${cost} (your wall was full, so you got the {rarity} Case's value)`
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
		got = `${cash}`
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
		return
	end
	local config = GameConfig.FreeChest
	DataService.Update(player, function(p)
		p.NextFreeChest = now + config.Cooldown
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
		Net.Notify(player, `FREE CHEST: +${cash}!`, "good")
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
	Net.Notify(player, `Index reward: +${cash} and +{speed} Speed!`, "good")
	Net.Remotes.Effect:FireClient(player, "IndexClaim", cash, speed)
	return true
end

-- Leaderboards on the plaza's back wall --------------------------------------------------------

type Board = { Rows: { TextLabel }, Stat: (Player) -> number, Format: (number) -> string }

local function abbreviate(n: number): string
	local suffixes = { "", "K", "M", "B", "T" }
	local i = 1
	while n >= 1000 and i < #suffixes do
		n /= 1000
		i += 1
	end
	return if i == 1 then tostring(math.floor(n)) else string.format("%.1f%s", n, suffixes[i])
end

local function buildBoard(parent: Instance, at: CFrame, title: string, color: Color3): { TextLabel }
	local frame = Instance.new("Part")
	frame.Name = `Board_{title}`
	frame.Anchored = true
	frame.Size = Vector3.new(15, 11, 0.6)
	frame.CFrame = at
	frame.Color = Color3.fromRGB(26, 22, 34)
	frame.Material = Enum.Material.Wood
	frame.Parent = parent
	local trim = Instance.new("Part")
	trim.Name = "Trim"
	trim.Anchored = true
	trim.CanCollide = false
	trim.Size = Vector3.new(15.8, 11.8, 0.3)
	trim.CFrame = at * CFrame.new(0, 0, 0.3)
	trim.Color = color
	trim.Material = Enum.Material.Neon
	trim.Parent = parent
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Back
	light.Color = color
	light.Range = 12
	light.Brightness = 1.2
	light.Parent = frame
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.CanvasSize = Vector2.new(450, 330)
	gui.LightInfluence = 0
	gui.Parent = frame
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, 0, 0, 56)
	header.BackgroundColor3 = color
	header.Font = Enum.Font.FredokaOne
	header.TextScaled = true
	header.TextColor3 = Color3.new(1, 1, 1)
	header.TextStrokeTransparency = 0
	header.Text = title
	header.Parent = gui
	local rows = {}
	for i = 1, 8 do
		local row = Instance.new("TextLabel")
		row.Position = UDim2.fromOffset(12, 60 + (i - 1) * 33)
		row.Size = UDim2.new(1, -24, 0, 30)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.FredokaOne
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = if i == 1
			then Color3.fromRGB(255, 215, 60)
			elseif i == 2 then Color3.fromRGB(220, 225, 235)
			elseif i == 3 then Color3.fromRGB(230, 150, 90)
			else Color3.fromRGB(200, 200, 215)
		row.TextStrokeTransparency = 0.3
		row.Text = ""
		row.Parent = gui
		table.insert(rows, row)
	end
	return rows
end

local function refreshBoard(board: Board)
	local list = {}
	for _, player in Players:GetPlayers() do
		table.insert(list, { Player = player, Value = board.Stat(player) })
	end
	table.sort(list, function(a, b)
		return a.Value > b.Value
	end)
	for i, row in board.Rows do
		local entry = list[i]
		row.Text = if entry then `{i}. {entry.Player.DisplayName}  —  {board.Format(entry.Value)}` else ""
	end
end

function Rewards.Init()
	local folder = Instance.new("Folder")
	folder.Name = "PlazaRewards"
	folder.Parent = workspace:FindFirstChild("Map")
	buildChest(folder)

	-- Facing into the plaza from its back wall
	local boards: { Board } = {
		{
			Rows = buildBoard(
				folder,
				CFrame.new(-16, 12, -187.6) * CFrame.Angles(0, math.pi, 0),
				"MOST MONEY/S",
				Color3.fromRGB(70, 200, 110)
			),
			Stat = function(player)
				return (player:GetAttribute("Income") or 0) :: number
			end,
			Format = function(n)
				return `${abbreviate(n)}/s`
			end,
		},
		{
			Rows = buildBoard(
				folder,
				CFrame.new(16, 12, -187.6) * CFrame.Angles(0, math.pi, 0),
				"TOP THIEVES",
				Color3.fromRGB(220, 60, 80)
			),
			Stat = function(player)
				return (player:GetAttribute("KnivesStolen") or 0) :: number
			end,
			Format = function(n)
				return `{abbreviate(n)} stolen`
			end,
		},
	}
	task.spawn(function()
		while true do
			for _, board in boards do
				refreshBoard(board)
			end
			task.wait(5)
		end
	end)

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
			Net.Notify(player, `Guide complete! +${GameConfig.TutorialReward}`, "good")
		elseif step == "Skip" and profile then
			DataService.Update(player, function(p)
				p.TutorialDone = true
			end)
		end
	end)
end

return Rewards
