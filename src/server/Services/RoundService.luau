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

local Format = require(ReplicatedStorage.Shared.Format)
local AnimLibrary = require(ReplicatedStorage.Shared.AnimLibrary)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local RoundPrize = require(ReplicatedStorage.Shared.RoundPrize)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local Props = require(ReplicatedStorage.Shared.Props)
local Textures = require(ReplicatedStorage.Shared.Config.Textures)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local Offers = require(script.Parent.Offers)
local Fuel = require(script.Parent.Fuel)
local MapService = require(script.Parent.MapService)
local Decoy = require(script.Parent.Decoy)
local Stealth = require(script.Parent.Stealth)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local Disguises = require(script.Parent.Disguises)
local Revolver = require(script.Parent.Revolver)
local StuckKnives = require(script.Parent.StuckKnives)
local StealService = require(script.Parent.StealService)
local RoundBots = require(script.Parent.RoundBots)
local Analytics = require(script.Parent.Analytics)
local CoffinService = require(script.Parent.CoffinService)
local MapVote = require(script.Parent.MapVote)
local Gamble = require(script.Parent.Gamble)
local SurpriseGifts = require(script.Parent.SurpriseGifts)

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
	PowerRevealed: boolean?, -- this Murderer's power has been announced (first use)
	Snares: { { Part: BasePart, Stun: number } }?, -- the Murderer's hidden snares (Snare power)
	Bots: { Bot },
	BotFolder: Folder,
	PrizeStats: { [Player]: RoundPrize.Stats }, -- each player's numbers when the round began
	Innocents: { Player },
	Alive: { [Player]: boolean },
	Kills: number,
	Weapon: Tool?,
	WeaponKnife: string,
	LastAttack: number,
	PerkReadyAt: number,
	Coins: Folder,
	Bodies: Folder,
	Loot: { { Owner: Player, Knife: string, Killer: Player? } },
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
	GunnerBot: Bot?, -- a bot Sheriff
	ShotByBot: boolean, -- a bot shot the (player) Murderer: loot goes home like a hero's shot
	Newcomer: boolean, -- a brand-new player's first round as the Murderer: the bots let them win
	HeroBot: Bot?, -- that bot (its face goes on the VS card)
	AtRisk: { [Player]: string }, -- the knife each innocent loses if the Murderer gets them (shown at the start)
	Classic: boolean, -- no powers, no perks, extra pay
	Double: boolean, -- DOUBLE TROUBLE: two Murderers, two Sheriffs
	Killers: { [Player]: boolean }, -- every Murderer this round (one, or two in Double Trouble)
	Partner: Player?, -- the second Murderer
	PartnerRound: Round?, -- their own view of the round (own knife and cooldowns; see partnerView)
	Gunner2: Player?, -- the second Sheriff
	GunTool2: Tool?,
	ShotKillers: { [Player]: boolean }, -- Murderers a Sheriff took down (their loot goes back)
	Id: string, -- analytics: round_id on every round event
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
local onMurderKill: (Round, Vector3) -> ()

-- Click-throw mode: all round for Spam Knife, a few seconds after Q for Hellfire (SpamUntil is a
-- player attribute the client reads too)
local function spamActive(player: Player): boolean
	local until_ = player:GetAttribute("SpamUntil")
	return type(until_) == "number" and workspace:GetServerTimeNow() < until_
end
-- Is this player one of the round's Murderers?
local function isKiller(round: Round, player: Player?): boolean
	return player ~= nil and round.Killers[player] == true
end

-- The second Murderer gets their own copy of the per-Murderer fields (Murderer, knife, cooldowns);
-- everything else reads and writes the real round. So every Murderer function just takes a round.
local OWN_FIELDS = {
	Murderer = true,
	Weapon = true,
	WeaponKnife = true,
	PowerRevealed = true,
	LastAttack = true,
	PerkReadyAt = true,
	ThrowReadyAt = true,
	FuryKills = true,
	PerkUses = true,
	BulletproofUsed = true,
	LatestAim = true,
	StabHint = true,
}
-- Is this the live round? The second Murderer's partnerView counts as the round it mirrors
local function isLive(round: Round): boolean
	return current ~= nil and (current == round or (current :: Round).PartnerRound == round)
end

local function partnerView(round: Round, partner: Player, knife: string): Round
	local own: { [string]: any } = {
		Murderer = partner,
		WeaponKnife = knife,
		LastAttack = 0,
		PerkReadyAt = 0,
		ThrowReadyAt = 0,
		FuryKills = 0,
		PerkUses = 0,
		BulletproofUsed = false,
	}
	return setmetatable({}, {
		__index = function(_, key)
			if OWN_FIELDS[key] then
				return own[key]
			end
			return (round :: any)[key]
		end,
		__newindex = function(_, key, value)
			if OWN_FIELDS[key] then
				own[key] = value
			else
				(round :: any)[key] = value
			end
		end,
	}) :: any
end

-- The round as seen by this Murderer (the partner's own view in Double Trouble)
local function killerRound(round: Round, player: Player): Round?
	if player == round.Murderer then
		return round
	elseif player == round.Partner then
		return round.PartnerRound
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
local function pay(round: Round, player: Player, entry: { Min: number, Seconds: number }, scale: number?): number
	local amount = math.floor(GameConfig.Pay(entry, BaseService.RackIncome(player)) * round.PayScale * (scale or 1))
	if amount > 0 then
		DataService.AddCash(player, amount, "round_pay")
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
		-- also: no round before your first knife is home (up to 5 min) - the newcomer pull-in
		-- dragged new players out mid-tutorial
		local fresh = here < GameConfig.RoundJoinGrace or (profile ~= nil and #profile.Knives == 0 and here < 300)
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
	local cap = if #players > 1 then total / #players * GameConfig.Fuel.MeterCap else math.huge
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
	elseif round.Sheriff == player or round.Gunner == player or round.Gunner2 == player then
		return "sheriff"
	end
	return "innocent"
end
local function roundProps(round: Round, player: Player, extra: { [string]: any }?): { [string]: any }
	local props: { [string]: any } = {
		round_id = round.Id,
		role = roleOf(round, player),
		classic = round.Classic,
		double = round.Double,
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
	player:SetAttribute("StunnedUntil", nil) -- (a Flash / Snare perk caught them)
	Stealth.Reveal(player) -- (a Shadow Murderer leaves visible)
	player:SetAttribute("SpamUntil", nil)
	player:SetAttribute("Perk", nil)
	player:SetAttribute("RoundSpeedBonus", nil)
	player:SetAttribute("PerkSpeed", nil)
	player:SetAttribute("Dread", nil)
	player:SetAttribute("KnifeOut", nil)
	for _, attribute in { "WeaponAt", "PerkPassive", "PerkUsesLeft", "PerkReadyAt", "RevolverReadyAt" } do
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

-- The Murderer takes a random knife off the victim's rack. It's held in the round's loot until
-- the round ends, so leaving or dying can't duplicate or lose it.
-- What the Murderer took off each victim (for their death card: killCard)
local deathLoss: { [Player]: { Lost: string?, Insured: boolean } } = {}

local function lootKnife(round: Round, victim: Player)
	deathLoss[victim] = { Lost = nil, Insured = false }
	local profile = DataService.Get(victim)
	if not profile then
		return
	end
	if DataService.IsNewPlayer(victim, profile) then
		return
	end
	-- Knife Insurance (Robux charge): the Murderer gets nothing
	local hasLoot = false
	for _, item in profile.Knives do
		if item ~= BaseService.ProtectedItem(victim) then
			hasLoot = true
			break
		end
	end
	if hasLoot and DataService.UseCharge(victim, "Insurance") then
		deathLoss[victim] = { Lost = nil, Insured = true }
		round.AtRisk[victim] = nil
		Analytics.Track(victim, "round.insured_save", roundProps(round, victim))
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
		-- The knife they were shown at the start of the round goes first
		local promised = round.AtRisk[victim]
		local promisedAt = promised and table.find(profile.Knives, promised)
		if promisedAt and promised ~= protected then
			index = promisedAt
			round.AtRisk[victim] = nil
		end
		local name = profile.Knives[index]
		DataService.Update(victim, function(p)
			DataService.RemoveKnife(p, index)
		end)
		BaseService.RefreshRack(victim)
		table.insert(round.Loot, { Owner = victim, Knife = name, Killer = round.Murderer })
		local parsed = Items.Parse(name) :: Items.Item
		local lootProps = {
			knife = parsed.Name,
			rarity = parsed.Knife.Rarity,
			mutation = parsed.Mutation.Id,
			value = Items.Income(name),
			promised = promisedAt ~= nil,
		}
		Analytics.Track(victim, "round.knife_lost", roundProps(round, victim, lootProps))
		if round.Murderer then
			Analytics.Track(round.Murderer, "round.knife_looted", roundProps(round, round.Murderer, lootProps))
		end
		-- (the victim's death card shows it, with the insurance offer: killCard)
		deathLoss[victim] = { Lost = name, Insured = false }
		if round.Murderer then
			Net.Notify(round.Murderer, `You took their {Items.DisplayName(name)}!`, "good")
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
			DataService.AddKnife(p, item)
			if not table.find(p.Discovered, parsed.Name) then
				table.insert(p.Discovered, parsed.Name)
			end
		end)
		BaseService.RefreshRack(player)
	else
		local value = math.floor(Items.Income(item) * GameConfig.SellSeconds)
		DataService.AddCash(player, value, "round_loot_sold")
		Net.Notify(player, `Your vault is full, so you got {Format.Cash(value)} instead`, "info")
	end
end

-- Hands a round prize over (RoundPrize: the same numbers the countdown showed) and pops it up
local function payPrize(
	player: Player,
	kind: string,
	side: string,
	jackpot: boolean,
	seed: number,
	stats: RoundPrize.Stats
)
	if not player.Parent or not DataService.Get(player) then
		return
	end
	local doubled = DataService.UseCharge(player, "DoublePrize")
	local prize = RoundPrize.For(kind, side, jackpot, seed, stats, doubled)
	if prize.Kind == "Cash" then
		DataService.AddCash(player, prize.Amount, "round_prize")
	elseif prize.Kind == "Speed" then
		DataService.Update(player, function(p)
			p.Speed += prize.Amount
		end)
		BaseService.RefreshWalkSpeed(player)
	elseif prize.Kind == "Knife" and prize.Knife then
		for _ = 1, prize.Amount do
			giveKnife(player, Items.Make(prize.Knife))
		end
	elseif prize.Kind == "Boost" then
		DataService.AddBoost(player, "Cash", prize.Amount)
	elseif prize.Kind == "Spins" then
		Gamble.AddSpins(player, prize.Amount)
	end
	-- (knives you can see, not a boss's name you don't know)
	local rarity = if prize.Rarity then string.upper(prize.Rarity) else nil
	local text = if rarity and prize.Reaches
		then `{prize.Text}\nNow you can steal {rarity} knives!`
		elseif rarity then `{prize.Text}\n{Format.Short(prize.Left)} more for {rarity} knives`
		else prize.Text
	-- Did the Speed get used? StealService tracks the next steal from that boss (prize.followup)
	if prize.Kind == "Speed" and prize.Zone then
		player:SetAttribute("PrizeTargetZone", prize.Zone)
	end
	Net.Remotes.Effect:FireClient(player, "PrizeWon", text, prize.Kind, prize.Knife, jackpot)
	Analytics.Track(player, "round.prize", {
		kind = prize.Kind,
		side = side,
		jackpot = jackpot,
		doubled = doubled,
		amount = prize.Amount,
		target_zone = prize.Zone,
		reaches = prize.Reaches,
	})
end

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

-- killer = who gets credit; fatal = kill the character here (false when they already died)
local function eliminate(round: Round, victim: Player, killer: Player?, fatal: boolean?)
	if not round.Alive[victim] then
		return
	end
	round.Alive[victim] = nil
	ReplicatedStorage:SetAttribute("Alive", aliveCount(round))
	if not isKiller(round, victim) then
		-- (no Heat lost any more: the round pulls everyone in, so dying in it shouldn't make your
		-- vault earn less)
		Fuel.AddMeter(victim, -1)
	end
	local root = rootOf(victim)
	if round.Gunner == victim and root then
		dropRevolver(round, root.Position)
	end
	if round.Gunner2 == victim then
		-- The second Sheriff's Revolver goes with them
		if round.GunTool2 then
			round.GunTool2:Destroy()
		end
		round.Gunner2, round.GunTool2 = nil, nil
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
			lootKnife(round, victim)
			onMurderKill(round, if root then root.Position else Vector3.zero)
		end
		local amount = pay(round, killer, GameConfig.RoundPay.Kill)
		DataService.Update(killer, function(p)
			p.TotalKills += 1
		end)
		Net.Notify(killer, `Got one! +{Format.Cash(amount)}`, "good")
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

local revealPower: (Round) -> ()
local killCard: (Round, Player) -> ()

-- Every way the Murderer can hurt someone ends here
local function strike(round: Round, victim: Player)
	if not round.Alive[victim] or isKiller(round, victim) then
		return -- (no friendly fire between Murderers)
	end
	if not round.Murderer then
		round.Kills += 1 -- a Murderer bot: no credit or loot, but it still kills
	end
	revealPower(round)
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
				Net.Notify(other, `{round.Names[killer] or "Someone"} shot the Murderer!`, "good")
			end
		end
	else
		round.Kills += 1
		if killer then
			local amount = pay(round, killer, GameConfig.RoundPay.Kill, GameConfig.BotKillPay)
			Net.Notify(killer, `Got one! +{Format.Cash(amount)}`, "good")
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
-- Stunned (StunnedUntil): no stabbing, throwing or perks until it wears off
local function isStunned(player: Player): boolean
	local until_ = player:GetAttribute("StunnedUntil")
	return type(until_) == "number" and workspace:GetServerTimeNow() < until_
end

local function onAttack(round: Round)
	local now = os.clock()
	local murderer = round.Murderer
	if not murderer or now - round.LastAttack < GameConfig.AttackCooldown or isStunned(murderer) then
		return
	end
	-- During a Spam Knife / Hellfire burst every click is a throw instead (onAbility "Spam")
	if spamActive(murderer) then
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
local function perkOf(round: Round): (string?, any)
	if round.Classic then
		return nil, nil -- CLASSIC: just a knife
	end
	local parsed = Items.Parse(round.WeaponKnife)
	local id = parsed and parsed.Perk
	return id, if id then GameConfig.Perks[id] else nil
end

local function knifePerkId(round: Round): string?
	return (perkOf(round))
end

-- The first time this Murderer's power shows itself (a throw, a perk, a kill, a bounced bullet),
-- everyone in the round (and anyone watching) gets the big "THE MURDERER HAS ..." banner. It names
-- the power, never the player (client/Transitions).
revealPower = function(round: Round)
	if round.PowerRevealed then
		return
	end
	local id, perk = perkOf(round)
	if not id or not perk then
		return
	end
	round.PowerRevealed = true
	Net.Remotes.Effect:FireAllClients("PowerReveal", {
		Perk = id,
		Name = perk.DisplayName,
		Description = perk.Description,
		Knife = round.WeaponKnife,
	})
end

-- The dead see who got them: the Murderer's disguise name, their knife, its power and the biome
-- that knife comes from (client/Transitions "KillCard")
killCard = function(round: Round, victim: Player)
	local id, perk = perkOf(round)
	local loss = deathLoss[victim]
	deathLoss[victim] = nil
	-- A free gift a minute later: dying isn't the end of your fun
	SurpriseGifts.Soon(victim, 60)
	Net.Remotes.Effect:FireClient(victim, "KillCard", {
		Lost = loss and loss.Lost,
		Insured = loss ~= nil and loss.Insured,
		New = DataService.IsNewPlayer(victim),
		Name = if round.Murderer
			then round.Names[round.Murderer] or "The Murderer"
			elseif round.MurdererBot then round.MurdererBot.Name
			else "The Murderer",
		Knife = round.WeaponKnife,
		Perk = id,
		PerkName = if perk then perk.DisplayName else nil,
	})
end

-- Kills one target in the blast around a throw kill (Exploding Knife, Hellfire)
local function explode(round: Round, at: Vector3, radius: number)
	Net.Remotes.Effect:FireAllClients("Explosion", at, radius)
	for player in round.Alive do
		local root = rootOf(player)
		if not isKiller(round, player) and root and (root.Position - at).Magnitude <= radius then
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
local function throwKnife(
	round: Round,
	origin: Vector3,
	direction: Vector3,
	charge: number,
	flaming: boolean?,
	range: number?,
	speedOverride: number?
)
	local config = { Range = range or GameConfig.MurderThrow.Range }
	local perkId, perk = perkOf(round)
	local speed = speedOverride or GameConfig.MurderThrow.Speed * (0.55 + 0.45 * charge)
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
	KnifeModel.FitLength(model, 1.9) -- matches the held knife
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
	Net.Remotes.Effect:FireAllClients("KnifeThrow", origin)
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
		if not stuck then
			model:Destroy()
		end
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
		if hit then
			-- Stays stuck in the wall / door for the rest of the round (round.Bodies goes at the end)
			StuckKnives.Stick(model, hit.Position, direction, 0, round.Bodies)
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
local function throwFromHand(
	round: Round,
	murderer: Player,
	direction: Vector3,
	charge: number,
	flaming: boolean?,
	range: number?,
	speed: number?
)
	local character = murderer.Character
	if not character then
		return
	end
	Net.Animate(character, "Throw", murderer)
	task.delay(AnimLibrary.Clips.Throw.Release or 0.07, function()
		local from = CombatService.HandPosition(murderer)
		if from and isLive(round) then
			throwKnife(round, from, direction, charge, flaming, range, speed)
		end
	end)
end

-- Spam Knife (always) / Hellfire (for a few seconds after Q): every click throws a knife straight
-- at where you aimed, as fast as you can click, flying until it hits something
local SPAM_SPEED = 80 -- ~70% of a charged throw: a spam knife can be dodged
local lastSpam: { [Player]: number } = {}
local function spamThrow(round: Round, murderer: Player, direction: Vector3)
	local character = murderer.Character
	local weapon = round.Weapon
	if not character or not weapon or weapon.Parent ~= character or isStunned(murderer) then
		return
	end
	local perkId, perk = perkOf(round)
	local flaming = perkId == "Hellfire"
	if not ((perkId == "SpamKnife" or flaming) and spamActive(murderer)) then
		return
	end
	local now = os.clock()
	if now - (lastSpam[murderer] or 0) < perk.Interval then
		return
	end
	lastSpam[murderer] = now
	local range = if perkId == "SpamKnife" then perk.Range else GameConfig.MurderThrow.Range
	throwFromHand(round, murderer, direction, 1, flaming, range, SPAM_SPEED)
end

local function usePerk(round: Round, direction: Vector3)
	local now = os.clock()
	local murderer = round.Murderer
	if not murderer or not round.Weapon or now < round.PerkReadyAt or isStunned(murderer) then
		return
	end
	local perkId, perk = perkOf(round)
	local root = rootOf(murderer)
	if not perkId or not perk or perk.Passive or not root then
		return
	end
	if perk.Uses then
		if round.PerkUses >= perk.Uses then
			Net.Notify(murderer, `No more {perk.DisplayName} this round`, "bad")
			return
		end
		round.PerkUses += 1
	end
	round.PerkReadyAt = now + perk.Cooldown
	murderer:SetAttribute("PerkUsesLeft", if perk.Uses then math.max(0, perk.Uses - round.PerkUses) else -1)
	murderer:SetAttribute("PerkReadyAt", workspace:GetServerTimeNow() + perk.Cooldown)
	Net.Remotes.AbilityState:FireClient(murderer, perk.DisplayName, workspace:GetServerTimeNow() + perk.Cooldown)
	round.LatestAim = direction
	Analytics.Track(murderer, "round.perk", roundProps(round, murderer, { perk = perkId, uses = round.PerkUses }))

	if perkId == "SpamKnife" then
		-- A burst of click-throwing
		murderer:SetAttribute("SpamUntil", workspace:GetServerTimeNow() + perk.Duration)
		Net.Notify(murderer, `SPAM KNIFE! Throw for {math.floor(perk.Duration)} seconds!`, "good")
	elseif perkId == "Hellfire" then
		-- For a few seconds every click throws a flaming knife
		murderer:SetAttribute("SpamUntil", workspace:GetServerTimeNow() + perk.Duration)
		Net.Remotes.Effect:FireAllClients("Hellfire", root.Position)
		Net.Notify(murderer, "HELLFIRE! Throw fire knives!", "bad")
	elseif perkId == "Identifier" then
		-- Who has the Revolver? Outlined through walls for a few seconds, on the Murderer's screen only
		local gunner = round.Gunner
		if gunner and gunner.Character then
			Net.Remotes.Effect:FireClient(murderer, "Radar", {
				{ Model = gunner.Character, Color = Color3.fromRGB(255, 220, 60) },
			}, perk.Duration)
			Net.Notify(murderer, `{round.Names[gunner] or "Someone"} has the gun!`, "bad")
		else
			Net.Notify(murderer, "Nobody has the gun yet", "info")
		end
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
			Net.Notify(murderer, `Poof! You are now {newName}!`, "good")
			-- (no Role event: that replayed the whole role reel. Just the poof.)
			-- Safety net: the knife must survive the change of clothes
			local weapon = round.Weapon
			if weapon and not weapon:IsDescendantOf(game) and round.Alive[murderer] then
				giveWeapon(round)
			end
		end
	elseif perkId == "Snare" then
		-- A hidden snare at your feet: the next innocent (or bot) to step in is stuck
		local snare = Instance.new("Part")
		snare.Name = "Snare"
		snare.Anchored, snare.CanCollide, snare.CanQuery, snare.CanTouch = true, false, false, false
		snare.Size = Vector3.new(2.6, 0.12, 2.6)
		snare.Shape = Enum.PartType.Cylinder
		snare.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.9, 0)) * CFrame.Angles(0, 0, math.rad(90))
		snare.Color = Color3.fromRGB(60, 50, 45)
		snare.Material = Enum.Material.Metal
		snare.Transparency = 0.6 -- hard to spot, not invisible
		snare.Parent = round.Bodies
		local snares = round.Snares or {}
		round.Snares = snares
		table.insert(snares, { Part = snare, Stun = perk.Duration })
		Net.Notify(murderer, "Trap set!", "good")
	elseif perkId == "DecoyKnife" then
		Decoy.Run(murderer, perk.Duration)
		Net.Notify(murderer, "A fake you runs off!", "good")
	elseif perkId == "FlashKnife" then
		local look = Vector3.new(direction.X, 0, direction.Z)
		look = if look.Magnitude > 0.01 then look.Unit else root.CFrame.LookVector
		local origin = root.Position + Vector3.new(0, 1.5, 0)
		Net.Remotes.Effect:FireAllClients("Flash", origin, look)
		local range = perk.Range or 24
		local function caught(position: Vector3): boolean
			local offset = position - origin
			return offset.Magnitude < range and (offset.Magnitude < 6 or look:Dot(offset.Unit) > 0.5)
		end
		local until_ = workspace:GetServerTimeNow() + perk.Duration
		for other in round.Alive do
			local r = rootOf(other)
			if r and not isKiller(round, other) and caught(r.Position) then
				other:SetAttribute("StunnedUntil", until_)
				BaseService.RefreshWalkSpeed(other)
				Net.Remotes.Effect:FireClient(other, "Blinded", perk.Duration)
				task.delay(perk.Duration, function()
					BaseService.RefreshWalkSpeed(other)
				end)
			end
		end
		for _, bot in round.Bots do
			if bot.Alive and bot ~= round.MurdererBot and caught(bot.Root.Position) then
				bot.StunnedUntil = until_
			end
		end
	end
end

-- Snares: the first innocent (player or bot) within reach of one is stuck, and it's gone
local function stepSnares(round: Round)
	local snares = round.Snares
	if not snares or #snares == 0 then
		return
	end
	local now = workspace:GetServerTimeNow()
	for i = #snares, 1, -1 do
		local snare = snares[i]
		local at = snare.Part.Position
		local function near(position: Vector3): boolean
			return Vector3.new(position.X - at.X, 0, position.Z - at.Z).Magnitude < 2.2
				and math.abs(position.Y - at.Y) < 5
		end
		local sprung = false
		for other in round.Alive do
			local r = rootOf(other)
			if r and not isKiller(round, other) and near(r.Position) then
				other:SetAttribute("StunnedUntil", now + snare.Stun)
				BaseService.RefreshWalkSpeed(other)
				Net.Notify(other, "You're stuck in a trap!", "bad")
				task.delay(snare.Stun, function()
					BaseService.RefreshWalkSpeed(other)
				end)
				sprung = true
				break
			end
		end
		if not sprung then
			for _, bot in round.Bots do
				if bot.Alive and bot ~= round.MurdererBot and near(bot.Root.Position) then
					bot.StunnedUntil = now + snare.Stun
					sprung = true
					break
				end
			end
		end
		if sprung then
			Net.Remotes.Effect:FireAllClients("Hit", at)
			snare.Part:Destroy()
			table.remove(snares, i)
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
	if now < round.ThrowReadyAt or not character or not weapon or weapon.Parent ~= character or isStunned(murderer) then
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
	if mine then
		revealPower(mine)
		if kind == "Spam" then
			spamThrow(mine, player, direction)
		elseif kind == "Throw" then
			basicThrow(mine, player, direction)
		else
			usePerk(mine, direction)
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
	local coin = Props.Build("Coin", true)
	coin.Name = "Coin"
	-- Streams in whole: clients spin it, and a rim arriving after the spin started sat crooked
	coin.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
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
		Analytics.Count(player, "coins")
		Net.Remotes.Effect:FireClient(player, "Coin", position, amount)
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
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = Revolver.BuildTool()
	tool.Parent = backpack
	round.GunTool = tool
	round.Gunner = player
	round.Sheriff = round.Sheriff or player
	player:SetAttribute("RevolverReadyAt", 0)
	ReplicatedStorage:SetAttribute("Revolver", "Taken")
	-- The role card said Innocent a moment ago: show the real role now
	Net.Remotes.Role:FireClient(player, "Sheriff", round.Names[player])
	Net.Notify(player, "You're the SHERIFF! Shoot the Murderer. Don't hit anyone else!", "good")
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
		Net.Notify(player, "You got the gun! Shoot the Murderer!", "good")
	end)
end

local function onShoot(player: Player, aim: unknown)
	local round = current
	if
		not round
		or (round.Gunner ~= player and round.Gunner2 ~= player)
		or not round.Alive[player]
		or typeof(aim) ~= "Vector3"
	then
		return
	end
	local character = player.Character
	local tool = if player == round.Gunner2 then round.GunTool2 else round.GunTool
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
	for _, holder in { round.Gunner, round.Gunner2 } do
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
	local perkId = if shotKiller then perkOf(shotKiller) else nil
	if shotKiller and perkId == "Bulletproof" and not shotKiller.BulletproofUsed then
		-- The bullet bounces off; the vest is used up
		shotKiller.BulletproofUsed = true
		revealPower(shotKiller)
		local victimRoot = rootOf(victim)
		if victimRoot then
			Net.Remotes.Effect:FireAllClients("Shield", victimRoot.Position)
		end
		Net.Notify(victim, "Bulletproof! That shot bounced off!", "good")
		Net.Notify(player, "It bounced off! Shoot again!", "bad")
		return
	end
	if shotKiller then
		if not round.Hero then
			Analytics.Track(player, "round.hero", roundProps(round, player))
			Analytics.Milestone(player, "hero_shot")
		end
		round.Hero = round.Hero or player
		round.ShotKillers[victim] = true
		local victimRoot = rootOf(victim)
		if victimRoot then
			finalMoment(round, victimRoot.Position, "Hero")
		end
		for other in round.Alive do
			Net.Notify(other, `{round.Names[player] or "Someone"} shot the Murderer!`, "good")
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
	for killer in round.Killers do
		local view = killerRound(round, killer)
		local weapon = view and view.Weapon
		-- Only once the knife is out (pulling it is the reveal)
		if
			view
			and weapon
			and round.Alive[killer]
			and weapon.Parent == killer.Character
			and not killer:GetAttribute("Invisible")
		then
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
			Net.Notify(other, `{bot.Name} shot the Murderer!`, "good")
		end
		killBot(round, murdererBot, nil)
		return
	end
	local murderer = round.Murderer
	if not murderer then
		return
	end
	local perkId = perkOf(round)
	if perkId == "Bulletproof" and not round.BulletproofUsed then
		round.BulletproofUsed = true
		revealPower(round)
		Net.Remotes.Effect:FireAllClients("Shield", target.Position)
		Net.Notify(murderer, "Bulletproof! That shot bounced off!", "good")
		return
	end
	round.ShotByBot = true
	round.HeroBot = bot
	finalMoment(round, target.Position, "Hero")
	for other in round.Alive do
		Net.Notify(other, `{bot.Name} shot the Murderer!`, "good")
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

	local stunned = workspace:GetServerTimeNow() < bot.StunnedUntil
	if bestDist < GameConfig.AttackRange - 2 and now >= bot.NextStab and not stunned then
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
	local perkId, perk = perkOf(round)
	-- Spam Knife: click = throw for the whole round (the same mode Hellfire's Q turns on briefly)
	murderer:SetAttribute("PerkPassive", if perk then perk.Passive == true else nil)
	murderer:SetAttribute("PerkUsesLeft", if perk then (perk.Uses or -1) else nil)
	murderer:SetAttribute("PerkReadyAt", 0)
	local spam = perkId == "SpamKnife" and perk ~= nil and perk.Passive == true
	if spam then
		murderer:SetAttribute("SpamUntil", workspace:GetServerTimeNow() + GameConfig.RoundTime + 60)
	end
	Net.Notify(
		murderer,
		`{Items.DisplayName(round.WeaponKnife)} is in your hotbar. Pull it out when you're ready - everyone will see it! {if spam
			then "Click = throw!"
			else "Click = stab, hold = throw."}`,
		"bad"
	)
	if perk then
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
	local built = MapService.BuildRoundMap(MapVote.TakeWinner())
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
	-- DOUBLE TROUBLE: two Murderers (and two Sheriffs). Always on busy servers, sometimes on quiet
	-- ones; needs two real players to be the Murderers. Your teammate is picked with you.
	local partner: Player? = nil
	if
		not plan
		and murderer
		and #participants >= 3
		and (#participants >= GameConfig.DoubleTrouble.Always or rng:NextNumber() < GameConfig.DoubleTrouble.Chance)
	then
		local rest = table.clone(participants)
		table.remove(rest, table.find(rest, murderer) :: number)
		partner = pickMurderer(rest)
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
		PrizeStats = {},
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
		Double = false,
		Killers = if murderer then { [murderer] = true } else {},
		Partner = nil,
		PartnerRound = nil,
		Gunner2 = nil,
		GunTool2 = nil,
		ShotKillers = {},
		GunnerBot = nil,
		ShotByBot = false,
		Newcomer = newcomer,
		HeroBot = nil,
		-- (never for a Studio bot round: those are for testing perks and powers)
		Classic = plan == nil and rng:NextNumber() < GameConfig.ClassicChance,
		AtRisk = {},
		PayScale = if #participants >= 2 then 1 else GameConfig.BotRoundPay,
		HumanKills = 0,
		Connections = {},
		Id = `{string.sub(game.JobId, 1, 6)}-{string.format("%x", os.time())}`,
		StartedAt = os.clock(),
		Map = built.Name,
	}
	current = round
	if partner then
		round.Double = true
		round.Partner = partner
		round.Killers[partner] = true
		round.PartnerRound = partnerView(round, partner, murdererKnife(partner))
	end
	ReplicatedStorage:SetAttribute("Classic", round.Classic or nil)
	ReplicatedStorage:SetAttribute("Double", round.Double or nil)
	if round.Classic then
		round.PayScale *= GameConfig.ClassicPay
	end
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

	-- Screens fade to black with the map's name while everyone is moved (client/Transitions)
	for _, player in participants do
		-- Let go of anything the client holds you in (the wheel lock) before the server moves you
		player:SetAttribute("RoundTeleport", true)
		Net.Remotes.Effect:FireClient(
			player,
			"Fade",
			`🔪 {ReplicatedStorage:GetAttribute("MapName") or "The Murder"}{if round.Double
				then "\nDOUBLE TROUBLE - 2 Murderers, 2 Sheriffs!"
				else ""}{if round.Classic
				then "\nCLASSIC ROUND - no Murderer power, x" .. GameConfig.ClassicPay .. " pay!"
				else ""}`
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
		StealService.Suspend(player) -- handed back when they return to this spot
		local isMurderer = round.Killers[player] == true
		if not isMurderer then
			table.insert(round.Innocents, player)
		end
		round.Alive[player] = true
		round.PrizeStats[player] = RoundPrize.Stats(player)
		player:SetAttribute("InRound", true)
		player:SetAttribute("Role", if isMurderer then "Murderer" else "Innocent")
		DataService.Update(player, function(p)
			p.Luck = if isMurderer then 0 else p.Luck + GameConfig.Fuel.MeterPerRound
		end)

		-- Back to exactly this spot when the round is over (BaseService.TeleportHome)
		local here = character:GetPivot()
		local facing = here.LookVector * Vector3.new(1, 0, 1)
		BaseService.SetReturnSpot(
			player,
			if facing.Magnitude > 0.1 then CFrame.lookAt(here.Position, here.Position + facing) else here
		)
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
		Net.Remotes.Role:FireClient(player, if isMurderer then "Murderer" else "Innocent", round.Names[player])

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

	if round.Partner then
		local a, b = round.Murderer :: Player, round.Partner :: Player
		for _, pair in { { a, b }, { b, a } } do
			Net.Remotes.Effect:FireClient(
				pair[1],
				"Partner",
				pair[2].Character,
				round.Names[pair[2]] or pair[2].DisplayName
			)
		end
	end
	for killer in round.Killers do
		killer:SetAttribute("WeaponAt", workspace:GetServerTimeNow() + GameConfig.MurdererGrace)
	end
	task.delay(GameConfig.MurdererGrace, function()
		if current == round then
			giveWeapon(round)
			if round.PartnerRound then
				giveWeapon(round.PartnerRound)
			end
		end
	end)
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
			giveRevolver(round, chosen :: Player)
		else
			giveRevolverToBot(round, chosen)
		end
		table.remove(sheriffs, table.find(sheriffs, chosen) :: number)
		if round.Double and #sheriffs > 0 then
			local second = sheriffs[rng:NextInteger(1, #sheriffs)]
			if typeof(second) == "Instance" then
				local player = second :: Player
				local tool = Revolver.BuildTool()
				tool.Parent = player:FindFirstChildOfClass("Backpack")
				round.Gunner2, round.GunTool2 = player, tool
				Net.Notify(player, "You're a SHERIFF too! There are 2 Murderers!", "good")
			else
				giveRevolverToBot(round, second)
			end
		end
	end

	-- Everyone sees the knife they'd lose to the Murderer (client/Transitions spins a reel onto it).
	-- Only when a real player has the knife: bot Murderers never loot, and the card promised a loss
	-- that couldn't happen (then the death card said "your knives are safe")
	local atRisk: { Player } = if next(round.Killers) ~= nil then round.Innocents else {}
	for _, player in atRisk do
		local profile = DataService.Get(player)
		if not profile or DataService.IsNewPlayer(player, profile) then
			continue
		end
		local protected = BaseService.ProtectedItem(player)
		local choices = {}
		for _, item in profile.Knives do
			if item ~= protected then
				table.insert(choices, item)
			end
		end
		-- (insured players aren't shown a knife at risk: there isn't one)
		if #choices > 0 and (profile.Charges.Insurance or 0) == 0 then
			local chosen = choices[rng:NextInteger(1, #choices)]
			round.AtRisk[player] = chosen
			Net.Remotes.Effect:FireClient(player, "AtRisk", choices, chosen)
		end
	end

	-- Nobody took the Revolver (or it dropped): it turns up somewhere later
	task.delay(GameConfig.RevolverTime, function()
		if current == round and not round.Gunner and not round.GunnerBot and not round.Revolver then
			spawnRevolver(round, nil)
			for player in round.Alive do
				Net.Notify(player, "A gun dropped somewhere. Find it!", "info")
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
	if round.PartnerRound and round.PartnerRound.Weapon then
		round.PartnerRound.Weapon:Destroy()
	end
	if round.GunTool2 then
		round.GunTool2:Destroy()
	end
	ReplicatedStorage:SetAttribute("Double", nil)
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
	local murdererPresent = murderer == nil or murderer.Parent ~= nil
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
					loot = #round.Loot,
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

	-- Loot goes back to its owners if the Innocents won, or the Murderer was shot (or quit);
	-- the Murderer keeps it only when they win. ("You won!" and then a missing knife spoiled it.)
	local hero = round.Hero
	local kept: { [Player]: { string } } = {}
	for _, entry in round.Loot do
		local killer = entry.Killer or murderer
		local returned = innocentsWon
			or round.ShotByBot
			or not killer
			or not killer.Parent
			or round.ShotKillers[killer]
			or (not round.Double and (hero ~= nil or not murdererPresent))
		if returned or not killer then
			if entry.Owner.Parent then
				giveKnife(entry.Owner, entry.Knife)
				Net.Notify(entry.Owner, `Your {Items.DisplayName(entry.Knife)} is back!`, "good")
			end
		else
			giveKnife(killer, entry.Knife)
			kept[killer] = kept[killer] or {}
			table.insert(kept[killer], entry.Knife)
		end
	end
	-- The haul, once everyone's back in the hub (after the VS card): the Murderer sees every knife
	-- they took, and the whole server hears about it
	for killer, items in kept do
		task.delay(GameConfig.ResultsTime + 1, function()
			if not killer.Parent then
				return
			end
			Net.Remotes.Effect:FireClient(killer, "LootHaul", items)
			local count = #items
			Net.Announce(
				`🔪 {killer.DisplayName} the Murderer stole {count} {if count == 1 then "knife" else "knives"}!`,
				Color3.fromRGB(255, 90, 90),
				2
			)
		end)
	end
	-- Coffins: the murder rounds are their clock - one round off everyone's, two for the winners
	local coffinWinners: { [Player]: boolean } = {}
	for player in round.Names do
		local role = roleOf(round, player)
		coffinWinners[player] = if role == "murderer" then not innocentsWon else innocentsWon
	end
	CoffinService.RoundEnded(coffinWinners)
	-- The round prize: the winning side gets what the countdown promised, once they're home
	local prizeKind = ReplicatedStorage:GetAttribute("PrizeKind")
	if type(prizeKind) == "string" then
		local jackpot = ReplicatedStorage:GetAttribute("PrizeJackpot") == true
		local seed = (ReplicatedStorage:GetAttribute("PrizeSeed") or 1) :: number
		for player in round.Names do
			local role = roleOf(round, player)
			local side = if role == "murderer" then "Murderer" else "Innocent"
			local won = if side == "Murderer" then not innocentsWon else innocentsWon
			local stats = round.PrizeStats[player]
			if won and stats then
				task.delay(GameConfig.ResultsTime + 2, payPrize, player, prizeKind, side, jackpot, seed, stats)
			elseif stats and player.Parent then
				-- lost: the prize they picked is still waiting - win the next one
				local prize = RoundPrize.For(prizeKind, side, false, seed, stats, false)
				task.delay(GameConfig.ResultsTime + 2, function()
					if player.Parent then
						Net.Notify(player, `So close! Win the next murder round for {prize.Text}`, "info")
					end
				end)
			end
		end
	end
	if hero and hero.Parent then
		local amount = pay(round, hero, GameConfig.RoundPay.Hero)
		Net.Notify(hero, `HERO! +{Format.Cash(amount)}`, "good")
	end
	ReplicatedStorage:SetAttribute("Loot", nil)
	if round.Partner and round.Partner.Parent and not innocentsWon then
		Fuel.AddHeat(round.Partner, 1, "You won as the Murderers!")
	end
	if murderer and murderer.Parent and not innocentsWon then
		Fuel.AddHeat(murderer, 1, "You won as the Murderer!")
	end
	local fewLeft = #survivors <= math.max(1, math.ceil(#round.Innocents * GameConfig.LastAliveFraction))

	-- The innocents' side won: everyone on it gets something, even the ones who didn't make it
	if innocentsWon and murdererPresent then
		for _, player in round.Innocents do
			if player.Parent and not table.find(survivors, player) and player ~= hero then
				local amount = pay(round, player, GameConfig.RoundPay.TeamWin)
				Net.Notify(player, `Your side won! +{Format.Cash(amount)}`, "good")
			end
		end
	end

	for _, player in survivors do
		Fuel.AddHeat(player, 1, "Survived the round!")
		Fuel.AddMeter(player, 1)
		local reward = pay(round, player, GameConfig.RoundPay.Survive)
			+ (if fewLeft then pay(round, player, GameConfig.RoundPay.LastAlive) else 0)
		DataService.Update(player, function(p)
			p.RoundsWon += 1
			player:SetAttribute("Wins", p.RoundsWon)
		end)
		Net.Notify(player, `You survived! +{Format.Cash(reward)}`, "good")
		if player.Character then
			Net.Animate(player.Character, "Cheer")
		end
		player:SetAttribute("BoostUntil", workspace:GetServerTimeNow() + GameConfig.BoostDuration)
		Net.Notify(player, `{GameConfig.BoostMultiplier}x money for {GameConfig.BoostDuration} seconds!`, "info")
	end
	if murderer and murdererPresent then
		if hero then
			Net.Notify(murderer, "You got shot! The knives you took went back.", "bad")
		elseif not innocentsWon and round.Kills > 0 then -- no bonus when everyone just left
			-- One against the whole lobby: the prize grows with every real player they got
			local bonus = pay(round, murderer, GameConfig.RoundPay.Wipe)
			for _ = 1, round.HumanKills do
				bonus += pay(round, murderer, GameConfig.RoundPay.WipePerVictim)
			end
			DataService.Update(murderer, function(p)
				p.RoundsWon += 1
				murderer:SetAttribute("Wins", p.RoundsWon)
			end)
			Net.Notify(murderer, `You got everyone! +{Format.Cash(bonus)}`, "good")
			if round.HumanKills > 0 then
				local config = GameConfig.WipeCase
				local rarity = if #round.Innocents >= config.BigLobby then config.Big else config.Small
				task.delay(1.5, function()
					if not murderer.Parent then
						return
					end
					if StealService.OpenCase(murderer, rarity) then
						Net.Notify(murderer, `You won a {rarity} Case!`, "good")
					else
						local value = 0
						for _, entry in GameConfig.CaseShop do
							if entry.Rarity == rarity then
								value = entry.Cost
							end
						end
						DataService.AddCash(murderer, value, "round_wipe")
						Net.Notify(murderer, `Your vault is full, so +{Format.Cash(value)} instead`, "good")
					end
				end)
			end
		else
			Net.Notify(murderer, "Time's up!", "info")
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
	if round.Partner then
		leaveRound(round.Partner)
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
	ReplicatedStorage:SetAttribute("Classic", nil)
	-- The VS card: who was the Murderer, with which knife, and who stopped them (client/Transitions)
	local heroName: string? = if hero
		then `{round.Names[hero] or "?"} ({hero.DisplayName})`
		elseif round.HeroBot then `{round.HeroBot.Name} (bot Sheriff)`
		else nil
	local _, murdererPerk = perkOf(round)
	local murdererPower: string? = if murdererPerk then murdererPerk.DisplayName else nil
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
		MurdererName = if murderer and round.Partner
			then `{round.Names[murderer] or "?"} & {round.Names[round.Partner] or "?"}`
			elseif murderer then `{round.Names[murderer] or "?"} ({murderer.DisplayName})`
			elseif round.MurdererBot then `{round.MurdererBot.Name} (bot)`
			else "?",
		MurdererId = if murderer then murderer.UserId else 0,
		Knife = round.WeaponKnife,
		HeroName = heroName,
		HeroId = if hero then hero.UserId else 0,
		MurdererFace = murdererBotFace,
		HeroFace = heroBotFace,
		Kills = round.Kills,
		Classic = round.Classic,
		-- The Murderer's knife power on show
		MurdererPower = murdererPower,
		SheriffName = sheriffName,
		SheriffId = sheriffId,
		SheriffStatus = sheriffStatus,
	}
	for player in round.Names do
		if player.Parent then
			Net.Remotes.Effect:FireClient(player, "RoundCard", card)
		end
	end
end

local function roundOver(round: Round): boolean
	local murderer = round.Murderer
	-- Every Murderer down (both, in Double Trouble): the innocents win
	if murderer then
		local anyLeft = false
		for killer in round.Killers do
			if round.Alive[killer] and killer.Parent then
				anyLeft = true
			end
		end
		if not anyLeft then
			return true
		end
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
		local insuranceOffered = false
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
				and math.max(os.clock() + GameConfig.NewcomerRoundIn, startedAt + GameConfig.NewcomerMinBreak) < endsAt - 5
				-- never cut a Thief Moon short (it runs out the intermission)
				and not ReplicatedStorage:GetAttribute("Raid")
				and ReplicatedStorage:GetAttribute("NextRaidAt") == nil
			then
				newcomerWaiting = false
				endsAt = math.max(os.clock() + GameConfig.NewcomerRoundIn, startedAt + GameConfig.NewcomerMinBreak)
				setPhase("Intermission", endsAt - os.clock(), INTERMISSION_STATUS)
			elseif ReplicatedStorage:GetAttribute("Status") ~= INTERMISSION_STATUS then
				setPhase("Intermission", endsAt - os.clock(), INTERMISSION_STATUS)
			end
			-- Just before the round: anyone with knives to lose and no insurance gets the offer once
			local left = endsAt - os.clock()
			if left <= 25 and not insuranceOffered then
				insuranceOffered = true
				for _, player in Players:GetPlayers() do
					local profile = DataService.Get(player)
					if
						profile
						and #profile.Knives >= 3
						and (profile.Charges.Insurance or 0) == 0
						and not DataService.IsNewPlayer(player, profile)
					then
						Offers.Show(
							player,
							"Insurance3",
							"Murder round soon! Insure your knives so the Murderer can't take one."
						)
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
			classic = round.Classic,
			double = round.Double,
			map = round.Map,
			bot_murderer = round.MurdererBot ~= nil,
		})
		for player in round.Names do
			Analytics.Track(
				player,
				"round.start",
				roundProps(round, player, {
					chance = player:GetAttribute("MurdererChance"),
					at_risk = round.AtRisk[player] ~= nil,
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
		setPhase("Round", GameConfig.RoundTime, "Survive!")
		local roundEnds = os.clock() + GameConfig.RoundTime
		while os.clock() < roundEnds and not roundOver(round) do
			task.wait(0.1)
			stepBots(round)
			stepSnares(round)
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
	-- The prize you picked for the next round (client/PrizePick); RoundPrize.Stats reads it at round start
	local lastPick: { [Player]: number } = {}
	Net.Remotes.PrizePick.OnServerEvent:Connect(function(player: Player, pick: unknown)
		if
			pick ~= "Cash" and pick ~= "Speed"
			or player:GetAttribute("InRound")
			or player:GetAttribute("PrizePickOn") ~= true
		then
			return
		end
		if os.clock() - (lastPick[player] or 0) < 0.3 then
			return
		end
		lastPick[player] = os.clock()
		local before = player:GetAttribute("PrizePick")
		player:SetAttribute("PrizePick", pick)
		local endsAt = (ReplicatedStorage:GetAttribute("PhaseEndsAt") or 0) :: number
		Analytics.Track(player, "prize.pick", {
			pick = pick,
			changed = before ~= nil and before ~= pick,
			seconds_left = math.floor(endsAt - workspace:GetServerTimeNow()),
		})
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastPick[player] = nil
	end)
	-- A/B "prize_pick": who gets the card (the rest keep the Speed-only prize)
	local function pickGroup(player: Player)
		player:SetAttribute("PrizePickOn", Analytics.Variant(player, "prize_pick") ~= "classic")
	end
	for _, player in Players:GetPlayers() do
		pickGroup(player)
	end
	Players.PlayerAdded:Connect(pickGroup)
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
