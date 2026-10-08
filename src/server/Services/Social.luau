--!strict
-- 👥 Friends bonus: every friend in the server = +10% cash, up to +30% (player attribute
-- FriendsHere 0-3). The Invite tile is in the More menu. (Team-up and trading were cut: almost
-- nobody used them, 2026-10.)

local Players = game:GetService("Players")

local Social = {}

local friendCache: { [string]: boolean } = {}

local function pairKey(a: Player, b: Player): string
	return if a.UserId < b.UserId then `{a.UserId}:{b.UserId}` else `{b.UserId}:{a.UserId}`
end

local function areFriends(a: Player, b: Player): boolean
	local key = pairKey(a, b)
	local cached = friendCache[key]
	if cached == nil then
		local ok, result = pcall(a.IsFriendsWithAsync, a, b.UserId)
		cached = ok and result == true
		friendCache[key] = cached
	end
	return cached :: boolean
end

local function refreshFriends()
	local all = Players:GetPlayers()
	for _, player in all do
		local count = 0
		for _, other in all do
			if other ~= player and areFriends(player, other) then
				count += 1
			end
		end
		player:SetAttribute("FriendsHere", math.min(count, 3))
	end
end

-- +10% per friend here (max 3)
function Social.FriendsMultiplier(player: Player): number
	return 1 + ((player:GetAttribute("FriendsHere") or 0) :: number) * 0.1
end

function Social.Init()
	Players.PlayerAdded:Connect(function()
		task.defer(refreshFriends)
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(refreshFriends)
	end)
	refreshFriends()
end

return Social
