--!strict
-- The first minutes, for new players, Steal An Egg style: red arrows on the ground running from you
-- to where you need to go, a bouncing arrow over the spot, and one short line of text in a slim
-- see-through bar under the timer (never a big box over the game). Learn by doing:
--   1. steal a knife off Frank's wall    2. run it home and place it (caught? back to 1)
--   3. collect its cash pad               4. run in your wheel (Speed = deeper biomes)
-- then the "Your knife's power" showcase. (Upgrades and Equip steps were cut: only 2 of 11 new
-- players got through them; Upgrades is found anyway, and your best knife is auto-equipped.)
-- Progress is saved (player TutorialStep), so leaving midway resumes there. More > How to play
-- replays it (Ui.ReplayTutorial). The murder rounds and everything later are taught by one-time
-- tips at the moment they happen (client/Tips). Placement is confirmed by the server, rather
-- than inferred from the timing of inventory and carrying attribute changes.
-- Finishing (or skipping) tells the server, which pays a small reward once (Rewards).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
-- Room at each end of the top line for its fade to nothing
local FADE = 60

local Ui = require(script.Parent.Ui)
local Effects = require(script.Parent.Effects)
local PowerShowcase = require(script.Parent.PowerShowcase)
local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Sounds"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local new = Ui.new

local Tutorial = {}

type Step = { Text: string, Target: () -> Vector3?, Done: () -> boolean }

local function root(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function nearestGuard(): Vector3?
	local here = root()
	if not here then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for _, guard in CollectionService:GetTagged("Guard") do
		local r = (guard :: Model).PrimaryPart
		-- Courtyard guards only (the first zone)
		if r and r.Position.Z < 220 and r.Position.Z > 0 then
			local distance = (r.Position - here.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = r.Position, distance
			end
		end
	end
	return best
end

local function myVault(): Model?
	local index = player:GetAttribute("VaultIndex")
	local map = workspace:FindFirstChild("Map")
	local bases = map and map:FindFirstChild("Bases")
	return bases and bases:FindFirstChild(`Base{index}`) :: Model?
end

local function vaultDoor(): Vector3?
	local vault = myVault()
	local floor = vault and vault:FindFirstChild("Floor") :: BasePart?
	return floor and floor.Position
end

-- The cash pad that has money waiting on it (its pill shows a number)
local function cashPad(): Vector3?
	local vault = myVault()
	if not vault then
		return nil
	end
	for _, d in vault:GetDescendants() do
		if d:IsA("BasePart") and d.Name:match("^CashPadArt%d+$") then
			for _, label in d:GetDescendants() do
				if label:IsA("TextLabel") and label.Text ~= "" and label.Text:find("%$") then
					return d.Position
				end
			end
		end
	end
	return vaultDoor()
end

local function wheel(): Vector3?
	local vault = myVault()
	local plate = vault and vault:FindFirstChild("WheelFloor") :: BasePart?
	return plate and plate.Position
end

local running = false

-- Step 1 is split in two so there's nothing to guess: first a glowing ring on the ground in front of
-- Frank's stash, then (once you're on it) the arrow jumps onto one knife on his wall, which glows.
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local function frankSpot(): Vector3
	local lair = GameConfig.BossLairCenter(1)
	local inward = if lair.X < 0 then 1 else -1 -- toward the middle of the runway
	return lair + Vector3.new(inward * (GameConfig.BossLair.Depth / 2 + 7), 0, 0)
end

-- A knife on Frank's wall near his ring (a stocked slot: its Steal prompt is on), never the one
-- in the middle that Frank himself stands in front of
local function frankKnife(): BasePart?
	local spot = frankSpot()
	local lair = GameConfig.BossLairCenter(1)
	local best, bestDistance = nil, 60
	for _, prompt in workspace:GetDescendants() do
		if prompt:IsA("ProximityPrompt") and prompt:GetAttribute("BossSteal") and prompt.Enabled then
			local pad = prompt.Parent
			if pad and pad:IsA("BasePart") and math.abs(pad.Position.Z - lair.Z) > 6 then
				local distance = (pad.Position - spot).Magnitude
				if distance < bestDistance then
					best, bestDistance = pad, distance
				end
			end
		end
	end
	return best
end

-- Just outside your own vault: your vault's spawn spot (BaseService's VaultSpawn<n>)
local function homeSpot(): Vector3?
	local index = player:GetAttribute("VaultIndex")
	local map = workspace:FindFirstChild("Map")
	local spawnPad = map and type(index) == "number" and map:FindFirstChild(`VaultSpawn{index}`) :: BasePart?
	return if spawnPad then spawnPad.Position + Vector3.new(0, 3, 0) else vaultDoor()
end

-- Your first free plate: its "Place Knife" prompt is on while you carry a knife. Returns the
-- plate's glowing model (to light up) and where to point.
local function freePlate(): (Instance?, Vector3?)
	local vault = myVault()
	if not vault then
		return nil, nil
	end
	local best: BasePart? = nil
	local home = homeSpot()
	for _, prompt in workspace:GetDescendants() do
		if
			prompt:IsA("ProximityPrompt")
			and prompt:GetAttribute("Place")
			and prompt:GetAttribute("Owner") == player.UserId
			and prompt.Enabled
		then
			local pad = prompt.Parent
			if pad and pad:IsA("BasePart") then
				-- the ground floor's nearest to the door
				if
					not best
					or pad.Position.Y < best.Position.Y - 2
					or (
						math.abs(pad.Position.Y - best.Position.Y) <= 2
						and home
						and (pad.Position - home).Magnitude < (best.Position - home).Magnitude
					)
				then
					best = pad
				end
			end
		end
	end
	if not best then
		return nil, nil
	end
	local plate: Instance? = nil
	local closest = 6
	for _, model in vault:GetDescendants() do
		if model:IsA("Model") and model.Name:match("^PlateDetails%d+$") then
			local distance = (model:GetPivot().Position - best.Position).Magnitude
			if distance < closest then
				plate, closest = model, distance
			end
		end
	end
	return plate or best, best.Position
end

-- The floating knife over a wall slot (the server's display model, tagged Spin)
local function knifeOver(pad: BasePart): Instance?
	for _, model in CollectionService:GetTagged("Spin") do
		if model:IsA("Model") then
			local at = model:GetPivot().Position
			if math.abs(at.X - pad.Position.X) < 3 and math.abs(at.Z - pad.Position.Z) < 3 then
				return model
			end
		end
	end
	return pad.Parent
end

-- One arrow design for the world targets.
local function guideArrow(parent: Instance): TextLabel
	local arrow = Ui.label({
		Name = "GuideArrow",
		Size = UDim2.fromScale(1, 1),
		Text = "⬇",
		TextColor3 = Color3.fromRGB(255, 220, 80),
	}, parent)
	Ui.textStroke(arrow, 4)
	return arrow
end

local function run(startAt: number, replay: boolean)
	if running then
		return
	end
	running = true
	local connections: { RBXScriptConnection } = {}
	local function own(connection: RBXScriptConnection)
		table.insert(connections, connection)
	end
	local function carryingKnife(): boolean
		local carrying = player:GetAttribute("Carrying")
		return type(carrying) == "string" and carrying ~= "" and not carrying:match("^Case:")
	end
	local placementBaseline = (player:GetAttribute("KnifePlacementSerial") or 0) :: number
	local carriedOnce = carryingKnife()
	local banked = false
	own(player:GetAttributeChangedSignal("Carrying"):Connect(function()
		if carryingKnife() then
			carriedOnce = true
		end
	end))
	local function confirmPlacement()
		local placed = (player:GetAttribute("KnifePlacementSerial") or 0) :: number
		local savedPlacement = not replay and ((player:GetAttribute("TutorialStep") or 1) :: number) >= 3
		if placed > placementBaseline or savedPlacement then
			-- A confirmed placement also proves the carry, even if its callbacks were missed.
			carriedOnce = true
			banked = true
		end
	end
	own(player:GetAttributeChangedSignal("KnifePlacementSerial"):Connect(confirmPlacement))
	if not replay then
		own(player:GetAttributeChangedSignal("TutorialStep"):Connect(confirmPlacement))
	end
	confirmPlacement()
	local collected = false
	own(Remotes.Effect.OnClientEvent:Connect(function(kind: string)
		if kind == "CashBurst" then
			collected = true
		end
	end))
	local atFrank = false -- stood on the glowing ring in front of his stash
	local atHome = false -- stood on the glowing ring outside your vault
	local plateModel: Instance? = nil
	local plateAt: Vector3? = nil
	-- Caught (or knocked loose) is a real signal from the server, not "the carry ended": placing a
	-- knife also ends the carry a moment before it lands on the plate
	local lostIt = false
	own(Remotes.Effect.OnClientEvent:Connect(function(kind: string, id: unknown)
		if kind == "Tip" and (id == "Caught" or id == "Knocked") then
			lostIt = true
		end
	end))
	local chosenPad: BasePart? = nil
	local lastScan = 0
	local steps: { Step } = {
		{
			Text = "Follow the arrows to the glowing circle at Frank's stash!",
			Target = function(): Vector3?
				if not atFrank then
					return frankSpot()
				end
				-- (looking for one is a scan of the map: at most once a second)
				if (not chosenPad or not chosenPad.Parent) and os.clock() - lastScan > 1 then
					lastScan = os.clock()
					chosenPad = frankKnife()
				end
				return if chosenPad then chosenPad.Position + Vector3.new(0, 4, 0) else nearestGuard()
			end,
			Done = function()
				return carriedOnce
			end,
		},
		{
			-- Straight to your free plate (it glows from the start): there used to be a ring outside
			-- the vault first, an extra stop on the way to the one thing that matters
			Text = "RUN home before Frank catches you! Follow the arrows to the glowing plate.",
			Target = function(): Vector3?
				if not plateAt or os.clock() - lastScan > 1 then
					lastScan = os.clock()
					plateModel, plateAt = freePlate()
				end
				return if plateAt then plateAt + Vector3.new(0, 1, 0) else homeSpot()
			end,
			Done = function()
				return banked
			end,
		},
		{
			Text = "Your knife makes cash every second! Walk over its green pad to collect it.",
			Target = cashPad,
			Done = function()
				return collected
			end,
		},
		{
			Text = "Run in your wheel to train Speed. More Speed = deeper biomes = better knives!",
			Target = wheel,
			Done = function()
				return player:GetAttribute("Training") == true
			end,
		},
	}

	-- The instruction: Steal An Egg's top line - one thin dark band right across the top of the
	-- screen that fades out at both ends (no pill, no box), plain white words on it. The timer lines
	-- move down under it while it's up (client/Hud, Ui.gui TutorialBar).
	local banner = new("Frame", {
		Name = "TutorialBar",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(8, 10, 22),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
	}, Ui.gui)
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.18, 0.45),
			NumberSequenceKeypoint.new(0.82, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, banner)
	local stepLabel = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "",
	}, banner)
	Ui.textStroke(stepLabel, 1.5)
	local skip = Ui.button({
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(52, 24),
		BackgroundColor3 = Color3.fromRGB(90, 90, 110),
		BackgroundTransparency = 0.4,
		Text = "Skip",
		TextSize = 13,
		TextScaled = false,
	}, banner)
	stepLabel.TextScaled, stepLabel.TextWrapped = true, false
	local textLimit = stepLabel:FindFirstChildOfClass("UITextSizeConstraint")
	if textLimit then
		textLimit.MinTextSize, textLimit.MaxTextSize = 12, 20
	end
	local function layout()
		local _, bounds = Ui.bounds()
		local phone = Ui.Phone
		local height = if phone then 36 else 34
		stepLabel.TextSize = if phone then 19 else 20
		-- Only as wide as the words (plus the fade at each end), never the whole screen
		local reserve = if skip.Visible then 64 else 0
		local maxLane = math.max(120, math.min(960, bounds.X - 24 - reserve - 2 * FADE))
		local words =
			TextService:GetTextSize(stepLabel.Text, stepLabel.TextSize, stepLabel.Font, Vector2.new(maxLane, height))
		local lane = math.min(maxLane, words.X + 8)
		banner.Size = UDim2.fromOffset(math.min(bounds.X, lane + reserve + 2 * FADE), height)
		banner.Position = UDim2.new(0.5, 0, 0, 0)
		stepLabel.Position = UDim2.new(0.5, -reserve / 2, 0, 0)
		stepLabel.Size = UDim2.new(0, lane, 1, 0)
		skip.AnchorPoint = Vector2.new(0, 0.5)
		skip.Position = UDim2.new(0.5, lane / 2 - reserve / 2 + 8, 0.5, 0)
		Ui.gui:SetAttribute("TutorialBarHeight", height)
	end
	own(Ui.Layout.Changed:Connect(layout))
	own(stepLabel:GetPropertyChangedSignal("Text"):Connect(layout))
	own(skip:GetPropertyChangedSignal("Visible"):Connect(layout))
	layout()

	-- The trail: red chevrons lying on the ground from you towards the target, sliding forwards
	local targetPart = new("Part", {
		Name = "TutorialTarget",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.one * 0.2,
	}, workspace)
	local trail = new("Folder", { Name = "TutorialTrail" }, workspace)
	-- The ring in front of Frank's stash: a glowing plate like the vault's knife plates
	local ring = new("Part", {
		Name = "FrankRing",
		Shape = Enum.PartType.Cylinder,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(70, 230, 255),
		Size = Vector3.new(0.25, 9, 9),
		Transparency = 1,
	}, trail)
	local ringCore = new("Part", {
		Name = "FrankRingCore",
		Shape = Enum.PartType.Cylinder,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 255, 255),
		Size = Vector3.new(0.3, 6.5, 6.5),
		Transparency = 1,
	}, trail)
	local knifeGlow = new("Highlight", {
		Name = "TutorialKnifeGlow",
		FillColor = Color3.fromRGB(255, 230, 80),
		FillTransparency = 0.15,
		OutlineColor = Color3.fromRGB(255, 255, 255),
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, -- seen through Frank too
		Enabled = false,
	}, trail) :: Highlight
	local SPACING, COUNT = 4.5, 22
	local chevrons: { { Part } } = {}
	for i = 1, COUNT do
		local pair = {}
		for side = 1, 2 do
			pair[side] = new("Part", {
				Name = "Chevron",
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 60, 60),
				Size = Vector3.new(0.85, 0.08, 2.6),
				Transparency = 1,
			}, trail)
		end
		chevrons[i] = pair
	end
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	local function hideTrail()
		for _, pair in chevrons do
			pair[1].Transparency, pair[2].Transparency = 1, 1
		end
	end
	local function drawTrail(from: Vector3, to: Vector3)
		local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
		local length = flat.Magnitude
		if length < 4 then
			hideTrail()
			return
		end
		local direction = flat.Unit
		local character = player.Character
		groundParams.FilterDescendantsInstances = { trail, character :: Instance }
		local slide = (os.clock() * 5) % SPACING
		for i, pair in chevrons do
			local along = 2.5 + (i - 1) * SPACING + slide
			if along > length - 2 then
				pair[1].Transparency, pair[2].Transparency = 1, 1
				continue
			end
			local point = from + direction * along
			local hit = workspace:Raycast(point + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), groundParams)
			local ground = if hit then hit.Position.Y + 0.08 else from.Y
			local base =
				CFrame.lookAt(Vector3.new(point.X, ground, point.Z), Vector3.new(point.X, ground, point.Z) + direction)
			-- a ">" pointing the way: two bars meeting at the tip
			pair[1].CFrame = base * CFrame.Angles(0, math.rad(40), 0) * CFrame.new(0, 0, 1.05)
			pair[2].CFrame = base * CFrame.Angles(0, math.rad(-40), 0) * CFrame.new(0, 0, 1.05)
			-- fade in near you and out near the end
			local fade = math.clamp(math.min(along - 2.5, length - 2 - along) / 4, 0, 1)
			pair[1].Transparency, pair[2].Transparency = 1 - fade * 0.9, 1 - fade * 0.9
		end
	end
	local arrowGui = new("BillboardGui", {
		Size = UDim2.fromOffset(80, 80),
		StudsOffsetWorldSpace = Vector3.new(0, 7, 0),
		AlwaysOnTop = true,
		Adornee = targetPart,
	}, targetPart)
	guideArrow(arrowGui)

	local savedStep = if replay
		then startAt
		else math.max(startAt, (player:GetAttribute("TutorialStep") or 1) :: number)
	local current = math.clamp(savedStep, 1, #steps)
	-- Resuming mid-run but not carrying anything any more: start that steal again
	if current == 2 and not carryingKnife() and not banked then
		current = 1
	end
	local finished = false
	local function finish(skipped: boolean)
		if finished then
			return
		end
		finished = true
		running = false
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		Ui.gui:SetAttribute("TutorialBar", false)
		skip.Visible = false
		if not replay then
			Remotes.Tutorial:FireServer(if skipped then "Skip" else "Done")
		end
		targetPart:Destroy()
		trail:Destroy()
		if skipped then
			banner:Destroy()
			return
		end
		stepLabel.Text = "You've got it! Steal better knives and get stronger!"
		layout()
		-- (its own sound: the power-reveal sting here made equipping sound like the steal again)
		Effects.Sound(Sounds.Cheer, nil, 0.5)
		-- Then what that knife's power actually does, with a one-tap demo
		task.delay(1.2, PowerShowcase.Show)
		task.delay(4, function()
			TweenService:Create(banner, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
			task.wait(0.5)
			banner:Destroy()
		end)
	end
	own(skip.Activated:Connect(function()
		finish(true)
	end))

	local function showStep()
		-- The first steal and placing it can't be skipped: that's the whole game in 60 seconds
		skip.Visible = current > 2
		layout()
		local compact = {
			"Go to the glowing circle at Frank's stash.",
			"Run home to the glowing plate!",
			"Walk over the green cash pad.",
			"Run in your wheel to train Speed.",
		}

		stepLabel.Text = `{current}/{#steps}  {if Ui.Phone or Ui.Layout.get().Compact
			then compact[current]
			else steps[current].Text}`
		if not replay then
			Remotes.Tutorial:FireServer("Step", current) -- saved: leaving midway resumes here
		end
		local scale = banner:FindFirstChildOfClass("UIScale") or new("UIScale", {}, banner)
		scale.Scale = 1.06
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	showStep()

	own(RunService.RenderStepped:Connect(function()
		if finished then
			return
		end
		-- Poll as well as listening: confirmation cannot depend on callback order or timing.
		confirmPlacement()
		-- Hide during rounds
		-- (out of the way while a biome's name pops up in the same spot)
		banner.Visible = not player:GetAttribute("InRound")
			and not Ui.menuOpen()
			and Ui.gui:GetAttribute("ZoneTitle") ~= true
		if Ui.gui:GetAttribute("TutorialBar") ~= banner.Visible then
			Ui.gui:SetAttribute("TutorialBar", banner.Visible) -- (Hud keeps other text off it)
		end
		-- Caught on the way home: the boss took it back, so go steal again
		if current == 2 and lostIt and not banked then
			lostIt = false
			carriedOnce = false
			atFrank = false
			atHome = false
			plateAt = nil
			chosenPad = nil
			current = 1
			showStep()
			stepLabel.Text = "Caught! Frank took it back. Try again - run straight home!"
			return
		end
		-- The glowing ring in front of Frank's stash (step 1): standing on it switches the target to a
		-- knife, which glows. Step 2 points straight at your free plate, glowing all the way.
		local inRound = player:GetAttribute("InRound") == true
		local onStep1 = current == 1 and not inRound
		local onStep2 = current == 2 and not inRound
		local me = root()
		local ringAt: Vector3? = if onStep1 and not atFrank then frankSpot() else nil
		-- Close to your glowing plate: say how to place it
		if onStep2 and not atHome and plateAt and me and (me.Position - plateAt).Magnitude < 14 then
			atHome = true
			stepLabel.Text = if Ui.Phone
				then "2/4  Tap Place Knife on the glowing plate!"
				else "2/4  Press E on the glowing plate to place your knife!"
		end
		if ringAt and me then
			local flat = Vector3.new(me.Position.X - ringAt.X, 0, me.Position.Z - ringAt.Z)
			if flat.Magnitude < 6 then
				atFrank = true
				chosenPad = frankKnife()
				stepLabel.Text = if Ui.Phone
					then "1/4  Hold Steal on the glowing knife!"
					else "1/4  Hold E on the glowing knife to steal it!"
				Effects.Sound(Sounds.Coin, nil, 0.5)
				ringAt = nil
			end
		end
		if ringAt then
			local pulse = (math.sin(os.clock() * 4) + 1) / 2
			local ringParams = RaycastParams.new()
			ringParams.FilterType = Enum.RaycastFilterType.Exclude
			ringParams.FilterDescendantsInstances = { trail, player.Character :: Instance }
			local hit = workspace:Raycast(ringAt + Vector3.new(0, 20, 0), Vector3.new(0, -40, 0), ringParams)
			local y = if hit then hit.Position.Y else ringAt.Y
			local flat = CFrame.new(ringAt.X, y + 0.1, ringAt.Z) * CFrame.Angles(0, 0, math.rad(90))
			ring.CFrame, ringCore.CFrame = flat, flat * CFrame.new(0.03, 0, 0)
			ring.Transparency = 0.15 + pulse * 0.25
			ringCore.Transparency = 0.55 + pulse * 0.3
		else
			ring.Transparency, ringCore.Transparency = 1, 1
		end
		-- What glows: Frank's knife (step 1, on his ring) or your free plate (step 2, home)
		local glowTarget: Instance? = nil
		if onStep1 and atFrank and chosenPad then
			if knifeGlow:GetAttribute("For") ~= chosenPad:GetFullName() or not knifeGlow.Adornee then
				knifeGlow:SetAttribute("For", chosenPad:GetFullName())
				knifeGlow:SetAttribute("Target", nil)
				glowTarget = knifeOver(chosenPad)
			else
				glowTarget = knifeGlow.Adornee
			end
		elseif onStep2 then
			glowTarget = plateModel
		end
		knifeGlow.Adornee = glowTarget
		knifeGlow.Enabled = glowTarget ~= nil
		local step = steps[current]
		if step.Done() then
			Effects.Sound(Sounds.Coin, nil, 0.6)
			current += 1
			if current > #steps then
				finish(false)
				return
			end
			showStep()
			return
		end
		local here = root()
		local target = step.Target()
		local show = here ~= nil and target ~= nil and not player:GetAttribute("InRound")
		arrowGui.Enabled = show
		if not show then
			hideTrail()
		end
		if show and here and target then
			targetPart.Position = target
			drawTrail(here.Position - Vector3.new(0, 2.5, 0), target)
			-- Keep the equip arrow close to the blade, below its floating name/income labels.
			arrowGui.StudsOffsetWorldSpace = Vector3.new(0, 7 + math.sin(os.clock() * 5), 0)
		end
	end))
end

function Tutorial.Init()
	-- More > How to play runs it again any time (no reward the second time)
	Ui.ReplayTutorial = function()
		task.spawn(run, 1, true)
	end
	if player:GetAttribute("TutorialDone") == true then
		return
	end
	-- Wait for the save, however long the server takes to start (it can be 30 s+): never guess,
	-- or returning players would get the guide again
	while player:GetAttribute("DataLoaded") ~= true do
		player:GetAttributeChangedSignal("DataLoaded"):Wait()
	end
	if player:GetAttribute("TutorialDone") == true then
		return
	end
	run((player:GetAttribute("TutorialStep") or 1) :: number, false)
end

return Tutorial
