--!strict
-- Cartoon outlines on the knives near you (the thick dark line Steal An Egg's models have).
-- Roblox draws at most 31 Highlights at once and the game's own effects (raid outlines, carried
-- knives, the Revolver) need some, so a small pool follows the closest display knives.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local KnifeOutlines = {}

local POOL = 18
local RANGE = 70
local OUTLINE = Color3.fromRGB(20, 16, 28)

function KnifeOutlines.Init()
	local pool: { Highlight } = {}
	for i = 1, POOL do
		local highlight = Instance.new("Highlight")
		highlight.Name = `KnifeOutline{i}`
		highlight.FillTransparency = 1
		highlight.OutlineColor = OUTLINE
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Enabled = false
		highlight.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		pool[i] = highlight
	end
	task.spawn(function()
		while true do
			task.wait(0.5)
			local camera = workspace.CurrentCamera
			local from = if camera then camera.CFrame.Position else Vector3.zero
			local near: { { Model: Model, Distance: number } } = {}
			for _, model in CollectionService:GetTagged("Spin") do
				if model:IsA("Model") and model:IsDescendantOf(workspace) then
					local blade = model:FindFirstChild("Blade")
					if blade and blade:IsA("BasePart") then
						local distance = (blade.Position - from).Magnitude
						if distance < RANGE then
							table.insert(near, { Model = model, Distance = distance })
						end
					end
				end
			end
			table.sort(near, function(a, b)
				return a.Distance < b.Distance
			end)
			for i, highlight in pool do
				local entry = near[i]
				highlight.Adornee = if entry then entry.Model else nil
				highlight.Enabled = entry ~= nil
			end
		end
	end)
end

return KnifeOutlines
