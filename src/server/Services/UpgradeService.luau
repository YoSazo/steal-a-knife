--!strict
-- Cash purchases. Clients only send the name of what they want; price and limits come from
-- GameConfig on the server. Murderer tickets are in-game cash only, never Robux.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(script.Parent.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)

local UpgradeService = {}

local lastRequest: { [Player]: number } = {}

local function purchase(player: Player, kind: unknown): (boolean, string)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < 0.25 then
		return false, "Slow down!"
	end
	lastRequest[player] = now

	local profile = DataService.Get(player)
	if not profile or type(kind) ~= "string" then
		return false, "Not ready yet"
	end

	if kind == "Speed" then
		if profile.SpeedLevel >= GameConfig.MaxSpeedLevel then
			return false, "Speed is maxed!"
		end
		if not DataService.TrySpend(player, GameConfig.SpeedCost(profile.SpeedLevel)) then
			return false, "Not enough cash"
		end
		DataService.Update(player, function(p)
			p.SpeedLevel += 1
		end)
		BaseService.RefreshWalkSpeed(player)
		return true, `Speed level {profile.SpeedLevel}!`
	elseif kind == "Slot" then
		if profile.Slots >= GameConfig.MaxSlots then
			return false, "Your rack is maxed!"
		end
		if not DataService.TrySpend(player, GameConfig.SlotCost(profile.Slots)) then
			return false, "Not enough cash"
		end
		DataService.Update(player, function(p)
			p.Slots += 1
		end)
		BaseService.RefreshRack(player)
		return true, `Rack now holds {profile.Slots} knives!`
	elseif kind == "Ticket" then
		if profile.Tickets >= GameConfig.MaxTickets then
			return false, `You can hold {GameConfig.MaxTickets} tickets at most`
		end
		if not DataService.TrySpend(player, GameConfig.TicketCost) then
			return false, "Not enough cash"
		end
		DataService.Update(player, function(p)
			p.Tickets += 1
		end)
		return true, "Murderer ticket bought! It's used next round."
	end
	return false, "Unknown item"
end

function UpgradeService.Init()
	Net.Remotes.Purchase.OnServerInvoke = function(player: Player, kind: unknown)
		local ok, message = purchase(player, kind)
		Net.Notify(player, message, if ok then "good" else "bad")
		return ok, message
	end
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return UpgradeService
