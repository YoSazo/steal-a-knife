--!strict
-- One way to hand out a free reward sized to the player (codes, the group gift): Speed as a share of
-- the way to the next monster they can't outrun yet, Cash as seconds of their own income, a coffin
-- of a rarity. Returns the words for what they got ("+1.2K Speed and $45K").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)
local CoffinService = require(script.Parent.CoffinService)
local Net = require(script.Parent.Parent.Remotes)

local FreeRewards = {}

local MIN_SPEED = 300
local MIN_CASH = 500

export type Reward = { Speed: number?, Cash: number?, Coffin: string? }

-- `share` of the way from the last zone you can outrun to the next one (past the last zone: that
-- share of your own Speed)
function FreeRewards.SpeedShare(speed: number, share: number): number
	local previous = 0
	for _, zone in GameConfig.Zones :: { any } do
		local need = (zone.SpeedNeeded or 0) :: number
		if need > speed then
			return math.floor(math.max((need - previous) * share, MIN_SPEED))
		end
		previous = need
	end
	return math.floor(math.max(speed * share, MIN_SPEED))
end

function FreeRewards.Give(player: Player, reward: Reward, reason: string): string?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local got: { string } = {}
	if reward.Speed then
		local amount = FreeRewards.SpeedShare(profile.Speed, reward.Speed)
		DataService.Update(player, function(p)
			p.Speed += amount
		end)
		BaseService.RefreshWalkSpeed(player)
		table.insert(got, `+{Format.Short(amount)} Speed`)
	end
	if reward.Cash then
		local cash = GameConfig.Pay({ Min = MIN_CASH, Seconds = reward.Cash }, BaseService.RackIncome(player))
		DataService.AddCash(player, cash, reason)
		Net.Remotes.Effect:FireClient(player, "CashBurst", nil, cash)
		table.insert(got, Format.Cash(cash))
	end
	if reward.Coffin then
		table.insert(got, CoffinService.GiveOrCash(player, reward.Coffin, reason))
	end
	return table.concat(got, " and ")
end

return FreeRewards
