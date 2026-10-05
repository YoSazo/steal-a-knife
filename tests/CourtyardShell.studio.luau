--!strict
-- Run as a ModuleScript inside a detached copy of Shared. Tests never mount in Workspace.
local Shell = require(script.Parent.Assets.CourtyardShell)
local Art = require(script.Parent.Config.CourtyardArt)
local CollectionService = game:GetService("CollectionService")
local storage = Instance.new("Folder")
storage.Name = "CourtyardShellAssetVerification"
storage.Parent = game:GetService("ServerStorage")
local passed = 0
local function check(value: boolean, message: string)
	assert(value, message)
	passed += 1
end

local success, result = pcall(function()
	local full = Shell.Build(storage)
	local low = Shell.Build(storage, nil, { Detail = false })
	local origin = CFrame.new(4000, 20, -200) * CFrame.Angles(0, math.rad(35), 0)
	local shifted = Shell.Build(storage, origin, { Detail = false, Ambient = false })
	local count, water, ambient, fine = 0, 0, 0, 0
	for _, item in full:GetDescendants() do
		check(not item:IsA("Light"), "shell must not create Light instances")
		check(not item:IsA("GuiBase2d"), "shell must not introduce UI or signs")
		if item:IsA("BasePart") then
			count += 1
			check(item.Anchored and not item.CanCollide and not item.CanTouch and not item.CanQuery, "decorative flags")
			if not item:GetAttribute("BiomeShellPivot") then
				local lo, hi = item.Position - item.Size / 2, item.Position + item.Size / 2
				check(lo.Z >= -0.001 and hi.Z <= 220.001, "zone length bounds")
				check(not (lo.X < -62 and hi.X > -80 and lo.Z < 159 and hi.Z > 105 and lo.Y < 32), "lair approach")
				if lo.X < 56 and hi.X > -56 then
					check(hi.Y <= 0.241 or lo.Y >= 52, "flat clear centre lane and overhead clearance")
				end
			end
			if CollectionService:HasTag(item, "BiomeFarDetail") then
				fine += 1
			end
		elseif item:IsA("Texture") and item.Name == "WaterFoam" then
			water += 1
			check(item.Texture == Art.WaterFoam.Image, "default uploaded foam image")
		elseif item:IsA("ParticleEmitter") then
			ambient += 1
		end
	end
	check(count == Shell.Geometry.PartCount and count < 3000, "full part count and budget")
	check(fine == count - Shell.Geometry.LowPartCount, "fine detail count")
	check(water == 12 and ambient == 2, "water faces and ambient effect limit")
	check(low:GetAttribute("PartCount") == Shell.Geometry.LowPartCount, "low-detail build")
	local groupCount = 0
	for _, group in full:GetChildren() do
		if group:IsA("Model") then
			groupCount += 1
			check(
				group.ModelStreamingMode == Enum.ModelStreamingMode.Atomic and group.PrimaryPart ~= nil,
				"streaming group"
			)
			local movedGroup = shifted:FindFirstChild(group.Name)
			check(movedGroup ~= nil, "transformed group")
			local sample = group:FindFirstChildWhichIsA("Part") :: Part
			local moved = (movedGroup :: Instance):FindFirstChild(sample.Name) :: Part
			check((moved.Position - (origin * sample.CFrame).Position).Magnitude < 0.01, "origin transformation")
		end
	end
	check(groupCount == 6, "six atomic groups")
	Shell.StepWater(full, 0.05)
	Shell.SetDetailVisible(full, false)
	for _, item in full:GetDescendants() do
		if item:IsA("Texture") and item.Name == "WaterFoam" then
			local speed = item:GetAttribute("FlowSpeed") :: number
			check(math.abs(item.OffsetStudsV - speed * 0.05) < 0.001, "texture scrolling")
		elseif item:IsA("BasePart") and CollectionService:HasTag(item, "BiomeFarDetail") then
			check(item.LocalTransparencyModifier == 1, "detail hiding hook")
		end
	end
	Shell.SetDetailVisible(full, true)
	return {
		Passed = passed,
		FullParts = count,
		LowParts = Shell.Geometry.LowPartCount,
		FineParts = fine,
		WaterFaces = water,
		AmbientEmitters = ambient,
		AtomicGroups = groupCount,
	}
end)
storage:Destroy()
assert(success, tostring(result))
return result
