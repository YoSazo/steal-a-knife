--!strict
-- Run after the eight physical titles have been mounted; accepts the fresh config fixture.
return function(lairs: { Model }, definitions: any)
	local checks = 0
	local meshes = 0
	local voxels = 0
	local function check(condition: boolean, message: string)
		assert(condition, message)
		checks += 1
	end
	check(#lairs == 8, "Expected all eight boss lairs")
	for _, lair in lairs do
		local sign = lair:FindFirstChild("Sign") :: BasePart
		local ribbon = lair:FindFirstChild("SignRibbon") :: BasePart
		check(sign ~= nil and ribbon ~= nil, `Missing mounts in {lair.Name}`)
		check(sign.Size == Vector3.new(26, 6.5, 0.2), "Sign canvas dimensions changed")
		check((ribbon.Size - Vector3.new(16.12, 16.12 / 6, 0.2)).Magnitude < 0.00001, "Ribbon canvas changed")
		local titles: Model? = nil
		for _, child in lair:GetChildren() do
			if child:IsA("Model") and child:GetAttribute("VoxelTitleVersion") then
				check(titles == nil, "Duplicate boss title model")
				titles = child
			end
		end
		check(titles ~= nil, `Missing physical titles in {lair.Name}`)
		local model = titles :: Model
		local boss = model:GetAttribute("Boss") :: string
		local design = definitions.Designs[boss]
		check(model:GetAttribute("Stash") == design.Stash, "Stash wording changed")
		check(model:GetAttribute("Title") == design.Title, "Boss title wording changed")
		check(model.PrimaryPart ~= nil and model:GetPivot() == sign.CFrame, "Title origin left the sign mount")
		check(model.ModelStreamingMode == Enum.ModelStreamingMode.Atomic, "Title can stream as incomplete letters")
		check(model:FindFirstChildWhichIsA("SurfaceGui", true) == nil, "Physical titles contain a SurfaceGui")
		for _, mount in { sign, ribbon } do
			for _, child in mount:GetDescendants() do
				if child:IsA("SurfaceGui") then
					check(not child.Enabled, "Legacy 2D art is still showing")
				end
			end
		end
		for _, spec in design.Chunks do
			local part = model:FindFirstChild(spec.Name) :: MeshPart
			check(part ~= nil and part:IsA("MeshPart"), `Missing cuboid chunk {boss}.{spec.Name}`)
			check(
				part.Anchored and not part.CanCollide and not part.CanQuery and not part.CanTouch,
				"Title affects gameplay physics"
			)
			check(part.MeshId ~= "", "No uploaded mesh")
			check(part.TextureID == "", "A title still uses an image texture")
			check((part.Size - spec.Size).Magnitude < 0.00001, "Cuboid chunk dimensions changed")
			local mount = if spec.Surface == "Sign" then sign else ribbon
			local localFrame = mount.CFrame:ToObjectSpace(part.CFrame)
			check(
				(localFrame.Position - (spec.Offset - Vector3.new(0, 0, 0.1))).Magnitude < 0.0002,
				"Chunk moved away from original canvas"
			)
			check(localFrame.LookVector.Z > 0.999, "Imported front/back orientation is wrong")
			meshes += 1
			voxels += spec.Voxels
		end
		local prompts = 0
		for _, child in lair:GetDescendants() do
			if child:IsA("ProximityPrompt") and child.ActionText == "Steal" then
				prompts += 1
			end
		end
		check(prompts == 5, "Steal pedestal count changed")
	end
	return { Checks = checks, Models = #lairs, Meshes = meshes, Voxels = voxels }
end
