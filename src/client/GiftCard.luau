--!strict
-- 🎁 The free gift (PLAN item 22): after a round you won (client/Transitions), once a visit until
-- it's claimed: "Join the group = FREE Speed". JOIN opens Roblox's join prompt, then claims by itself;
-- CLAIM is there for anyone who joined some other way. The server checks the group and pays
-- (server/Services/GiftService).
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)

local player = Players.LocalPlayer
local GiftCard = {}

local frame: Frame? = nil
local shown = false
local waitingForHome = false

local function claim(result: TextLabel)
	local ok, worked, message =
		pcall(ReplicatedStorage.Remotes.ClaimGift.InvokeServer, ReplicatedStorage.Remotes.ClaimGift)
	result.Text = if ok and type(message) == "string" then message else "Try again!"
	result.TextColor3 = if ok and worked then Color3.fromRGB(120, 255, 140) else Color3.fromRGB(255, 120, 120)
	if ok and worked then
		task.delay(1.5, function()
			if frame then
				frame.Visible = false
			end
		end)
	end
end

local function build(): Frame
	local card, body = Theme.shell("FreeGift", "Free Gift!", Theme.Gold, "Shop", 440, 760)
	Theme.text(body, "Join our group = FREE 👟 Speed!", {
		Position = UDim2.fromScale(0.04, 0.02),
		Size = UDim2.fromScale(0.92, 0.3),
		MaximumTextSize = 46,
	})
	local result = Theme.text(body, "", {
		Name = "Result",
		Position = UDim2.fromScale(0.04, 0.8),
		Size = UDim2.fromScale(0.92, 0.18),
		MaximumTextSize = 30,
	})
	Theme.button(body, "JOIN", Theme.Green, {
		Name = "Join",
		Position = UDim2.fromScale(0.04, 0.38),
		Size = UDim2.fromScale(0.44, 0.36),
		MaximumTextSize = 52,
	}, function()
		local ok, status = pcall(GroupService.PromptJoinAsync, GroupService, GameConfig.CommunityGroupId)
		if
			ok and (status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember)
		then
			claim(result)
		elseif ok and status == Enum.GroupMembershipStatus.JoinRequestPending then
			result.Text = "Join request sent!"
		end
	end)
	Theme.button(body, "CLAIM", Theme.Gold, {
		Name = "Claim",
		Position = UDim2.fromScale(0.52, 0.38),
		Size = UDim2.fromScale(0.44, 0.36),
		MaximumTextSize = 52,
	}, function()
		claim(result)
	end)
	return card
end

-- Show it (once a visit, never in a round, never once claimed)
function GiftCard.Offer()
	if shown or player:GetAttribute("GiftClaimed") then
		return
	end
	if player:GetAttribute("InRound") then
		-- (the win card shows while still on the round map: wait until they're home)
		if waitingForHome then
			return
		end
		waitingForHome = true
		local waiting: RBXScriptConnection? = nil
		waiting = player:GetAttributeChangedSignal("InRound"):Connect(function()
			if not player:GetAttribute("InRound") and waiting then
				waiting:Disconnect()
				waitingForHome = false
				task.delay(3, GiftCard.Offer)
			end
		end)
		return
	end
	shown = true
	frame = frame or build()
	if frame then
		Ui.Menu.Close()
		frame.Visible = true
	end
end

return GiftCard
