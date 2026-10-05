--!strict
-- Robux: game passes and developer products (Config/Monetization).
--   * passes: checked on join and on purchase, mirrored to the player as attribute Pass_<Key>
--     (server-set, so it can't be faked). Other services just read the attribute:
--       DoubleCash / VIP   BaseService.IncomeMultiplier      FastWheel  BaseService training
--       Fortified          BaseService.RefreshWalls          VIP        Rewards free chest, the tag
--       MurdererLuck       RoundService.pickMurderer
--   * products: MarketplaceService.ProcessReceipt. Every PurchaseId is granted once (kept in the
--     profile) and the save is written before Roblox is told it's granted; if that save fails the
--     receipt is retried later and the stored PurchaseId stops it being granted twice.
--   * Studio: anything whose id is still 0 can be "bought" for free through Remotes.StoreTest.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local Offers = require(script.Parent.Offers)
local RaidService = require(script.Parent.RaidService)
local StealService = require(script.Parent.StealService)
local Gamble = require(script.Parent.Gamble)
local GuardService = require(script.Parent.GuardService)
local Fuel = require(script.Parent.Fuel)
local Rewards = require(script.Parent.Rewards)
local Analytics = require(script.Parent.Analytics)

local MonetizationService = {}

local MAX_RECEIPTS = 60

local passById: { [number]: Monetization.Pass } = {}
local productById: { [number]: Monetization.Product } = {}
for _, pass in Monetization.Passes do
	if pass.Id > 0 then
		passById[pass.Id] = pass
	end
end
for _, product in Monetization.Products do
	if product.Id > 0 then
		productById[product.Id] = product
	end
end

-- (the VIP tag over the head is drawn with the cash by client/Overheads, from Pass_VIP)

-- Passes -------------------------------------------------------------------------------------

local function grantPass(player: Player, key: string, announce: boolean)
	if player:GetAttribute("Pass_" .. key) then
		return
	end
	player:SetAttribute("Pass_" .. key, true)
	local pass = Monetization.PassByKey[key]
	if key == "ExtraFloor" then
		-- One extra floor, once ever (passes are re-checked every visit)
		local profile = DataService.Get(player)
		if profile and not table.find(profile.Bought, "ExtraFloorPass") then
			DataService.Update(player, function(p)
				table.insert(p.Bought, "ExtraFloorPass")
				p.Slots = math.min(GameConfig.MaxSlots, p.Slots + GameConfig.SlotsPerFloor)
			end)
			BaseService.RefreshRack(player)
		end
	elseif key == "DoubleCash" or key == "VIP" then
		BaseService.RefreshRack(player) -- income readouts
	end
	if announce and pass then
		Net.Notify(player, `{pass.Icon} {pass.Name} unlocked! Thank you!`, "good")
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			Net.Remotes.Effect:FireAllClients("Deposit", player, "Legendary")
		end
	end
end

local function checkPasses(player: Player)
	for _, pass in Monetization.Passes do
		if pass.Id > 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
			if ok and owns and player.Parent then
				grantPass(player, pass.Key, false)
			end
		end
	end
	player:SetAttribute("PassesChecked", true) -- Rewards waits for this before offline earnings
end

-- Products -----------------------------------------------------------------------------------

local function caseValue(rarity: string): number
	for _, entry in GameConfig.CaseShop do
		if entry.Rarity == rarity then
			return entry.Cost
		end
	end
	return 0
end

-- Gives what a product contains. Returns false if it can't be given right now (try again later).
local grantProduct: (Player, Monetization.Product) -> boolean
grantProduct = function(player: Player, product: Monetization.Product): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end
	local key = product.Key
	if product.OneTime and table.find(profile.Bought, key) then
		-- Bought twice somehow: never lose their Robux, pay out the cash part twice instead
		local cash = if product.Cash then GameConfig.Pay(product.Cash, BaseService.RackIncome(player)) else 0
		DataService.AddCash(player, cash * 2 + (if product.Case then caseValue(product.Case) else 0), "robux_product")
		return true
	end

	-- A gift: the chosen player gets the real product (the buyer, if they've left)
	if product.Gift then
		local inner = Monetization.ProductByKey[product.Gift]
		local target = Gamble.GiftTarget(player) or player
		if inner and grantProduct(target, inner) then
			if target ~= player then
				Net.Notify(player, `You gifted {inner.Name} to {target.DisplayName}!`, "good")
				Net.Notify(target, `{player.DisplayName} gifted you {inner.Name}!`, "good")
				Net.Announce(`{player.DisplayName} gifted {target.DisplayName} a {inner.Name}!`, inner.Color, 2)
			end
			return true
		end
		return false
	end
	-- Paid random items aren't allowed where this player lives: never open one (the client hides
	-- them; this is the backstop). They get the case's cash value instead.
	if Monetization.IsPaidRandom(product) and player:GetAttribute("PaidRandomRestricted") == true then
		DataService.AddCash(player, caseValue(product.Case or product.LuckyBlock or "Rare"), "robux_case_value")
		Net.Notify(player, "Cases aren't available where you are - here's cash instead.", "info")
		return true
	end
	local got: { string } = {}
	if product.Cash then
		local cash = GameConfig.Pay(product.Cash, BaseService.RackIncome(player))
		DataService.AddCash(player, cash, "robux_cash")
		Net.Remotes.Effect:FireClient(player, "CashBurst", nil, cash)
		table.insert(got, `{Format.Cash(cash)}`)
	end
	if product.Tickets then
		local amount = product.Tickets
		DataService.Update(player, function(p)
			p.Tickets += amount
		end)
		table.insert(got, `{amount} Murderer Tickets`)
	end
	if product.Case then
		StealService.OpenCase(player, product.Case, true)
		table.insert(got, `a {product.Case} Case`)
	end
	if product.Spins then
		Gamble.AddSpins(player, product.Spins)
		table.insert(got, `{product.Spins} wheel spins`)
	end
	if product.Luck then
		Gamble.AddLuck(player, product.Luck)
		table.insert(got, `{product.Luck // 60} min of 2x Luck`)
	end
	if product.LuckyBlock then
		StealService.OpenCase(player, product.LuckyBlock, true, true)
		table.insert(got, `a {product.LuckyBlock} Lucky Block`)
	end
	if product.Boost then
		local boost = product.Boost
		DataService.AddBoost(player, boost.Name, boost.Seconds)
		if boost.Name == "Speed" then
			BaseService.RefreshWalkSpeed(player)
		end
		table.insert(got, `{boost.Seconds // 60} min of {product.Name:match("^[^%(]+") or boost.Name}`)
	end
	if product.Charge then
		local charge = product.Charge
		DataService.AddCharge(player, charge.Name, charge.Count)
		table.insert(got, product.Name)
	end
	if key == "Mount" then
		if profile.Slots < GameConfig.MaxSlots then
			DataService.Update(player, function(p)
				p.Slots = math.min(GameConfig.MaxSlots, p.Slots + GameConfig.SlotsPerFloor)
			end)
			BaseService.RefreshRack(player)
			table.insert(got, "a new vault floor")
		else
			-- Already maxed: their Robux turn into the cash a mount would have cost
			local value = GameConfig.SlotCost(profile.Slots)
			DataService.AddCash(player, value, "robux_product")
			table.insert(got, `{Format.Cash(value)} (your vault was already maxed)`)
		end
	elseif key == "HealthBoost" then
		local before = profile.HealthLevel
		local after = math.min(before + 3, GameConfig.Health.MaxLevel)
		if after > before then
			DataService.Update(player, function(p)
				p.HealthLevel = after
			end)
			table.insert(got, `+{after - before} Health levels`)
		end
		-- Anything past the max comes back as the cash those levels would have cost
		local refund = 0
		for level = after, before + 2 do
			refund += GameConfig.HealthCost(level)
		end
		if refund > 0 then
			DataService.AddCash(player, refund, "robux_product")
			table.insert(got, `{Format.Cash(refund)} (health was maxed)`)
		end
	elseif key == "ServerLuck" then
		local config = Monetization.ServerLuck
		local now = workspace:GetServerTimeNow()
		local current = ReplicatedStorage:GetAttribute("ServerLuckUntil")
		local from = if type(current) == "number" and current > now then current else now
		ReplicatedStorage:SetAttribute("ServerLuckMultiplier", config.Multiplier)
		ReplicatedStorage:SetAttribute("ServerLuckUntil", from + config.Minutes * 60)
		Net.Announce(
			`🍀 {player.DisplayName} activated {config.Multiplier}x SERVER LUCK for everyone!`,
			Color3.fromRGB(90, 230, 120),
			3
		)
		table.insert(got, "Server Luck")
	elseif key == "ChestRefill" then
		DataService.Update(player, function(p)
			p.NextFreeChest = 0
		end)
		table.insert(got, "a full free chest")
	elseif key == "CollectSession" then
		player:SetAttribute("SessionAutoCollect", true) -- gone when they leave (never saved)
		table.insert(got, "Auto Collect until you leave")
	elseif key == "HeatRefill" then
		Fuel.AddHeat(player, GameConfig.Fuel.MaxHeat - profile.Heat, "Full Heat!")
		table.insert(got, "full Heat")
	elseif key == "BossRestock" then
		local boss = GuardService.RestockNear(player)
		if boss then
			Net.Announce(`🔄 {player.DisplayName} restocked {boss}'s wall!`, Color3.fromRGB(255, 140, 90), 2)
			table.insert(got, `{boss}'s wall restocked`)
		else
			-- Nothing was waiting there: a Mythic Lucky Block's worth of cash instead of nothing
			local value = GameConfig.Pay({ Min = 5000, Seconds = 600 }, BaseService.RackIncome(player))
			DataService.AddCash(player, value, "robux_product")
			table.insert(got, `{Format.Cash(value)} (that wall was already full)`)
		end
	elseif key == "OfflineDouble" then
		local amount = profile.LastOffline
		if amount <= 0 then
			amount = GameConfig.Pay({ Min = 1000, Seconds = 1800 }, BaseService.RackIncome(player))
		end
		DataService.AddCash(player, amount, "robux_product")
		DataService.Update(player, function(p)
			p.LastOffline = 0
		end)
		Net.Remotes.Effect:FireClient(player, "CashBurst", nil, amount)
		table.insert(got, Format.Cash(amount))
	elseif key == "StreakSave" then
		if Rewards.RestoreStreak(player) then
			table.insert(got, "your daily streak back")
		else
			Gamble.AddSpins(player, 3) -- nothing to restore: never lose their Robux
			table.insert(got, "3 wheel spins (your streak was fine)")
		end
	elseif key == "BloodMoon" then
		RaidService.Summon(player)
		table.insert(got, "the Blood Moon")
	end
	if product.OneTime then
		DataService.Update(player, function(p)
			table.insert(p.Bought, key)
		end)
		player:SetAttribute("Bought_" .. key, true)
	end
	if #got > 0 then
		Net.Notify(player, `{product.Icon} Thank you! You got {table.concat(got, ", ")}`, "good")
	end
	return true
end

local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local profile = player and DataService.Get(player)
	if not player or not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(info.PurchaseId)
	if table.find(profile.Receipts, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local product = productById[info.ProductId]
	if not product then
		warn(`[Monetization] unknown product {info.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(grantProduct, player, product)
	if not ok or not granted then
		warn(`[Monetization] couldn't grant {product.Key} to {player.Name}: {granted}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	DataService.Update(player, function(p)
		table.insert(p.Receipts, purchaseId)
		while #p.Receipts > MAX_RECEIPTS do
			table.remove(p.Receipts, 1)
		end
	end)
	local robux = tonumber(info.CurrencySpent) or product.Price or 0
	Analytics.Robux(player, robux)
	Analytics.Track(player, "purchase.product", { key = product.Key, robux = robux, price = product.Price })
	Analytics.Milestone(player, "first_purchase", { key = product.Key, robux = robux })
	if not DataService.SaveNow(player) then
		-- Roblox will retry; the PurchaseId is already recorded, so it won't be granted twice
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Studio: "buy" things whose ids aren't filled in yet, to test them for free
local lastTest: { [Player]: number } = {}
local function storeTest(player: Player, kind: unknown, key: unknown): boolean
	if not RunService:IsStudio() or type(key) ~= "string" then
		return false
	end
	if os.clock() - (lastTest[player] or 0) < 0.5 then
		return false
	end
	lastTest[player] = os.clock()
	Analytics.Track(player, "purchase.studio_test", { kind = kind, key = key })
	if kind == "Pass" and Monetization.PassByKey[key] then
		grantPass(player, key, true)
		return true
	elseif kind == "Product" and Monetization.ProductByKey[key] then
		return grantProduct(player, Monetization.ProductByKey[key])
	end
	return false
end

function MonetizationService.Init()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			local pass = passById[passId]
			if purchased and pass then
				grantPass(player, pass.Key, true)
				Analytics.Robux(player, pass.Price)
				Analytics.Track(player, "purchase.pass", { key = pass.Key, robux = pass.Price })
				Analytics.Milestone(player, "first_purchase", { key = pass.Key, robux = pass.Price })
			end
		end
	)
	Net.Remotes.StoreTest.OnServerInvoke = storeTest

	local function setup(player: Player)
		player:SetAttribute("JoinedAt", os.time())
		-- Roblox policy: paid random items (Robux cases, Lucky Blocks) are off where restricted.
		-- If the check fails we assume restricted (the safe side).
		task.spawn(function()
			local ok, info = pcall(function()
				return game:GetService("PolicyService"):GetPolicyInfoForPlayerAsync(player)
			end)
			player:SetAttribute("PaidRandomRestricted", not ok or (info :: any).ArePaidRandomItemsRestricted == true)
		end)
		task.spawn(checkPasses, player)
	end
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerAdded:Connect(setup)
	Players.PlayerRemoving:Connect(function(player)
		lastTest[player] = nil
	end)

	-- The Starter Pack, once, right after the guide (they know the game by then)
	Net.Remotes.Tutorial.OnServerEvent:Connect(function(player: Player, step: unknown)
		if step == "Done" or step == "Skip" then
			task.delay(6, function()
				Offers.Show(
					player,
					"Starter",
					"Welcome to Blackwood! A one-time head start, just for new players.",
					true
				)
			end)
		end
	end)
end

return MonetizationService
