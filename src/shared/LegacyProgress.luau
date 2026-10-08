--!strict
-- One-time replacement for removed health progression. Historical costs are frozen here so
-- future economy changes cannot change what an old save receives.
local LegacyProgress = {}
function LegacyProgress.Apply(profile: any): number
	local level = profile.HealthLevel
	local count = if type(level) == "number"
			and level == level
			and level < math.huge
		then math.clamp(math.floor(level), 0, 20)
		else 0
	profile.HealthLevel, profile.Heat = 0, 0
	if table.find(profile.Bought, "LegacyHealthRefund") then
		return 0
	end
	local cash = 0
	for i = 0, count - 1 do
		cash += math.floor(25000 * 2.6 ^ i)
	end
	table.insert(profile.Bought, "LegacyHealthRefund")
	profile.Cash += cash
	return cash
end
return LegacyProgress
