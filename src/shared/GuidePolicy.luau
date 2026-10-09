--!strict
-- How much coaching to show, separate from the resolver's truthful next action.
local GuidePolicy = {}
GuidePolicy.Thresholds = {
	delivery = 3,
	collect = 1,
	vault = 1,
	sell = 1,
	index = 1,
	knife_draw = 1,
	knife_fight = 1,
	gun_draw = 1,
	gun_shoot = 1,
	coins = 1,
} :: { [string]: number }

function GuidePolicy.Limit(skill: string): number?
	return GuidePolicy.Thresholds[skill]
end

function GuidePolicy.Parse(encoded: string): { [string]: number }
	local learned = {}
	for entry in string.gmatch(encoded, "[^,]+") do
		local key, count = entry:match("^(.-)=(%d+)$")
		if key and count and GuidePolicy.Limit(key) then
			learned[key] = math.min(tonumber(count) :: number, GuidePolicy.Limit(key) :: number)
		end
	end
	return learned
end

function GuidePolicy.Skill(id: string): string?
	if id == "steal" or id == "carry_home" or id == "carry_place" then
		return "delivery"
	elseif id == "collect" or id == "collect_all" then
		return "collect"
	elseif id == "vault_bigger" or id == "carry_bigger" then
		return "vault"
	elseif id == "vault_full" or id == "carry_full" then
		return "sell"
	elseif id == "murderer_draw" then
		return "knife_draw"
	elseif id == "sheriff_draw" then
		return "gun_draw"
	elseif id == "sheriff_shoot" or id == "sheriff_reload" then
		return "gun_shoot"
	elseif id == "murderer_fight" then
		return "knife_fight"
	elseif id == "innocent_coins" then
		return "coins"
	elseif id == "index" then
		return id
	end
	return nil
end

export type State = {
	Mode: string,
	Id: string,
	Skill: string?,
	Learned: { [string]: number },
	Age: number,
	Started: boolean,
	Help: boolean?,
}
function GuidePolicy.Visible(s: State): boolean
	if s.Id == "round_speed" or s.Id == "coffin_ready" then
		return true
	end
	if s.Mode == "Off" then
		return false
	elseif s.Mode == "On" or s.Help then
		return true
	end
	-- New milestones and temporary combat states are brief notices, not permanent orders.
	if s.Id == "new_tier" or s.Id == "gift" or s.Id == "murderer_grace" or s.Id == "round_stunned" then
		return s.Age < 8
	end
	-- The core loop (steal -> run home -> place it) is always shown, however often you've done it:
	-- the one big line and the red trail are how a young kid always knows what to do next
	if s.Skill == "delivery" then
		return true
	end
	local count = if s.Skill then s.Learned[s.Skill] or 0 else 0
	local limit = s.Skill and GuidePolicy.Limit(s.Skill)
	if limit and count >= limit then
		return false
	end
	if s.Started and s.Age >= 3 then
		return false
	end
	return true
end

return GuidePolicy
