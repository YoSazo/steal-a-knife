--!strict
local Knives = require(script.Parent.Config.Knives)
local GameConfig = require(script.Parent.Config.GameConfig)
local IndexRewards = {}

-- The same eligibility on the guide, badge and claim button. A successful server reply can
-- acknowledge claims before the corresponding player attribute arrives.
function IndexRewards.Pending(discovered: string, claimed: string, acknowledged: string?): { string }
	local paid, seen = {}, {}
	for _, source in { claimed, acknowledged or "" } do
		for name in string.gmatch(source, "[^,]+") do
			paid[name] = true
		end
	end
	local pending = {}
	for name in string.gmatch(discovered, "[^,]+") do
		local knife = Knives.ByName[name]
		if knife and GameConfig.IndexRewards[knife.Rarity] and not paid[name] and not seen[name] then
			seen[name] = true
			table.insert(pending, name)
		end
	end
	return pending
end

return IndexRewards
