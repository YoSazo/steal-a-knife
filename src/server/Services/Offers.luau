--!strict
-- Contextual store offers: "here's the thing that fixes what just happened" (short on cash, wall
-- full, gate under attack, just robbed...). Any service can call Offers.Show without pulling in
-- the whole MonetizationService. Rate limited hard (Monetization.OfferGap and friends) and never
-- shown during a round, so it never feels like spam.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Net = require(script.Parent.Parent.Remotes)
local Analytics = require(script.Parent.Analytics)

local Offers = {}

local lastAny: { [Player]: number } = {}
local lastByKey: { [Player]: { [string]: number } } = {}

-- Whether `player` already has this (owned pass, or a one-time pack they've bought)
function Offers.Has(player: Player, key: string): boolean
	if Monetization.PassByKey[key] then
		return player:GetAttribute("Pass_" .. key) == true
	end
	local product = Monetization.ProductByKey[key]
	return product ~= nil and product.OneTime == true and player:GetAttribute("Bought_" .. key) == true
end

-- `early` skips the first-minutes grace period (the Starter Pack right after the tutorial)
function Offers.Show(player: Player, key: string, reason: string, early: boolean?)
	if not player.Parent or player:GetAttribute("InRound") or Offers.Has(player, key) then
		return
	end
	if not Monetization.PassByKey[key] and not Monetization.ProductByKey[key] then
		return
	end
	local joined = player:GetAttribute("JoinedAt")
	local grace = if RunService:IsStudio() then 10 else Monetization.FirstOfferAfter
	if not early and type(joined) == "number" and os.time() - joined < grace then
		return
	end
	local now = os.clock()
	local gap = if RunService:IsStudio() then 20 else Monetization.OfferGap
	if now - (lastAny[player] or -math.huge) < gap then
		return
	end
	local byKey = lastByKey[player] or {}
	lastByKey[player] = byKey
	if now - (byKey[key] or -math.huge) < Monetization.SameOfferGap then
		return
	end
	lastAny[player] = now
	byKey[key] = now
	Net.Remotes.Offer:FireClient(player, key, reason)
	Analytics.Track(player, "offer.shown", { key = key, reason = Analytics.Normalize(reason) })
end

-- Short on cash: offer the smallest cash pack that covers the gap
function Offers.Cash(player: Player, short: number, income: number)
	if short <= 0 then
		return
	end
	for _, key in { "CashSmall", "CashMedium", "CashBig" } do
		local product = Monetization.ProductByKey[key]
		if product and product.Cash and GameConfig.Pay(product.Cash, income) >= short then
			Offers.Show(player, key, `Only {Format.Cash(math.ceil(short))} short? This covers it right now.`)
			return
		end
	end
	Offers.Show(player, "CashBig", "Need a big boost? Four hours of income, right now.")
end

-- Show an offer once they're out of the round (it happened in a round, but offers never show
-- there): waits up to `within` seconds for InRound to go off, plus a moment to read the results
function Offers.Later(player: Player, key: string, reason: string, within: number?)
	task.spawn(function()
		local deadline = os.clock() + (within or 240)
		while player.Parent and player:GetAttribute("InRound") and os.clock() < deadline do
			task.wait(1)
		end
		task.wait(6)
		Offers.Show(player, key, reason)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	lastAny[player] = nil
	lastByKey[player] = nil
end)

return Offers
