--!strict
-- How much coaching to show, separate from the resolver's truthful next action.
local GuidePolicy = {}
GuidePolicy.Thresholds = {
	delivery = 3,
	collect = 1,
	wheel = 1,
	vault = 1,
	sell = 1,
	index = 1,
	train = 1,
	knife_draw = 1,
	knife_fight = 1,
	gun_draw = 1,
	gun_shoot = 1,
	coins = 1,
} :: { [string]: number }

function GuidePolicy.Limit(skill: string): number?
	return GuidePolicy.Thresholds[skill] or (if skill:match("^perk:[%w_]+$") then 1 else nil)
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

function GuidePolicy.Skill(id: string, perk: string?): string?
	if id == "steal" or id == "carry_home" or id == "carry_place" or id == "carry_case" then
		return "delivery"
	elseif id == "collect" or id == "collect_all" then
		return "collect"
	elseif id == "wheel_upgrade" then
		return "wheel"
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
	elseif id == "murderer_perk" then
		return if perk then `perk:{perk}` else "knife_fight"
	elseif id == "murderer_spam" or id == "murderer_fight" or id == "murderer_passive" then
		return "knife_fight"
	elseif id == "innocent_coins" or id == "classic_coins" then
		return "coins"
	elseif id == "index" or id == "train" then
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
	if s.Mode == "Off" then
		return false
	elseif s.Mode == "On" or s.Help then
		return true
	end
	-- New milestones and temporary combat states are brief notices, not permanent orders.
	if s.Id == "new_tier" or s.Id == "gift" or s.Id == "murderer_grace" or s.Id == "round_stunned" then
		return s.Age < 8
	end
	local count = if s.Skill then s.Learned[s.Skill] or 0 else 0
	local limit = s.Skill and GuidePolicy.Limit(s.Skill)
	if limit and count >= limit then
		return false
	end
	-- After the first delivery, familiar routes become brief cues. A new control remains coached
	-- until demonstrated, but its words can step aside once the player starts the right action.
	if s.Skill == "delivery" and count > 0 then
		return s.Age < (if s.Started then 3 else 8)
	end
	if s.Started and s.Age >= 3 then
		return false
	end
	return true
end

return GuidePolicy
