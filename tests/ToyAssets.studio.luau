--!strict
-- Detached copies of the actual model and world builders; no live world mutation.
local K = require(script.Parent.KnifeModel)
local B = require(script.Parent.ToyBlockModel)
local Specs = require(script.Parent.Config.ToyGeometryData)
local Catalog = require(script.Parent.Config.Knives)
local Items = require(script.Parent.Items)
local Aura = require(script.Parent.KnifeAura)
local LairOld = require(script.Parent.LairOld)
local LairNew = require(script.Parent.LairNew)
local ShopOld = require(script.Parent.ShopOld)
local ShopNew = require(script.Parent.ShopNew)
local BoardOld = require(script.Parent.BoardOld)
local BoardNew = require(script.Parent.BoardNew)
local ChestOld = require(script.Parent.ChestOld)
local ChestNew = require(script.Parent.ChestNew)
local passed = 0
local function check(ok: boolean, message: string)
	assert(ok, message)
	passed += 1
end
local function sameCF(a: CFrame, b: CFrame, message: string)
	check((a.Position - b.Position).Magnitude < 0.002 and a.LookVector:Dot(b.LookVector) > 0.99999, message)
end
local function uiSignature(parent: Instance): { string }
	local result = {}
	for _, p in parent:GetDescendants() do
		if p:IsA("TextLabel") then
			table.insert(result, `Text|{p.Name}|{p.Text}|{p.Size}|{p.Position}|{p.Font.Name}|{p.TextScaled}`)
		elseif p:IsA("ImageLabel") then
			table.insert(result, `Image|{p.Name}|{p.Image}|{p.Size}|{p.Position}`)
		elseif p:IsA("SurfaceGui") then
			table.insert(result, `Surface|{p.Name}|{p.Face.Name}|{p.SizingMode.Name}|{p.PixelsPerStud}`)
		elseif p:IsA("BillboardGui") then
			table.insert(result, `Billboard|{p.Name}|{p.Size}|{p.StudsOffsetWorldSpace}|{p.MaxDistance}`)
		elseif p:IsA("ProximityPrompt") then
			table.insert(
				result,
				`Prompt|{p.ActionText}|{p.ObjectText}|{p.HoldDuration}|{p.MaxActivationDistance}|{p.KeyboardKeyCode.Name}|{p.Enabled}`
			)
		end
	end
	table.sort(result)
	return result
end
local function sameUI(a: Instance, b: Instance, name: string)
	local first, second = uiSignature(a), uiSignature(b)
	check(#first == #second, name .. ": UI element count changed")
	for i, signature in first do
		check(signature == second[i], name .. ": UI changed: " .. signature)
	end
end

local total = 0
for name, specs in Specs do
	local model = B.Build(name, true)
	check(model:GetPivot().Position.Magnitude < 0.0001, name .. ": origin shifted")
	local blocks = {}
	for _, p in model:GetChildren() do
		if p:IsA("Part") and p:GetAttribute("ToyBlock") then
			table.insert(blocks, p)
		end
	end
	check(#blocks == #specs, name .. ": missing cuboid")
	local target = CFrame.new(2400, 80, 3000) * CFrame.Angles(0, math.rad(53), 0)
	model:PivotTo(target)
	for i, p in blocks do
		local spec = specs[i]
		check(p.Name == spec.Name and p.Size == spec.Size, name .. ": wrong block")
		sameCF(
			p.CFrame,
			target * CFrame.new(spec.Offset) * CFrame.Angles(0, 0, math.rad(spec.Angle or 0)),
			name .. ": transform"
		)
		check(p.Color == spec.Color and p.Shape == Enum.PartType.Block, name .. ": wrong finish/shape")
		check(
			p.Anchored and p.Massless and not p.CanCollide and not p.CanQuery and not p.CanTouch,
			name .. ": cosmetic physics"
		)
		check(p.Material == Enum.Material.SmoothPlastic, name .. ": wrong toy material")
	end
	total += #blocks
	model:Destroy()
end
check(#Catalog.List == 24, "Knife catalog changed")
local silhouettes = {}
if game:GetService("RunService"):IsServer() then
	K.Preload()
	local templates = script.Parent:FindFirstChild("KnifeTemplates") :: Folder
	check(templates ~= nil and #templates:GetChildren() == 24, "Native preload is incomplete")
	K.Preload()
	check(#templates:GetChildren() == 24, "Preload duplicated knives")
end
for _, knife in Catalog.List do
	local plain = K.Build(knife.Name, true)
	local root = plain.PrimaryPart :: BasePart
	check(root.Name == "Handle" and root.Position.Magnitude < 0.0001, knife.Name .. ": grip origin")
	local blade = plain:FindFirstChild("Blade") :: BasePart
	local guard = plain:FindFirstChild("Guard") :: BasePart
	check(blade ~= nil and guard ~= nil, knife.Name .. ": aura anchors removed")
	check(blade.Size.Y > blade.Size.X and blade.Size.Y > blade.Size.Z, knife.Name .. ": blade axis")
	check(plain:GetAttribute("Silhouette") == knife.Name, knife.Name .. ": wrong silhouette")
	check(blade:FindFirstChild("KnifeTrail") ~= nil, knife.Name .. ": swing trail missing")
	local shape = {}
	for _, p in plain:GetChildren() do
		if p:IsA("BasePart") then
			table.insert(shape, `{p.Size}|{p.Position}`)
		end
	end
	local signature = table.concat(shape, ";")
	check(not silhouettes[signature], knife.Name .. ": repeats another silhouette")
	silhouettes[signature] = true
	local _, originalSize = plain:GetBoundingBox()
	for _, mutation in Items.Mutations do
		local model = K.Build(knife.Name .. "|" .. mutation.Id .. "|", true)
		local _, size = model:GetBoundingBox()
		check((size - originalSize).Magnitude < 0.001, knife.Name .. ": mutation moved geometry")
		local anchor = Instance.new("Part")
		anchor.CFrame = guard.CFrame
		Aura.Mount(
			anchor,
			Aura.Power(knife.Name),
			10,
			Aura.Variation(knife.Name),
			model:FindFirstChild("Blade") :: BasePart
		)
		check(anchor:GetAttribute("AuraPower") ~= nil, knife.Name .. ": aura mounting failed")
		anchor:Destroy()
		model:Destroy()
	end
	plain:Destroy()
	local tool = K.BuildTool(knife.Name)
	local handle = tool:FindFirstChild("Handle") :: BasePart
	check(handle ~= nil and not handle.Anchored and handle.Position.Magnitude < 0.001, knife.Name .. ": tool grip")
	check(tool.Grip == CFrame.new() and not tool.CanBeDropped, knife.Name .. ": tool contract")
	local count = 0
	for _, p in tool:GetChildren() do
		if p:IsA("BasePart") and p ~= handle then
			check(
				not p.Anchored and p.Massless and p:FindFirstChildOfClass("WeldConstraint") ~= nil,
				knife.Name .. ": loose tool block"
			)
			count += 1
		end
	end
	check(count > 20, knife.Name .. ": toy details missing")
	tool:Destroy()
end
for i = 1, 8 do
	local old, new = LairOld(i), LairNew(i)
	check(#new.Slots == 5, "Five lair slots required")
	sameCF(old.Post, new.Post, "Boss post moved")
	for slot = 1, 5 do
		sameCF(old.Slots[slot].Spot, new.Slots[slot].Spot, "Knife spot moved")
		check((old.Slots[slot].Pad.Position - new.Slots[slot].Pad.Position).Magnitude < 0.002, "Steal anchor moved")
		check(old.Slots[slot].Prompt.ActionText == new.Slots[slot].Prompt.ActionText, "Steal action changed")
	end
	for _, name in { "Sign", "SignRibbon", "Stage", "BackWall" } do
		local a, b = old.Folder:FindFirstChild(name) :: BasePart, new.Folder:FindFirstChild(name) :: BasePart
		sameCF(a.CFrame, b.CFrame, name .. ": placement changed")
		check(a.Size == b.Size, name .. ": dimensions changed")
	end
	sameUI(old.Folder, new.Folder, "Lair" .. i)
	old.Folder:Destroy()
	new.Folder:Destroy()
end
for _, panel in { "Shop", "Powers" } do
	local old, new = ShopOld(panel), ShopNew(panel)
	for _, name in { "GlowRing", "TitleAnchor", "Counter", "KeeperStep" } do
		local a, b = old:FindFirstChild(name) :: BasePart, new:FindFirstChild(name) :: BasePart
		sameCF(a.CFrame, b.CFrame, name .. ": shop anchor moved")
		check(a.Size == b.Size, name .. ": shop dimensions changed")
	end
	local ring = new:FindFirstChild("GlowRing") :: BasePart
	check(ring:HasTag("ShopRing") and ring:GetAttribute("ShopPanel") == panel, "Shop trigger changed")
	sameUI(old, new, panel)
	old:Destroy()
	new:Destroy()
end
local boardOld, boardNew = BoardOld(), BoardNew()
sameUI(boardOld, boardNew, "Event board")
local a, b = boardOld:FindFirstChild("EventBoard") :: BasePart, boardNew:FindFirstChild("EventBoard") :: BasePart
sameCF(a.CFrame, b.CFrame, "Event board canvas moved")
check(a.Size == b.Size, "Event board canvas resized")
boardOld:Destroy()
boardNew:Destroy()
local chestOld, chestNew = ChestOld(), ChestNew()
sameUI(chestOld, chestNew, "Free chest")
local oldRoot = chestOld:FindFirstChild("FreeChest") :: Model
local newRoot = chestNew:FindFirstChild("FreeChest") :: Model
sameCF(oldRoot:GetPivot(), newRoot:GetPivot(), "Chest interaction origin moved")
check(newRoot:HasTag("FreeChest"), "Chest HUD tag missing")
chestOld:Destroy()
chestNew:Destroy()
for _, tier in { "Rare", "Epic", "Legendary", "Mythic", "Godly", "Celestial", "Cosmic" } do
	local model = K.BuildLuckyBlock(tier, true)
	check(model:GetAttribute("LuckyBlock") == tier, "Wrong mystery cube tier")
	local glyphs = 0
	for _, p in model:GetChildren() do
		if p.Name == "QuestionPixel" then
			glyphs += 1
		end
	end
	check(glyphs >= 56, "Missing mystery cube question marks")
	model:Destroy()
end
return {
	Passed = passed,
	Knives = 24,
	Lairs = 8,
	Shops = 2,
	LuckyBlocks = 7,
	PlazaProps = 2,
	Cuboids = total,
	InteractionsPreserved = true,
	WorldUIPreserved = true,
}
