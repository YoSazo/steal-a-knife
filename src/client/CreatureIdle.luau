--!strict
-- A creature boss breathes while it dozes (tag "CreatureBoss", attribute Asleep): a slow rise and
-- fall, the same job a round character's chair fidget does (client/Moves, tag "Guard") - but a
-- creature isn't a humanoid rig, so it isn't in that system. Purely cosmetic, purely client-side
-- (GuardService: "a boss at their post just stands there"); the server's own CFrame is only ever
-- touched again when it actually wakes, so this never fights it.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Lod = require(script.Parent.Lod)

local CreatureIdle = {}

local RATE = 1.1 -- breaths per second-ish
local AMOUNT = 0.22 -- studs of rise

type Sleeper = { Rest: CFrame, Seed: number }
local sleepers: { [Model]: Sleeper } = {}

local function snapshot(model: Model)
	sleepers[model] = { Rest = model:GetPivot(), Seed = math.random() * 97 }
end

local function refresh(model: Model)
	if model:GetAttribute("Asleep") == true then
		snapshot(model)
	else
		sleepers[model] = nil
	end
end

function CreatureIdle.Init()
	for _, model in CollectionService:GetTagged("CreatureBoss") do
		if model:IsA("Model") then
			refresh(model)
			model:GetAttributeChangedSignal("Asleep"):Connect(function()
				refresh(model)
			end)
		end
	end
	CollectionService:GetInstanceAddedSignal("CreatureBoss"):Connect(function(model)
		if model:IsA("Model") then
			refresh(model)
			model:GetAttributeChangedSignal("Asleep"):Connect(function()
				refresh(model)
			end)
		end
	end)
	CollectionService:GetInstanceRemovedSignal("CreatureBoss"):Connect(function(model)
		sleepers[model :: Model] = nil
	end)

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for model, sleeper in sleepers do
			if not model.Parent then
				sleepers[model] = nil
				continue
			end
			if not Lod.Near(sleeper.Rest.Position, 90) then
				continue
			end
			local breath = (math.sin(now * RATE + sleeper.Seed) * 0.5 + 0.5) * AMOUNT
			model:PivotTo(sleeper.Rest * CFrame.new(0, breath, 0))
		end
	end)
end

return CreatureIdle
