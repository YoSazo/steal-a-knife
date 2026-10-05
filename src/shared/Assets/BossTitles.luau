--!strict
-- Physical voxel reliefs with native vertex colours and the original art's source-pixel letter contours.
local InsertService = game:GetService("InsertService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Definitions = require(script.Parent.Parent.Config.BossTitles)

local BossTitleModel = {}
local FOLDER = "BossTitleTemplates"
-- Roblox's FBX import maps Blender X/+Y to -X/+Z. Correct it at the mesh pivot.
local IMPORT_ROTATION = CFrame.Angles(0, math.pi, 0)

local function configure(part: MeshPart)
	part.Anchored = true
	part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
	part.Massless, part.CastShadow = true, false
	part.Color = Color3.new(1, 1, 1)
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = 0
	-- (RenderFidelity can only be set in Studio, not by a running script)
end

function BossTitleModel.Preload()
	assert(RunService:IsServer(), "Boss titles preload on the server")
	local cached = ServerStorage:FindFirstChild(FOLDER)
	local expected = 0
	for _ in Definitions.Designs do
		expected += 1
	end
	if cached and cached:GetAttribute("Version") == Definitions.Version and #cached:GetChildren() == expected then
		return
	end
	if cached then
		cached:Destroy()
	end
	local templates = Instance.new("Folder")
	templates.Name = FOLDER
	templates:SetAttribute("Version", Definitions.Version)
	local pending = 0
	for boss, design in Definitions.Designs do
		pending += 1
		task.spawn(function()
			local downloaded: Model? = nil
			local template: Model? = nil
			local ok, result = pcall(function()
				for attempt = 1, 2 do
					local loaded, asset = pcall(InsertService.LoadAsset, InsertService, design.AssetId)
					if loaded then
						downloaded = asset :: Model
						break
					end
					if attempt == 2 then
						error(tostring(asset))
					end
					task.wait(0.5)
				end
				assert(downloaded, "No downloaded boss title")
				local built = Instance.new("Model")
				template = built
				built.Name = boss
				for _, spec in design.Chunks do
					local source = downloaded:FindFirstChild(spec.Name, true)
					assert(source and source:IsA("MeshPart"), `Missing {boss}.{spec.Name}`)
					local part = source:Clone()
					part:ClearAllChildren()
					configure(part)
					part.Size = spec.Size
					part.TextureID = ""
					part:SetAttribute("Surface", spec.Surface)
					part:SetAttribute("VoxelCount", spec.Voxels)
					part.Parent = built
				end
				built.Parent = templates
			end)
			if downloaded then
				downloaded:Destroy()
			end
			if not ok then
				if template then
					template:Destroy()
				end
				warn(`Boss title {boss} could not load: {result}`)
			end
			pending -= 1
		end)
	end
	while pending > 0 do
		task.wait()
	end
	templates.Parent = ServerStorage
end

function BossTitleModel.Build(boss: string, sign: BasePart, ribbon: BasePart): Model?
	local design = Definitions.Designs[boss]
	assert(design, `Unknown boss title {boss}`)
	local templates = ServerStorage:FindFirstChild(FOLDER)
	local template = templates and templates:FindFirstChild(boss)
	if not template or not template:IsA("Model") then
		warn(`Boss title {boss} is unavailable`)
		return nil
	end
	local model = template:Clone()
	model.Name = "BossTitles" .. boss
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("Boss", boss)
	model:SetAttribute("Stash", design.Stash)
	model:SetAttribute("Title", design.Title)
	model:SetAttribute("VoxelTitleVersion", Definitions.Version)
	local root = Instance.new("Part")
	root.Name, root.Size = "Root", Vector3.one * 0.2
	root.CFrame, root.Transparency, root.Anchored = sign.CFrame, 1, true
	root.CanCollide, root.CanQuery, root.CanTouch = false, false, false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root
	for _, spec in design.Chunks do
		local part = model:FindFirstChild(spec.Name) :: MeshPart
		local mount = if spec.Surface == "Sign" then sign else ribbon
		local referenceWidth = if spec.Surface == "Sign" then 26 else 16.12
		local referenceHeight = if spec.Surface == "Sign" then 6.5 else 16.12 / 6
		local scale = Vector3.new(mount.Size.X / referenceWidth, mount.Size.Y / referenceHeight, 1)
		part.Size = spec.Size * scale
		local offset = spec.Offset * scale - Vector3.new(0, 0, mount.Size.Z / 2)
		part.CFrame = mount.CFrame * CFrame.new(offset) * IMPORT_ROTATION
	end
	return model
end

return BossTitleModel
