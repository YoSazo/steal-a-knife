--!strict
-- Spectate the murder round, MM2 style. While a round is on and you're not in it (you died, or you
-- weren't pulled in), an eye button shows on the left. Tap it and the camera follows someone still
-- alive; a slim bar at the bottom shows their name between < and > (Q / E or the arrow keys on a
-- keyboard). Ends by itself when the round does.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer
local Spectate = {}

local DARK = Color3.fromRGB(16, 16, 22)
local ROUND_CENTER = Vector3.new(3000, 0, 0) -- MapService.RoundCenter: the round maps are far away

local function roundOn(): boolean
	return ReplicatedStorage:GetAttribute("Phase") == "Round"
end

-- Everyone still alive in the round: players with InRound, and living round bots
local function alive(): { Model }
	local list = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if
			other ~= player
			and other:GetAttribute("InRound")
			and humanoid
			and humanoid.Health > 0
			and (character :: Model):IsDescendantOf(workspace) -- streamed in
		then
			table.insert(list, character :: Model)
		end
	end
	local bots = workspace:FindFirstChild("RoundBots")
	for _, bot in if bots then bots:GetChildren() else {} do
		local humanoid = bot:FindFirstChildOfClass("Humanoid")
		if bot:IsA("Model") and humanoid and humanoid.Health > 0 and bot.PrimaryPart then
			table.insert(list, bot)
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

local function nameOf(model: Model): string
	local owner = Players:GetPlayerFromCharacter(model)
	return if owner then owner.DisplayName else model.Name
end

local function roundButton(parent: Instance, text: string, size: number): TextButton
	local button = Ui.new("TextButton", {
		Text = text,
		Font = Enum.Font.FredokaOne,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.25,
		AutoButtonColor = true,
		Size = UDim2.fromOffset(size, size),
	}, parent)
	Ui.new("UICorner", { CornerRadius = UDim.new(0.3, 0) }, button)
	Ui.new("UIPadding", {
		PaddingTop = UDim.new(0.18, 0),
		PaddingBottom = UDim.new(0.18, 0),
		PaddingLeft = UDim.new(0.12, 0),
		PaddingRight = UDim.new(0.12, 0),
	}, button)
	return button
end

function Spectate.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Spectate"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The eye: left side, a little under the middle (the hub buttons hide while a round is on)
	local eye = roundButton(gui, "👁", if Ui.Phone then 52 else 60)
	eye.Name = "SpectateButton"
	eye.AnchorPoint = Vector2.new(0, 0.5)
	eye.Position = UDim2.new(0, 14, 0.5, 0)
	eye.Visible = false

	-- The bar: < name > at the bottom, above the hotbar and health bar
	local bar = Ui.new("Frame", {
		Name = "SpectateBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if Ui.Phone then -64 else -96),
		Size = UDim2.fromOffset(if Ui.Phone then 300 else 380, if Ui.Phone then 46 else 54),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	local height = if Ui.Phone then 46 else 54
	local keyboard = not Ui.Phone
	local previous = roundButton(bar, if keyboard then "◀ Q" else "<", height)
	previous.Name = "Previous"
	previous.AnchorPoint = Vector2.new(0, 0.5)
	previous.Position = UDim2.fromScale(0, 0.5)
	previous.Size = UDim2.fromOffset(if keyboard then height * 1.4 else height, height)
	local nextButton = roundButton(bar, if keyboard then "E ▶" else ">", height)
	nextButton.Name = "Next"
	nextButton.AnchorPoint = Vector2.new(1, 0.5)
	nextButton.Position = UDim2.fromScale(1, 0.5)
	nextButton.Size = previous.Size
	local nameLabel = Ui.new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -2 * (previous.Size.X.Offset + 10), 0.8, 0),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.35,
		Font = Enum.Font.FredokaOne,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		Text = "",
	}, bar)
	Ui.new("UICorner", { CornerRadius = UDim.new(0.3, 0) }, nameLabel)
	Ui.new(
		"UIStroke",
		{ Color = Color3.new(0, 0, 0), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual },
		nameLabel
	)
	Ui.new("UIPadding", { PaddingTop = UDim.new(0.12, 0), PaddingBottom = UDim.new(0.12, 0) }, nameLabel)

	local watching: Model? = nil
	local spectating = false
	local lastStream = 0

	local function follow(model: Model?)
		watching = model
		local camera = workspace.CurrentCamera
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
			nameLabel.Text = nameOf(model :: Model)
		else
			nameLabel.Text = "Nobody left"
		end
	end

	local function stop()
		if not spectating then
			return
		end
		spectating = false
		watching = nil
		bar.Visible = false
		player:SetAttribute("Spectating", nil)
		ContextActionService:UnbindAction("SpectateStep")
		local own = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if own then
			local camera = workspace.CurrentCamera
			camera.CameraSubject = own
		end
	end

	local function step(direction: number)
		local list = alive()
		if #list == 0 then
			follow(nil)
			return
		end
		local index = (watching and table.find(list, watching :: Model)) or 0
		index = (index - 1 + direction) % #list + 1
		follow(list[index])
	end

	local function start()
		if spectating or not roundOn() or player:GetAttribute("InRound") then
			return
		end
		spectating = true
		bar.Visible = true
		player:SetAttribute("Spectating", true)
		-- Q / E (and the arrows) step through people; sunk so they don't throw or press prompts
		ContextActionService:BindActionAtPriority(
			"SpectateStep",
			function(_, state, input)
				if state ~= Enum.UserInputState.Begin then
					return Enum.ContextActionResult.Sink
				end
				local back = input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.Left
				step(if back then -1 else 1)
				return Enum.ContextActionResult.Sink
			end,
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.KeyCode.Q,
			Enum.KeyCode.E,
			Enum.KeyCode.Left,
			Enum.KeyCode.Right
		)
		nameLabel.Text = "Loading..."
		-- The round map is far from the hub: stream it in first, then pick someone
		task.spawn(function()
			pcall(player.RequestStreamAroundAsync, player, ROUND_CENTER, 4)
			if spectating then
				step(1)
			end
		end)
	end

	eye.Activated:Connect(function()
		if spectating then
			stop()
		else
			start()
		end
	end)
	previous.Activated:Connect(function()
		step(-1)
	end)
	nextButton.Activated:Connect(function()
		step(1)
	end)

	RunService.Heartbeat:Connect(function()
		local canWatch = roundOn() and not player:GetAttribute("InRound")
		eye.Visible = canWatch and not Ui.menuOpen()
		-- In the left column, right under the last button (More); Slow Mode moves down under it
		-- (client/Menus). It used to sit in the middle of the left edge, on top of More.
		local nav = Ui.Navigation :: GuiObject?
		if eye.Visible and nav and nav.Visible then
			local bottom = nav.AbsolutePosition.Y
			for _, child in nav:GetChildren() do
				if child:IsA("GuiObject") and child.Visible and child.Name ~= "Slow" then
					bottom = math.max(bottom, child.AbsolutePosition.Y + child.AbsoluteSize.Y)
				end
			end
			eye.AnchorPoint = Vector2.zero
			eye.Position =
				UDim2.fromOffset(nav.AbsolutePosition.X - gui.AbsolutePosition.X, bottom - gui.AbsolutePosition.Y + 8)
		end
		eye.BackgroundColor3 = if spectating then Color3.fromRGB(40, 110, 200) else DARK
		if spectating and not canWatch then
			stop()
			return
		end
		if not spectating then
			return
		end
		-- The one we watch died or left: on to the next
		local model = watching
		local humanoid = model and model.Parent and model:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			step(1)
			return
		end
		-- The round map is far away: keep it streamed in around them
		local root = (model :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and os.clock() - lastStream > 2 then
			lastStream = os.clock()
			task.spawn(function()
				pcall(player.RequestStreamAroundAsync, player, root.Position, 2)
			end)
		end
	end)
	player.CharacterAdded:Connect(function()
		if spectating then
			task.defer(function()
				if watching then
					follow(watching)
				end
			end)
		end
	end)
end

return Spectate
