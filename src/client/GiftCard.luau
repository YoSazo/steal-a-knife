--!strict
-- A hub chest opens the same gift card offered after the first win. The server grants once.
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local Favorite = require(script.Parent.Favorite)
local player = Players.LocalPlayer
local GiftCard = {}
local frame: Frame? = nil
local shown = false
local refreshCard: (() -> ())? = nil
local function busy(): boolean
	return player:GetAttribute("InRound") == true
		or player:GetAttribute("Carrying") ~= nil
		or player:GetAttribute("RunSaved") == true
end

local function build(): Frame
	local card, body = Theme.shell("FreeGift", "FREE GIFT!", Theme.Purple, "Gift", 530, 900)
	Ui.new("ImageLabel", {
		Name = "SpeedBag",
		Image = "rbxassetid://74015651442016",
		Position = UDim2.fromScale(0.03, 0.015),
		Size = UDim2.fromScale(0.30, 0.35),
		ScaleType = Enum.ScaleType.Fit,
		BackgroundTransparency = 1,
		ZIndex = 8,
	}, body)
	local amount = Theme.text(body, "", {
		Name = "Reward",
		Position = UDim2.fromScale(0.34, 0.05),
		Size = UDim2.fromScale(0.62, 0.18),
		MaximumTextSize = 48,
		TextColor3 = Theme.Cyan,
	})
	local condition = Theme.text(body, "", {
		Name = "Requirement",
		Position = UDim2.fromScale(0.34, 0.24),
		Size = UDim2.fromScale(0.62, 0.10),
		MaximumTextSize = 26,
	})
	local result = Theme.text(body, "", {
		Name = "Result",
		Position = UDim2.fromScale(0.02, 0.72),
		Size = UDim2.fromScale(0.96, 0.09),
		MaximumTextSize = 24,
		TextWrapped = true,
	})
	local likeHelp = Ui.new("Frame", {
		Name = "LikeInstructions",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 20,
		Visible = false,
		Active = true,
	}, body) :: Frame
	Theme.text(likeHelp, "Tap 👍 under Play!", {
		Position = UDim2.fromScale(0.05, 0.03),
		Size = UDim2.fromScale(0.9, 0.17),
		MaximumTextSize = 40,
		TextColor3 = Theme.Cyan,
		ZIndex = 21,
	})
	Ui.new("ImageLabel", {
		Name = "ExactScreenshot",
		Image = "rbxassetid://109848101855793",
		Position = UDim2.fromScale(0.05, 0.23),
		Size = UDim2.fromScale(0.9, 0.54),
		ScaleType = Enum.ScaleType.Fit,
		BackgroundTransparency = 1,
		ZIndex = 21,
	}, likeHelp)
	Theme.button(
		likeHelp,
		"BACK",
		Theme.Cyan,
		{ Position = UDim2.fromScale(0.3, 0.82), Size = UDim2.fromScale(0.4, 0.15), MaximumTextSize = 40, ZIndex = 21 },
		function()
			likeHelp.Visible = false
		end
	)
	local headings = { "Like the game!", "Favorite the game!", "Join our community!" }
	local colors = { Theme.Cyan, Theme.Purple, Theme.Green }
	local join: TextButton? = nil
	for i = 1, 3 do
		local step = Theme.surface(body, {
			Name = `Step{i}`,
			Position = UDim2.fromScale(0.02 + (i - 1) * 0.33, 0.39),
			Size = UDim2.fromScale(0.30, 0.30),
			ZIndex = 7,
		}, colors[i]:Lerp(Color3.new(1, 1, 1), 0.7))
		Theme.text(step, headings[i], {
			Position = UDim2.fromScale(0.03, 0.03),
			Size = UDim2.fromScale(0.94, 0.38),
			MaximumTextSize = 27,
			TextWrapped = true,
		})
		local button = Theme.button(step, ({ "👍 HOW TO LIKE", "⭐ FAVORITE", "JOIN" })[i], colors[i], {
			Name = ({ "LikeHelp", "Favorite", "Join" })[i],
			Position = UDim2.fromScale(0.04, 0.47),
			Size = UDim2.fromScale(0.92, 0.47),
			MaximumTextSize = 28,
		}, function()
			if i == 1 then
				likeHelp.Visible = true
			elseif i == 2 then
				result.Text = "Tap Favorite in the Roblox pop-up!"
				Favorite.Ask("gift_card", function()
					result.Text = if player:GetAttribute("FavoriteConfirmed")
						then "⭐ Favorited!"
						else "You can favorite on our Roblox page too."
				end, true)
			else
				local ok, status = pcall(GroupService.PromptJoinAsync, GroupService, GameConfig.CommunityGroupId)
				if
					ok
					and (
						status == Enum.GroupMembershipStatus.Joined
						or status == Enum.GroupMembershipStatus.AlreadyMember
					)
				then
					result.Text = "Joined! Tap CLAIM!"
					if join then
						(join:FindFirstChild("Label") :: TextLabel).Text = "✓ JOINED"
					end
				elseif ok and status == Enum.GroupMembershipStatus.JoinRequestPending then
					result.Text = "Join request sent!"
				else
					result.Text = "Join our community on Roblox, then tap CLAIM."
				end
			end
		end)
		if i == 3 then
			join = button
		end
	end
	local claim = Theme.button(body, "CLAIM", Theme.Green, {
		Name = "Claim",
		Position = UDim2.fromScale(0.27, 0.83),
		Size = UDim2.fromScale(0.46, 0.16),
		MaximumTextSize = 44,
	}, function()
		local ok, worked, message =
			pcall(ReplicatedStorage.Remotes.ClaimGift.InvokeServer, ReplicatedStorage.Remotes.ClaimGift)
		result.Text = if ok and type(message) == "string" then message else "Try again!"
		result.TextColor3 = if ok and worked then Color3.fromRGB(120, 255, 140) else Color3.fromRGB(255, 120, 120)
		if ok and worked then
			task.delay(1.5, function()
				card.Visible = false
			end)
		end
	end)
	refreshCard = function()
		local claimed = player:GetAttribute("GiftClaimed") == true
		amount.Text = if claimed
			then "GIFT CLAIMED!"
			else `+{Ui.abbreviate((player:GetAttribute("GiftSpeed") or 0) :: number)} SPEED!`
		condition.Text = if ((player:GetAttribute("Wins") or 0) :: number) < 1
			then "Win 1 round, then join to claim!"
			else "Join our community to claim!"
		Theme.enabled(
			claim,
			not claimed and ((player:GetAttribute("Wins") or 0) :: number) >= 1,
			if claimed then "CLAIMED" else "CLAIM"
		)
	end
	for _, attribute in { "GiftSpeed", "GiftClaimed", "Wins" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshCard :: () -> ())
	end
	(refreshCard :: () -> ())()
	return card
end

function GiftCard.Open()
	if busy() then
		if Ui.Toast then
			Ui.Toast("Get your coffin home first!", "info")
		end
		return
	end
	frame = frame or build()
	Ui.Menu.Close()
	local opened = frame :: Frame
	opened.Visible = true
	if refreshCard then
		refreshCard()
	end
end
function GiftCard.Offer()
	if shown or player:GetAttribute("GiftClaimed") or busy() then
		return
	end
	shown = true
	GiftCard.Open()
end
function GiftCard.Init()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if prompt.Name == "CommunityGiftPrompt" and who == player then
			GiftCard.Open()
		end
	end)
	player:GetAttributeChangedSignal("InRound"):Connect(function()
		if player:GetAttribute("InRound") and frame then
			frame.Visible = false
		end
	end)
	task.spawn(function()
		local map = workspace:WaitForChild("Map")
		local chest = map:WaitForChild("CommunityGiftChest", 30)
		if not chest then
			return
		end
		local function refreshChest()
			local label = chest:FindFirstChild("FreeGiftLabel", true)
			if label and label:IsA("BillboardGui") then
				label.Enabled = player:GetAttribute("GiftClaimed") ~= true
			end
		end
		player:GetAttributeChangedSignal("GiftClaimed"):Connect(refreshChest)
		refreshChest()
	end)
end
return GiftCard
