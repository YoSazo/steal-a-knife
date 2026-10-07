--!strict
-- Fighting in the hub. Everyone carries their equipped knife (or the free Rusty Shank) as a Tool:
-- click to swing (stab / slash combo), hold right-click / Q / LT / the Throw button to crank back
-- and release to throw - MM2 style. Clients animate instantly; damage lands on the clip's Impact
-- frame and thrown knives leave the hand on its Release frame. Guards take damage; so do whatever
-- RaidService registers in Targets (vault gates, burglars, and players - who only get knocked down,
-- never hurt). All hits are decided here from Tool.Activated and Remotes.Ability.
-- Also owns deaths: every character goes limp with a death cry and collapses (Mad Murderer style).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimLibrary = require(ReplicatedStorage.Shared.AnimLibrary)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local Net = require(script.Parent.Parent.Remotes)
local GuardService = require(script.Parent.GuardService)
local Ragdoll = require(script.Parent.Ragdoll)
local Analytics = require(script.Parent.Analytics)
local Targets = require(script.Parent.Targets)
local StuckKnives = require(script.Parent.StuckKnives)
local BaseService = require(script.Parent.BaseService)

local CombatService = {}

local HUB_KNIFE = "HubKnife" -- attribute marking the hub weapon so rounds can take it away
local lastSwing: { [Player]: number } = {}
local combo: { [Player]: number } = {}
local COMBO_CLIPS = { "Stab", "Slash" }
local COMBO_RESET = 1.2 -- seconds without swinging before the combo starts over
local throwReadyAt: { [Player]: number } = {}

type Flying = {
	Model: Model,
	Owner: Player,
	Position: Vector3,
	Direction: Vector3,
	Traveled: number,
	Speed: number,
	Damage: number,
}
local flying: { Flying } = {}
local flyingFolder: Folder

-- The knife you fight with (BaseService.BestKnife: your pick, else your best power), else the starter
-- (a knife fresh out of its coffin rides in your hand until it hops into your pen)
function CombatService.WieldedKnife(player: Player): string
	return BaseService.HatchedItem(player) or BaseService.BestKnife(player) or GameConfig.StarterKnife
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function currentTool(player: Player): Tool?
	local containers: { Instance? } = { player.Character, player:FindFirstChildOfClass("Backpack") }
	for _, container in containers do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute(HUB_KNIFE) then
					return child
				end
			end
		end
	end
	return nil
end

-- Which clip a swing plays: alternates Stab, Slash, Stab... (the client predicts the same order)
function CombatService.NextSwing(player: Player): string
	local now = os.clock()
	local index = if now - (lastSwing[player] or 0) > COMBO_RESET then 1 else (combo[player] or 0) % #COMBO_CLIPS + 1
	combo[player] = index
	return COMBO_CLIPS[index]
end

local function swing(player: Player, tool: Tool)
	local now = os.clock()
	if now - (lastSwing[player] or 0) < GameConfig.SwingCooldown or player:GetAttribute("InRound") then
		return
	end
	local character = player.Character
	if not character or not rootOf(player) then
		return
	end
	local clipName = CombatService.NextSwing(player)
	lastSwing[player] = now
	local clip = AnimLibrary.Clips[clipName]
	Net.Animate(character, clipName, player)
	-- The blade connects partway through the swing; check reach at that moment
	task.delay(clip.Impact or 0.15, function()
		local root = rootOf(player)
		if not root or tool.Parent ~= character then
			return
		end
		Net.Remotes.Effect:FireAllClients("Swing", root.Position)
		local damage = Items.Damage(tool:GetAttribute(HUB_KNIFE) :: string)
		local guard = GuardService.InReach(root.Position, root.CFrame.LookVector, GameConfig.SwingRange)
		if guard then
			GuardService.Damage(guard, damage, player)
			return
		end
		local target = Targets.InReach(player, root.Position, root.CFrame.LookVector, GameConfig.SwingRange)
		if target then
			target.Hit(player, damage, "Swing", root.Position)
		end
	end)
end

-- Gives (or refreshes) the hub knife; nothing while in a round
function CombatService.Arm(player: Player, equip: boolean?)
	local character = player.Character
	-- Not in rounds, and not while both hands hold a stolen knife over your head
	if not character or player:GetAttribute("InRound") or player:GetAttribute("Carrying") then
		return
	end
	local name = CombatService.WieldedKnife(player)
	local existing = currentTool(player)
	if existing and existing:GetAttribute(HUB_KNIFE) == name then
		-- Already the right knife: just make sure it's in hand when asked
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if equip and existing.Parent ~= character and humanoid then
			humanoid:EquipTool(existing)
		end
		return
	end
	local wasHeld = existing ~= nil and existing.Parent == character
	if existing then
		existing:Destroy()
	end
	local tool = KnifeModel.BuildTool(name)
	tool:SetAttribute(HUB_KNIFE, name)
	tool.Activated:Connect(function()
		swing(player, tool)
	end)
	local backpack = player:FindFirstChildOfClass("Backpack")
	tool.Parent = if wasHeld or equip then character else backpack
	Net.Remotes.AbilityState:FireClient(player, "Throw Knife", throwReadyAt[player] or 0)
end

function CombatService.Disarm(player: Player)
	local tool = currentTool(player)
	if tool then
		tool:Destroy()
		-- ...and its Throw button goes with it (RoundService hands the Murderer their own later)
		Net.Remotes.AbilityState:FireClient(player, nil)
	end
end

-- Winding up: the character's ChargeStart attribute (server time) drives everyone's view of the
-- crank-back, and how long it was held decides the throw's power
local function onCharge(player: Player, charging: unknown)
	local character = player.Character
	if not character then
		return
	end
	if charging == true and character:FindFirstChildOfClass("Tool") and rootOf(player) then
		if character:GetAttribute("ChargeStart") == nil then
			character:SetAttribute("ChargeStart", workspace:GetServerTimeNow())
			character:SetAttribute("ChargeTime", AnimLibrary.ChargeTime)
		end
	else
		character:SetAttribute("ChargeStart", nil)
	end
end

-- How charged the throw was (0.25 for a quick flick, 1 for fully cranked); clears the charge
function CombatService.TakeCharge(player: Player): number
	local character = player.Character
	local start = character and character:GetAttribute("ChargeStart")
	if character then
		character:SetAttribute("ChargeStart", nil)
	end
	if type(start) ~= "number" then
		return 0.25
	end
	return math.clamp((workspace:GetServerTimeNow() - start) / AnimLibrary.ChargeTime, 0.25, 1)
end

-- Where a thrown knife leaves from: the right hand, or the chest if there isn't one
-- Where a thrown knife leaves from: the throwing hand at shoulder height, just ahead of the body.
-- The server sees players a little in the past, so a sprinting thrower is led by their speed x ping
-- (otherwise the knife would start behind them on their own screen).
function CombatService.HandPosition(player: Player): Vector3?
	local root = rootOf(player)
	if not root then
		return nil
	end
	local from = (root.CFrame * CFrame.new(1, 1.4, -1.6)).Position
	local velocity = root.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	return from + flat * math.clamp(player:GetNetworkPing() + 0.08, 0.05, 0.35)
end

-- Thrown knives (hub): straight line from the hand, hits the first guard it passes through
local function throw(player: Player, aim: unknown)
	if player:GetAttribute("InRound") then
		return -- rounds have their own abilities (RoundService)
	end
	local now = workspace:GetServerTimeNow()
	local root = rootOf(player)
	local tool = currentTool(player)
	local character = player.Character
	if not root or not tool or not character or now < (throwReadyAt[player] or 0) then
		CombatService.TakeCharge(player)
		return
	end
	local direction = root.CFrame.LookVector
	if typeof(aim) == "Vector3" then
		local v = aim :: Vector3
		if v == v and v.Magnitude > 0.01 and v.Magnitude < 1e4 then
			direction = v.Unit
		end
	end
	local charge = CombatService.TakeCharge(player)
	local config = GameConfig.HubThrow
	throwReadyAt[player] = now + math.max(config.Cooldown, GameConfig.ThrowMinInterval)
	Net.Remotes.AbilityState:FireClient(player, "Throw Knife", throwReadyAt[player])
	Net.Animate(character, "Throw", player)

	local name = tool:GetAttribute(HUB_KNIFE) :: string
	local baseDamage = Items.Damage(name)
	-- The knife leaves the hand on the Release frame of the throw
	task.delay(AnimLibrary.Clips.Throw.Release or 0.07, function()
		local from = CombatService.HandPosition(player)
		if not from then
			return
		end
		local model = KnifeModel.Build(name, true)
		KnifeModel.FitLength(model, 1.9) -- thrown knives match the held size
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanQuery = false
			elseif d:IsA("Trail") then
				d.Enabled = true -- streak behind it all the way
			end
		end
		model.Parent = flyingFolder
		Net.Remotes.Effect:FireAllClients("KnifeThrow", from)
		table.insert(flying, {
			Model = model,
			Owner = player,
			Position = from,
			Direction = direction,
			Traveled = 0,
			Speed = 55 + 60 * charge,
			Damage = math.floor(baseDamage * (1 + (config.DamageMultiplier - 1) * charge)),
		})
		Net.Remotes.Effect:FireAllClients("Dash", from)
	end)
end

local function stepFlying(dt: number)
	local config = GameConfig.HubThrow
	for i = #flying, 1, -1 do
		local f = flying[i]
		local stepLength = f.Speed * dt
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore: { Instance } = { flyingFolder }
		if f.Owner.Character then
			table.insert(ignore, f.Owner.Character)
		end
		params.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(f.Position, f.Direction * stepLength, params)
		-- Invisible blockers (vault gates and side walls, trusses...) aren't walls you can see: fly
		-- through them, unless they're something you can actually hit (a gate during a break-in)
		for _ = 1, 4 do
			local part = hit and hit.Instance
			if
				not part
				or part.Transparency < 0.99
				or GuardService.FromPart(part)
				or Targets.FromPart(f.Owner, part)
			then
				break
			end
			table.insert(ignore, part)
			params.FilterDescendantsInstances = ignore
			hit = workspace:Raycast(f.Position, f.Direction * stepLength, params)
		end
		local done = false
		-- Knockable players and other soft targets along the way (the ray passes through characters)
		local passed = Targets.AlongPath(f.Owner, f.Position, f.Position + f.Direction * stepLength, 2.2)
		if passed and not passed.Solid then
			passed.Hit(f.Owner, f.Damage, "Throw", f.Position)
			done = true
		elseif hit then
			local guard = GuardService.FromPart(hit.Instance)
			local target = if guard then nil else Targets.FromPart(f.Owner, hit.Instance)
			if guard then
				GuardService.Damage(guard, f.Damage, f.Owner)
			elseif target then
				target.Hit(f.Owner, f.Damage, "Throw", f.Position)
			end
			-- Other players are ghosts to hub knives; anything else stops it
			done = Players:GetPlayerFromCharacter(hit.Instance:FindFirstAncestorOfClass("Model")) == nil
		end
		-- Hit a wall (not a guard, target or person): it sticks there for a minute
		if
			done
			and hit
			and not passed
			and not GuardService.FromPart(hit.Instance)
			and not Targets.FromPart(f.Owner, hit.Instance)
		then
			StuckKnives.Stick(f.Model, hit.Position, f.Direction, 60)
			table.remove(flying, i)
			continue
		end
		f.Position += f.Direction * stepLength
		f.Traveled += stepLength
		if done or f.Traveled > config.Range then
			f.Model:Destroy()
			table.remove(flying, i)
		else
			f.Model:PivotTo(
				CFrame.lookAt(f.Position, f.Position + f.Direction) * CFrame.Angles(-f.Traveled * 0.5, 0, 0)
			)
		end
	end
end

-- Max health from the Health level (cash upgrade) and the Titan pass. Topping up keeps the same
-- fraction of health you had, so buying mid-fight doesn't heal you outright.
function CombatService.ApplyHealth(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local level = (player:GetAttribute("HealthLevel") or 0) :: number
	local max = GameConfig.MaxHealthFor(level, if player:GetAttribute("Pass_Titan") then 2 else 1)
	if player:GetAttribute("InRound") then
		max = GameConfig.Health.Base -- rounds are fair: everyone is equal
	end
	if humanoid.MaxHealth ~= max then
		local fraction = humanoid.Health / math.max(humanoid.MaxHealth, 1)
		humanoid.MaxHealth = max
		humanoid.Health = math.max(1, max * fraction)
	end
end

-- Deaths: go limp, cry out, collapse. Players respawn at their vault as usual.
local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	task.defer(function()
		local level = (player:GetAttribute("HealthLevel") or 0) :: number
		local max = GameConfig.MaxHealthFor(level, if player:GetAttribute("Pass_Titan") then 2 else 1)
		if not player:GetAttribute("InRound") and humanoid.Health > 0 then
			humanoid.MaxHealth = max
			humanoid.Health = max
		end
	end)
	humanoid.BreakJointsOnDeath = false
	humanoid.Died:Connect(function()
		Analytics.Track(player, "death", { where = if player:GetAttribute("InRound") then "round" else "hub" })
		Ragdoll.DeathCry(character)
		Ragdoll.Collapse(character, nil)
		Net.Remotes.Effect:FireClient(player, "Died")
		-- Auto-loading is off (see Main), so respawn here once the body has had time to fall
		task.delay(Players.RespawnTime, function()
			if player.Parent and player.Character == character then
				BaseService.LoadCharacter(player) -- (streams the spawn in first)
			end
		end)
	end)
	task.defer(CombatService.Arm, player)
end

function CombatService.Init()
	flyingFolder = Instance.new("Folder")
	flyingFolder.Name = "ThrownKnives"
	flyingFolder.Parent = workspace

	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
		-- Re-arm when the equipped knife / collection changes, and around rounds
		-- Equipping a knife puts it straight in your hands; a changed collection just swaps it
		player:GetAttributeChangedSignal("Equipped"):Connect(function()
			CombatService.Arm(player, true)
		end)
		player:GetAttributeChangedSignal("Knives"):Connect(function()
			CombatService.Arm(player)
		end)
		player:GetAttributeChangedSignal("HoldingHatch"):Connect(function()
			CombatService.Arm(player, player:GetAttribute("HoldingHatch") ~= nil)
		end)
		-- Hands full while carrying a stolen knife; your own knife comes back once you're home
		player:GetAttributeChangedSignal("Carrying"):Connect(function()
			if player:GetAttribute("Carrying") then
				CombatService.TakeCharge(player)
				CombatService.Disarm(player)
				Net.Remotes.AbilityState:FireClient(player, nil)
			else
				CombatService.Arm(player, true)
			end
		end)
		player:GetAttributeChangedSignal("InRound"):Connect(function()
			if player:GetAttribute("InRound") then
				CombatService.Disarm(player)
			else
				CombatService.Arm(player)
			end
			CombatService.ApplyHealth(player)
		end)
		for _, attribute in { "HealthLevel", "Pass_Titan" } do
			player:GetAttributeChangedSignal(attribute):Connect(function()
				CombatService.ApplyHealth(player)
			end)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
		combo[player] = nil
		throwReadyAt[player] = nil
	end)

	Net.Remotes.Ability.OnServerEvent:Connect(throw)
	Net.Remotes.Charge.OnServerEvent:Connect(onCharge)
	RunService.Heartbeat:Connect(stepFlying)
end

return CombatService
