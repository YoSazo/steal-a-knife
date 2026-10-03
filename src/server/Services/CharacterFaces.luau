--!strict
-- Dynamic heads have a baked face and incompatible decal UVs. Disguises use a texture-free
-- classic head while retaining the original rig's dimensions, attachments and neck joints.
local CharacterFaces = {}

function CharacterFaces.Apply(head: BasePart, texture: string): BasePart
	local character = head.Parent
	assert(character, "A character face needs a parented head")
	if head:IsA("MeshPart") then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local requiresNeck = humanoid and humanoid.RequiresNeck
		if humanoid then
			humanoid.RequiresNeck = false
		end
		local classic = Instance.new("Part")
		classic.Name = "Head"
		classic.Size = head.Size
		classic.CFrame = head.CFrame
		classic.Color = head.Color
		classic.Material = Enum.Material.SmoothPlastic
		classic.Transparency = head.Transparency
		classic.Anchored = head.Anchored
		classic.CanCollide = head.CanCollide
		classic.CanQuery = head.CanQuery
		classic.CanTouch = head.CanTouch
		classic.Massless = head.Massless
		classic.CollisionGroup = head.CollisionGroup
		classic.CustomPhysicalProperties = head.CustomPhysicalProperties
		classic.CastShadow = head.CastShadow
		classic.TopSurface = Enum.SurfaceType.Smooth
		classic.BottomSurface = Enum.SurfaceType.Smooth
		for name, value in head:GetAttributes() do
			classic:SetAttribute(name, value)
		end
		for _, tag in head:GetTags() do
			classic:AddTag(tag)
		end
		-- Attachment references remain intact for both AnimationConstraints and ragdoll sockets.
		for _, child in head:GetChildren() do
			if
				child:IsA("Decal")
				or child:IsA("Texture")
				or child:IsA("SurfaceAppearance")
				or child:IsA("FaceControls")
				or child:IsA("WrapTarget")
				or child:IsA("DataModelMesh")
			then
				child:Destroy()
			else
				child.Parent = classic
			end
		end
		local mesh = Instance.new("SpecialMesh")
		mesh.Name = "ClassicHeadMesh"
		mesh.MeshType = Enum.MeshType.Head
		mesh.Parent = classic
		classic.Parent = character
		for _, joint in character:GetDescendants() do
			-- Separate branches keep Roblox's writable joint types narrowed in strict Luau.
			-- selene: allow(if_same_then_else)
			if joint:IsA("JointInstance") then
				if joint.Part0 == head then
					joint.Part0 = classic
				end
				if joint.Part1 == head then
					joint.Part1 = classic
				end
			elseif joint:IsA("WeldConstraint") then
				if joint.Part0 == head then
					joint.Part0 = classic
				end
				if joint.Part1 == head then
					joint.Part1 = classic
				end
			elseif joint:IsA("NoCollisionConstraint") then
				if joint.Part0 == head then
					joint.Part0 = classic
				end
				if joint.Part1 == head then
					joint.Part1 = classic
				end
			elseif joint:IsA("BillboardGui") and joint.Adornee == head then
				joint.Adornee = classic
			end
		end
		if character:IsA("Model") and character.PrimaryPart == head then
			character.PrimaryPart = classic
		end
		head:Destroy()
		head = classic
		if humanoid then
			humanoid.RequiresNeck = requiresNeck == true
		end
	end
	-- Reapplying an expression must never leave a second face underneath it.
	for _, child in head:GetChildren() do
		if child:IsA("Decal") or child:IsA("Texture") then
			child:Destroy()
		elseif child:IsA("SpecialMesh") then
			child.TextureId = ""
		end
	end
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Face = Enum.NormalId.Front
	face.Texture = texture
	face.Color3 = Color3.new(1, 1, 1)
	face.Parent = head
	head:SetAttribute("ClassicCharacterFace", true)
	return head
end

return CharacterFaces
