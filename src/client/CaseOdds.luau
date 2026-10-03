--!strict
-- Presentation mirrors Items.OpenCase and the current replicated luck multipliers.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Items = require(Shared.Items)
local Knives = require(Shared.Config.Knives)
local player = Players.LocalPlayer
local Odds = {}
local function pct(n: number): string
	return (string.format("%.3f", n):gsub("0+$", ""):gsub("%.$", "")) .. "%"
end

function Odds.Text(rarity: string): string
	local pool = Knives.ByRarity[rarity]
	local nextRarity = Knives.Rarities[(table.find(Knives.Rarities, rarity) or 1) + 1]
	local inside = {}
	for _, knife in pool do
		table.insert(inside, `{knife.DisplayName} {pct((if nextRarity then 96 else 100) / #pool)}`)
	end
	if nextRarity then
		for _, knife in Knives.ByRarity[nextRarity] do
			table.insert(inside, `{knife.DisplayName} {pct(4 / #Knives.ByRarity[nextRarity])}`)
		end
	end
	local luck = 1 + (player:GetAttribute("Rebirths") or 0) * GameConfig.Rebirth.LuckBonus
	local untilLuck = ReplicatedStorage:GetAttribute("ServerLuckUntil")
	if type(untilLuck) == "number" and untilLuck > workspace:GetServerTimeNow() then
		luck *= (ReplicatedStorage:GetAttribute("ServerLuckMultiplier") or 2)
	end
	local mutationTotal, sizeTotal = 0, 0
	for _, m in Items.Mutations do
		mutationTotal += m.Weight * (if m.Rank > 0 then luck else 1)
	end
	for _, s in Items.Sizes do
		sizeTotal += s.Weight * (if s.Rank > 0 then luck else 1)
	end
	local mutations, sizes = {}, {}
	for _, m in Items.Mutations do
		table.insert(
			mutations,
			`{if m.Rank == 0 then "None" else m.DisplayName} {pct(
				m.Weight * (if m.Rank > 0 then luck else 1) / mutationTotal * 100
			)}`
		)
	end
	for _, s in Items.Sizes do
		table.insert(
			sizes,
			`{if s.Id == "" then "Normal" else s.DisplayName} {pct(
				s.Weight * (if s.Rank > 0 then luck else 1) / sizeTotal * 100
			)}`
		)
	end
	return `{table.concat(inside, " · ")}\nMutations: {table.concat(mutations, " · ")}\nSizes: {table.concat(
		sizes,
		" · "
	)}`
end

return Odds
