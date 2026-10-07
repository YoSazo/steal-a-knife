--!strict
-- Innocent Powers. Bought for good with cash (what your knives earn), upgraded to level 3, and
-- equipped in a loadout of PowerSlots. Every power works everywhere:
--   * in the arena against guards, on a cooldown
--   * in raids against raiders and burglars (same cooldowns)
--   * in rounds against the Murderer, paid for with Energy: you start each round with a little
--     and every coin you grab adds more (the Murderer can't use them)
-- The client only asks (Remotes.Power / Remotes.UsePower); everything is checked here.
-- State the HUD reads: player attributes PowerReady_<id> (server time), Energy, MaxEnergy.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local GuardService = require(script.Parent.GuardService)
local Obstacles = require(script.Parent.Obstacles)
local Offers = require(script.Parent.Offers)
local Stealth = require(script.Parent.Stealth)
local Targets = require(script.Parent.Targets)
local Fuel = require(script.Parent.Fuel)
local Analytics = require(script.Parent.Analytics)
local Items = require(ReplicatedStorage.Shared.Items)
local KnifePowers = require(ReplicatedStorage.Shared.Config.KnifePowers)
local Format = require(ReplicatedStorage.Shared.Format)

type PowerConfig = {
	Id: string,
	DisplayName: string,
	Description: string,
	Cost: number,
	Color: Color3,
	Duration: { number },
	Energy: { number },
	Hits: { number }?,
	Speed: number?, -- Rush: extra walk speed
	Range: number?, -- Smoke Burst: reach
	RoundDuration: { number }?, -- rounds use this instead of Duration when set
	RoundUses: number?, -- most uses per round
	Cooldown: number,
}

type Trap = {
	Model: Model,
	Owner: Player,
	Position: Vector3,
	Round: boolean,
	Stun: number,
	Expires: number,
	Home: boolean, -- set inside the owner's own vault: it waits there for intruders
}
type Decoy = { Model: Model, Owner: Player, Pop: () -> () }

local PowerService = {}
PowerService.CanRaidPlayer = nil :: ((Player, Player) -> boolean)?

local byId: { [string]: PowerConfig } = {}
for _, power in GameConfig.Powers do
	byId[power.Id] = power :: PowerConfig
end

local lastRequest: { [Player]: number } = {}
local energy: { [Player]: number? } = {} -- in a round
local roundUses: { [Player]: { [string]: number } } = {} -- powers used this round (RoundUses caps)
-- Others who react to a Flash (RoundService: Murderer bots; RaidService: burglars and raiders).
-- Called with (flasher, origin, look, range, duration).
local flashHandlers: { (Player, Vector3, Vector3, number, number, number) -> () } = {}
local traps: { Trap } = {}
local decoys: { Decoy } = {}
local effectsFolder: Folder

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function stat(values: { number }, level: number): number
	return values[math.clamp(level, 1, #values)]
end

local function floorUnder(position: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position, Vector3.new(0, -12, 0), params)
	return if hit then hit.Position else position - Vector3.new(0, 3, 0)
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Shop / loadout ----------------------------------------------------------------------------

-- The Enchanter: re-roll the power on the knife you fight with, for cash (that knife's income for
-- GameConfig.Enchant.CostSeconds) or one Reroll Token. Always lands on a different power; uses your
-- power luck (Heat etc.). Levels belong to powers, so nothing you've grinded is lost.
local lastEnchant: { [Player]: number } = {}
function PowerService.EnchantCost(item: string): number
	return math.max(GameConfig.Enchant.MinCost, math.floor(Items.Income(item) * GameConfig.Enchant.CostSeconds))
end
local function enchant(player: Player, mode: unknown): (boolean, string?)
	if os.clock() - (lastEnchant[player] or 0) < 0.4 then
		return false, nil
	end
	lastEnchant[player] = os.clock()
	local profile = DataService.Get(player)
	local item = BaseService.ProtectedItem(player)
	local index = profile and item and table.find(profile.Knives, item)
	if not profile or not item or not index then
		return false, "You need a knife in your vault first"
	end
	if player:GetAttribute("InRound") then
		return false, "Not during a round!"
	end
	local parsed = Items.Parse(item)
	if not parsed then
		return false, nil
	end
	if mode == "Token" then
		if not DataService.UseCharge(player, "Reroll") then
			Offers.Show(player, "Reroll3", "Out of Reroll Tokens? Get more and chase that Mythic power!")
			return false, "No Reroll Tokens left"
		end
	else
		local cost = PowerService.EnchantCost(item)
		if not DataService.TrySpend(player, cost, "enchant") then
			return false, `Re-rolling this knife costs {Format.Cash(cost)}`
		end
	end
	local power = parsed.Perk
	for _ = 1, 20 do
		power = Items.RollPower(Random.new(), Fuel.PowerLuck(player))
		if power ~= parsed.Perk then
			break
		end
	end
	local rerolled = Items.WithPower(item, power :: string)
	DataService.Update(player, function(p)
		p.Knives[index] = rerolled
		if p.Equipped == item then
			p.Equipped = rerolled
		end
	end)
	BaseService.RefreshRack(player)
	Analytics.Track(player, "power.enchant", {
		mode = if mode == "Token" then "token" else "cash",
		from = parsed.Perk,
		to = power,
		one_in = Items.PowerOneIn(power),
	})
	Net.Remotes.Effect:FireClient(player, "PowerRoll", rerolled, power, Items.PowerOneIn(power))
	if Items.PowerOneIn(power) >= 60 then
		Net.Announce(
			`🔮 {player.DisplayName} enchanted a {Items.PowerName(power)} knife!`,
			Color3.fromRGB(190, 110, 255),
			3
		)
	end
	return true, Items.PowerName(power)
end

local function handlePower(player: Player, action: unknown, id: unknown): boolean
	if action == "Enchant" then
		local ok, message = enchant(player, id)
		if message then
			Net.Notify(player, if ok then `🔮 New power: {message}!` else message, if ok then "good" else "bad")
		end
		return ok
	end
	-- Powers aren't bought any more: they live on knives (docs/POWERS.md)
	if true then
		local _ = action
		local _ = id
		return false
	end
	local now = os.clock()
	if now - (lastRequest[player] or 0) < 0.25 then
		return false
	end
	lastRequest[player] = now
	local profile = DataService.Get(player)
	if not profile or type(action) ~= "string" then
		return false
	end

	if action == "Slot" then
		if profile.PowerSlots >= GameConfig.MaxPowerSlots then
			Net.Notify(player, "You already have every power slot!", "bad")
			return false
		end
		if not DataService.TrySpend(player, GameConfig.PowerSlotCost, "power_slot") then
			Net.Notify(player, "Not enough cash", "bad")
			return false
		end
		DataService.Update(player, function(p)
			p.PowerSlots += 1
		end)
		Net.Notify(player, "New power slot unlocked!", "good")
		return true
	end

	local power = type(id) == "string" and byId[id] or nil
	if not power then
		return false
	end
	local level = profile.Powers[power.Id] or 0

	if action == "Buy" then
		if level >= GameConfig.PowerMaxLevel then
			Net.Notify(player, `{power.DisplayName} is maxed!`, "bad")
			return false
		end
		local cost = GameConfig.PowerCost(power.Cost, level)
		if not DataService.TrySpend(player, cost, "power_buy") then
			Net.Notify(player, "Not enough cash", "bad")
			Offers.Cash(player, cost - profile.Cash, BaseService.RackIncome(player))
			return false
		end
		DataService.Update(player, function(p)
			p.Powers[power.Id] = level + 1
			-- First unlock goes straight into a free slot
			if level == 0 and #p.Loadout < p.PowerSlots then
				table.insert(p.Loadout, power.Id)
			end
		end)
		Net.Notify(
			player,
			if level == 0 then `{power.DisplayName} unlocked!` else `{power.DisplayName} upgraded to level {level + 1}!`,
			"good"
		)
		return true
	elseif action == "Equip" then
		if level == 0 or table.find(profile.Loadout, power.Id) then
			return false
		end
		if #profile.Loadout >= profile.PowerSlots then
			Net.Notify(player, "Your loadout is full - unequip a power first", "bad")
			return false
		end
		DataService.Update(player, function(p)
			table.insert(p.Loadout, power.Id)
		end)
		return true
	elseif action == "Unequip" then
		local index = table.find(profile.Loadout, power.Id)
		if not index then
			return false
		end
		DataService.Update(player, function(p)
			table.remove(p.Loadout, index)
		end)
		return true
	end
	return false
end

-- The powers ------------------------------------------------------------------------------

-- Radar: see through walls. Rounds: the Murderer, once their knife is out (no free reveals). Arena: every guard, outlined in the colour of
-- the knife it carries, plus knives lying on the floor.
local function radar(player: Player, duration: number)
	local entries: { any } = {} -- { Model, Color } pairs for the client
	if player:GetAttribute("InRound") then
		for _, other in Players:GetPlayers() do
			if
				other:GetAttribute("InRound")
				and other:GetAttribute("Role") == "Murderer"
				and other:GetAttribute("KnifeOut")
				and other.Character
			then
				table.insert(entries, { Model = other.Character, Color = Color3.fromRGB(255, 40, 50) })
			end
		end
		for _, bot in CollectionService:GetTagged("RoundBot") do
			if bot:GetAttribute("Role") == "Murderer" and bot:GetAttribute("KnifeOut") then
				table.insert(entries, { Model = bot, Color = Color3.fromRGB(255, 40, 50) })
			end
		end
	else
		local canRaidPlayer = PowerService.CanRaidPlayer
		if canRaidPlayer then
			for _, other in Players:GetPlayers() do
				if other.Character and canRaidPlayer(player, other) then
					table.insert(entries, { Model = other.Character, Color = Color3.fromRGB(255, 100, 70) })
				end
			end
		end
		if ReplicatedStorage:GetAttribute("Raid") then
			for _, burglar in CollectionService:GetTagged("Burglar") do
				table.insert(entries, { Model = burglar, Color = Color3.fromRGB(255, 180, 70) })
			end
		end
		for _, guard in GuardService.All() do
			local knife = Knives.ByName[guard.KnifeName]
			table.insert(entries, {
				Model = guard.Model,
				Color = if knife then Knives.RarityColors[knife.Rarity] else Color3.new(1, 1, 1),
			})
		end
		local map = workspace:FindFirstChild("Map")
		local drops = map and map:FindFirstChild("DroppedKnives")
		if drops then
			for _, drop in drops:GetChildren() do
				table.insert(entries, { Model = drop, Color = Color3.fromRGB(255, 255, 255) })
			end
		end
	end
	if player:GetAttribute("InRound") and #entries == 0 then
		Net.Notify(player, "The Murderer is hiding. Try again soon!", "info")
	end
	Net.Remotes.Effect:FireClient(player, "Radar", entries, duration)
end

-- Bear Trap: snaps on the next guard (arena) or Murderer (round) that steps in
local function placeTrap(player: Player, stun: number)
	local root = rootOf(player)
	if not root then
		return
	end
	-- One trap each; a new one replaces the old
	for i = #traps, 1, -1 do
		if traps[i].Owner == player then
			traps[i].Model:Destroy()
			table.remove(traps, i)
		end
	end
	local ignore: { Instance } = { effectsFolder }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local at = floorUnder(root.Position, ignore)
	local model = Instance.new("Model")
	model.Name = `Trap_{player.Name}`
	local metal = Color3.fromRGB(120, 120, 130)
	local base = part(
		model,
		"Base",
		Vector3.new(0.3, 3.2, 3.2),
		CFrame.new(at + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		metal,
		Enum.Material.Metal
	)
	base.Shape = Enum.PartType.Cylinder
	part(
		model,
		"Plate",
		Vector3.new(1, 0.15, 1),
		CFrame.new(at + Vector3.new(0, 0.32, 0)),
		Color3.fromRGB(170, 140, 60),
		Enum.Material.Metal
	)
	for i = 0, 7 do
		local angle = i * math.pi / 4
		part(
			model,
			"Tooth",
			Vector3.new(0.25, 0.6, 0.25),
			CFrame.new(at + Vector3.new(math.cos(angle) * 1.4, 0.45, math.sin(angle) * 1.4)),
			Color3.fromRGB(200, 200, 210),
			Enum.Material.Metal
		)
	end
	model.Parent = effectsFolder
	local inRound = player:GetAttribute("InRound") == true
	local home = not inRound and BaseService.IsInOwnBase(player, at)
	if home then
		-- One home trap at a time: the new one replaces the old
		for i = #traps, 1, -1 do
			if traps[i].Home and traps[i].Owner == player then
				traps[i].Model:Destroy()
				table.remove(traps, i)
			end
		end
		Net.Notify(player, "Trap set!", "good")
	end
	table.insert(traps, {
		Model = model,
		Owner = player,
		Position = at,
		Round = inRound,
		Stun = stun,
		Expires = if home then math.huge else os.clock() + 45,
		Home = home,
	})
end

local function snap(trap: Trap)
	Net.Remotes.Effect:FireAllClients("TrapSnap", trap.Position)
	trap.Model:Destroy()
end

local function nearTrap(trap: Trap, position: Vector3, radius: number): boolean
	local offset = position - trap.Position
	return math.abs(offset.Y) <= 6 and (offset * Vector3.new(1, 0, 1)).Magnitude < radius
end

local function stepTraps()
	local now = os.clock()
	for i = #traps, 1, -1 do
		local trap = traps[i]
		local sprung = false
		if now > trap.Expires or not trap.Owner.Parent then
			trap.Model:Destroy()
			table.remove(traps, i)
			continue
		end
		do
			local canRaidPlayer = PowerService.CanRaidPlayer
			for _, other in Players:GetPlayers() do
				local root = rootOf(other)
				local eligible = if trap.Round
					then other:GetAttribute("InRound") and other:GetAttribute("Role") == "Murderer"
					else canRaidPlayer ~= nil and canRaidPlayer(trap.Owner, other)
				if root and eligible then
					if nearTrap(trap, root.Position, 3) then
						other:SetAttribute("StunnedUntil", workspace:GetServerTimeNow() + trap.Stun)
						BaseService.RefreshWalkSpeed(other)
						if other.Character then
							Net.Animate(other.Character, "Hurt")
						end
						Net.Notify(other, "SNAP! You're stuck in a trap!", "bad")
						task.delay(trap.Stun, function()
							BaseService.RefreshWalkSpeed(other)
						end)
						sprung = true
						break
					end
				end
			end
		end
		if not trap.Round and not sprung then
			for _, guard in GuardService.All() do
				if nearTrap(trap, guard.Position, 3.5) then
					GuardService.Stun(guard, trap.Stun)
					sprung = true
					break
				end
			end
		end
		if sprung then
			snap(trap)
			table.remove(traps, i)
		end
	end
end

-- Shield: a bubble that eats the next hit (arena: for a while; round: until it's used)
local function shield(player: Player, duration: number)
	local character = player.Character
	local root = rootOf(player)
	if not character or not root then
		return
	end
	local inRound = player:GetAttribute("InRound") == true
	character:SetAttribute("ShieldUntil", workspace:GetServerTimeNow() + (if inRound then 9999 else duration))
	local old = character:FindFirstChild("ShieldBubble")
	if old then
		old:Destroy()
	end
	local bubble = Instance.new("Part")
	bubble.Name = "ShieldBubble"
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.one * 7
	bubble.Material = Enum.Material.ForceField
	bubble.Color = Color3.fromRGB(90, 180, 255)
	bubble.Transparency = 0.3
	bubble.CanCollide = false
	bubble.CanQuery = false
	bubble.CanTouch = false
	bubble.Massless = true
	bubble.CFrame = root.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = bubble
	weld.Parent = bubble
	bubble.Parent = character
	-- The bubble goes when the shield is used up or runs out
	local connection
	connection = character:GetAttributeChangedSignal("ShieldUntil"):Connect(function()
		if character:GetAttribute("ShieldUntil") == nil then
			connection:Disconnect()
			bubble:Destroy()
		end
	end)
	if not inRound then
		task.delay(duration, function()
			if bubble.Parent then
				character:SetAttribute("ShieldUntil", nil)
			end
		end)
	end
end

-- Decoy: a copy of you that sprints off; whoever was after you follows it until they catch it
local function decoy(player: Player, duration: number)
	local character = player.Character
	local root = rootOf(player)
	if not character or not root then
		return
	end
	character.Archivable = true
	local ok, clone = pcall(character.Clone, character)
	local model = (clone :: any) :: Model?
	if not ok or not model then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("Tool") or d:IsA("Sound") or d.Name == "ShieldBubble" then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	local decoyRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart
	decoyRoot.Anchored = true
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.EvaluateStateMachine = false
	model.Name = `Decoy_{player.Name}`
	model.Parent = effectsFolder

	-- Run away from the closest threat, or straight ahead
	local direction = root.CFrame.LookVector
	local threatPos: Vector3? = nil
	if player:GetAttribute("InRound") then
		for _, other in Players:GetPlayers() do
			local r = rootOf(other)
			if r and other:GetAttribute("InRound") and other:GetAttribute("Role") == "Murderer" then
				threatPos = r.Position
			end
		end
	else
		local best = math.huge
		for _, guard in GuardService.All() do
			local d = (guard.Position - root.Position).Magnitude
			if d < best then
				best, threatPos = d, guard.Position
			end
		end
	end
	if threatPos then
		local away = (root.Position - threatPos) * Vector3.new(1, 0, 1)
		if away.Magnitude > 0.1 then
			-- Off at an angle, so it doesn't run in a straight line from you
			direction = (CFrame.Angles(0, math.rad(math.random(-50, 50)), 0) * away.Unit)
		end
	end
	direction = Vector3.new(direction.X, 0, direction.Z).Unit

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local animation = Instance.new("Animation")
		animation.AnimationId = "rbxassetid://507767714" -- R15 run
		local trackOk, track = pcall(animator.LoadAnimation, animator, animation)
		if trackOk then
			track.Looped = true
			track:Play()
		end
	end

	local entry: Decoy
	local connection: RBXScriptConnection
	local popped = false
	local function pop()
		if popped then
			return
		end
		popped = true
		connection:Disconnect()
		Net.Remotes.Effect:FireAllClients("Smoke", decoyRoot.Position)
		model:Destroy()
		local index = table.find(decoys, entry)
		if index then
			table.remove(decoys, index)
		end
	end
	entry = { Model = model, Owner = player, Pop = pop }
	table.insert(decoys, entry)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { effectsFolder, character }
	local speed = 18
	local position = decoyRoot.Position
	local started = os.clock()
	connection = RunService.Heartbeat:Connect(function(dt)
		if os.clock() - started > duration then
			pop()
			return
		end
		-- Turn when something's in the way
		local ahead = workspace:Raycast(position, direction * 4, params)
		if ahead then
			direction = (CFrame.Angles(0, math.rad(if math.random() < 0.5 then 90 else -90), 0) * direction)
		end
		position += direction * speed * dt
		decoyRoot.CFrame = CFrame.lookAt(position, position + direction)
	end)
	GuardService.Lure(player, decoyRoot, duration, pop)
end

-- The Murderer swiping at a decoy pops it (RoundService calls this on every swing)
-- Round traps also catch a Murderer bot (Studio bot rounds): returns the stun time if one snapped
function PowerService.SpringRoundTrap(position: Vector3): number?
	for i = #traps, 1, -1 do
		local trap = traps[i]
		if trap.Round and nearTrap(trap, position, 3) then
			snap(trap)
			table.remove(traps, i)
			return trap.Stun
		end
	end
	return nil
end

function PowerService.SpringRaidTrap(position: Vector3): number?
	for i = #traps, 1, -1 do
		local trap = traps[i]
		if not trap.Round and os.clock() <= trap.Expires and nearTrap(trap, position, 3.5) then
			snap(trap)
			table.remove(traps, i)
			return trap.Stun
		end
	end
	return nil
end

function PowerService.PopDecoyNear(position: Vector3, range: number): boolean
	for _, entry in table.clone(decoys) do
		local r = entry.Model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r and (r.Position - position).Magnitude <= range then
			entry.Pop()
			return true
		end
	end
	return false
end

-- Mimic: hide the body and become a piece of furniture until you move
local PROPS = { "Crate", "Barrel", "Plant", "Chair", "Lamp" }
local function buildProp(kind: string, at: CFrame, parent: Instance): BasePart
	local wood = Color3.fromRGB(150, 105, 60)
	if kind == "Crate" then
		return part(
			parent,
			"Crate",
			Vector3.new(3.6, 3.6, 3.6),
			at * CFrame.new(0, -1.2, 0),
			wood,
			Enum.Material.WoodPlanks
		)
	elseif kind == "Barrel" then
		local b = part(
			parent,
			"Barrel",
			Vector3.new(4, 3, 3),
			at * CFrame.new(0, -1, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(120, 75, 40),
			Enum.Material.Wood
		)
		b.Shape = Enum.PartType.Cylinder
		return b
	elseif kind == "Plant" then
		local pot =
			part(parent, "Pot", Vector3.new(2.2, 2.2, 2.2), at * CFrame.new(0, -2, 0), Color3.fromRGB(170, 95, 60))
		local leaves = part(
			parent,
			"Leaves",
			Vector3.new(3.6, 3.6, 3.6),
			at * CFrame.new(0, 0.6, 0),
			Color3.fromRGB(60, 150, 60),
			Enum.Material.Grass
		)
		leaves.Shape = Enum.PartType.Ball
		return pot
	elseif kind == "Chair" then
		local seat =
			part(parent, "Seat", Vector3.new(2.6, 0.5, 2.6), at * CFrame.new(0, -1.1, 0), wood, Enum.Material.Wood)
		part(parent, "Back", Vector3.new(2.6, 3, 0.4), at * CFrame.new(0, 0.6, 1.1), wood, Enum.Material.Wood)
		part(
			parent,
			"Legs",
			Vector3.new(2.2, 1.6, 2.2),
			at * CFrame.new(0, -2.2, 0),
			wood:Lerp(Color3.new(0, 0, 0), 0.3)
		)
		return seat
	end
	local pole = part(
		parent,
		"Pole",
		Vector3.new(0.4, 5, 0.4),
		at * CFrame.new(0, -0.6, 0),
		Color3.fromRGB(40, 40, 45),
		Enum.Material.Metal
	)
	local shade = part(
		parent,
		"Shade",
		Vector3.new(2.4, 1.4, 2.4),
		at * CFrame.new(0, 2.2, 0),
		Color3.fromRGB(255, 220, 160),
		Enum.Material.Neon
	)
	local light = Instance.new("PointLight")
	light.Range = 10
	light.Color = Color3.fromRGB(255, 210, 150)
	light.Parent = shade
	return pole
end

local function mimic(player: Player, duration: number)
	local character = player.Character
	local root = rootOf(player)
	if not character or not root then
		return
	end
	Stealth.Reveal(player)
	local undo = Stealth.Hide(player)
	if not undo then
		return
	end
	Net.Remotes.Effect:FireAllClients("Smoke", root.Position)
	local prop = Instance.new("Model")
	prop.Name = `Mimic_{player.Name}`
	local yaw = math.random() * math.pi * 2
	buildProp(PROPS[math.random(1, #PROPS)], CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0), prop)
	-- The disguise moves with you (prop-hunt style), so it works mid-run too: weld it to the root
	for _, d in prop:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = d
			weld.Parent = d
		end
	end
	prop.Parent = effectsFolder
	player:SetAttribute("Mimic", true)
	local finished = false
	local connection: RBXScriptConnection
	local function finish()
		if finished then
			return
		end
		finished = true
		connection:Disconnect()
		Stealth.Unregister(player, finish)
		player:SetAttribute("Mimic", nil)
		prop:Destroy()
		undo()
		local r = rootOf(player)
		if r then
			Net.Remotes.Effect:FireAllClients("Smoke", r.Position)
		end
	end
	Stealth.Register(player, finish)
	local started = os.clock()
	connection = RunService.Heartbeat:Connect(function()
		-- Only dying or the time running out ends it (walking around in it is the fun part)
		if not rootOf(player) or os.clock() - started > duration then
			finish()
		end
	end)
end

-- Flash: a blinding camera flash. Everything within FLASH_BURST of you is caught whichever way
-- you face, and the beam reaches FLASH_RANGE in a wide cone where you aim (the client sends its
-- camera aim: people mostly flash over their shoulder while running away).
local FLASH_RANGE = 40
local FLASH_BURST = 24
local FLASH_CONE = math.cos(math.rad(55))
local function flash(player: Player, duration: number, aim: unknown)
	local root = rootOf(player)
	if not root then
		return
	end
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local look = root.CFrame.LookVector
	if typeof(aim) == "Vector3" then
		local flat = Vector3.new((aim :: Vector3).X, 0, (aim :: Vector3).Z)
		if flat.Magnitude > 0.01 and flat.Magnitude == flat.Magnitude then
			look = flat.Unit
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { effectsFolder, player.Character :: Model }
	local function inCone(position: Vector3, model: Instance?): boolean
		local offset = position - origin
		local distance = offset.Magnitude
		local inBurst = distance <= FLASH_BURST
		if distance > FLASH_RANGE or (not inBurst and look:Dot(offset.Unit) < FLASH_CONE) then
			return false
		end
		-- Walls block the light
		local hit = workspace:Raycast(origin, offset, params)
		return hit == nil or (model ~= nil and hit.Instance:IsDescendantOf(model))
	end
	Net.Remotes.Effect:FireAllClients("Flash", origin, look)
	local now = workspace:GetServerTimeNow()
	if player:GetAttribute("InRound") then
		for _, other in Players:GetPlayers() do
			local r = rootOf(other)
			if r and other:GetAttribute("InRound") and other:GetAttribute("Role") == "Murderer" then
				if inCone(r.Position, other.Character) then
					other:SetAttribute("StunnedUntil", now + duration)
					BaseService.RefreshWalkSpeed(other)
					Net.Remotes.Effect:FireClient(other, "Blinded", duration)
					Net.Animate(other.Character :: Model, "Hurt")
					Net.Notify(other, "FLASH! You can't see!", "bad")
					Net.Notify(player, "You blinded the Murderer! RUN!", "good")
					task.delay(duration, function()
						BaseService.RefreshWalkSpeed(other)
					end)
				end
			end
		end
	else
		for _, guard in GuardService.All() do
			if inCone(guard.Position, guard.Model) then
				GuardService.Stun(guard, duration)
			end
		end
	end
	for _, handler in flashHandlers do
		handler(player, origin, look, FLASH_RANGE, duration, FLASH_BURST)
	end
end

-- Barricade: a wooden barricade slams down in front of you. Solid to everyone; guards, burglars,
-- raiders and the Murderer have to smash it (Hits stabs) to get through.
local function barricade(player: Player, duration: number, hits: number)
	local root = rootOf(player)
	if not root then
		return
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local ignore: { Instance } = { effectsFolder }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local center = root.Position + look * 4.5
	local floor = floorUnder(center + Vector3.new(0, 2, 0), ignore)
	local frame = CFrame.lookAt(floor, floor + look)
	local model = Instance.new("Model")
	model.Name = `Barricade_{player.Name}`
	local wood = Color3.fromRGB(150, 98, 54)
	-- The solid core (what blocks and gets hit)
	local core =
		part(model, "Core", Vector3.new(10, 8, 1.2), frame * CFrame.new(0, 4, 0), wood, Enum.Material.WoodPlanks)
	core.CanCollide = true
	core.CanQuery = true
	core.Transparency = 1
	-- Planks, crossed boards and nails
	for i = 0, 4 do
		local plank = part(
			model,
			"Plank",
			Vector3.new(10.4, 1.3, 0.4),
			frame * CFrame.new(0, 0.9 + i * 1.6, 0) * CFrame.Angles(0, 0, math.rad((i % 2) * 4 - 2)),
			wood:Lerp(Color3.fromRGB(90, 60, 35), (i % 3) / 4),
			Enum.Material.WoodPlanks
		)
		plank.CanCollide = false
	end
	for _, angle in { 38, -38 } do
		part(
			model,
			"Brace",
			Vector3.new(12, 0.9, 0.35),
			frame * CFrame.new(0, 4, -0.35) * CFrame.Angles(0, 0, math.rad(angle)),
			Color3.fromRGB(110, 72, 40),
			Enum.Material.Wood
		)
	end
	for _, x in { -4.6, 4.6 } do
		part(
			model,
			"Post",
			Vector3.new(0.9, 8.6, 0.9),
			frame * CFrame.new(x, 4.3, 0.4),
			Color3.fromRGB(85, 55, 30),
			Enum.Material.Wood
		)
	end
	model.PrimaryPart = core
	model.Parent = effectsFolder
	Net.Remotes.Effect:FireAllClients("Barricade", core.Position)

	local health = hits
	local removeObstacle: () -> ()
	local removeTarget: () -> ()
	local function smash()
		if not model.Parent then
			return
		end
		removeObstacle()
		removeTarget()
		Net.Remotes.Effect:FireAllClients("Smash", core.Position)
		model:Destroy()
	end
	local function hit()
		health -= 1
		Net.Remotes.Effect:FireAllClients("Hit", core.Position)
		if health <= 0 then
			smash()
		else
			-- Knocked crooked a little more each hit
			for _, d in model:GetChildren() do
				if d:IsA("BasePart") and d ~= core then
					d.CFrame *= CFrame.Angles(0, 0, math.rad(math.random(-5, 5)))
				end
			end
		end
	end
	removeObstacle = Obstacles.Add({
		Part = core,
		Owner = player,
		Hit = function(_by: string)
			hit()
		end,
	})
	-- Other players' hub knives can smash it too (raiders)
	removeTarget = Targets.Add({
		Part = core,
		Model = model,
		Solid = true,
		CanHit = function(attacker: Player)
			return attacker ~= player
		end,
		Hit = function()
			hit()
		end,
	})
	task.delay(duration, smash)
	-- Rounds end: it goes too
	local connection: RBXScriptConnection
	connection = player:GetAttributeChangedSignal("InRound"):Connect(function()
		connection:Disconnect()
		smash()
	end)
end

-- Using a power -----------------------------------------------------------------------------

local function publishRound(player: Player)
	player:SetAttribute("Energy", energy[player])
	player:SetAttribute("MaxEnergy", if energy[player] then GameConfig.MaxEnergy else nil)
	local id = player:GetAttribute("RoundPower")
	local power = type(id) == "string" and byId[id] or nil
	local uses = roundUses[player]
	player:SetAttribute(
		"PowerUsesLeft",
		if not energy[player] or not power
			then nil
			else if power.RoundUses
				then math.max(0, power.RoundUses - (if uses then uses[power.Id] or 0 else 0))
				else -1
	)
end

-- Coins in rounds charge your powers
function PowerService.AddEnergy(player: Player, amount: number)
	if energy[player] == nil then
		return
	end
	energy[player] = math.min(GameConfig.MaxEnergy, (energy[player] :: number) + amount)
	publishRound(player)
end

-- Smoke Burst: handler(user, origin, range, push) - RoundService throws the Murderer back
local smokeHandlers: { (Player, Vector3, number, number) -> () } = {}
function PowerService.OnSmoke(handler: (Player, Vector3, number, number) -> ())
	table.insert(smokeHandlers, handler)
end

-- handler(flasher, origin, look, range, duration, burst): anything within `burst` is caught
-- whichever way the flasher faces; further out, only inside the cone along `look`
function PowerService.OnFlash(handler: (Player, Vector3, Vector3, number, number, number) -> ())
	table.insert(flashHandlers, handler)
end

local function usePower(player: Player, id: unknown, aim: unknown)
	if type(id) ~= "string" then
		return
	end
	local power = byId[id]
	local profile = DataService.Get(player)
	if not power or not profile or not rootOf(player) then
		return
	end
	local inRound = player:GetAttribute("InRound") == true
	-- One power system: in a round your power is the Innocent side of the knife you fight with
	if not inRound or player:GetAttribute("RoundPower") ~= id then
		return
	end
	local level = 1
	if inRound then
		if player:GetAttribute("Role") == "Murderer" then
			return -- the Murderer has their knife; powers are for innocents
		end
		if ReplicatedStorage:GetAttribute("Classic") then
			Net.Notify(player, "No powers this round!", "bad")
			return
		end
		-- The same base strength for everyone; the power's level adds a little (<= +20%)
		level = GameConfig.RoundPowerLevel
		local have = energy[player]
		local cost = stat(power.Energy, level)
		if not have then
			return
		end
		if have < cost then
			Net.Notify(player, `Grab coins to use {power.DisplayName}!`, "bad")
			Net.Remotes.Effect:FireClient(player, "NoEnergy", id)
			return
		end
		-- Some powers are capped per round (Vanish), so nobody can just stay invisible
		local uses = roundUses[player] or {}
		roundUses[player] = uses
		if power.RoundUses and (uses[id] or 0) >= power.RoundUses then
			Net.Notify(player, `No more {power.DisplayName} this round`, "bad")
			return
		end
		uses[id] = (uses[id] or 0) + 1
		energy[player] = have - cost
		publishRound(player)
	else
		return -- powers only work in murder rounds
	end

	local duration = stat(if inRound and power.RoundDuration then power.RoundDuration else power.Duration, level)
	duration *= 1 + 0.2 * GameConfig.PowerProgress((player:GetAttribute("PowerLevel") or 1) :: number)
	if id == "Vanish" then
		Stealth.Vanish(player, duration)
		if inRound then
			-- The Murderer still catches a faint shimmer of you
			for _, other in Players:GetPlayers() do
				if other:GetAttribute("InRound") and other:GetAttribute("Role") == "Murderer" then
					Net.Remotes.Effect:FireClient(other, "Shimmer", player.Character, duration)
				end
			end
		end
	elseif id == "Radar" then
		radar(player, duration)
	elseif id == "Trap" then
		placeTrap(player, duration)
	elseif id == "Shield" then
		shield(player, duration)
	elseif id == "Decoy" then
		decoy(player, duration)
	elseif id == "Mimic" then
		mimic(player, duration)
	elseif id == "Flash" then
		flash(player, duration, aim)
	elseif id == "Rush" then
		player:SetAttribute("PowerSpeed", power.Speed or 10)
		BaseService.RefreshWalkSpeed(player)
		Net.Remotes.Effect:FireAllClients("Dash", (rootOf(player) :: BasePart).Position)
		task.delay(duration, function()
			player:SetAttribute("PowerSpeed", nil)
			BaseService.RefreshWalkSpeed(player)
		end)
	elseif id == "Dash" then
		-- A short blink forward, stopped by walls
		local root = rootOf(player) :: BasePart
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		if look.Magnitude > 0.01 then
			look = look.Unit
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { player.Character :: any, effectsFolder }
			local hit = workspace:Raycast(root.Position, look * duration, params)
			local distance = if hit then math.max(0, hit.Distance - 2) else duration
			Net.Remotes.Effect:FireAllClients("Dash", root.Position)
			root.CFrame += look * distance
		end
	elseif id == "SmokeBurst" then
		local root = rootOf(player) :: BasePart
		Net.Remotes.Effect:FireAllClients("Smoke", root.Position)
		for _, handler in smokeHandlers do
			handler(player, root.Position, power.Range or 12, duration)
		end
	elseif id == "PhoenixWall" then
		-- A barricade of fire the Murderer can't smash (it burns out by itself)
		barricade(player, duration, math.huge)
		local wall = effectsFolder:FindFirstChild(`Barricade_{player.Name}`)
		if wall then
			for _, d in wall:GetDescendants() do
				if d:IsA("BasePart") and d.Name ~= "Core" then
					d.Color = Color3.fromRGB(255, 120 + math.random(0, 60), 30)
					d.Material = Enum.Material.Neon
				end
			end
			local core = wall:FindFirstChild("Core")
			if core then
				local fire = Instance.new("Fire")
				fire.Size, fire.Heat = 12, 14
				fire.Color, fire.SecondaryColor = Color3.fromRGB(255, 140, 30), Color3.fromRGB(255, 40, 10)
				fire.Parent = core
			end
		end
	elseif id == "Barricade" then
		barricade(player, duration, stat(power.Hits or { 3 }, level))
	end
	player:SetAttribute("LastPower", id)
	player:SetAttribute("LastPowerAt", workspace:GetServerTimeNow())
	Analytics.Track(player, "power.used", { id = id, energy_left = energy[player], role = player:GetAttribute("Role") })
	local root = rootOf(player)
	if root then
		Net.Remotes.Effect:FireClient(player, "PowerUsed", id, root.Position)
	end
end

-- Round start/end: hand out starting Energy, and clean everything up afterwards
local function onRoundChanged(player: Player)
	roundUses[player] = nil
	if player:GetAttribute("InRound") then
		player:SetAttribute("SecondLifeUsed", false)
		energy[player] = if player:GetAttribute("Role") ~= "Murderer" then GameConfig.StartEnergy else nil
	else
		energy[player] = nil
		player:SetAttribute("SecondLifeUsed", nil)
		if PowerService.PublishKnifePower then
			PowerService.PublishKnifePower(player)
		end
		Stealth.Reveal(player)
		if player.Character then
			player.Character:SetAttribute("ShieldUntil", nil)
		end
		player:SetAttribute("StunnedUntil", nil)
		for i = #traps, 1, -1 do
			if traps[i].Owner == player and traps[i].Round then
				traps[i].Model:Destroy()
				table.remove(traps, i)
			end
		end
		for _, entry in table.clone(decoys) do
			if entry.Owner == player then
				entry.Pop()
			end
		end
	end
	publishRound(player)
end

-- The power on the knife you fight with: what you use in rounds (both sides) and its level
local function publishKnifePower(player: Player)
	local profile = DataService.Get(player)
	local item = BaseService.ProtectedItem(player)
	local parsed = item and Items.Parse(item)
	local id = parsed and parsed.Perk
	local entry = id and KnifePowers.ById[id]
	local xp = if profile and id then profile.PowerXP[id] or 0 else 0
	local function set(name: string, value: any)
		if player:GetAttribute(name) ~= value then
			player:SetAttribute(name, value)
		end
	end
	set("PowerId", id)
	set("FightingKnife", item)
	set("PowerName", if entry then entry.Name else nil)
	set("PowerLevel", GameConfig.PowerLevelFor(xp))
	set("PowerXP", xp)
	set("RoundPower", if entry then entry.Innocent else nil)
	-- Every power's level (the Powers menu shows them all)
	local levels = {}
	local xpTable: { [string]: number } = if profile then profile.PowerXP else {}
	for powerId, amount in xpTable do
		table.insert(levels, `{powerId}:{GameConfig.PowerLevelFor(amount)}`)
	end
	table.sort(levels)
	set("PowerLevels", table.concat(levels, ","))
	set("RoundPowerName", if entry then entry.InnocentName else nil)
end
PowerService.PublishKnifePower = publishKnifePower
-- Studio tests (DebugService "UsePower"): the same path as the client's UsePower remote
PowerService.DebugUse = function(player: Player, id: string, aim: Vector3?)
	usePower(player, id, aim)
end
-- The Murderer's Decoy side uses the same decoy (RoundService)
PowerService.Decoy = function(player: Player, duration: number)
	decoy(player, duration)
end

-- Old saves: powers used to be bought with cash. They live on knives now, so that cash comes back
-- (once), and every old knife gets a power
local function onLoaded(player: Player, profile: DataService.Profile)
	if not table.find(profile.Bought, "PowerRefund") then
		local refund = 0
		for id, level in profile.Powers do
			local power = byId[id]
			if power then
				for l = 0, level - 1 do
					refund += GameConfig.PowerCost(power.Cost, l)
				end
			end
		end
		refund += math.max(0, profile.PowerSlots - GameConfig.PowerSlots) * GameConfig.PowerSlotCost
		DataService.CashFlow(player, refund, "power_refund")
		DataService.Update(player, function(p)
			table.insert(p.Bought, "PowerRefund")
			p.Powers = {}
			p.Loadout = {}
			p.Cash += refund
		end)
		if refund > 0 then
			task.delay(8, function()
				if player.Parent then
					Net.Notify(player, `Powers come from knives now! You got +{Format.Cash(refund)} back.`, "good")
				end
			end)
		end
	end
	Fuel.EnsurePowers(player)
	publishKnifePower(player)
end

-- Studio tests (DebugService "OldPowers"): rerun the old-save migration (refund, powers on knives)
PowerService.DebugMigrate = function(player: Player)
	local profile = DataService.Get(player)
	if profile then
		onLoaded(player, profile)
	end
end

function PowerService.Init()
	DataService.PlayerLoaded:Connect(onLoaded)
	DataService.Changed:Connect(function(player: Player)
		publishKnifePower(player)
	end)
	effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "PowerEffects"
	effectsFolder.Parent = workspace

	Net.Remotes.Power.OnServerInvoke = Analytics.Remote("Power", handlePower)
	Net.Remotes.UsePower.OnServerEvent:Connect(usePower)

	local function watch(player: Player)
		player:GetAttributeChangedSignal("InRound"):Connect(function()
			-- Role is set right after InRound; wait a beat so the Murderer gets no uses
			task.defer(onRoundChanged, player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		energy[player] = nil
		roundUses[player] = nil
		for _, entry in table.clone(decoys) do
			if entry.Owner == player then
				entry.Pop()
			end
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.1 then
			accumulator = 0
			stepTraps()
		end
	end)
end

return PowerService
