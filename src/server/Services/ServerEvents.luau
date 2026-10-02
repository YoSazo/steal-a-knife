--!strict
-- Things the whole server does together. Two kinds, both dead simple on screen:
--
--   🤝 Server goal: one shared bar ("Steal 25 knives together"). Every player's steals / survivals
--      fill it; when it's full, a reward event starts for EVERYONE.
--   ⚡ Events: short boosts anyone can set off, by filling a goal or by doing something big:
--        LuckyRush  - 2x power-roll luck            (steal goal filled)
--        CashRush   - 2x vault income               (survive goal filled)
--        HeatWave   - Heat gains doubled            (someone hits max Heat)
--        CosmicRush - deep bosses restock fast       (someone steals from the last boss)
--      plus a Murderer wipe calling the Thief Moon early (RaidService hooks OnWipe).
--
-- State lives on ReplicatedStorage so the HUD and events board just read it:
--   GoalKind, GoalProgress, GoalNeed, GoalReward   and   Event_<Name> = server time it ends.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(script.Parent.Parent.Remotes)

local ServerEvents = {}

export type EventSpec = { Name: string, Title: string, Emoji: string, Seconds: number, Color: Color3, What: string }

ServerEvents.Events = {
	LuckyRush = {
		Name = "LuckyRush",
		Title = "LUCKY RUSH",
		Emoji = "🍀",
		Seconds = 300,
		Color = Color3.fromRGB(110, 255, 120),
		What = "2x power luck for everyone",
	},
	CashRush = {
		Name = "CashRush",
		Title = "CASH RUSH",
		Emoji = "💸",
		Seconds = 180,
		Color = Color3.fromRGB(255, 220, 80),
		What = "2x vault cash for everyone",
	},
	HeatWave = {
		Name = "HeatWave",
		Title = "HEAT WAVE",
		Emoji = "🔥",
		Seconds = 180,
		Color = Color3.fromRGB(255, 120, 50),
		What = "Heat gains doubled for everyone",
	},
	CosmicRush = {
		Name = "CosmicRush",
		Title = "COSMIC RUSH",
		Emoji = "🪐",
		Seconds = 180,
		Color = Color3.fromRGB(190, 120, 255),
		What = "Deep bosses restock super fast",
	},
} :: { [string]: EventSpec }

-- The goals cycle; the size grows with the number of players so it always takes teamwork
local GOALS = {
	{ Kind = "Steals", Text = "Steal %d knives together", Reward = "LuckyRush", Base = 10, PerPlayer = 3 },
	{ Kind = "Survives", Text = "Survive %d rounds together", Reward = "CashRush", Base = 4, PerPlayer = 1 },
}
local goalIndex = 0

-- Set by RaidService: a Murderer wiped every innocent, so the Thief Moon rises early
ServerEvents.OnWipe = nil :: ((string) -> ())?

function ServerEvents.Active(name: string): boolean
	local ends = ReplicatedStorage:GetAttribute(`Event_{name}`)
	return type(ends) == "number" and workspace:GetServerTimeNow() < ends
end

-- Starts (or extends) an event for everyone; `by` is who set it off, for the shout-out
function ServerEvents.Start(name: string, by: string?)
	local spec = ServerEvents.Events[name]
	if not spec then
		return
	end
	local now = workspace:GetServerTimeNow()
	local current = ReplicatedStorage:GetAttribute(`Event_{name}`)
	local from = if type(current) == "number" and current > now then current else now
	ReplicatedStorage:SetAttribute(`Event_{name}`, from + spec.Seconds)
	Net.Announce(`{spec.Emoji} {spec.Title}! {spec.What}{if by then ` (thanks {by}!)` else ""}`, spec.Color, 3)
end

local function nextGoal()
	goalIndex = goalIndex % #GOALS + 1
	local goal = GOALS[goalIndex]
	local need = goal.Base + goal.PerPlayer * #Players:GetPlayers()
	ReplicatedStorage:SetAttribute("GoalKind", goal.Kind)
	ReplicatedStorage:SetAttribute("GoalText", string.format(goal.Text, need))
	ReplicatedStorage:SetAttribute("GoalReward", goal.Reward)
	ReplicatedStorage:SetAttribute("GoalNeed", need)
	ReplicatedStorage:SetAttribute("GoalProgress", 0)
end

-- Someone did a thing that counts toward the current goal
function ServerEvents.Progress(kind: string, amount: number?)
	if ReplicatedStorage:GetAttribute("GoalKind") ~= kind then
		return
	end
	local progress = ((ReplicatedStorage:GetAttribute("GoalProgress") or 0) :: number) + (amount or 1)
	local need = (ReplicatedStorage:GetAttribute("GoalNeed") or 1) :: number
	if progress >= need then
		ServerEvents.Start(ReplicatedStorage:GetAttribute("GoalReward") :: string, "everyone")
		nextGoal()
	else
		ReplicatedStorage:SetAttribute("GoalProgress", progress)
	end
end

function ServerEvents.Wipe(murdererName: string)
	if ServerEvents.OnWipe then
		ServerEvents.OnWipe(murdererName)
	end
end

function ServerEvents.Init()
	nextGoal()
end

return ServerEvents
