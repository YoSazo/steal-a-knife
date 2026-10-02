--!strict
-- How much money everyone has, floating over their head in the hub (Tsunami style). Drawn on each
-- client from the player's Cash attribute; hidden in rounds so it can't give a disguise away.

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
	gui.Size = UDim2.fromOffset(160, 34)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.Adornee = head
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
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
		gui.Enabled = not owner:GetAttribute("InRound")
	end
	refresh()
	local connections = {
		owner:GetAttributeChangedSignal("Cash"):Connect(refresh),
		owner:GetAttributeChangedSignal("InRound"):Connect(refresh),
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
end

return Overheads
