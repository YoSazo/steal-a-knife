--!strict
-- Roblox's "Get notifications from this experience?" opt-in (GameConfig.Notify). Asked once a
-- session, back in the hub after a round, once you've played AskAfterRounds of them (you know the
-- game by then), and only after the round's cards are gone (never on top of the favourite prompt).
-- Roblox decides who can see it (13+, not asked in the last 30 days, not already on). Shown ->
-- Remotes.NotifyAsked, so NotifyService plans a "your vault filled up" reminder when you leave.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Ui = require(script.Parent.Ui)
local Telemetry = require(script.Parent.Telemetry)

local player = Players.LocalPlayer
local NotifyOptIn = {}

local CONFIG = GameConfig.Notify

function NotifyOptIn.Init()
	if not CONFIG.Enabled then
		return
	end
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local asked = false
	local function maybeAsk()
		if asked or player:GetAttribute("InRound") then
			return
		end
		if ((player:GetAttribute("RoundsPlayed") or 0) :: number) < CONFIG.AskAfterRounds then
			return
		end
		asked = true
		task.spawn(function()
			-- let the results, prize and favourite prompt finish first
			task.wait(12)
			local started = os.clock()
			while
				(Ui.gui:GetAttribute("Presenting") == true or Ui.menuOpen() or player:GetAttribute("InRound"))
				and os.clock() - started < 60
			do
				task.wait(1)
			end
			local service = game:GetService("ExperienceNotificationService")
			local ok, can = pcall(service.CanPromptOptInAsync, service)
			if not ok or not can then
				return
			end
			Remotes:WaitForChild("NotifyAsked"):FireServer()
			Telemetry.Track("notify.prompt", { shown = true })
			pcall(service.PromptOptIn, service)
		end)
	end
	player:GetAttributeChangedSignal("InRound"):Connect(maybeAsk)
	player:GetAttributeChangedSignal("RoundsPlayed"):Connect(maybeAsk)
end

return NotifyOptIn
