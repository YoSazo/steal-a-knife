--!strict
-- The main event. Every few minutes everyone is pulled into a round: one Murderer (weighted by
-- the luck meter and tickets), everyone else survives until the timer runs out.
-- Round state is published as attributes on ReplicatedStorage for the HUD:
--   Phase ("Intermission" | "Round" | "Results"), PhaseEndsAt (server time), Status (text), Alive

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local StealService = require(script.Parent.StealService)

local RoundService = {}

type Round = {
	Murderer: Player,
	Innocents: { Player },
	Alive: { [Player]: boolean },
	Kills: number,
	Weapon: Tool?,
	LastAttack: number,
	Connections: { RBXScriptConnection },
}

local current: Round? = nil

local function setPhase(phase: string, duration: number, status: string)
	ReplicatedStorage:SetAttribute("Phase", phase)
	ReplicatedStorage:SetAttribute("PhaseEndsAt", workspace:GetServerTimeNow() + duration)
	ReplicatedStorage:SetAttribute("Status", status)
end

local function aliveCount(round: Round): number
	local n = 0
	for _ in round.Alive do
		n += 1
	end
	return n
end

local function eligiblePlayers(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if DataService.Get(player) and humanoid and humanoid.Health > 0 then
			table.insert(list, player)
		end
	end
	return list
end

-- Luck meter + tickets. Everyone has at least weight 1 so a brand new player can still get picked.
local function pickMurderer(participants: { Player }): Player
	local weights, total = {}, 0
	for _, player in participants do
		local profile = DataService.Get(player) :: DataService.Profile
		local weight = 1 + profile.Luck
		if profile.Tickets > 0 then
			weight += GameConfig.TicketWeight
			DataService.Update(player, function(p)
				p.Tickets -= 1
			end)
		end
		weights[player] = weight
		total += weight
	end
	local roll = math.random() * total
	for _, player in participants do
		roll -= weights[player]
		if roll <= 0 then
			return player
		end
	end
	return participants[#participants]
end

local function bestKnife(player: Player): string
	local profile = DataService.Get(player)
	local best, bestIncome = "RustyShank", -1
	local owned: { string } = if profile then profile.Knives else {}
	for _, name in owned do
		local knife = Knives.ByName[name]
		if knife and knife.Income > bestIncome then
			best, bestIncome = name, knife.Income
		end
	end
	return best
end

local function leaveRound(player: Player)
	player:SetAttribute("InRound", nil)
	player:SetAttribute("Role", nil)
	BaseService.RefreshWalkSpeed(player)
end

local function eliminate(round: Round, victim: Player, killer: Player?)
	if not round.Alive[victim] then
		return
	end
	round.Alive[victim] = nil
	ReplicatedStorage:SetAttribute("Alive", aliveCount(round))
	leaveRound(victim)
	if killer then
		round.Kills += 1
		DataService.AddCash(killer, GameConfig.KillReward)
		DataService.Update(killer, function(p)
			p.TotalKills += 1
		end)
		Net.Notify(killer, `Eliminated {victim.DisplayName}! +${GameConfig.KillReward}`, "good")
		Net.Notify(victim, `{killer.DisplayName} got you! You'll respawn at your vault.`, "bad")
		local humanoid = victim.Character and victim.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = 0
		end
	end
end

-- Server-side hit check: range, facing, cooldown, and the victim must still be alive in this round
local function onAttack(round: Round)
	local now = os.clock()
	if now - round.LastAttack < GameConfig.AttackCooldown then
		return
	end
	local murdererRoot = round.Murderer.Character
		and round.Murderer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not murdererRoot or not round.Alive[round.Murderer] then
		return
	end
	round.LastAttack = now

	local weapon = round.Weapon
	if weapon then
		local anim = Instance.new("StringValue")
		anim.Name = "toolanim"
		anim.Value = "Slash" -- the default Animate script plays the slash animation for this
		anim.Parent = weapon
		game:GetService("Debris"):AddItem(anim, 1)
	end

	local closest, closestDist = nil, GameConfig.AttackRange
	for player in round.Alive do
		if player ~= round.Murderer then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local offset = root.Position - murdererRoot.Position
				local dist = offset.Magnitude
				local facing = if dist > 0.1 then murdererRoot.CFrame.LookVector:Dot(offset.Unit) else 1
				if dist < closestDist and facing > -0.2 then
					closest, closestDist = player, dist
				end
			end
		end
	end
	if closest then
		eliminate(round, closest, round.Murderer)
	end
end

local function giveWeapon(round: Round)
	local backpack = round.Murderer:FindFirstChildOfClass("Backpack")
	if not backpack or not round.Alive[round.Murderer] then
		return
	end
	local tool = KnifeModel.BuildTool(bestKnife(round.Murderer))
	tool.Parent = backpack
	round.Weapon = tool
	-- Tool.Activated replicates to the server; the client never reports hits itself
	table.insert(
		round.Connections,
		tool.Activated:Connect(function()
			onAttack(round)
		end)
	)
	Net.Notify(round.Murderer, "Your knife is ready. Hunt them down!", "bad")
end

local function startRound(participants: { Player })
	local murderer = pickMurderer(participants)
	local round: Round = {
		Murderer = murderer,
		Innocents = {},
		Alive = {},
		Kills = 0,
		Weapon = nil,
		LastAttack = 0,
		Connections = {},
	}
	current = round

	-- Shuffle spawns so the Murderer's spot gives nothing away
	local spawns = table.clone(MapService.RoundSpawns)
	for i = #spawns, 2, -1 do
		local j = math.random(1, i)
		spawns[i], spawns[j] = spawns[j], spawns[i]
	end

	for i, player in participants do
		StealService.ForceDrop(player)
		local isMurderer = player == murderer
		if not isMurderer then
			table.insert(round.Innocents, player)
		end
		round.Alive[player] = true
		player:SetAttribute("InRound", true)
		player:SetAttribute("Role", if isMurderer then "Murderer" else "Innocent")
		DataService.Update(player, function(p)
			p.Luck = if isMurderer then 0 else p.Luck + 1
		end)
		local character = player.Character :: Model
		character:PivotTo(spawns[(i - 1) % #spawns + 1])
		BaseService.RefreshWalkSpeed(player)
		Net.Remotes.Role:FireClient(player, if isMurderer then "Murderer" else "Innocent")

		local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
		table.insert(
			round.Connections,
			humanoid.Died:Connect(function()
				if player == round.Murderer then
					round.Alive[player] = nil -- fell off or reset: round ends, innocents win
				else
					eliminate(round, player, nil)
				end
			end)
		)
	end
	ReplicatedStorage:SetAttribute("Alive", aliveCount(round))

	task.delay(GameConfig.MurdererGrace, function()
		if current == round then
			giveWeapon(round)
		end
	end)
end

local function endRound(round: Round)
	current = nil
	for _, connection in round.Connections do
		connection:Disconnect()
	end
	if round.Weapon then
		round.Weapon:Destroy()
	end

	local survivors = {}
	for _, player in round.Innocents do
		if round.Alive[player] and player.Parent then
			table.insert(survivors, player)
		end
	end
	local murdererPresent = round.Murderer.Parent ~= nil
	local innocentsWon = #survivors > 0
	local fewLeft = #survivors <= math.max(1, math.ceil(#round.Innocents * GameConfig.LastAliveFraction))

	for _, player in survivors do
		local reward = GameConfig.SurviveReward + (if fewLeft then GameConfig.LastAliveBonus else 0)
		DataService.AddCash(player, reward)
		DataService.Update(player, function(p)
			p.RoundsWon += 1
		end)
		Net.Notify(player, `You survived! +${reward}`, "good")
	end
	if murdererPresent then
		if not innocentsWon and round.Kills > 0 then -- no bonus when everyone just left
			DataService.AddCash(round.Murderer, GameConfig.WipeBonus)
			DataService.Update(round.Murderer, function(p)
				p.RoundsWon += 1
			end)
			Net.Notify(round.Murderer, `You got everyone! Bonus +${GameConfig.WipeBonus}`, "good")
		else
			Net.Notify(round.Murderer, `Time's up! {round.Kills} eliminated.`, "info")
		end
	end

	-- Everyone still in the round goes home
	for player in round.Alive do
		if player.Parent then
			leaveRound(player)
			BaseService.TeleportHome(player)
		end
	end
	leaveRound(round.Murderer)

	local status = if innocentsWon
		then `Innocents win! {#survivors} survived`
		else `The Murderer wins! ({round.Murderer.DisplayName})`
	setPhase("Results", GameConfig.ResultsTime, status)
end

local function roundOver(round: Round): boolean
	if not round.Alive[round.Murderer] or not round.Murderer.Parent then
		return true
	end
	for player in round.Alive do
		if player ~= round.Murderer and player.Parent then
			return false
		end
	end
	return true
end

local function loop()
	while true do
		-- Intermission: steal knives, earn cash, buy upgrades
		setPhase("Intermission", GameConfig.IntermissionTime, "Next round in")
		local endsAt = os.clock() + GameConfig.IntermissionTime
		while os.clock() < endsAt do
			task.wait(1)
			if #Players:GetPlayers() < GameConfig.MinPlayers then
				-- Hold the timer until enough people are here
				endsAt = os.clock() + GameConfig.IntermissionTime
				setPhase("Intermission", GameConfig.IntermissionTime, `Waiting for {GameConfig.MinPlayers} players`)
			elseif ReplicatedStorage:GetAttribute("Status") ~= "Next round in" then
				setPhase("Intermission", endsAt - os.clock(), "Next round in")
			end
		end

		local participants = eligiblePlayers()
		if #participants < GameConfig.MinPlayers then
			continue
		end

		startRound(participants)
		local round = current :: Round
		setPhase("Round", GameConfig.RoundTime, "Survive!")
		local roundEnds = os.clock() + GameConfig.RoundTime
		while os.clock() < roundEnds and not roundOver(round) do
			task.wait(0.25)
		end
		endRound(round)
		task.wait(GameConfig.ResultsTime)
	end
end

function RoundService.Init()
	Players.PlayerRemoving:Connect(function(player)
		local round = current
		if round and round.Alive[player] then
			round.Alive[player] = nil
			ReplicatedStorage:SetAttribute("Alive", aliveCount(round))
		end
	end)
	task.spawn(loop)
end

return RoundService
