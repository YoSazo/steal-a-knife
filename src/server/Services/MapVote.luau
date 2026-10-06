--!strict
-- Vote for the next murder map. At the back of the plaza, one board per map (its emoji, name and
-- size) with a glowing pad in front of it: stand on a pad and your vote goes to that map. The
-- vote card (client MapVoteCard) does the same with a tap (Remotes.MapVote). The count floats
-- over each board. When the round starts the map with the most votes is built (a tie: one of
-- them at random; no votes: any map), and the votes start over.
--
-- State for clients: ReplicatedStorage MapVotes ("Office=2;Mansion=1"), player MapVote (their pick).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoundMapInfo = require(ReplicatedStorage.Shared.Config.RoundMapInfo)
local Net = require(script.Parent.Parent.Remotes)
local Analytics = require(script.Parent.Analytics)

local MapVote = {}

local ROW_Z = -205 -- where the knife monument used to stand
local SPACING = 26
local PAD_RADIUS = 6.5

local votes: { [Player]: string } = {}
local labels: { [string]: TextLabel } = {}
local pads: { [string]: Vector3 } = {}
local rng = Random.new()

local function counts(): { [string]: number }
	local out = {}
	for _, info in RoundMapInfo.List do
		out[info.Name] = 0
	end
	for player, name in votes do
		if player.Parent and out[name] then
			out[name] += 1
		end
	end
	return out
end

local function publish()
	local tally = counts()
	local parts = {}
	for _, info in RoundMapInfo.List do
		local n = tally[info.Name]
		table.insert(parts, `{info.Name}={n}`)
		local label = labels[info.Name]
		if label then
			label.Text = `Votes: {n}`
		end
	end
	ReplicatedStorage:SetAttribute("MapVotes", table.concat(parts, ";"))
end

local function cast(player: Player, name: unknown, how: string)
	if type(name) ~= "string" or not RoundMapInfo.ByName[name] or player:GetAttribute("InRound") then
		return
	end
	if votes[player] == name then
		return
	end
	votes[player] = name
	player:SetAttribute("MapVote", name)
	publish()
	Net.Remotes.Effect:FireClient(player, "MapVoted", name)
	Analytics.Track(player, "map.vote", { map = name, how = how })
end

-- The map the next round is built on (nil = any), and a fresh vote for the one after
function MapVote.TakeWinner(): string?
	local tally = counts()
	local best, top = {}, 0
	for _, info in RoundMapInfo.List do
		local n = tally[info.Name]
		if n > top then
			best, top = { info.Name }, n
		elseif n == top and n > 0 then
			table.insert(best, info.Name)
		end
	end
	table.clear(votes)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("MapVote", nil)
	end
	publish()
	return if #best > 0 then best[rng:NextInteger(1, #best)] else nil
end

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	for key, value in props do
		(label :: any)[key] = value
	end
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(20, 20, 40)
	stroke.Parent = label
	label.Parent = parent
	return label
end

local function buildBoards()
	local folder = Instance.new("Folder")
	folder.Name = "MapVote"
	local n = #RoundMapInfo.List
	for i, info in RoundMapInfo.List do
		local x = (i - (n + 1) / 2) * SPACING
		local model = Instance.new("Model")
		model.Name = `Vote_{info.Name}`
		-- MM2's vote frames: a wooden frame with a real shot of the map, its name across the picture,
		-- and a black plate under it with the name and the votes. On two posts, facing down the plaza.
		local wood = Color3.fromRGB(112, 74, 46)
		local boardAt = CFrame.lookAt(Vector3.new(x, 11, ROW_Z), Vector3.new(x, 11, ROW_Z + 10))
		for _, side in { -1, 1 } do
			part(
				"Post",
				Vector3.new(1.4, 20, 1.4),
				CFrame.new(x + side * 8.6, 10, ROW_Z - 0.4),
				wood,
				Enum.Material.Wood
			).Parent =
				model
		end
		part("Frame", Vector3.new(17.6, 19, 1.2), boardAt, wood, Enum.Material.Wood).Parent = model
		local board = part("Board", Vector3.new(16, 17.4, 1.4), boardAt, Color3.fromRGB(16, 22, 30))
		board.Parent = model
		local surface = Instance.new("SurfaceGui")
		surface.Face = Enum.NormalId.Front
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 40
		surface.LightInfluence = 0
		surface.Parent = board
		-- the picture (16 x 12.6 studs: the shot's own shape)
		local picture = Instance.new("ImageLabel")
		picture.BackgroundColor3 = Color3.new(0, 0, 0)
		picture.BorderSizePixel = 0
		picture.Position = UDim2.fromScale(0.04, 0.03)
		picture.Size = UDim2.fromScale(0.92, 0.7)
		picture.Image = info.Image
		picture.ScaleType = Enum.ScaleType.Crop
		picture.Parent = surface
		text(picture, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.fromScale(0.9, 0.24),
			Text = info.Name:upper(),
			TextColor3 = info.Color:Lerp(Color3.new(1, 1, 1), 0.25),
		})
		-- the plate: name and votes
		text(surface, {
			Position = UDim2.fromScale(0.05, 0.75),
			Size = UDim2.fromScale(0.9, 0.12),
			Text = info.Name,
		})
		labels[info.Name] = text(surface, {
			Position = UDim2.fromScale(0.05, 0.87),
			Size = UDim2.fromScale(0.9, 0.1),
			Text = "Votes: 0",
			TextColor3 = Color3.fromRGB(190, 195, 205),
		})
		-- "VOTE" floating over it, like the shopkeepers' names
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(200, 50)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 12, 0)
		billboard.MaxDistance = 220
		billboard.LightInfluence = 0
		billboard.Adornee = board
		billboard.Parent = board
		text(billboard, { Size = UDim2.fromScale(1, 1), Text = "VOTE", TextColor3 = Color3.fromRGB(255, 225, 90) })
		-- the pad: a glowing disc on the ground in front of the board
		local padAt = Vector3.new(x, 0, ROW_Z + 11)
		local pad = part(
			"Pad",
			Vector3.new(0.3, PAD_RADIUS * 2, PAD_RADIUS * 2),
			CFrame.new(padAt + Vector3.new(0, 0.32, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			info.Color,
			Enum.Material.Neon
		)
		pad.Shape = Enum.PartType.Cylinder
		pad.Transparency = 0.25
		pad.CanCollide = false
		pad.CanQuery = false
		pad.Parent = model
		local ring = part(
			"PadRing",
			Vector3.new(0.12, PAD_RADIUS * 2 + 1.2, PAD_RADIUS * 2 + 1.2),
			CFrame.new(padAt + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.new(1, 1, 1),
			Enum.Material.Neon
		)
		ring.Shape = Enum.PartType.Cylinder
		ring.CanCollide = false
		ring.CanQuery = false
		ring.Parent = model
		pads[info.Name] = padAt
		model.Parent = folder
	end
	folder.Parent = workspace:FindFirstChild("Map") or workspace
end

function MapVote.Init()
	buildBoards()
	publish()
	Net.Remotes.MapVote.OnServerEvent:Connect(function(player: Player, name: unknown)
		cast(player, name, "card")
	end)
	Players.PlayerRemoving:Connect(function(player)
		if votes[player] then
			votes[player] = nil
			publish()
		end
	end)
	-- standing on a pad
	task.spawn(function()
		while true do
			task.wait(0.3)
			for _, player in Players:GetPlayers() do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					for name, at in pads do
						local flat = Vector3.new(root.Position.X - at.X, 0, root.Position.Z - at.Z)
						if flat.Magnitude <= PAD_RADIUS and math.abs(root.Position.Y - at.Y) < 8 then
							cast(player, name, "pad")
						end
					end
				end
			end
		end
	end)
end

return MapVote
