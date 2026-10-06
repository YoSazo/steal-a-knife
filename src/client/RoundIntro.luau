--!strict
-- The heads-up before your first Murder Mystery round of the session: for the last 10 seconds of
-- the intermission, big red text in the middle counts down (no box, no sting - kept simple).
-- First-time players (attribute FirstVisit, set by RoundService) get one short line under it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Effects = require(script.Parent.Effects)
local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Sounds"))
local RoundPrize = require(ReplicatedStorage.Shared.RoundPrize)
local player = Players.LocalPlayer
local new = Ui.new

local RoundIntro = {}

local STATUS = "🔪 MURDER ROUND in" -- RoundService.IntermissionStatus
local WARN_AT = 10 -- seconds before the round

function RoundIntro.Init()
	local card = new("Frame", {
		Name = "RoundIntro",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromOffset(760, 190),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 60,
	}, Ui.gui)
	local scale = new("UIScale", {}, card)
	local title = Ui.label({
		Size = UDim2.new(1, 0, 0, 80),
		Font = Enum.Font.FredokaOne,
		TextColor3 = Color3.fromRGB(255, 60, 60),
		Text = "",
		ZIndex = 61,
	}, card)
	Ui.textStroke(title, 4)
	local body = Ui.label({
		Size = UDim2.new(1, 0, 0, 96),
		Position = UDim2.fromOffset(0, 86),
		Font = Enum.Font.FredokaOne,
		RichText = true,
		Text = "",
		ZIndex = 61,
	}, card)
	Ui.textStroke(body, 3)

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
			Ui.Menu.Close()
			card.Visible = true
			scale.Scale = 0.6
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			-- What each side wins (the same line as under the timer), plus the rule for first-timers
			local lines = {}
			if player:GetAttribute("FirstVisit") then
				table.insert(lines, "One player is secretly the Murderer. Everyone else: survive!")
			end
			local kind = ReplicatedStorage:GetAttribute("PrizeKind")
			if type(kind) == "string" then
				local jackpot = ReplicatedStorage:GetAttribute("PrizeJackpot") == true
				local seed = (ReplicatedStorage:GetAttribute("PrizeSeed") or 1) :: number
				local doubled = ((player:GetAttribute("Charge_DoublePrize") or 0) :: number) > 0
				local stats = RoundPrize.Stats(player)
				local innocent = RoundPrize.For(kind, "Innocent", jackpot, seed, stats, doubled)
				local murderer = RoundPrize.For(kind, "Murderer", jackpot, seed, stats, doubled)
				table.insert(lines, `<font color="#8CFF96">😇 If Innocents win: {innocent.Text}</font>`)
				table.insert(lines, `<font color="#FF7878">🔪 If the Murderer wins: {murderer.Text}</font>`)
			end
			body.Text = table.concat(lines, "\n")
		end
		local second = math.ceil(left)
		if second ~= lastSecond then
			lastSecond = second
			title.Text = `🔪 MURDER ROUND IN {second}`
			if second <= 3 then
				Effects.Sound(Sounds.Tick, nil, 0.35)
			end
		end
	end)
end

return RoundIntro
