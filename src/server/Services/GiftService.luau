--!strict
-- The free gift (PLAN item 22, Steal An Egg's): join the community group (GameConfig.CommunityGroupId)
-- and claim a one-time Speed reward sized to the next monster (GameConfig.GroupGift). The client
-- offers it after a round you won (client/GiftCard); the join is checked live here (GroupService,
-- not the per-session group cache, so joining mid-visit counts). profile.Claimed "gift:group";
-- player attribute GiftClaimed hides the card.

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(script.Parent.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local FreeRewards = require(script.Parent.FreeRewards)
local Analytics = require(script.Parent.Analytics)

local GiftService = {}

local KEY = "gift:group"
local lastTry: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

local busy: { [Player]: boolean } = {}

local function inGroup(player: Player): boolean
	local ok, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
	if ok and type(groups) == "table" then
		for _, group in groups do
			if group.Id == GameConfig.CommunityGroupId then
				return true
			end
		end
		return false
	end
	local cached, member = pcall(player.IsInGroupAsync, player, GameConfig.CommunityGroupId)
	return cached and member == true
end

local function claim(player: Player): (boolean, string)
	local now = os.clock()
	if busy[player] or now - (lastTry[player] or 0) < 2 then
		return false, "One sec..."
	end
	lastTry[player] = now
	local profile = DataService.Get(player)
	if not profile then
		return false, "Still loading..."
	end
	if table.find(profile.Claimed, KEY) then
		return false, "Already claimed!"
	end
	if profile.RoundsWon < 1 then
		return false, "Win a round first!"
	end
	busy[player] = true
	local member = inGroup(player)
	busy[player] = nil
	profile = DataService.Get(player)
	if not profile or not player.Parent then
		return false, "Try again later!"
	end
	if table.find(profile.Claimed, KEY) then
		return false, "Already claimed!"
	end
	if not member then
		return false, "Join the group first!"
	end
	DataService.Update(player, function(p)
		table.insert(p.Claimed, KEY)
	end)
	player:SetAttribute("GiftClaimed", true)
	local got = FreeRewards.Give(player, { Speed = GameConfig.GroupGift.Speed }, "group_gift")
	Analytics.Track(player, "gift.group_claimed")
	local message = `🎁 Thanks for joining! {got or ""}`
	Net.Notify(player, message, "good")
	return true, message
end

function GiftService.Init()
	Net.Remotes.ClaimGift.OnServerInvoke = claim
	DataService.PlayerLoaded:Connect(function(player: Player, profile: DataService.Profile)
		player:SetAttribute("GiftClaimed", table.find(profile.Claimed, KEY) ~= nil)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastTry[player] = nil
		busy[player] = nil
	end)
end

return GiftService
