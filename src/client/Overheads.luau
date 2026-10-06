--!strict
-- How much money everyone has, floating over their head (Tsunami style), with a gold "VIP" above it
-- for VIP pass owners. One tag, so the two never overlap. Shown in rounds too: the rich ones are the
-- juicy targets. Drawn on each client from the player's Cash and Pass_VIP attributes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)

local Overheads = {}

local function attach(owner: Player, character: Model)
	local head = character:WaitForChild("Head", 10) :: BasePart?
	if not head or not character.Parent then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "CashTag"
	gui:SetAttribute("LabelCategory", "Utility")
	gui:SetAttribute("Lines", 2)
	gui:AddTag("ResponsiveWorldLabel")
	gui.Size = UDim2.fromOffset(160, 64)
	gui.StudsOffset = Vector3.new(0, 2.9, 0)
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.Adornee = head
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
		local cash = (owner:GetAttribute("Cash") or 0) :: number
		text.Text = `${Format.Short(cash)}`
		vip.Visible = owner:GetAttribute("Pass_VIP") == true
	end
	refresh()
	local connections = {
		owner:GetAttributeChangedSignal("Cash"):Connect(refresh),
		owner:GetAttributeChangedSignal("Pass_VIP"):Connect(refresh),
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
	-- back on whoever's missing one
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
		end
	end)
end

return Overheads
