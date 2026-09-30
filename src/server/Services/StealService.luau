--!strict
-- Stealing knives from arena pedestals and carrying them home. The client only presses a
-- ProximityPrompt; the server checks everything (distance, state, rack space) and decides
-- when a knife is deposited, based on where the server sees the character.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)

type Pedestal = {
	Part: BasePart,
	Zone: MapService.Zone,
	Prompt: ProximityPrompt,
	Knife: string?,
	Display: Model?,
}

type Carry = {
	Knife: string,
	Pedestal: Pedestal,
	Visual: Model,
	LastPos: Vector3,
	LastCheck: number,
}

local StealService = {}

local carriers: { [Player]: Carry } = {}

local function rootPart(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function fillPedestal(pedestal: Pedestal)
	local pool = Knives.ByRarity[pedestal.Zone.Rarity]
	local knife = pool[math.random(1, #pool)]
	pedestal.Knife = knife.Name
	local display = KnifeModel.Build(knife.Name, true)
	display:PivotTo(pedestal.Part.CFrame * CFrame.new(0, 3.2, 0) * CFrame.Angles(0, 0, math.rad(15)))
	display.Parent = pedestal.Part
	pedestal.Display = display
	pedestal.Prompt.ObjectText = `{knife.DisplayName} ({knife.Rarity}) - ${knife.Income}/s`
	pedestal.Prompt.Enabled = true
end

local function emptyPedestal(pedestal: Pedestal)
	if pedestal.Display then
		pedestal.Display:Destroy()
		pedestal.Display = nil
	end
	pedestal.Knife = nil
	pedestal.Prompt.Enabled = false
end

-- Ends a carry. deposited = knife made it home; otherwise it goes straight back on its pedestal.
local function endCarry(player: Player, deposited: boolean)
	local carry = carriers[player]
	if not carry then
		return
	end
	carriers[player] = nil
	carry.Visual:Destroy()
	player:SetAttribute("Carrying", nil)
	BaseService.RefreshWalkSpeed(player)
	if deposited then
		task.delay(GameConfig.KnifeRespawnTime, fillPedestal, carry.Pedestal)
	else
		fillPedestal(carry.Pedestal)
	end
end

local function startCarry(player: Player, pedestal: Pedestal)
	local character = player.Character :: Model
	local head = character:FindFirstChild("Head") :: BasePart?
	local root = rootPart(player)
	if not head or not root or not pedestal.Knife then
		return
	end

	local knifeName = pedestal.Knife
	emptyPedestal(pedestal)

	-- Hold it up over the head so everyone can see who has what
	local visual = KnifeModel.Build(knifeName, false)
	for _, p in visual:GetDescendants() do
		if p:IsA("BasePart") then
			p.Massless = true
		end
	end
	visual:PivotTo(head.CFrame * CFrame.new(0, 2.5, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = visual.PrimaryPart :: BasePart
	weld.Parent = visual
	visual.Parent = character

	carriers[player] =
		{ Knife = knifeName, Pedestal = pedestal, Visual = visual, LastPos = root.Position, LastCheck = os.clock() }
	player:SetAttribute("Carrying", knifeName)
	BaseService.RefreshWalkSpeed(player)
	local knife = Knives.ByName[knifeName]
	Net.Notify(player, `You grabbed a {knife.DisplayName}! Run home before a guard catches you!`, "good")
end

local function onStealTriggered(player: Player, pedestal: Pedestal)
	local root = rootPart(player)
	local profile = DataService.Get(player)
	if not root or not profile or not pedestal.Knife then
		return
	end
	if player:GetAttribute("InRound") or carriers[player] then
		return
	end
	if (root.Position - pedestal.Part.Position).Magnitude > pedestal.Prompt.MaxActivationDistance + 6 then
		return -- prompt fired from too far away: exploit or lag, ignore either way
	end
	if not BaseService.GetBase(player) then
		Net.Notify(player, "No free vault on this server, you can't store knives.", "bad")
		return
	end
	if #profile.Knives >= profile.Slots then
		Net.Notify(player, "Your rack is full! Buy more slots to steal more knives.", "bad")
		return
	end
	startCarry(player, pedestal)
end

local function deposit(player: Player)
	local carry = carriers[player]
	if not carry then
		return
	end
	local profile = DataService.Get(player)
	if not profile or #profile.Knives >= profile.Slots then
		endCarry(player, false)
		return
	end
	local knifeName = carry.Knife
	DataService.Update(player, function(p)
		table.insert(p.Knives, knifeName)
	end)
	endCarry(player, true)
	BaseService.RefreshRack(player)
	local knife = Knives.ByName[knifeName]
	Net.Notify(player, `{knife.DisplayName} is safe in your vault! +${knife.Income}/s`, "good")
end

-- Deposits and the carrier speed check run on the server's view of positions
local function tick()
	local now = os.clock()
	for player, carry in carriers do
		local root = rootPart(player)
		if not root then
			endCarry(player, false)
			continue
		end
		local pos = root.Position
		if BaseService.IsInOwnBase(player, pos) then
			deposit(player)
			continue
		end
		local elapsed = now - carry.LastCheck
		if elapsed >= 0.5 then
			local humanoid = (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
			local flat = Vector3.new(pos.X - carry.LastPos.X, 0, pos.Z - carry.LastPos.Z).Magnitude
			local allowed = humanoid.WalkSpeed * elapsed * GameConfig.SpeedTolerance + 3
			if flat > allowed then
				warn(
					`[StealService] {player.Name} moved {math.floor(flat)} studs in {elapsed}s while carrying, dropping knife`
				)
				Net.Notify(player, "Whoa, too fast! The knife slipped out of your hands.", "bad")
				endCarry(player, false)
				continue
			end
			carry.LastPos = pos
			carry.LastCheck = now
		end
	end
end

function StealService.GetCarriers(): { [Player]: Carry }
	return carriers
end

-- A guard caught them: knife goes back, they get sent home
function StealService.Catch(player: Player)
	if not carriers[player] then
		return
	end
	endCarry(player, false)
	BaseService.TeleportHome(player)
	Net.Notify(player, "A guard caught you! The knife went back on its pedestal.", "bad")
end

-- Rounds pull everyone out of the arena; whatever they carried goes back
function StealService.ForceDrop(player: Player)
	endCarry(player, false)
end

function StealService.Init()
	for _, zone in MapService.Zones do
		for _, part in zone.Pedestals do
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Steal"
			prompt.HoldDuration = GameConfig.StealHoldDuration
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.Parent = part
			local pedestal: Pedestal = { Part = part, Zone = zone, Prompt = prompt }
			prompt.Triggered:Connect(function(player)
				onStealTriggered(player, pedestal)
			end)
			fillPedestal(pedestal)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		endCarry(player, false)
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.1 then
			accumulator = 0
			tick()
		end
	end)
end

return StealService
