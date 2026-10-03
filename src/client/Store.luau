--!strict
-- The Robux side of the HUD (Config/Monetization, server: MonetizationService):
--   * the 💎 STORE button and panel: passes, boosts, and Robux cases with their full odds
--   * contextual offers (Remotes.Offer): a card that slides in when you hit something a product
--     fixes - short on cash, wall full, gate under attack - then gets out of the way
--   * "Instant Repair" beside the Repair button while your gate is damaged
--   * the Server Luck timer while someone's luck boost is running
-- Purchases go through MarketplaceService; in Studio, anything without an id is faked for testing.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local Effects = require(script.Parent.Effects)
local StoreView = require(script.Parent.StoreView)
local CaseOdds = require(script.Parent.CaseOdds)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Monetization = require(Shared.Config:WaitForChild("Monetization"))
local Sounds = require(Shared.Config:WaitForChild("Sounds"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local new = Ui.new

local Store = {}

local DARK = Ui.PANEL
local ROBUX = Color3.fromRGB(0, 176, 111)
-- Where offer cards settle: left of the right-hand buttons (higher on phones, above the thumbs)
local OFFER_X = if Ui.Phone then -190 else -262
local OFFER_Y = if Ui.Phone then 0.46 else 0.62

-- Buying ---------------------------------------------------------------------------------------

local function buy(kind: string, key: string)
	local entry: { Id: number } = if kind == "Pass"
		then Monetization.PassByKey[key] :: any
		else Monetization.ProductByKey[key] :: any
	if not entry then
		return
	end
	if entry.Id > 0 then
		if kind == "Pass" then
			MarketplaceService:PromptGamePassPurchase(player, entry.Id)
		else
			MarketplaceService:PromptProductPurchase(player, entry.Id)
		end
	elseif RunService:IsStudio() then
		Remotes:WaitForChild("StoreTest"):InvokeServer(kind, key)
	end
end

local function kindOf(key: string): string
	return if Monetization.PassByKey[key] then "Pass" else "Product"
end

local function owned(key: string): boolean
	return player:GetAttribute("Pass_" .. key) == true or player:GetAttribute("Bought_" .. key) == true
end

-- What a cash pack is worth to *you* right now
local function cashFor(product: Monetization.Product): number?
	if not product.Cash then
		return nil
	end
	local income = (player:GetAttribute("Income") or 0) :: number
	return GameConfig.Pay(product.Cash, income)
end

-- A green Robux price button
local function priceButton(parent: Instance, price: number, props: { [string]: any }, onClick: () -> ()): TextButton
	props.BackgroundColor3 = ROBUX
	props.Text = `R$ {price}`
	local button = Theme.button(parent, `R$ {price}`, Theme.Green, props, onClick)
	return button
end

-- Case odds (the same numbers the Case Shop shows) -----------------------------------------------

-- The Store panel --------------------------------------------------------------------------------

local function text(parent: Instance, props: { [string]: any }): TextLabel
	props.ZIndex = props.ZIndex or 6
	local label = Ui.label(props, parent)
	Ui.textStroke(label, 1.5)
	return label
end

function Store.Init()
	local gui = Ui.gui

	StoreView.Build({ buy = buy, owned = owned, cash = cashFor, odds = CaseOdds.Text, price = priceButton })

	-- Contextual offers ---------------------------------------------------------------------------
	local offerCard: Frame? = nil
	local function hideOffers()
		if offerCard and (Ui.menuOpen() or gui:GetAttribute("KnifeGestureActive") == true) then
			offerCard:Destroy()
			offerCard = nil
		end
	end
	gui:GetAttributeChangedSignal("MenuOpen"):Connect(hideOffers)
	gui:GetAttributeChangedSignal("KnifeGestureActive"):Connect(hideOffers)
	local function closeOffer()
		local card = offerCard
		offerCard = nil
		if card then
			TweenService:Create(card, TweenInfo.new(0.25), { Position = UDim2.new(1, 360, OFFER_Y, 0) }):Play()
			task.delay(0.3, function()
				card:Destroy()
			end)
		end
	end
	Remotes:WaitForChild("Offer").OnClientEvent:Connect(function(key: string, reason: string)
		if
			Ui.menuOpen()
			or gui:GetAttribute("KnifeGestureActive") == true
			or player:GetAttribute("InRound")
			or owned(key)
		then
			return
		end
		local kind = kindOf(key)
		local entry: { Name: string, Icon: string, Price: number, Color: Color3 } = if kind == "Pass"
			then Monetization.PassByKey[key] :: any
			else Monetization.ProductByKey[key] :: any
		if not entry then
			return
		end
		closeOffer()
		local card = new("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 360, OFFER_Y, 0),
			Size = UDim2.fromOffset(330, 150),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 20,
		}, gui)
		offerCard = card
		Ui.corner(card, 14)
		Ui.gradient(card, entry.Color:Lerp(DARK, 0.25), entry.Color:Lerp(DARK, 0.75))
		new("UIStroke", { Thickness = 3.5, Color = Color3.fromRGB(16, 12, 22) }, card)
		text(card, {
			Position = UDim2.fromOffset(10, 6),
			Size = UDim2.new(1, -56, 0, 32),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = `{entry.Icon} {entry.Name}`,
			ZIndex = 21,
		})
		text(card, {
			Position = UDim2.fromOffset(10, 40),
			Size = UDim2.new(1, -20, 0, 46),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = false,
			TextSize = 16,
			TextWrapped = true,
			Text = reason,
			ZIndex = 21,
		})
		priceButton(card, entry.Price, {
			Position = UDim2.fromOffset(10, 94),
			Size = UDim2.fromOffset(190, 46),
			ZIndex = 22,
		}, function()
			buy(kind, key)
			closeOffer()
		end)
		Ui.button({
			Position = UDim2.fromOffset(210, 94),
			Size = UDim2.fromOffset(110, 46),
			BackgroundColor3 = Color3.fromRGB(80, 76, 96),
			Text = "No thanks",
			ZIndex = 22,
		}, card, closeOffer)
		Effects.Sound(Sounds.Reveal, nil, 0.4)
		TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back), {
			Position = UDim2.new(1, OFFER_X, OFFER_Y, 0),
		}):Play()
		task.delay(14, function()
			if offerCard == card then
				closeOffer()
			end
		end)
	end)
	player:GetAttributeChangedSignal("InRound"):Connect(function()
		if player:GetAttribute("InRound") then
			closeOffer()
		end
	end)

	-- Instant Repair, beside the Repair button while your gate is damaged -------------------------
	local repair = Monetization.ProductByKey.Repair
	local instant = priceButton(gui, repair.Price, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 160),
		Size = UDim2.fromOffset(120, 44),
		Visible = false,
	}, function()
		buy("Product", "Repair")
	end)
	local instantLabel = instant:FindFirstChild("Label") :: TextLabel?
	if instantLabel then
		instantLabel.Text = `🔧 Instant  R$ {repair.Price}`
	end
	local function refreshRepair()
		instant.Visible = gui:GetAttribute("RepairVisible") == true
			and not Ui.menuOpen()
			and gui:GetAttribute("KnifeGestureActive") ~= true
	end
	for _, attribute in { "RepairVisible", "MenuOpen", "KnifeGestureActive" } do
		gui:GetAttributeChangedSignal(attribute):Connect(refreshRepair)
	end
end

return Store
