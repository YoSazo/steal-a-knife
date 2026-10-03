--!strict
-- Break-ins, any time outside a round:
--   * every vault gate is a barrier you can break - knife swings and throws chip its health
--     (GameConfig.Walls). The owner is alerted the moment someone starts on it, can repair it
--     (R) and come home to stop them. A broken gate stays open for a bit, then reforges.
--   * inside a broken vault, anything on the wall except its owner's equipped knife can be
--     stolen (hold "Steal"); carry it home and it's yours
--   * hub knives knock down intruders and anyone carrying loot (never hurt them): they drop it.
--     A vault's owner who catches their thief gets the knife back, a bounty, and sends them home.
--   * a vault that just lost a knife is sealed for a while (GameConfig.Raid.RobbedSeal)
--   * gates can't be touched while their owner is in a round, during a round, or while the owner
--     still has the new-player shield
-- The Thief Moon (the "raid" in code) rises every few intermissions: burglars (NPCs) come for
-- everyone's knives, gates take more damage, bounties double and anyone outside their own vault can
-- be knocked down.
-- Getting robbed gives you revenge: for a while the thief's vault is open to you.
-- Knives on walls give off an aura (better knife, bigger aura) that slows anyone who isn't the
-- owner. State for clients lives in attributes: ReplicatedStorage Raid/RaidEndsAt/NextRaidAt,
-- gate Blockers (Health, MaxHealth, Open), players (KnockedUntil, RevengeOn, RevengeUntil,
-- AuraSlow, AuraFrom).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Format = require(ReplicatedStorage.Shared.Format)
local AnimLibrary = require(ReplicatedStorage.Shared.AnimLibrary)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local Props = require(ReplicatedStorage.Shared.Props)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local Disguises = require(script.Parent.Disguises)
local GuardService = require(script.Parent.GuardService)
local Offers = require(script.Parent.Offers)
local MapService = require(script.Parent.MapService)
local Obstacles = require(script.Parent.Obstacles)
local PowerService = require(script.Parent.PowerService)
local Ragdoll = require(script.Parent.Ragdoll)
local StealService = require(script.Parent.StealService)
local ServerEvents = require(script.Parent.ServerEvents)
local Targets = require(script.Parent.Targets)
local VaultWalls = require(script.Parent.VaultWalls)

local RaidService = {}

local CONFIG = GameConfig.Raid
local HALF_D = 22 -- vault depth / 2 (MapService)

type GateState = {
	Base: MapService.BaseSite,
	LastHit: number,
	LastAlert: number,
	BrokenUntil: number,
	RepairReadyAt: { [Player]: number },
	RemoveTarget: (() -> ())?,
}

type Burglar = {
	Model: Model,
	Root: BasePart,
	Name: string,
	Position: Vector3,
	Health: number,
	Dead: boolean,
	State: string, -- "ToGate" | "Bash" | "Enter" | "Steal" | "Escape" | "Taunt"
	Base: MapService.BaseSite?,
	Slot: number?,
	GateLane: number,
	Carrying: string?, -- item
	CarryOwner: number?,
	CarryVisual: Model?,
	Waypoints: { Vector3 },
	NextAction: number,
	StunnedUntil: number,
	Tracks: { [string]: AnimationTrack },
	Playing: string?,
	HealthFill: Frame,
	RemoveTarget: () -> (),
}

local gates: { [MapService.BaseSite]: GateState } = {}
-- Knives taken from each vault this raid, capped by BurglarStealsPerVault.
local takenFrom: { [MapService.BaseSite]: number } = {}
local burglars: { Burglar } = {}
local burglarFolder: Folder
local raiding = false
local raidEndsAt = 0
local raidGeneration = 0
local rng = Random.new()

local BURGLAR_NAMES = {
	"Sneaky Pete",
	"Slim Jim",
	"Burglar Bill",
	"Light-Fingers Lou",
	"Pockets",
	"The Weasel",
	"Quick Nick",
	"Shady Sal",
}
local ANIMATIONS: { [string]: string } = {
	Idle = "rbxassetid://507766388",
	Walk = "rbxassetid://507777826",
	Run = "rbxassetid://507767714",
}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function RaidService.IsRaiding(): boolean
	return raiding
end

-- Revenge: `player` may enter and rob `owner`'s vault right now
local function hasRevenge(player: Player, owner: Player): boolean
	local until_ = player:GetAttribute("RevengeUntil")
	return player:GetAttribute("RevengeOn") == owner.UserId and type(until_) == "number" and now() < until_
end

local function gateOpen(base: MapService.BaseSite): boolean
	return base.Blocker:GetAttribute("Open") == true
end

-- Why this vault's gate can't be attacked right now (nil = it can)
local function protectedReason(base: MapService.BaseSite, beforeRaid: boolean?): string?
	local owner = BaseService.OwnerOf(base)
	if not owner then
		return "Nobody lives here - nothing to steal"
	end
	if DataService.IsNewPlayer(owner) then
		local profile = DataService.Get(owner)
		local left = if profile then math.ceil((GameConfig.NewPlayerShield - profile.PlayTime) / 60) else 0
		return `🛡️ {owner.DisplayName} is new - protected for {math.max(1, left)} more min`
	end
	if owner:GetAttribute("InRound") then
		return `{owner.DisplayName} is in a round - come back after it`
	end
	if ReplicatedStorage:GetAttribute("Phase") ~= "Intermission" then
		return "Vaults are sealed during a round"
	end
	local sealed = owner:GetAttribute("SealedUntil")
	if not beforeRaid and type(sealed) == "number" and now() < sealed then
		return `🔒 {owner.DisplayName} was just robbed - sealed for {math.ceil(sealed - now())}s`
	end
	return nil
end

local function canBreak(base: MapService.BaseSite): boolean
	return protectedReason(base) == nil
end

-- Hitting a gate that's protected tells you why (not every swing)
local toldAt: { [Player]: number } = {}
local function tellProtected(attacker: Player, base: MapService.BaseSite, reason: string)
	local t = os.clock()
	if t - (toldAt[attacker] or 0) > 2.5 then
		toldAt[attacker] = t
		Net.Notify(attacker, reason, "info")
	end
	Net.Remotes.Effect:FireClient(attacker, "Shield", base.Blocker.Position)
end

-- Whether `player` may be inside `base` (owned by `owner`) right now
local function mayEnter(player: Player, base: MapService.BaseSite, owner: Player?): boolean
	if not owner or owner == player then
		return true
	end
	return canBreak(base) and (gateOpen(base) or hasRevenge(player, owner))
end

-- Who hub knives (and home traps, Flash, Radar) can go after: intruders in someone else's vault
-- and anyone carrying loot, any time; during the Thief Moon anyone who isn't home
function RaidService.CanAttackPlayer(attacker: Player, victim: Player): boolean
	if
		ReplicatedStorage:GetAttribute("Phase") ~= "Intermission"
		or attacker == victim
		or attacker:GetAttribute("InRound")
		or victim:GetAttribute("InRound")
		or DataService.IsNewPlayer(victim)
		or rootOf(attacker) == nil
	then
		return false
	end
	local root = rootOf(victim)
	if not root then
		return false
	end
	local _, vaultOwner = BaseService.BaseAt(root.Position)
	if vaultOwner == victim then
		return false -- safe at home
	end
	-- Hit my gate? Then you're fair game for me, anywhere in the hub, for a while
	if RaidService.IsMarkedBy(victim, attacker) then
		return true
	end
	return raiding or (vaultOwner ~= nil and vaultOwner ~= victim) or victim:GetAttribute("Carrying") ~= nil
end

-- Raiders: hitting someone's gate marks you as theirs to hunt (RaiderOf / RaiderUntil). Like the
-- watchmen, the owner's knife does real damage to you - a starter knife takes a few hits, a great
-- knife one-shots - and your Health level is what keeps you standing.
function RaidService.IsMarkedBy(raider: Player, owner: Player): boolean
	local until_ = raider:GetAttribute("RaiderUntil")
	return raider:GetAttribute("RaiderOf") == owner.UserId and type(until_) == "number" and now() < until_
end

local function markRaider(raider: Player, owner: Player)
	local fresh = not RaidService.IsMarkedBy(raider, owner)
	raider:SetAttribute("RaiderOf", owner.UserId)
	raider:SetAttribute("RaiderUntil", now() + CONFIG.RaiderMarkTime)
	if fresh then
		Net.Notify(raider, `You're raiding {owner.DisplayName}! They can fight back now - watch your health.`, "bad")
		Net.Notify(owner, `{raider.DisplayName} is raiding you! Your knife hurts them now - take them out!`, "bad")
	end
end

-- Gates ------------------------------------------------------------------------------------

local function refreshGateBar(base: MapService.BaseSite)
	local blocker = base.Blocker
	local gui = blocker:FindFirstChild("GateHealth") :: BillboardGui?
	if not gui then
		return
	end
	local health = (blocker:GetAttribute("Health") or 0) :: number
	local max = (blocker:GetAttribute("MaxHealth") or 1) :: number
	local owner = BaseService.OwnerOf(base)
	local shielded = owner ~= nil and DataService.IsNewPlayer(owner)
	gui.Enabled = owner ~= nil and (raiding or shielded or gateOpen(base) or health < max - 0.5)
	local fill = gui:FindFirstChild("Fill", true) :: Frame?
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(health / max, 0, 1), 1)
	end
	local title = gui:FindFirstChild("Title") :: TextLabel?
	if title then
		title.Text = if gateOpen(base)
			then "BROKEN!"
			elseif shielded then `🛡️ {(owner :: Player).DisplayName} (new player)`
			else `{if owner then owner.DisplayName .. "'s " else ""}{GameConfig.Walls[(blocker:GetAttribute("Tier") or 1) :: number].Name}`
	end
end

local function breakGate(base: MapService.BaseSite, by: string)
	local state = gates[base]
	VaultWalls.SetOpen(base.Gate, true)
	base.Blocker:SetAttribute("Health", 0)
	state.BrokenUntil = now() + CONFIG.BrokenTime
	refreshGateBar(base)
	Net.Remotes.Effect:FireAllClients("GateBreak", base.Blocker.Position, base.Color)
	local owner = BaseService.OwnerOf(base)
	if owner then
		Net.Announce(`{by} broke into {owner.DisplayName}'s vault!`, Color3.fromRGB(255, 80, 70), 2)
		Net.Notify(owner, "YOUR GATE IS DOWN! Defend your knives!", "bad")
		Net.Remotes.Effect:FireClient(owner, "Alarm")
	end
end

local function damageGate(base: MapService.BaseSite, amount: number, by: string, attacker: Model?)
	if gateOpen(base) or not canBreak(base) then
		return
	end
	if raiding then
		amount *= CONFIG.BloodMoonGateDamage
	end
	local state = gates[base]
	local before = (base.Blocker:GetAttribute("Health") or 0) :: number
	local max = (base.Blocker:GetAttribute("MaxHealth") or 1) :: number
	local health = before - amount
	state.LastHit = now()
	local owner = BaseService.OwnerOf(base)
	local raider = attacker and Players:GetPlayerFromCharacter(attacker)
	if raider and owner and raider ~= owner then
		markRaider(raider, owner)
	end
	-- Someone just started on it: tell the owner straight away (not every hit)
	if owner and now() - state.LastAlert > 12 then
		state.LastAlert = now()
		Net.Notify(owner, `{by} is breaking into your vault! Get back and stop them!`, "bad")
		Net.Remotes.Effect:FireClient(owner, "Alarm")
		-- ...and who: outlined through walls for a while, so you can find them on the way home
		if attacker then
			Net.Remotes.Effect:FireClient(owner, "Radar", {
				{ Model = attacker, Color = Color3.fromRGB(255, 70, 60) },
			}, 8)
		end
	end
	-- Warn the owner as it goes down
	for _, mark in { 0.75, 0.5, 0.25 } do
		if owner and before > max * mark and health <= max * mark and health > 0 then
			Net.Notify(owner, `Your gate is at {math.floor(mark * 100)}%! {by} is breaking in!`, "bad")
			Net.Remotes.Effect:FireClient(owner, "Alarm")
			if mark == 0.5 then
				Offers.Show(owner, "Repair", `{by} is breaking in! Fix your gate instantly, wherever you are.`)
			end
		end
	end
	base.Blocker:SetAttribute("Health", math.max(0, health))
	Net.Remotes.Effect:FireAllClients("GateHit", base.Blocker.Position, amount)
	if health <= 0 then
		breakGate(base, by)
	else
		refreshGateBar(base)
	end
end

local function reforge(base: MapService.BaseSite, fraction: number)
	local max = (base.Blocker:GetAttribute("MaxHealth") or 1) :: number
	VaultWalls.SetOpen(base.Gate, false)
	base.Blocker:SetAttribute("Health", max * fraction)
	gates[base].BrokenUntil = 0
	refreshGateBar(base)
	Net.Remotes.Effect:FireAllClients("GateReforge", base.Blocker.Position, base.Color)
end

-- (Re)register a vault's gate as something knives can hit; called whenever its walls are rebuilt
local function trackGate(base: MapService.BaseSite)
	local state = gates[base]
	if not state then
		state = { Base = base, LastHit = 0, LastAlert = 0, BrokenUntil = 0, RepairReadyAt = {}, RemoveTarget = nil }
		gates[base] = state
	end
	if state.RemoveTarget then
		state.RemoveTarget()
	end
	state.BrokenUntil = 0
	state.RemoveTarget = Targets.Add({
		Part = base.Blocker,
		Model = base.Gate,
		Solid = true,
		CanHit = function(attacker: Player)
			-- Never your own gate. Empty vaults still take the swing, so the attacker hears why
			-- nothing happens.
			return BaseService.OwnerOf(base) ~= attacker and not attacker:GetAttribute("InRound") and not gateOpen(base)
		end,
		Hit = function(attacker: Player, damage: number, kind: string)
			if BaseService.OwnerOf(base) == attacker then
				return -- belt and braces: whatever path the hit came by
			end
			local reason = protectedReason(base)
			if reason then
				tellProtected(attacker, base, reason)
				return
			end
			damageGate(
				base,
				(if kind == "Throw" then damage * CONFIG.ThrowGateMultiplier else damage) * CONFIG.PlayerGateDamage,
				attacker.DisplayName,
				attacker.Character
			)
		end,
	})
	refreshGateBar(base)
end

local function onRepair(player: Player)
	local base = BaseService.GetBase(player)
	local root = rootOf(player)
	if not base or not root or gateOpen(base) then
		return
	end
	local state = gates[base]
	local t = now()
	if t < (state.RepairReadyAt[player] or 0) then
		return
	end
	if (root.Position - base.Blocker.Position).Magnitude > 16 then
		return
	end
	state.RepairReadyAt[player] = t + CONFIG.RepairCooldown
	local max = (base.Blocker:GetAttribute("MaxHealth") or 1) :: number
	local health = (base.Blocker:GetAttribute("Health") or 0) :: number
	base.Blocker:SetAttribute("Health", math.min(max, health + max * CONFIG.RepairAmount))
	refreshGateBar(base)
	Net.Remotes.Effect:FireAllClients("GateRepair", base.Blocker.Position, base.Color)
end

-- Instant Repair (Robux): the gate back to full, or rebuilt at full if it was broken
function RaidService.RepairFull(player: Player)
	local base = BaseService.GetBase(player)
	if not base then
		return
	end
	if gateOpen(base) then
		reforge(base, 1)
	else
		base.Blocker:SetAttribute("Health", base.Blocker:GetAttribute("MaxHealth"))
		refreshGateBar(base)
	end
	Net.Remotes.Effect:FireAllClients("GateRepair", base.Blocker.Position, base.Color)
end

-- Knockdowns -------------------------------------------------------------------------------

function RaidService.Knockdown(victim: Player, from: Vector3, by: string): boolean
	local character = victim.Character
	local root = rootOf(victim)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if
		ReplicatedStorage:GetAttribute("Phase") ~= "Intermission"
		or DataService.IsNewPlayer(victim)
		or not character
		or not root
		or not humanoid
		or victim:GetAttribute("InRound")
	then
		return false
	end
	local t = now()
	local knocked = victim:GetAttribute("KnockedUntil")
	local immune = victim:GetAttribute("KnockImmuneUntil")
	if (type(knocked) == "number" and t < knocked) or (type(immune) == "number" and t < immune) then
		return false
	end
	-- A Shield eats it
	local shieldUntil = character:GetAttribute("ShieldUntil")
	if type(shieldUntil) == "number" and t < shieldUntil then
		character:SetAttribute("ShieldUntil", nil)
		Net.Remotes.Effect:FireAllClients("Shield", root.Position)
		return false
	end
	StealService.ForceDrop(victim)
	local until_ = t + CONFIG.KnockdownTime
	victim:SetAttribute("KnockedUntil", until_)
	victim:SetAttribute("StunnedUntil", until_)
	BaseService.RefreshWalkSpeed(victim)
	humanoid.JumpHeight = 0
	-- Shoved back a little, then down
	local away = (root.Position - from) * Vector3.new(1, 0, 1)
	if away.Magnitude > 0.1 then
		root.AssemblyLinearVelocity = away.Unit * 30 + Vector3.new(0, 18, 0)
	end
	Net.Animate(character, "Knockdown")
	Net.Remotes.Effect:FireAllClients("Knockdown", root.Position)
	Net.Notify(victim, `{by} knocked you down!`, "bad")
	task.delay(CONFIG.KnockdownTime, function()
		if victim:GetAttribute("KnockedUntil") == until_ then
			victim:SetAttribute("KnockedUntil", nil)
			victim:SetAttribute("KnockImmuneUntil", now() + CONFIG.KnockImmunity)
			BaseService.RefreshWalkSpeed(victim)
			if humanoid.Parent then
				humanoid.JumpHeight = 7.2
			end
		end
	end)
	return true
end

-- Players as targets for hub knives during the raid window.
local function playerTargets(): { Targets.Target }
	local list: { Targets.Target } = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if not root or player:GetAttribute("InRound") then
			continue
		end
		local character = player.Character :: Model
		local target: Targets.Target = {
			Part = root,
			Model = character,
			Solid = false,
			CanHit = function(attacker: Player)
				if not RaidService.CanAttackPlayer(attacker, player) then
					return false
				end
				if player:GetAttribute("Invisible") or player:GetAttribute("Mimic") then
					return false
				end
				return true
			end,
			Hit = function(attacker: Player, damage: number, _kind: string, from: Vector3)
				-- The vault's owner vs someone raiding them (marked at the gate, inside the vault, or
				-- running off with the owner's knife): real damage, like a watchman
				local _, vaultOwner = BaseService.BaseAt(root.Position)
				local caught = vaultOwner == attacker
					or player:GetAttribute("StolenFrom") == attacker.UserId
					or RaidService.IsMarkedBy(player, attacker)
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if caught and humanoid and humanoid.Health > 0 and not DataService.IsNewPlayer(player) then
					-- A Shield eats one hit
					local shieldUntil = character:GetAttribute("ShieldUntil")
					if type(shieldUntil) == "number" and now() < shieldUntil then
						character:SetAttribute("ShieldUntil", nil)
						Net.Remotes.Effect:FireAllClients("Shield", root.Position)
						return
					end
					local lethal = damage >= humanoid.Health
					-- The owner snatches their knife back before the thief's body hits the floor
					local recovered = if lethal then StealService.Recover(player, attacker) else nil
					humanoid:TakeDamage(damage)
					Net.Remotes.Effect:FireAllClients("Hit", root.Position)
					Net.Remotes.Effect:FireClient(player, "Hurt", from)
					Net.Remotes.Effect:FireClient(attacker, "Damage", root.Position + Vector3.new(0, 3, 0), damage)
					if humanoid.Health > 0 then
						Net.Animate(character, "Hurt")
						return
					end
					player:SetAttribute("RaiderOf", nil)
					player:SetAttribute("RaiderUntil", nil)
					local bonus = if raiding then CONFIG.BloodMoonBounty else 1
					local bounty = if recovered
						then GameConfig.Pay(CONFIG.CatchBounty, Items.Income(recovered)) * bonus
						else GameConfig.Pay(CONFIG.IntruderBounty, BaseService.RackIncome(attacker)) * bonus
					DataService.AddCash(attacker, bounty)
					Net.Remotes.Effect:FireClient(attacker, "CashBurst", root.Position, bounty)
					if recovered then
						Net.Notify(
							attacker,
							`Got your {Items.DisplayName(recovered)} back! Bounty +{Format.Cash(bounty)}`,
							"good"
						)
					else
						Net.Notify(attacker, `Raider down! Bounty +{Format.Cash(bounty)}`, "good")
					end
					Net.Notify(player, `{attacker.DisplayName} took you down defending their vault!`, "bad")
					return
				end
				if not RaidService.Knockdown(player, from, attacker.DisplayName) then
					return
				end
				Net.Remotes.Effect:FireClient(attacker, "Damage", root.Position + Vector3.new(0, 3, 0), "KO!")
			end,
		}
		table.insert(list, target)
	end
	return list
end

-- Stealing from walls ----------------------------------------------------------------------

local function onStealPrompt(thief: Player, owner: Player, slot: number)
	local base = BaseService.GetBase(owner)
	local profile = DataService.Get(owner)
	local thiefProfile = DataService.Get(thief)
	local root = rootOf(thief)
	if not base or not profile or not thiefProfile or not root then
		return
	end
	if thief:GetAttribute("InRound") or StealService.IsCarrying(thief) or thief:GetAttribute("KnockedUntil") then
		return
	end
	if ReplicatedStorage:GetAttribute("Phase") ~= "Intermission" then
		return
	end
	local sealed = owner:GetAttribute("SealedUntil")
	if type(sealed) == "number" and now() < sealed then
		Net.Notify(thief, `{owner.DisplayName} was just robbed - leave them be for a bit`, "info")
		return
	end
	local revenge = hasRevenge(thief, owner)
	if not (gateOpen(base) or revenge) or DataService.IsNewPlayer(owner) or owner:GetAttribute("InRound") then
		return
	end
	if not MapService.InBounds(base.Bounds, root.Position) then
		return
	end
	if not BaseService.GetBase(thief) then
		return
	end
	if #thiefProfile.Knives >= thiefProfile.Slots then
		Net.Notify(thief, "Your own wall is full - nowhere to put it!", "bad")
		return
	end
	local item = profile.Knives[slot]
	if not item or item == BaseService.ProtectedItem(owner) then
		return
	end
	local spot = base.SlotCFrames[DataService.PlateOf(profile, slot)]
	if not spot or (root.Position - spot.Position).Magnitude > 14 then
		return
	end
	DataService.Update(owner, function(p)
		DataService.RemoveKnife(p, slot)
	end)
	BaseService.RefreshRack(owner)
	StealService.StartCarry(thief, "Knife", item, owner.UserId)
	-- The victim gets revenge on the thief (and it ends the thief's own revenge on them)
	owner:SetAttribute("RevengeOn", thief.UserId)
	local revengeEndsAt = now() + CONFIG.RevengeTime
	owner:SetAttribute("RevengeUntil", revengeEndsAt)
	-- Nobody else gets to clean them out: the vault seals for a while
	owner:SetAttribute("SealedUntil", now() + CONFIG.RobbedSeal)
	task.delay(4, function()
		Offers.Show(owner, "Fortified", "Robbed! A Fortified Vault gives your gate +50% health for good.")
	end)
	if revenge then
		thief:SetAttribute("RevengeOn", nil)
		thief:SetAttribute("RevengeUntil", nil)
	end
	Net.Notify(owner, `{thief.DisplayName} is stealing your {Items.DisplayName(item)}! Knock them down!`, "bad")
	Net.Notify(
		owner,
		`REVENGE: {thief.DisplayName}'s vault is open to you for {math.ceil(revengeEndsAt - now())}s!`,
		"info"
	)
	Net.Remotes.Effect:FireClient(owner, "Alarm")
	Net.Remotes.Effect:FireAllClients("Stolen", root.Position, Items.Color(item))
end

-- Intruders: nobody stands in a sealed vault that isn't theirs (exploiters, or a gate that
-- reforged around someone) - they get put back outside the gate
local function evictIntruders()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if not root or player:GetAttribute("InRound") then
			continue
		end
		local base, owner = BaseService.BaseAt(root.Position)
		if base and owner and not mayEnter(player, base, owner) then
			local outside = base.Frame * CFrame.new(0, 3, HALF_D + 5);
			(player.Character :: Model):PivotTo(
				CFrame.lookAt(outside.Position, outside.Position + base.Frame.LookVector)
			)
			Net.Notify(player, "That vault is sealed!", "bad")
		end
	end
end

-- Knife auras ------------------------------------------------------------------------------

function RaidService.AuraPower(item: string): number
	return Items.AuraPower(item)
end

-- Anyone who isn't the owner gets slowed near powerful mounted knives
local function stepAuras()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local slow, from = 1, nil :: string?
		if root and not player:GetAttribute("InRound") then
			local base, owner = BaseService.BaseAt(root.Position)
			local profile = owner and DataService.Get(owner)
			if base and owner and owner ~= player and profile then
				for slot, item in profile.Knives do
					local cf = base.SlotCFrames[DataService.PlateOf(profile, slot)]
					local power = RaidService.AuraPower(item)
					if cf and power > 0.5 then
						local radius = Items.AuraRadius(power)
						local distance = (cf.Position - root.Position).Magnitude
						if distance < radius then
							local strength = 1 - math.clamp(power / 12, 0, 0.6) * (1 - distance / radius)
							if strength < slow then
								slow = strength
								from = `{owner.DisplayName}'s {Items.DisplayName(item)}`
							end
						end
					end
				end
			end
		end
		local old = player:GetAttribute("AuraSlow")
		local value = if slow < 0.99 then math.floor(slow * 100) / 100 else nil
		if old ~= value then
			player:SetAttribute("AuraSlow", value)
			player:SetAttribute("AuraFrom", from)
			BaseService.RefreshWalkSpeed(player)
		end
	end
end

-- Burglars ---------------------------------------------------------------------------------

local function loadTracks(rig: Model): { [string]: AnimationTrack }
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	local animator = humanoid:FindFirstChildOfClass("Animator") :: Animator?
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local tracks: { [string]: AnimationTrack } = {}
	for key, id in ANIMATIONS do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall((animator :: Animator).LoadAnimation, animator :: Animator, animation)
		if ok then
			track.Looped = true
			tracks[key] = track
		end
	end
	return tracks
end

local function animate(b: Burglar, key: string, speed: number?)
	local track = b.Tracks[key]
	if b.Playing ~= key then
		local old = b.Playing and b.Tracks[b.Playing]
		if old then
			old:Stop(0.2)
		end
		if track then
			track:Play(0.2)
		end
		b.Playing = key
	end
	if track and speed then
		track:AdjustSpeed(speed)
	end
end

local function attachProp(prop: Model, to: BasePart, offset: CFrame, parent: Instance)
	prop:PivotTo(to.CFrame * offset)
	for _, d in prop:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = to
	weld.Part1 = prop.PrimaryPart :: BasePart
	weld.Parent = prop
	prop.Parent = parent
end

local function buildBurglar(name: string): Model
	local description = Instance.new("HumanoidDescription")
	local black = Color3.fromRGB(26, 24, 30)
	description.HeadColor = Color3.fromRGB(234, 184, 146)
	description.TorsoColor = Color3.fromRGB(230, 230, 235) -- the classic striped jumper (stripes below)
	description.LeftArmColor = black
	description.RightArmColor = black
	description.LeftLegColor = black
	description.RightLegColor = black
	local rig = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	rig.Name = name
	rig.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- streams in whole, never half a body
	rig:AddTag("Burglar")
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = name
	humanoid.NameDisplayDistance = 90
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.EvaluateStateMachine = false
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	rig.PrimaryPart = root
	-- Stripes across the jumper
	local torso = rig:FindFirstChild("UpperTorso") :: BasePart?
	if torso then
		for i = -1, 1 do
			local stripe = Instance.new("Part")
			stripe.Name = "Stripe"
			stripe.Size = Vector3.new(torso.Size.X + 0.04, 0.28, torso.Size.Z + 0.04)
			stripe.Color = black
			stripe.Material = Enum.Material.Fabric
			stripe.CanCollide = false
			stripe.CanQuery = false
			stripe.CanTouch = false
			stripe.Massless = true
			stripe.CFrame = torso.CFrame * CFrame.new(0, i * 0.5, 0)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = torso
			weld.Part1 = stripe
			weld.Parent = stripe
			stripe.Parent = rig
		end
		attachProp(Props.Build("LootSack"), torso, CFrame.new(0, -0.3, torso.Size.Z / 2 + 0.9), rig)
	end
	local head = rig:FindFirstChild("Head") :: BasePart?
	if head then
		Disguises.AddHat(head, "Beanie", black)
		attachProp(Props.Build("BurglarMask"), head, CFrame.new(0, 0.1, -head.Size.Z / 2 - 0.02), rig)
	end
	return rig
end

local function healthBar(head: BasePart): Frame
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(90, 10)
	gui.StudsOffset = Vector3.new(0, 2.8, 0)
	gui.MaxDistance = 100
	gui.Adornee = head
	gui.Parent = head
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(30, 10, 10)
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 170, 50)
	fill.BorderSizePixel = 0
	fill.Parent = back
	return fill
end

local function dropLoot(b: Burglar)
	if b.CarryVisual then
		b.CarryVisual:Destroy()
		b.CarryVisual = nil
	end
	if b.Carrying then
		StealService.DropKnife(b.Carrying, b.Position, b.CarryOwner)
		b.Carrying = nil
	end
end

local killBurglar: (Burglar, Player?) -> ()

local function hitBurglar(b: Burglar, damage: number, attacker: Player?, from: Vector3?)
	if b.Dead then
		return
	end
	b.Health -= damage
	b.HealthFill.Size = UDim2.fromScale(math.max(0, b.Health / CONFIG.BurglarHealth), 1)
	Net.Remotes.Effect:FireAllClients("Hit", b.Position + Vector3.new(0, 1.5, 0))
	if attacker then
		Net.Remotes.Effect:FireClient(attacker, "Damage", b.Position + Vector3.new(0, 3, 0), damage)
	end
	if b.Health <= 0 then
		killBurglar(b, attacker)
		return
	end
	Net.Animate(b.Model, "GuardHurt")
	b.NextAction = math.max(b.NextAction, os.clock() + 0.25)
	-- Knocked back a step
	if from then
		local away = (b.Position - from) * Vector3.new(1, 0, 1)
		if away.Magnitude > 0.1 then
			b.Position += away.Unit * 1.5
		end
	end
end

killBurglar = function(b: Burglar, killer: Player?)
	if b.Dead then
		return
	end
	b.Dead = true
	b.RemoveTarget()
	for _, track in b.Tracks do
		track:Stop(0.1)
	end
	dropLoot(b)
	for _, d in b.Model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	Ragdoll.DeathCry(b.Model)
	Ragdoll.Collapse(b.Model, Vector3.new(0, 6, 0))
	pcall(b.Root.SetNetworkOwner, b.Root, nil)
	game:GetService("Debris"):AddItem(b.Model, 5)
	if killer then
		local bounty = GameConfig.Pay(CONFIG.BurglarReward, BaseService.RackIncome(killer)) * CONFIG.BloodMoonBounty
		DataService.AddCash(killer, bounty)
		Net.Notify(killer, `You stopped {b.Name}! Bounty +{Format.Cash(bounty)}`, "good")
	end
end

-- Escape route: out of the vault, across the plaza and down the runway into the dark
local function exitPath(base: MapService.BaseSite?): { Vector3 }
	local height = GuardService.RootHeight()
	local path = {}
	if base then
		table.insert(path, (base.Frame * CFrame.new(0, 0, 10)).Position)
		table.insert(path, (base.Frame * CFrame.new(0, 0, HALF_D + 6)).Position)
	end
	table.insert(path, Vector3.new(rng:NextNumber(-10, 10), 0, 30))
	table.insert(path, Vector3.new(rng:NextNumber(-20, 20), 0, 160))
	for i, p in path do
		path[i] = Vector3.new(p.X, height, p.Z)
	end
	return path
end

-- Count current assignments, so dead and escaping burglars immediately free up a gate.
local function assignedTo(base: MapService.BaseSite): number
	local count = 0
	for _, b in burglars do
		if not b.Dead and b.Base == base and b.State ~= "Escape" then
			count += 1
		end
	end
	return count
end

local function stealableSlot(base: MapService.BaseSite): number?
	local owner = BaseService.OwnerOf(base)
	local profile = owner and DataService.Get(owner)
	if not owner or not profile or not canBreak(base) or (takenFrom[base] or 0) >= CONFIG.BurglarStealsPerVault then
		return nil
	end
	local protected = BaseService.ProtectedItem(owner)
	for slot, item in profile.Knives do
		-- Burglars walk the ground floor only
		local plate = DataService.PlateOf(profile, slot)
		if plate <= profile.Slots and plate <= MapService.SlotsPerFloor and item ~= protected then
			return slot
		end
	end
	return nil
end

-- Picks a vault to hit: any owned, breakable one that hasn't got BurglarsPerGate of them at its
-- gate already. Ones with a stealable knife (and loot left this raid) come with a slot to rob;
-- the rest still get their gate smashed.
local function pickTarget(except: MapService.BaseSite?): (MapService.BaseSite?, number?)
	local options: { { Base: MapService.BaseSite, Slot: number? } } = {}
	for _, base in MapService.Bases do
		local owner = BaseService.OwnerOf(base)
		local profile = owner and DataService.Get(owner)
		if owner and profile and canBreak(base) and base ~= except then
			if assignedTo(base) >= CONFIG.BurglarsPerGate then
				continue
			end
			local protected = BaseService.ProtectedItem(owner)
			local any = false
			if (takenFrom[base] or 0) < CONFIG.BurglarStealsPerVault then
				for slot, item in profile.Knives do
					if item ~= protected and slot <= profile.Slots and slot <= MapService.SlotsPerFloor then
						table.insert(options, { Base = base, Slot = slot })
						any = true
					end
				end
			end
			-- Nothing worth taking? They'll still smash the gate and rummage around
			if not any then
				table.insert(options, { Base = base, Slot = nil })
			end
		end
	end
	if #options == 0 then
		return nil, nil
	end
	local pick = options[rng:NextInteger(1, #options)]
	return pick.Base, pick.Slot
end

-- Where a burglar stands to hack at a vault's gate
local function gateFront(base: MapService.BaseSite, burglar: Burglar): Vector3
	local occupied: { [number]: boolean } = {}
	for _, other in burglars do
		if other ~= burglar and not other.Dead and other.Base == base and other.State ~= "Escape" then
			occupied[other.GateLane] = true
		end
	end
	for lane = 1, CONFIG.BurglarsPerGate do
		if not occupied[lane] then
			burglar.GateLane = lane
			break
		end
	end
	local offset = if CONFIG.BurglarsPerGate > 1
		then -9 + 18 * (burglar.GateLane - 1) / (CONFIG.BurglarsPerGate - 1)
		else 0
	local front = (base.Frame * CFrame.new(offset, 0, HALF_D + 5)).Position
	return Vector3.new(front.X, GuardService.RootHeight(), front.Z)
end

local function spawnBurglar(generation: number)
	local name = BURGLAR_NAMES[rng:NextInteger(1, #BURGLAR_NAMES)]
	local model = buildBurglar(name)
	if not raiding or generation ~= raidGeneration then
		model:Destroy()
		return
	end
	local height = GuardService.RootHeight()
	local start = Vector3.new(rng:NextNumber(-25, 25), height, rng:NextNumber(150, 200))
	model:PivotTo(CFrame.new(start))
	local head = model:FindFirstChild("Head") :: BasePart
	local fill = healthBar(head)
	model.Parent = burglarFolder
	local b: Burglar
	b = {
		Model = model,
		Root = model.PrimaryPart :: BasePart,
		Name = name,
		Position = start,
		Health = CONFIG.BurglarHealth,
		Dead = false,
		State = "ToGate",
		Base = nil,
		Slot = nil,
		GateLane = 0,
		Carrying = nil,
		CarryOwner = nil,
		CarryVisual = nil,
		Waypoints = {},
		NextAction = 0,
		StunnedUntil = 0,
		Tracks = loadTracks(model),
		Playing = nil,
		HealthFill = fill,
		RemoveTarget = function() end,
	}
	b.RemoveTarget = Targets.Add({
		Part = b.Root,
		Model = model,
		Solid = false,
		CanHit = function()
			return not b.Dead
		end,
		Hit = function(attacker: Player, damage: number, _kind: string, from: Vector3)
			hitBurglar(b, damage, attacker, from)
		end,
	})
	b.Base, b.Slot = pickTarget()
	if b.Base then
		b.Waypoints = { Vector3.new(rng:NextNumber(-9, 9), height, 20), gateFront(b.Base, b) }
	else
		b.State = "Taunt"
		b.Waypoints = { Vector3.new(rng:NextNumber(-20, 20), height, rng:NextNumber(-140, -20)) }
	end
	table.insert(burglars, b)
	Net.Remotes.Effect:FireAllClients("BurglarSpawn", start)
end

-- Moves a burglar toward its next waypoint; returns true once there are none left
local function walk(b: Burglar, dt: number, speed: number): boolean
	local target = b.Waypoints[1]
	if not target then
		return true
	end
	local offset = target - b.Position
	local distance = offset.Magnitude
	if distance < 1 then
		table.remove(b.Waypoints, 1)
		return #b.Waypoints == 0
	end
	local nextPos = b.Position + offset.Unit * math.min(distance, speed * dt)
	-- Barricades stop burglars too; they smash through
	local obstacle = Obstacles.Blocks(b.Position, nextPos, 1.5)
	if obstacle then
		animate(b, "Idle")
		if os.clock() >= b.NextAction then
			b.NextAction = os.clock() + 1
			Net.Animate(b.Model, "GuardStab")
			obstacle.Hit("Burglar")
		end
		return false
	end
	b.Position = nextPos
	b.Model:PivotTo(CFrame.lookAt(nextPos, nextPos + Vector3.new(offset.X, 0, offset.Z)))
	animate(b, "Run", speed / 16)
	return false
end

local function stepBurglar(b: Burglar, dt: number)
	if b.Dead then
		return
	end
	local clock = os.clock()
	if raiding then
		local stun = PowerService.SpringRaidTrap(b.Position)
		if stun then
			b.StunnedUntil = now() + stun
		end
	end
	if not raiding and b.State ~= "Escape" then
		local inside = b.State == "Enter" or b.State == "Steal"
		b.Waypoints = exitPath(if inside then b.Base else nil)
		b.State = "Escape"
		b.NextAction = 0
	end
	if b.Base and b.State ~= "Escape" and not canBreak(b.Base) then
		local inside = b.State == "Enter" or b.State == "Steal"
		b.Waypoints = exitPath(if inside then b.Base else nil)
		b.State = "Escape"
		b.NextAction = 0
	end
	if now() < b.StunnedUntil or clock < b.NextAction then
		animate(b, "Idle")
		return
	end
	-- Shove anyone standing right in front of it
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if
			root
			and (root.Position - b.Position).Magnitude < 3.5
			and not BaseService.IsInOwnBase(player, b.Position)
		then
			if math.random() < 0.02 then
				Net.Animate(b.Model, "GuardStab")
				RaidService.Knockdown(player, b.Position, b.Name)
			end
		end
	end

	local base = b.Base
	if b.State == "ToGate" or b.State == "Taunt" then
		if walk(b, dt, CONFIG.BurglarSpeed) then
			if b.State == "Taunt" then
				-- Nothing to rob right now: look again, otherwise dart somewhere else on the plaza
				local nextBase, nextSlot = pickTarget()
				if nextBase then
					b.Base, b.Slot = nextBase, nextSlot
					b.State = "ToGate"
					b.Waypoints = { gateFront(nextBase, b) }
				else
					b.Waypoints =
						{ Vector3.new(rng:NextNumber(-20, 20), GuardService.RootHeight(), rng:NextNumber(-140, -20)) }
				end
			else
				b.State = "Bash"
			end
		end
	elseif b.State == "Bash" and base then
		if not raiding then
			b.State = "Escape"
			b.Waypoints = exitPath(nil)
		elseif gateOpen(base) or not BaseService.OwnerOf(base) then
			b.State = "Enter"
			b.Slot = stealableSlot(base)
			local robbed = BaseService.OwnerOf(base)
			local robbedProfile = robbed and DataService.Get(robbed)
			local slotCF = if b.Slot and robbedProfile
				then base.SlotCFrames[DataService.PlateOf(robbedProfile, b.Slot)]
				else nil
			local height = GuardService.RootHeight()
			local inside = (base.Frame * CFrame.new(0, 0, 10)).Position
			b.Waypoints = { Vector3.new(inside.X, height, inside.Z) }
			if slotCF then
				local reach = (slotCF * CFrame.new(0, 0, 3)).Position
				table.insert(b.Waypoints, Vector3.new(reach.X, height, reach.Z))
			end
		else
			-- Hack at the gate
			local blocker = base.Blocker
			b.Model:PivotTo(
				CFrame.lookAt(b.Position, Vector3.new(blocker.Position.X, b.Position.Y, blocker.Position.Z))
			)
			animate(b, "Idle")
			b.NextAction = clock + CONFIG.BurglarSwing
			Net.Animate(b.Model, "GuardStab")
			task.delay(AnimLibrary.Clips.GuardStab.Impact or 0.3, function()
				if not b.Dead and raiding and b.State == "Bash" and now() >= b.StunnedUntil then
					-- Burglars come prepared: tougher gates take bigger crowbars
					local max = (base.Blocker:GetAttribute("MaxHealth") or 0) :: number
					local _ = max
					damageGate(base, CONFIG.BurglarGateDamage, b.Name, b.Model)
				end
			end)
		end
	elseif b.State == "Enter" and base then
		if walk(b, dt, CONFIG.BurglarSpeed) then
			b.State = "Steal"
			b.NextAction = clock + CONFIG.StealTime
			Net.Animate(b.Model, "Pickup")
		end
	elseif b.State == "Steal" and base then
		-- Lift the knife (if it's still there)
		b.Slot = stealableSlot(base)
		local owner = BaseService.OwnerOf(base)
		local profile = owner and DataService.Get(owner)
		local slot = b.Slot
		local item = if profile and slot then profile.Knives[slot] else nil
		if
			owner
			and profile
			and slot
			and item
			and item ~= BaseService.ProtectedItem(owner)
			and canBreak(base)
			and (takenFrom[base] or 0) < CONFIG.BurglarStealsPerVault
		then
			takenFrom[base] = (takenFrom[base] or 0) + 1
			DataService.Update(owner, function(p)
				DataService.RemoveKnife(p, slot)
			end)
			BaseService.RefreshRack(owner)
			b.Carrying = item
			b.CarryOwner = owner.UserId
			local visual = KnifeModel.Build(item, false)
			KnifeModel.FitItem(visual, item, 3.4)
			local head = b.Model:FindFirstChild("Head") :: BasePart
			attachProp(visual, head, CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, math.rad(90)), b.Model)
			b.CarryVisual = visual
			b.Model:SetAttribute("Carrying", true) -- clients hold it up with the Carry pose
			Net.Notify(owner, `{b.Name} grabbed your {Items.DisplayName(item)}! Stop them before they escape!`, "bad")
			Net.Remotes.Effect:FireClient(owner, "Alarm")
			Net.Announce(
				`{b.Name} is escaping with {owner.DisplayName}'s {Items.DisplayName(item)}!`,
				Color3.fromRGB(255, 160, 60),
				1
			)
		end
		if b.Carrying then
			b.State = "Escape"
			b.Waypoints = exitPath(base)
		else
			-- Came up empty: straight on to the next vault
			b.Base, b.Slot = nil, nil
			local nextBase, nextSlot = pickTarget(base)
			if nextBase then
				local height = GuardService.RootHeight()
				local outside = (base.Frame * CFrame.new(0, 0, HALF_D + 6)).Position
				b.Base, b.Slot = nextBase, nextSlot
				b.State = "ToGate"
				b.Waypoints = { Vector3.new(outside.X, height, outside.Z), gateFront(nextBase, b) }
			else
				b.State = "Escape"
				b.Waypoints = exitPath(base)
			end
		end
	elseif b.State == "Escape" then
		if walk(b, dt, if b.Carrying then CONFIG.BurglarCarrySpeed else CONFIG.BurglarSpeed) then
			-- Got away
			if b.Carrying then
				local owner = b.CarryOwner and Players:GetPlayerByUserId(b.CarryOwner)
				Net.Announce(
					`{b.Name} got away with {if owner then owner.DisplayName .. "'s" else "a"} {Items.DisplayName(
						b.Carrying
					)}!`,
					Color3.fromRGB(200, 120, 255),
					1
				)
			end
			b.Dead = true
			b.RemoveTarget()
			Net.Remotes.Effect:FireAllClients("Smoke", b.Position)
			b.Model:Destroy()
		end
	end
end

-- The raid itself --------------------------------------------------------------------------

function RaidService.Start()
	if raiding then
		return
	end
	-- Burglars need somewhere to go: if every vault is protected (new players, everyone in a
	-- round), there's no raid rather than an announcement that nothing follows
	local any = false
	for _, base in MapService.Bases do
		if protectedReason(base, true) == nil then
			any = true
		end
	end
	if not any then
		return
	end
	raiding = true
	raidGeneration += 1
	local generation = raidGeneration
	raidEndsAt = now() + CONFIG.Duration
	ReplicatedStorage:SetAttribute("Raid", true)
	ReplicatedStorage:SetAttribute("RaidEndsAt", raidEndsAt)
	for base in gates do
		refreshGateBar(base)
	end
	Net.Announce(
		"THIEF MOON! Burglars are coming, gates are weak and bounties are doubled!",
		Color3.fromRGB(255, 60, 60),
		3
	)
	Net.Remotes.Effect:FireAllClients("RaidStart", raidEndsAt)
	-- Burglars arrive in waves through the raid
	table.clear(takenFrom)
	local count = CONFIG.Burglars
	for i = 1, count do
		-- Three arrive together, with all waves appearing in the first half of the raid.
		task.delay(((i - 1) // 3) * (CONFIG.Duration * 0.5 / math.ceil(count / 3)) + ((i - 1) % 3) * 0.4, function()
			if raiding and generation == raidGeneration then
				spawnBurglar(generation)
			end
		end)
	end
end

function RaidService.Stop()
	if not raiding then
		return
	end
	raiding = false
	raidGeneration += 1
	ReplicatedStorage:SetAttribute("Raid", nil)
	ReplicatedStorage:SetAttribute("RaidEndsAt", nil)
	for base in gates do
		if gateOpen(base) then
			reforge(base, 1)
		else
			refreshGateBar(base)
		end
	end
	-- Burglars still around flee
	for _, b in burglars do
		if not b.Dead and b.State ~= "Escape" then
			local inside = b.State == "Enter" or b.State == "Steal"
			b.State = "Escape"
			b.Waypoints = exitPath(if inside then b.Base else nil)
			b.NextAction = 0
		end
	end
	Net.Announce("The Thief Moon sets. The burglars are fleeing...", Color3.fromRGB(200, 200, 220), 1)
	Net.Remotes.Effect:FireAllClients("RaidEnd")
end

-- Raids happen near the end of each intermission (GameConfig.Raid.StartBefore before the round)
-- Summon the Thief Moon (Robux): now if we can, otherwise as soon as the next intermission
-- allows; during one already it lasts a minute longer
local pendingSummon: string? = nil
function RaidService.Summon(player: Player)
	if raiding then
		raidEndsAt += 60
		ReplicatedStorage:SetAttribute("RaidEndsAt", raidEndsAt)
		Net.Announce(`🌕 {player.DisplayName} made the Thief Moon last longer!`, Color3.fromRGB(255, 70, 70), 2)
		return
	end
	pendingSummon = player.DisplayName
	Net.Notify(player, "The Thief Moon will rise as soon as the next intermission allows", "info")
end

local function schedule()
	local raidedThisIntermission = false
	local intermissions = 0
	local counted = false
	while true do
		task.wait(0.5)
		local phase = ReplicatedStorage:GetAttribute("Phase")
		local endsAt = ReplicatedStorage:GetAttribute("PhaseEndsAt")
		local waiting = ReplicatedStorage:GetAttribute("Status") ~= "🔪 MURDER ROUND in"
		if phase == "Intermission" and type(endsAt) == "number" and not waiting then
			if not counted then
				counted = true
				intermissions += 1
			end
			if pendingSummon and not raiding and endsAt - now() > 45 then
				local who = pendingSummon
				pendingSummon = nil
				RaidService.Start()
				if raiding then
					raidedThisIntermission = true
					Net.Announce(`🌕 {who} summoned the THIEF MOON!`, Color3.fromRGB(255, 60, 60), 3)
				end
			end
			local bloodMoon = intermissions % CONFIG.Every == 0
			local left = endsAt - now()
			ReplicatedStorage:SetAttribute(
				"NextRaidAt",
				if raidedThisIntermission or not bloodMoon then nil else endsAt - CONFIG.StartBefore
			)
			if
				bloodMoon
				and not raidedThisIntermission
				and not raiding
				and left <= CONFIG.StartBefore
				and left > 20
			then
				if #Players:GetPlayers() >= CONFIG.MinPlayers then
					raidedThisIntermission = true
					RaidService.Start()
				end
			end
		else
			ReplicatedStorage:SetAttribute("NextRaidAt", nil)
			if phase ~= "Intermission" then
				raidedThisIntermission = false
				counted = false
			end
		end
		if raiding and now() >= raidEndsAt then
			RaidService.Stop()
		end
		-- Stop before the round starts no matter what
		if raiding and phase ~= "Intermission" then
			RaidService.Stop()
		end
	end
end

local function step(dt: number)
	-- Gates: reopen broken ones after a while, slowly mend the rest
	do
		local t = now()
		for base, state in gates do
			if gateOpen(base) then
				if state.BrokenUntil > 0 and t >= state.BrokenUntil then
					reforge(base, 0.5)
				end
			elseif t - state.LastHit > CONFIG.GateRegenDelay then
				local max = (base.Blocker:GetAttribute("MaxHealth") or 1) :: number
				local health = (base.Blocker:GetAttribute("Health") or 0) :: number
				if health < max then
					base.Blocker:SetAttribute("Health", math.min(max, health + max * CONFIG.GateRegen * dt))
					refreshGateBar(base)
				end
			end
		end
	end
	for i = #burglars, 1, -1 do
		local b = burglars[i]
		if b.Dead and not b.Model.Parent then
			table.remove(burglars, i)
		elseif not b.Dead then
			stepBurglar(b, dt)
		end
	end
end

function RaidService.Init()
	-- A Murderer wipe calls the Thief Moon (now, or as soon as the intermission allows)
	ServerEvents.OnWipe = function(name: string)
		Net.Announce(`🔪 {name}'s massacre is calling the Thief Moon!`, Color3.fromRGB(255, 70, 70), 3)
		if raiding then
			raidEndsAt += 60
			ReplicatedStorage:SetAttribute("RaidEndsAt", raidEndsAt)
		else
			pendingSummon = name
		end
	end
	burglarFolder = Instance.new("Folder")
	burglarFolder.Name = "Burglars"
	burglarFolder.Parent = workspace:FindFirstChild("Map")

	for _, base in MapService.Bases do
		trackGate(base)
	end
	BaseService.OnWallsBuilt = function(base)
		trackGate(base)
		if raiding then
			-- New walls arrive at full strength
			base.Blocker:SetAttribute("Health", base.Blocker:GetAttribute("MaxHealth"))
		end
		refreshGateBar(base)
	end
	BaseService.OnStealPrompt = onStealPrompt
	PowerService.CanRaidPlayer = RaidService.CanAttackPlayer
	Targets.AddProvider(playerTargets)
	Net.Remotes.RepairGate.OnServerEvent:Connect(onRepair)

	-- Flash blinds burglars and raiders in front of you too
	PowerService.OnFlash(function(flasher, origin, look, range, duration, burst)
		for _, b in burglars do
			local offset = b.Position - origin
			if
				not b.Dead
				and offset.Magnitude < range
				and (offset.Magnitude <= burst or look:Dot(offset.Unit) > 0.57)
			then
				b.StunnedUntil = now() + duration
			end
		end
		-- Anyone you could hit (raiders marked on your gate, thieves, Thief Moon targets)
		do
			for _, player in Players:GetPlayers() do
				local root = rootOf(player)
				if root and RaidService.CanAttackPlayer(flasher, player) then
					local offset = root.Position - origin
					if offset.Magnitude < range and (offset.Magnitude <= burst or look:Dot(offset.Unit) > 0.57) then
						player:SetAttribute("StunnedUntil", now() + duration)
						BaseService.RefreshWalkSpeed(player)
						Net.Remotes.Effect:FireClient(player, "Blinded", duration)
						task.delay(duration, function()
							BaseService.RefreshWalkSpeed(player)
						end)
					end
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		for _, other in Players:GetPlayers() do
			if other:GetAttribute("RevengeOn") == player.UserId then
				other:SetAttribute("RevengeOn", nil)
				other:SetAttribute("RevengeUntil", nil)
			end
		end
	end)

	RunService.Heartbeat:Connect(step)
	task.spawn(schedule)
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(0.3)
			evictIntruders()
			stepAuras()
			-- Gate labels (the new-player shield counts down, owners come and go)
			tick += 1
			if tick % 10 == 0 then
				for base in gates do
					refreshGateBar(base)
				end
			end
		end
	end)
end

return RaidService
