--!strict
-- Pen room, capacity, display scale and player-facing wording.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local PenMode = {}

-- Coffins on (GameConfig.Coffins.Enabled; Studio: ReplicatedStorage DebugCoffins): boss walls show
-- coffins (rarity known, knife a surprise), carried home on your head, opening on the round clock
function PenMode.Coffins(): boolean
	return GameConfig.Coffins.Enabled == true
		or (RunService:IsStudio() and ReplicatedStorage:GetAttribute("DebugCoffins") == true)
end

-- Maximum room in a pen.
function PenMode.MaxSlots(): number
	return GameConfig.Pens.MaxSlots
end

-- The next room upgrade at `slots`: (its cost, how many slots it adds, rebirths it needs).
-- Pens grow one knife at a time (GameConfig.Pens.SlotCosts).
function PenMode.RoomUpgrade(slots: number): (number, number, number)
	local costs = GameConfig.Pens.SlotCosts
	local cost = costs[slots - GameConfig.StartingSlots + 1] or costs[#costs]
	return if slots >= GameConfig.Pens.MaxSlots then math.huge else cost, 1, 0
end

-- How many knives you can own before a steal is refused: the pen, plus the bag with pens on
-- (Steal an Egg: a full pen never loses what you hatched - it waits in your inventory)
function PenMode.Capacity(slots: number): number
	return slots + GameConfig.Pens.Bag
end

-- How long a pen is: always its full length now. (It used to grow from StartDepth with your
-- upgrades, but the pen sits where a full-length one fits, so a short one left an empty strip
-- behind its fence and looked cut off next to the others; and room grows a slot at a time now.)
function PenMode.Depth(_slots: number): number
	return GameConfig.Pens.Depth
end

-- Messages and labels say "pen" instead of "vault" with pens on ("Your vault is full!" ->
-- "Your pen is full!"); Remotes.Notify / Announce run every message through this
function PenMode.Words(text: string): string
	return (
		text:gsub("[Vv]ault", function(word: string): string
			return if word:sub(1, 1) == "V" then "Pen" else "pen"
		end)
	)
end

-- How big a knife character is drawn in its pen (x its 2.4-stud base): value you see from afar
function PenMode.Scale(rarity: string): number
	return GameConfig.Pens.Scale[rarity] or 2
end

return PenMode
