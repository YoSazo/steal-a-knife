--!strict
-- One-time replacements for removed systems, applied when a save loads. Historical prices are
-- frozen here so future economy changes cannot change what an old save receives.
--   * health levels: the cash they cost, once (Bought "LegacyHealthRefund")
--   * a luck potion still running when potions were cut: the time left as cash at the 39 Robux /
--     15 minute potion's rate, once (Bought "LegacyLuckRefund")
--   * Knife Insurance charges left when round loot was cut: 13 Robux each (the x3 pack's rate), as
--     cash at the potions' 4000 a Robux, once (Bought "LegacyInsuranceRefund")
local LegacyProgress = {}

function LegacyProgress.Apply(profile: any): number
	local cash = 0
	local level = profile.HealthLevel
	local count = if type(level) == "number"
			and level == level
			and level < math.huge
		then math.clamp(math.floor(level), 0, 20)
		else 0
	profile.HealthLevel, profile.Heat = 0, 0
	if not table.find(profile.Bought, "LegacyHealthRefund") then
		for i = 0, count - 1 do
			cash += math.floor(25000 * 2.6 ^ i)
		end
		table.insert(profile.Bought, "LegacyHealthRefund")
	end
	local luckLeft = if type(profile.LuckUntil) == "number" then profile.LuckUntil - os.time() else 0
	profile.LuckUntil = 0
	if luckLeft > 0 and not table.find(profile.Bought, "LegacyLuckRefund") then
		cash += math.floor(math.min(luckLeft, 6 * 3600) / 900 * 39 * 4000)
		table.insert(profile.Bought, "LegacyLuckRefund")
	end
	local charges = profile.Charges
	local insured = if type(charges) == "table" and type(charges.Insurance) == "number"
		then math.clamp(math.floor(charges.Insurance), 0, 1000)
		else 0
	if insured > 0 and not table.find(profile.Bought, "LegacyInsuranceRefund") then
		cash += insured * 13 * 4000
		charges.Insurance = 0
		table.insert(profile.Bought, "LegacyInsuranceRefund")
	end
	profile.Cash += cash
	return cash
end

return LegacyProgress
