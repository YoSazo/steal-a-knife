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

local ToyBlockModel = require(ReplicatedStorage.Shared.ToyBlockModel)
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
		return false, "Join our community first!"
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

local function sync(player: Player)
	local profile = DataService.Get(player)
	if profile then
		player:SetAttribute("GiftClaimed", table.find(profile.Claimed, KEY) ~= nil)
		player:SetAttribute("GiftSpeed", FreeRewards.SpeedShare(profile.Speed, GameConfig.GroupGift.Speed))
	end
end

local function buildChest()
	local chest = ToyBlockModel.Build("FreeChest", true)
	chest.Name = "CommunityGiftChest"
	chest:ScaleTo(3)
	local box, size = chest:GetBoundingBox()
	local bottom = box.Position.Y - size.Y / 2
	chest:PivotTo(CFrame.new(-12, 0.2 - bottom, -72) * CFrame.Angles(0, math.pi, 0))
	for _, part in chest:GetChildren() do
		if part:IsA("BasePart") and part.Name == "Wood" then
			part.Color = Color3.fromRGB(245, 225, 190)
		end
	end
	local root = chest.PrimaryPart :: BasePart
	local gui = Instance.new("BillboardGui")
	gui.Name = "FreeGiftLabel"
	gui.Size = UDim2.fromScale(10, 2.4)
	gui.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 3, 0)
	gui.MaxDistance, gui.LightInfluence = 100, 0
	gui.Parent = root
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundTransparency = 1
	title.Font, title.TextScaled, title.Text = Enum.Font.FredokaOne, true, "FREE!"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 210, 30)),
		ColorSequenceKeypoint.new(0.33, Color3.fromRGB(100, 255, 80)),
		ColorSequenceKeypoint.new(0.66, Color3.fromRGB(50, 220, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 230)),
	})
	gradient.Parent = title
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.Thickness = Color3.fromRGB(20, 15, 30), 3
	stroke.Parent = title
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name, prompt.ActionText, prompt.ObjectText = "CommunityGiftPrompt", "Open", "Free Gift"
	prompt.HoldDuration, prompt.MaxActivationDistance, prompt.RequiresLineOfSight = 0, 12, false
	prompt.Parent = root
	chest.Parent = workspace:FindFirstChild("Map")
end

function GiftService.Init()
	buildChest()
	local function setup(player: Player)
		player:GetAttributeChangedSignal("Speed"):Connect(function()
			sync(player)
		end)
		player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
			sync(player)
		end)
		sync(player)
	end
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerAdded:Connect(setup)
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
