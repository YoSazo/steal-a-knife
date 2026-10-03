--!strict
-- Run as a temporary Studio server Script, never part of the published game.
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
assert(RunService:IsStudio(), "Knife audit is Studio-only")
game:GetService("ServerStorage"):WaitForChild("Debug", 60)
local Shared = ReplicatedStorage.Shared
local KnifeModel = require(Shared.KnifeModel)
local KnifeAura = require(Shared.KnifeAura)
local Knives = require(Shared.Config.Knives)
local Items = require(Shared.Items)
local DetailMeshes = require(Shared.Config.KnifeDetailMeshes)
local AuraArt = require(Shared.Config.KnifeAuraArt)
local templates = ReplicatedStorage:WaitForChild("KnifeTemplates", 30)
local result = { Passed = 0, Failed = 0, Errors = {} :: { string } }
local function check(condition: boolean, message: string)
	if condition then
		result.Passed += 1
	else
		result.Failed += 1
		table.insert(result.Errors, message)
	end
end
local gallery = Instance.new("Folder")
gallery.Name = "KnifeDetailAuditGallery"
gallery.Parent = workspace
local floor = Instance.new("Part")
floor.Name = "AuditFloor"
floor.Size = Vector3.new(65, 0.3, 85)
floor.Position = Vector3.new(6122.5, 1, -27)
floor.Color = Color3.fromRGB(81, 92, 99)
floor.Anchored = true
floor.CanCollide, floor.CanQuery, floor.CanTouch = false, false, false
floor.Parent = gallery
local previous = -1
local standardMeshes: { [string]: string } = {}
local standardSize: Vector3? = nil
for index, knife in Knives.List do
	local name = knife.Name
	local template = templates:FindFirstChild(name)
	check(template ~= nil, name .. ": missing mesh template")
	if not template then
		continue
	end
	local power = KnifeAura.Power(name)
	check(power > previous, name .. ": stronger knife aura does not grow")
	previous = power
	for _, mutation in Items.Mutations do
		local item = name .. "|" .. mutation.Id .. "|"
		local model = KnifeModel.Build(item, true)
		local root = model.PrimaryPart :: BasePart
		local blade = model:FindFirstChild("Blade") :: BasePart
		check(model:GetAttribute("Silhouette") == "GoldenDagger", item .. ": nonstandard silhouette")
		local _, bounds = model:GetBoundingBox()
		if standardSize then
			check((bounds - standardSize).Magnitude < 0.001, item .. ": skin changes model size")
		else
			standardSize = bounds
		end
		for _, role in { "Blade", "Guard", "Grip", "Pommel" } do
			local body = model:FindFirstChild(role) :: MeshPart
			if standardMeshes[role] then
				check(body.MeshId == standardMeshes[role], item .. ": different body shape " .. role)
			else
				standardMeshes[role] = body.MeshId
			end
		end
		check(root.Name == "Handle" and root.Transparency == 1, item .. ": grip pivot changed")
		check(blade.Material ~= Enum.Material.Neon, item .. ": blade bevel flattened by neon")
		check(blade.Transparency == 0, item .. ": blade body lost opacity")
		check(root.CFrame.UpVector:Dot((blade.Position - root.Position).Unit) > 0.7, item .. ": blade axis changed")
		local count = 0
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") then
				count += 1
				check(not part.CanQuery and not part.CanCollide and not part.CanTouch, item .. ": cosmetic hitbox")
				if part ~= root then
					check(
						part.Massless and part:FindFirstChildOfClass("WeldConstraint") ~= nil,
						item .. ": loose decoration"
					)
				end
			end
		end
		check(count <= 9, item .. ": too many physics parts")
		for _, spec in DetailMeshes[name] do
			local detail = model:FindFirstChild(spec.Name)
			check(detail ~= nil and detail:IsA("MeshPart"), item .. ": missing " .. spec.Name)
		end
		local edge = model:FindFirstChild("CuttingEdge") :: BasePart?
		if edge then
			local contrast = math.abs(edge.Color.R - blade.Color.R)
				+ math.abs(edge.Color.G - blade.Color.G)
				+ math.abs(edge.Color.B - blade.Color.B)
			check(contrast > 0.12, item .. ": cutting edge not distinct")
		end
		check(blade:FindFirstChild("KnifeTrail") ~= nil, item .. ": swing trail missing")
		if mutation.Id == "Rainbow" then
			check(model:HasTag("RainbowKnife"), item .. ": rainbow animation tag missing")
			local grip = model:FindFirstChild("Grip") :: BasePart
			check(grip:GetAttribute("RainbowValue") == nil, item .. ": rainbow erases grip contrast")
		end
		KnifeModel.FitLength(model, 6)
		local _, size = model:GetBoundingBox()
		check(math.abs(math.max(size.X, size.Y, size.Z) - 6) < 0.01, item .. ": display scale changed")
		if mutation.Id == "" then
			model.Name = name
			model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
			local position = Vector3.new(6100 + ((index - 1) % 6) * 9, 8, -math.floor((index - 1) / 6) * 18)
			model:PivotTo(CFrame.new(position))
			model.Parent = gallery
			local anchor = Instance.new("Part")
			anchor.Name = name .. "Aura"
			anchor.Anchored = true
			anchor.CanCollide, anchor.CanTouch, anchor.CanQuery = false, false, false
			anchor.Transparency = 1
			anchor.Size = Vector3.new(0.2, 0.2, 0.2)
			anchor.Position = position + Vector3.new(0, 1.5, 0)
			anchor.Parent = model
			KnifeAura.Mount(anchor, power)
			check(anchor:FindFirstChild("AuraFire") == nil, name .. ": default Fire remains")
			local totalRate, emitters = 0, 0
			for _, effect in anchor:GetDescendants() do
				if effect:IsA("ParticleEmitter") then
					emitters += 1
					totalRate += effect.Rate
					check(
						(
							effect.Texture == AuraArt.Flame
							or effect.Texture == AuraArt.Core
							or effect.Texture == AuraArt.SoftFlame
							or effect.Texture == AuraArt.Wisp
							or effect.Texture == AuraArt.Ember
						)
							and effect.FlipbookLayout == (if effect.Texture == AuraArt.Ember
								then Enum.ParticleFlipbookLayout.Grid4x4
								else Enum.ParticleFlipbookLayout.Grid8x8)
							and effect.FlipbookMode == Enum.ParticleFlipbookMode.Loop,
						name .. ": custom animated art missing"
					)
					local baseRate = effect:GetAttribute("BaseRate")
					check(
						effect:HasTag("KnifeAuraEmitter")
							and type(baseRate) == "number"
							and math.abs(baseRate - effect.Rate) < 0.0001,
						name .. ": missing particle LOD contract"
					)
				end
			end
			check(emitters == 6 and totalRate <= 60, name .. ": particle budget exceeded")
		else
			model:Destroy()
		end
	end
	for _, itemSize in Items.Sizes do
		local item = name .. "||" .. itemSize.Id
		local tool = KnifeModel.BuildTool(item)
		local parts = Instance.new("Model")
		for _, part in tool:GetChildren() do
			part.Parent = parts
		end
		parts.PrimaryPart = parts:FindFirstChild("Handle") :: BasePart
		local _, size = parts:GetBoundingBox()
		local expected = 2.4
		check(math.abs(math.max(size.X, size.Y, size.Z) - expected) < 0.01, item .. ": held size changed")
		local display = KnifeModel.Build(item, true)
		KnifeModel.FitItem(display, item, 6)
		local _, displaySize = display:GetBoundingBox()
		check(
			math.abs(math.max(displaySize.X, displaySize.Y, displaySize.Z) - 6) < 0.01,
			item .. ": size roll changes display scale"
		)
		display:Destroy()
		check(tool.TextureId ~= "" and tool.Grip == CFrame.new(), item .. ": hotbar or grip broken")
		parts:Destroy()
		tool:Destroy()
	end
	local rainbow = KnifeModel.BuildTool(name .. "|Rainbow|")
	check(rainbow:HasTag("RainbowKnife"), name .. ": held rainbow does not animate")
	rainbow:Destroy()
	check(KnifeAura.Power(name .. "|Void|Colossal") > power, name .. ": variant aura does not grow")
end
local smallWidth, smallHeight = KnifeAura.Dimensions(0)
local bigWidth, bigHeight = KnifeAura.Dimensions(15)
check(bigWidth > smallWidth and bigHeight > smallHeight, "Aura strength dimensions")
local ceiling = Instance.new("Part")
KnifeAura.Mount(ceiling, 15, 4)
local capped = ceiling:GetAttribute("AuraHeight") :: number
check(capped < 4 and capped > 3, "Aura crosses an upper vault floor")
ceiling:Destroy()
local case = KnifeModel.BuildCase("Legendary", true)
check(case.PrimaryPart ~= nil and case:GetAttribute("Case") == "Legendary", "Chest builder regression")
case:Destroy()
workspace:SetAttribute("KnifeDetailAuditResult", HttpService:JSONEncode(result))
print("[KnifeDetailsAudit]", HttpService:JSONEncode(result))
