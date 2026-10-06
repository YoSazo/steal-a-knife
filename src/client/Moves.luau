--!strict
-- Client animation engine. Every frame, after Roblox's Animator has posed each character (walk,
-- run, idle), this layers our procedural clips on top by multiplying each joint's Transform.
-- Works on players and guards alike, on Motor6D and AnimationConstraint rigs.
--
-- What plays comes from:
--   * Remotes.Anim (server -> everyone): one-shot clips like stabs, hurts, cheers
--   * Moves.Play (local prediction): your own swings start the instant you click
--   * state that lasts: a character's ChargeStart attribute (winding up a throw), its player's
--     Carrying attribute (knife over the head), holding the Revolver, and guards' idle fidgets
-- Knife trails on the held knife switch on during the part of a clip that swings it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimLibrary = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AnimLibrary"))
local Lod = require(script.Parent.Lod)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local localPlayer = Players.LocalPlayer

local Moves = {}

type Playing = { Clip: AnimLibrary.Clip, Name: string, Start: number }
type Rig = {
	Joints: { [string]: Instance }, -- Motor6D or AnimationConstraint, by name
	Playing: { Playing },
	-- What we wrote last frame, so joints the Animator didn't touch don't accumulate our offsets
	LastBase: { [Instance]: CFrame },
	LastWritten: { [Instance]: CFrame },
	Seed: number,
	TrailOn: boolean,
	LoopWeight: number, -- current blend of held poses (carry / aim)
}

-- Holding a Tool, the default Animate script raises the right arm ~84 degrees forward. Our poses are
-- designed from a hanging arm, so while one plays we blend that raise back out.
local TOOL_HOLD_UNDO = CFrame.Angles(math.rad(84), math.rad(12), math.rad(6)):Inverse()
local LOOP_BLEND = 0.12 -- seconds for held poses (carry, aim) to blend in and out

local rigs: { [Model]: Rig } = {}
local tracked: { [Model]: boolean } = {} -- models we animate (rigs build once their joints exist)

local function getRig(model: Model): Rig?
	local rig = rigs[model]
	if rig and rig.Joints.RightShoulder:IsDescendantOf(model) then
		return rig
	end
	rigs[model] = nil -- never built, or its joints were replaced
	if not model:FindFirstChildOfClass("Humanoid") then
		return nil
	end
	local joints: { [string]: Instance } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then
			joints[d.Name] = d
		end
	end
	if not joints.RightShoulder then
		return nil -- still streaming in; try again next frame
	end
	local built: Rig = {
		Joints = joints,
		Playing = {},
		LastBase = {},
		LastWritten = {},
		Seed = math.random() * 100,
		TrailOn = false,
		LoopWeight = 0,
	}
	rigs[model] = built
	local connections: { RBXScriptConnection } = {}
	-- Round disguises (ApplyDescription) swap body parts, which replaces the joints: rebuild the
	-- rig next frame, keeping whatever clip is playing
	table.insert(
		connections,
		model.DescendantAdded:Connect(function(d)
			if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and rigs[model] == built then
				rigs[model] = nil
				for _, c in connections do
					c:Disconnect()
				end
				local rebuilt = getRig(model)
				if rebuilt then
					rebuilt.Playing = built.Playing
					rebuilt.Seed = built.Seed
				end
			end
		end)
	)
	table.insert(
		connections,
		model.Destroying:Connect(function()
			rigs[model] = nil
			tracked[model] = nil
		end)
	)
	return built
end

-- The knife trail on whatever knife this model is holding (hub tool, murderer tool, guard knife)
local function setTrail(model: Model, on: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("Trail") and d.Name == "KnifeTrail" then
			d.Enabled = on
		end
	end
end

function Moves.Play(model: Model, name: string)
	local clip = AnimLibrary.Clips[name]
	tracked[model] = true
	local rig = getRig(model)
	if not clip or not rig then
		return
	end
	-- One-shots replace each other (a new swing cuts the last one short)
	table.clear(rig.Playing)
	table.insert(rig.Playing, { Clip = clip, Name = name, Start = os.clock() })
end

-- Your own character's charge starts locally, before the server has heard about it
local localChargeStart: number? = nil
function Moves.SetLocalCharge(start: number?)
	localChargeStart = start
end

local function addPose(total: { [string]: Vector3 }, pose: AnimLibrary.Pose, weight: number)
	for joint, value in pose do
		total[joint] = (total[joint] or Vector3.zero) + value * weight
	end
end

local function heldTool(model: Model): Tool?
	return model:FindFirstChildOfClass("Tool")
end

-- 0 -> 1 -> 0 over a clip, so poses ease in from and back out to whatever the Animator is doing
local function envelope(t: number, length: number): number
	return math.clamp(math.min(t / 0.07, (length - t) / 0.12), 0, 1)
end

local function step(dt: number)
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	for model in tracked do
		if not model.Parent then
			rigs[model] = nil
			tracked[model] = nil
			continue
		end
		local rig = getRig(model)
		if not rig then
			continue
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue -- ragdolls are physics now
		end
		-- Too far away to see the detail (LOD): leave it to the Animator. Our own character always
		-- animates. Whatever we'd written gets overwritten by the Animator next frame.
		if model ~= localPlayer.Character and #rig.Playing == 0 then
			local root = model.PrimaryPart
			if root and not Lod.Near(root.Position) then
				table.clear(rig.LastWritten)
				table.clear(rig.LastBase)
				continue
			end
		end
		local total: { [string]: Vector3 } = {}
		local trail = false
		local undo = 0 -- how much of the tool-hold arm raise to take out this frame

		-- One-shot clips
		for i = #rig.Playing, 1, -1 do
			local playing = rig.Playing[i]
			local t = now - playing.Start
			if t >= playing.Clip.Length then
				table.remove(rig.Playing, i)
				continue
			end
			addPose(total, AnimLibrary.Sample(playing.Clip, t), 1)
			undo = math.max(undo, envelope(t, playing.Clip.Length))
			local window = playing.Clip.Trail
			if window and t >= window[1] and t <= window[2] then
				trail = true
			end
		end
		local busy = #rig.Playing > 0

		-- Winding up a throw (players and guards): crank back over ChargeTime, then tremble
		local chargeStart: number? = nil
		if model == localPlayer.Character then
			chargeStart = localChargeStart
		else
			local attr = model:GetAttribute("ChargeStart")
			if type(attr) == "number" then
				-- Server time -> seconds charged so far
				chargeStart = now - (serverNow - attr)
			end
		end
		if chargeStart and not busy then
			local chargeTime = (model:GetAttribute("ChargeTime") or AnimLibrary.ChargeTime) :: number
			local fraction = math.clamp((now - chargeStart) / chargeTime, 0, 1)
			local pose = AnimLibrary.Sample(AnimLibrary.Clips.Charge, fraction)
			if fraction >= 1 then
				-- Fully cranked: a little shake says "let go!"
				local shake = math.sin(now * 55 + rig.Seed) * 2.5
				pose.RightShoulder = (pose.RightShoulder or Vector3.zero) + Vector3.new(shake, 0, shake * 0.5)
			end
			addPose(total, pose, 1)
			undo = math.max(undo, math.min(1, fraction * 5))
		end

		-- Held states
		local player = Players:GetPlayerFromCharacter(model)
		local loop: AnimLibrary.Pose? = nil
		if not busy and not chargeStart then
			if (player and player:GetAttribute("Carrying")) or model:GetAttribute("Carrying") then
				local bob = math.sin(now * 6 + rig.Seed) * 4
				local carry = table.clone(AnimLibrary.Loops.Carry)
				carry.RightShoulder += Vector3.new(bob, 0, 0)
				carry.LeftShoulder += Vector3.new(-bob, 0, 0)
				loop = carry
			elseif player and player:GetAttribute("Training") then
				-- Running up the rungs of the Haunted Wheel: legs and arms pump faster on better wheels,
				-- steeply (x1.3 a tier) so the top wheels are a blur - past ~10 strides a second the
				-- frame rate makes the legs look like they run backwards (Steal An Egg's top treadmill).
				-- Better wheels also lean you further into it and swing the limbs wider.
				local level = (player:GetAttribute("TreadmillLevel") or 1) :: number
				local t = math.clamp((level - 1) / 12, 0, 1)
				local phase = now * 11 * 1.3 ^ (level - 1) + rig.Seed
				local swing = math.sin(phase)
				local legs = 45 + t * 20
				local arms = 50 + t * 25
				loop = {
					RightHip = Vector3.new(swing * legs, 0, 0),
					LeftHip = Vector3.new(-swing * legs, 0, 0),
					RightKnee = Vector3.new(-25 - math.max(0, swing) * legs, 0, 0),
					LeftKnee = Vector3.new(-25 - math.max(0, -swing) * legs, 0, 0),
					RightShoulder = Vector3.new(-swing * arms, 0, 0),
					LeftShoulder = Vector3.new(swing * arms, 0, 0),
					RightElbow = Vector3.new(60 + t * 25, 0, 0),
					LeftElbow = Vector3.new(60 + t * 25, 0, 0),
					Waist = Vector3.new(8 + t * 22, 0, 0),
					Neck = Vector3.new(-t * 12, 0, 0), -- head up, looking ahead while leaning in
					RootMove = Vector3.new(0, math.abs(math.cos(phase)) * (0.3 - t * 0.15), 0),
				}
			else
				local tool = heldTool(model)
				if tool and tool:GetAttribute("Revolver") then
					loop = AnimLibrary.Loops.Aim
				end
			end
		end
		-- Held poses blend in and out instead of snapping
		local goal = if loop then 1 else 0
		rig.LoopWeight += math.clamp(goal - rig.LoopWeight, -dt / LOOP_BLEND, dt / LOOP_BLEND)
		if loop and rig.LoopWeight > 0 then
			addPose(total, loop, rig.LoopWeight)
			undo = math.max(undo, rig.LoopWeight)
		end

		-- Guards fidget while nothing else is happening: look around, lantern swings, breathing
		if CollectionService:HasTag(model, "ShopNPC") and not busy then
			-- Shopkeepers: lean on the counter, gesture, look around at the customers
			local s = rig.Seed
			addPose(total, {
				Neck = Vector3.new(math.sin(now * 0.7 + s) * 8, math.sin(now * 0.5 + s) * 30, 0),
				LeftShoulder = Vector3.new(40 + math.sin(now * 1.3 + s) * 25, 0, -10),
				LeftElbow = Vector3.new(50 + math.sin(now * 2.1 + s) * 20, 0, 0),
				RightShoulder = Vector3.new(30 + math.sin(now * 1.1 + s + 1) * 15, 0, 10),
				RightElbow = Vector3.new(45, 0, 0),
				Waist = Vector3.new(6 + math.sin(now * 1.4 + s) * 3, math.sin(now * 0.6 + s) * 10, 0),
			}, 1)
		end
		-- Bosses doze in their chair (GuardService setAsleep), and getting up / sitting down are acted
		-- out (Steal An Egg's chicken wakes before it moves). WakeAt..WakeEnd, as a share p of it:
		--   0-0.2   the head snaps up, eyes open (still slumped in the chair)
		--   0.2-0.45 hands grip the armrests, looking around
		--   0.45-0.65 lean forward and push up off the seat
		--   0.65-0.85 stand up while the server slides them forward out of the chair
		-- SitAt..SitEnd (back home) plays the same thing backwards.
		local seated, push, dozing = 0, 0, 0
		if CollectionService:HasTag(model, "Guard") then
			if model:GetAttribute("Asleep") then
				seated, dozing = 1, 1
			else
				local wakeAt, wakeEnd = model:GetAttribute("WakeAt"), model:GetAttribute("WakeEnd")
				local sitAt, sitEnd = model:GetAttribute("SitAt"), model:GetAttribute("SitEnd")
				local p: number? = nil
				if type(wakeAt) == "number" and type(wakeEnd) == "number" and serverNow < wakeEnd then
					p = math.clamp((serverNow - wakeAt) / math.max(wakeEnd - wakeAt, 0.1), 0, 1)
				elseif type(sitAt) == "number" and type(sitEnd) == "number" and serverNow < sitEnd + 0.5 then
					-- (backwards: 1 = still standing in front of the chair, 0 = sat down)
					p = 0.85 * (1 - math.clamp((serverNow - sitAt) / math.max(sitEnd - sitAt, 0.1), 0, 1))
					dozing = 0
				end
				if p then
					local function ease(x: number): number
						x = math.clamp(x, 0, 1)
						return x * x * (3 - 2 * x)
					end
					if type(wakeAt) == "number" and serverNow < (wakeEnd :: number) then
						dozing = 1 - ease(p / 0.2)
					end
					if p < 0.45 then
						seated = 1
					elseif p < 0.65 then
						local u = ease((p - 0.45) / 0.2)
						seated, push = 1 - u, u
					else
						push = 1 - ease((p - 0.65) / 0.2)
					end
				end
			end
		end
		if (seated > 0 or push > 0) and not chargeStart then
			local breath = math.sin(now * 1.6 + rig.Seed) * dozing
			local awake = 1 - dozing
			-- Startled once awake: glancing left and right while gripping the armrests
			local glance = math.sin(now * 5 + rig.Seed) * 25 * awake
			-- Asleep: slouched back (sat forward on the deep seat, knees over its front edge, feet on the
			-- footstool: GuardService), head lolled forward to one side, forearms on the armrests.
			-- Awake: sitting up, gripping the armrests.
			local sit: AnimLibrary.Pose = {
				RootMove = Vector3.new(0, 0.2, 0),
				LeftHip = Vector3.new(90, 0, -4),
				RightHip = Vector3.new(90, 0, 4),
				LeftKnee = Vector3.new(-72, 0, 0),
				RightKnee = Vector3.new(-72, 0, 0),
				Waist = Vector3.new(24 * dozing - breath * 2 + 6 * awake, 0, 0),
				Neck = Vector3.new(-44 * dozing - breath * 3 + 6 * awake, glance, 24 * dozing),
				LeftShoulder = Vector3.new(30 * awake, 0, 10 * dozing - 16 * awake),
				RightShoulder = Vector3.new(30 * awake, 0, -10 * dozing + 16 * awake),
				LeftElbow = Vector3.new(70 * dozing + 50 * awake, 0, 0),
				RightElbow = Vector3.new(70 * dozing + 50 * awake, 0, 0),
			}
			addPose(total, sit, seated)
			-- Pushing up off the seat: hips and knees half bent, leaning well forward, hands down
			addPose(total, {
				RootMove = Vector3.new(0, 0.1, 0),
				LeftHip = Vector3.new(55, 0, 0),
				RightHip = Vector3.new(55, 0, 0),
				LeftKnee = Vector3.new(-50, 0, 0),
				RightKnee = Vector3.new(-50, 0, 0),
				Waist = Vector3.new(-28, 0, 0),
				Neck = Vector3.new(18, 0, 0),
				LeftShoulder = Vector3.new(15, 0, -12),
				RightShoulder = Vector3.new(15, 0, 12),
				LeftElbow = Vector3.new(25, 0, 0),
				RightElbow = Vector3.new(25, 0, 0),
			}, push)
		elseif CollectionService:HasTag(model, "Guard") and not busy and not chargeStart then
			local s = rig.Seed
			addPose(total, {
				Neck = Vector3.new(math.sin(now * 0.9 + s) * 6, math.sin(now * 0.45 + s) * 35, 0),
				LeftShoulder = Vector3.new(15 + math.sin(now * 2.2 + s) * 10, 0, math.sin(now * 1.7 + s) * 6),
				LeftElbow = Vector3.new(20, 0, 0),
				RightShoulder = Vector3.new(20, 0, 8), -- knife held ready
				RightElbow = Vector3.new(35, 0, 0),
				Waist = Vector3.new(math.sin(now * 1.6 + s) * 2, 0, 0),
			}, 1)
		end

		if trail ~= rig.TrailOn then
			rig.TrailOn = trail
			setTrail(model, trail)
		end

		-- Apply on top of whatever the Animator wrote this frame
		for name, joint in rig.Joints do
			local angles = total[name]
			local move = if name == "Root" then total.RootMove else nil
			local current = (joint :: any).Transform :: CFrame
			local base = current
			if rig.LastWritten[joint] and current == rig.LastWritten[joint] then
				base = rig.LastBase[joint] -- the Animator didn't touch it; don't stack our offset
			end
			if angles or move then
				local offset = AnimLibrary.ToCFrame(angles or Vector3.zero, move)
				if name == "RightShoulder" and heldTool(model) and undo > 0 then
					offset = CFrame.new():Lerp(TOOL_HOLD_UNDO, undo) * offset
				end
				local result = base * offset;
				(joint :: any).Transform = result
				rig.LastBase[joint] = base
				rig.LastWritten[joint] = result
			elseif rig.LastWritten[joint] then
				(joint :: any).Transform = base
				rig.LastWritten[joint] = nil
				rig.LastBase[joint] = nil
			end
		end
	end
end

local function track(model: Instance)
	if model:IsA("Model") then
		tracked[model] = true
	end
end

function Moves.Init()
	-- Everyone's character, and every guard
	local function watchPlayer(player: Player)
		if player.Character then
			track(player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 10)
			track(character)
		end)
	end
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, guard in CollectionService:GetTagged("Guard") do
		track(guard)
	end
	CollectionService:GetInstanceAddedSignal("Guard"):Connect(function(guard)
		track(guard)
	end)
	-- Round bots (Studio bot rounds) and raid burglars
	for _, tag in { "RoundBot", "Burglar", "ShopNPC" } do
		for _, model in CollectionService:GetTagged(tag) do
			track(model)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(track)
	end

	Remotes:WaitForChild("Anim").OnClientEvent:Connect(function(model: Model, name: string)
		if model and model.Parent then
			Moves.Play(model, name)
		end
	end)

	-- PreSimulation runs after the Animator has written this frame's pose
	RunService.PreSimulation:Connect(step)
end

return Moves
