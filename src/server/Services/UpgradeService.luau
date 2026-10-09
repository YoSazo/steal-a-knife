--!strict
-- Cash purchases (cosmetic trails, pen room, Murderer tickets, rebirth). Clients only send what they
-- want; price and limits come from GameConfig on the server. Tickets are in-game cash only, never
-- Robux.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local PenMode = require(ReplicatedStorage.Shared.PenMode)
local Items = require(ReplicatedStorage.Shared.Items)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local Net = require(script.Parent.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)
local Offers = require(script.Parent.Offers)
local Analytics = require(script.Parent.Analytics)

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

	if kind == "Trail" then
		local nextTrail = GameConfig.Trails[profile.TrailLevel + 1]
		if not nextTrail then
			return false, "You have the best knife trail!"
		end
		if not DataService.TrySpend(player, nextTrail.Cost, "upgrade_trail") then
			return short(player, nextTrail.Cost)
		end
		DataService.Update(player, function(p)
			p.TrailLevel += 1
		end)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			Net.Remotes.Effect:FireAllClients("Deposit", player, "Epic")
		end
		return true, `{nextTrail.Name} unlocked!`
	elseif kind == "Rebirth" then
		local cost = GameConfig.RebirthCost(profile.Rebirths)
		if profile.Rebirths >= GameConfig.Rebirth.Max then
			return false, "You've reached the final rebirth!"
		end
		if player:GetAttribute("InRound") or player:GetAttribute("Carrying") then
			return false, "Get home first!"
		end
		if profile.Cash < cost then
			return false, `Rebirth needs {Format.Cash(cost)}`
		end
		-- ...and a knife of the right rarity on your plates (Steal a Brainrot style)
		local need = GameConfig.RebirthNeeds(profile.Rebirths)
		local needRank = Knives.Rank(need)
		local has = false
		for _, item in profile.Knives do
			local parsed = Items.Parse(item)
			if parsed and Knives.Rank(parsed.Knife.Rarity) >= needRank then
				has = true
				break
			end
		end
		if not has then
			return false, `Rebirth needs a {need} knife (or better) in your vault`
		end
		-- Start over with a permanent boost: powers, stats, collection and tickets stay
		DataService.Update(player, function(p)
			p.Rebirths += 1
			p.Cash = 0
			-- uncollected vault money resets too (it used to survive and fund the next run)
			for slot in p.Pending do
				p.Pending[slot] = 0
			end
			p.Knives = {}
			p.Plates = {}
			p.Equipped = ""
			p.Slots = GameConfig.StartingSlots
			p.Speed = 0
		end)
		BaseService.RefreshRack(player)
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
		if profile.Slots >= PenMode.MaxSlots() then
			return false, "Your vault is as tall as it gets!"
		end
		local cost, step, floorRebirths = PenMode.RoomUpgrade(profile.Slots)
		if profile.Rebirths < floorRebirths then
			Offers.Show(player, "Mount", "Want it now? Add the next floor instantly.")
			return false, `The next floor needs Rebirth {floorRebirths}`
		end
		if not DataService.TrySpend(player, cost, "upgrade_floor") then
			Offers.Show(player, "Mount", PenMode.Words("Want it now? Make your vault bigger instantly."))
			return false, "Not enough cash"
		end
		DataService.Update(player, function(p)
			p.Slots = math.min(PenMode.MaxSlots(), p.Slots + step)
		end)
		BaseService.RefreshRack(player)
		return true, PenMode.Words(`Your vault is bigger: room for {profile.Slots} knives!`)
	elseif kind == "Ticket" then
		if profile.Tickets >= GameConfig.MaxTickets then
			return false, `You can hold {GameConfig.MaxTickets} tickets at most`
		end
		if
			not DataService.TrySpend(player, GameConfig.TicketPrice(BaseService.RackIncome(player)), "upgrade_ticket")
		then
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
		local before = DataService.Get(player)
		local cashBefore = if before then before.Cash else 0
		local ok, message = purchase(player, kind)
		Net.Notify(player, message, if ok then "good" else "bad")
		local what = if type(kind) == "string" then kind:sub(1, 24) else "?"
		Analytics.Track(player, "upgrade", { kind = what, ok = ok, reply = Analytics.Normalize(message) })
		if ok then
			local base = what:match("^(%a+)") or what
			Analytics.Milestone(player, "upgrade_" .. base)
			Analytics.Milestone(player, "first_upgrade")
			if what == "Rebirth" then
				local after = DataService.Get(player)
				Analytics.Track(player, "rebirth", { cash_lost = cashBefore, rebirths = after and after.Rebirths })
				Analytics.Milestone(player, "rebirth_" .. (if after then after.Rebirths else 1))
			end
		end
		return ok, message
	end
	Net.Remotes.Purchase.OnServerInvoke = buy
	BaseService.OnUpgradeBase = function(player: Player)
		buy(player, "Slot")
	end
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return UpgradeService
