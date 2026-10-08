--!strict
-- A creature boss sleeping (tag "CreatureBoss", attribute Asleep): its body slowly rises and falls
-- with each deep breath, its head nods heavily, its tail sways - the same job a round character's
-- chair fidget does (client/Moves). Purely cosmetic and client-side: the server leaves a sleeping
-- boss's parts alone until it wakes (GuardService), so this never fights it. The joints come from
-- the creature's geometry (Config/ToyGeometry/<model attribute Creature>).
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Lod = require(script.Parent.Lod)

local CreatureIdle = {}

local RATE = 0.9 -- breaths per second-ish (slow, heavy)
local RISE = 0.35 -- studs the body rises per breath (times the creature's scale)
local NOD = math.rad(7) -- the head sinks and lifts with each breath
local SWAY = math.rad(14) -- the tail sways slowly from side to side

type Piece = { Part: BasePart, Offset: CFrame, Group: string }
type Sleeper = {
	Rest: CFrame,
	Seed: number,
	Pieces: { Piece },
	Head: Vector3?,
	Tail: Vector3?,
	Scale: number,
	Zs: { TextLabel }, -- the Zzz BillboardGui's "Z1".."Z3" (GuardService), animated below
}
local sleepers: { [Model]: Sleeper } = {}
local geometry: { [string]: any } = {}

local function joints(model: Model): any
	local name = model:GetAttribute("Creature")
	if type(name) ~= "string" then
		return nil
	end
	if geometry[name] == nil then
		local source = ReplicatedStorage.Shared.Config.ToyGeometry:FindFirstChild(name)
		geometry[name] = if source and source:IsA("ModuleScript") then (require(source) :: any).Joints else false
	end
	return geometry[name] or nil
end

local function snapshot(model: Model)
	local rest = model:GetPivot()
	local scale = model:GetScale()
	local pieces: { Piece } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local group = d:GetAttribute("JointGroup")
			table.insert(pieces, {
				Part = d,
				Offset = rest:ToObjectSpace(d.CFrame),
				Group = if type(group) == "string" then group else "",
			})
		end
	end
	local data = joints(model)
	sleepers[model] = {
		Rest = rest,
		Seed = math.random() * 97,
		Pieces = pieces,
		Head = if data and data.Head then data.Head.Asleep.Position * scale else nil,
		Tail = if data and data.Tail then data.Tail.Asleep.Position * scale else nil,
		Scale = scale,
		Zs = {},
	}
end

-- The Zzz gui's Z labels (the server may add the gui a moment after the creature lies down)
local function findZs(model: Model, sleeper: Sleeper)
	local head = model:FindFirstChild("Head")
	local gui = head and head:FindFirstChild("Zzz")
	if gui then
		for i = 1, 3 do
			local z = gui:FindFirstChild(`Z{i}`)
			if z and z:IsA("TextLabel") then
				table.insert(sleeper.Zs, z)
			end
		end
	end
end

-- Steal An Egg's sleeping Z's: each one comes up out of the top of the body small, grows as it
-- drifts up and a little to the side, then fades away; three of them a third of a loop apart
local Z_LOOP = 2.4 -- seconds for one Z to rise and fade
local function animateZs(zs: { TextLabel }, now: number, seed: number)
	for i, z in zs do
		local p = ((now + seed) / Z_LOOP + (i - 1) / #zs) % 1
		local fade = if p < 0.15 then 1 - p / 0.15 elseif p > 0.7 then (p - 0.7) / 0.3 else 0
		z.Position = UDim2.fromScale(0.3 + 0.35 * p + math.sin(p * math.pi * 2) * 0.05, 1 - 0.8 * p)
		z.TextSize = 16 + 26 * p
		z.Rotation = -18 + 16 * p
		z.TextTransparency = fade
		local stroke = z:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = fade
		end
	end
end

local function refresh(model: Model)
	if model:GetAttribute("Asleep") == true then
		task.defer(snapshot, model) -- (after the server has laid it down)
	else
		sleepers[model] = nil
	end
end

local function watch(model: Instance)
	if model:IsA("Model") then
		refresh(model)
		model:GetAttributeChangedSignal("Asleep"):Connect(function()
			refresh(model)
		end)
	end
end

function CreatureIdle.Init()
	for _, model in CollectionService:GetTagged("CreatureBoss") do
		watch(model)
	end
	CollectionService:GetInstanceAddedSignal("CreatureBoss"):Connect(watch)
	CollectionService:GetInstanceRemovedSignal("CreatureBoss"):Connect(function(model)
		sleepers[model :: Model] = nil
	end)

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for model, sleeper in sleepers do
			if not model.Parent or model:GetAttribute("Asleep") ~= true then
				sleepers[model] = nil
				continue
			end
			if #sleeper.Zs == 0 then
				findZs(model, sleeper)
			end
			if #sleeper.Zs > 0 and Lod.Near(sleeper.Rest.Position, 110) then
				animateZs(sleeper.Zs, now, sleeper.Seed)
			end
			if not Lod.Near(sleeper.Rest.Position, 120) then
				continue
			end
			local breath = math.sin(now * RATE + sleeper.Seed) * 0.5 + 0.5
			local base = sleeper.Rest * CFrame.new(0, breath * RISE * sleeper.Scale, 0)
			local head = sleeper.Head
			local tail = sleeper.Tail
			local nod = CFrame.Angles((breath - 0.5) * NOD, 0, 0)
			local sway = CFrame.Angles(0, math.sin(now * 0.7 + sleeper.Seed) * SWAY, 0)
			for _, piece in sleeper.Pieces do
				if not piece.Part.Parent then
					continue
				end
				if piece.Group == "Head" and head then
					piece.Part.CFrame = base * CFrame.new(head) * nod * CFrame.new(-head) * piece.Offset
				elseif piece.Group == "Tail" and tail then
					piece.Part.CFrame = base * CFrame.new(tail) * sway * CFrame.new(-tail) * piece.Offset
				else
					piece.Part.CFrame = base * piece.Offset
				end
			end
		end
	end)
end

return CreatureIdle
