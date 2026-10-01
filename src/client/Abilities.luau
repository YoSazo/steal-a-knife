--!strict
-- Knife controls from the client side, MM2 style:
--   * tap left click (or the screen) with a knife: stab / slash combo
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
local AnimLibrary = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AnimLibrary"))
local GameConfig = require(ReplicatedStorage.Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
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

-- Mouse/touch aim at whatever is under the pointer; gamepad aims through the screen centre
local function screenAim(): Vector2
	local camera = workspace.CurrentCamera
	local lastInput = UserInputService:GetLastInputType()
	if lastInput.Name:find("Gamepad") or UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return camera.ViewportSize / 2
	end
	return UserInputService:GetMouseLocation()
end

local function aimPoint(): Vector3
	local camera = workspace.CurrentCamera
	local screen = screenAim()
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	return if hit then hit.Position else ray.Origin + ray.Direction * 300
end

-- Direction from the character to what's under the cursor / crosshair, like MM2's knife throw
local function aimDirection(): Vector3
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not head then
		return workspace.CurrentCamera.CFrame.LookVector
	end
	local offset = aimPoint() - head.Position
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
		Position = UDim2.new(1, -20, 1, -186),
		Size = UDim2.fromOffset(230, 64),
		BackgroundColor3 = Color3.fromRGB(200, 40, 60),
		Text = "",
		Visible = false,
	}, gui)

	-- Crosshair + charge ring, shown while winding up a throw
	local crosshairGui = Instance.new("ScreenGui")
	crosshairGui.Name = "Crosshair"
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
		zoom(BASE_FOV - 10)
	end

	local function endCharge(throw: boolean)
		if not chargingSince then
			return
		end
		chargingSince = nil
		Moves.SetLocalCharge(nil)
		crosshairGui.Enabled = false
		zoom(BASE_FOV)
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
		if not abilityName then
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
		if processed then
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
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonR2
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not isPrimary(input) or not knifeInHand() then
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
			press()
		end
	end)
	button.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			release()
		end
	end)

	Remotes:WaitForChild("AbilityState").OnClientEvent:Connect(function(name: string?, until_: number?)
		abilityName = name
		readyAt = until_ or 0
		button.Visible = name ~= nil
		button.BackgroundColor3 = if name == "Smoke Bomb"
			then Color3.fromRGB(120, 120, 140)
			else Color3.fromRGB(200, 40, 60)
		if not name then
			endCharge(false)
		end
	end)

	RunService.RenderStepped:Connect(function()
		-- Button label + cooldown
		if abilityName then
			local left = readyAt - workspace:GetServerTimeNow()
			local key = if UserInputService.GamepadEnabled
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
				button.Text = `[{key}] {abilityName}`
				button.BackgroundTransparency = 0
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
		if tool:GetAttribute("Wired") then
			return
		end
		tool:SetAttribute("Wired", true)
		tool.Activated:Connect(function()
			local character = player.Character
			if not character or chargingSince then
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

	-- Revolver: every tool with the Revolver attribute fires at the aim point when activated
	local function watchTool(tool: Instance)
		if not tool:IsA("Tool") then
			return
		end
		if isKnife(tool) then
			wireKnife(tool)
		elseif tool:GetAttribute("Revolver") and not tool:GetAttribute("Wired") then
			tool:SetAttribute("Wired", true)
			tool.Activated:Connect(function()
				Remotes.Shoot:FireServer(aimPoint())
			end)
		end
	end
	local function watchContainer(container: Instance)
		for _, child in container:GetChildren() do
			watchTool(child)
		end
		container.ChildAdded:Connect(watchTool)
	end
	local function onCharacter(character: Model)
		watchContainer(character)
		endCharge(false)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.Died:Connect(function()
				endCharge(false)
			end)
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
