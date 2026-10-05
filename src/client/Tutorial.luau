--!strict
-- The first minutes, for new players, Steal An Egg style: red arrows on the ground running from you
-- to where you need to go, a bouncing arrow over the spot, and one short line of text in a slim
-- see-through bar under the timer (never a big box over the game). Learn by doing:
--   1. steal a knife off Frank's wall    2. run it home and place it (caught? back to 1)
--   3. collect its cash pad               4. run in your wheel (Speed = deeper biomes)
--   5. open Upgrades (the button pulses)  6. equip your best knife (your Murderer weapon)
-- Progress is saved (player TutorialStep), so leaving midway resumes there. More > How to play
-- replays it (Ui.ReplayTutorial). The murder rounds and everything later are taught by one-time
-- tips at the moment they happen (client/Tips). Steps advance on their own as you do them:
--   1. take down a watchman in the Courtyard   2. grab the case it drops
--   3. carry it home, place it on a plate             4. run in your Haunted Wheel
--   5. the Murder Mystery rounds (just read it)       6. your vault gate
-- Finishing (or skipping) tells the server, which pays a small reward once (Rewards).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Effects = require(script.Parent.Effects)
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

local function run(startAt: number, replay: boolean)
	if running then
		return
	end
	running = true
	local carriedOnce = false
	local banked = false
	player:GetAttributeChangedSignal("Carrying"):Connect(function()
		if player:GetAttribute("Carrying") then
			carriedOnce = true
		end
	end)
	-- Banked = the knife you carried home landed on a plate: the count goes up while you're carrying,
	-- or within a few seconds of the carry ending (the knife flies onto the plate). A knife from the
	-- free chest or the daily reward doesn't count, or the guide would skip the run home.
	local lastCount = (player:GetAttribute("KnifeCount") or 0) :: number
	local carryEndedAt = -math.huge
	player:GetAttributeChangedSignal("Carrying"):Connect(function()
		if not player:GetAttribute("Carrying") then
			carryEndedAt = os.clock()
		end
	end)
	player:GetAttributeChangedSignal("KnifeCount"):Connect(function()
		local count = (player:GetAttribute("KnifeCount") or 0) :: number
		local fromCarry = player:GetAttribute("Carrying") ~= nil or os.clock() - carryEndedAt < 4
		if count > lastCount and fromCarry and carriedOnce then
			banked = true
		end
		lastCount = count
	end)
	local collected = false
	Remotes.Effect.OnClientEvent:Connect(function(kind: string)
		if kind == "CashBurst" then
			collected = true
		end
	end)
	local stepShownAt = os.clock()
	local equippedChanged = false
	player:GetAttributeChangedSignal("Equipped"):Connect(function()
		equippedChanged = true
	end)
	local function menuOpen(name: string): boolean
		return Ui.gui:GetAttribute("ActiveMenu") == name
	end
	local atFrank = false -- stood on the glowing ring in front of his stash
	local atHome = false -- stood on the glowing ring outside your vault
	local plateModel: Instance? = nil
	local plateAt: Vector3? = nil
	-- Caught (or knocked loose) is a real signal from the server, not "the carry ended": placing a
	-- knife also ends the carry a moment before it lands on the plate
	local lostIt = false
	Remotes.Effect.OnClientEvent:Connect(function(kind: string, id: unknown)
		if kind == "Tip" and (id == "Caught" or id == "Knocked") then
			lostIt = true
		end
	end)
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
			Text = "RUN home before Frank catches you! Follow the arrows to the glowing circle.",
			Target = function(): Vector3?
				if not atHome then
					return homeSpot()
				end
				if not plateAt or os.clock() - lastScan > 1 then
					lastScan = os.clock()
					plateModel, plateAt = freePlate()
				end
				return if plateAt then plateAt + Vector3.new(0, 1, 0) else vaultDoor()
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
		{
			-- No world target: the Upgrades button pulses instead
			Text = "Open Upgrades: faster wheels, more floors and more health!",
			Target = function(): Vector3?
				return nil
			end,
			Done = function()
				return menuOpen("Upgrades") or os.clock() - stepShownAt > 25
			end,
		},
		{
			-- The link between the two halves: the knife you equip is the one you fight with as Murderer
			Text = if Ui.Phone
				then "Your best knife is your Murderer weapon! Tap Equip on it."
				else "Your best knife is your Murderer weapon! Press E on it to equip it.",
			Target = vaultDoor,
			Done = function()
				return equippedChanged or os.clock() - stepShownAt > 20
			end,
		},
	}

	-- Step 5: a big yellow arrow beside the Upgrades button, bouncing at it (the button's pulse
	-- ring alone was easy to miss). Its own ScreenGui with no UIScale, so it can sit at the
	-- button's on-screen position wherever the layout (or a phone) put it.
	local pointerGui = new("ScreenGui", {
		Name = "TutorialArrow",
		ResetOnSpawn = false,
		DisplayOrder = 60,
		IgnoreGuiInset = Ui.gui.IgnoreGuiInset,
		ScreenInsets = Ui.gui.ScreenInsets,
		Enabled = false,
	}, player:WaitForChild("PlayerGui")) :: ScreenGui
	local pointer = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(78, 50),
		BackgroundTransparency = 1,
	}, pointerGui)
	local YELLOW = Color3.fromRGB(255, 220, 60)
	local function bar(size: UDim2, position: UDim2, rotation: number)
		local piece = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = size,
			Position = position,
			Rotation = rotation,
			BackgroundColor3 = YELLOW,
		}, pointer)
		Ui.corner(piece, 6)
		new("UIStroke", { Color = Color3.fromRGB(30, 22, 6), Thickness = 3 }, piece)
	end
	-- a shaft and a ">" head, pointing right at the button
	bar(UDim2.fromOffset(46, 14), UDim2.new(0, 28, 0.5, 0), 0)
	bar(UDim2.fromOffset(32, 14), UDim2.new(1, -18, 0.5, -9), 40)
	bar(UDim2.fromOffset(32, 14), UDim2.new(1, -18, 0.5, 9), -40)

	-- The instruction: one line in a slim see-through bar under the timer
	local banner = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(10, 10, 16),
		BackgroundTransparency = 0.45,
	}, Ui.gui)
	Ui.corner(banner, 10)
	local stepLabel = Ui.label({
		Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
	}, banner)
	Ui.textStroke(stepLabel, 2)
	local skip = Ui.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(58, 26),
		BackgroundColor3 = Color3.fromRGB(90, 90, 110),
		BackgroundTransparency = 0.3,
		Text = "Skip",
		TextSize = 14,
		TextScaled = false,
	}, banner)
	stepLabel.TextScaled, stepLabel.TextWrapped = false, true
	local function layout()
		local _, bounds = Ui.bounds()
		local phone = Ui.Phone
		-- between the left and right button columns, under the timer lines
		-- (phones: the most important words a new player reads, so big - 14 px was too small)
		local width =
			math.min(if phone then 600 else 640, math.max(240, bounds.X - (if phone then 2 * 130 else 2 * 190)))
		local height = if phone then 56 else 44
		banner.Size = UDim2.fromOffset(width, height)
		banner.Position = UDim2.new(0.5, 0, 0, if phone then 88 else 116)
		stepLabel.Size = UDim2.new(1, -84, 1, 0)
		stepLabel.TextSize = if phone then 21 else 19
	end
	Ui.Layout.Changed:Connect(layout)
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
	local arrow =
		Ui.label({ Size = UDim2.fromScale(1, 1), Text = "⬇", TextColor3 = Color3.fromRGB(255, 220, 80) }, arrowGui)
	Ui.textStroke(arrow, 4)

	local current = math.clamp(startAt, 1, #steps)
	-- Resuming mid-run but not carrying anything any more: start that steal again
	if current == 2 and not player:GetAttribute("Carrying") then
		current = 1
	end
	local finished = false
	local function finish(skipped: boolean)
		if finished then
			return
		end
		finished = true
		running = false
		Ui.gui:SetAttribute("TutorialBar", false)
		if not replay then
			Remotes.Tutorial:FireServer(if skipped then "Skip" else "Done")
		end
		targetPart:Destroy()
		trail:Destroy()
		pointerGui:Destroy()
		if skipped then
			banner:Destroy()
			return
		end
		stepLabel.Text =
			"You've got it! Steal better knives - the best one you equip is your Murderer weapon. Good luck!"
		Effects.Sound(Sounds.Reveal, nil, 0.7)
		task.delay(4, function()
			TweenService:Create(banner, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
			task.wait(0.5)
			banner:Destroy()
		end)
	end
	skip.Activated:Connect(function()
		finish(true)
	end)

	local function showStep()
		stepShownAt = os.clock()
		-- The first steal and placing it can't be skipped: that's the whole game in 60 seconds
		skip.Visible = current > 2
		local compact = {
			"Go to the glowing circle at Frank's stash.",
			"Run home to the glowing circle!",
			"Walk over the green cash pad.",
			"Run in your wheel to train Speed.",
			"Open Upgrades!",
			"Equip your best knife: your Murderer weapon!",
		}

		stepLabel.Text =
			`{current}/{#steps}  {if Ui.Layout.get().Compact then compact[current] else steps[current].Text}`
		if not replay then
			Remotes.Tutorial:FireServer("Step", current) -- saved: leaving midway resumes here
		end
		local scale = banner:FindFirstChildOfClass("UIScale") or new("UIScale", {}, banner)
		scale.Scale = 1.06
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	showStep()

	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		if finished then
			connection:Disconnect()
			return
		end
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
		-- The Upgrades step: a pulsing yellow ring round the Upgrades button
		local upgrades = Ui.gui:FindFirstChild("UpgradesButton", true) :: GuiObject?
		if upgrades then
			local pulseRing = upgrades:FindFirstChild("TutorialRing") :: UIStroke?
			if current == 5 and not pulseRing then
				pulseRing = new("UIStroke", {
					Name = "TutorialRing",
					Color = Color3.fromRGB(255, 220, 60),
					Thickness = 4,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}, upgrades) :: UIStroke
			end
			if pulseRing then
				if current == 5 then
					pulseRing.Thickness = 3 + (math.sin(os.clock() * 8) + 1) * 2.5
				else
					pulseRing:Destroy()
				end
			end
		end
		local pointAt = current == 5
			and upgrades ~= nil
			and upgrades.Visible
			and upgrades.AbsoluteSize.X > 0
			and not Ui.menuOpen()
			and not player:GetAttribute("InRound")
		pointerGui.Enabled = pointAt == true
		if pointAt and upgrades then
			local bounce = math.abs(math.sin(os.clock() * 5)) * 14
			local at = upgrades.AbsolutePosition
			pointer.Position = UDim2.fromOffset(at.X - 8 - bounce, at.Y + upgrades.AbsoluteSize.Y / 2)
		end
		-- The glowing ring: Frank's stash (step 1), then outside your vault (step 2); standing on it
		-- switches the target to the knife / the free plate, which glows
		local inRound = player:GetAttribute("InRound") == true
		local onStep1 = current == 1 and not inRound
		local onStep2 = current == 2 and not inRound
		local me = root()
		local ringAt: Vector3? = if onStep1 and not atFrank
			then frankSpot()
			elseif onStep2 and not atHome then homeSpot()
			else nil
		if ringAt and me then
			local flat = Vector3.new(me.Position.X - ringAt.X, 0, me.Position.Z - ringAt.Z)
			if flat.Magnitude < 6 then
				if onStep1 then
					atFrank = true
					chosenPad = frankKnife()
					stepLabel.Text = if Ui.Phone
						then "1/6  Hold Steal on the glowing knife!"
						else "1/6  Hold E on the glowing knife to steal it!"
				else
					atHome = true
					plateModel, plateAt = freePlate()
					stepLabel.Text = if Ui.Phone
						then "2/6  Tap Place Knife on the glowing plate!"
						else "2/6  Press E on the glowing plate to place your knife!"
				end
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
		elseif onStep2 and atHome then
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
			arrowGui.StudsOffsetWorldSpace = Vector3.new(0, 7 + math.sin(os.clock() * 5) * 1, 0)
		end
	end)
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
