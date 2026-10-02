--!strict
-- The heads-up before your first Murder Mystery round of the session: for the last 10 seconds of
-- the intermission a big card counts down and says what's about to happen, so the teleport into
-- the round map is exciting instead of confusing. First-time players (attribute FirstVisit, set
-- by RoundService) get the full explanation; everyone else a short reminder with their chance of
-- being the Murderer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Effects = require(script.Parent.Effects)
local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Sounds"))
local player = Players.LocalPlayer
local new = Ui.new

local RoundIntro = {}

local STATUS = "🔪 MURDER ROUND in" -- RoundService.IntermissionStatus
local WARN_AT = 10 -- seconds before the round

function RoundIntro.Init()
	local card = new("Frame", {
		Name = "RoundIntro",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(620, 190),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
		ZIndex = 60, -- over the welcome card (50s): it matters more right now
	}, Ui.gui)
	Ui.corner(card, 18)
	Ui.gradient(card, Color3.fromRGB(70, 16, 24), Color3.fromRGB(30, 8, 14))
	new("UIStroke", { Thickness = 5, Color = Color3.fromRGB(255, 70, 70) }, card)
	local scale = new("UIScale", {}, card)
	local title = Ui.label({
		Size = UDim2.new(1, -30, 0, 70),
		Position = UDim2.fromOffset(15, 10),
		Font = Ui.SPOOKY,
		TextColor3 = Color3.fromRGB(255, 70, 70),
		Text = "",
		ZIndex = 61,
	}, card)
	Ui.textStroke(title, 4)
	local body = Ui.label({
		Size = UDim2.new(1, -40, 0, 92),
		Position = UDim2.fromOffset(20, 86),
		TextWrapped = true,
		Text = "",
		ZIndex = 61,
	}, card)
	Ui.textStroke(body, 2.5)

	local shownThisSession = false
	local showing = false
	local lastSecond = -1

	local function hide()
		if not showing then
			return
		end
		showing = false
		TweenService:Create(scale, TweenInfo.new(0.2), { Scale = 0.6 }):Play()
		task.delay(0.2, function()
			if not showing then
				card.Visible = false
			end
		end)
	end

	RunService.Heartbeat:Connect(function()
		local phase = ReplicatedStorage:GetAttribute("Phase")
		local status = ReplicatedStorage:GetAttribute("Status")
		local endsAt = ReplicatedStorage:GetAttribute("PhaseEndsAt")
		if
			phase ~= "Intermission"
			or status ~= STATUS
			or type(endsAt) ~= "number"
			or player:GetAttribute("InRound")
		then
			hide()
			return
		end
		local left = endsAt - workspace:GetServerTimeNow()
		if left > WARN_AT or left <= 0 then
			hide()
			return
		end
		if not showing then
			if shownThisSession then
				return
			end
			shownThisSession = true
			showing = true
			card.Visible = true
			scale.Scale = 0.6
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			Effects.Sound(Sounds.Sting, nil, 0.7)
			if player:GetAttribute("FirstVisit") then
				body.Text = "Everyone here is about to play MURDER MYSTERY! One player is secretly the MURDERER. "
					.. "Everyone else: SURVIVE! Grab coins for powers - and if you find the Revolver, shoot the Murderer!"
			else
				local chance = player:GetAttribute("MurdererChance")
				body.Text =
					`Who's the Murderer this time? Your chance: {chance or "?"}%. Innocents: survive and find the Revolver!`
			end
		end
		local second = math.ceil(left)
		if second ~= lastSecond then
			lastSecond = second
			title.Text = `🔪 MURDER ROUND IN {second}`
			if second <= 5 then
				Effects.Sound(Sounds.Tick, nil, 0.6)
			end
		end
	end)
end

return RoundIntro
