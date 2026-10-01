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
local DataService = require(script.Parent.DataService)
local GuardService = require(script.Parent.GuardService)
local Ragdoll = require(script.Parent.Ragdoll)
local Targets = require(script.Parent.Targets)

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

-- The knife you fight with: the equipped one if you still own it, else your best, else the starter
function CombatService.WieldedKnife(player: Player): string
	local profile = DataService.Get(player)
	if not profile then
		return GameConfig.StarterKnife
	end
	if profile.Equipped ~= "" and table.find(profile.Knives, profile.Equipped) then
		return profile.Equipped
	end
	local best, bestDamage = GameConfig.StarterKnife, -1
	for _, item in profile.Knives do
		local damage = Items.Damage(item)
		if damage > bestDamage then
			best, bestDamage = item, damage
		end
	end
	return best
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
function CombatService.HandPosition(player: Player): Vector3?
	local character = player.Character
	local hand = character and character:FindFirstChild("RightHand") :: BasePart?
	local root = rootOf(player)
	if hand then
		return hand.Position
	end
	return if root then root.Position + Vector3.new(0, 1.2, 0) else nil
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
		KnifeModel.FitLength(model, 2.6)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanQuery = false
			elseif d:IsA("Trail") then
				d.Enabled = true -- streak behind it all the way
			end
		end
		model.Parent = flyingFolder
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

-- Deaths: go limp, cry out, collapse. Players respawn at their vault as usual.
local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.BreakJointsOnDeath = false
	humanoid.Died:Connect(function()
		Ragdoll.DeathCry(character)
		Ragdoll.Collapse(character, nil)
		Net.Remotes.Effect:FireClient(player, "Died")
		-- Auto-loading is off (see Main), so respawn here once the body has had time to fall
		task.delay(Players.RespawnTime, function()
			if player.Parent and player.Character == character then
				player:LoadCharacterAsync()
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
		for _, attribute in { "Equipped", "Knives" } do
			player:GetAttributeChangedSignal(attribute):Connect(function()
				CombatService.Arm(player)
			end)
		end
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
		end)
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
