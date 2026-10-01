--!strict
-- Cash purchases (Haunted Wheel tiers, vault walls, rack slots, Murderer tickets, Rebirth). Clients only send the name of what they
-- want; price and limits come from GameConfig on the server. Tickets are in-game cash only, never
-- Robux. Innocent Powers are bought through PowerService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(script.Parent.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)
local Rewards = require(script.Parent.Rewards)

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

	local caseRarity = kind:match("^Case:(%a+)$")
	if caseRarity then
		return Rewards.BuyCase(player, caseRarity)
	end

	if kind == "Treadmill" then
		local nextTier = GameConfig.Treadmills[profile.TreadmillLevel + 1]
		if not nextTier then
			return false, "Your Haunted Wheel is maxed!"
		end
		if not DataService.TrySpend(player, nextTier.Cost) then
			return false, "Not enough cash"
		end
		DataService.Update(player, function(p)
			p.TreadmillLevel += 1
		end)
		BaseService.RefreshRack(player) -- updates the wheel's sign
		return true, `{nextTier.Name}! +{nextTier.Rate} Speed per second`
	elseif kind == "Walls" then
		local nextTier = GameConfig.Walls[profile.WallLevel + 1]
		if not nextTier then
			return false, "Your walls are as good as they get!"
		end
		if not DataService.TrySpend(player, nextTier.Cost) then
			return false, "Not enough cash"
		end
		DataService.Update(player, function(p)
			p.WallLevel += 1
		end)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			Net.Remotes.Effect:FireAllClients("WallsUp", player, root.Position)
		end
		return true, `{nextTier.Name}! Your gate now holds {nextTier.GateHealth} damage`
	elseif kind == "Rebirth" then
		local cost = GameConfig.RebirthCost(profile.Rebirths)
		if profile.Rebirths >= GameConfig.Rebirth.Max then
			return false, "You've reached the final rebirth!"
		end
		if player:GetAttribute("InRound") or player:GetAttribute("Carrying") then
			return false, "Finish what you're doing first"
		end
		if profile.Cash < cost then
			return false, `Rebirth needs ${cost}`
		end
		-- Start over with a permanent boost: powers, stats, collection and tickets stay
		DataService.Update(player, function(p)
			p.Rebirths += 1
			p.Cash = 0
			p.Knives = {}
			p.Equipped = ""
			p.Slots = GameConfig.StartingSlots
			p.Speed = 0
			p.TreadmillLevel = 1
			p.WallLevel = 1
		end)
		BaseService.RefreshRack(player) -- (the walls rebuild themselves when WallLevel changes)
		local title = GameConfig.RebirthTitle(profile.Rebirths) or ""
		Net.Announce(
			`{player.DisplayName} REBIRTHED! They are now a {title} (x{1 + profile.Rebirths * GameConfig.Rebirth.IncomeBonus} income)`,
			Color3.fromRGB(255, 220, 90),
			2
		)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			Net.Remotes.Effect:FireAllClients("Rebirth", player, root.Position)
		end
		return true,
			`Rebirth {profile.Rebirths}! Everything earns x{1 + profile.Rebirths * GameConfig.Rebirth.IncomeBonus}`
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
		if not DataService.TrySpend(player, GameConfig.TicketPrice(BaseService.RackIncome(player))) then
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
