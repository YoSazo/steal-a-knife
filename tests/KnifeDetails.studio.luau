--!strict
-- Studio-only knife contract audit for the native toy catalog.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
assert(RunService:IsStudio(), "Knife audit is Studio-only")
local Shared = ReplicatedStorage.Shared
local K = require(Shared.KnifeModel)
local Knives = require(Shared.Config.Knives)
local Items = require(Shared.Items)
local Aura = require(Shared.KnifeAura)
local result = { Passed = 0, Failed = 0, Errors = {} :: { string } }
local function check(ok: boolean, message: string)
	if ok then
		result.Passed += 1
	else
		result.Failed += 1
		table.insert(result.Errors, message)
	end
end
for _, knife in Knives.List do
	for _, mutation in Items.Mutations do
		local model = K.Build(knife.Name .. "|" .. mutation.Id .. "|", true)
		local handle = model.PrimaryPart :: BasePart
		local blade = model:FindFirstChild("Blade") :: BasePart
		local guard = model:FindFirstChild("Guard") :: BasePart
		check(handle.Name == "Handle" and handle.Position.Magnitude < 0.001, knife.Name .. ": grip origin")
		check(blade ~= nil and guard ~= nil, knife.Name .. ": aura anchors")
		check(model:GetAttribute("Silhouette") == knife.Name, knife.Name .. ": distinct silhouette")
		local anchor = Instance.new("Part")
		anchor.CFrame = guard.CFrame
		Aura.Mount(anchor, Aura.Power(knife.Name), 10, Aura.Variation(knife.Name), blade)
		check(anchor:GetAttribute("AuraPower") ~= nil, knife.Name .. ": aura")
		local count = 0
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") then
				check(
					part.Anchored and not part.CanCollide and not part.CanQuery and not part.CanTouch,
					knife.Name .. ": physics"
				)
				if part:GetAttribute("ToyBlock") then
					count += 1
					check(part:IsA("Part") and part.Shape == Enum.PartType.Block, knife.Name .. ": cuboid")
				end
			end
		end
		check(count > 20, knife.Name .. ": block detail")
		K.FitLength(model, 2.4)
		local _, size = model:GetBoundingBox()
		check(math.abs(math.max(size.X, size.Y, size.Z) - 2.4) < 0.001, knife.Name .. ": tool fitting")
		anchor:Destroy()
		model:Destroy()
	end
end
local output = Instance.new("StringValue")
output.Name = "CodexKnifeDetailAuditResult"
output.Value = HttpService:JSONEncode(result)
output.Parent = game:GetService("ServerStorage")
print("[KnifeDetailAudit] " .. output.Value)
