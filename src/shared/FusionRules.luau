--!strict
local Items = require(script.Parent.Items)
local FusionRules = {}
export type Group = { Key: string, Item: string, Output: string, Count: number, Indexes: { number } }
function FusionRules.Groups(knives: { string }, sealed: { [number]: boolean }?): { Group }
	local groups: { [string]: Group } = {}
	for index, item in knives do
		local parsed = Items.Parse(item)
		if not parsed or (sealed and sealed[index]) or parsed.Mutation.Rank >= #Items.Mutations - 1 then
			continue
		end
		local key = `{parsed.Name}|{parsed.Mutation.Id}`
		local group = groups[key]
		if not group then
			group = {
				Key = key,
				Item = item,
				Output = Items.Make(parsed.Name, Items.Mutations[parsed.Mutation.Rank + 2].Id, parsed.Size.Id),
				Count = 0,
				Indexes = {},
			}
			groups[key] = group
		end
		group.Count += 1
		table.insert(group.Indexes, index)
	end
	local out = {}
	for _, group in groups do
		table.insert(out, group)
	end
	table.sort(out, function(a, b)
		return if a.Count == b.Count then a.Key < b.Key else a.Count > b.Count
	end)
	return out
end
return FusionRules
