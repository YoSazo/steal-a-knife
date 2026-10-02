--!strict
-- Cash purchases (Haunted Wheel tiers, vault walls, rack slots, Murderer tickets, Rebirth). Clients only send the name of what they
-- want; price and limits come from GameConfig on the server. Tickets are in-game cash only, never
-- Robux. Innocent Powers are bought through PowerService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(script.Parent.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)
local Offers = require(script.Parent.Offers)
local Rewards = require(script.Parent.Rewards)

local UpgradeService = {}

local lastRequest: { [Player]: number } = {}
-- Not enough cash for something: offer the cash pack that would cover it
local function short(player: Player, cost: number): (boolean, string)
	local profile = DataService.Get(player)
	if profile then
		Offers.Cash(player, cost - profile.Cash, BaseService.RackIncome(player))
	end
	return false, "Not enough cash"
end

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
			return short(player, nextTier.Cost)
		end
		DataService.Update(player, function(p)
			p.TreadmillLevel += 1
		end)
		BaseService.RefreshRack(player) -- updates the wheel's sign
		return true, `{nextTier.Name}! +{nextTier.Rate} Speed per second`
	elseif kind == "Trail" then
		local nextTrail = GameConfig.Trails[profile.TrailLevel + 1]
		if not nextTrail then
			return false, "You have the best knife trail!"
		end
		if not DataService.TrySpend(player, nextTrail.Cost) then
			return short(player, nextTrail.Cost)
		end
		DataService.Update(player, function(p)
			p.TrailLevel += 1
		end)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			Net.Remotes.Effect:FireAllClients("Deposit", player, "Epic")
		end
		return true, `{nextTrail.Name}! Your wheel now trains Speed x{nextTrail.Multiplier}`
	elseif kind == "Health" then
		if profile.HealthLevel >= GameConfig.Health.MaxLevel then
			return false, "Your health is maxed!"
		end
		local cost = GameConfig.HealthCost(profile.HealthLevel)
		if not DataService.TrySpend(player, cost) then
			Offers.Show(player, "HealthBoost", "Need more health now? +3 Health levels instantly.")
			return short(player, cost)
		end
		DataService.Update(player, function(p)
			p.HealthLevel += 1
		end)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			Net.Remotes.Effect:FireAllClients("Heal", root.Position)
		end
		return true,
			`Max health {GameConfig.MaxHealthFor(
				profile.HealthLevel,
				if player:GetAttribute("Pass_Titan") then 2 else 1
			)}!`
	elseif kind == "Walls" then
		local nextTier = GameConfig.Walls[profile.WallLevel + 1]
		if not nextTier then
			return false, "Your walls are as good as they get!"
		end
		if not DataService.TrySpend(player, nextTier.Cost) then
			return short(player, nextTier.Cost)
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
			return false, `Rebirth needs {Format.Cash(cost)}`
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
			return false, "Your vault is as tall as it gets!"
		end
		if not DataService.TrySpend(player, GameConfig.SlotCost(profile.Slots)) then
			Offers.Show(player, "Mount", "Want it now? Add the next floor instantly.")
			return false, "Not enough cash"
		end
		DataService.Update(player, function(p)
			p.Slots = math.min(GameConfig.MaxSlots, p.Slots + GameConfig.SlotsPerFloor)
		end)
		BaseService.RefreshRack(player)
		return true, `Your vault grew a floor: {profile.Slots} knife plates!`
	elseif kind == "Ticket" then
		if profile.Tickets >= GameConfig.MaxTickets then
			return false, `You can hold {GameConfig.MaxTickets} tickets at most`
		end
		if not DataService.TrySpend(player, GameConfig.TicketPrice(BaseService.RackIncome(player))) then
			Offers.Show(player, "Tickets", "Get 3 Murderer Tickets right now.")
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
	local function buy(player: Player, kind: unknown): (boolean, string)
		local ok, message = purchase(player, kind)
		Net.Notify(player, message, if ok then "good" else "bad")
		return ok, message
	end
	Net.Remotes.Purchase.OnServerInvoke = buy
	BaseService.OnUpgradeWalls = function(player: Player)
		buy(player, "Walls")
	end
	BaseService.OnUpgradeBase = function(player: Player)
		buy(player, "Slot")
	end
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return UpgradeService
