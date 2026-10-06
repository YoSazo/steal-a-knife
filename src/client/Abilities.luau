--!strict
-- Knife controls from the client side, MM2 style:
--   * desktop click / gamepad trigger: existing stab and throw controls
--   * mobile: tap the translucent knife button to stab; hold its joystick to aim and throw
--   * HOLD left click (or Q, gamepad LT/X, or the on-screen button): your arm cranks back, a
--     crosshair shows and the camera leans in; let go to throw at whatever is under the cursor
-- Knife tools are ManualActivationOnly, so a tap is turned into tool:Activate() here and the
-- server still decides every hit from Tool.Activated.
--   * other abilities (Murderer perks like Dash, the Smoke Bomb) fire on press
-- The Revolver fires at the cursor too. The client only sends aim; the server validates it all.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Ui = require(script.Parent.Ui)
local Moves = require(script.Parent.Moves)
local KnifeGesture = require(script.Parent.KnifeGesture)
local KnifeAim = require(script.Parent.KnifeAim)
local WorldSignInput = require(script.Parent.WorldSignInput)
local KNIFE_SIZE = KnifeAim.ButtonSize
local AnimLibrary = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AnimLibrary"))
local GameConfig = require(ReplicatedStorage.Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Textures = require(ReplicatedStorage.Shared.Config:WaitForChild("Textures"))
local Items = require(ReplicatedStorage.Shared.Items)
local Artwork = require(ReplicatedStorage.Shared.Config.UiArtwork)
local PowerIcons = require(ReplicatedStorage.Shared.Config.VoxelPowerIcons)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local Abilities = {}

local THROW_INPUTS: { [Enum.KeyCode | Enum.UserInputType]: boolean } = {
	[Enum.KeyCode.Q] = true,
	[Enum.KeyCode.ButtonL2] = true,
	[Enum.KeyCode.ButtonX] = true,
}
local COMBO = { "Stab", "Slash" }
local HOLD_TO_THROW = 0.2 -- seconds holding left click before a tap becomes a throw
local BASE_FOV = 70

-- A mouse aims at the cursor (always, even on a touch laptop or Studio's phone preview); touch
-- screens and gamepads aim through the screen centre (MM2's THROW button)
local function usingMouse(): boolean
	local lastInput = UserInputService:GetLastInputType()
	return lastInput == Enum.UserInputType.MouseMovement
		or lastInput == Enum.UserInputType.MouseButton1
		or lastInput == Enum.UserInputType.MouseButton2
		or lastInput == Enum.UserInputType.MouseWheel
		or lastInput == Enum.UserInputType.Keyboard
end
local function screenAim(): Vector2
	if usingMouse() and UserInputService.MouseEnabled then
		return UserInputService:GetMouseLocation()
	end
	return workspace.CurrentCamera.ViewportSize / 2
end

-- `touch` = `at` is a touch position (InputObject / TouchTapInWorld space, under the top bar inset)
local function aimPoint(at: Vector2?, touch: boolean?): Vector3
	local camera = workspace.CurrentCamera
	local screen = at or screenAim()
	local ray = if touch
		then camera:ScreenPointToRay(screen.X, screen.Y)
		else camera:ViewportPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	return if hit then hit.Position else ray.Origin + ray.Direction * 2000
end

-- Phones, MM2 style: you tap the person you want to shoot. A tap a little beside them still counts
-- (fingers are fat): if the tap's ray passes within TAP_ASSIST studs of someone in front of what it
-- hit, aim at their chest instead.
local TAP_ASSIST = 3
local function tapAim(at: Vector2): Vector3
	local camera = workspace.CurrentCamera
	local ray = camera:ScreenPointToRay(at.X, at.Y)
	local point = aimPoint(at, true)
	local reach = (point - ray.Origin).Magnitude + 2
	local models: { Model } = {}
	for _, other in Players:GetPlayers() do
		if other ~= player and other.Character then
			table.insert(models, other.Character)
		end
	end
	local bots = workspace:FindFirstChild("RoundBots")
	for _, bot in if bots then bots:GetChildren() else {} do
		if bot:IsA("Model") then
			table.insert(models, bot)
		end
	end
	local best: Vector3? = nil
	local bestGap = TAP_ASSIST
	for _, model in models do
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then
			continue
		end
		local along = (root.Position - ray.Origin):Dot(ray.Direction)
		if along <= 0 or along > reach then
			continue -- behind the camera, or behind the wall the tap hit
		end
		local gap = (ray.Origin + ray.Direction * along - root.Position).Magnitude
		if gap < bestGap then
			best, bestGap = root.Position, gap
		end
	end
	return best or point
end

-- Direction from the character to what's under the cursor / crosshair, like MM2's knife throw
local function aimDirection(at: Vector2?, touch: boolean?): Vector3
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not head then
		return workspace.CurrentCamera.CFrame.LookVector
	end
	local offset = (if touch and at then tapAim(at) else aimPoint(at)) - head.Position
	return if offset.Magnitude > 0.1 then offset.Unit else workspace.CurrentCamera.CFrame.LookVector
end

local function isKnife(tool: Instance): boolean
	return tool:IsA("Tool") and (tool:GetAttribute("HubKnife") ~= nil or tool:GetAttribute("MurderKnife") == true)
end

local function knifeInHand(): Tool?
	local character = player.Character
	if not character then
		return nil
	end
	for _, child in character:GetChildren() do
		if isKnife(child) then
			return child :: Tool
		end
	end
	return nil
end

-- Pull the knife out of the backpack if it isn't already in hand
local function drawKnife(): Tool?
	local held = knifeInHand()
	if held then
		return held
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not humanoid or not backpack then
		return nil
	end
	for _, child in backpack:GetChildren() do
		if isKnife(child) then
			humanoid:EquipTool(child :: Tool)
			return child :: Tool
		end
	end
	return nil
end

function Abilities.Init()
	local gui = Ui.gui
	local button = Ui.button({
		-- Bottom right, above where the touch jump button sits and clear of the tool hotbar
		AnchorPoint = Vector2.new(1, 1),
		-- (phones: just left of the jump button, under the right thumb)
		Position = if Ui.Phone then UDim2.new(1, -160, 1, -22) else UDim2.new(1, -20, 1, -186),
		Size = if Ui.Phone then UDim2.fromOffset(180, 70) else UDim2.fromOffset(230, 64),
		BackgroundColor3 = Color3.fromRGB(200, 40, 60),
		Text = "",
		Visible = false,
	}, gui)

	-- The Murderer's perk: its Blender badge on the ability button, and a card above it that
	-- explains the perk (passive perks get the card only)
	local buttonIcon = Instance.new("ImageLabel")
	buttonIcon.Name = "PerkIcon"
	buttonIcon.AnchorPoint = Vector2.new(0, 0.5)
	buttonIcon.Position = UDim2.new(0, -18, 0.5, 0)
	buttonIcon.Size = UDim2.fromOffset(if Ui.Phone then 58 else 66, if Ui.Phone then 58 else 66)
	buttonIcon.BackgroundTransparency = 1
	buttonIcon.ZIndex = (button.ZIndex or 1) + 3
	buttonIcon.Visible = false
	buttonIcon.Parent = button
	local perkCard = Instance.new("Frame")
	perkCard.Name = "PerkCard"
	perkCard.AnchorPoint = Vector2.new(1, 1)
	perkCard.Position = if Ui.Phone then UDim2.new(1, -160, 1, -100) else UDim2.new(1, -20, 1, -262)
	perkCard.Size = UDim2.fromOffset(260, 70)
	perkCard.BackgroundColor3 = Color3.fromRGB(28, 20, 34)
	perkCard.BackgroundTransparency = 0.15
	perkCard.Visible = false
	perkCard.Parent = Ui.root
	Ui.corner(perkCard, 14)
	Ui.stroke(perkCard)
	local cardIcon = Instance.new("ImageLabel")
	cardIcon.Position = UDim2.fromOffset(4, 3)
	cardIcon.Size = UDim2.fromOffset(64, 64)
	cardIcon.BackgroundTransparency = 1
	cardIcon.Parent = perkCard
	local cardName = Ui.label({
		Position = UDim2.fromOffset(74, 4),
		Size = UDim2.new(1, -80, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 90, 100),
		Text = "",
	}, perkCard)
	Ui.textStroke(cardName, 2)
	local cardText = Ui.label({
		Position = UDim2.fromOffset(74, 30),
		Size = UDim2.new(1, -80, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextScaled = false,
		TextSize = 14,
		TextWrapped = true,
		Text = "",
	}, perkCard)
	Ui.textStroke(cardText, 1)
	local function refreshPerk()
		local id = player:GetAttribute("Perk")
		local perk = type(id) == "string" and GameConfig.Perks[id] or nil
		-- Codex's voxel power icon, else the old Blender render
		local icon = if type(id) == "string" then PowerIcons.KnifePowers[id] or Textures.PerkIcons[id] else nil
		perkCard.Visible = not Ui.Phone and not Ui.menuOpen() and perk ~= nil and player:GetAttribute("InRound") == true
		buttonIcon.Visible = icon ~= nil
		if perk then
			cardIcon.Image = icon or ""
			buttonIcon.Image = icon or ""
			cardName.Text = if perk.Passive then `{perk.DisplayName} (passive)` else perk.DisplayName
			cardText.Text = perk.Description
		end
	end
	player:GetAttributeChangedSignal("Perk"):Connect(refreshPerk)
	player:GetAttributeChangedSignal("InRound"):Connect(refreshPerk)
	refreshPerk()

	-- Crosshair + charge ring, shown while winding up a throw
	local crosshairGui = Instance.new("ScreenGui")
	crosshairGui.Name = "Crosshair"
	crosshairGui.ResetOnSpawn = false
	crosshairGui.IgnoreGuiInset = true
	crosshairGui.DisplayOrder = 5
	crosshairGui.Enabled = false
	crosshairGui.Parent = player:WaitForChild("PlayerGui")
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Size = UDim2.fromOffset(46, 46)
	ring.BackgroundTransparency = 1
	ring.Parent = crosshairGui
	Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Thickness = 3
	ringStroke.Color = Color3.new(1, 1, 1)
	ringStroke.Parent = ring
	local fill = Instance.new("Frame")
	fill.AnchorPoint = Vector2.new(0.5, 0.5)
	fill.Position = UDim2.fromScale(0.5, 0.5)
	fill.Size = UDim2.fromScale(0.15, 0.15)
	fill.BackgroundColor3 = Color3.fromRGB(255, 220, 120)
	fill.BackgroundTransparency = 0.25
	fill.Parent = ring
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(5, 5)
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.Parent = ring
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

	local abilityName: string? = nil
	local readyAt = 0
	local chargingSince: number? = nil
	-- "perk" = the ability button's throw (hub throw / Knife Throw perk), "basic" = the Murderer's
	-- hold-click throw that every Murderer has
	local chargeKind = "perk"
	local basicThrowReadyAt = 0
	local restoreFov = BASE_FOV
	-- The zoom to come back to, taken only when no lean is in progress: re-reading it on every press
	-- caught it mid-tween, so tapping the knife button zoomed the camera in a little more each time
	local leanBase: number? = nil
	local lastSwing = 0
	local comboIndex = 0

	local function isThrow(): boolean
		return abilityName ~= nil and (abilityName :: string):find("Throw") ~= nil
	end

	local function ready(): boolean
		return abilityName ~= nil and workspace:GetServerTimeNow() >= readyAt
	end

	local function zoom(fov: number)
		TweenService:Create(workspace.CurrentCamera, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
			FieldOfView = fov,
		}):Play()
	end

	local function holdingMurderKnife(): boolean
		local tool = knifeInHand()
		return tool ~= nil and tool:GetAttribute("MurderKnife") == true
	end

	-- Spam Knife (always) / Hellfire (a few seconds after Q): no stab, every click throws a knife
	-- straight at the cursor
	local lastSpam = 0
	local function spamMode(): boolean
		if not holdingMurderKnife() then
			return false
		end
		local until_ = player:GetAttribute("SpamUntil")
		return type(until_) == "number" and workspace:GetServerTimeNow() < until_
	end
	local function spamThrow(at: Vector2?, touch: boolean?)
		local now = os.clock()
		if now - lastSpam < 0.1 then
			return
		end
		lastSpam = now
		local character = player.Character
		if character then
			Moves.Play(character, "Throw")
		end
		Remotes.Ability:FireServer(aimDirection(at, touch), "Spam")
	end

	local function beginCharge(kind: string?)
		local basic = kind == "basic"
		if chargingSince or not drawKnife() then
			return
		end
		if basic and os.clock() < basicThrowReadyAt or not basic and not ready() then
			return
		end
		chargeKind = if basic then "basic" else "perk"
		chargingSince = os.clock()
		Moves.SetLocalCharge(chargingSince)
		Remotes.Charge:FireServer(true)
		crosshairGui.Enabled = true
		if leanBase == nil then
			leanBase = workspace.CurrentCamera.FieldOfView
		end
		restoreFov = leanBase :: number
		zoom(restoreFov - 10)
	end

	local function endCharge(throw: boolean)
		if not chargingSince then
			return
		end
		chargingSince = nil
		Moves.SetLocalCharge(nil)
		crosshairGui.Enabled = false
		zoom(restoreFov)
		task.delay(0.4, function()
			if not chargingSince then
				leanBase = nil -- back where it started: the next lean reads it fresh
			end
		end)
		local character = player.Character
		if throw and character and knifeInHand() then
			Moves.Play(character, "Throw")
			if chargeKind == "basic" then
				basicThrowReadyAt = os.clock() + GameConfig.MurdererThrowCooldown
				Remotes.Ability:FireServer(aimDirection(), "Throw")
			else
				Remotes.Ability:FireServer(aimDirection())
			end
		else
			Remotes.Charge:FireServer(false)
		end
	end

	-- Press: instant abilities fire; throws start charging
	local function press()
		if Ui.menuOpen() or not abilityName then
			return
		end
		if isThrow() then
			beginCharge()
		elseif ready() then
			Remotes.Ability:FireServer(aimDirection())
		end
	end
	local function release()
		endCharge(true)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or Ui.menuOpen() then
			return
		end
		if THROW_INPUTS[input.KeyCode] or THROW_INPUTS[input.UserInputType] then
			press()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if THROW_INPUTS[input.KeyCode] or THROW_INPUTS[input.UserInputType] then
			release()
		end
	end)

	-- Left click / screen tap / R2 with a knife in hand: tap = stab, hold = crank back and throw
	local primaryDown: InputObject? = nil
	local primaryAt = 0
	local function isPrimary(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or Ui.menuOpen() or not isPrimary(input) or not knifeInHand() then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			and WorldSignInput.Target(UserInputService:GetMouseLocation())
		then
			return -- a world-sign purchase/sale must not also swing or wind up the knife
		end
		if spamMode() then
			spamThrow(nil)
			return
		end
		primaryDown = input
		local pressedAt = os.clock()
		primaryAt = pressedAt
		task.delay(HOLD_TO_THROW, function()
			-- Still the same press, still held: it's a throw
			if primaryDown ~= input or primaryAt ~= pressedAt then
				return
			end
			if isThrow() and ready() then
				beginCharge()
			elseif holdingMurderKnife() then
				beginCharge("basic")
			end
		end)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if primaryDown ~= input then
			return
		end
		primaryDown = nil
		if chargingSince then
			release() -- it was a hold: throw
			return
		end
		local tool = knifeInHand()
		if tool then
			tool:Activate() -- it wasn't a throw: stab
		end
	end)
	-- The on-screen button: hold to charge on touch, click-hold with a mouse
	button.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			if not Ui.Phone or not isThrow() then
				press()
			end
		end
	end)
	button.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			if not Ui.Phone and isThrow() then
				release()
			end
		end
	end)

	local knifeButton = Ui.button({
		Name = "KnifeButton",
		Text = "",
		Size = UDim2.fromOffset(KNIFE_SIZE, KNIFE_SIZE),
		BackgroundColor3 = Color3.fromRGB(218, 56, 77),
		BackgroundTransparency = 0.65,
		Visible = false,
		ZIndex = 3,
	}, gui)
	local knifePadding = knifeButton:FindFirstChildOfClass("UIPadding")
	if knifePadding then
		knifePadding:Destroy()
	end
	local knifeCorner = knifeButton:FindFirstChildOfClass("UICorner") :: UICorner
	knifeCorner.CornerRadius = UDim.new(1, 0)
	local knifeBorder = knifeButton:FindFirstChildOfClass("UIStroke") :: UIStroke
	knifeBorder.Color, knifeBorder.Transparency = Color3.fromRGB(240, 250, 255), 0.2
	local knifeIcon = Ui.new("ImageLabel", {
		Name = "KnifeIcon",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(60, 52),
		Size = UDim2.fromOffset(64, 64),
		ZIndex = 3,
	}, knifeButton)
	-- It's a joystick, and it looks like one before you touch it: dotted spokes from the middle out
	-- to the rim, with the knife as the knob
	local joystickGuide = Ui.new("Frame", {
		Name = "JoystickGuide",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}, knifeButton)
	for spoke = 0, 7 do
		local angle = spoke / 8 * math.pi * 2
		for step, radius in { 0.56, 0.72, 0.88 } do
			local guideDot = Ui.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5 + math.cos(angle) * radius * 0.5, 0.5 + math.sin(angle) * radius * 0.5),
				Size = UDim2.fromScale(0.075 - step * 0.01, 0.075 - step * 0.01),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.25 + step * 0.12,
				ZIndex = 3,
			}, joystickGuide)
			Ui.new("UICorner", { CornerRadius = UDim.new(1, 0) }, guideDot)
		end
	end
	local knifeLabel = Ui.label({
		Text = "Knife",
		TextScaled = false,
		TextSize = 14,
		Position = UDim2.fromOffset(0, 94),
		Size = UDim2.new(1, 0, 0, 20),
		ZIndex = 3,
	}, knifeButton)
	local knifeFallback = Ui.label({
		Text = "🔪",
		TextScaled = false,
		TextSize = 56,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
	}, knifeIcon)
	local chargeOutline =
		Ui.new("UIStroke", { Thickness = 3, Color = Color3.fromRGB(255, 219, 89), Enabled = false }, knifeIcon)
	Ui.new("UICorner", { CornerRadius = UDim.new(1, 0) }, knifeIcon)
	local chargeSegments: { Frame } = {}
	for i = 1, 24 do
		local angle = (i / 24) * math.pi * 2 - math.pi / 2
		local segment = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(60 + math.cos(angle) * 55, 60 + math.sin(angle) * 55),
			Size = UDim2.fromOffset(4, 7),
			Rotation = math.deg(angle) + 90,
			BackgroundColor3 = Color3.fromRGB(255, 219, 89),
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 4,
		}, knifeButton)
		Ui.corner(segment, 2)
		chargeSegments[i] = segment
	end
	local overCancel = false -- the aiming thumb is on the X right now (let go = cancel)
	local cancelButton = Ui.button({
		Name = "CancelKnife",
		Text = "X",
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = Color3.fromRGB(43, 55, 80),
		Visible = false,
		ZIndex = 3,
	}, gui)
	local chargeHint = Ui.label({
		Text = "Release to throw",
		TextScaled = false,
		TextSize = 14,
		TextWrapped = true,
		Size = UDim2.fromOffset(150, 22),
		Visible = false,
		ZIndex = 3,
	}, gui)
	local gesture = KnifeGesture.new()
	local gestureTool: Tool? = nil
	local aimAxis = Vector2.zero
	local aimDelta = Vector2.zero
	local pointerOrigin = Vector2.zero
	local lastPointer = Vector2.zero
	local iconTool: Tool? = nil
	local iconStarted = 0
	local fallbackImage = ""
	local function allowed(): boolean
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local stunned = player:GetAttribute("StunnedUntil")
		return humanoid ~= nil
			and humanoid.Health > 0
			and not Ui.menuOpen()
			and not player:GetAttribute("Carrying")
			and (type(stunned) ~= "number" or stunned <= workspace:GetServerTimeNow())
	end
	local releaseCamera: () -> () = function() end
	local takeCameraHook: () -> () = function() end
	local function cancelKnife()
		releaseCamera()
		gui:SetAttribute("KnifeGestureActive", false)
		KnifeGesture.cancel(gesture)
		gestureTool = nil
		aimAxis = Vector2.zero
		aimDelta = Vector2.zero
		primaryDown = nil
		endCharge(false)
	end
	local function knifeAvailable(): Tool?
		local held = knifeInHand()
		if held then
			return held
		end
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			for _, tool in backpack:GetChildren() do
				if isKnife(tool) then
					return tool :: Tool
				end
			end
		end
		return nil
	end
	local function positionControls()
		local at = Ui.Layout.knifePosition()
		local x, y = at.X, at.Y
		local factor = Ui.Scale.Scale
		knifeButton.Position = UDim2.fromOffset(x / factor, y / factor)
		knifeButton.Size = UDim2.fromOffset(KNIFE_SIZE / factor, KNIFE_SIZE / factor)
		local aiming = gesture.mode == "charging" or gesture.mode == "spam"
		local center = KNIFE_SIZE / 2
		-- The knife is the stick's knob: centred until you drag it
		local knob = Vector2.new(center, center) + (if aiming then aimAxis * KNIFE_SIZE * 0.28 else Vector2.zero)
		knifeIcon.Position = UDim2.fromOffset(knob.X / factor, knob.Y / factor)
		local iconSize = KNIFE_SIZE * 0.5
		knifeIcon.Size = UDim2.fromOffset(iconSize / factor, iconSize / factor)
		knifeFallback.TextSize = KNIFE_SIZE * 0.3 / factor
		knifeLabel.Position = UDim2.fromOffset(0, (KNIFE_SIZE - 26) / factor)
		knifeLabel.Size = UDim2.new(1, 0, 0, 20 / factor)
		knifeLabel.TextSize = 18 / factor
		for i, segment in chargeSegments do
			local angle = (i / 24) * math.pi * 2 - math.pi / 2
			local radius = center - 5
			segment.Position = UDim2.fromOffset(
				(center + math.cos(angle) * radius) / factor,
				(center + math.sin(angle) * radius) / factor
			)
			segment.Size = UDim2.fromOffset(4 / factor, 9 / factor)
		end
		cancelButton.Position = UDim2.fromOffset((x + KNIFE_SIZE - 44) / factor, (y - 56) / factor)
		cancelButton.Size = UDim2.fromOffset(44 / factor, 44 / factor)
		local _, bounds = Ui.bounds()
		local hintX = x + KNIFE_SIZE + 12
		chargeHint.Position = UDim2.fromOffset(hintX / factor, (y - 44) / factor)
		chargeHint.Size = UDim2.fromOffset(math.max(44, math.min(112, bounds.X - hintX - 12)) / factor, 32 / factor)
		chargeHint.TextSize = 14 / factor
		if Ui.Phone then
			local padding = button:FindFirstChildOfClass("UIPadding")
			if padding then
				padding:Destroy()
			end
			button.AnchorPoint = Vector2.zero
			button.Position = UDim2.fromOffset((x - 96) / factor, (y + 14) / factor)
			button.Size = UDim2.fromOffset(64 / factor, 64 / factor)
			buttonIcon.Position, buttonIcon.Size =
				UDim2.fromOffset(4 / factor, 4 / factor), UDim2.fromOffset(56 / factor, 40 / factor)
			button.TextYAlignment = Enum.TextYAlignment.Bottom
			button.TextSize, button.TextScaled, button.TextTruncate = 14 / factor, false, Enum.TextTruncate.AtEnd
		end
	end
	local function onKnifeTouch(input: InputObject)
		if
			input.UserInputType ~= Enum.UserInputType.Touch
			and not (Ui.Phone and input.UserInputType == Enum.UserInputType.MouseButton1)
		then
			return
		end
		if not allowed() or gesture.owner ~= nil then
			return
		end
		local tool = drawKnife()
		if not tool then
			return
		end
		if KnifeGesture.press(gesture, input, os.clock()) then
			overCancel = false
			takeCameraHook()
			gui:SetAttribute("KnifeGestureActive", true)
			gestureTool = tool
			lastPointer = Vector2.new(input.Position.X, input.Position.Y)
			pointerOrigin = lastPointer
		end
	end
	knifeButton.InputBegan:Connect(onKnifeTouch)
	UserInputService.InputChanged:Connect(function(input)
		local previewMouse = RunService:IsStudio()
			and gesture.owner ~= nil
			and gesture.owner.UserInputType == Enum.UserInputType.MouseButton1
			and input.UserInputType == Enum.UserInputType.MouseMovement
		if input ~= gesture.owner and not previewMouse then
			return
		end
		local at = Vector2.new(input.Position.X, input.Position.Y)
		local pos, size = cancelButton.AbsolutePosition, cancelButton.AbsoluteSize
		-- Over the X: it lights up, and letting go THERE cancels (it used to cancel the moment the
		-- thumb slid across it - and aiming up-right runs straight over it)
		overCancel = cancelButton.Visible
			and at.X >= pos.X
			and at.X <= pos.X + size.X
			and at.Y >= pos.Y
			and at.Y <= pos.Y + size.Y
		cancelButton.BackgroundColor3 = if overCancel then Color3.fromRGB(220, 50, 60) else Color3.fromRGB(43, 55, 80)
		if overCancel then
			return
		end
		aimDelta += at - lastPointer
		lastPointer = at
		aimAxis = KnifeAim.Axis(at, pointerOrigin)
	end)
	-- While the knife joystick is held we own the camera (Scriptable): it orbits the character at the
	-- distance it had, turned only by the finger. Roblox's touch camera kept pulling the yaw back
	-- behind a moving character and fought the aim; with it paused nothing can. On release the
	-- camera goes back to Custom from exactly where the aim left it.
	local aimYaw, aimPitch, aimDistance = 0, 0, 12
	local owningCamera = false
	local function takeCamera()
		local camera = workspace.CurrentCamera
		if owningCamera or camera.CameraType ~= Enum.CameraType.Custom then
			return
		end
		local look = camera.CFrame.LookVector
		aimYaw = math.atan2(-look.X, -look.Z)
		aimPitch = math.asin(math.clamp(look.Y, -1, 1))
		aimDistance = math.max(0.5, (camera.CFrame.Position - camera.Focus.Position).Magnitude)
		camera.CameraType = Enum.CameraType.Scriptable
		owningCamera = true
	end
	releaseCamera = function()
		if owningCamera then
			owningCamera = false
			workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		end
	end
	takeCameraHook = takeCamera
	local function applyKnifeAim()
		if not owningCamera then
			return
		end
		local camera = workspace.CurrentCamera
		local character = player.Character
		local head = character
			and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
		if not head then
			return
		end
		if aimDelta ~= Vector2.zero then
			local delta =
				KnifeAim.RotationDelta(camera.CFrame, aimDelta, UserSettings().GameSettings:GetCameraYInvertValue())
			aimYaw -= delta.X
			aimPitch = math.clamp(aimPitch - delta.Y, math.rad(-80), math.rad(80))
			aimDelta = Vector2.zero
		end
		local focus = head.Position + Vector3.new(0, 0.5, 0)
		local rotation = CFrame.fromOrientation(aimPitch, aimYaw, 0)
		camera.CFrame = CFrame.new(focus - rotation.LookVector * aimDistance) * rotation
		camera.Focus = CFrame.new(focus)
	end
	UserInputService.InputEnded:Connect(function(input)
		if input ~= gesture.owner then
			return
		end
		if overCancel then
			overCancel = false
			cancelButton.BackgroundColor3 = Color3.fromRGB(43, 55, 80)
			cancelKnife()
			return
		end
		-- Consume the final movement before sampling the release crosshair.
		applyKnifeAim()
		-- Input may end between render ticks on a slow phone. Resolve the threshold first.
		local canCharge = if holdingMurderKnife() then os.clock() >= basicThrowReadyAt else isThrow() and ready()
		local pending = KnifeGesture.tick(gesture, os.clock(), canCharge, spamMode())
		if allowed() and gestureTool == knifeInHand() then
			if pending == "charge" then
				beginCharge(if holdingMurderKnife() then "basic" else "perk")
			elseif pending == "spam" then
				spamThrow(nil)
			end
		end
		local action = KnifeGesture.release(gesture, input, os.clock(), spamMode())
		if allowed() and gestureTool == knifeInHand() then
			if action == "swing" then
				(gestureTool :: Tool):Activate()
			elseif action == "throw" then
				endCharge(true)
			elseif action == "spam" then
				spamThrow(nil)
			end
		end
		cancelKnife()
	end)
	UserInputService.WindowFocusReleased:Connect(cancelKnife)
	gui:GetAttributeChangedSignal("MenuOpen"):Connect(function()
		if Ui.menuOpen() then
			cancelKnife()
		end
	end)
	player:GetAttributeChangedSignal("InRound"):Connect(cancelKnife)
	ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(cancelKnife)
	player:GetAttributeChangedSignal("StunnedUntil"):Connect(function()
		if not allowed() then
			cancelKnife()
		end
	end)
	player:GetAttributeChangedSignal("Carrying"):Connect(function()
		if not allowed() then
			cancelKnife()
		end
	end)
	player.CharacterAdded:Connect(cancelKnife)
	cancelButton.Activated:Connect(cancelKnife)
	RunService:BindToRenderStep("KnifeThumbAim", Enum.RenderPriority.Camera.Value + 1, applyKnifeAim)
	RunService.RenderStepped:Connect(function()
		local available = knifeAvailable()
		-- In a round the Murderer's knife works MM2 style once it's out (tap = stab, THROW button), so the
		-- knife button is only there to pull it out
		knifeButton.Visible = Ui.Phone
			and allowed()
			and available ~= nil
			and not (player:GetAttribute("InRound") and holdingMurderKnife() and gesture.owner == nil)
		if gesture.owner ~= nil and (not allowed() or gestureTool ~= knifeInHand()) then
			cancelKnife()
		end
		if Ui.Phone then
			positionControls()
			button.Visible = allowed() and abilityName ~= nil and not isThrow()
			perkCard.Visible = false
		end
		if not knifeButton.Visible then
			if Ui.Phone and gesture.owner ~= nil then
				cancelKnife()
			end
			cancelButton.Visible = false
			chargeHint.Visible = false
			return
		end
		if available ~= iconTool then
			iconTool, iconStarted = available, os.clock()
			knifeIcon.Image = if available then available.TextureId else ""
			local item = if available
				then available:GetAttribute("HubKnife") or player:GetAttribute("Equipped")
				else nil
			local parsed = if type(item) == "string" then Items.Parse(item) else nil
			fallbackImage = if parsed then Artwork[parsed.Knife.Name] or "" else ""
		end
		if not knifeIcon.IsLoaded and os.clock() - iconStarted > 8 and fallbackImage ~= "" then
			knifeIcon.Image = fallbackImage
		end
		knifeFallback.Visible = knifeIcon.Image == "" or not knifeIcon.IsLoaded
		local canCharge = if holdingMurderKnife() then os.clock() >= basicThrowReadyAt else isThrow() and ready()
		local action = KnifeGesture.tick(gesture, os.clock(), canCharge, spamMode())
		if action == "charge" then
			beginCharge(if holdingMurderKnife() then "basic" else "perk")
		elseif action == "spam" then
			spamThrow(nil)
		end
		cancelButton.Visible = false -- (no cancel: let go to throw, the rest of the screen just looks around)
		chargeHint.Visible = gesture.mode == "charging" or gesture.mode == "spam"
		chargeHint.Text = if gesture.mode == "charging"
			then "Release to throw"
			elseif gesture.mode == "spam" then "Drag: aim\nHold: throw"
			elseif spamMode() then "Tap: throw\nHold: repeat"
			else "Tap: stab\nHold: aim"
		knifeLabel.Text = if gesture.mode == "charging"
			then "Throw"
			elseif gesture.mode == "blocked" then "Wait"
			else "Knife"
		knifeButton.BackgroundColor3 = if gesture.owner
			then Color3.fromRGB(61, 178, 255)
			else Color3.fromRGB(218, 56, 77)
		knifeButton.BackgroundTransparency = if gesture.owner then 0.4 else 0.65
		knifeIcon.BackgroundColor3 = Color3.fromRGB(61, 178, 255)
		local aimingNow = gesture.mode == "charging" or gesture.mode == "spam"
		knifeIcon.BackgroundColor3 = if aimingNow then Color3.fromRGB(61, 178, 255) else Color3.fromRGB(20, 22, 34)
		knifeIcon.BackgroundTransparency = if aimingNow then 0.25 else 0.35
		knifeLabel.Visible = gesture.owner ~= nil
		joystickGuide.Visible = not aimingNow
		chargeOutline.Enabled = chargingSince ~= nil
		local fraction = if chargingSince
			then math.clamp((os.clock() - chargingSince) / AnimLibrary.ChargeTime, 0, 1)
			else 0
		for i, segment in chargeSegments do
			segment.Visible = chargingSince ~= nil
			segment.BackgroundTransparency = if i / 24 <= fraction then 0 else 0.8
		end
		chargeOutline.Thickness = if chargingSince
			then 2 + 4 * math.clamp((os.clock() - chargingSince) / AnimLibrary.ChargeTime, 0, 1)
			else 2
	end)

	Remotes:WaitForChild("AbilityState").OnClientEvent:Connect(function(name: string?, until_: number?)
		-- The hub knife's throw never belongs in a round (a late message can't bring it back)
		if name == "Throw Knife" and player:GetAttribute("InRound") then
			name = nil
		end
		abilityName = name
		readyAt = until_ or 0
		-- The hub throw is "hold click" with a mouse: the big button is only needed on touch screens
		button.Visible = name ~= nil and (Ui.Phone or name ~= "Throw Knife")
		button.BackgroundColor3 = if name == "Smoke Bomb"
			then Color3.fromRGB(120, 120, 140)
			else Color3.fromRGB(200, 40, 60)
		if not name then
			endCharge(false)
		end
	end)

	RunService.RenderStepped:Connect(function()
		if Ui.menuOpen() then
			button.Visible = false
			perkCard.Visible = false
			crosshairGui.Enabled = false
			endCharge(false)
			return
		end
		-- Button label + cooldown
		if abilityName then
			local left = readyAt - workspace:GetServerTimeNow()
			local key = if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
				then "LT"
				elseif UserInputService.TouchEnabled and not UserInputService.MouseEnabled then "Hold"
				else if isThrow() then "Hold Click" else "Q"
			if chargingSince then
				button.Text = "Release to throw!"
				button.BackgroundTransparency = 0
			elseif left > 0 then
				button.Text = `{abilityName}  {math.ceil(left)}s`
				button.BackgroundTransparency = 0.4
			else
				button.Text = if Ui.Phone then abilityName :: string else `[{key}] {abilityName}`
				button.BackgroundTransparency = 0
			end
		end
		-- Spam mode: a red crosshair on the cursor the whole time the knife is out
		if not chargingSince then
			local spamming = spamMode()
			crosshairGui.Enabled = spamming
			if spamming then
				local at = screenAim()
				ring.Position = UDim2.fromOffset(at.X, at.Y)
				ring.Size = UDim2.fromOffset(40, 40)
				ringStroke.Color = Color3.fromRGB(255, 70, 70)
				fill.Size = UDim2.fromScale(0.3, 0.3)
				fill.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
			end
		end
		-- Crosshair follows the aim point; the ring fills as the arm cranks back
		if chargingSince then
			if not knifeInHand() then
				endCharge(false)
				return
			end
			local fraction = math.clamp((os.clock() - chargingSince) / AnimLibrary.ChargeTime, 0, 1)
			local at = screenAim()
			ring.Position = UDim2.fromOffset(at.X, at.Y)
			fill.Size = UDim2.fromScale(0.15 + 0.85 * fraction, 0.15 + 0.85 * fraction)
			local full = fraction >= 1
			ringStroke.Color = if full then Color3.fromRGB(255, 70, 70) else Color3.new(1, 1, 1)
			fill.BackgroundColor3 = if full then Color3.fromRGB(255, 70, 70) else Color3.fromRGB(255, 220, 120)
			local pulse = if full then 1 + math.sin(os.clock() * 20) * 0.08 else 1
			ring.Size = UDim2.fromOffset(46 * pulse, 46 * pulse)
		end
	end)

	-- Phones: a big red THROW button while the Murderer's knife is out. It works like the hub's knife
	-- stick: press and drag to aim (the camera turns with your thumb, the knife goes where the dot in
	-- the middle of the screen is), let go to throw. A quick tap throws straight ahead.
	-- Looks like the hub's knife stick (see-through red disc, dotted spokes), with a THROW knob
	-- that follows your thumb
	local throwButton = Ui.button({
		Name = "ThrowButton",
		Text = "",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -60, 1, -150), -- above Jump, in from the edge
		Size = UDim2.fromOffset(170, 170),
		BackgroundColor3 = Color3.fromRGB(218, 56, 77),
		BackgroundTransparency = 0.6,
		Visible = false,
		ZIndex = 4,
	}, gui)
	local throwCorner = throwButton:FindFirstChildOfClass("UICorner")
	if throwCorner then
		throwCorner.CornerRadius = UDim.new(1, 0)
	end
	local throwPadding = throwButton:FindFirstChildOfClass("UIPadding")
	if throwPadding then
		throwPadding:Destroy()
	end
	local throwBorder = throwButton:FindFirstChildOfClass("UIStroke")
	if throwBorder then
		throwBorder.Color, throwBorder.Transparency = Color3.fromRGB(240, 250, 255), 0.2
	end
	for spoke = 0, 7 do
		local angle = spoke / 8 * math.pi * 2
		for step, radius in { 0.62, 0.76, 0.9 } do
			local guideDot = Ui.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5 + math.cos(angle) * radius * 0.5, 0.5 + math.sin(angle) * radius * 0.5),
				Size = UDim2.fromScale(0.07 - step * 0.01, 0.07 - step * 0.01),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.25 + step * 0.12,
				ZIndex = 4,
			}, throwButton)
			Ui.new("UICorner", { CornerRadius = UDim.new(1, 0) }, guideDot)
		end
	end
	local throwKnob = Ui.label({
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.6),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = Color3.fromRGB(218, 56, 77),
		Text = "THROW",
		TextScaled = true,
		ZIndex = 5,
	}, throwButton)
	Ui.new("UICorner", { CornerRadius = UDim.new(1, 0) }, throwKnob)
	Ui.new("UIStroke", { Color = Color3.fromRGB(240, 250, 255), Thickness = 2.5 }, throwKnob)
	Ui.new("UIPadding", {
		PaddingLeft = UDim.new(0.07, 0),
		PaddingRight = UDim.new(0.07, 0),
		PaddingTop = UDim.new(0.27, 0),
		PaddingBottom = UDim.new(0.27, 0),
	}, throwKnob)
	local throwStart = Vector2.zero
	-- The Mad Murderer crosshair: with a mouse, the pointer is a plain grey "+" while you're in a
	-- round or holding a knife / the Revolver (menus get the normal cursor back)
	local cursorGui = Instance.new("ScreenGui")
	cursorGui.Name = "Cursor"
	cursorGui.ResetOnSpawn = false
	cursorGui.IgnoreGuiInset = true
	cursorGui.DisplayOrder = 50
	cursorGui.Enabled = false
	cursorGui.Parent = player:WaitForChild("PlayerGui")
	local cross = Instance.new("Frame")
	cross.AnchorPoint = Vector2.new(0.5, 0.5)
	cross.Size = UDim2.fromOffset(26, 26)
	cross.BackgroundTransparency = 1
	cross.Parent = cursorGui
	for _, size in { Vector2.new(26, 6), Vector2.new(6, 26) } do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(size.X, size.Y)
		bar.BackgroundColor3 = Color3.fromRGB(70, 70, 76)
		bar.BorderSizePixel = 0
		bar.Parent = cross
		local edge = Instance.new("UIStroke")
		edge.Color, edge.Thickness = Color3.fromRGB(235, 235, 235), 1.5
		edge.Parent = bar
	end
	local cursorHidden = false
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		local armed = tool ~= nil and (isKnife(tool) or tool:GetAttribute("Revolver") ~= nil)
		local show = usingMouse()
			and UserInputService.MouseEnabled
			and not Ui.menuOpen()
			and (armed or player:GetAttribute("InRound") == true)
		cursorGui.Enabled = show
		if show then
			local at = UserInputService:GetMouseLocation()
			cross.Position = UDim2.fromOffset(at.X, at.Y)
		end
		if show ~= cursorHidden then
			cursorHidden = show
			UserInputService.MouseIconEnabled = not show
		end
	end)

	local dotGui = Instance.new("ScreenGui")
	dotGui.Name = "ThrowDot"
	dotGui.ResetOnSpawn = false
	dotGui.IgnoreGuiInset = true
	dotGui.DisplayOrder = 4
	dotGui.Parent = player:WaitForChild("PlayerGui")
	local centerDot = Instance.new("Frame")
	centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
	centerDot.Position = UDim2.fromScale(0.5, 0.5)
	centerDot.Size = UDim2.fromOffset(8, 8)
	centerDot.BackgroundColor3 = Color3.new(1, 1, 1)
	centerDot.BackgroundTransparency = 0.15
	centerDot.Visible = false
	centerDot.Parent = dotGui
	Instance.new("UICorner", centerDot).CornerRadius = UDim.new(1, 0)
	local dotStroke = Instance.new("UIStroke")
	dotStroke.Color, dotStroke.Thickness = Color3.new(0, 0, 0), 1.5
	dotStroke.Parent = centerDot
	local MIN_WINDUP = 0.3 -- a tap still gets a short wind-up, like MM2's
	local throwInput: InputObject? = nil
	throwButton.InputBegan:Connect(function(input)
		if
			input.UserInputType ~= Enum.UserInputType.Touch
			and input.UserInputType ~= Enum.UserInputType.MouseButton1
		then
			return
		end
		if throwInput or not allowed() or not holdingMurderKnife() then
			return
		end
		if spamMode() then
			spamThrow(nil)
			return
		end
		throwInput = input
		lastPointer = Vector2.new(input.Position.X, input.Position.Y)
		throwStart = lastPointer
		takeCameraHook()
		beginCharge("basic")
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input ~= throwInput then
			return
		end
		local at = Vector2.new(input.Position.X, input.Position.Y)
		aimDelta += at - lastPointer
		lastPointer = at
		-- the knob follows the thumb a little, like the hub stick
		local pull = at - throwStart
		if pull.Magnitude > 1 then
			pull = pull.Unit * math.min(pull.Magnitude, throwButton.AbsoluteSize.X * 0.25)
		end
		throwKnob.Position = UDim2.new(0.5, pull.X / Ui.Scale.Scale, 0.5, pull.Y / Ui.Scale.Scale)
	end)
	throwButton.InputEnded:Connect(function(input)
		if input ~= throwInput then
			return
		end
		throwInput = nil
		throwKnob.Position = UDim2.fromScale(0.5, 0.5)
		applyKnifeAim() -- (the last bit of the drag counts)
		local started = chargingSince
		if not started then
			releaseCamera()
			return
		end
		local left = MIN_WINDUP - (os.clock() - started)
		if left > 0 then
			task.delay(left, function()
				if chargingSince == started then
					endCharge(true)
				end
				releaseCamera()
			end)
		else
			endCharge(true)
			releaseCamera()
		end
	end)
	RunService.RenderStepped:Connect(function()
		local show = Ui.Phone
			and not usingMouse()
			and holdingMurderKnife()
			and allowed()
			and player:GetAttribute("InRound") == true
		throwButton.Visible = show
		if show then
			-- Same spot and size as the hub's knife stick, so your thumb finds it in both
			throwButton.AnchorPoint = knifeButton.AnchorPoint
			throwButton.Position = knifeButton.Position
			throwButton.Size = knifeButton.Size
		end
		centerDot.Visible = show and not chargingSince
		if show then
			local isReady = os.clock() >= basicThrowReadyAt or spamMode()
			throwKnob.BackgroundTransparency = if isReady then 0.1 else 0.55
			throwKnob.Text = if chargingSince
				then "LET GO"
				elseif isReady then "THROW"
				else `{math.ceil(basicThrowReadyAt - os.clock())}`
		end
	end)

	-- Who the Murderer's swing is at, as this screen sees it: the nearest living character in
	-- front (or right next to you). The server re-checks it with a little extra reach for lag.
	local function stabTarget(character: Model): Model?
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return nil
		end
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local best: Model?, bestScore = nil, math.huge
		local seen: { [Model]: boolean } = {}
		for _, part in workspace:GetPartBoundsInRadius(root.Position, GameConfig.AttackRange + 3, params) do
			local model = part:FindFirstAncestorOfClass("Model")
			local humanoid = model and model:FindFirstChildOfClass("Humanoid")
			local targetRoot = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not model or seen[model] or not humanoid or humanoid.Health <= 0 or not targetRoot then
				continue
			end
			seen[model] = true
			local offset = targetRoot.Position - root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local dist = flat.Magnitude
			local facing = if dist > 0.1 then look:Dot(flat.Unit) else 1
			if dist > GameConfig.AttackRange + 2.5 or (facing < 0.1 and dist > 4) then
				continue
			end
			local score = dist * (2 - facing) -- prefer whoever is straight ahead
			if score < bestScore then
				best, bestScore = model, score
			end
		end
		return best
	end

	-- Knife swings: animate the instant you click (same combo order as the server)
	local function wireKnife(tool: Tool)
		tool.ManualActivationOnly = true
		tool.Unequipped:Connect(cancelKnife)
		if tool:GetAttribute("Wired") then
			return
		end
		tool:SetAttribute("Wired", true)
		tool.Activated:Connect(function()
			local character = player.Character
			if not character or chargingSince or Ui.menuOpen() or not allowed() or spamMode() then
				return
			end
			local now = os.clock()
			local cooldown = if tool:GetAttribute("MurderKnife")
				then GameConfig.AttackCooldown
				else GameConfig.SwingCooldown
			if now - lastSwing < cooldown then
				return
			end
			comboIndex = if now - lastSwing > 1.2 then 1 else comboIndex % #COMBO + 1
			lastSwing = now
			Moves.Play(character, COMBO[comboIndex])
			if tool:GetAttribute("MurderKnife") then
				Remotes.Stab:FireServer(stabTarget(character))
			end
		end)
	end

	local shootAt: (aim: Vector3) -> () -- (below, with the reload bar)
	-- Revolver: every tool with the Revolver attribute fires at the aim point when activated
	local function watchTool(tool: Instance)
		if not tool:IsA("Tool") then
			return
		end
		if isKnife(tool) then
			wireKnife(tool)
		elseif tool:GetAttribute("Revolver") and not tool:GetAttribute("Wired") then
			tool:SetAttribute("Wired", true)
			-- A finger fires where it taps (TouchTapInWorld below); a mouse fires at the cursor here
			tool.Activated:Connect(function()
				if not Ui.menuOpen() and UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch then
					shootAt(aimPoint())
				end
			end)
		end
	end
	-- The Revolver's reload, shown on this screen: a shot taken during it would be thrown away
	-- by the server (GameConfig.RevolverCooldown), so a bar fills under the screen centre instead of
	-- the tap looking broken
	local lastShot = -math.huge
	local reloadBar: Frame = Ui.new("Frame", {
		Name = "ReloadBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 40),
		Size = UDim2.fromOffset(120, 12),
		BackgroundColor3 = Color3.fromRGB(20, 18, 30),
		BackgroundTransparency = 0.3,
		Visible = false,
		ZIndex = 20,
	}, Ui.gui)
	Ui.corner(reloadBar, 6)
	local reloadFill: Frame = Ui.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(255, 210, 70),
		ZIndex = 21,
	}, reloadBar)
	Ui.corner(reloadFill, 6)
	shootAt = function(aim: Vector3)
		local now = os.clock()
		if now - lastShot < GameConfig.RevolverCooldown then
			-- still reloading: nudge the bar so the tap visibly registered
			reloadBar.Size = UDim2.fromOffset(132, 14)
			task.delay(0.1, function()
				reloadBar.Size = UDim2.fromOffset(120, 12)
			end)
			return
		end
		lastShot = now
		Remotes.Shoot:FireServer(aim)
		reloadBar.Visible = true
		reloadFill.Size = UDim2.fromScale(0, 1)
		local reload = TweenService:Create(
			reloadFill,
			TweenInfo.new(GameConfig.RevolverCooldown, Enum.EasingStyle.Linear),
			{ Size = UDim2.fromScale(1, 1) }
		)
		reload:Play()
		task.delay(GameConfig.RevolverCooldown, function()
			if lastShot == now then
				reloadBar.Visible = false
			end
		end)
	end

	-- Phones, MM2 style: with the gun out, a quick tap anywhere shoots there the moment your finger
	-- lifts. Our own tap check (short and still), because TouchTapInWorld waited and dropped any tap
	-- with a little finger wobble. Gun still in the hotbar: the first tap pulls it out.
	local touches: { [InputObject]: { At: number, From: Vector3 } } = {}
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.UserInputType == Enum.UserInputType.Touch and not processed then
			touches[input] = { At = os.clock(), From = input.Position }
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local start = touches[input]
		touches[input] = nil
		if not start or not Ui.Phone or Ui.menuOpen() then
			return
		end
		if os.clock() - start.At > 0.45 or (input.Position - start.From).Magnitude > 40 then
			return -- a drag (turning the camera), not a tap
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid then
			return
		end
		local held = character:FindFirstChildOfClass("Tool")
		if held and held:GetAttribute("Revolver") then
			shootAt(tapAim(Vector2.new(input.Position.X, input.Position.Y)))
			return
		end
		if not held and player:GetAttribute("InRound") then
			local backpack = player:FindFirstChildOfClass("Backpack")
			for _, tool in if backpack then backpack:GetChildren() else {} do
				if tool:IsA("Tool") and tool:GetAttribute("Revolver") then
					humanoid:EquipTool(tool)
					return
				end
			end
		end
	end)

	-- Phones: with the Murderer's knife out, a tap stabs (Spam Knife: throws at the spot you tapped)
	UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processed: boolean)
		if processed or not Ui.Phone or Ui.menuOpen() or usingMouse() then
			return
		end
		local character = player.Character
		if not character then
			return
		end
		local gun = character:FindFirstChildOfClass("Tool")
		if gun and gun:GetAttribute("Revolver") then
			return -- (the gun's taps are handled above)
		end
		local knife = knifeInHand()
		if knife and knife:GetAttribute("MurderKnife") and allowed() then
			if spamMode() then
				spamThrow(position, true)
			else
				knife:Activate()
			end
		end
	end)

	local function watchContainer(container: Instance)
		for _, child in container:GetChildren() do
			watchTool(child)
		end
		container.ChildAdded:Connect(watchTool)
	end
	local function onCharacter(character: Model)
		watchContainer(character)
		cancelKnife()
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.Died:Connect(cancelKnife)
		end
	end
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	watchContainer(player:WaitForChild("Backpack"))
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			watchContainer(child)
		end
	end)
end

return Abilities
