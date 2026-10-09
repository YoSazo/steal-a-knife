--!strict
-- The main event. Every few minutes everyone is pulled into a round: one Murderer (weighted by
-- the luck meter and tickets), everyone else survives until the timer runs out.
-- Round state is published as attributes on ReplicatedStorage for the HUD:
--   Phase ("Intermission" | "Round" | "Results"), PhaseEndsAt (server time), Status (text), Alive
--
-- Classic murder-game rules: a random indoor map, everyone disguised as a named character
-- (Disguises), bodies stay where they fall, and a Revolver drops mid-round that any innocent can
-- grab. The two halves of the game feed each other:
--   * every kill loots a random knife off the victim's rack, kept unless the Revolver ends them
--   * survivors get a temporary income boost back at their vault
-- Innocents also bring items from the pre-round shop and pick up coins while they hide.
-- Every ability and shot goes through a remote and is validated here.
--
-- Studio-only switches (set as attributes on ReplicatedStorage from the command bar):
--   DebugMinPlayers = 1   start rounds with fewer players
--   DebugSkip = true      end the current intermission now
-- The Studio "Bot Round" buttons (RoundService.DebugBotRound) fill the round with RoundBots so one
-- person can play either side: as the Murderer against innocent bots, or as an innocent against
-- a Murderer bot (plus a couple of innocent bots for it to chase).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimLibrary = require(ReplicatedStorage.Shared.AnimLibrary)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local RoundPrize = require(ReplicatedStorage.Shared.RoundPrize)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local ChanceMeter = require(script.Parent.ChanceMeter)
local MapService = require(script.Parent.MapService)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local Disguises = require(script.Parent.Disguises)
local Revolver = require(script.Parent.Revolver)
local StuckKnives = require(script.Parent.StuckKnives)
local StealService = require(script.Parent.StealService)
local GuardService = require(script.Parent.GuardService)
local RoundBots = require(script.Parent.RoundBots)
local Analytics = require(script.Parent.Analytics)
local CoffinService = require(script.Parent.CoffinService)
local SurpriseGifts = require(script.Parent.SurpriseGifts)

local Progress = require(script.Parent.RoundProgress)
local RoundService = {}

-- The hub's top timer. Says what's coming, so a new player knows the Murder Mystery half exists.
local INTERMISSION_STATUS = "🔪 MURDER ROUND in"
RoundService.IntermissionStatus = INTERMISSION_STATUS
-- A first-time player joined during this intermission: their first round comes sooner, so they
-- see both halves of the game while they're still deciding whether to stay (once per intermission)
local newcomerWaiting = false

type Bot = RoundBots.Bot

type Round = {
	Murderer: Player?, -- nil when a bot is the Murderer
	MurdererBot: Bot?,
	Sheriff: Player?, -- the first Sheriff (for the end-of-round card), whoever holds the gun later
	SheriffBot: Bot?,
	Bots: { Bot },
	BotFolder: Folder,
	Innocents: { Player },
	Alive: { [Player]: boolean },
	Kills: number,
	Weapon: Tool?,
	WeaponKnife: string,
	LastAttack: number,
	Coins: Folder,
	Bodies: Folder,
	Names: { [Player]: string },
	Revolver: Model?, -- the pickup while it's lying somewhere
	Gunner: Player?, -- whoever holds it
	GunTool: Tool?,
	LastShot: number,
	ThrowReadyAt: number,
	StabHint: { Target: Model, At: number }?, -- who the Murderer's client says the last swing was at
	Hero: Player?,
	HumanKills: number, -- real players the Murderer got (bots don't count toward the wipe prize)
	Connections: { RBXScriptConnection },
	GunnerBot: Bot?, -- a bot Sheriff
	ShotByBot: boolean, -- a bot shot the (player) Murderer: loot goes home like a hero's shot
	Newcomer: boolean, -- a brand-new player's first round as the Murderer: the bots let them win
	HeroBot: Bot?, -- that bot (its face goes on the VS card)
	Id: string, -- analytics: round_id on every round event
	RevealEndsAt: number, -- server time shared by the reveal, hiding ladder and weapons
	StartedAt: number, -- os.clock()
	Map: string,
	KnifeShownAt: number?, -- os.clock() the Murderer first pulled the knife out
}

local current: Round? = nil
-- Where each player was dropped into the current round (the fall net puts them back here)
local spawnOf: { [Player]: CFrame } = {}

-- Pins a character in place for a moment while the round map streams in around them: the client
-- owns its character's physics, so with the floor not loaded yet it fell straight through the sky
local function holdWhileStreaming(player: Player, character: Model, at: CFrame)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = true
	task.spawn(function()
		pcall(player.RequestStreamAroundAsync, player, at.Position, 3)
		task.wait(0.4) -- (a moment for the parts to land on the client)
		if root.Parent then
			root.Anchored = false
		end
	end)
end
local rng = Random.new()

-- player attribute the client reads too)
-- Is this player one of the round's Murderers?
local function isKiller(round: Round, player: Player?): boolean
	return player ~= nil and player == round.Murderer
end

-- The second Murderer gets their own copy of the per-Murderer fields (Murderer, knife, cooldowns);
-- everything else reads and writes the real round. So every Murderer function just takes a round.
local function isLive(round: Round): boolean
	return current == round
end

local function killerRound(round: Round, player: Player): Round?
	if player == round.Murderer then
		return round
	end
	return nil
end

-- Set by the Studio "Bot Round" buttons; used by the next round
local botPlan: { Player: Player, Role: string }? = nil

local function setPhase(phase: string, duration: number, status: string)
	ReplicatedStorage:SetAttribute("Phase", phase)
	ReplicatedStorage:SetAttribute("PhaseEndsAt", workspace:GetServerTimeNow() + duration)
	ReplicatedStorage:SetAttribute("Status", status)
end

local function minPlayers(): number
	local override = ReplicatedStorage:GetAttribute("DebugMinPlayers")
	if RunService:IsStudio() and type(override) == "number" then
		return math.max(1, override)
	end
	-- Bots fill rounds in, so one real player is enough
	if GameConfig.BotFill.Size > 0 then
		return GameConfig.BotFill.MinHumans
	end
	return GameConfig.MinPlayers
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Round pay scales with what the player's vault earns (GameConfig.RoundPay); returns the amount

local function aliveCount(round: Round): number
	local n = 0
	for _ in round.Alive do
		n += 1
	end
	for _, bot in round.Bots do
		if bot.Alive then
			n += 1
		end
	end
	return n
end

-- When each player joined this server: nobody is pulled into a round in their first
-- GameConfig.RoundJoinGrace seconds (an ad player was dragged in 16 s after joining, died, left)
local joinedAt: { [Player]: number } = {}
Players.PlayerAdded:Connect(function(player)
	joinedAt[player] = os.clock()
end)
Players.PlayerRemoving:Connect(function(player)
	joinedAt[player] = nil
end)

local function eligiblePlayers(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local here = os.clock() - (joinedAt[player] or -math.huge)
		local profile = DataService.Get(player)
		-- No round before your first knife is home: the newcomer pull-in
		-- dragged new players out mid-tutorial
		local debugSolo = RunService:IsStudio() and ReplicatedStorage:GetAttribute("DebugMinPlayers") == 1
		local fresh = (not debugSolo and here < GameConfig.RoundJoinGrace) or (profile ~= nil and #profile.Knives == 0)
		if DataService.Get(player) and humanoid and humanoid.Health > 0 and not fresh then
			table.insert(list, player)
		end
	end
	return list
end

-- One player's draw weight (luck meter, pass, a ticket waiting to be used)
local function murdererWeight(player: Player): number
	local profile = DataService.Get(player)
	local weight = 1 + (if profile then profile.Luck else 0)
	return weight + (if profile and profile.Tickets > 0 then GameConfig.TicketWeight else 0)
end

-- Nobody's weight may be more than MeterCap x the average, so grinders can't hog the knife
local function cappedWeights(players: { Player }): { [Player]: number }
	local raw, total = {}, 0
	for _, player in players do
		raw[player] = murdererWeight(player)
		total += raw[player]
	end
	local cap = if #players > 1 then total / #players * GameConfig.MurdererMeter.Cap else math.huge
	for player, weight in raw do
		raw[player] = math.min(weight, cap)
	end
	return raw
end

-- Everyone's chance (0-100) of the knife next round, shown on their HUD (MurdererChance)
local function publishChances()
	local players = {}
	for _, player in Players:GetPlayers() do
		if DataService.Get(player) then
			table.insert(players, player)
		end
	end
	local weights = cappedWeights(players)
	local total = 0
	for _, weight in weights do
		total += weight
	end
	-- Alone, bots fill the round and one of them can draw the knife instead
	if #players == 1 then
		total += math.max(0, GameConfig.BotFill.Size - 1)
	end
	for _, player in players do
		local chance = if total > 0 then weights[player] / total * 100 else 0
		player:SetAttribute("MurdererChance", math.floor(chance + 0.5))
	end
end

-- Luck meter + tickets. Everyone has at least weight 1 so a brand new player can still get picked.
local function pickMurderer(participants: { Player }): Player
	local weights = cappedWeights(participants)
	local total = 0
	for player, weight in weights do
		total += weight
		local profile = DataService.Get(player)
		if profile and profile.Tickets > 0 then
			DataService.Update(player, function(p)
				p.Tickets -= 1
			end)
		end
	end
	local roll = rng:NextNumber() * total
	for _, player in participants do
		roll -= weights[player]
		if roll <= 0 then
			return player
		end
	end
	return participants[#participants]
end

-- The knife they fight with (BaseService.BestKnife: their pick, else their best power - the same
-- knife whose power the HUD shows), else the Rusty Shank
local function murdererKnife(player: Player): string
	return BaseService.BestKnife(player) or "RustyShank"
end

-- Analytics: the round as this player saw it ------------------------------------------------
local function roleOf(round: Round, player: Player): string
	if isKiller(round, player) then
		return "murderer"
	elseif round.Sheriff == player or round.Gunner == player then
		return "sheriff"
	end
	return "innocent"
end
local function roundProps(round: Round, player: Player, extra: { [string]: any }?): { [string]: any }
	local props: { [string]: any } = {
		round_id = round.Id,
		role = roleOf(round, player),
		map = round.Map,
		round_s = math.floor(os.clock() - round.StartedAt),
		alive = aliveCount(round),
		bots = #round.Bots,
		bot_murderer = round.MurdererBot ~= nil,
	}
	if extra then
		for key, value in extra do
			props[key] = value
		end
	end
	return props
end

local function leaveRound(player: Player)
	-- Hide the round ability first; CombatService re-arms the hub knife (and its Throw button)
	-- when InRound clears
	if player.Parent then
		Net.Remotes.AbilityState:FireClient(player, nil)
	end
	player:SetAttribute("InRound", nil)
	player:SetAttribute("Role", nil)
	player:SetAttribute("RoundSpeedBonus", nil)
	player:SetAttribute("Dread", nil)
	player:SetAttribute("KnifeOut", nil)
	for _, attribute in { "WeaponAt", "RevolverReadyAt" } do
		player:SetAttribute(attribute, nil)
	end
	BaseService.RefreshWalkSpeed(player)
end

-- Bodies stay on the floor until the round ends, like the classic. The character ragdolls when it
-- dies (CombatService); once it has collapsed we freeze a copy of it where it fell, so the body
-- stays after the player respawns at their vault.
local function leaveBody(round: Round, player: Player)
	local character = player.Character
	if not character then
		return
	end
	task.delay(2.2, function()
		if current ~= round or not character.Parent then
			return
		end
		character.Archivable = true
		local ok, clone = pcall(character.Clone, character)
		local body = (clone :: any) :: Model?
		if not ok or not body then
			return
		end
		for _, d in body:GetDescendants() do
			if d:IsA("BaseScript") or d:IsA("Tool") or d:IsA("Humanoid") or d:IsA("Sound") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		body.Name = `Body_{round.Names[player] or player.Name}`
		body.Parent = round.Bodies
	end)
end

-- Puts a knife on a rack, or pays its sell value if the rack is full

-- Hands a round prize over (RoundPrize: the same numbers the countdown showed) and pops it up

local spawnRevolver: (Round, Vector3?) -> ()
local giveRevolver: (Round, Player) -> ()
local giveWeapon: (Round) -> ()
local giveRevolverToBot: (Round, Bot) -> ()

local function dropRevolver(round: Round, position: Vector3)
	if round.GunTool then
		round.GunTool:Destroy()
		round.GunTool = nil
	end
	round.Gunner = nil
	spawnRevolver(round, position)
end

-- Innocents (players and bots) still standing
local function innocentsLeft(round: Round): number
	local n = 0
	for player in round.Alive do
		if not isKiller(round, player) then
			n += 1
		end
	end
	for _, bot in round.Bots do
		if bot.Alive and bot ~= round.MurdererBot then
			n += 1
		end
	end
	return n
end

-- The last innocent falls (or the Murderer is shot): everyone in the round gets the dramatic
-- slow-mo moment on their screen
local function finalMoment(round: Round, position: Vector3, kind: string)
	for player in round.Names do
		if player.Parent then
			Net.Remotes.Effect:FireClient(player, "FinalKill", position, kind)
		end
	end
end

local function knifeKillEffect(round: Round, position: Vector3)
	local parsed = Items.Parse(round.WeaponKnife)
	if parsed then
		Net.Remotes.Effect:FireAllClients(
			"KnifeKill",
			position,
			Items.Color(round.WeaponKnife),
			Knives.Rank(parsed.Knife.Rarity)
		)
	end
end

-- killer = who gets credit; fatal = kill the character here (false when they already died)
local function eliminate(round: Round, victim: Player, killer: Player?, fatal: boolean?)
	if not round.Alive[victim] then
		return
	end
	Progress.Finish(victim, false)
	round.Alive[victim] = nil
	ReplicatedStorage:SetAttribute("Alive", aliveCount(round))
	if not isKiller(round, victim) then
		-- (no Heat lost any more: the round pulls everyone in, so dying in it shouldn't make your
		-- vault earn less)
		ChanceMeter.Add(victim, -1)
	end
	local root = rootOf(victim)
	if round.Gunner == victim and root then
		dropRevolver(round, root.Position)
	end
	Analytics.Track(
		victim,
		"round.death",
		roundProps(round, victim, {
			by = if killer then roleOf(round, killer) else (if fatal then "murderer_bot" else "left"),
			was = if isKiller(round, victim) then "murderer" else "innocent",
		})
	)
	if killer then
		Analytics.Track(killer, "round.kill", roundProps(round, killer, { victim = "player" }))
	end
	leaveRound(victim)
	if killer then
		if isKiller(round, killer) then
			round.Kills += 1
			round.HumanKills += 1
			Progress.Kill(killer)
			knifeKillEffect(round, if root then root.Position else Vector3.zero)
		end
		DataService.Update(killer, function(p)
			p.TotalKills += 1
		end)
	end
	if killer or fatal then
		if root then
			Net.Remotes.Effect:FireAllClients("Hit", root.Position)
		end
		leaveBody(round, victim)
		local humanoid = victim.Character and victim.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = 0
		end
	end
	victim:SetAttribute("Dread", nil)
	if root and not isKiller(round, victim) and innocentsLeft(round) == 0 and #round.Innocents + #round.Bots > 0 then
		finalMoment(round, root.Position, "Wipe")
	end
end

local killCard: (Round, Player) -> ()

-- Every way the Murderer can hurt someone ends here
local function strike(round: Round, victim: Player)
	if not round.Alive[victim] or isKiller(round, victim) then
		return -- (no friendly fire between Murderers)
	end
	if not round.Murderer then
		round.Kills += 1 -- a Murderer bot: no credit or loot, but it still kills
	end
	eliminate(round, victim, round.Murderer, true)
	killCard(round, victim) -- (after: it shows what the Murderer just took)
end

-- Bots --------------------------------------------------------------------------------------

local function killBot(round: Round, bot: Bot, killer: Player?)
	if not bot.Alive then
		return
	end
	local push = Vector3.zero
	local killerRoot = killer and rootOf(killer)
	if killerRoot then
		local away = bot.Root.Position - killerRoot.Position
		push = Vector3.new(away.X, 0, away.Z).Unit * 18 + Vector3.new(0, 8, 0)
	end
	Net.Remotes.Effect:FireAllClients("Hit", bot.Root.Position)
	if bot == round.GunnerBot then
		round.GunnerBot = nil
		if bot.Gun then
			bot.Gun:Destroy()
			bot.Gun = nil
		end
		spawnRevolver(round, bot.Root.Position)
	end
	RoundBots.Kill(bot, push, round.Bodies)
	if killer then
		Analytics.Track(
			killer,
			"round.kill",
			roundProps(round, killer, { victim = if bot == round.MurdererBot then "murderer_bot" else "bot" })
		)
	end
	if bot == round.MurdererBot then
		finalMoment(round, bot.Root.Position, "Hero")
	elseif innocentsLeft(round) == 0 then
		finalMoment(round, bot.Root.Position, "Wipe")
	end
	if bot == round.MurdererBot then
		if killer then
			round.Hero = killer
			for other in round.Alive do
				Net.Notify(other, `{round.Names[killer] or "Someone"} shot the Murderer!`, "good", true)
			end
		end
	else
		round.Kills += 1
		if killer and killer == round.Murderer then
			Progress.Kill(killer)
			knifeKillEffect(round, bot.Root.Position)
		end
	end
	ReplicatedStorage:SetAttribute("Alive", aliveCount(round))
end

local function botAt(round: Round, instance: Instance): Bot?
	for _, bot in round.Bots do
		if bot.Alive and (instance == bot.Model or instance:IsDescendantOf(bot.Model)) then
			return bot
		end
	end
	return nil
end

-- Server-side melee check: range, facing, cooldown, and the victim must still be alive in this round

local function onAttack(round: Round)
	local now = os.clock()
	local murderer = round.Murderer
	if not murderer or now - round.LastAttack < GameConfig.AttackCooldown then
		return
	end
	local murdererRoot = rootOf(murderer)
	if not murdererRoot or not round.Alive[murderer] then
		return
	end
	round.LastAttack = now

	-- Same stab / slash combo as in the hub; the murderer's own client already started it
	local character = murderer.Character :: Model
	local clipName = CombatService.NextSwing(murderer)
	Net.Animate(character, clipName, murderer)
	task.wait(AnimLibrary.Clips[clipName].Impact or 0.15)
	murdererRoot = rootOf(murderer) :: BasePart
	if not isLive(round) or not murdererRoot or not round.Alive[murderer] then
		return
	end
	local weapon = round.Weapon
	local handle = weapon and weapon:FindFirstChild("Handle")
	local sound = handle and handle:FindFirstChild("Slash") :: Sound?
	if sound then
		sound:Play()
	end
	Net.Remotes.Effect:FireAllClients("Swing", murdererRoot.Position)

	-- Who can this swing reach? Distance is measured flat (no missing someone on a step), the
	-- facing check is loose (the server's view of the Murderer's turn lags), and a wall in between
	-- always blocks it.
	local exclude: { Instance } = { round.Bodies, round.Coins, round.BotFolder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = exclude
	local function reach(root: BasePart, range: number): number?
		local offset = root.Position - murdererRoot.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local dist = flat.Magnitude
		if dist > range or math.abs(offset.Y) > 6 then
			return nil
		end
		local look = murdererRoot.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if dist > 3 and flatLook.Magnitude > 0.01 and flatLook.Unit:Dot(flat.Unit) < -0.3 then
			return nil
		end
		local from = murdererRoot.Position + Vector3.new(0, 1.5, 0)
		local wallHit = workspace:Raycast(from, root.Position + Vector3.new(0, 1.5, 0) - from, rayParams)
		if wallHit and wallHit.Instance.Name == "Wall" then
			return nil
		end
		return dist
	end

	local closest: Player?, closestBot: Bot?, closestDist = nil, nil, math.huge
	-- 1. The target the Murderer's own screen showed, if the server agrees it's believable: what
	--    you see is a little behind where people really are, so it gets extra reach for lag
	local hint = round.StabHint
	round.StabHint = nil
	if hint and os.clock() - hint.At < 0.75 then
		local target = hint.Target
		local victim = Players:GetPlayerFromCharacter(target)
		local bot = if victim then nil else botAt(round, target)
		local root = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		local range = GameConfig.AttackRange + GameConfig.StabLagSlack
		if root and victim and victim ~= murderer and round.Alive[victim] then
			local dist = reach(root, range)
			if dist then
				closest, closestDist = victim, dist
			end
		elseif bot and bot ~= round.MurdererBot then
			local dist = reach(bot.Root, range)
			if dist then
				closestBot, closestDist = bot, dist
			end
		end
	end
	-- 2. Otherwise whoever is closest in front of the Murderer on the server
	if not closest and not closestBot then
		local range = GameConfig.AttackRange + 1
		for player in round.Alive do
			local root = rootOf(player)
			local dist = if player ~= murderer and root then reach(root, range) else nil
			if dist and dist < closestDist then
				closest, closestDist = player, dist
			end
		end
		for _, bot in round.Bots do
			local dist = if bot.Alive then reach(bot.Root, range) else nil
			if dist and dist < closestDist then
				closest, closestBot, closestDist = nil, bot, dist
			end
		end
	end
	if closestBot then
		killBot(round, closestBot, murderer)
	elseif closest then
		strike(round, closest)
	end
end

-- Abilities ---------------------------------------------------------------------------------

local function distanceToSegment(point: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	local t = if lengthSq > 0 then math.clamp((point - a):Dot(ab) / lengthSq, 0, 1) else 0
	return (point - (a + ab * t)).Magnitude
end

-- The Murderer's perk (from their knife), or nil

-- The first time this Murderer's power shows itself (a throw, a perk, a kill, a bounced bullet),
-- everyone in the round (and anyone watching) gets the big "THE MURDERER HAS ..." banner. It names
-- the power, never the player (client/Transitions).

-- The dead see who got them: the Murderer's disguise name, their knife, its power and the biome
-- that knife comes from (client/Transitions "KillCard")
killCard = function(round: Round, victim: Player)
	-- A free gift a minute later: dying isn't the end of your fun
	SurpriseGifts.Soon(victim, 60)
	Net.Remotes.Effect:FireClient(victim, "KillCard", {
		New = DataService.IsNewPlayer(victim),
		Name = if round.Murderer
			then round.Names[round.Murderer] or "The Murderer"
			elseif round.MurdererBot then round.MurdererBot.Name
			else "The Murderer",
		Knife = round.WeaponKnife,
	})
end

local function throwKnife(round: Round, origin: Vector3, direction: Vector3, charge: number)
	local config = GameConfig.MurderThrow
	local speed = GameConfig.MurderThrow.Speed * (0.55 + 0.45 * charge)
	local model = KnifeModel.Build(round.WeaponKnife, true)
	KnifeModel.FitLength(model, 1.9)
	for _, part in model:GetDescendants() do
		if part:IsA("Trail") then
			part.Enabled = true
		end
	end
	model.Parent = workspace
	Net.Remotes.Effect:FireAllClients("KnifeThrow", origin)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { (round.Murderer :: Player).Character :: Model, model, round.Bodies }

	local hitAlready: { [any]: boolean } = {}
	local position, traveled, spin = origin, 0, 0
	local connection: RBXScriptConnection
	local function finish(stuck: boolean)
		connection:Disconnect()
		if not stuck then
			model:Destroy()
		end
	end
	connection = RunService.Heartbeat:Connect(function(dt)
		if not isLive(round) then
			finish(false)
			return
		end
		local stepLength = math.min(speed * dt, config.Range - traveled)
		local nextPosition = position + direction * stepLength
		-- Walls first: anyone standing behind the wall this step is safe
		local hit = workspace:Raycast(position, nextPosition - position, params)
		if hit then
			nextPosition = hit.Position
		end

		-- Generous hit test against innocents so it feels fair on laggy connections
		for player in round.Alive do
			local root = rootOf(player)
			if
				not isKiller(round, player)
				and not hitAlready[player]
				and root
				and distanceToSegment(root.Position, position, nextPosition) < 3
			then
				hitAlready[player] = true
				strike(round, player)
				finish(false)
				return
			end
		end
		for _, bot in round.Bots do
			if
				bot.Alive
				and bot ~= round.MurdererBot
				and not hitAlready[bot]
				and distanceToSegment(bot.Root.Position, position, nextPosition) < 3
			then
				hitAlready[bot] = true
				killBot(round, bot, round.Murderer)
				finish(false)
				return
			end
		end
		if hit then
			-- Stays stuck in the wall / door for the rest of the round (round.Bodies goes at the end)
			StuckKnives.Stick(model, hit.Position, direction, 0, round.Bodies)
			finish(true)
			return
		end

		position = nextPosition
		traveled += stepLength
		spin += dt * 25
		model:PivotTo(CFrame.lookAt(position, position + direction) * CFrame.Angles(spin, 0, 0))
		if traveled >= config.Range then
			finish(false)
		end
	end)
	table.insert(round.Connections, connection)
end

-- Throws one knife from the Murderer's hand on the Throw clip's release frame
local function throwFromHand(round: Round, murderer: Player, direction: Vector3, charge: number)
	local character = murderer.Character
	if not character then
		return
	end
	Net.Animate(character, "Throw", murderer)
	task.delay(AnimLibrary.Clips.Throw.Release or 0.07, function()
		local from = CombatService.HandPosition(murderer)
		if from and isLive(round) then
			throwKnife(round, from, direction, charge)
		end
	end)
end

-- at where you aimed, as fast as you can click, flying until it hits something

-- Every kill the Murderer makes (players or bots): Fury stacks, Invisiknife cloaks

-- Aim comes from the client, so make sure it's a sane unit vector before using it
local function sanitizeAim(player: Player, aim: unknown): Vector3?
	local root = rootOf(player)
	if not root then
		return nil
	end
	if typeof(aim) == "Vector3" then
		local v = aim :: Vector3
		if v == v and v.Magnitude > 0.01 and v.Magnitude < 1e4 then
			return v.Unit
		end
	end
	return root.CFrame.LookVector
end

-- Hold-click throw: every Murderer has one, on its own cooldown, whatever their knife's perk is
local function basicThrow(round: Round, murderer: Player, direction: Vector3)
	local now = os.clock()
	local character = murderer.Character
	local weapon = round.Weapon
	if now < round.ThrowReadyAt or not character or not weapon or weapon.Parent ~= character then
		CombatService.TakeCharge(murderer)
		return
	end
	round.ThrowReadyAt = now + math.max(GameConfig.MurdererThrowCooldown, GameConfig.ThrowMinInterval)
	local charge = CombatService.TakeCharge(murderer)
	throwFromHand(round, murderer, direction, charge)
end

local function onAbility(player: Player, aim: unknown, kind: unknown)
	local round = current
	if not round or not round.Alive[player] then
		return
	end
	local direction = sanitizeAim(player, aim)
	if not direction then
		return
	end
	local mine = killerRound(round, player)
	if mine and kind == "Throw" then
		basicThrow(mine, player, direction)
	end
end

-- Coins -------------------------------------------------------------------------------------

-- A random open spot on the round map's floor (not inside furniture or walls). Cast from just
-- under the ceiling so tall furniture still blocks it.
local function randomFloorPoint(): Vector3?
	local center = MapService.RoundCenter
	local half = MapService.RoundMapSize / 2 - Vector2.new(3, 3)
	for _ = 1, 20 do
		local x, z = rng:NextNumber(-half.X, half.X), rng:NextNumber(-half.Y, half.Y)
		-- a storey too (upstairs covers only part of the plan: misses just try again)
		local level = if MapService.RoundLevels > 1 and rng:NextNumber() < 0.4
			then rng:NextInteger(1, MapService.RoundLevels - 1)
			else 0
		local y = 12 + level * MapService.RoundStorey
		local hit = workspace:Raycast(Vector3.new(center.X + x, y, center.Z + z), Vector3.new(0, -20, 0))
		local parent = hit and hit.Instance.Parent
		if hit and hit.Instance.Name == "Floor" and parent and parent.Name == "RoundMap" then
			return hit.Position
		end
	end
	return nil
end

-- A floor point that isn't right on top of another coin, so they spread through every room
local function coinPoint(round: Round): Vector3?
	local best: Vector3?, bestGap = nil, -1
	for _ = 1, 6 do
		local point = randomFloorPoint()
		if not point then
			continue
		end
		local gap = math.huge
		for _, other in round.Coins:GetChildren() do
			if other.Name == "Coin" and other:IsA("Model") then
				gap = math.min(gap, (other:GetPivot().Position - point).Magnitude)
			end
		end
		if gap > 10 then
			return point
		elseif gap > bestGap then
			best, bestGap = point, gap
		end
	end
	return best
end

-- The Blender coin (Props "Coin": rim, notched edge, a skull on both faces) standing upright with
-- a soft gold glow and a few sparkles; an invisible ball around it is what you touch
local function buildCoin(at: CFrame): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "SpeedShoe"
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.one * 3.4
	hitbox.CFrame = at
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.Transparency = 1
	hitbox.Parent = model
	model.PrimaryPart = hitbox
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(52, 52)
	gui.MaxDistance = 100
	gui.LightInfluence = 0
	gui.Parent = hitbox
	local art = Instance.new("ImageLabel")
	art.Size = UDim2.fromScale(1, 1)
	art.BackgroundTransparency = 1
	art.Image = require(ReplicatedStorage.Shared.Config.CartoonArt).Speed
	art.Parent = gui
	return model, hitbox
end

local function spawnCoin(round: Round)
	local point = coinPoint(round)
	if not point then
		return
	end
	-- Face a random way so a room full of coins doesn't look stamped out
	local coin, hitbox =
		buildCoin(CFrame.new(point + Vector3.new(0, 2.1, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0))
	coin:AddTag("Coin")
	coin.Parent = round.Coins
	hitbox.Touched:Connect(function(other)
		local player = Players:GetPlayerFromCharacter(other.Parent)
		local root = player and rootOf(player)
		if
			not player
			or not root
			or (root.Position - hitbox.Position).Magnitude > 5
			or not round.Alive[player]
			or not coin.Parent
			or current ~= round
		then
			return
		end
		local position = hitbox.Position
		coin:Destroy()
		Analytics.Count(player, "coins")
		Progress.Coin(player)
		Net.Remotes.Effect:FireClient(player, "SpeedPickup", position)
		task.delay(GameConfig.CoinRespawn, function()
			if current == round then
				spawnCoin(round)
			end
		end)
	end)
end

-- Revolver ----------------------------------------------------------------------------------

-- The Sheriff: hand the Revolver to a player, or to a bot (which then hunts and shoots, see the brains)
giveRevolver = function(round: Round, player: Player)
	local alreadySheriff = round.Sheriff == player and player:GetAttribute("Role") == "Sheriff"
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = Revolver.BuildTool()
	tool.Parent = backpack
	round.GunTool = tool
	round.Gunner = player
	round.Sheriff = round.Sheriff or player
	player:SetAttribute("RevolverReadyAt", 0)
	ReplicatedStorage:SetAttribute("Revolver", "Taken")
	-- The role card said Innocent a moment ago: show the real role now
	if not alreadySheriff then
		player:SetAttribute("Role", "Sheriff")
		Net.Remotes.Role:FireClient(player, "Sheriff", round.Names[player])
	end
	-- (the role reveal says SHOOT THE MURDERER and the gun is in your hand: no extra toast)
end
giveRevolverToBot = function(round: Round, bot: Bot)
	local tool = Revolver.BuildTool()
	tool.Parent = bot.Model
	bot.Humanoid:EquipTool(tool)
	bot.Gun = tool
	round.GunnerBot = bot
	if not round.Sheriff then
		round.SheriffBot = round.SheriffBot or bot
	end
	ReplicatedStorage:SetAttribute("Revolver", "Taken")
end

spawnRevolver = function(round: Round, position: Vector3?)
	if current ~= round or round.Revolver then
		return
	end
	local point = position or randomFloorPoint()
	if not point then
		return
	end
	local pickup = Revolver.BuildPickup(point + Vector3.new(0, if position then 0 else 2.5, 0))
	pickup:AddTag("RoundGunPickup")
	pickup.Parent = round.Coins
	round.Revolver = pickup
	ReplicatedStorage:SetAttribute("Revolver", "Dropped")
	Net.Remotes.Effect:FireAllClients("RevolverDrop", point)
	local zone = pickup:FindFirstChild("PickupZone") :: BasePart
	zone.Touched:Connect(function(other)
		local player = Players:GetPlayerFromCharacter(other.Parent)
		if not player or current ~= round or round.Revolver ~= pickup then
			return
		end
		if not round.Alive[player] or isKiller(round, player) or round.Gunner then
			return
		end
		pickup:Destroy()
		round.Revolver = nil
		local backpack = player:FindFirstChildOfClass("Backpack")
		local tool = Revolver.BuildTool()
		tool.Parent = backpack
		round.GunTool = tool
		round.Gunner = player
		player:SetAttribute("RevolverReadyAt", 0)
		ReplicatedStorage:SetAttribute("Revolver", "Taken")
		Analytics.Track(player, "round.revolver_pickup", roundProps(round, player))
		Net.Notify(player, "You got the gun! Shoot the Murderer!", "good", true)
	end)
end

local function onShoot(player: Player, aim: unknown)
	local round = current
	if not round or round.Gunner ~= player or not round.Alive[player] or typeof(aim) ~= "Vector3" then
		return
	end
	local character = player.Character
	local tool = round.GunTool
	if not character or not tool or tool.Parent ~= character then
		return -- has to be holding it
	end
	local now = os.clock()
	if now - round.LastShot < GameConfig.RevolverCooldown then
		return
	end
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local offset = (aim :: Vector3) - head.Position
	if offset ~= offset or offset.Magnitude < 0.5 then
		return
	end
	round.LastShot = now
	for _, holder in { round.Gunner } do
		if holder then
			holder:SetAttribute("RevolverReadyAt", workspace:GetServerTimeNow() + GameConfig.RevolverCooldown)
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, round.Bodies, round.Coins }
	local direction = offset.Unit * GameConfig.RevolverRange
	local hit = workspace:Raycast(head.Position, direction, params)
	local handle = tool:FindFirstChild("Handle")
	local muzzle = tool:FindFirstChild("Muzzle") :: BasePart?
	local sound = handle and handle:FindFirstChild("Shot") :: Sound?
	if sound then
		sound:Play()
	end
	Net.Animate(character, "Recoil")
	Net.Remotes.Effect:FireAllClients(
		"Shot",
		if muzzle then muzzle.Position else head.Position,
		if hit then hit.Position else head.Position + direction
	)
	if not hit then
		return
	end

	local hitBot = botAt(round, hit.Instance)
	if hitBot then
		if hitBot ~= round.MurdererBot then
			-- why you're out, on the top line where you'll see it (a toast got lost in the death)
			Net.Remotes.Effect:FireClient(
				player,
				"Why",
				"💥 You shot someone who WASN'T the Murderer, so you're out too!"
			)
			eliminate(round, player, nil, true)
		end
		killBot(round, hitBot, if hitBot == round.MurdererBot then player else nil)
		return
	end

	local victim: Player? = nil
	for other in round.Alive do
		if other ~= player and other.Character and hit.Instance:IsDescendantOf(other.Character) then
			victim = other
			break
		end
	end
	if not victim then
		return
	end
	local shotKiller = killerRound(round, victim)
	if shotKiller then
		if not round.Hero then
			Analytics.Track(player, "round.hero", roundProps(round, player))
			Analytics.Milestone(player, "hero_shot")
		end
		round.Hero = round.Hero or player
		local victimRoot = rootOf(victim)
		if victimRoot then
			finalMoment(round, victimRoot.Position, "Hero")
		end
		for other in round.Alive do
			Net.Notify(other, `{round.Names[player] or "Someone"} shot the Murderer!`, "good", true)
		end
		eliminate(round, victim, player, true)
	else
		-- Shot an innocent: both go down, and the Revolver drops where the shooter stood
		Net.Remotes.Effect:FireClient(
			player,
			"Why",
			"💥 You shot someone who WASN'T the Murderer, so you're out too!"
		)
		Net.Remotes.Effect:FireClient(victim, "Why", "💥 The Sheriff shot you by mistake! (They're out too.)")
		eliminate(round, victim, nil, true)
		eliminate(round, player, nil, true)
	end
end

-- Bot brains --------------------------------------------------------------------------------

-- Where the Murderer is, if an innocent bot could notice it (only once the knife is out)
local function murdererThreat(round: Round): BasePart?
	local murdererBot = round.MurdererBot
	if murdererBot then
		return if murdererBot.Alive and murdererBot.Knife then murdererBot.Root else nil
	end
	local killer = round.Murderer
	if killer then
		local view = killerRound(round, killer)
		local weapon = view and view.Weapon
		-- Only once the knife is out (pulling it is the reveal)
		if view and weapon and round.Alive[killer] and weapon.Parent == killer.Character then
			return rootOf(killer)
		end
	end
	return nil
end

-- Stroll to a random spot, hang around a moment, pick another
local function wander(bot: Bot, now: number)
	bot.Humanoid.WalkSpeed = 10
	if bot.Goal then
		if RoundBots.Reached(bot, 4) then
			bot.Goal = nil
			bot.IdleUntil = now + rng:NextNumber(0.5, 3)
		end
	elseif now >= bot.IdleUntil then
		RoundBots.WalkTo(bot, randomFloorPoint())
	end
end

-- Can this point see that one? (only the round map's walls, doors and furniture block)
local function canSee(from: Vector3, to: Vector3): boolean
	local map = MapService.RoundMapFolder()
	if not map then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { map }
	return workspace:Raycast(from, to - from, params) == nil
end

-- A bot Sheriff's shot: good aim up close, worse far away
local function botShoot(round: Round, bot: Bot, target: BasePart)
	if RunService:IsStudio() and ReplicatedStorage:GetAttribute("DebugCalmBots") then
		return
	end
	local from = bot.Root.Position + Vector3.new(0, 1.5, 0)
	local dist = (target.Position - from).Magnitude
	-- Nervous shots: decent point-blank, mostly misses from across a room. In a newcomer's first
	-- Murderer round every shot misses (the bang still makes it tense): 62% of first-visit Murderers
	-- used to lose, and winning that round is one of the best predictors of coming back.
	local hits = not round.Newcomer and rng:NextNumber() < math.clamp(0.55 - dist / 80, 0.12, 0.55)
	local aimAt = if hits
		then target.Position
		else target.Position + Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(0, 3), rng:NextNumber(-4, 4))
	local handle = bot.Gun and bot.Gun:FindFirstChild("Handle")
	local sound = handle and handle:FindFirstChild("Shot") :: Sound?
	if sound then
		sound:Play()
	end
	Net.Animate(bot.Model, "Recoil")
	Net.Remotes.Effect:FireAllClients("Shot", from, aimAt)
	if not hits then
		return
	end
	local murdererBot = round.MurdererBot
	if murdererBot and target == murdererBot.Root then
		round.HeroBot = bot
		for other in round.Alive do
			Net.Notify(other, `{bot.Name} shot the Murderer!`, "good", true)
		end
		killBot(round, murdererBot, nil)
		return
	end
	local murderer = round.Murderer
	if not murderer then
		return
	end
	round.ShotByBot = true
	round.HeroBot = bot
	finalMoment(round, target.Position, "Hero")
	for other in round.Alive do
		Net.Notify(other, `{bot.Name} shot the Murderer!`, "good", true)
	end
	eliminate(round, murderer, nil, true)
end

local function innocentBrain(round: Round, bot: Bot, now: number)
	local threat = murdererThreat(round)
	local eye = bot.Root.Position + Vector3.new(0, 1.5, 0)
	-- The Sheriff: once it knows who the Murderer is, it closes in, stops, aims and shoots
	if bot.Gun then
		if threat then
			local dist = (threat.Position - bot.Root.Position).Magnitude
			if dist < 45 and canSee(eye, threat.Position) then
				RoundBots.WalkTo(bot, nil)
				RoundBots.Face(bot, threat.Position)
				if bot.AimUntil == 0 then
					bot.AimUntil = now + 1.1 + dist / 40 -- a slow, shaky aim: time to dodge or close in
				end
				if now >= bot.AimUntil and now >= bot.NextShot then
					bot.NextShot = now + GameConfig.RevolverCooldown + 2
					bot.AimUntil = 0
					botShoot(round, bot, threat)
				end
				return
			end
			-- Lost sight: go to where it was
			bot.AimUntil = 0
			bot.Humanoid.WalkSpeed = GameConfig.RoundWalkSpeed - 1
			RoundBots.WalkTo(bot, threat.Position)
			return
		end
		bot.AimUntil = 0
		wander(bot, now)
		return
	end
	-- A Revolver lying around and the coast is clear: go get it
	local pickup = round.Revolver
	if pickup and pickup.Parent and not round.Gunner and not round.GunnerBot then
		local spot = pickup:GetPivot().Position
		if not threat or (threat.Position - bot.Root.Position).Magnitude > 22 then
			bot.Humanoid.WalkSpeed = GameConfig.RoundWalkSpeed - 1
			RoundBots.WalkTo(bot, spot)
			if (spot - bot.Root.Position).Magnitude < 4 then
				pickup:Destroy()
				round.Revolver = nil
				giveRevolverToBot(round, bot)
			end
			return
		end
	end
	if not threat or (threat.Position - bot.Root.Position).Magnitude > 32 then
		wander(bot, now)
		return
	end
	-- Run! Head for a spot far from the Murderer that isn't back past it (slower in a newcomer's
	-- first Murderer round, so the timer doesn't run out on them with one bot left)
	bot.Humanoid.WalkSpeed = GameConfig.RoundWalkSpeed - (if round.Newcomer then 4 else 1)
	if bot.Goal and not RoundBots.Reached(bot, 4) and now < bot.NextThink then
		return
	end
	bot.NextThink = now + 1.2
	local away = bot.Root.Position - threat.Position
	local best, bestScore = nil, -math.huge
	for _ = 1, 8 do
		local point = randomFloorPoint()
		if point then
			local score = (point - threat.Position).Magnitude - 0.5 * (point - bot.Root.Position).Magnitude
			if (point - bot.Root.Position):Dot(away) < 0 then
				score -= 40
			end
			if score > bestScore then
				best, bestScore = point, score
			end
		end
	end
	RoundBots.WalkTo(bot, best)
end

local function murdererBrain(round: Round, bot: Bot, now: number)
	-- Studio: ReplicatedStorage DebugCalmBots = true keeps a test round running the full timer
	-- (the Murderer bot just wanders) - for testing spectate, powers, the HUD
	if not bot.Knife or (RunService:IsStudio() and ReplicatedStorage:GetAttribute("DebugCalmBots")) then
		wander(bot, now) -- the grace period: blend in
		return
	end
	-- Hunt the closest person
	local target: BasePart?, targetPlayer: Player?, targetBot: Bot? = nil, nil, nil
	local bestDist = math.huge
	for player in round.Alive do
		local root = rootOf(player)
		local dist = if root then (root.Position - bot.Root.Position).Magnitude else math.huge
		if root and dist < bestDist then
			target, targetPlayer, targetBot, bestDist = root, player, nil, dist
		end
	end
	for _, other in round.Bots do
		if other.Alive and other ~= bot then
			local dist = (other.Root.Position - bot.Root.Position).Magnitude
			if dist < bestDist then
				target, targetPlayer, targetBot, bestDist = other.Root, nil, other, dist
			end
		end
	end
	local sheriff: BasePart? = if round.Gunner
		then rootOf(round.Gunner)
		elseif round.GunnerBot then round.GunnerBot.Root
		else nil
	if sheriff and (sheriff.Position - bot.Root.Position).Magnitude < 40 then
		target, bestDist = sheriff, (sheriff.Position - bot.Root.Position).Magnitude
		targetPlayer = round.Gunner
		targetBot = round.GunnerBot
	end
	if not target then
		wander(bot, now)
		return
	end
	bot.Humanoid.WalkSpeed = GameConfig.MurdererWalkSpeed - 0.5
	RoundBots.WalkTo(bot, target.Position)

	if bestDist < GameConfig.AttackRange - 2 and now >= bot.NextStab then
		bot.NextStab = now + 1.2
		RoundBots.Face(bot, target.Position)
		Net.Animate(bot.Model, "Stab")
		Net.Remotes.Effect:FireAllClients("Swing", bot.Root.Position)
		local victimRoot = target
		task.delay(AnimLibrary.Clips.Stab.Impact or 0.15, function()
			-- Still in reach when the blade lands? (you can dodge it)
			if current ~= round or not bot.Alive then
				return
			end
			if (victimRoot.Position - bot.Root.Position).Magnitude > GameConfig.AttackRange + 1 then
				return
			end
			if targetPlayer then
				strike(round, targetPlayer)
			elseif targetBot then
				killBot(round, targetBot, nil)
			end
		end)
	end
end

local function stepBots(round: Round)
	local now = os.clock()
	for _, bot in round.Bots do
		if not bot.Alive then
			continue
		end
		if bot == round.MurdererBot then
			murdererBrain(round, bot, now)
		else
			innocentBrain(round, bot, now)
		end
		RoundBots.Step(bot)
		if bot.Root.Position.Y < -30 then
			killBot(round, bot, nil) -- fell out of the map
		end
	end
end

-- Round flow --------------------------------------------------------------------------------

giveWeapon = function(round: Round)
	local murderer = round.Murderer
	if not murderer then
		if round.MurdererBot then
			RoundBots.GiveKnife(round.MurdererBot, round.WeaponKnife)
		end
		return
	end
	local backpack = murderer:FindFirstChildOfClass("Backpack")
	if not backpack or not round.Alive[murderer] then
		return
	end
	local tool = KnifeModel.BuildTool(round.WeaponKnife)
	tool:SetAttribute("MurderKnife", true)
	local slash = Instance.new("Sound")
	slash.Name = "Slash"
	slash.SoundId = Sounds.Throw -- (the same swish as a thrown knife)
	slash.Volume = 0.9
	slash.Parent = tool:FindFirstChild("Handle")
	tool.Parent = backpack
	round.Weapon = tool
	-- Knife in hand = revealed: only then the Murderer's speed (no speed tell while hiding) and
	-- only then can Radar find them
	local function knifeOut(out: boolean)
		if out and not round.KnifeShownAt then
			round.KnifeShownAt = os.clock()
			Analytics.Track(murderer, "round.knife_out", roundProps(round, murderer))
		end
		murderer:SetAttribute("KnifeOut", if out then true else nil)
		BaseService.RefreshWalkSpeed(murderer)
	end
	table.insert(
		round.Connections,
		tool.Equipped:Connect(function()
			knifeOut(true)
		end)
	)
	table.insert(
		round.Connections,
		tool.Unequipped:Connect(function()
			knifeOut(false)
		end)
	)
	-- Tool.Activated replicates to the server; the client never reports hits itself
	table.insert(
		round.Connections,
		tool.Activated:Connect(function()
			onAttack(round)
		end)
	)
	-- (how to stab / throw: the guide line, which knows your device)
	-- The knife arrives quietly in their hotbar: nobody can tell who got it until they choose to
	-- pull it out (the draw flourish plays then, for everyone - that's the reveal)
	local root = rootOf(murderer)
	if root then
		Net.Remotes.Effect:FireClient(murderer, "Unsheath", nil)
	end
	table.insert(
		round.Connections,
		tool.Equipped:Connect(function()
			local character = murderer.Character
			if character and current == round then
				Net.Animate(character, "Draw")
			end
		end)
	)
end

local function startRound(participants: { Player })
	CoffinService.RoundStarted()
	local built = MapService.BuildRoundMap() -- (a random map: the vote was cut)
	ReplicatedStorage:SetAttribute("MapName", built.Name)
	RoundBots.SetMap(built.Folder)
	-- A Studio bot round: the person who asked picks their side; bots fill in the rest
	local plan = botPlan
	botPlan = nil
	if plan and not table.find(participants, plan.Player) then
		plan = nil
	end
	-- Bots: a Studio bot round asks for exactly three; otherwise they top the round up to
	-- GameConfig.BotFill.Size. With two or more real players the Murderer is always one of them;
	-- alone with bots, a bot gets the knife as often as a fair draw would give it to one.
	local botCount = if plan then 3 else math.max(0, GameConfig.BotFill.Size - #participants)
	-- A brand-new player's FIRST round: they're the Murderer (the thumbnail says "BECOME MURDERER";
	-- on a fair draw a newcomer has the lowest luck meter in the server and rarely got the knife)
	local firstTimers = {}
	for _, player in participants do
		local profile = DataService.Get(player)
		if profile and profile.RoundsPlayed == 0 and profile.PlayTime < GameConfig.FirstRoundMurdererUnder then
			table.insert(firstTimers, player)
		end
	end
	local murderer: Player?
	local newcomer = false
	if plan then
		murderer = if plan.Role == "Murderer" then plan.Player else nil
	elseif #firstTimers > 0 then
		murderer = firstTimers[rng:NextInteger(1, #firstTimers)]
		newcomer = true
		Analytics.Track(murderer, "round.first_murderer")
	elseif #participants == 1 and botCount > 0 then
		local profile = DataService.Get(participants[1])
		local weight = (1 + (if profile then profile.Luck else 0))
			+ (if profile and profile.Tickets > 0 then GameConfig.TicketWeight else 0)
		murderer = if rng:NextNumber() * (weight + botCount) < weight then pickMurderer(participants) else nil
	else
		murderer = pickMurderer(participants)
	end
	local botFolder = Instance.new("Folder")
	botFolder.Name = "RoundBots"
	botFolder.Parent = workspace
	local coins = Instance.new("Folder")
	coins.Name = "RoundCoins"
	coins.Parent = workspace
	local bodies = Instance.new("Folder")
	bodies.Name = "RoundBodies"
	bodies.Parent = workspace
	local round: Round = {
		Murderer = murderer,
		MurdererBot = nil,
		Bots = {},
		BotFolder = botFolder,
		Innocents = {},
		Alive = {},
		Kills = 0,
		Weapon = nil,
		WeaponKnife = if murderer then murdererKnife(murderer) else Knives.List[rng:NextInteger(1, #Knives.List)].Name,
		LastAttack = 0,
		Coins = coins,
		Bodies = bodies,
		Names = {},
		Revolver = nil,
		Gunner = nil,
		GunTool = nil,
		LastShot = 0,
		ThrowReadyAt = 0,
		Hero = nil,
		GunnerBot = nil,
		ShotByBot = false,
		Newcomer = newcomer,
		HeroBot = nil,
		HumanKills = 0,
		Connections = {},
		Id = `{string.sub(game.JobId, 1, 6)}-{string.format("%x", os.time())}`,
		RevealEndsAt = 0,
		StartedAt = os.clock(),
		Map = built.Name,
	}
	current = round
	ReplicatedStorage:SetAttribute("Revolver", nil)

	-- Everyone becomes a named character (yields while outfits apply)
	round.Names = Disguises.Assign(participants)

	-- Shuffle spawns so the Murderer's spot gives nothing away
	local spawns = table.clone(MapService.RoundSpawns)
	for i = #spawns, 2, -1 do
		local j = rng:NextInteger(1, i)
		spawns[i], spawns[j] = spawns[j], spawns[i]
	end

	-- Screens fade to black with the map's name while everyone is moved (client/Transitions)
	for _, player in participants do
		-- Let go of anything the client holds you in (the wheel lock) before the server moves you
		player:SetAttribute("RoundTeleport", true)
		Net.Remotes.Effect:FireClient(
			player,
			"Fade",
			`🔪 {ReplicatedStorage:GetAttribute("MapName") or "The Murder"}`
		)
	end
	task.wait(0.35)

	-- The round map is far from the hub: load it on everyone's client first, or StreamingEnabled
	-- freezes them with "Gameplay paused" while it streams in (all at once, at most 4 seconds)
	local pending = 0
	for i, player in participants do
		pending += 1
		task.spawn(function()
			pcall(player.RequestStreamAroundAsync, player, spawns[(i - 1) % #spawns + 1].Position, 4)
			pending -= 1
		end)
	end
	local streamStart = os.clock()
	while pending > 0 and os.clock() - streamStart < 4 do
		task.wait()
	end

	for i, player in participants do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid then
			player:SetAttribute("RoundTeleport", nil)
			continue
		end
		-- The night: a boss's knife you're carrying goes back to its wall (the 10 s warning said so)
		StealService.EndForRound(player)
		local isMurderer = player == round.Murderer
		if not isMurderer then
			table.insert(round.Innocents, player)
		end
		round.Alive[player] = true
		player:SetAttribute("InRound", true)
		player:SetAttribute("Role", if isMurderer then "Murderer" else "Innocent")
		DataService.Update(player, function(p)
			p.Luck = if isMurderer then 0 else p.Luck + GameConfig.MurdererMeter.PerRound
		end)

		-- (no saved spot any more: after the round everyone comes home to their pen, like Steal An
		-- Egg after the night - BaseService.TeleportHome)
		local target = spawns[(i - 1) % #spawns + 1]
		-- Off any seat first (a seat weld would hold you in the hub), and out of a boss tumble
		humanoid.Sit = false
		humanoid.PlatformStand = false
		player:SetAttribute("Tumbling", nil)
		player:SetAttribute("TumblePush", nil)
		local seat = humanoid.SeatPart
		local seatWeld = seat and seat:FindFirstChild("SeatWeld")
		if seatWeld then
			seatWeld:Destroy()
		end
		character:PivotTo(target)
		spawnOf[player] = target
		holdWhileStreaming(player, character, target)
		-- Safety net: if anything else held them back (client physics owns your character, so a
		-- client script snapping you somewhere wins a race), move them again until they're really in
		task.spawn(function()
			for _ = 1, 5 do
				task.wait(0.5)
				local now = player.Character
				if now ~= character or not player:GetAttribute("InRound") or not round.Alive[player] then
					break
				end
				if (character:GetPivot().Position - target.Position).Magnitude < 400 then
					break
				end
				humanoid.Sit = false
				character:PivotTo(target)
			end
			player:SetAttribute("RoundTeleport", nil)
		end)
		BaseService.RefreshWalkSpeed(player)

		table.insert(
			round.Connections,
			humanoid.Died:Connect(function()
				if isKiller(round, player) then
					round.Alive[player] = nil -- fell off or reset: that Murderer is out
				else
					eliminate(round, player, nil)
				end
			end)
		)
	end

	if botCount > 0 then
		local taken: { [string]: boolean } = {}
		for _, name in round.Names do
			taken[name] = true
		end
		local roles: { string } = {}
		for i = 1, botCount do
			table.insert(roles, if i == 1 and not murderer then "Murderer" else "Innocent")
		end
		-- Bots wear a believable money tag (and now and then VIP) like everyone else's, or the
		-- tagless ones gave away who the real players - the only possible Murderers and Sheriffs.
		-- Each is somewhere around what the real players here have (log-scale spread).
		local low, high = math.huge, 0
		for _, player in participants do
			local cash = player:GetAttribute("Cash")
			if type(cash) == "number" and cash > 0 then
				low, high = math.min(low, cash), math.max(high, cash)
			end
		end
		if high <= 0 then
			low, high = 1e3, 1e6
		end
		local logLow, logHigh = math.log10(math.max(low / 4, 100)), math.log10(math.max(high * 3, 1000))
		for i, role in roles do
			local at = spawns[(#participants + i - 1) % #spawns + 1]
			local bot = RoundBots.Spawn(at, role, taken, botFolder)
			bot.Model:SetAttribute("FakeCash", math.floor(10 ^ rng:NextNumber(logLow, logHigh)))
			bot.Model:SetAttribute("FakeVIP", rng:NextNumber() < 0.15)
			table.insert(round.Bots, bot)
			if role == "Murderer" then
				round.MurdererBot = bot
			end
		end
	end
	ReplicatedStorage:SetAttribute("Alive", aliveCount(round))

	for _ = 1, GameConfig.RoundCoins do
		spawnCoin(round)
	end

	-- A Sheriff from the start (MM2 style): any innocent, player or bot, gets the Revolver now
	local sheriffs: { any } = {}
	for _, player in round.Innocents do
		if round.Alive[player] then
			table.insert(sheriffs, player)
		end
	end
	for _, bot in round.Bots do
		if bot.Alive and bot ~= round.MurdererBot then
			table.insert(sheriffs, bot)
		end
	end
	if #sheriffs > 0 then
		local chosen = sheriffs[rng:NextInteger(1, #sheriffs)]
		-- A newcomer's 2nd and 3rd rounds: they're the Sheriff (after being the Murderer in their 1st).
		-- Players whose first visit had a hero moment came back 2-3x as often (Sheriff: 33% vs 11%).
		local heroes = {}
		for _, candidate in sheriffs do
			if typeof(candidate) == "Instance" then
				local profile = DataService.Get(candidate :: Player)
				if
					profile
					and profile.RoundsPlayed >= 1
					and profile.RoundsPlayed <= GameConfig.NewcomerSheriffRounds
					and profile.PlayTime < GameConfig.FirstRoundMurdererUnder * 2
				then
					table.insert(heroes, candidate)
				end
			end
		end
		if #heroes > 0 then
			chosen = heroes[rng:NextInteger(1, #heroes)]
			Analytics.Track(chosen :: Player, "round.first_sheriff")
		end
		if typeof(chosen) == "Instance" then
			round.Sheriff = chosen :: Player
			(chosen :: Player):SetAttribute("Role", "Sheriff")
		else
			round.SheriffBot = chosen
		end
		table.remove(sheriffs, table.find(sheriffs, chosen) :: number)
	end

	round.RevealEndsAt = workspace:GetServerTimeNow() + GameConfig.RoleRevealSeconds
	local weaponAt = round.RevealEndsAt + GameConfig.MurdererGrace
	for player in round.Names do
		local role = if player == murderer
			then "Murderer"
			else if player == round.Sheriff then "Sheriff" else "Innocent"
		Net.Remotes.Role:FireClient(player, role, round.Names[player], round.RevealEndsAt)
		player:SetAttribute("WeaponAt", weaponAt)
	end
	task.delay(math.max(0, weaponAt - workspace:GetServerTimeNow()), function()
		if current ~= round then
			return
		end
		Progress.Tick(round.Alive)
		giveWeapon(round)
		if round.Sheriff and round.Alive[round.Sheriff] then
			giveRevolver(round, round.Sheriff)
		elseif round.SheriffBot and round.SheriffBot.Alive then
			giveRevolverToBot(round, round.SheriffBot)
		end
	end)
	-- Nobody took the Revolver (or it dropped): it turns up somewhere later
	task.delay(GameConfig.RevolverTime, function()
		if current == round and not round.Gunner and not round.GunnerBot and not round.Revolver then
			spawnRevolver(round, nil)
			for player in round.Alive do
				Net.Notify(player, "A gun dropped somewhere. Find it!", "info", true)
			end
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
	if round.GunTool then
		round.GunTool:Destroy()
	end
	-- Bots have no Roblox photo: keep their disguise's face for the VS card before they're gone
	local function botFace(bot: Bot?): { Face: string, Skin: Color3 }?
		local head = bot and bot.Model:FindFirstChild("Head") :: BasePart?
		local decal = head and head:FindFirstChildOfClass("Decal")
		return if head then { Face = if decal then decal.Texture else "", Skin = head.Color } else nil
	end
	local murdererBotFace = botFace(round.MurdererBot)
	local heroBotFace = botFace(round.HeroBot)
	round.Coins:Destroy()
	round.Bodies:Destroy()
	round.BotFolder:Destroy()
	ReplicatedStorage:SetAttribute("Revolver", nil)

	local survivors = {}
	for _, player in round.Innocents do
		if round.Alive[player] and player.Parent then
			table.insert(survivors, player)
		end
	end
	local murderer = round.Murderer
	local botsSurvived = false
	for _, bot in round.Bots do
		if bot.Alive and bot ~= round.MurdererBot then
			botsSurvived = true
		end
	end
	local innocentsWon = #survivors > 0 or botsSurvived or round.Hero ~= nil
	for player in round.Names do
		if player.Parent then
			local role = roleOf(round, player)
			local won = if role == "murderer" then not innocentsWon else innocentsWon
			Analytics.Track(
				player,
				"round.end",
				roundProps(round, player, {
					survived = round.Alive[player] == true,
					won = won,
					murderer_won = not innocentsWon,
					kills = if role == "murderer" then round.Kills else nil,
					hero = round.Hero == player,
					knife_out_s = if round.KnifeShownAt then math.floor(round.KnifeShownAt - round.StartedAt) else nil,
				})
			)
			if round.Alive[player] and role ~= "murderer" then
				Analytics.Milestone(player, "round_survived")
			end
			if won and role == "murderer" then
				Analytics.Milestone(player, "murderer_win")
			end
		end
	end

	local hero = round.Hero
	-- Coffins: the murder rounds are their clock - one round off everyone's, two for the winners
	-- One meaning of "you won", used by everything: the round card's YOU WON, the coffin clock,
	-- Winner's Luck, the win count and the jackpot step. (A Murderer wins with at least one kill:
	-- a round the innocents only "lost" by leaving isn't a win.)
	local coffinWinners: { [Player]: boolean } = {}
	for player in round.Names do
		local role = roleOf(round, player)
		coffinWinners[player] = if role == "murderer" then not innocentsWon and round.Kills > 0 else innocentsWon
	end
	CoffinService.RoundEnded(coffinWinners)
	for player in round.Names do
		local alive = round.Alive[player] == true
		local won = coffinWinners[player] == true
		Progress.Finish(player, (alive and player ~= murderer) or round.Hero == player or (player == murderer and won))
		if won and player.Parent then
			CoffinService.Winner(player)
			DataService.Update(player, function(p)
				p.RoundsWon += 1
			end)
		end
	end

	-- Everyone still in the round goes home as themselves, behind a fade (client/Transitions)
	local fading = false
	for player in round.Alive do
		if player.Parent then
			Net.Remotes.Effect:FireClient(player, "Fade", "🏠 Back to the hub")
			fading = true
		end
	end
	if fading then
		task.wait(0.35)
	end
	for player in round.Alive do
		if player.Parent then
			leaveRound(player)
			Disguises.Remove(player)
			BaseService.TeleportHome(player)
		end
	end
	if murderer then
		leaveRound(murderer)
	end
	for player in round.Names do
		Disguises.Forget(player)
	end
	-- The night is over: every monster has fresh coffins, and everyone's home to race out for them
	if GuardService.RestockAll() > 0 then
		task.delay(1.2, function()
			Net.Announce("🔪 NEW COFFINS! Every monster has fresh ones!", Color3.fromRGB(255, 220, 90), 2)
		end)
	end

	local murdererName = if murderer
		then `{round.Names[murderer] or "?"} ({murderer.DisplayName})`
		else `{if round.MurdererBot then round.MurdererBot.Name else "?"} (a bot)`
	local status = if #round.Innocents == 0 and #round.Bots == 0
		then "Solo test round over" -- Studio debug rounds have nobody to survive
		elseif hero then `{round.Names[hero] or hero.DisplayName} shot the Murderer, {murdererName}!`
		elseif innocentsWon then `Innocents win! The Murderer was {murdererName}`
		else `The Murderer wins! It was {murdererName}`
	setPhase("Results", GameConfig.ResultsTime, status)
	-- The VS card: who was the Murderer, with which knife, and who stopped them (client/Transitions)
	local heroName: string? = if hero
		then `{round.Names[hero] or "?"} ({hero.DisplayName})`
		elseif round.HeroBot then `{round.HeroBot.Name} (bot Sheriff)`
		else nil
	local sheriff: Player? = hero or round.Sheriff
	local sheriffBot = if sheriff then nil else round.HeroBot or round.SheriffBot
	local sheriffName: string? = if sheriff
		then `{round.Names[sheriff] or "?"} ({sheriff.DisplayName})`
		elseif sheriffBot then `{sheriffBot.Name} (bot)`
		else nil
	local sheriffId = if sheriff then sheriff.UserId else 0
	local sheriffStatus = if hero or round.HeroBot
		then "shot the Murderer!"
		elseif sheriff and round.Alive[sheriff] then "survived"
		elseif sheriff or sheriffBot then "was taken out"
		else ""
	local card = {
		Title = if hero or round.HeroBot
			then "The Sheriff saved the day!"
			elseif innocentsWon then "The innocents survived!"
			else "The Murderer wins!",
		Won = if innocentsWon then "Innocents" else "Murderer",
		MurdererName = if murderer
			then `{round.Names[murderer] or "?"} ({murderer.DisplayName})`
			elseif round.MurdererBot then `{round.MurdererBot.Name} (bot)`
			else "?",
		MurdererId = if murderer then murderer.UserId else 0,
		Knife = round.WeaponKnife,
		HeroName = heroName,
		HeroId = if hero then hero.UserId else 0,
		MurdererFace = murdererBotFace,
		HeroFace = heroBotFace,
		Kills = round.Kills,
		-- The Murderer's knife power on show
		SheriffName = sheriffName,
		SheriffId = sheriffId,
		SheriffStatus = sheriffStatus,
	}
	for player in round.Names do
		if player.Parent then
			-- (and your own result on it: did your side win, and the Speed you banked this round)
			local mine = table.clone(card)
			mine.YouWon = coffinWinners[player] == true
			mine.YourSpeed = (player:GetAttribute("RoundSpeedBanked") or 0) :: number
			Net.Remotes.Effect:FireClient(player, "RoundCard", mine)
		end
	end
end

local function roundOver(round: Round): boolean
	local murderer = round.Murderer
	if murderer and (not round.Alive[murderer] or not murderer.Parent) then
		return true
	end
	if round.MurdererBot and not round.MurdererBot.Alive then
		return true
	end
	if #round.Innocents == 0 and #round.Bots == 0 then
		return false -- solo Studio test: just run the clock
	end
	for player in round.Alive do
		if not isKiller(round, player) and player.Parent then
			return false
		end
	end
	for _, bot in round.Bots do
		if bot.Alive and bot ~= round.MurdererBot then
			return false
		end
	end
	return true
end

local function loop()
	while true do
		-- Intermission: steal knives, earn cash, buy upgrades and round items
		setPhase("Intermission", GameConfig.IntermissionTime, INTERMISSION_STATUS)
		local prizeKind, jackpot, seed = RoundPrize.Roll(rng)
		ReplicatedStorage:SetAttribute("PrizeKind", prizeKind)
		ReplicatedStorage:SetAttribute("PrizeJackpot", jackpot)
		ReplicatedStorage:SetAttribute("PrizeSeed", seed)
		local startedAt = os.clock()
		local endsAt = startedAt + GameConfig.IntermissionTime
		local warned = false
		while os.clock() < endsAt do
			task.wait(1)
			if RunService:IsStudio() and ReplicatedStorage:GetAttribute("DebugSkip") then
				ReplicatedStorage:SetAttribute("DebugSkip", nil)
				break
			end
			if #Players:GetPlayers() < minPlayers() then
				-- Hold the timer until enough people are here
				endsAt = os.clock() + GameConfig.IntermissionTime
				setPhase("Intermission", GameConfig.IntermissionTime, `Waiting for {minPlayers()} players`)
			elseif
				newcomerWaiting
				-- a newcomer brings the round forward, but the hub break never drops below
				-- NewcomerMinBreak (every ad player joining kept cutting it to 100 s)
				and math.max(os.clock() + GameConfig.NewcomerRoundIn, startedAt + GameConfig.NewcomerMinBreak)
					< endsAt - 5
			then
				newcomerWaiting = false
				endsAt = math.max(os.clock() + GameConfig.NewcomerRoundIn, startedAt + GameConfig.NewcomerMinBreak)
				setPhase("Intermission", endsAt - os.clock(), INTERMISSION_STATUS)
			elseif ReplicatedStorage:GetAttribute("Status") ~= INTERMISSION_STATUS then
				setPhase("Intermission", endsAt - os.clock(), INTERMISSION_STATUS)
			end
			-- The night is coming (Steal An Egg's 10 s warning): anyone carrying a boss's coffin hears
			-- it goes back if it isn't home in time
			local left = endsAt - os.clock()
			if left > GameConfig.NightWarning + 2 then
				warned = false
			elseif not warned and left <= GameConfig.NightWarning then
				warned = true
				for _, player in Players:GetPlayers() do
					if player:GetAttribute("InRound") then
						continue
					end
					if StealService.BossCarry(player) then
						Net.Notify(player, "🔪 Murder round in 10! Get it home or it goes back!", "bad")
					else
						Net.Notify(player, "🔪 Murder round in 10 seconds!", "info")
					end
				end
			end
		end

		newcomerWaiting = false -- they'll be in this round anyway
		local participants = eligiblePlayers()
		if #participants < minPlayers() then
			continue
		end

		startRound(participants)
		local round = current :: Round
		Analytics.Track(nil, "round.server_start", {
			round_id = round.Id,
			players = #participants,
			bots = #round.Bots,
			map = round.Map,
			bot_murderer = round.MurdererBot ~= nil,
		})
		for player in round.Names do
			Analytics.Track(
				player,
				"round.start",
				roundProps(round, player, {
					chance = player:GetAttribute("MurdererChance"),
				})
			)
			Analytics.Milestone(player, "round_played")
			DataService.Update(player, function(p)
				p.RoundsPlayed += 1
			end)
			local played = DataService.Get(player)
			if played then
				player:SetAttribute("RoundsPlayed", played.RoundsPlayed)
			end
			if played and played.RoundsPlayed == 2 then
				-- stayed through a whole round and into the next one: the round didn't make them leave
				Analytics.Milestone(player, "second_round")
			end
			local role = roleOf(round, player)
			if role ~= "innocent" then
				Analytics.Milestone(player, "first_" .. role)
			end
		end
		setPhase("Reveal", GameConfig.RoleRevealSeconds, "HIDE!")
		Progress.Begin(round.Alive, round.Murderer, #round.Innocents + #round.Bots, round.RevealEndsAt)
		task.wait(math.max(0, round.RevealEndsAt - workspace:GetServerTimeNow()))
		setPhase("Round", GameConfig.RoundTime, "Survive!")
		local roundEnds = os.clock() + GameConfig.RoundTime
		while os.clock() < roundEnds and not roundOver(round) do
			task.wait(0.1)
			Progress.Tick(round.Alive)
			stepBots(round)
			-- The fall net: anyone who drops well below their spawn (fell through a floor that hadn't
			-- loaded yet, glitched out of the map) goes back to it instead of dying
			for player in round.Alive do
				local at = spawnOf[player]
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if at and character and root and not root.Anchored and root.Position.Y < at.Position.Y - 30 then
					character:PivotTo(at)
					holdWhileStreaming(player, character, at)
				end
			end
		end
		Progress.Tick(round.Alive)
		endRound(round)
		task.wait(GameConfig.ResultsTime)
	end
end

-- Studio "Bot Round" buttons: start a round now with bots filling in, `role` = the side the
-- asking player plays ("Murderer" | "Innocent")
function RoundService.DebugBotRound(player: Player, role: string)
	botPlan = { Player = player, Role = if role == "Innocent" then "Innocent" else "Murderer" }
	ReplicatedStorage:SetAttribute("DebugMinPlayers", 1)
	ReplicatedStorage:SetAttribute("DebugSkip", true)
end

function RoundService.Init()
	-- First visit (no tutorial yet, barely played): flag them for the client's round explainer, and
	-- once their first knife is home pull the next round in a little (see newcomerWaiting) - not
	-- on join: they can't be in a round before that knife anyway (eligiblePlayers)
	DataService.PlayerLoaded:Connect(function(player: Player, profile: DataService.Profile)
		if not profile.TutorialDone and profile.PlayTime < 120 then
			player:SetAttribute("FirstVisit", true)
			local connection: RBXScriptConnection
			connection = player:GetAttributeChangedSignal("Knives"):Connect(function()
				local now = DataService.Get(player)
				if now and #now.Knives > 0 then
					connection:Disconnect()
					newcomerWaiting = true
				end
			end)
		end
	end)
	task.spawn(function()
		while true do
			publishChances()
			task.wait(2)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local round = current
		if round and round.Alive[player] then
			round.Alive[player] = nil
			ReplicatedStorage:SetAttribute("Alive", aliveCount(round))
			-- Don't let the Revolver leave with them
			local root = rootOf(player)
			if round.Gunner == player then
				dropRevolver(round, if root then root.Position else MapService.RoundCenter + Vector3.new(0, 3, 0))
			end
		end
	end)
	Net.Remotes.Ability.OnServerEvent:Connect(onAbility)
	Net.Remotes.Shoot.OnServerEvent:Connect(onShoot)
	Net.Remotes.Stab.OnServerEvent:Connect(function(player: Player, target: any)
		local round = current
		local mine = round and killerRound(round, player)
		if mine and typeof(target) == "Instance" and target:IsA("Model") then
			mine.StabHint = { Target = target, At = os.clock() }
		end
	end)
	task.spawn(loop)
end

return RoundService
