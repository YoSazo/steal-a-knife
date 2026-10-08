--!strict
-- A vault's clean block-built frame for its wall look (GameConfig.Walls). VaultModel supplies
-- stepped pillars, panel roofs and themed hardware. Everything is built in the vault's own frame
-- (local +Z = the open side facing the plaza). The gate gap holds an invisible, walk-through
-- "Blocker" (tag VaultGate) that marks the vault: attributes Owner, OwnerName, Tier, Floors
-- (client/BaseMarkers, BaseService's rebuild checks).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local VaultModel = require(ReplicatedStorage.Shared.VaultModel)

local VaultWalls = {}

local HALF_W, HALF_D = 20, 22 -- vault is 40 wide, 44 deep
local T = 1 -- rail thickness
local GATE_HALF = 8 -- gate opening is 16 wide
local GATE_H = 11
local FLOOR_H = 22 -- MapService.FloorHeight

export type Built = {
	Gate: Model,
	Blocker: Part,
	Height: number,
	BackHeight: number,
}

local function block(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Builds (or rebuilds) a vault's frame into `folder`. `color` is the vault's own colour (the strip
-- along the base), `tierIndex` its wall look.
function VaultWalls.Build(folder: Folder, frame: CFrame, color: Color3, tierIndex: number, floors: number?): Built
	folder:ClearAllChildren()
	-- The frame rises with the vault: up past the top floor's railing
	local floorCount = floors or 1
	local FRAME_H = floorCount * FLOOR_H + 4
	local WALL_H = math.max(44, FRAME_H + 16) -- the invisible walls: nobody climbs or jumps out over them
	local tier = GameConfig.Walls[math.clamp(tierIndex, 1, #GameConfig.Walls)]
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end

	-- Invisible walls on every side but the gate: you can see in, you can't walk in
	local function invisible(name: string, size: Vector3, cframe: CFrame)
		local p = block(folder, name, size, cframe, Color3.new(), nil)
		p.Transparency = 1
		p.CastShadow = false
		p.CanTouch = false
	end
	invisible("BackWall", Vector3.new(HALF_W * 2, WALL_H, T), at(0, WALL_H / 2, -HALF_D + T / 2))
	for _, side in { -1, 1 } do
		invisible("SideWall", Vector3.new(T, WALL_H, HALF_D * 2), at(side * (HALF_W - T / 2), WALL_H / 2, 0))
	end
	VaultModel.BuildFrame(folder, frame, color, tier.Color, floorCount, tierIndex)

	-- The open front: an invisible, walk-through marker across the gate gap
	local gate = Instance.new("Model")
	gate.Name = "Gate"
	local gateZ = HALF_D - T / 2
	local blocker =
		block(gate, "Blocker", Vector3.new(GATE_HALF * 2, GATE_H, 1.2), at(0, GATE_H / 2, gateZ), Color3.new(), nil)
	blocker.Transparency = 1
	blocker.CanCollide = false
	blocker.CanQuery = true
	blocker.CanTouch = false
	blocker:AddTag("VaultGate")
	gate.PrimaryPart = blocker
	gate.Parent = folder

	-- Nothing in the frame throws shadows into the vault
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = false
		end
	end
	blocker:SetAttribute("Tier", tierIndex)
	blocker:SetAttribute("Floors", floorCount)
	return { Gate = gate, Blocker = blocker, Height = FRAME_H, BackHeight = FRAME_H }
end

return VaultWalls
