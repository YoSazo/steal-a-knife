--!strict
-- Decode the uploaded mesh assets in Studio and verify actual front-face canvas coordinates.
return function(lairs: { Model })
	local service = game:GetService("AssetService")
	local meshes = 0
	local vertices = 0
	local maximumError = 0
	for _, lair in lairs do
		for _, model in lair:GetChildren() do
			if not model:IsA("Model") or not model:GetAttribute("VoxelTitleVersion") then
				continue
			end
			for _, part in model:GetChildren() do
				if not part:IsA("MeshPart") then
					continue
				end
				local mount = lair:FindFirstChild(part:GetAttribute("Surface") :: string) :: BasePart
				local mesh = service:CreateEditableMeshAsync(Content.fromUri(part.MeshId))
				assert(mesh, "Could not decode uploaded title mesh")
				local scale = part.Size / part.MeshSize
				local samples = 0
				local faces = mesh:GetFaces()
				for index = 1, #faces, 19 do
					local face = faces[index]
					local normals = mesh:GetFaceNormals(face)
					local normal = mesh:GetNormal(normals[1])
					if normal.Z < 0.99 then
						continue
					end
					local orientation = mount.CFrame:VectorToObjectSpace(part.CFrame:VectorToWorldSpace(normal))
					assert(orientation.Z < -0.99, "Letter faces point away from the runway")
					local points = mesh:GetFaceVertices(face)
					local uvs = mesh:GetFaceUVs(face)
					for i, point in points do
						local position = mesh:GetPosition(point) * scale
						local localPosition = mount.CFrame:PointToObjectSpace(part.CFrame:PointToWorldSpace(position))
						local uv = mesh:GetUV(uvs[i])
						local expected = Vector2.new((0.5 - uv.X) * mount.Size.X, (0.5 - uv.Y) * mount.Size.Y)
						local errorDistance = (Vector2.new(localPosition.X, localPosition.Y) - expected).Magnitude
						maximumError = math.max(maximumError, errorDistance)
						assert(errorDistance < 0.0003, `Canvas UV mismatch in {part.Name}: {errorDistance}`)
						assert(
							localPosition.Z <= -0.279 and localPosition.Z >= -0.761,
							"Letter relief has no physical depth"
						)
						vertices += 1
					end
					samples += 1
					if samples >= 24 then
						break
					end
				end
				mesh:Destroy()
				-- Side/back-only chunks still have native painted voxel geometry.
				meshes += 1
			end
		end
	end
	assert(meshes > 0, "No uploaded voxel chunks were verified")
	return { Meshes = meshes, FrontVertices = vertices, MaximumCanvasError = maximumError }
end
