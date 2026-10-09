--!strict
-- A pen's fence (Shared/PenMode): Steal an Egg's low orange X-rail fence with dark posts all round,
-- a gap in the front middle for the gate. An invisible, walk-through
-- "Blocker" across the gate gap marks the pen (tag VaultGate; attributes Owner, Tier, Floors,
-- PenDepth). Built in the pen's frame (local +Z = the gate side).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Toy = require(ReplicatedStorage.Shared.Toy)

local PenWalls = {}

local RAIL = Color3.fromRGB(196, 96, 42)
local POST = Color3.fromRGB(62, 55, 70)
local FENCE_H = 3.4
local GATE_HALF = 8
local GATE_H = 11
local SECTION = 8

export type Built = { Gate: Model, Blocker: Part, Height: number, BackHeight: number }

local function block(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- One section of fence between two floor points: two rails, an X, a post at the start
local function section(parent: Instance, a: Vector3, b: Vector3)
	local length = (b - a).Magnitude
	local along = CFrame.lookAt((a + b) / 2, b)
	for _, y in { 0.75, FENCE_H - 0.4 } do
		local rail = block(parent, "Rail", Vector3.new(0.5, 0.5, length), along + Vector3.new(0, y, 0), RAIL)
		Toy.Dress(rail, { Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top }, 1)
	end
	local span = FENCE_H - 1.15
	local diag = math.sqrt(length * length + span * span)
	local tilt = math.atan2(span, length)
	for _, sign in { 1, -1 } do
		local d = block(
			parent,
			"Cross",
			Vector3.new(0.4, 0.4, diag),
			along * CFrame.new(0, 0.75 + span / 2, 0) * CFrame.Angles(sign * tilt, 0, 0),
			RAIL
		)
		Toy.Dress(d, { Enum.NormalId.Left, Enum.NormalId.Right }, 1)
	end
	local post = block(
		parent,
		"Post",
		Vector3.new(1, FENCE_H + 0.5, 1),
		CFrame.new(a + Vector3.new(0, (FENCE_H + 0.5) / 2, 0)),
		POST
	)
	Toy.Dress(post, nil, 1)
end

-- `depth`: how long the pen is now (PenMode.Depth); the gate side stays where it is and the back
-- fence moves out as the pen grows. `frame` is the full-size pen's centre.
function PenWalls.Build(folder: Folder, frame: CFrame, _color: Color3, tierIndex: number, depth: number?): Built
	folder:ClearAllChildren()
	local length = depth or GameConfig.Pens.Depth
	local hx, hz = GameConfig.Pens.Width / 2, length / 2
	local shift = GameConfig.Pens.Depth / 2 - hz -- (towards the gate side)
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z + shift)
	end
	-- the fence all round, in sections; the front (+Z) leaves the gate gap
	local corners =
		{ Vector3.new(-hx, 0, -hz), Vector3.new(hx, 0, -hz), Vector3.new(hx, 0, hz), Vector3.new(-hx, 0, hz) }
	for side = 1, 4 do
		local a, b = corners[side], corners[side % 4 + 1]
		local sideLength = (b - a).Magnitude
		local pieces = math.max(1, math.floor(sideLength / SECTION + 0.5))
		for i = 0, pieces - 1 do
			local from, to = a:Lerp(b, i / pieces), a:Lerp(b, (i + 1) / pieces)
			if side == 3 then
				-- the front: skip what falls in the gate gap (local X between -GATE_HALF and GATE_HALF)
				local mid = (from + to) / 2
				if math.abs(mid.X) < GATE_HALF then
					continue
				end
			end
			section(folder, at(from.X, 0, from.Z).Position, at(to.X, 0, to.Z).Position)
		end
	end
	-- gate posts, a little taller
	for _, x in { -GATE_HALF, GATE_HALF } do
		local post =
			block(folder, "GatePost", Vector3.new(1.4, FENCE_H + 1.6, 1.4), at(x, (FENCE_H + 1.6) / 2, hz), POST)
		Toy.Dress(post, nil, 1)
	end
	-- (no invisible walls: hop the fence from any side, like Steal an Egg's pens)
	-- the gate: an invisible marker across the gap
	local gate = Instance.new("Model")
	gate.Name = "Gate"
	local blocker = block(gate, "Blocker", Vector3.new(GATE_HALF * 2, GATE_H, 1.2), at(0, GATE_H / 2, hz), Color3.new())
	blocker.Transparency = 1
	blocker.CanCollide = false
	blocker.CanQuery = true
	blocker.CanTouch = false
	blocker:AddTag("VaultGate")
	gate.PrimaryPart = blocker
	gate.Parent = folder
	blocker:SetAttribute("Tier", tierIndex)
	blocker:SetAttribute("Floors", 1)
	blocker:SetAttribute("PenDepth", length)
	return { Gate = gate, Blocker = blocker, Height = FENCE_H, BackHeight = FENCE_H }
end

return PenWalls
