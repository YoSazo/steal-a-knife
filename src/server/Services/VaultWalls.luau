--!strict
-- A vault's clean block-built frame for its wall tier (GameConfig.Walls). VaultModel supplies
-- stepped pillars, panel roofs and themed hardware; this service preserves walls and raid state.
-- Everything is built in the vault's own frame (local +Z = the open side facing the plaza). The
-- gate's invisible "Blocker" is what raiders hit and what clients make solid for everyone but the
-- owner (see client/Raid, which also fades the "Pane" lasers as the gate loses health). Gate state
-- lives in attributes on the Blocker: Owner, Health, MaxHealth, Open, Tier.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldSignModel = require(ReplicatedStorage.Shared.WorldSignModel)

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
-- along the base and the gate's health bar), `tierIndex` its wall tier.
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

	-- The open front keeps its existing invisible raid target and health UI.
	local gate = Instance.new("Model")
	gate.Name = "Gate"
	local gateZ = HALF_D - T / 2
	-- What actually blocks (on clients) and what raiders hit
	local blocker =
		block(gate, "Blocker", Vector3.new(GATE_HALF * 2, GATE_H, 1.2), at(0, GATE_H / 2, gateZ), Color3.new(), nil)
	blocker.Transparency = 1
	blocker.CanCollide = false -- each client decides (the owner walks through, everyone else bumps)
	blocker.CanQuery = true
	blocker.CanTouch = false
	blocker:AddTag("VaultGate")
	for _, d in gate:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("BaseTransparency", d.Transparency)
		end
	end
	-- Physical raid board; only live title and health are SurfaceGui text.
	local healthAnchor = Instance.new("Part")
	healthAnchor.Name, healthAnchor.Size = "GateHealthFace", Vector3.new(10, 2.3, 0.2)
	healthAnchor.CFrame = blocker.CFrame * CFrame.new(0, GATE_H / 2 + 2.6, 0)
	healthAnchor.Anchored, healthAnchor.Transparency = true, 1
	healthAnchor.CanCollide, healthAnchor.CanQuery, healthAnchor.CanTouch = false, false, false
	healthAnchor:SetAttribute("Keep", true)
	healthAnchor.Parent = blocker
	local board, healthFace = WorldSignModel.Attach("GateHealth", healthAnchor, Enum.NormalId.Back)
	WorldSignModel.SetVisible(board, false)
	local gui = WorldSignModel.Surface(blocker, healthFace, "GateHealth", 120)
	gui.Enabled = false
	local name = WorldSignModel.LiveText(gui, "Title", tier.Name)
	name.Size = UDim2.fromScale(1, 0.48)
	local amount = WorldSignModel.LiveText(gui, "Health", tostring(tier.GateHealth))
	amount.Position, amount.Size = UDim2.fromScale(0, 0.52), UDim2.fromScale(1, 0.45)
	-- Keep the Fill path for callers, without drawing a flat GUI bar.
	local back = Instance.new("Frame")
	back.Name, back.BackgroundTransparency, back.Size = "Back", 1, UDim2.fromScale(1, 1)
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name, fill.BackgroundTransparency, fill.Size = "Fill", 1, UDim2.fromScale(1, 1)
	fill.Parent = back
	gate.PrimaryPart = blocker
	gate.Parent = folder

	-- Nothing in the frame throws shadows into the vault
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = false
		end
	end
	blocker:SetAttribute("Tier", tierIndex)
	blocker:SetAttribute("MaxHealth", tier.GateHealth)
	blocker:SetAttribute("Health", tier.GateHealth)
	blocker:SetAttribute("Floors", floorCount)
	return { Gate = gate, Blocker = blocker, Height = FRAME_H, BackHeight = FRAME_H }
end

-- Broken gates: the lasers switch off (and come back when it reforges); the posts stay
function VaultWalls.SetOpen(gate: Model, open: boolean)
	for _, d in gate:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Blocker" and not d:GetAttribute("Keep") then
			local base = d:GetAttribute("BaseTransparency")
			d.Transparency = if open then 1 else (if type(base) == "number" then base else 0)
		end
	end
	local blocker = gate:FindFirstChild("Blocker")
	if blocker then
		blocker:SetAttribute("Open", open or nil)
	end
end

return VaultWalls
