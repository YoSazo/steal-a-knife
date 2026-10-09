--!strict
-- Robux: game passes and developer products (Config/Monetization).
--   * passes: checked on join and on purchase, mirrored to the player as attribute Pass_<Key>
--     (server-set, so it can't be faked). Other services just read the attribute:
--       DoubleCash / VIP   BaseService.IncomeMultiplier      FastWheel  BaseService training
--       VIP                the tag (client/Overheads)        Luck       CoffinService.Luck
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
local PenMode = require(ReplicatedStorage.Shared.PenMode)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local Gamble = require(script.Parent.Gamble)
local GuardService = require(script.Parent.GuardService)
local Rewards = require(script.Parent.Rewards)
local Analytics = require(script.Parent.Analytics)
local CoffinService = require(script.Parent.CoffinService)

local MonetizationService = {}

-- PurchaseIds kept per profile. Roblox only re-sends a receipt until it's acknowledged, and we only
-- acknowledge once the id is saved, so this just has to outlast a burst of purchases between
-- saves - 200 is plenty and stays small in the save.
local MAX_RECEIPTS = 200
-- Receipts being handled right now: Roblox can call ProcessReceipt again for the same purchase
-- while the first call is still yielding (a save, a grant); the second one must not grant too
local inFlight: { [string]: boolean } = {}

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
				-- (pens hold at most Pens.MaxSlots and grow a few at a time: PassRoom)
				local room = GameConfig.Pens.PassRoom
				p.Slots = math.min(PenMode.MaxSlots(), p.Slots + room)
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

-- Each pass is counted as a purchase once (profile.Bought "Pass:<Key>"): bought in game it's
-- counted when the prompt finishes; bought on the game's Roblox page (its Store tab) we only find
-- out here, on the next join - those were invisible to analytics before
local function countPass(player: Player, pass: Monetization.Pass, source: string)
	local profile = DataService.Get(player)
	local mark = "Pass:" .. pass.Key
	if not profile or table.find(profile.Bought, mark) then
		return
	end
	DataService.Update(player, function(p)
		table.insert(p.Bought, mark)
	end)
	Analytics.Robux(player, pass.Price)
	Analytics.Track(player, "purchase.pass", { key = pass.Key, robux = pass.Price, source = source })
	Analytics.Milestone(player, "first_purchase", { key = pass.Key, robux = pass.Price })
end

local function checkPasses(player: Player)
	-- (the profile first: ExtraFloor's slots and the purchase record both live in it)
	local waited = 0
	while player.Parent and not DataService.Get(player) and waited < 60 do
		waited += task.wait(0.25)
	end
	local profile = DataService.Get(player)
	if not player.Parent or not profile then
		return
	end
	-- Retired passes (a system that was cut): the owner gets the Robux back as cash, once
	for id, price in Monetization.RetiredPasses do
		local mark = `RetiredPass:{id}`
		if not table.find(profile.Bought, mark) then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
			if ok and owns and player.Parent then
				local value =
					GameConfig.Pay({ Min = price * 4000, Seconds = price * 20 }, BaseService.RackIncome(player))
				DataService.Update(player, function(p)
					table.insert(p.Bought, mark)
				end)
				DataService.AddCash(player, value, "robux_retired_pass")
				Net.Notify(player, `Thank you! A pass you own was retired, so you got {Format.Cash(value)}.`, "good")
			end
		end
	end
	for _, pass in Monetization.Passes do
		if pass.Id > 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
			if ok and owns and player.Parent then
				grantPass(player, pass.Key, false)
				countPass(player, pass, "outside")
			end
		end
	end
	player:SetAttribute("PassesChecked", true) -- Rewards waits for this before offline earnings
end

-- Products -----------------------------------------------------------------------------------

local function coffinValue(rarity: string): number
	return GameConfig.CoffinValue[rarity] or 0
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
		DataService.AddCash(
			player,
			cash * 2 + (if product.Coffin then coffinValue(product.Coffin) else 0),
			"robux_product"
		)
		return true
	end

	-- Paid random items aren't allowed where this player lives: the coffin's cash value instead
	local restricted = Monetization.IsPaidRandom(product) and player:GetAttribute("PaidRandomRestricted") == true
	local got: { string } = {}
	if product.Cash then
		local cash = GameConfig.Pay(product.Cash, BaseService.RackIncome(player))
		DataService.AddCash(player, cash, "robux_cash")
		Net.Remotes.Effect:FireClient(player, "CashBurst", nil, cash)
		table.insert(got, `{Format.Cash(cash)}`)
	end
	if product.Speed then
		local amount = Monetization.SpeedFor(product, profile.Speed)
		DataService.Update(player, function(p)
			p.Speed += amount
		end)
		BaseService.RefreshWalkSpeed(player)
		table.insert(got, `+{Format.Short(amount)} Speed`)
	end
	if product.Tickets then
		local amount = product.Tickets
		DataService.Update(player, function(p)
			p.Tickets += amount
		end)
		table.insert(got, `{amount} Murderer Tickets`)
	end
	if product.Coffin then
		if restricted then
			local value = coffinValue(product.Coffin)
			DataService.AddCash(player, value, "robux_coffin_value")
			table.insert(got, Format.Cash(value))
		else
			if CoffinService.GiveRarity(player, product.Coffin, "the Starter Pack", true) then
				table.insert(got, `a {product.Coffin} {if PenMode.Coffins() then "Coffin" else "knife"}`)
			else
				local value = coffinValue(product.Coffin)
				DataService.AddCash(player, value, "robux_coffin_value")
				table.insert(got, `{Format.Cash(value)} (no room for a coffin)`)
			end
		end
	end
	if product.Spins then
		Gamble.AddSpins(player, product.Spins)
		table.insert(got, `{product.Spins} wheel spins`)
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
		if profile.Slots < PenMode.MaxSlots() then
			local _, step = PenMode.RoomUpgrade(profile.Slots)
			DataService.Update(player, function(p)
				p.Slots = math.min(PenMode.MaxSlots(), p.Slots + step)
			end)
			BaseService.RefreshRack(player)
			table.insert(got, PenMode.Words("a bigger vault"))
		else
			-- Already maxed: their Robux turn into the cash a mount would have cost
			local costs = GameConfig.Pens.SlotCosts
			local value = costs[#costs]
			DataService.AddCash(player, value, "robux_product")
			table.insert(got, `{Format.Cash(value)} (your vault was already maxed)`)
		end
	elseif key == "CoffinOpen" then
		if CoffinService.OpenNow(player) then
			table.insert(got, "your coffin, open")
		else
			-- Nothing sealed any more (it opened on its own meanwhile): its worth in cash instead
			local value = GameConfig.Pay({ Min = 5000, Seconds = 600 }, BaseService.RackIncome(player))
			DataService.AddCash(player, value, "robux_product")
			table.insert(got, `{Format.Cash(value)} (that coffin had already opened)`)
		end
	elseif key == "CollectSession" then
		player:SetAttribute("SessionAutoCollect", true) -- gone when they leave (never saved)
		table.insert(got, "Auto Collect until you leave")
	elseif key == "BossRestock" then
		local boss = GuardService.RestockNear(player)
		if boss then
			Net.Announce(`🔄 {player.DisplayName} restocked the {boss}!`, Color3.fromRGB(255, 140, 90), 2)
			table.insert(got, `the {boss} restocked`)
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

local handleReceipt: (info: { [string]: any }, player: Player, profile: any, purchaseId: string) -> Enum.ProductPurchaseDecision

local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local profile = player and DataService.Get(player)
	if not player or not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(info.PurchaseId)
	if inFlight[purchaseId] then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- (the other call finishes it)
	end
	inFlight[purchaseId] = true
	local ok, decision = pcall(handleReceipt, info, player, profile, purchaseId)
	inFlight[purchaseId] = nil
	if not ok then
		warn(`[Monetization] receipt {purchaseId} failed: {decision}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return decision
end

handleReceipt = function(info, player, profile, purchaseId): Enum.ProductPurchaseDecision
	if table.find(profile.Receipts, purchaseId) then
		-- Granted before, but maybe never saved (that save failed): never grant again, only
		-- acknowledge once the record is really saved
		return if DataService.SaveNow(player)
			then Enum.ProductPurchaseDecision.PurchaseGranted
			else Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local product = productById[info.ProductId]
	local retired = Monetization.Retired[info.ProductId]
	if not product and not retired then
		warn(`[Monetization] unknown product {info.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(function(): boolean
		if product then
			return grantProduct(player, product)
		end
		-- A product we no longer sell: cash worth the Robux (~20 s of income per Robux)
		local price = retired :: number
		local value = GameConfig.Pay({ Min = price * 4000, Seconds = price * 20 }, BaseService.RackIncome(player))
		DataService.AddCash(player, value, "robux_product")
		Net.Notify(player, `Thank you! That item was retired, so you got {Format.Cash(value)} instead.`, "good")
		return true
	end)
	if not ok or not granted then
		warn(`[Monetization] couldn't grant {info.ProductId} to {player.Name}: {granted}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	DataService.Update(player, function(p)
		table.insert(p.Receipts, purchaseId)
		while #p.Receipts > MAX_RECEIPTS do
			table.remove(p.Receipts, 1)
		end
	end)
	local robux = tonumber(info.CurrencySpent) or (if product then product.Price else retired) or 0
	local key = if product then product.Key else `retired:{info.ProductId}`
	Analytics.Robux(player, robux)
	Analytics.Track(player, "purchase.product", { key = key, robux = robux, price = product and product.Price })
	Analytics.Milestone(player, "first_purchase", { key = key, robux = robux })
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
	MonetizationService.ProcessReceipt = processReceipt -- (tests: Roblox's callback can't be read back)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			local pass = passById[passId]
			if purchased and pass then
				grantPass(player, pass.Key, true)
				countPass(player, pass, "game")
			end
		end
	)
	Net.Remotes.StoreTest.OnServerInvoke = storeTest

	local function setup(player: Player)
		player:SetAttribute("JoinedAt", os.time())
		-- Roblox policy: paid random items (a Robux coffin) are off where restricted.
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
end

return MonetizationService
