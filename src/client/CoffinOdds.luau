--!strict
-- "Is that rare? like %?" (a kid, about his Mythic coffin): walk up to any coffin - in a boss's
-- graveyard or in a pen - and a small card shows what could be inside and the chance of each,
-- Steal an Egg's egg odds. Every coffin holds one knife of its rarity, each equally likely
-- (Items.RollKnife), plus the rarity's place on the ladder ("5th rarest of 8"). Server tags the
-- coffins "CoffinOdds" (attribute Rarity).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local KnifeIcons = require(ReplicatedStorage.Shared.Config.KnifeIcons)

local player = Players.LocalPlayer
local CoffinOdds = {}

local RANGE = 16 -- studs: close enough to be looking at it
local ROW = 30

local cards: { [Model]: BillboardGui } = {}

local function build(model: Model): BillboardGui?
	local rarity = model:GetAttribute("Rarity")
	local pool = if type(rarity) == "string" then Knives.ByRarity[rarity] else nil
	local anchor = model.PrimaryPart
	if not pool or not anchor then
		return nil
	end
	local color = Knives.RarityColors[rarity :: string] or Color3.new(1, 1, 1)
	local rank = table.find(Knives.Rarities, rarity :: string) or 1
	local _, size = model:GetBoundingBox()
	local gui = Instance.new("BillboardGui")
	gui.Name = "CoffinOdds"
	gui.Size = UDim2.fromOffset(190, 44 + #pool * ROW)
	gui.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 4.5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Enabled = false
	gui.Adornee = anchor
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(24, 18, 40)
	frame.BackgroundTransparency = 0.15
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Parent = frame
	local function text(
		y: number,
		height: number,
		value: string,
		tint: Color3,
		x: number?,
		width: number?,
		right: boolean?
	)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(x or 8, y)
		label.Size = UDim2.fromOffset(width or 174, height)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = tint
		label.TextXAlignment = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
		label.Text = value
		local outline = Instance.new("UIStroke")
		outline.Thickness = 1.5
		outline.Color = Color3.fromRGB(10, 8, 20)
		outline.Parent = label
		label.Parent = frame
	end
	text(5, 18, "What's inside?", Color3.new(1, 1, 1))
	text(23, 14, `{rarity} · rarity {rank} of {#Knives.Rarities}`, color)
	local chance = math.floor(100 / #pool + 0.5)
	for i, knife in pool do
		local y = 40 + (i - 1) * ROW
		local icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.Position = UDim2.fromOffset(8, y)
		icon.Size = UDim2.fromOffset(ROW - 4, ROW - 4)
		icon.Image = KnifeIcons[knife.Name] or ""
		icon.Parent = frame
		text(y + 4, ROW - 10, knife.DisplayName or knife.Name, Color3.new(1, 1, 1), 8 + ROW, 104)
		text(y + 4, ROW - 10, `{chance}%`, Color3.fromRGB(120, 255, 140), 140, 42, true)
	end
	gui.Parent = model
	return gui
end

function CoffinOdds.Init()
	local function add(model: Instance)
		if model:IsA("Model") and not cards[model] then
			task.defer(function()
				local gui = build(model)
				if gui then
					cards[model] = gui
				end
			end)
		end
	end
	for _, model in CollectionService:GetTagged("CoffinOdds") do
		add(model)
	end
	CollectionService:GetInstanceAddedSignal("CoffinOdds"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("CoffinOdds"):Connect(function(model)
		cards[model :: Model] = nil
	end)
	-- only the coffin you're standing at shows its card (the closest one)
	local clock = 0
	RunService.Heartbeat:Connect(function(dt)
		clock += dt
		if clock < 0.15 then
			return
		end
		clock = 0
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local closest: BillboardGui? = nil
		local best = RANGE
		for model, gui in cards do
			if not model.Parent then
				cards[model] = nil
				continue
			end
			local anchor = (gui.Adornee :: any) :: BasePart?
			local distance = if root and anchor then (anchor.Position - root.Position).Magnitude else math.huge
			if distance < best then
				closest, best = gui, distance
			end
		end
		for _, gui in cards do
			gui.Enabled = gui == closest and player:GetAttribute("Carrying") == nil
		end
	end)
end

return CoffinOdds
