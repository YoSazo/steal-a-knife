--!strict
-- The last 10 seconds before a round. The top timer itself turns red and pulses (client/Hud) - there
-- used to be a second big red countdown here, and on phones it sat right on top of the timer.
-- This adds what the timer can't: a tick on 3-2-1, and for first-time players (attribute FirstVisit,
-- set by RoundService) one small rule line under the prize line.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Ui = require(script.Parent.Ui)
local Effects = require(script.Parent.Effects)
local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Sounds"))
local player = Players.LocalPlayer

local RoundIntro = {}

local STATUS = "🔪 MURDER ROUND in" -- RoundService.IntermissionStatus
local WARN_AT = 10 -- seconds before the round

function RoundIntro.Init()
	local rule = Ui.label({
		Name = "RoundIntroRule",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(560, 22),
		TextScaled = false,
		TextSize = if Ui.Phone then 15 else 17,
		TextColor3 = Color3.fromRGB(255, 120, 120),
		Text = "One player is secretly the Murderer. Everyone else: survive!",
		Visible = false,
	}, Ui.gui)
	Ui.textStroke(rule, 2)
	-- just under the Murderer chance (client/Hud publishes where its lines start: under the top line)
	local function place()
		local top = (Ui.gui:GetAttribute("HudTop") or 0) :: number
		rule.Position = UDim2.new(0.5, 0, 0, top + 22)
	end
	Ui.gui:GetAttributeChangedSignal("HudTop"):Connect(place)
	Ui.Layout.Changed:Connect(place)
	place()

	local lastSecond = -1
	RunService.Heartbeat:Connect(function()
		local endsAt = ReplicatedStorage:GetAttribute("PhaseEndsAt")
		local left = if type(endsAt) == "number" then endsAt - workspace:GetServerTimeNow() else math.huge
		local counting = ReplicatedStorage:GetAttribute("Phase") == "Intermission"
			and ReplicatedStorage:GetAttribute("Status") == STATUS
			and left <= WARN_AT
			and left > 0
			and not player:GetAttribute("InRound")
		rule.Visible = counting and player:GetAttribute("FirstVisit") == true and not Ui.menuOpen()
		if not counting then
			lastSecond = -1
			return
		end
		local second = math.ceil(left)
		if second ~= lastSecond then
			lastSecond = second
			if second <= 3 then
				Effects.Sound(Sounds.Tick, nil, 0.35)
			end
		end
	end)
end

return RoundIntro
