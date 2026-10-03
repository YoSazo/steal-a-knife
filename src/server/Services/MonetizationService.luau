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
local Analytics = require(script.Parent.Analytics)
local RaidService = require(script.Parent.RaidService)
local StealService = require(script.Parent.StealService)

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

-- VIP tag ------------------------------------------------------------------------------------

-- A gold "VIP" over the head in the hub (hidden in rounds: disguises must stay anonymous)
local function refreshTag(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local tag = head:FindFirstChild("VIPTag") :: BillboardGui?
	local show = player:GetAttribute("Pass_VIP") == true and not player:GetAttribute("InRound")
	if show and not tag then
		local gui = Instance.new("BillboardGui")
		gui.Name = "VIPTag"
		gui.Size = UDim2.fromOffset(90, 30)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
		gui.MaxDistance = 90
		gui.Parent = head
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = "👑 VIP"
		label.TextColor3 = Color3.fromRGB(255, 205, 60)
		label.TextStrokeTransparency = 0
		label.Parent = gui
	elseif tag then
		tag.Enabled = show
	end
end

-- Passes -------------------------------------------------------------------------------------

local function grantPass(player: Player, key: string, announce: boolean)
	if player:GetAttribute("Pass_" .. key) then
		return
	end
	player:SetAttribute("Pass_" .. key, true)
	local pass = Monetization.PassByKey[key]
	if key == "Fortified" then
		local base = BaseService.GetBase(player)
		if base then
			BaseService.RefreshWalls(base)
		end
	elseif key == "DoubleCash" or key == "VIP" then
		BaseService.RefreshRack(player) -- income readouts
	end
	if key == "VIP" then
		refreshTag(player)
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
local function grantProduct(player: Player, product: Monetization.Product): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end
	local key = product.Key
	if product.OneTime and table.find(profile.Bought, key) then
		-- Bought twice somehow: never lose their Robux, pay out the cash part twice instead
		local cash = if product.Cash then GameConfig.Pay(product.Cash, BaseService.RackIncome(player)) else 0
		DataService.AddCash(player, cash * 2 + (if product.Case then caseValue(product.Case) else 0))
		return true
	end

	local got: { string } = {}
	if product.Cash then
		local cash = GameConfig.Pay(product.Cash, BaseService.RackIncome(player))
		DataService.AddCash(player, cash)
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
			DataService.AddCash(player, value)
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
			DataService.AddCash(player, refund)
			table.insert(got, `{Format.Cash(refund)} (health was maxed)`)
		end
	elseif key == "Repair" then
		RaidService.RepairFull(player)
		table.insert(got, "a fully repaired gate")
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
	elseif key == "BloodMoon" then
		RaidService.Summon(player)
		table.insert(got, "the Thief Moon")
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
	Analytics.Purchased(player, product.Key, product.Price, "product")
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
				Analytics.Purchased(player, pass.Key, pass.Price, "pass")
			end
		end
	)
	Net.Remotes.StoreTest.OnServerInvoke = storeTest

	local function setup(player: Player)
		player:SetAttribute("JoinedAt", os.time())
		task.spawn(checkPasses, player)
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			refreshTag(player)
		end)
		player:GetAttributeChangedSignal("InRound"):Connect(function()
			refreshTag(player)
		end)
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
