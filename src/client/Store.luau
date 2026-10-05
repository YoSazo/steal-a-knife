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
local Telemetry = require(script.Parent.Telemetry)
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
	if
		kind == "Product"
		and Monetization.IsPaidRandom(entry :: any)
		and player:GetAttribute("PaidRandomRestricted") ~= false
	then
		-- not available here (or not checked yet): Roblox's paid random item policy
		if Ui.Toast then
			Ui.Toast("This isn't available where you are.", "bad")
		end
		return
	end
	Telemetry.Prompt(kind, key)
	if entry.Id > 0 then
		if kind == "Pass" then
			MarketplaceService:PromptGamePassPurchase(player, entry.Id)
		else
			MarketplaceService:PromptProductPurchase(player, entry.Id)
		end
	elseif RunService:IsStudio() then
		Remotes:WaitForChild("StoreTest"):InvokeServer(kind, key)
	elseif Ui.Toast then
		Ui.Toast("Coming soon!", "info") -- (not on sale yet: its Robux id isn't set up)
	end
end

-- Other modules (the gift picker, the wheel) buy through the same path
Ui.Buy = buy

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

-- Roblox's buy popup fetches the item's picture only when it opens (a blank square for a while on
-- a phone). Warm it up in the background after joining: ask Roblox for every product's info (the
-- same lookup the popup makes) and preload its icon, so it's already on the device.
local function preloadIcons()
	task.wait(8) -- (after the game has loaded: never slow the join)
	local ContentProvider = game:GetService("ContentProvider")
	local images: { string } = {}
	local entries: { { Id: number, Kind: Enum.InfoType } } = {}
	for _, pass in Monetization.Passes do
		if pass.Id > 0 then
			table.insert(entries, { Id = pass.Id, Kind = Enum.InfoType.GamePass })
		end
	end
	for _, product in Monetization.Products do
		if product.Id > 0 then
			table.insert(entries, { Id = product.Id, Kind = Enum.InfoType.Product })
		end
	end
	for _, entry in entries do
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, entry.Id, entry.Kind)
		local icon = ok and (info :: any).IconImageAssetId
		if type(icon) == "number" and icon > 0 then
			table.insert(images, `rbxassetid://{icon}`)
			table.insert(images, `rbxthumb://type=Asset&id={icon}&w=150&h=150`)
		end
		task.wait(0.15) -- (gentle on the web API)
	end
	pcall(ContentProvider.PreloadAsync, ContentProvider, images)
end

function Store.Init()
	task.spawn(preloadIcons)
	local gui = Ui.gui

	StoreView.Build({ buy = buy, owned = owned, cash = cashFor, odds = CaseOdds.Text, price = priceButton })

	-- Contextual offers ---------------------------------------------------------------------------
	local offerCard: Frame? = nil
	local offerKey, offerAt = "", 0
	local function offerClosed(how: string)
		Telemetry.Track("offer.close", { key = offerKey, how = how, seconds = math.floor(os.clock() - offerAt) })
	end
	local function hideOffers()
		if offerCard and (Ui.menuOpen() or gui:GetAttribute("KnifeGestureActive") == true) then
			offerClosed("menu")
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
			Telemetry.Track("offer.blocked", {
				key = key,
				why = if owned(key)
					then "owned"
					elseif player:GetAttribute("InRound") then "round"
					elseif Ui.menuOpen() then "menu"
					else "gesture",
			})
			return
		end
		local kind = kindOf(key)
		local entry: { Name: string, Icon: string, Price: number, Color: Color3 } = if kind == "Pass"
			then Monetization.PassByKey[key] :: any
			else Monetization.ProductByKey[key] :: any
		if not entry then
			return
		end
		if offerCard then
			offerClosed("replaced")
		end
		closeOffer()
		offerKey, offerAt = key, os.clock()
		Telemetry.OfferShown(key)
		local card = new("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 360, OFFER_Y, 0),
			Size = UDim2.fromOffset(330, 150),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 20,
		}, Ui.feedback) -- (above menus: an offer often follows a "not enough cash" inside one)
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
			Telemetry.Track("offer.click", { key = key })
			buy(kind, key)
			closeOffer()
		end)
		Ui.button(
			{
				Position = UDim2.fromOffset(210, 94),
				Size = UDim2.fromOffset(110, 46),
				BackgroundColor3 = Color3.fromRGB(80, 76, 96),
				Text = "No thanks",
				ZIndex = 22,
			},
			card,
			function()
				offerClosed("no_thanks")
				closeOffer()
			end
		)
		Effects.Sound(Sounds.Reveal, nil, 0.4)
		TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back), {
			Position = UDim2.new(1, OFFER_X, OFFER_Y, 0),
		}):Play()
		task.delay(14, function()
			if offerCard == card then
				offerClosed("timeout")
				closeOffer()
			end
		end)
	end)
	player:GetAttributeChangedSignal("InRound"):Connect(function()
		if player:GetAttribute("InRound") then
			closeOffer()
		end
	end)
end

return Store
