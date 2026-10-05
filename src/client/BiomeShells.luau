--!strict
-- The Codex biome shells (MapService.BuildBiomeShells) on this client: their water textures flow
-- while you're near, and their fine detail blocks hide on the Low graphics profile (phones on
-- Automatic) to keep the part count down. Everything here is local looks only.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Lod = require(script.Parent.Lod)

local BiomeShells = {}

local NEAR = 320 -- studs from a shell's middle where its water still moves

function BiomeShells.Init()
	local modules: { [string]: any } = {}
	local function moduleFor(shell: Instance): any
		local name = shell.Name
		if modules[name] == nil then
			local source = ReplicatedStorage.Shared.Assets:FindFirstChild(name)
			modules[name] = if source and source:IsA("ModuleScript") then require(source) :: any else false
		end
		return modules[name] or nil
	end
	local detailShown: { [Instance]: boolean } = {}
	local lastProfile = ""
	RunService.Heartbeat:Connect(function(dt: number)
		local showDetail = Lod.Profile ~= "Low"
		local profileChanged = Lod.Profile ~= lastProfile
		lastProfile = Lod.Profile
		for _, shell in CollectionService:GetTagged("BiomeShell") do
			if not shell:IsA("Model") or not shell:IsDescendantOf(workspace) then
				continue
			end
			local module = moduleFor(shell)
			if not module then
				continue
			end
			if profileChanged or detailShown[shell] ~= showDetail then
				detailShown[shell] = showDetail
				module.SetDetailVisible(shell, showDetail)
			end
			local pivot = shell.PrimaryPart
			local width = (shell:GetAttribute("GroundDepth") or 220) :: number
			local middle = if pivot then pivot.Position + Vector3.new(0, 0, width / 2) else nil
			if middle and Lod.Near(middle, NEAR) then
				module.StepWater(shell, dt)
			end
		end
	end)
	-- Parts streamed in later start hidden too if detail is off
	CollectionService:GetInstanceAddedSignal("BiomeFarDetail"):Connect(function(part)
		if Lod.Profile == "Low" and part:IsA("BasePart") then
			part.LocalTransparencyModifier = 1
		end
	end)
end

return BiomeShells
