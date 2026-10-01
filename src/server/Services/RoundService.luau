--!strict
-- The main event. Every few minutes everyone is pulled into a round: one Murderer (weighted by
-- the luck meter and tickets), everyone else survives until the timer runs out.
-- Round state is published as attributes on ReplicatedStorage for the HUD:
--   Phase ("Intermission" | "Round" | "Results"), PhaseEndsAt (server time), Status (text), Alive
--
-- Classic murder-game rules: a random indoor map, everyone disguised as a named character
-- (Disguises), bodies stay where they fall, and a Revolver drops mid-round that any innocent can
-- grab. The two halves of the game feed each other:
--   * the Murderer's equipped knife (stolen in the arena) gives them a perk (GameConfig.Perks)
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
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local Props = require(ReplicatedStorage.Shared.Props)
local Textures = require(ReplicatedStorage.Shared.Config.Textures)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local PowerService = require(script.Parent.PowerService)
local Stealth = require(script.Parent.Stealth)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local Disguises = require(script.Parent.Disguises)
local Obstacles = require(script.Parent.Obstacles)
local Revolver = require(script.Parent.Revolver)
local StealService = require(script.Parent.StealService)
local RoundBots = require(script.Parent.RoundBots)

local RoundService = {}

type Bot = RoundBots.Bot

type Round = {
	Murderer: Player?, -- nil when a bot is the Murderer
	MurdererBot: Bot?,
	Bots: { Bot },
	BotFolder: Folder,
	Innocents: { Player },
	Alive: { [Player]: boolean },
	Kills: number,
	Weapon: Tool?,
	WeaponKnife: string,
	LastAttack: number,
	PerkReadyAt: number,
	Coins: Folder,
	Bodies: Folder,
	Loot: { { Owner: Player, Knife: string } },
	Names: { [Player]: string },
	Revolver: Model?, -- the pickup while it's lying somewhere
	Gunner: Player?, -- whoever holds it
	GunTool: Tool?,
	LastShot: number,
	ThrowReadyAt: number,
	FuryKills: number,
	PerkUses: number,
	BulletproofUsed: boolean,
	LatestAim: Vector3?, -- where the Murderer is aiming (kept fresh during a Spam Knife volley)
	StabHint: { Target: Model, At: number }?, -- who the Murderer's client says the last swing was at
	Hero: Player?,
	PayScale: number, -- 1, or GameConfig.BotRoundPay with fewer than two real players
	HumanKills: number, -- real players the Murderer got (bots don't count toward the wipe prize)
	Connections: { RBXScriptConnection },
}

local current: Round? = nil
local rng = Random.new()
local updateDread: (Round) -> ()
local onMurderKill: (Round, Vector3) -> ()
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
local function pay(round: Round, player: Player, entry: { Min: number, Seconds: number }, scale: number?): number
	local amount = math.floor(GameConfig.Pay(entry, BaseService.RackIncome(player)) * round.PayScale * (scale or 1))
	if amount > 0 then
		DataService.AddCash(player, amount)
	end
	return amount
end

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
	local roll = rng:NextNumber() * total
	for _, player in participants do
		roll -= weights[player]
		if roll <= 0 then
			return player
		end
	end
	return participants[#participants]
end

-- The equipped knife if they still own it, otherwise their highest earner
local function murdererKnife(player: Player): string
	local profile = DataService.Get(player)
	if not profile then
		return "RustyShank"
	end
	if profile.Equipped ~= "" and table.find(profile.Knives, profile.Equipped) then
		return profile.Equipped
	end
	local best, bestIncome = "RustyShank", -1
	for _, item in profile.Knives do
		local income = Items.Income(item)
		if income > bestIncome then
			best, bestIncome = item, income
		end
	end
	return best
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
	player:SetAttribute("PerkSpeed", nil)
	player:SetAttribute("Dread", nil)
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

-- The Murderer takes a random knife off the victim's rack. It's held in the round's loot until
-- the round ends, so leaving or dying can't duplicate or lose it.
local function lootKnife(round: Round, victim: Player)
	local profile = DataService.Get(victim)
	if not profile then
		return
	end
	if DataService.IsNewPlayer(victim, profile) then
		if round.Murderer then
			Net.Notify(round.Murderer, `{round.Names[victim] or "They"} is new here - nothing to loot.`, "info")
		end
		return
	end
	for _ = 1, GameConfig.LootPerKill do
		-- Anything but the knife they fight with
		local choices = {}
		local protected = BaseService.ProtectedItem(victim)
		for index, item in profile.Knives do
			if item ~= protected then
				table.insert(choices, index)
			end
		end
		if #choices == 0 then
			break
		end
		local index = choices[rng:NextInteger(1, #choices)]
		local name = profile.Knives[index]
		DataService.Update(victim, function(p)
			table.remove(p.Knives, index)
		end)
		BaseService.RefreshRack(victim)
		table.insert(round.Loot, { Owner = victim, Knife = name })
		local parsed = Items.Parse(name) :: Items.Item
		Net.Notify(victim, `The Murderer took your {Items.DisplayName(name)}! Shoot them to get it back.`, "bad")
		if round.Murderer then
			Net.Notify(round.Murderer, `Looted a {Items.DisplayName(name)} ({parsed.Knife.Rarity})!`, "good")
		end
		ReplicatedStorage:SetAttribute("Loot", #round.Loot)
	end
end

-- Puts a knife on a rack, or pays its sell value if the rack is full
local function giveKnife(player: Player, item: string)
	local profile = DataService.Get(player)
	local parsed = Items.Parse(item)
	if not profile or not parsed then
		return
	end
	if #profile.Knives < profile.Slots then
		DataService.Update(player, function(p)
			table.insert(p.Knives, item)
			if not table.find(p.Discovered, parsed.Name) then
				table.insert(p.Discovered, parsed.Name)
			end
		end)
		BaseService.RefreshRack(player)
	else
		local value = math.floor(Items.Income(item) * GameConfig.SellSeconds)
		DataService.AddCash(player, value)
		Net.Notify(player, `Rack full - {Items.DisplayName(item)} sold for ${value}`, "info")
	end
end

local spawnRevolver: (Round, Vector3?) -> ()

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
		if player ~= round.Murderer then
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

-- killer = who gets credit; fatal = kill the character here (false when they already died)
local function eliminate(round: Round, victim: Player, killer: Player?, fatal: boolean?)
	if not round.Alive[victim] then
		return
	end
	round.Alive[victim] = nil
	ReplicatedStorage:SetAttribute("Alive", aliveCount(round))
	local root = rootOf(victim)
	if round.Gunner == victim and root then
		dropRevolver(round, root.Position)
	end
	leaveRound(victim)
	if killer then
		if killer == round.Murderer then
			round.Kills += 1
			round.HumanKills += 1
			lootKnife(round, victim)
			onMurderKill(round, if root then root.Position else Vector3.zero)
		end
		local amount = pay(round, killer, GameConfig.RoundPay.Kill)
		DataService.Update(killer, function(p)
			p.TotalKills += 1
		end)
		Net.Notify(killer, `Eliminated {round.Names[victim] or victim.DisplayName}! +${amount}`, "good")
	end
	if killer or fatal then
		Net.Notify(victim, "You were killed! You'll respawn at your vault.", "bad")
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
	if root and victim ~= round.Murderer and innocentsLeft(round) == 0 and #round.Innocents + #round.Bots > 0 then
		finalMoment(round, root.Position, "Wipe")
	end
end

-- Every way the Murderer can hurt someone ends here, so the Shield works against all of them
local function strike(round: Round, victim: Player)
	if not round.Alive[victim] or victim == round.Murderer then
		return
	end
	Stealth.Reveal(victim) -- getting stabbed blows any Vanish / Mimic cover
	local character = victim.Character
	local shieldUntil = character and character:GetAttribute("ShieldUntil")
	if character and type(shieldUntil) == "number" and workspace:GetServerTimeNow() < shieldUntil then
		character:SetAttribute("ShieldUntil", nil)
		local root = rootOf(victim)
		if root then
			Net.Remotes.Effect:FireAllClients("Shield", root.Position)
		end
		Net.Notify(victim, "Your Shield blocked the hit! RUN!", "good")
		if round.Murderer then
			Net.Notify(round.Murderer, `{round.Names[victim] or "Their"}'s Shield blocked you!`, "bad")
		end
		return
	end
	if not round.Murderer then
		round.Kills += 1 -- a Murderer bot: no credit or loot, but it still kills
	end
	eliminate(round, victim, round.Murderer, true)
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
	RoundBots.Kill(bot, push, round.Bodies)
	if bot == round.MurdererBot then
		finalMoment(round, bot.Root.Position, "Hero")
	elseif innocentsLeft(round) == 0 then
		finalMoment(round, bot.Root.Position, "Wipe")
	end
	if bot == round.MurdererBot then
		if killer then
			round.Hero = killer
			for other in round.Alive do
				Net.Notify(other, `{round.Names[killer] or "Someone"} shot the Murderer!`, "good")
			end
		end
	else
		round.Kills += 1
		if killer then
			local amount = pay(round, killer, GameConfig.RoundPay.Kill, GameConfig.BotKillPay)
			Net.Notify(killer, `Eliminated {bot.Name}! +${amount}`, "good")
			if killer == round.Murderer then
				onMurderKill(round, bot.Root.Position)
			end
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
	if current ~= round or not murdererRoot or not round.Alive[murderer] then
		return
	end
	local weapon = round.Weapon
	local handle = weapon and weapon:FindFirstChild("Handle")
	local sound = handle and handle:FindFirstChild("Slash") :: Sound?
	if sound then
		sound:Play()
	end
	Net.Remotes.Effect:FireAllClients("Swing", murdererRoot.Position)
	PowerService.PopDecoyNear(murdererRoot.Position + murdererRoot.CFrame.LookVector * 3, GameConfig.AttackRange)

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
	-- A Barricade in the way takes the hit instead
	local obstacle = Obstacles.Near(murdererRoot.Position, GameConfig.AttackRange, murdererRoot.CFrame.LookVector)
	if obstacle then
		local point = obstacle.Part.Position
		if (point - murdererRoot.Position).Magnitude < closestDist + 1 then
			obstacle.Hit("Murderer")
			return
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
local function perkOf(round: Round): (string?, any)
	local parsed = Items.Parse(round.WeaponKnife)
	local id = parsed and parsed.Knife.Perk
	return id, if id then GameConfig.Perks[id] else nil
end

local function knifePerkId(round: Round): string?
	return (perkOf(round))
end

-- Kills one target in the blast around a throw kill (Exploding Knife, Hellfire)
local function explode(round: Round, at: Vector3, radius: number)
	Net.Remotes.Effect:FireAllClients("Explosion", at, radius)
	for player in round.Alive do
		local root = rootOf(player)
		if player ~= round.Murderer and root and (root.Position - at).Magnitude <= radius then
			strike(round, player)
		end
	end
	for _, bot in round.Bots do
		if bot.Alive and bot ~= round.MurdererBot and (bot.Root.Position - at).Magnitude <= radius then
			killBot(round, bot, round.Murderer)
		end
	end
end

-- A thrown knife. Perks change it: Fury (faster per kill), Laser Knife (full charge = lightning
-- fast), Ghost Knife (flies through people), Exploding Knife / Hellfire (kills explode).
local function throwKnife(round: Round, origin: Vector3, direction: Vector3, charge: number, flaming: boolean?)
	local config = GameConfig.MurderThrow
	local perkId, perk = perkOf(round)
	local speed = config.Speed * (0.55 + 0.45 * charge)
	if perkId == "Fury" then
		speed *= 1 + round.FuryKills * perk.PerKill
	end
	local laser = perkId == "LaserKnife" and charge >= 0.95
	if laser then
		speed = perk.Speed
	end
	local pierceLeft = if perkId == "GhostKnife" then perk.Pierce else 1
	local blast = if perkId == "ExplodingKnife" or perkId == "Hellfire" then perk.Radius else nil

	local model = KnifeModel.Build(round.WeaponKnife, true)
	KnifeModel.FitLength(model, 2.6)
	for _, d in model:GetDescendants() do
		if d:IsA("Trail") then
			d.Enabled = true
		elseif d:IsA("BasePart") then
			if perkId == "GhostKnife" then
				d.Transparency = math.max(d.Transparency, 0.45)
			end
		end
	end
	local primary = model.PrimaryPart :: BasePart
	if flaming then
		local fire = Instance.new("Fire")
		fire.Size = 3
		fire.Heat = 8
		fire.Color = Color3.fromRGB(255, 120, 30)
		fire.SecondaryColor = Color3.fromRGB(255, 40, 10)
		fire.Parent = primary
	end
	model.Parent = workspace
	if laser then
		Net.Remotes.Effect:FireAllClients("Laser", origin, origin + direction * config.Range)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { (round.Murderer :: Player).Character :: Model, model, round.Bodies }

	local hitAlready: { [any]: boolean } = {}
	local position, traveled, spin = origin, 0, 0
	local connection: RBXScriptConnection
	local function finish(stuck: boolean)
		connection:Disconnect()
		game:GetService("Debris"):AddItem(model, if stuck then 2 else 0)
	end
	local function landed(at: Vector3, killed: boolean): boolean
		if killed then
			if blast then
				explode(round, at, blast)
			end
		end
		pierceLeft -= 1
		return pierceLeft <= 0
	end
	connection = RunService.Heartbeat:Connect(function(dt)
		if current ~= round then
			finish(false)
			return
		end
		local stepLength = math.min(speed * dt, config.Range - traveled)
		local nextPosition = position + direction * stepLength

		-- Generous hit test against innocents so it feels fair on laggy connections
		for player in round.Alive do
			local root = rootOf(player)
			if
				player ~= round.Murderer
				and not hitAlready[player]
				and root
				and distanceToSegment(root.Position, position, nextPosition) < 3
			then
				hitAlready[player] = true
				local at = root.Position
				strike(round, player)
				if landed(at, not round.Alive[player]) then
					finish(false)
					return
				end
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
				local at = bot.Root.Position
				killBot(round, bot, round.Murderer)
				if landed(at, true) then
					finish(false)
					return
				end
			end
		end
		local hit = workspace:Raycast(position, nextPosition - position, params)
		if hit then
			-- A Barricade takes the knife
			local obstacle = Obstacles.Near(hit.Position, 1.5, nil)
			if obstacle then
				obstacle.Hit("Murderer")
			end
			model:PivotTo(CFrame.lookAt(hit.Position, hit.Position + direction) * CFrame.Angles(-math.pi / 2, 0, 0))
			finish(true)
			return
		end

		position = nextPosition
		traveled += stepLength
		spin += dt * 25
		model:PivotTo(CFrame.lookAt(position, position + direction) * CFrame.Angles(if laser then 0 else spin, 0, 0))
		if traveled >= config.Range then
			finish(false)
		end
	end)
	table.insert(round.Connections, connection)
end

-- Throws one knife from the Murderer's hand on the Throw clip's release frame
local function throwFromHand(round: Round, murderer: Player, direction: Vector3, charge: number, flaming: boolean?)
	local character = murderer.Character
	if not character then
		return
	end
	Net.Animate(character, "Throw", murderer)
	task.delay(AnimLibrary.Clips.Throw.Release or 0.07, function()
		local from = CombatService.HandPosition(murderer)
		if from and current == round then
			throwKnife(round, from, direction, charge, flaming)
		end
	end)
end

-- Spam Knife / Hellfire: a volley of quick throws wherever the Murderer is aiming
local function volley(round: Round, murderer: Player, perk: any, flaming: boolean)
	local endsAt = os.clock() + perk.Duration
	murderer:SetAttribute("SpamUntil", workspace:GetServerTimeNow() + perk.Duration)
	task.spawn(function()
		while current == round and os.clock() < endsAt and round.Alive[murderer] do
			local root = rootOf(murderer)
			if not root then
				break
			end
			local aim = round.LatestAim or root.CFrame.LookVector
			-- A little spread, so it sprays
			local spread = CFrame.Angles(math.rad(rng:NextNumber(-3, 3)), math.rad(rng:NextNumber(-5, 5)), 0)
			throwFromHand(round, murderer, (CFrame.lookAt(Vector3.zero, aim) * spread).LookVector, 0.6, flaming)
			task.wait(perk.Interval)
		end
		murderer:SetAttribute("SpamUntil", nil)
	end)
end

local function usePerk(round: Round, direction: Vector3)
	local now = os.clock()
	local murderer = round.Murderer
	if not murderer or not round.Weapon or now < round.PerkReadyAt then
		return
	end
	local perkId, perk = perkOf(round)
	local root = rootOf(murderer)
	if not perkId or not perk or perk.Passive or not root then
		return
	end
	if perk.Uses then
		if round.PerkUses >= perk.Uses then
			Net.Notify(murderer, `No {perk.DisplayName} left this round`, "bad")
			return
		end
		round.PerkUses += 1
	end
	round.PerkReadyAt = now + perk.Cooldown
	Net.Remotes.AbilityState:FireClient(murderer, perk.DisplayName, workspace:GetServerTimeNow() + perk.Cooldown)
	round.LatestAim = direction

	if perkId == "SpamKnife" then
		volley(round, murderer, perk, false)
		Net.Remotes.Effect:FireAllClients("Dash", root.Position)
	elseif perkId == "Hellfire" then
		volley(round, murderer, perk, true)
		Net.Remotes.Effect:FireAllClients("Hellfire", root.Position)
	elseif perkId == "Identifier" then
		-- Who has the Revolver? Outlined through walls for a few seconds, on the Murderer's screen only
		local gunner = round.Gunner
		if gunner and gunner.Character then
			Net.Remotes.Effect:FireClient(murderer, "Radar", {
				{ Model = gunner.Character, Color = Color3.fromRGB(255, 220, 60) },
			}, perk.Duration)
			Net.Notify(murderer, `{round.Names[gunner] or "Someone"} has the Revolver!`, "bad")
		else
			Net.Notify(murderer, "Nobody has the Revolver yet...", "info")
		end
		Net.Notify(murderer, `Identifier: {perk.Uses - round.PerkUses} left`, "info")
	elseif perkId == "ShapeShifter" then
		local taken: { [string]: boolean } = {}
		for _, name in round.Names do
			taken[name] = true
		end
		for _, bot in round.Bots do
			taken[bot.Name] = true
		end
		local newName = Disguises.Shift(murderer, taken)
		if newName then
			round.Names[murderer] = newName
			Net.Remotes.Effect:FireAllClients("Smoke", root.Position)
			Net.Notify(murderer, `You are now {newName}!`, "good")
			Net.Remotes.Role:FireClient(murderer, "Murderer", newName)
		end
	end
end

-- Every kill the Murderer makes (players or bots): Fury stacks, Invisiknife cloaks
onMurderKill = function(round: Round, _at: Vector3)
	local murderer = round.Murderer
	local perkId, perk = perkOf(round)
	if not murderer or not perkId then
		return
	end
	if perkId == "Fury" then
		round.FuryKills += 1
		local root = rootOf(murderer)
		if root then
			Net.Remotes.Effect:FireAllClients("Fury", root.Position, round.FuryKills)
		end
		Net.Notify(
			murderer,
			`FURY x{round.FuryKills}: throws +{math.floor(round.FuryKills * perk.PerKill * 100)}% faster`,
			"bad"
		)
	elseif perkId == "Invisiknife" then
		Stealth.Vanish(murderer, perk.Duration)
	end
end

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
	round.ThrowReadyAt = now + GameConfig.MurdererThrowCooldown
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
	if player == round.Murderer then
		if kind == "Aim" then
			round.LatestAim = direction -- the client keeps this fresh during a volley
		elseif kind == "Throw" then
			basicThrow(round, player, direction)
		else
			usePerk(round, direction)
		end
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
		local hit = workspace:Raycast(Vector3.new(center.X + x, 12, center.Z + z), Vector3.new(0, -20, 0))
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
	local coin = Props.Build("Coin", true)
	coin.Name = "Coin"
	coin:PivotTo(at)
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Shape = Enum.PartType.Ball
	hitbox.Size = Vector3.one * 3.4
	hitbox.CFrame = at
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanQuery = false
	hitbox.Transparency = 1
	hitbox.Parent = coin
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 80)
	light.Range = 6
	light.Brightness = 0.7
	light.Shadows = false
	light.Parent = hitbox
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Texture = Textures.Sparkle
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 235, 150))
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkle.Lifetime = NumberRange.new(0.5, 0.9)
	sparkle.Rate = 2.5
	sparkle.Speed = NumberRange.new(0.3, 0.8)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Rotation = NumberRange.new(0, 360)
	sparkle.Parent = hitbox
	coin.PrimaryPart = hitbox
	return coin, hitbox
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
		if not player or not round.Alive[player] or not coin.Parent or current ~= round then
			return
		end
		local position = hitbox.Position
		coin:Destroy()
		local amount = pay(round, player, GameConfig.RoundPay.Coin)
		PowerService.AddEnergy(player, GameConfig.EnergyPerCoin)
		Net.Remotes.Effect:FireClient(player, "Coin", position, amount)
		task.delay(GameConfig.CoinRespawn, function()
			if current == round then
				spawnCoin(round)
			end
		end)
	end)
end

-- Revolver ----------------------------------------------------------------------------------

spawnRevolver = function(round: Round, position: Vector3?)
	if current ~= round or round.Revolver then
		return
	end
	local point = position or randomFloorPoint()
	if not point then
		return
	end
	local pickup = Revolver.BuildPickup(point + Vector3.new(0, if position then 0 else 2.5, 0))
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
		if not round.Alive[player] or player == round.Murderer or round.Gunner then
			return
		end
		pickup:Destroy()
		round.Revolver = nil
		local backpack = player:FindFirstChildOfClass("Backpack")
		local tool = Revolver.BuildTool()
		tool.Parent = backpack
		round.GunTool = tool
		round.Gunner = player
		ReplicatedStorage:SetAttribute("Revolver", "Taken")
		Net.Notify(player, "You have the Revolver! Shoot the Murderer, but don't hit an innocent!", "good")
		for other_ in round.Alive do
			if other_ ~= player then
				Net.Notify(other_, "Someone picked up the Revolver...", "info")
			end
		end
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
			Net.Notify(player, "You shot an innocent! That costs you your life.", "bad")
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
	local perkId = perkOf(round)
	if victim == round.Murderer and perkId == "Bulletproof" and not round.BulletproofUsed then
		-- The bullet bounces off; the vest is used up
		round.BulletproofUsed = true
		local victimRoot = rootOf(victim)
		if victimRoot then
			Net.Remotes.Effect:FireAllClients("Shield", victimRoot.Position)
		end
		Net.Notify(victim, "BULLETPROOF! That shot bounced off. Next one counts!", "good")
		Net.Notify(player, "They're BULLETPROOF! Shoot again!", "bad")
		return
	end
	if victim == round.Murderer then
		round.Hero = player
		local victimRoot = rootOf(victim)
		if victimRoot then
			finalMoment(round, victimRoot.Position, "Hero")
		end
		for other in round.Alive do
			Net.Notify(other, `{round.Names[player] or "Someone"} shot the Murderer!`, "good")
		end
		eliminate(round, victim, player, true)
	elseif
		victim.Character
		and type(victim.Character:GetAttribute("ShieldUntil")) == "number"
		and workspace:GetServerTimeNow() < victim.Character:GetAttribute("ShieldUntil") :: number
	then
		victim.Character:SetAttribute("ShieldUntil", nil)
		Net.Notify(victim, "Your Shield stopped a bullet!", "good")
	else
		-- Shot an innocent: both go down, and the Revolver drops where the shooter stood
		Net.Notify(player, "You shot an innocent! That costs you your life.", "bad")
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
	local murderer = round.Murderer
	if not murderer or not round.Alive[murderer] or not round.Weapon then
		return nil
	end
	if murderer:GetAttribute("Invisible") or murderer:GetAttribute("Mimic") then
		return nil
	end
	return rootOf(murderer)
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

local function innocentBrain(round: Round, bot: Bot, now: number)
	local threat = murdererThreat(round)
	if not threat or (threat.Position - bot.Root.Position).Magnitude > 32 then
		wander(bot, now)
		return
	end
	-- Run! Head for a spot far from the Murderer that isn't back past it
	bot.Humanoid.WalkSpeed = GameConfig.RoundWalkSpeed - 1
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
	if not bot.Knife then
		wander(bot, now) -- the grace period: blend in
		return
	end
	-- Bear traps catch a Murderer bot too
	local stun = PowerService.SpringRoundTrap(bot.Root.Position)
	if stun then
		bot.StunnedUntil = workspace:GetServerTimeNow() + stun
		Net.Animate(bot.Model, "Hurt")
	end
	-- Stuck at a Barricade: smash it
	local obstacle = Obstacles.Near(bot.Root.Position, 4.5, bot.Root.CFrame.LookVector)
	if obstacle and now >= bot.NextStab then
		bot.NextStab = now + 1
		RoundBots.Face(bot, obstacle.Part.Position)
		Net.Animate(bot.Model, "Stab")
		obstacle.Hit("Murderer")
		return
	end

	-- Hunt the closest person it can see (Vanish / Mimic hide you)
	local target: BasePart?, targetPlayer: Player?, targetBot: Bot? = nil, nil, nil
	local bestDist = math.huge
	for player in round.Alive do
		local root = rootOf(player)
		if root and not player:GetAttribute("Invisible") and not player:GetAttribute("Mimic") then
			local dist = (root.Position - bot.Root.Position).Magnitude
			if dist < bestDist then
				target, targetPlayer, targetBot, bestDist = root, player, nil, dist
			end
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
	if not target then
		wander(bot, now)
		return
	end
	bot.Humanoid.WalkSpeed = GameConfig.MurdererWalkSpeed - 0.5
	RoundBots.WalkTo(bot, target.Position)

	local stunned = workspace:GetServerTimeNow() < bot.StunnedUntil
	if bestDist < GameConfig.AttackRange - 2 and now >= bot.NextStab and not stunned then
		bot.NextStab = now + 1.2
		RoundBots.Face(bot, target.Position)
		Net.Animate(bot.Model, "Stab")
		Net.Remotes.Effect:FireAllClients("Swing", bot.Root.Position)
		PowerService.PopDecoyNear(bot.Root.Position + bot.Root.CFrame.LookVector * 3, GameConfig.AttackRange)
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

-- Dread: how close the Murderer (with the knife out) is to each innocent, 0..1. Clients turn
-- it into a heartbeat and a dark vignette. Nobody is told who the Murderer is.
updateDread = function(round: Round)
	local murdererRoot: BasePart? = nil
	if round.MurdererBot then
		murdererRoot = if round.MurdererBot.Alive and round.MurdererBot.Knife then round.MurdererBot.Root else nil
	elseif round.Murderer and round.Weapon and round.Alive[round.Murderer] then
		murdererRoot = rootOf(round.Murderer)
	end
	for player in round.Alive do
		if player == round.Murderer then
			continue
		end
		local root = rootOf(player)
		local dread = 0
		if root and murdererRoot then
			local distance = (root.Position - murdererRoot.Position).Magnitude
			dread = math.clamp(1 - (distance - 8) / 45, 0, 1)
		end
		local value = if dread > 0.05 then math.floor(dread * 10 + 0.5) / 10 else nil
		if player:GetAttribute("Dread") ~= value then
			player:SetAttribute("Dread", value)
		end
	end
end

-- Round flow --------------------------------------------------------------------------------

local function giveWeapon(round: Round)
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
	slash.SoundId = Sounds.Slash
	slash.Volume = 0.8
	slash.Parent = tool:FindFirstChild("Handle")
	tool.Parent = backpack
	round.Weapon = tool
	-- Tool.Activated replicates to the server; the client never reports hits itself
	table.insert(
		round.Connections,
		tool.Activated:Connect(function()
			onAttack(round)
		end)
	)
	local _, perk = perkOf(round)
	Net.Notify(
		murderer,
		`{Items.DisplayName(round.WeaponKnife)} is in your hotbar. Pull it out when you're ready - everyone will see it! Click = stab, hold = throw.`,
		"bad"
	)
	if perk then
		Net.Notify(
			murderer,
			`Perk: {perk.DisplayName} - {perk.Description}{if perk.Passive then "" else " (Q)"}`,
			"bad"
		)
		-- Only active perks get a button
		Net.Remotes.AbilityState:FireClient(murderer, if perk.Passive then nil else perk.DisplayName, 0)
		murderer:SetAttribute("Perk", knifePerkId(round))
	end
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
	local built = MapService.BuildRoundMap()
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
	local murderer: Player?
	if plan then
		murderer = if plan.Role == "Murderer" then plan.Player else nil
	elseif #participants == 1 and botCount > 0 then
		local profile = DataService.Get(participants[1])
		local weight = 1
			+ (if profile then profile.Luck else 0)
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
		PerkReadyAt = 0,
		Coins = coins,
		Bodies = bodies,
		Loot = {},
		Names = {},
		Revolver = nil,
		Gunner = nil,
		GunTool = nil,
		LastShot = 0,
		ThrowReadyAt = 0,
		FuryKills = 0,
		PerkUses = 0,
		BulletproofUsed = false,
		LatestAim = nil,
		Hero = nil,
		PayScale = if #participants >= 2 then 1 else GameConfig.BotRoundPay,
		HumanKills = 0,
		Connections = {},
	}
	current = round
	ReplicatedStorage:SetAttribute("Revolver", nil)
	ReplicatedStorage:SetAttribute("Loot", nil)

	-- Everyone becomes a named character (yields while outfits apply)
	round.Names = Disguises.Assign(participants)

	-- Shuffle spawns so the Murderer's spot gives nothing away
	local spawns = table.clone(MapService.RoundSpawns)
	for i = #spawns, 2, -1 do
		local j = rng:NextInteger(1, i)
		spawns[i], spawns[j] = spawns[j], spawns[i]
	end

	for i, player in participants do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid then
			continue
		end
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

		character:PivotTo(spawns[(i - 1) % #spawns + 1])
		BaseService.RefreshWalkSpeed(player)
		Net.Remotes.Role:FireClient(player, if isMurderer then "Murderer" else "Innocent", round.Names[player])

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

	if botCount > 0 then
		local taken: { [string]: boolean } = {}
		for _, name in round.Names do
			taken[name] = true
		end
		local roles: { string } = {}
		for i = 1, botCount do
			table.insert(roles, if i == 1 and not murderer then "Murderer" else "Innocent")
		end
		for i, role in roles do
			local at = spawns[(#participants + i - 1) % #spawns + 1]
			local bot = RoundBots.Spawn(at, role, taken, botFolder)
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

	task.delay(GameConfig.MurdererGrace, function()
		if current == round then
			giveWeapon(round)
		end
	end)
	task.delay(GameConfig.RevolverTime, function()
		if current == round then
			spawnRevolver(round, nil)
			for player in round.Alive do
				Net.Notify(player, "A Revolver appeared somewhere in the building!", "info")
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
	local murdererPresent = murderer == nil or murderer.Parent ~= nil
	local botsSurvived = false
	for _, bot in round.Bots do
		if bot.Alive and bot ~= round.MurdererBot then
			botsSurvived = true
		end
	end
	local innocentsWon = #survivors > 0 or botsSurvived or round.Hero ~= nil

	-- Loot goes back to its owners if the Murderer was shot (or quit); otherwise they keep it
	local hero = round.Hero
	if hero or not murdererPresent then
		for _, entry in round.Loot do
			if entry.Owner.Parent then
				giveKnife(entry.Owner, entry.Knife)
				Net.Notify(entry.Owner, `Your {Items.DisplayName(entry.Knife)} is back!`, "good")
			end
		end
		if hero and hero.Parent then
			local amount = pay(round, hero, GameConfig.RoundPay.Hero)
			Net.Notify(hero, `HERO! You stopped the Murderer! +${amount}`, "good")
		end
	elseif murderer then
		for _, entry in round.Loot do
			giveKnife(murderer, entry.Knife)
		end
		if #round.Loot > 0 then
			Net.Notify(murderer, `{#round.Loot} looted knife(s) added to your vault!`, "good")
		end
	end
	ReplicatedStorage:SetAttribute("Loot", nil)
	local fewLeft = #survivors <= math.max(1, math.ceil(#round.Innocents * GameConfig.LastAliveFraction))

	-- The innocents' side won: everyone on it gets something, even the ones who didn't make it
	if innocentsWon and murdererPresent then
		for _, player in round.Innocents do
			if player.Parent and not table.find(survivors, player) and player ~= hero then
				local amount = pay(round, player, GameConfig.RoundPay.TeamWin)
				Net.Notify(player, `Your side won! +${amount}`, "good")
			end
		end
	end

	for _, player in survivors do
		local reward = pay(round, player, GameConfig.RoundPay.Survive)
			+ (if fewLeft then pay(round, player, GameConfig.RoundPay.LastAlive) else 0)
		DataService.Update(player, function(p)
			p.RoundsWon += 1
		end)
		Net.Notify(player, `You survived! +${reward}`, "good")
		if player.Character then
			Net.Animate(player.Character, "Cheer")
		end
		player:SetAttribute("BoostUntil", workspace:GetServerTimeNow() + GameConfig.BoostDuration)
		Net.Notify(
			player,
			`Survivor boost: {GameConfig.BoostMultiplier}x vault income for {GameConfig.BoostDuration}s!`,
			"info"
		)
	end
	if murderer and murdererPresent then
		if hero then
			Net.Notify(murderer, "You were shot! Your loot went back to its owners.", "bad")
		elseif not innocentsWon and round.Kills > 0 then -- no bonus when everyone just left
			-- One against the whole lobby: the prize grows with every real player they got
			local bonus = pay(round, murderer, GameConfig.RoundPay.Wipe)
			for _ = 1, round.HumanKills do
				bonus += pay(round, murderer, GameConfig.RoundPay.WipePerVictim)
			end
			DataService.Update(murderer, function(p)
				p.RoundsWon += 1
			end)
			Net.Notify(murderer, `You got everyone! Bonus +${bonus}`, "good")
			if round.HumanKills > 0 then
				local config = GameConfig.WipeCase
				local rarity = if #round.Innocents >= config.BigLobby then config.Big else config.Small
				task.delay(1.5, function()
					if not murderer.Parent then
						return
					end
					if StealService.OpenCase(murderer, rarity) then
						Net.Notify(murderer, `Wipe prize: a {rarity} Case!`, "good")
					else
						local value = 0
						for _, entry in GameConfig.CaseShop do
							if entry.Rarity == rarity then
								value = entry.Cost
							end
						end
						DataService.AddCash(murderer, value)
						Net.Notify(
							murderer,
							`Wipe prize: your wall is full, so +${value} instead of a {rarity} Case`,
							"good"
						)
					end
				end)
			end
		else
			Net.Notify(murderer, `Time's up! {round.Kills} eliminated.`, "info")
		end
	end

	-- Everyone still in the round goes home as themselves
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

	local murdererName = if murderer
		then `{round.Names[murderer] or "?"} ({murderer.DisplayName})`
		else `{if round.MurdererBot then round.MurdererBot.Name else "?"} (a bot)`
	local status = if #round.Innocents == 0 and #round.Bots == 0
		then "Solo test round over" -- Studio debug rounds have nobody to survive
		elseif hero then `{round.Names[hero] or hero.DisplayName} shot the Murderer, {murdererName}!`
		elseif innocentsWon then `Innocents win! The Murderer was {murdererName}`
		else `The Murderer wins! It was {murdererName}`
	setPhase("Results", GameConfig.ResultsTime, status)
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
		if player ~= murderer and player.Parent then
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
		setPhase("Intermission", GameConfig.IntermissionTime, "Next round in")
		local endsAt = os.clock() + GameConfig.IntermissionTime
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
			elseif ReplicatedStorage:GetAttribute("Status") ~= "Next round in" then
				setPhase("Intermission", endsAt - os.clock(), "Next round in")
			end
		end

		local participants = eligiblePlayers()
		if #participants < minPlayers() then
			continue
		end

		startRound(participants)
		local round = current :: Round
		setPhase("Round", GameConfig.RoundTime, "Survive!")
		local roundEnds = os.clock() + GameConfig.RoundTime
		local nextDread = 0
		while os.clock() < roundEnds and not roundOver(round) do
			task.wait(0.1)
			stepBots(round)
			if os.clock() >= nextDread then
				nextDread = os.clock() + 0.4
				updateDread(round)
			end
		end
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
	-- Flash blinds a Murderer bot too
	PowerService.OnFlash(function(_flasher, origin, look, range, duration)
		local round = current
		local bot = round and round.MurdererBot
		if bot and bot.Alive then
			local offset = bot.Root.Position - origin
			if offset.Magnitude < range and look:Dot(offset.Unit) > 0.7 then
				bot.StunnedUntil = workspace:GetServerTimeNow() + duration
				Net.Animate(bot.Model, "Hurt")
			end
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
		if round and player == round.Murderer and typeof(target) == "Instance" and target:IsA("Model") then
			round.StabHint = { Target = target, At = os.clock() }
		end
	end)
	task.spawn(loop)
end

return RoundService
