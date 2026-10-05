"""Apply bounded replacements to the existing builders, retaining interaction/UI code."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def read(rel):return (ROOT/rel).read_text(encoding='utf-8')
def write(rel,s):(ROOT/rel).write_text(s,encoding='utf-8')
def replace(s,a,b):
    assert s.count(a)==1, f'Expected one boundary: {a[:70]}'
    return s.replace(a,b)

p='src/shared/KnifeModel.luau';s=read(p)
start=s.index('-- Builds knife models.');end=s.index('local ReplicatedStorage')
s=s[:start]+'''-- Native chunky toy knives; all 24 silhouettes are reconstructed as individual cuboids.
-- The invisible Handle remains at the grip origin, Blade and Guard keep their aura contracts.
'''+s[end:]
for line in ['local KnifeMeshes = require(script.Parent.Config.KnifeMeshes)\n','local KnifeDetailMeshes = require(script.Parent.Config.KnifeDetailMeshes)\n','local KnifeAppearance = require(script.Parent.Config.KnifeAppearance)\n']:
    s=replace(s,line,'')
s=replace(s,'local KnifeModel = {}','local ToyBlockModel = require(script.Parent.ToyBlockModel)\n\nlocal KnifeModel = {}')
start=s.index('local MESH_SCALE');end=s.index('local function part(')
s=s[:start]+'''local TEMPLATE_FOLDER = "KnifeTemplates"
local TOOL_LENGTH = 2.4
local BLOCK_VERSION = 1

'''+s[end:]
start=s.index('local function assembleParts(');end=s.index('-- A motion trail',start)
s=s[:start]+'''-- Server templates and client fallback use exactly the same native geometry.
function KnifeModel.Preload()
	assert(RunService:IsServer(), "KnifeModel.Preload runs on the server")
	local old = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER)
	if old and old:GetAttribute("ToyBlockVersion") == BLOCK_VERSION then
		return
	end
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = TEMPLATE_FOLDER
	folder:SetAttribute("ToyBlockVersion", BLOCK_VERSION)
	for _, knife in Knives.List do
		local model = ToyBlockModel.Build(knife.Name, false, "Handle")
		model.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

local function template(name: string): Model?
	local folder = ReplicatedStorage:FindFirstChild(TEMPLATE_FOLDER)
	if not folder or folder:GetAttribute("ToyBlockVersion") ~= BLOCK_VERSION then
		return nil
	end
	return folder:FindFirstChild(name) :: Model?
end

'''+s[end:]
start=s.index('\tlocal name, knife = parsed.Name, parsed.Knife',s.index('function KnifeModel.Build('))
end=s.index('\tlocal root = model.PrimaryPart',start)
s=s[:start]+'''\tlocal name, knife = parsed.Name, parsed.Knife
	local source = template(name)
	local model = if source then source:Clone() else ToyBlockModel.Build(name, false, "Handle")
'''+s[end:]
s=replace(s,'model:SetAttribute("Silhouette", SILHOUETTE)','model:SetAttribute("Silhouette", name)')
# Lucky cubes have their own builder; ordinary sealed cases retain their current pipeline.
start=s.index('-- Scales a knife so it is')
s=s[:start]+'''-- Mystery blocks are actual cuboid toys, shared by the Store's static viewport previews.
function KnifeModel.BuildLuckyBlock(rarity: string, anchored: boolean?): Model
	assert(Knives.RarityColors[rarity] and rarity ~= "Common", `Unknown Lucky Block tier {rarity}`)
	local model = ToyBlockModel.Build("Lucky" .. rarity, anchored, "Handle")
	model:SetAttribute("LuckyBlock", rarity)
	return model
end

'''+s[start:]
write(p,s)

p='src/server/Services/GuardService.luau';s=read(p)
s=replace(s,'local Props = require(ReplicatedStorage.Shared.Props)','local ToyBlockModel = require(ReplicatedStorage.Shared.ToyBlockModel)')
s=replace(s,'local Toy = require(ReplicatedStorage.Shared.Toy)\n','')
start=s.index('\tlocal dark = config.Color:Lerp',s.index('local function buildLair'))
end=s.index('\t-- The art-pack sign',start)
s=s[:start]+'''\tlocal W, D = lair.Width, lair.Depth
	local wallZ = D / 2 - 1
	local shell = ToyBlockModel.Build("Lair" .. config.Boss, true)
	shell:PivotTo(frame)
	shell.Parent = model
	-- Original walking surface and back boundary remain; the block shell is cosmetic.
	local stage = block(model, "Stage", Vector3.new(W, PLATFORM, D), at(0, PLATFORM / 2, 0), config.Color)
	stage.Transparency = 1
	local back = block(model, "BackWall", Vector3.new(W, 18, 2), at(0, 9 + PLATFORM, wallZ), config.Color)
	back.Transparency = 1
'''+s[end:]
start=s.index('\t\tlocal pedestal = Props.Build("Pedestal", true)',s.index('local function buildLair'))
end=s.index('\t\t-- The zone\'s plate art',start)
s=s[:start]+'''\t\tlocal pedestal = ToyBlockModel.Build("LairPlate" .. config.Boss, true)
		pedestal:PivotTo(at(x, PLATFORM, wallZ - 6))
		pedestal.Parent = model
		-- Stone is the original interaction centre; its collision and query contract is unchanged.
		local pad = block(pedestal, "Stone", Vector3.new(4.55, 1.521, 4.55), at(x, PLATFORM + 0.7605, wallZ - 6), config.Color)
		pad.Transparency = 1
'''+s[end:]
write(p,s)

p='src/server/Services/ShopNPCs.luau';s=read(p)
s=replace(s,'local Props = require(ReplicatedStorage.Shared.Props)','local ToyBlockModel = require(ReplicatedStorage.Shared.ToyBlockModel)')
s=replace(s,'local Toy = require(ReplicatedStorage.Shared.Toy)\n','')
start=s.index('\t-- Local -Z is the front',s.index('local function buildStall'))
end=s.index('\t-- A soft glowing ring',start)
s=s[:start]+'''\tlocal shell = ToyBlockModel.Build(if spec.Panel == "Shop" then "ShopMortimer" else "ShopVesper", true)
	shell:PivotTo(frame)
	shell.Parent = folder
	-- Retain the existing counter and keeper step as collision-only surfaces.
	local counter = block(folder, "Counter", Vector3.new(10, 3.4, 2.4), at(0, 1.7, -3), wood)
	counter.Transparency = 1
	local step = block(folder, "KeeperStep", Vector3.new(7, 0.45, 2.4), at(0, 0.225, 0.2), wood)
	step.Transparency = 1
'''+s[end:]
# Vesper's crystal/candles are included in her block reconstruction. Keep Mortimer's dynamic knife display.
start=s.index('\telse\n\t\t-- A glowing crystal ball',s.index('local function buildStall'))
end=s.index('\n\tend\nend\n\nlocal function buildKeeper',start)
s=s[:start]+s[end:]
write(p,s)

p='src/server/Services/Rewards.luau';s=read(p)
s=replace(s,'local Props = require(ReplicatedStorage.Shared.Props)','local ToyBlockModel = require(ReplicatedStorage.Shared.ToyBlockModel)')
s=replace(s,'local chest = Props.Build("Chest", true)','local chest = ToyBlockModel.Build("FreeChest", true)')
write(p,s)

p='src/server/Services/ManorDecor.luau';s=read(p)
s=replace(s,'local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)','local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)\nlocal ToyBlockModel = require(ReplicatedStorage.Shared.ToyBlockModel)')
start=s.index('\tlocal woodColor =',s.index('local function eventBoard'))
end=s.index('\tlocal board = block(',start)
s=s[:start]+'''\tlocal hardware = ToyBlockModel.Build("EventBoardDecor", true)
	hardware:PivotTo(CFrame.new(0, 0, z))
	hardware.Parent = folder
	local boardWidth, boardHeight = 52, 15
'''+s[end:]
s=replace(s,'local function eventBoard(z: number, width: number)','local function eventBoard(z: number, _width: number)')
# Change only the existing blank physical canvas finish; both SurfaceGuis are untouched.
s=replace(s,'at(0, 29 - boardHeight / 2 + 0.8, z),\n\t\tColor3.fromRGB(34, 22, 16)','at(0, 29 - boardHeight / 2 + 0.8, z),\n\t\tColor3.fromRGB(28, 38, 60)')
write(p,s)

p='src/client/LuckyBlockView.luau';s=read(p)
s=replace(s,'local View = {}','local ToyBlockModel = require(ReplicatedStorage.Shared.ToyBlockModel)\nlocal View = {}')
start=s.index('\tTheme.image(art, "Case" .. block')
end=s.index('\t-- Every knife inside',start)
s=s[:start]+'''\t-- Same card, burst, price and odds: only the product picture becomes its native 3D toy.
	local viewport = Ui.new("ViewportFrame", {
		Name = "LuckyBlockModel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(220, 220, 220),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -2, -3),
		ZIndex = 9,
	}, art)
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local model = ToyBlockModel.Build("Lucky" .. block, true)
	model.Parent = world
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.CFrame = CFrame.lookAt(Vector3.new(6.6, 4.8, -8.6), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
'''+s[end:]
write(p,s)
