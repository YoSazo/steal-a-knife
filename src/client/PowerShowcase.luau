--!strict
-- "Your knife's power" - shown once at the end of the tutorial, so a new player gets the value of
-- their knife straight away: the power's picture and name, what it does for the Murderer in plain
-- words, and a "Show me!" button that demos it on the spot (Shadow: you vanish for a few
-- seconds - on your own screen; it's a demo). SimpleUi look.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Ui = require(script.Parent.Ui)
local SimpleUi = require(script.Parent.SimpleUi)
local Effects = require(script.Parent.Effects)
local Icons = require(ReplicatedStorage.Shared.Config.VoxelPowerIcons)
local KnifePowers = require(ReplicatedStorage.Shared.Config.KnifePowers)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local player = Players.LocalPlayer

local PowerShowcase = {}

local PURPLE = Color3.fromRGB(150, 70, 235)
local GREEN = Color3.fromRGB(80, 210, 50)
local MURDERER = Color3.fromRGB(255, 130, 130)

-- Demos that work anywhere, on this screen only. Powers without one just get the card.
local DEMOS: { [string]: () -> () } = {
	Invisiknife = function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not root then
			return
		end
		Effects.Burst(root.Position, Color3.fromRGB(170, 120, 255), 40, 16, 0.8)
		Effects.Sound(Sounds.Lunge, root.Position, 0.9)
		local parts = {}
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				table.insert(parts, d)
				d.LocalTransparencyModifier = 0.85
			end
		end
		task.delay(3, function()
			for _, d in parts do
				if d.Parent then
					d.LocalTransparencyModifier = 0
				end
			end
			if root.Parent then
				Effects.Burst(root.Position, Color3.fromRGB(170, 120, 255), 30, 14, 0.7)
			end
		end)
	end,
}

local showing = false

-- A round about to start (or on) would cover the card: wait until you're back in the hub with time
local function roundSoon(): boolean
	if player:GetAttribute("InRound") then
		return true
	end
	local endsAt = ReplicatedStorage:GetAttribute("PhaseEndsAt")
	return ReplicatedStorage:GetAttribute("Phase") ~= "Intermission"
		or (type(endsAt) == "number" and endsAt - workspace:GetServerTimeNow() < 25)
end

function PowerShowcase.Show()
	if showing then
		return
	end
	showing = true
	while roundSoon() do
		task.wait(1)
	end
	task.wait(0.5)
	local id = player:GetAttribute("PowerId")
	local power = type(id) == "string" and KnifePowers.ById[id] or nil
	if not power then
		showing = false
		return
	end
	local tier = KnifePowers.TierById[power.Tier]
	local short = KnifePowers.Short[power.Id] or { "", "" }
	local demo = DEMOS[power.Id]
	local function targetScale(): number
		local _, bounds = Ui.bounds()
		return math.min(0.85, bounds.Y * 0.6 / 400, bounds.X * 0.5 / 560)
	end

	local card: Frame = Ui.new("Frame", {
		Name = "PowerShowcase",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 400),
		BackgroundColor3 = Color3.fromRGB(34, 38, 56),
		BackgroundTransparency = 0.05,
		ZIndex = 60,
	}, Ui.gui)
	Ui.corner(card, 18)
	Ui.new("UIStroke", { Color = PURPLE, Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	local scale = Ui.new("UIScale", { Scale = targetScale() * 0.85 }, card) :: UIScale
	local opening: Tween? = nil
	local closed = false
	local layoutWatch = Ui.Layout.Changed:Connect(function()
		if not closed then
			if opening then
				opening:Cancel()
			end
			scale.Scale = targetScale()
		end
	end)
	SimpleUi.text(card, "Your knife's power:", {
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.new(1, -40, 0, 36),
		Max = 30,
		ZIndex = 61,
	})
	Ui.new("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, 52),
		Size = UDim2.fromOffset(120, 120),
		Image = Icons.KnifePowers[power.Id] or "",
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 61,
	}, card)
	SimpleUi.text(card, power.Name, {
		Position = UDim2.fromOffset(20, 172),
		Size = UDim2.new(1, -40, 0, 50),
		TextColor3 = tier.Color,
		Max = 46,
		ZIndex = 61,
	})
	SimpleUi.text(card, `Murderer power: {short[1]}`, {
		Position = UDim2.fromOffset(20, 226),
		Size = UDim2.new(1, -40, 0, 32),
		TextColor3 = MURDERER,
		Max = 26,
		ZIndex = 61,
	})

	local function close()
		if closed or not card.Parent then
			return
		end
		closed = true
		if opening then
			opening:Cancel()
		end
		showing = false
		TweenService:Create(scale, TweenInfo.new(0.15), { Scale = scale.Scale * 0.8 }):Play()
		task.delay(0.15, function()
			card:Destroy()
		end)
	end
	local main = SimpleUi.button(card, if demo then "Show me!" else "Got it!", GREEN, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(260, 74),
		ZIndex = 62,
		Max = 34,
	})
	local demoed = false
	main.Activated:Connect(function()
		if demo and not demoed then
			demoed = true
			demo()
			-- the card steps aside so you can watch, then you're done
			card.Visible = false
			task.delay(3.4, function()
				if card.Parent then
					card.Visible = not player:GetAttribute("InRound")
					SimpleUi.set(main, "Got it!", GREEN, true)
				end
			end)
			return
		end
		close()
	end)

	-- A round starting while it's open closes it for good (it used to come back the moment you
	-- died - on top of the round's results card), and nobody tapping it for 15 s closes it too:
	-- it must never sit there hiding the guide's DO line (the round teaches the power anyway)
	local roundWatch = player:GetAttributeChangedSignal("InRound"):Connect(function()
		if player:GetAttribute("InRound") then
			close()
		end
	end)
	task.delay(15, function()
		if not demoed then
			close()
		end
	end)
	card.Destroying:Connect(function()
		roundWatch:Disconnect()
		layoutWatch:Disconnect()
	end)

	Effects.Sound(Sounds.Reveal, nil, 0.6)
	-- A card in the middle, not the whole screen: at most ~60% of the height and half the width
	-- (at full size it filled a phone screen)
	local tween = TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Scale = targetScale() })
	opening = tween
	tween:Play()
end

return PowerShowcase
