--!strict
-- Playing together, kept simple:
--   👥 Friends bonus: every friend (or your teammate) in the server = +10% cash and power luck,
--      up to +30%. Player attribute FriendsHere (0-3). The Invite button is on the client.
--   🤝 Team up: pick one other player as your teammate (invite -> accept). Teammates see each other
--      outlined, share team-steal credit, count as a friend for the bonus, and in Double Trouble
--      rounds they're picked together: both Murderers, or both Sheriffs. Player attribute Partner
--      (the other's UserId). Remote TeamUp: ("Invite", userId) / ("Accept", userId) /
--      ("Decline", userId) / ("Leave").

local Players = game:GetService("Players")

local Net = require(script.Parent.Parent.Remotes)

local Social = {}

local friendCache: { [string]: boolean } = {}
local invites: { [Player]: { [number]: number } } = {} -- target -> inviter UserId -> when
local lastRequest: { [Player]: number } = {}

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

function Social.PartnerOf(player: Player): Player?
	local id = player:GetAttribute("Partner")
	if type(id) ~= "number" then
		return nil
	end
	local other = Players:GetPlayerByUserId(id)
	if other and other:GetAttribute("Partner") == player.UserId then
		return other
	end
	return nil
end

local function refreshFriends()
	local all = Players:GetPlayers()
	for _, player in all do
		local count = 0
		for _, other in all do
			if other ~= player and (areFriends(player, other) or Social.PartnerOf(player) == other) then
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

local function setPartner(a: Player, b: Player?)
	local old = Social.PartnerOf(a)
	if old then
		old:SetAttribute("Partner", nil)
		Net.Notify(old, `{a.DisplayName} left your team.`, "info")
	end
	a:SetAttribute("Partner", if b then b.UserId else nil)
	if b then
		local theirs = Social.PartnerOf(b)
		if theirs and theirs ~= a then
			theirs:SetAttribute("Partner", nil)
		end
		b:SetAttribute("Partner", a.UserId)
	end
	refreshFriends()
end

local function onTeamUp(player: Player, action: unknown, userId: unknown)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < 0.5 then
		return
	end
	lastRequest[player] = now
	if action == "Leave" then
		if Social.PartnerOf(player) then
			setPartner(player, nil)
			Net.Notify(player, "You left your team.", "info")
		end
		return
	end
	if type(userId) ~= "number" then
		return
	end
	local other = Players:GetPlayerByUserId(userId)
	if not other or other == player then
		return
	end
	if action == "Invite" then
		local pending = invites[other] or {}
		pending[player.UserId] = now
		invites[other] = pending
		Net.Remotes.Effect:FireClient(other, "TeamInvite", player.UserId, player.DisplayName)
		Net.Notify(player, `Team invite sent to {other.DisplayName}!`, "info")
	elseif action == "Accept" then
		local mine = invites[player]
		local sent = mine and mine[other.UserId]
		if not sent or now - sent > 60 then
			Net.Notify(player, "That invite expired.", "bad")
			return
		end
		if mine then
			mine[other.UserId] = nil
		end
		setPartner(player, other)
		Net.Notify(player, `🤝 You teamed up with {other.DisplayName}!`, "good")
		Net.Notify(other, `🤝 {player.DisplayName} teamed up with you!`, "good")
	elseif action == "Decline" then
		local mine = invites[player]
		if mine then
			mine[other.UserId] = nil
		end
		Net.Notify(other, `{player.DisplayName} said no thanks.`, "info")
	end
end

function Social.Init()
	Net.Remotes.TeamUp.OnServerEvent:Connect(onTeamUp)
	Players.PlayerAdded:Connect(function()
		task.defer(refreshFriends)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local partner = Social.PartnerOf(player)
		if partner then
			partner:SetAttribute("Partner", nil)
			Net.Notify(partner, `{player.DisplayName} left, so your team ended.`, "info")
		end
		invites[player] = nil
		lastRequest[player] = nil
		task.defer(refreshFriends)
	end)
	refreshFriends()
end

return Social
