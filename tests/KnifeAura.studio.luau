--!strict
-- Temporary Studio server audit and visual stage; not mapped into the published game.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
assert(game:GetService("RunService"):IsStudio())
game:GetService("ServerStorage"):WaitForChild("Debug", 60)
local Aura = require(ReplicatedStorage.Shared.KnifeAura)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local Art = require(ReplicatedStorage.Shared.Config.KnifeAuraArt)
local Variants = require(ReplicatedStorage.Shared.Config.KnifeAuraVariants)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local Items = require(ReplicatedStorage.Shared.Items)
local result = { Passed = 0, Failed = 0, Errors = {} :: { string } }
local function check(condition: boolean, message: string)
	if condition then
		result.Passed += 1
	else
		result.Failed += 1
		table.insert(result.Errors, message)
	end
end
local allowed =
	{ [Art.Flame] = true, [Art.Core] = true, [Art.Wisp] = true, [Art.Ember] = true, [Art.CartoonFlame] = true }
check(#Variants.List == 50, "Exactly fifty variations")
local seen: { [string]: boolean } = {}
for _, style in Variants.List do
	check(not seen[style.Id] and Variants.ById[style.Id] == style, "Unique indexed recipe " .. style.Id)
	seen[style.Id] = true
	for _, clearance in { 0.25, 4, 30 } do
		local anchor = Instance.new("Part")
		Aura.Mount(anchor, 15, clearance, style)
		check(anchor:GetAttribute("AuraVariation") == style.Id, "Mounted recipe identity")
		check((anchor:GetAttribute("AuraHeight") :: number) <= clearance, "Recipe ceiling cap")
		local roles: { [string]: boolean } = {}
		for _, effect in anchor:GetDescendants() do
			if effect:IsA("ParticleEmitter") then
				local role = effect:GetAttribute("AuraLayer") :: string
				check(not roles[role], "Duplicate independent role")
				roles[role] = true
				local colors = style.Colors[role]
				local keys = effect.Color.Keypoints
				check(keys[1].Value == colors.Start and keys[#keys].Value == colors.Finish, "Layer color " .. role)
				check(effect.FlipbookFramerate.Max <= 30 and effect.FlipbookFramerate.Min > 0, "Animation frame budget")
			end
		end
		for _, role in Variants.LayerNames do
			check(roles[role] == true, "Missing role " .. role)
		end
		anchor:Destroy()
	end
end
local custom = { Start = Color3.fromRGB(17, 41, 103), Finish = Color3.fromRGB(119, 13, 205) }
local mixed = Variants.Compose(
	"volcano-rolling",
	{ Outer = "glacier-rolling", Smoke = "phantom-floating" },
	{ Embers = custom }
)
check(mixed.Colors.Outer == Variants.ById["glacier-rolling"].Colors.Outer, "Outer recombination")
check(mixed.Colors.Smoke == Variants.ById["phantom-floating"].Colors.Smoke, "Smoke recombination")
check(mixed.Colors.Core == Variants.ById["volcano-rolling"].Colors.Core, "Unchanged core")
check(
	mixed.Colors.Embers.Start == custom.Start and mixed.Colors.Embers.Finish == custom.Finish,
	"Original layer override"
)
check(Variants.ById["volcano-rolling"].Colors.Outer ~= mixed.Colors.Outer, "Compose mutated shared recipe")
check(not pcall(Variants.Compose, "missing"), "Reject missing base")
check(not pcall(Variants.Compose, "volcano-rolling", { Unknown = "glacier-rolling" }), "Reject missing role")
check(not pcall(Variants.Compose, "volcano-rolling", { Core = "missing" }), "Reject missing source")
local reachable: { [string]: boolean } = {}
for _, knife in Knives.List do
	for _, mutation in Items.Mutations do
		for _, size in Items.Sizes do
			local item = knife.Name .. "|" .. mutation.Id .. "|" .. size.Id
			local style = Aura.Variation(item)
			reachable[style.Id] = true
			check(Aura.Variation(item .. "|Hellfire") == style, "Combat perk changed aura identity")
		end
	end
end
for _, style in Variants.List do
	check(reachable[style.Id] == true, "Unreachable recipe " .. style.Id)
end
check(Aura.Variation("NotAKnife") == Variants.List[1], "Invalid item fallback")
local previousWidth, previousHeight = 0, 0
for power = 0, 15 do
	local w, h = Aura.Dimensions(power)
	check(w > previousWidth and h > previousHeight, "Strength progression " .. power)
	previousWidth, previousHeight = w, h
	for _, clearance in { 0.25, 1, 4, 8, 30 } do
		local anchor = Instance.new("Part")
		local preserved = Instance.new("Attachment")
		preserved.Name = "UnrelatedAttachment"
		preserved.Parent = anchor
		Aura.Mount(anchor, power, clearance)
		Aura.Mount(anchor, power, clearance)
		local height = anchor:GetAttribute("AuraHeight") :: number
		check(height <= clearance + 0.001 and height > 0, "Ceiling cap " .. clearance)
		check(preserved.Parent == anchor, "Remount removed unrelated attachment")
		local count, rate, lights = 0, 0, 0
		for _, effect in anchor:GetDescendants() do
			check(not effect:IsA("Fire"), "Default fire reintroduced")
			if effect:IsA("ParticleEmitter") then
				count += 1
				rate += effect.Rate
				local minimum = effect:GetAttribute("AuraMinRate") :: number
				check(allowed[effect.Texture] == true, "Noncustom aura art")
				check(
					effect.FlipbookLayout
						== (
							if effect.Texture == Art.Ember
								then Enum.ParticleFlipbookLayout.Grid4x4
								else Enum.ParticleFlipbookLayout.Grid8x8
						),
					"Flipbook grid"
				)
				check(effect.FlipbookMode == Enum.ParticleFlipbookMode.Loop, "Animation loop")
				check(minimum > 0 and minimum <= effect.Rate, "Mobile density floor")
				check(effect:HasTag("KnifeAuraEmitter"), "LOD tag")
				local baseRate = effect:GetAttribute("BaseRate") :: number
				check(math.abs(baseRate - effect.Rate) < 0.001, "LOD base rate")
			elseif effect:IsA("PointLight") then
				lights += 1
			end
		end
		check(count == 6 and lights == 1 and rate <= 60, "Remount budget or duplicate layers")
		anchor:Destroy()
	end
end
local stage = Instance.new("Model")
stage.Name = "CodexAuraVisualGallery"
stage.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
local function part(name: string, size: Vector3, position: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = position
	p.Color = color
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = stage
	return p
end
part("Floor", Vector3.new(76, 1, 28), Vector3.new(6240, 0, 20), Color3.fromRGB(65, 74, 79))
part("Backdrop", Vector3.new(76, 36, 1), Vector3.new(6240, 17, 6), Color3.fromRGB(29, 36, 41))
for i, power in { 0, 7, 15, 15 } do
	local x = 6213 + (i - 1) * 18
	local model = KnifeModel.Build("GoldenDagger", true)
	KnifeModel.FitLength(model, 6)
	model:PivotTo(CFrame.new(x, 4.5, 20))
	model.Name = "Strength" .. i
	model.Parent = stage
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			p.Anchored = true
		end
	end
	local anchor = part("Aura" .. i, Vector3.new(0.2, 0.2, 0.2), Vector3.new(x, 5, 20), Color3.new())
	anchor.Transparency = 1
	Aura.Mount(anchor, power, if i == 4 then 4 else nil)
	if i == 4 then
		part("Ceiling", Vector3.new(12, 0.3, 12), Vector3.new(x, 9.5, 20), Color3.fromRGB(77, 91, 99))
	end
end
stage.Parent = workspace
-- Ten themes in the same motion profile, separate from the strength comparison.
for i = 1, 10 do
	local x = 6186 + ((i - 1) % 5) * 27
	local z = 80 + math.floor((i - 1) / 5) * 42
	local anchor = part("Palette" .. i, Vector3.new(0.2, 0.2, 0.2), Vector3.new(x, 5, z), Color3.new())
	anchor.Transparency = 1
	Aura.Mount(anchor, 10, nil, Variants.List[(i - 1) * 5 + 1])
end
workspace:SetAttribute("KnifeAuraAuditResult", HttpService:JSONEncode(result))
print("[KnifeAuraAudit]", HttpService:JSONEncode(result))
