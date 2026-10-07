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
-- Finishing tells the server, which pays a small reward once (Rewards).

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
local Places = require(script.Parent.Places)
local Arrows = require(script.Parent.Arrows)
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

local running = false

-- (where things are: client/Places, shared with the guide)
local cashPad, wheel, homeSpot = Places.CashPad, Places.Wheel, Places.HomeSpot
local freePlate, knifeOver = Places.FreePlate, Places.KnifeOver

-- Go directly to a stocked side knife. The lair approach is only a fallback while it streams in.
local function frankSpot(): Vector3
	return Places.LairSpot(1)
end
-- A knife on Frank's wall near his ring, never the one in the middle Frank stands in front of
local function frankKnife(): BasePart?
	return Places.LairKnife(1, true)
end

local function run(startAt: number, replay: boolean)
	if running then
		return
	end
	running = true
	Ui.gui:SetAttribute("TutorialRunning", true)
	Places.Init()
	Arrows.Claim("Tutorial") -- (the guide waits until we're done)
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
	local atFrank = false -- close enough to use the chosen knife's prompt
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
	local trainingSince: number? = nil
	local steps: { Step } = {
		{
			Text = "Follow the arrows to Frank's knife!",
			Target = function(): Vector3?
				local prompt = chosenPad and chosenPad:FindFirstChildOfClass("ProximityPrompt")
				if
					(not chosenPad or not chosenPad.Parent or not prompt or not prompt.Enabled)
					and os.clock() - lastScan > 1
				then
					lastScan = os.clock()
					chosenPad = frankKnife()
				end
				return if chosenPad then chosenPad.Position else frankSpot()
			end,
			Done = function()
				return carriedOnce
			end,
		},
		{
			-- Straight to your free plate (it glows from the start): there used to be a ring outside
			-- the vault first, an extra stop on the way to the one thing that matters
			Text = "RUN home before the boss catches you! Follow the arrows!",
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
			Text = "Your knife makes money! Walk on the green pad to get it.",
			Target = cashPad,
			Done = function()
				return collected
			end,
		},
		{
			Text = "Run in your wheel to get faster! Faster = better knives!",
			Target = wheel,
			Done = function()
				if player:GetAttribute("Training") and Ui.inHub() then
					trainingSince = trainingSince or os.clock()
					return os.clock() - (trainingSince :: number) >= 3
				end
				trainingSince = nil
				return false
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
		local reserve = 0
		-- Phones: up in Roblox's top bar (Ui.topStrip), with short fades so it fits
		local strip = Ui.topStrip()
		local fade = if strip then 16 else FADE
		local room = if strip then strip.W else bounds.X - 24
		local maxLane = math.max(120, math.min(960, room - reserve - 2 * fade))
		local words =
			TextService:GetTextSize(stepLabel.Text, stepLabel.TextSize, stepLabel.Font, Vector2.new(maxLane, height))
		local lane = math.min(maxLane, words.X + 8)
		banner.Size = UDim2.fromOffset(math.min(bounds.X, lane + reserve + 2 * fade), height)
		if strip then
			height = math.min(height, strip.H)
			banner.Size = UDim2.fromOffset(lane + reserve + 2 * fade, height)
			banner.Position = UDim2.fromOffset(strip.X, strip.Y + (strip.H - height) / 2)
		else
			banner.Position = UDim2.fromScale(0.5, 0)
		end
		Ui.gui:SetAttribute("TutorialInStrip", strip ~= nil)
		stepLabel.Position = UDim2.new(0.5, -reserve / 2, 0, 0)
		stepLabel.Size = UDim2.new(0, lane, 1, 0)
		Ui.gui:SetAttribute("TutorialBarHeight", height)
	end
	own(Ui.Layout.Changed:Connect(layout))
	own(stepLabel:GetPropertyChangedSignal("Text"):Connect(layout))
	layout()

	local savedStep = if replay
		then startAt
		else math.max(startAt, (player:GetAttribute("TutorialStep") or 1) :: number)
	local current = math.clamp(savedStep, 1, #steps)
	-- Resuming mid-run but not carrying anything any more: start that steal again
	if current == 2 and not carryingKnife() and not banked then
		current = 1
	end
	local finished = false
	local glowFor: BasePart? = nil
	local glowModel: Instance? = nil
	local function finish(skipped: boolean)
		if finished then
			return
		end
		finished = true
		running = false
		Ui.gui:SetAttribute("TutorialRunning", false)
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		Ui.gui:SetAttribute("TutorialBar", false)
		if not replay then
			Remotes.Tutorial:FireServer(if skipped then "Skip" else "Done")
		end
		Arrows.Release("Tutorial") -- (the guide takes over the arrows this frame)
		if skipped then
			banner:Destroy()
			return
		end
		banner:Destroy()
		local me = root()
		if me then
			Effects.FloatText(me.Position + Vector3.new(0, 3, 0), "+Speed!", Color3.fromRGB(120, 255, 140))
		end
		-- (its own sound: the power-reveal sting here made equipping sound like the steal again)
		-- Then what that knife's power actually does, with a one-tap demo
		task.delay(1.2, PowerShowcase.Show)
	end

	local function showStep()
		layout()
		local compact = {
			"Follow the arrows!",
			"RUN HOME!",
			"Collect your cash!",
			"Run in your wheel!",
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

	own(RunService.Heartbeat:Connect(function()
		if finished then
			return
		end
		-- Poll as well as listening: confirmation cannot depend on callback order or timing.
		confirmPlacement()
		-- Hide during rounds
		-- (out of the way while a biome's name pops up in the same spot)
		banner.Visible = Ui.inHub() -- (not dead and watching a round either)
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
			stepLabel.Text = "Caught! Try again - run straight home!"
			return
		end
		-- Both steal and placement trails lead directly to the interaction object.
		local inRound = player:GetAttribute("InRound") == true
		if inRound then
			Arrows.Release("Tutorial")
		else
			Arrows.Claim("Tutorial")
		end
		local onStep1 = current == 1 and not inRound
		local onStep2 = current == 2 and not inRound
		local me = root()
		-- Close to your glowing plate: say how to place it
		if onStep2 and not atHome and plateAt and me and (me.Position - plateAt).Magnitude < 14 then
			atHome = true
			stepLabel.Text = if Ui.Phone
				then "2/4  Tap PLACE KNIFE!"
				else "2/4  Press E on the glowing plate to place your knife!"
		end
		if onStep1 and chosenPad and me and not atFrank then
			if (me.Position - chosenPad.Position).Magnitude < 12 then
				atFrank = true
				stepLabel.Text = if Ui.Phone
					then "1/4  Hold STEAL!"
					else "1/4  Hold E on the glowing knife to steal it!"
				Effects.Sound(Sounds.Coin, nil, 0.5)
			end
		end
		-- What glows: the chosen knife or your free plate.
		local glowTarget: Instance? = nil
		if onStep1 and chosenPad then
			if glowFor ~= chosenPad or not glowModel or not glowModel.Parent then
				glowFor = chosenPad
				glowModel = knifeOver(chosenPad)
			end
			glowTarget = glowModel
		elseif onStep2 then
			glowTarget = plateModel
		end
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
		if
			here
			and target
			and banner.Visible
			and not player:GetAttribute("Spectating")
			and Ui.gui:GetAttribute("FadeCover") ~= true
			and Ui.gui:GetAttribute("Presenting") ~= true
		then
			Arrows.Draw("Tutorial", {
				Target = target,
				Aim = Places.Aim(here.Position, target),
				Glow = glowTarget,
			})
		else
			Arrows.Hide("Tutorial")
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
