--!strict
-- Codes (PLAN item 26): More -> Codes sends Remotes.RedeemCode(code). Each code in Config/Codes
-- works once per player (profile.Claimed "code:<CODE>"); the reward is sized to them (FreeRewards).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Codes = require(ReplicatedStorage.Shared.Config.Codes)
local Net = require(script.Parent.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local FreeRewards = require(script.Parent.FreeRewards)
local Analytics = require(script.Parent.Analytics)

local CodesService = {}

local lastTry: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

local function redeem(player: Player, raw: unknown): (boolean, string)
	if type(raw) ~= "string" or #raw > 40 then
		return false, "That code doesn't work."
	end
	local now = os.clock()
	if now - (lastTry[player] or 0) < 1.5 then
		return false, "Slow down!"
	end
	lastTry[player] = now
	local profile = DataService.Get(player)
	if not profile then
		return false, "Still loading..."
	end
	local name = string.upper((raw:gsub("%s", "")))
	local code = Codes[name]
	if not code or (code.Ends and os.time() > code.Ends) then
		Analytics.Track(player, "code.bad", { code = name:sub(1, 20) })
		return false, "That code doesn't work."
	end
	local key = "code:" .. name
	if table.find(profile.Claimed, key) then
		return false, "Already used!"
	end
	-- Mark it first: a second request racing this one finds it taken
	DataService.Update(player, function(p)
		table.insert(p.Claimed, key)
	end)
	local got = FreeRewards.Give(player, code.Reward, "code")
	Analytics.Track(player, "code.redeemed", { code = name })
	local message = `Code worked! {got or ""}`
	Net.Notify(player, message, "good")
	return true, message
end

function CodesService.Init()
	Net.Remotes.RedeemCode.OnServerInvoke = redeem
end

return CodesService
