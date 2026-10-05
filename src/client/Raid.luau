--!strict
-- The raid side of the hub, on this client:
--   * vault gates are solid for everyone but their owner (unless broken, or you have revenge on
--     its owner); the server double-checks and evicts anyone who slips through
--   * "Steal" prompts on other players' pedestals light up only when that vault is open to you
--   * hold R (or the button) at your own gate to repair it whenever it's been hit
--   * every gate's glowing barrier fades and stutters as its health drops
--   * pushing into someone's powerful knife aura: the screen tints, you slow, "Get away from..."
--   * getting knocked down: stars, a shake, the screen greys out for a moment

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Effects = require(script.Parent.Effects)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local new = Ui.new

local Raid = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function revengeOn(ownerId: number?): boolean
	local until_ = player:GetAttribute("RevengeUntil")
	return ownerId ~= nil
		and player:GetAttribute("RevengeOn") == ownerId
		and type(until_) == "number"
		and now() < until_
end

local function blockerOf(ownerId: number): BasePart?
	for _, blocker in CollectionService:GetTagged("VaultGate") do
		if blocker:GetAttribute("Owner") == ownerId then
			return blocker :: BasePart
		end
	end
	return nil
end

-- Whether a vault is open to me right now: during the Blood Moon, anyone's but a new player's
local function openToMe(ownerId: number?): boolean
	if ReplicatedStorage:GetAttribute("Phase") ~= "Intermission" or player:GetAttribute("InRound") then
		return false
	end
	if not ownerId or ownerId == player.UserId then
		return false
	end
	if ReplicatedStorage:GetAttribute("Raid") == true then
		local owner = Players:GetPlayerByUserId(ownerId)
		return owner ~= nil and not owner:GetAttribute("Shielded") and not player:GetAttribute("Carrying")
	end
	if revengeOn(ownerId) then
		return true
	end
	local blocker = blockerOf(ownerId)
	return blocker ~= nil and blocker:GetAttribute("Open") == true
end

-- The barrier glow behind each gate's bars: solid at full health, thinner as it's chipped away,
-- and stuttering when it's about to give
local function refreshBarriers()
	local t = os.clock()
	for _, instance in CollectionService:GetTagged("VaultGate") do
		local blocker = instance :: BasePart
		local gate = blocker.Parent
		if not gate or blocker:GetAttribute("Open") then
			continue
		end
		local health = (blocker:GetAttribute("Health") or 1) :: number
		local max = (blocker:GetAttribute("MaxHealth") or 1) :: number
		local ratio = math.clamp(health / max, 0, 1)
		local stutter = ratio < 0.3 and math.noise(t * 9, blocker.Position.X) > 0.15
		for _, d in gate:GetChildren() do
			if d:IsA("BasePart") and d.Name == "Pane" then
				local base = (d:GetAttribute("BaseTransparency") or 0.35) :: number
				d.Transparency = if stutter then 0.95 else base + (1 - ratio) * (0.9 - base)
			end
		end
	end
end

local function refreshGates()
	for _, instance in CollectionService:GetTagged("VaultGate") do
		local blocker = instance :: BasePart
		local owner = blocker:GetAttribute("Owner") :: number?
		-- Vaults are open now (Tsunami): anyone can walk in, nobody can take anything
		local _ = owner
		local _ = openToMe
		blocker.CanCollide = false
	end
end

local function refreshPrompts()
	local inRound = player:GetAttribute("InRound") == true
	for _, prompt in CollectionService:GetTagged("StealPrompt") do
		local p = prompt :: ProximityPrompt
		p.Enabled = not inRound and openToMe(p:GetAttribute("Owner") :: number?)
	end
end

local function trackPrompt(instance: Instance)
	if instance:IsA("ProximityPrompt") and instance:GetAttribute("WallUpgrade") then
		instance.Enabled = instance:GetAttribute("Owner") == player.UserId
		return
	end
	if instance:IsA("ProximityPrompt") and instance:GetAttribute("Steal") then
		instance:AddTag("StealPrompt")
		instance.Enabled = false
	end
end

-- Coloured light creeping in from the screen edges; returns a setter for how strong (0..1).
-- (Atmosphere uses one too, for the Murderer's dread.)
function Raid.Vignette(parent: Instance, color: Color3): (number) -> ()
	local frames = {}
	for _, side in
		{
			{ Size = UDim2.fromScale(1, 0.32), Position = UDim2.fromScale(0, 0), Rotation = 90 },
			{ Size = UDim2.fromScale(1, 0.32), Position = UDim2.fromScale(0, 0.68), Rotation = -90 },
			{ Size = UDim2.fromScale(0.24, 1), Position = UDim2.fromScale(0, 0), Rotation = 0 },
			{ Size = UDim2.fromScale(0.24, 1), Position = UDim2.fromScale(0.76, 0), Rotation = 180 },
		}
	do
		local frame = new("Frame", {
			Size = side.Size,
			Position = side.Position,
			BackgroundColor3 = color,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, parent)
		new("UIGradient", {
			Rotation = side.Rotation,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, frame)
		table.insert(frames, frame)
	end
	local current = 0
	return function(strength: number)
		current += (strength - current) * 0.15
		for _, frame in frames do
			frame.BackgroundTransparency = 1 - current * 0.75
		end
	end
end

function Raid.Init()
	-- Gates and prompts: refresh on every change, and on a slow timer for revenge running out
	for _, d in workspace:GetDescendants() do
		trackPrompt(d)
	end
	workspace.DescendantAdded:Connect(trackPrompt)
	CollectionService:GetInstanceAddedSignal("VaultGate"):Connect(function(blocker)
		blocker.AttributeChanged:Connect(function()
			refreshGates()
			refreshPrompts()
		end)
		refreshGates()
	end)
	for _, blocker in CollectionService:GetTagged("VaultGate") do
		blocker.AttributeChanged:Connect(function()
			refreshGates()
			refreshPrompts()
		end)
	end
	CollectionService:GetInstanceAddedSignal("StealPrompt"):Connect(refreshPrompts)
	for _, attribute in { "RevengeOn", "RevengeUntil", "InRound", "Carrying" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			refreshGates()
			refreshPrompts()
		end)
	end
	ReplicatedStorage:GetAttributeChangedSignal("Raid"):Connect(function()
		refreshGates()
		refreshPrompts()
	end)
	ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(function()
		refreshGates()
		refreshPrompts()
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			refreshGates()
			refreshPrompts()
		end
	end)

	-- Repairing your own gate during a raid ------------------------------------------------------
	local repairButton = Ui.chunky(
		{
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 108),
			Size = UDim2.fromOffset(120, 44),
			BackgroundColor3 = Color3.fromRGB(90, 160, 255),
			Text = "Repair" .. Ui.hint("R", "L3"),
			Visible = false,
		},
		Ui.gui,
		"🔧",
		function()
			Remotes.RepairGate:FireServer()
		end
	)
	local function nearOwnGate(): boolean
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local blocker = blockerOf(player.UserId)
		return root ~= nil
			and blocker ~= nil
			and blocker:GetAttribute("Open") ~= true
			and ((blocker:GetAttribute("Health") or 0) :: number) < ((blocker:GetAttribute("MaxHealth") or 0) :: number)
			and (root.Position - blocker.Position).Magnitude < 16
	end
	repairButton:GetPropertyChangedSignal("Visible"):Connect(function()
		Ui.gui:SetAttribute("RepairVisible", repairButton.Visible)
	end)
	ContextActionService:BindAction("RepairGate", function(_, state)
		if state == Enum.UserInputState.Begin and nearOwnGate() and not Ui.menuOpen() then
			Remotes.RepairGate:FireServer()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.R, Enum.KeyCode.ButtonL3)

	-- Aura pressure: a tint creeping in from the edges, and the warning ------------------------------
	local auraGui = new("ScreenGui", {
		Name = "AuraPressure",
		IgnoreGuiInset = true,
		DisplayOrder = 4,
		ResetOnSpawn = false,
	}, player:WaitForChild("PlayerGui"))
	local setVignette = Raid.Vignette(auraGui, Color3.fromRGB(170, 70, 255))
	local warning = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.2),
		Size = UDim2.fromOffset(700, 44),
		Text = "",
		TextTransparency = 1,
		TextColor3 = Color3.fromRGB(230, 170, 255),
	}, auraGui)
	Ui.textStroke(warning, 3)

	-- Knocked down: stars and a grey-out
	local knockLabel = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(600, 70),
		Text = "💫 KNOCKED DOWN 💫",
		TextColor3 = Color3.fromRGB(255, 230, 120),
		Visible = false,
	}, auraGui)
	Ui.textStroke(knockLabel, 4)
	Ui.fitPhone(knockLabel)
	Ui.fitPhone(warning)
	local grey = new("ColorCorrectionEffect", { Name = "KnockGrey", Enabled = false }, workspace.CurrentCamera)
	player:GetAttributeChangedSignal("KnockedUntil"):Connect(function()
		local knocked = player:GetAttribute("KnockedUntil")
		local down = type(knocked) == "number" and knocked > now()
		knockLabel.Visible = down
		grey.Enabled = down
		grey.Saturation = -0.7
		if down then
			Effects.Shake(4, 0.5)
			local scale = knockLabel:FindFirstChildOfClass("UIScale") or new("UIScale", {}, knockLabel)
			scale.Scale = 0.4
			TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end)

	local camera = workspace.CurrentCamera
	local baseFov = 70
	local barrierTimer = 0
	RunService.RenderStepped:Connect(function(dt: number)
		-- Repair button
		barrierTimer += dt
		if barrierTimer >= 0.1 then
			barrierTimer = 0
			repairButton.Visible = nearOwnGate()
				and not Ui.menuOpen()
				and Ui.gui:GetAttribute("KnifeGestureActive") ~= true
			refreshBarriers()
		end
		-- Aura pressure
		local slow = player:GetAttribute("AuraSlow")
		local pressure = if type(slow) == "number" then math.clamp((1 - slow) / 0.6, 0, 1) else 0
		setVignette(pressure)
		local from = player:GetAttribute("AuraFrom")
		if pressure > 0.02 and type(from) == "string" then
			warning.Text = `Get away from {from}!`
			warning.TextTransparency = math.max(0, warning.TextTransparency - dt * 4)
			-- The pull wobbles your view a little
			camera.FieldOfView = baseFov - pressure * 8 + math.sin(os.clock() * 7) * pressure * 1.5
		else
			warning.TextTransparency = math.min(1, warning.TextTransparency + dt * 3)
		end
		local stroke = warning:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = warning.TextTransparency
		end
	end)
	-- Put the field of view back once you're out of the aura
	player:GetAttributeChangedSignal("AuraSlow"):Connect(function()
		if player:GetAttribute("AuraSlow") == nil then
			TweenService:Create(camera, TweenInfo.new(0.4), { FieldOfView = baseFov }):Play()
		end
	end)
end

return Raid
