--!strict
-- Pens instead of vaults (Steal an Egg): one flat fenced pen per player, knife characters hopping
-- around inside, coffins waiting on the ground. GameConfig.Pens.Enabled switches it for real;
-- in Studio, ReplicatedStorage attribute DebugPenLayout = true (read when the map is built).
-- What changes with pens (everything else - gate, raids, income, the guide - works as with vaults):
--   * MapService builds GameConfig.Pens.Count pens, bigger and flat (no storeys, no plates)
--   * BaseService shows knives as hopping characters, sized by rarity (Pens.Scale)
--   * walking into your pen with a knife drops it in (StealService), and collects your money
--   * the pen holds up to Pens.MaxSlots knives (upgrades add Pens room, not floors)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local PenMode = {}

function PenMode.On(): boolean
	return GameConfig.Pens.Enabled
		or (RunService:IsStudio() and ReplicatedStorage:GetAttribute("DebugPenLayout") == true)
end

-- How many knives a base can hold at most (pens: Pens.MaxSlots; vaults: 4 floors)
function PenMode.MaxSlots(): number
	return if PenMode.On() then GameConfig.Pens.MaxSlots else GameConfig.MaxSlots
end

-- How long a pen is for `slots` knives: StartDepth for a new pen, Depth when fully upgraded
function PenMode.Depth(slots: number): number
	local config = GameConfig.Pens
	local start = GameConfig.StartingSlots
	local t = math.clamp((slots - start) / math.max(1, config.MaxSlots - start), 0, 1)
	return config.StartDepth + (config.Depth - config.StartDepth) * t
end

-- Messages and labels say "pen" instead of "vault" with pens on ("Your vault is full!" ->
-- "Your pen is full!"); Remotes.Notify / Announce run every message through this
function PenMode.Words(text: string): string
	if not PenMode.On() then
		return text
	end
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
