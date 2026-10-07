--!strict
-- PROTOTYPE (Studio only, ReplicatedStorage attribute DebugPens = true): one Steal an Egg-style pen
-- away from the hub, to judge the look before the real switch from vaults to pens. A flat grass
-- pen inside a low orange X-rail fence with dark posts and a gate gap; Codex's knife characters
-- (Assets/KnifeCharacterAssets) hop around inside at their rarity's size (client/PenKnives, maths in
-- Shared/PenHop), with two coffins waiting. Nothing here touches live play.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Toy = require(ReplicatedStorage.Shared.Toy)

local PenPrototype = {}

local CENTRE = Vector3.new(-700, 0, 0) -- its own patch of ground, far from the hub
local HALF = Vector2.new(34, 34) -- a 68 x 68 pen (a vault is 40 x 44 today)
local RAIL = Color3.fromRGB(196, 96, 42)
local POST = Color3.fromRGB(62, 55, 70)

-- Rarity -> how big the character is drawn (x its 2.4-stud base): value you can see from afar
local SCALE =
	{ Common = 2.2, Rare = 2.8, Epic = 3.5, Legendary = 4.4, Mythic = 5.5, Godly = 6.6, Celestial = 7.8, Cosmic = 9 }

local function block(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- One fence section from a to b (floor points): rails top and bottom + an X, posts at the ends
local function fence(parent: Instance, a: Vector3, b: Vector3)
	local length = (b - a).Magnitude
	local mid = (a + b) / 2
	local along = CFrame.lookAt(mid, b)
	local h = 3.2
	for _, y in { 0.7, h - 0.35 } do
		local rail = block(parent, "Rail", Vector3.new(0.45, 0.45, length), along + Vector3.new(0, y, 0), RAIL)
		Toy.Dress(rail, { Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top }, 1)
	end
	-- the X: two diagonals between the rails
	local span = h - 1.05
	local diag = math.sqrt(length * length + span * span)
	local tilt = math.atan2(span, length)
	for _, sign in { 1, -1 } do
		local d = block(
			parent,
			"Cross",
			Vector3.new(0.35, 0.35, diag),
			along * CFrame.new(0, 0.7 + span / 2, 0) * CFrame.Angles(sign * tilt, 0, 0),
			RAIL
		)
		Toy.Dress(d, { Enum.NormalId.Left, Enum.NormalId.Right }, 1)
	end
	local post =
		block(parent, "Post", Vector3.new(0.9, h + 0.4, 0.9), CFrame.new(a + Vector3.new(0, (h + 0.4) / 2, 0)), POST)
	Toy.Dress(post, nil, 1)
end

function PenPrototype.Build()
	local old = workspace:FindFirstChild("PenPrototype")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "PenPrototype"
	folder.Parent = workspace
	-- ground: a big grass island, the pen in the middle
	local ground = block(
		folder,
		"Ground",
		Vector3.new(HALF.X * 2 + 60, 4, HALF.Y * 2 + 60),
		CFrame.new(CENTRE - Vector3.new(0, 2, 0)),
		Toy.Grass
	)
	Toy.Dress(ground, { Enum.NormalId.Top }, 2, 8)
	-- the fence all round, 8-stud sections, a gate gap in the middle of the front (+Z) side
	local hx, hz = HALF.X, HALF.Y
	local corners = {
		Vector3.new(-hx, 0, -hz),
		Vector3.new(hx, 0, -hz),
		Vector3.new(hx, 0, hz),
		Vector3.new(-hx, 0, hz),
	}
	for side = 1, 4 do
		local a, b = corners[side], corners[side % 4 + 1]
		local length = (b - a).Magnitude
		local pieces = math.floor(length / 8 + 0.5)
		for i = 0, pieces - 1 do
			local from = a:Lerp(b, i / pieces)
			local to = a:Lerp(b, (i + 1) / pieces)
			-- (the gate: leave the two middle sections of the front open)
			local isGate = side == 3 and (i == pieces // 2 or i == pieces // 2 - 1)
			if not isGate then
				fence(folder, CENTRE + from, CENTRE + to)
			end
		end
	end
	-- the characters, hopping (client/PenKnives reads the pen + seed + scale)
	local Assets = require(ReplicatedStorage.Shared.Assets.KnifeCharacterAssets)
	local Characters = require(ReplicatedStorage.Shared.Config.KnifeCharacters)
	local seed = 1
	for name, info in Characters :: { [string]: any } do
		local scale = SCALE[info.Rarity] or 3
		local model = Assets.BuildCharacter(name, folder, CFrame.new(CENTRE), { Scale = scale })
		model:SetAttribute("PenCentre", CENTRE)
		model:SetAttribute("PenHalf", Vector3.new(HALF.X, 0, HALF.Y))
		model:SetAttribute("HopSeed", seed * 101)
		model:SetAttribute("HopScale", scale)
		model:AddTag("PenKnife")
		model:AddTag("KnifeFace")
		seed += 1
	end
	-- two coffins waiting by the gate
	for i, rarity in { "Common", "Cosmic" } do
		local ok, coffin = pcall(
			Assets.BuildCoffin,
			rarity,
			folder,
			CFrame.new(CENTRE + Vector3.new(i == 1 and -14 or 12, 0, hz - 12))
		)
		if ok and coffin then
			coffin:AddTag("PenCoffin")
		end
	end
	return folder
end

function PenPrototype.Init()
	if not RunService:IsStudio() then
		return
	end
	local function check()
		if ReplicatedStorage:GetAttribute("DebugPens") == true then
			PenPrototype.Build()
		end
	end
	ReplicatedStorage:GetAttributeChangedSignal("DebugPens"):Connect(check)
	check()
end

PenPrototype.Centre = CENTRE
return PenPrototype
