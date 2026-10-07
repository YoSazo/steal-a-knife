--!strict
-- "Come back" notifications (GameConfig.Notify). Game servers only exist while people are in them,
-- so a reminder hours after someone leaves is sent by our analytics server (analytics/src/notify.js):
--   - a player who was shown the opt-in (profile.NotifyAsked) leaves -> plan "your vault filled up:
--     $X waiting" for SendAfterHours later ($X = what offline earnings will pay by then)
--   - they join again -> cancel it (no reminder for someone who's already back)
-- Roblox only delivers it to 13+ players who said yes, one a day. Off while GameConfig.Notify.Enabled
-- is false; never from Studio (Analytics.Post).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Format = require(ReplicatedStorage.Shared.Format)
local DataService = require(script.Parent.DataService)
local Analytics = require(script.Parent.Analytics)
local Net = require(script.Parent.Parent.Remotes)

local NotifyService = {}

local CONFIG = GameConfig.Notify

-- What offline earnings will have paid by the time the reminder arrives (Rewards' formula)
local function waiting(player: Player): number
	local income = (player:GetAttribute("Income") or 0) :: number
	local hours = math.min(CONFIG.SendAfterHours, GameConfig.Offline.MaxHours)
	return math.floor(income * hours * 3600 * GameConfig.Offline.Fraction)
end

function NotifyService.Init()
	Net.Remotes.NotifyAsked.OnServerEvent:Connect(function(player: Player)
		DataService.Update(player, function(p)
			p.NotifyAsked = true
		end)
	end)
	if not CONFIG.Enabled then
		return
	end
	DataService.PlayerLoaded:Connect(function(player: Player, profile: any)
		if profile and profile.NotifyAsked then
			task.spawn(Analytics.Post, "/api/notify", { action = "cancel", user_id = player.UserId })
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		local profile = DataService.Get(player)
		if not profile or not profile.NotifyAsked then
			return
		end
		local cash = waiting(player)
		if cash <= 0 then
			return
		end
		task.spawn(Analytics.Post, "/api/notify", {
			action = "schedule",
			user_id = player.UserId,
			send_at = os.time() + CONFIG.SendAfterHours * 3600,
			kind = "comeback",
			params = { cash = Format.Cash(cash) },
		})
	end)
end

return NotifyService
