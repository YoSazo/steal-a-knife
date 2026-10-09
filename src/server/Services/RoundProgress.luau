--!strict
-- A frozen budget per round; each reached step is banked once through DataService.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RoundPrize = require(ReplicatedStorage.Shared.RoundPrize)
local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)
local Net = require(script.Parent.Parent.Remotes)

local Progress = {}
type Entry = {
	Full: number,
	Banked: number,
	Step: number,
	Kills: number,
	Enemies: number,
	Murderer: boolean,
	Started: number,
	Finished: boolean,
	Reached: number?,
	Coins: number,
}
local entries: { [Player]: Entry } = {}
local TIMES = { 10, 20, 35, 50, 60 }
local PARTS = { 1, 2, 4, 7, 12 }
local TOTAL = 26

local function budget(player: Player, round: boolean): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	local prize = RoundPrize.For("Speed", "", false, 0, RoundPrize.Stats(player), false)
	local multiplier = 1 + profile.Rebirths * GameConfig.Rebirth.SpeedBonus
	if round then
		if player:GetAttribute("Pass_FastWheel") then
			multiplier *= 2
		end
		if DataService.BoostActive(profile, "RoundSpeed") then
			multiplier *= GameConfig.Consumables.RoundSpeedMultiplier
		end
		multiplier *= (ReplicatedStorage:GetAttribute("RoundSpeedMultiplier") or 1) :: number
	else
		-- the Speed Rush weekly event (EventService)
		multiplier *= (ReplicatedStorage:GetAttribute("DeliverySpeedMultiplier") or 1) :: number
	end
	return math.max(1, math.floor(prize.Amount * multiplier))
end

local function award(player: Player, amount: number, entry: Entry?)
	if amount <= 0 or not DataService.Get(player) then
		return
	end
	local before = (player:GetAttribute("Speed") or 0) :: number
	DataService.Update(player, function(p)
		p.Speed += amount
	end)
	BaseService.RefreshWalkSpeed(player)
	if entry then
		entry.Banked += amount
		player:SetAttribute("RoundSpeedBanked", entry.Banked)
	end
	Net.Remotes.Effect:FireClient(player, "SpeedBank", amount)
	for i, zone in GameConfig.Zones do
		local need = zone.SpeedNeeded or 0
		if before < need and before + amount >= need then
			if entry then
				entry.Reached = i
			else
				Net.Notify(player, `Outrun the {string.upper(GameConfig.MonsterName(i))}!`, "good")
			end
		end
	end
end

local function nextStep(player: Player, entry: Entry)
	if entry.Step == 0 then
		player:SetAttribute("RoundHide", true)
		player:SetAttribute("RoundStepAt", entry.Started + TIMES[1])
		player:SetAttribute("RoundStepKills", nil)
		player:SetAttribute("RoundStepSpeed", math.max(1, math.floor(entry.Full / TOTAL)))
		return
	end
	player:SetAttribute("RoundHide", nil)
	if entry.Murderer then
		local kills = math.min(entry.Kills + 1, entry.Enemies)
		local denominator = entry.Enemies * (entry.Enemies + 1) / 2
		player:SetAttribute("RoundStepAt", nil)
		player:SetAttribute("RoundStepKills", kills)
		player:SetAttribute("RoundStepSpeed", math.max(1, math.floor(entry.Full * 13 / TOTAL * kills / denominator)))
	else
		local step = math.min(entry.Step + 1, #TIMES)
		player:SetAttribute("RoundStepAt", entry.Started + TIMES[step])
		player:SetAttribute("RoundStepKills", nil)
		player:SetAttribute("RoundStepSpeed", math.max(1, math.floor(entry.Full * PARTS[step] / TOTAL)))
	end
end

function Progress.Begin(players: { [Player]: boolean }, murderer: Player?, enemies: number, started: number)
	for player in players do
		local entry: Entry = {
			Full = budget(player, true) * (if DataService.UseCharge(player, "DoublePrize") then 2 else 1),
			Banked = 0,
			Step = 0,
			Kills = 0,
			Enemies = math.max(1, enemies),
			Murderer = player == murderer,
			Started = started,
			Finished = false,
			Coins = 0,
		}
		entries[player] = entry
		player:SetAttribute("RoundSpeedBanked", 0)
		nextStep(player, entry)
	end
end

function Progress.Tick(alive: { [Player]: boolean })
	local now = workspace:GetServerTimeNow()
	for player in alive do
		local entry = entries[player]
		if entry and not entry.Finished then
			if entry.Step == 0 and now - entry.Started >= TIMES[1] then
				entry.Step = 1
				award(player, math.max(1, math.floor(entry.Full / TOTAL)), entry)
			end
			if not entry.Murderer then
				while entry.Step < #TIMES and now - entry.Started >= TIMES[entry.Step + 1] do
					entry.Step += 1
					award(player, math.max(1, math.floor(entry.Full * PARTS[entry.Step] / TOTAL)), entry)
				end
			end
			nextStep(player, entry)
		end
	end
end

function Progress.Kill(player: Player)
	local entry = entries[player]
	if not entry or entry.Finished or not entry.Murderer or entry.Kills >= entry.Enemies then
		return
	end
	entry.Kills += 1
	local denominator = entry.Enemies * (entry.Enemies + 1) / 2
	award(player, math.max(1, math.floor(entry.Full * 13 / TOTAL * entry.Kills / denominator)), entry)
	nextStep(player, entry)
end

function Progress.Coin(player: Player)
	local entry = entries[player]
	if entry and not entry.Finished and entry.Coins < 15 then
		entry.Coins += 1
		award(player, math.max(1, math.floor(entry.Full * 0.01)), entry)
	end
end

function Progress.Finish(player: Player, jackpot: boolean)
	local entry = entries[player]
	if not entry or entry.Finished then
		return
	end
	if jackpot and (entry.Murderer or entry.Step < #TIMES) then
		award(player, math.max(1, math.floor(entry.Full * PARTS[#PARTS] / TOTAL)), entry)
	elseif entry.Banked == 0 then
		award(player, math.max(1, math.floor(entry.Full / TOTAL)), entry)
	end
	entry.Finished = true
	if entry.Reached then
		local monster = string.upper(GameConfig.MonsterName(entry.Reached))
		task.delay(2, function()
			if player.Parent then
				Net.Notify(player, `Outrun the {monster}!`, "good")
			end
		end)
	end
	player:SetAttribute("RoundHide", nil)
	player:SetAttribute("RoundStepAt", nil)
	player:SetAttribute("RoundStepKills", nil)
	player:SetAttribute("RoundStepSpeed", nil)
end

function Progress.Delivered(player: Player, zone: number)
	local multiplier = (ReplicatedStorage:GetAttribute("DeliverySpeedMultiplier") or 1) :: number
	local reached = 1
	local speed = (player:GetAttribute("Speed") or 0) :: number
	for i, entry in GameConfig.Zones do
		if speed >= (entry.SpeedNeeded or 0) then
			reached = i
		end
	end
	local depth = math.clamp(zone / reached, 0.25, 1)
	award(player, math.max(1, math.floor(budget(player, false) * 0.1 * depth * multiplier)), nil)
end

Players.PlayerRemoving:Connect(function(player)
	entries[player] = nil
end)
return Progress
