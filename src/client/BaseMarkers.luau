--!strict
-- Which vault is whose, Tsunami / Steal a Brainrot style: every vault has its owner's face (their avatar
-- headshot) with their name under it, standing low in the entrance like a doorman. All 16 vaults looked
-- the same before ("VAULT"), and new players couldn't find theirs - your own face says "that's mine".
-- Reads the gate's Owner / OwnerName (server BaseService, tag VaultGate). Sized in studs, so it gets
-- smaller with distance like the shop titles, never huge from far away.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local BaseMarkers = {}

local faces: { [number]: string } = {} -- userId -> headshot (one fetch per player)

local function headshot(userId: number): string?
	if faces[userId] then
		return faces[userId]
	end
	local ok, image = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	if ok and image then
		faces[userId] = image
		return image
	end
	return nil
end

local function track(gate: Instance)
	if not gate:IsA("BasePart") or gate:FindFirstChild("OwnerFace") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "OwnerFace"
	gui.Size = UDim2.fromScale(8, 5.4) -- (studs: a head-sized face + its name)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.9 - gate.Size.Y / 2, 0) -- (stands on the floor in the doorway)
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	gui.Adornee = gate
	gui.Enabled = false

	local face = Instance.new("ImageLabel")
	face.AnchorPoint = Vector2.new(0.5, 0)
	face.Position = UDim2.fromScale(0.5, 0)
	face.Size = UDim2.fromScale(0.72, 0.72)
	face.SizeConstraint = Enum.SizeConstraint.RelativeYY
	face.BackgroundTransparency = 1
	face.ScaleType = Enum.ScaleType.Fit
	face.Parent = gui

	local name = Instance.new("TextLabel")
	name.Position = UDim2.fromScale(0, 0.7)
	name.Size = UDim2.fromScale(1, 0.3)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.Text = ""
	name.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(20, 20, 40)
	stroke.Parent = name

	local shown = 0
	local function refresh()
		local owner = gate:GetAttribute("Owner")
		local ownerName = gate:GetAttribute("OwnerName")
		if type(owner) ~= "number" or type(ownerName) ~= "string" then
			gui.Enabled = false
			return
		end
		gui.Enabled = true
		local mine = owner == player.UserId
		name.Text = if mine then "YOU" else ownerName
		name.TextColor3 = if mine then Color3.fromRGB(255, 225, 90) else Color3.new(1, 1, 1)
		if shown ~= owner then
			shown = owner
			face.Image = ""
			task.spawn(function()
				local image = headshot(owner)
				if image and shown == owner then
					face.Image = image
				end
			end)
		end
	end
	gate:GetAttributeChangedSignal("Owner"):Connect(refresh)
	gate:GetAttributeChangedSignal("OwnerName"):Connect(refresh)
	refresh()
	gui.Parent = gate
end

function BaseMarkers.Init()
	for _, gate in CollectionService:GetTagged("VaultGate") do
		track(gate)
	end
	CollectionService:GetInstanceAddedSignal("VaultGate"):Connect(track)
end

return BaseMarkers
