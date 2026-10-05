--!strict
-- Asset verification only. Run inside a detached Shared copy with the unchanged GameConfig.
local Shell = require(script.Parent.Assets.HeavensShell)
local GameConfig = require(script.Parent.Config.GameConfig)
local previous = require(script.Parent.PreviousExit)
local CollectionService = game:GetService("CollectionService")
local storage = Instance.new("Folder")
storage.Name = "HeavensShellAssetVerification"
storage.Parent = game:GetService("ServerStorage")
local passed = 0
local function check(ok: boolean, message: string)
	assert(ok, message)
	passed += 1
end
local success, result = pcall(function()
	local full = Shell.Build(storage, CFrame.identity)
	local low = Shell.Build(storage, CFrame.identity, { Detail = false })
	local placed = Shell.Build(storage)
	check(
		placed.PrimaryPart ~= nil and (placed:GetPivot().Position - Vector3.new(0, 0, 1320)).Magnitude < 0.001,
		"default zone entrance"
	)
	check(
		GameConfig.Zones[7].Boss == Shell.Geometry.Boss and GameConfig.Zones[7].BossTitle == Shell.Geometry.BossTitle,
		"boss identity"
	)
	check(GameConfig.Zones[7].BossWear[1] == "Halo" and Shell.Geometry.BossWear[1] == "Halo", "Halo theme")
	check(
		GameConfig.Zones[7].BossWear[2] == "AngelWings" and Shell.Geometry.BossWear[2] == "AngelWings",
		"Angel Wings theme"
	)
	check((GameConfig.BossLairCenter(7) - Vector3.new(-73, 0, 1452)).Magnitude < 0.001, "current lair position")
	check(GameConfig.ZoneDepth == 220 and GameConfig.ArenaWidth == 160, "measured zone bounds")
	local count, fine, water, ambient, groups, glow = 0, 0, 0, 0, 0, 0
	for _, child in full:GetChildren() do
		if child:IsA("Model") then
			groups += 1
			check(child.ModelStreamingMode == Enum.ModelStreamingMode.Atomic, "atomic section")
		end
	end
	for _, item in full:GetDescendants() do
		check(
			not item:IsA("Light") and not item:IsA("GuiBase2d") and not item:IsA("Constraint"),
			"no lights/UI/physics constraints"
		)
		if item:IsA("BasePart") then
			count += 1
			if item:GetAttribute("BiomeHeroGlow") then
				glow += 1
				check(item.Material == Enum.Material.Neon, "hero glow uses Neon")
			end
			check(item.Anchored and not item.CanCollide and not item.CanTouch and not item.CanQuery, "cosmetic flags")
			if not item:GetAttribute("BiomeShellPivot") then
				local lo, hi = item.Position - item.Size / 2, item.Position + item.Size / 2
				local isSeam = item.Parent and item.Parent.Name == "Entrance"
				check(lo.Z >= (if isSeam then -3.001 else -0.001) and hi.Z <= 220.001, "zone and seam bounds")
				check(
					not (lo.X < -62 and hi.X > -80 and lo.Z < 159 and hi.Z > 105 and lo.Y < 32),
					"Zoe approach clearance"
				)
				if lo.X < 56 and hi.X > -56 then
					check(hi.Y <= 0.241 or lo.Y >= 70, "flat central lane and overhead clearance")
				end
			end
			if CollectionService:HasTag(item, "BiomeFarDetail") then
				fine += 1
			end
		elseif item:IsA("Texture") and item.Name == "WaterFoam" then
			water += 1
		elseif item:IsA("ParticleEmitter") then
			ambient += 1
		end
	end
	check(glow > 20, "visible hero glow geometry")
	check(count == Shell.Geometry.PartCount and count <= 1500, "full budget")
	check(
		low:GetAttribute("PartCount") == Shell.Geometry.LowPartCount and Shell.Geometry.LowPartCount <= 800,
		"low budget"
	)
	check(count - fine == Shell.Geometry.LowPartCount, "detail omission counts")
	local lowCount, lowGlow, lowFlows = 0, 0, 0
	for _, item in low:GetDescendants() do
		if item:IsA("BasePart") then
			lowCount += 1
			if item:GetAttribute("BiomeHeroGlow") then
				lowGlow += 1
			end
			check(not CollectionService:HasTag(item, "BiomeFarDetail"), "low omits fine geometry")
		elseif item:IsA("Texture") and item.Name == "WaterFoam" then
			lowFlows += 1
		end
	end
	check(lowCount == Shell.Geometry.LowPartCount and lowCount <= 800, "actual low-detail part budget")
	check(lowGlow > 20 and lowFlows == Shell.Geometry.FlowFaces, "low preserves hero glow and flows")
	check(groups == 6 and water == Shell.Geometry.FlowFaces and ambient == 0, "group/effect count")
	local seam = full:FindFirstChild("Entrance") :: Model
	for _, p in previous do
		local profileName = string.match(p.Name, "(Gate%a+_%d%d%d)")
		check(profileName ~= nil, "canonical gate identity")
		local collar = seam:FindFirstChild("OlympusSeam_" .. (profileName :: string) .. "_001") :: Part
		check(collar ~= nil, "complete previous-exit profile")
		check(collar:GetAttribute("PreviousExitName") == p.Name, "incoming seam provenance")
		check(collar.Color == Color3.fromRGB(p.Color[1], p.Color[2], p.Color[3]), "seam colours retained")
		check(
			math.abs(collar.Position.X - p.Offset[1]) < 0.001 and math.abs(collar.Position.Y - p.Offset[2]) < 0.001,
			"seam XY centre"
		)
		check(
			math.abs(collar.Size.X - p.Size[1]) < 0.001 and math.abs(collar.Size.Y - p.Size[2]) < 0.001,
			"seam XY size"
		)
		local expectedFace = p.Offset[3] + p.Size[3] / 2 - 220
		check(math.abs(collar.Position.Z - collar.Size.Z / 2 - expectedFace) < 0.001, "seam faces touch")
	end
	Shell.StepWater(full, 0.05)
	Shell.SetDetailVisible(full, false)
	for _, item in full:GetDescendants() do
		if item:IsA("Texture") and item.Name == "WaterFoam" then
			local speed = item:GetAttribute("FlowSpeed") :: number
			check(math.abs(item.OffsetStudsV - 0.05 * speed) < 0.001, "water hook")
		elseif item:IsA("BasePart") and CollectionService:HasTag(item, "BiomeFarDetail") then
			check(item.LocalTransparencyModifier == 1, "detail hook")
		end
	end
	check(
		(placed:GetPivot().Position - GameConfig.BossLairCenter(7) + Vector3.new(-73, 0, 132)).Magnitude < 0.001,
		"world lair-relative origin"
	)
	return {
		Passed = passed,
		FullParts = count,
		LowParts = Shell.Geometry.LowPartCount,
		FineParts = fine,
		AtomicGroups = groups,
		WaterFaces = water,
		AmbientEmitters = ambient,
		HeroGlowParts = glow,
		LowHeroGlowParts = lowGlow,
		LowFlowFaces = lowFlows,
		SeamProfileParts = #previous,
	}
end)
storage:Destroy()
assert(success, tostring(result))
return result
