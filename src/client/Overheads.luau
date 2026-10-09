--!strict
-- How much money everyone has, floating over their head (Tsunami style), with a gold "VIP" above it
-- for VIP pass owners. One tag, so the two never overlap. Hidden during murder rounds. Drawn on each client from the player's Cash and Pass_VIP attributes - and on round
-- bots from FakeCash / FakeVIP (RoundService), so a tag never tells a real player from a bot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local Ui = require(script.Parent.Ui)

local Overheads = {}

-- owner: the Player (Cash, Pass_VIP) or a round bot's model (FakeCash, FakeVIP)
local function attach(owner: Instance, character: Model)
	local cashKey = if owner:IsA("Player") then "Cash" else "FakeCash"
	local vipKey = if owner:IsA("Player") then "Pass_VIP" else "FakeVIP"
	local head = character:WaitForChild("Head", 10) :: BasePart?
	if not head or not character.Parent then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "CashTag"
	gui:SetAttribute("LabelCategory", "Utility")
	gui:SetAttribute("Lines", 2)
	gui:AddTag("ResponsiveWorldLabel")
	gui.Size = UDim2.fromScale(4.6, 1.85) -- (studs: shrinks with distance)
	gui.StudsOffset = Vector3.new(0, 2.9, 0)
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.Adornee = head
	-- Your own tag isn't drawn on a phone: the camera sits close behind you there and it landed right
	-- behind the timer lines (checked on an iPhone 13). Your cash is in the corner anyway; everyone
	-- else still sees your tag.
	gui.Enabled = not (owner == Players.LocalPlayer and Ui.Phone)
	-- VIP on top, cash underneath (close to the head)
	local vip = Instance.new("TextLabel")
	vip.Size = UDim2.fromScale(1, 0.45)
	vip.BackgroundTransparency = 1
	vip.Font = Enum.Font.FredokaOne
	vip.TextScaled = true
	vip.Text = "👑 VIP"
	vip.TextColor3 = Color3.fromRGB(255, 205, 60)
	vip.Parent = gui
	local vipStroke = Instance.new("UIStroke")
	vipStroke.Thickness = 2.5
	vipStroke.Color = Color3.fromRGB(70, 45, 0)
	vipStroke.Parent = vip
	local text = Instance.new("TextLabel")
	text.AnchorPoint = Vector2.new(0, 1)
	text.Position = UDim2.fromScale(0, 1)
	text.Size = UDim2.fromScale(1, 0.53)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(110, 255, 110)
	text.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(15, 60, 20)
	stroke.Parent = text
	local function refresh()
		gui.Enabled = ReplicatedStorage:GetAttribute("Phase") ~= "Round"
			and not (owner == Players.LocalPlayer and Ui.Phone)
		-- (a shape-shifted Murderer shows their new person's money: DisguiseCash / DisguiseVIP)
		local fake = owner:GetAttribute("DisguiseCash")
		local cash = (if type(fake) == "number" then fake else owner:GetAttribute(cashKey) or 0) :: number
		text.Text = `${Format.Short(cash)}`
		vip.Visible = if type(fake) == "number"
			then owner:GetAttribute("DisguiseVIP") == true
			else owner:GetAttribute(vipKey) == true
	end
	refresh()
	local connections = {
		ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(refresh),
		owner:GetAttributeChangedSignal(cashKey):Connect(refresh),
		owner:GetAttributeChangedSignal(vipKey):Connect(refresh),
		owner:GetAttributeChangedSignal("DisguiseCash"):Connect(refresh),
	}
	gui.Destroying:Connect(function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end)
	gui.Parent = head
end

local function track(owner: Player)
	owner.CharacterAdded:Connect(function(character)
		attach(owner, character)
	end)
	if owner.Character then
		task.spawn(attach, owner, owner.Character)
	end
end

function Overheads.Init()
	for _, owner in Players:GetPlayers() do
		track(owner)
	end
	Players.PlayerAdded:Connect(track)
	-- Round disguises rebuild the head (and the tag with it) without a new character: put the tag
	-- back on whoever's missing one. Round bots (workspace.RoundBots) get theirs here too.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, owner in Players:GetPlayers() do
				local character = owner.Character
				local head = character and character:FindFirstChild("Head")
				if head and not head:FindFirstChild("CashTag") then
					task.spawn(attach, owner, character :: Model)
				end
			end
			local bots = workspace:FindFirstChild("RoundBots")
			for _, bot in if bots then bots:GetChildren() else {} do
				local head = bot:FindFirstChild("Head")
				if
					bot:IsA("Model")
					and head
					and bot:GetAttribute("FakeCash")
					and not head:FindFirstChild("CashTag")
				then
					task.spawn(attach, bot, bot)
				end
			end
		end
	end)
end

return Overheads
