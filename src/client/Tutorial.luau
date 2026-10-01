--!strict
-- The first minute, for new players: a glowing trail from you to where you need to go, a bouncing
-- arrow over it, and one short instruction at a time. Steps advance on their own as you do them:
--   1. take down a watchman in the Courtyard   2. grab the case it drops
--   3. carry it home to your vault              4. run in your Haunted Wheel
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

local function nearestDrop(): Vector3?
	local map = workspace:FindFirstChild("Map")
	local drops = map and map:FindFirstChild("DroppedKnives")
	local here = root()
	if not drops or not here then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for _, drop in drops:GetChildren() do
		if drop:IsA("Model") and drop.PrimaryPart then
			local distance = (drop.PrimaryPart.Position - here.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = drop.PrimaryPart.Position, distance
			end
		end
	end
	return if bestDistance < 80 then best else nil
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

-- Your vault's gate (the barrier rivals break)
local function gate(): Vector3?
	for _, blocker in game:GetService("CollectionService"):GetTagged("VaultGate") do
		if blocker:GetAttribute("Owner") == player.UserId then
			return (blocker :: BasePart).Position
		end
	end
	return nil
end

local function wheel(): Vector3?
	local vault = myVault()
	local plate = vault and vault:FindFirstChild("WheelFloor") :: BasePart?
	return plate and plate.Position
end

function Tutorial.Init()
	if player:GetAttribute("TutorialDone") == true then
		return
	end
	-- Wait for data; returning players skip all of this
	local started = os.clock()
	while player:GetAttribute("DataLoaded") ~= true and os.clock() - started < 20 do
		task.wait(0.5)
	end
	if player:GetAttribute("TutorialDone") == true then
		return
	end

	local carriedOnce = false
	local banked = false
	player:GetAttributeChangedSignal("Carrying"):Connect(function()
		if player:GetAttribute("Carrying") then
			carriedOnce = true
		elseif carriedOnce then
			banked = true
		end
	end)
	local steps: { Step } = {
		{
			Text = if Ui.Phone
				then "Take down a watchman in the Courtyard! (tap to stab, hold the red button to throw)"
				else "Take down a watchman in the Courtyard! (click to stab, hold to throw)",
			Target = nearestGuard,
			Done = function()
				return nearestDrop() ~= nil or carriedOnce
			end,
		},
		{
			Text = "Grab the sealed case it dropped!",
			Target = nearestDrop,
			Done = function()
				return carriedOnce
			end,
		},
		{
			Text = "RUN! Carry it home to your vault before the guards catch you!",
			Target = vaultDoor,
			Done = function()
				return banked
			end,
		},
		{
			Text = "Your knife earns cash every second. Now run in your Haunted Wheel to get faster!",
			Target = wheel,
			Done = function()
				return player:GetAttribute("Training") == true
			end,
		},
		{
			Text = "Rivals can break your gate and steal knives! Go to it: R repairs it, G upgrades your walls.",
			Target = gate,
			Done = function()
				local at = gate()
				local me = root()
				return at ~= nil and me ~= nil and (me.Position - at).Magnitude < 12
			end,
		},
	}

	-- The banner
	local banner = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 104),
		Size = UDim2.fromOffset(if Ui.Phone then 540 else 640, 64),
		BackgroundColor3 = Color3.fromRGB(255, 200, 60),
	}, Ui.gui)
	Ui.corner(banner, 16)
	Ui.gradient(banner, Color3.fromRGB(255, 220, 90), Color3.fromRGB(230, 150, 30))
	new("UIStroke", { Thickness = 4, Color = Color3.fromRGB(20, 16, 28) }, banner)
	local stepLabel = Ui.label({
		Size = UDim2.new(1, -120, 1, -10),
		Position = UDim2.fromOffset(12, 5),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, banner)
	Ui.textStroke(stepLabel, 2.5)
	local skip = Ui.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(90, 40),
		BackgroundColor3 = Color3.fromRGB(90, 90, 110),
		Text = "Skip",
	}, banner)

	-- The trail: a beam from you to the target, and an arrow bouncing over it
	local targetPart = new("Part", {
		Name = "TutorialTarget",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.one * 0.2,
	}, workspace)
	local targetAttachment = new("Attachment", {}, targetPart)
	local beam = new("Beam", {
		Attachment1 = targetAttachment,
		Color = ColorSequence.new(Color3.fromRGB(255, 230, 90)),
		LightEmission = 1,
		Width0 = 1.2,
		Width1 = 1.2,
		FaceCamera = true,
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		TextureMode = Enum.TextureMode.Wrap,
		TextureLength = 3,
		TextureSpeed = 2,
		Transparency = NumberSequence.new(0.2),
		Segments = 20,
		CurveSize0 = 6,
	}, targetPart)
	local arrowGui = new("BillboardGui", {
		Size = UDim2.fromOffset(80, 80),
		StudsOffsetWorldSpace = Vector3.new(0, 7, 0),
		AlwaysOnTop = true,
		Adornee = targetPart,
	}, targetPart)
	local arrow =
		Ui.label({ Size = UDim2.fromScale(1, 1), Text = "⬇", TextColor3 = Color3.fromRGB(255, 220, 80) }, arrowGui)
	Ui.textStroke(arrow, 4)

	local current = 1
	local finished = false
	local function finish(skipped: boolean)
		if finished then
			return
		end
		finished = true
		Remotes.Tutorial:FireServer(if skipped then "Skip" else "Done")
		targetPart:Destroy()
		if skipped then
			banner:Destroy()
			return
		end
		stepLabel.Text = "You've got it! Steal, train, defend your vault, survive. Good luck!"
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
		stepLabel.Text = `{current}/{#steps}  {steps[current].Text}`
		local scale = banner:FindFirstChildOfClass("UIScale") or new("UIScale", {}, banner)
		scale.Scale = 1.1
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
		banner.Visible = not player:GetAttribute("InRound")
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
		beam.Enabled = show
		arrowGui.Enabled = show
		if show and here and target then
			targetPart.Position = target
			local attachment = here:FindFirstChild("TutorialAttachment") :: Attachment?
			if not attachment then
				attachment =
					new("Attachment", { Name = "TutorialAttachment", Position = Vector3.new(0, -2.5, 0) }, here)
			end
			beam.Attachment0 = attachment
			arrowGui.StudsOffsetWorldSpace = Vector3.new(0, 7 + math.sin(os.clock() * 5) * 1, 0)
		end
	end)
end

return Tutorial
