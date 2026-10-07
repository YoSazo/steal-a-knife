--!strict
-- Brings knife characters' faces to life (Codex's art: Assets/KnifeCharacterAssets, parts tagged by
-- Role). Procedural, no uploaded animations: every frame it moves the face blocks directly.
--   * blink: lids grow from RestSize to SleepSize and back, every 2-5 s (sometimes twice)
--   * look: pupils (and their welded highlights) slide inside the eye whites toward the nearest
--     player's head, or dart around when nobody's close
--   * brows: up when scared, droopy when sad, one up when smug (parts named Brow_1 / Brow_2)
--   * mouth: one Mouth_<Expression> shown; "Talking" flaps it open (Mouth_Scared) and shut
--   * tears drip while Sad; "Sleeping" closes the lids
-- Drive it with attributes on the model: Expression (Happy / Scared / Sad / Smug), Sleeping, Talking.
-- Tag the model "KnifeFace". Only faces near the camera are animated (client/Lod).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Lod = require(script.Parent.Lod)

local KnifeFace = {}

type Lid = { Part: BasePart, Rest: CFrame, RestSize: Vector3, Sleep: CFrame, SleepSize: Vector3 }
type Pupil = { Part: BasePart, Rest: CFrame, MaxX: number, MaxY: number }
type Face = {
	Model: Model,
	Lids: { Lid },
	Pupils: { Pupil },
	Brows: { { Part: BasePart, Rest: CFrame, Index: number } },
	Mouths: { [string]: { BasePart } },
	Tears: { { Part: BasePart, Rest: CFrame } },
	Scale: number,
	EyeCentre: Vector3, -- model-local
	NextBlink: number,
	BlinkStart: number,
	DoubleBlink: boolean,
	Look: Vector2, -- current pupil offset (-1..1)
	LookGoal: Vector2,
	NextDart: number,
	NextFlap: number,
	MouthOpen: boolean,
	Shown: string?,
}

local faces: { [Model]: Face } = {}

local function register(model: Instance)
	if not model:IsA("Model") or faces[model] then
		return
	end
	local pivot = model:GetPivot()
	local scale = model:GetScale()
	local face: Face = {
		Model = model,
		Lids = {},
		Pupils = {},
		Brows = {},
		Mouths = {},
		Tears = {},
		Scale = scale,
		EyeCentre = Vector3.zero,
		NextBlink = os.clock() + 1 + math.random() * 3,
		BlinkStart = -1,
		DoubleBlink = false,
		Look = Vector2.zero,
		LookGoal = Vector2.zero,
		NextDart = 0,
		NextFlap = 0,
		MouthOpen = false,
		Shown = nil,
	}
	local whites: { [number]: BasePart } = {}
	local eyes, eyeSum = 0, Vector3.zero
	for _, d in model:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		local role = d:GetAttribute("Role") or d:GetAttribute("KnifeRole")
		local rel = pivot:ToObjectSpace(d.CFrame)
		if role == "EyeWhite" then
			whites[(d:GetAttribute("EyeIndex") or 1) :: number] = d
			eyes += 1
			eyeSum += rel.Position
		elseif role == "Lid" then
			local sleepSize = d:GetAttribute("SleepSize")
			local sleepOffset = d:GetAttribute("SleepOffset")
			if typeof(sleepSize) == "Vector3" and typeof(sleepOffset) == "Vector3" then
				table.insert(face.Lids, {
					Part = d,
					Rest = rel,
					RestSize = d.Size,
					Sleep = CFrame.new(sleepOffset * scale) * rel.Rotation,
					SleepSize = sleepSize * scale,
				})
			end
		elseif role == "Pupil" then
			table.insert(face.Pupils, { Part = d, Rest = rel, MaxX = 0, MaxY = 0 })
		elseif role == "Tear" then
			table.insert(face.Tears, { Part = d, Rest = rel })
		elseif type(role) == "string" and role:sub(1, 6) == "Mouth_" then
			local list = face.Mouths[role:sub(7)] or {}
			table.insert(list, d)
			face.Mouths[role:sub(7)] = list
		end
		local brow = d.Name:match("^Brow_(%d+)$")
		if brow then
			table.insert(face.Brows, { Part = d, Rest = rel, Index = tonumber(brow) :: number })
		end
	end
	-- how far each pupil may slide: inside its eye white
	for _, pupil in face.Pupils do
		local index = (pupil.Part:GetAttribute("EyeIndex") or 1) :: number
		local white = whites[index]
		if white then
			pupil.MaxX = math.max(0, (white.Size.X - pupil.Part.Size.X) / 2)
			pupil.MaxY = math.max(0, (white.Size.Y - pupil.Part.Size.Y) / 2)
		end
	end
	if eyes > 0 then
		face.EyeCentre = eyeSum / eyes
	end
	faces[model] = face
end

local function showMouth(face: Face, which: string)
	if face.Shown == which then
		return
	end
	face.Shown = which
	for name, parts in face.Mouths do
		for _, part in parts do
			part.Transparency = if name == which then 0 else 1
		end
	end
end

-- 0 = open, 1 = shut
local function blinkAmount(face: Face, now: number): number
	if now >= face.NextBlink and face.BlinkStart < 0 then
		face.BlinkStart = now
		face.DoubleBlink = math.random() < 0.2
	end
	if face.BlinkStart < 0 then
		return 0
	end
	local t = now - face.BlinkStart
	local length = if face.DoubleBlink then 0.42 else 0.16
	if t >= length then
		face.BlinkStart = -1
		face.NextBlink = now + 2 + math.random() * 3
		return 0
	end
	local phase = (t % 0.21) / 0.21 -- (one close-open is 0.16-0.21 s)
	return math.sin(math.min(phase * 1.3, 1) * math.pi)
end

local function nearestHead(at: Vector3): Vector3?
	local best, bestDist = nil, 45
	for _, player in Players:GetPlayers() do
		local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
		if head then
			local dist = (head.Position - at).Magnitude
			if dist < bestDist then
				best, bestDist = head.Position, dist
			end
		end
	end
	return best
end

local function step(face: Face, now: number, dt: number)
	local model = face.Model
	local pivot = model:GetPivot()
	local expression = (model:GetAttribute("Expression") or "Happy") :: string
	local sleeping = model:GetAttribute("Sleeping") == true

	-- Mouth: the expression's mouth, flapping open while it talks
	if model:GetAttribute("Talking") == true and not sleeping then
		if now >= face.NextFlap then
			face.MouthOpen = not face.MouthOpen
			face.NextFlap = now + 0.07 + math.random() * 0.1
		end
	else
		face.MouthOpen = false
	end
	showMouth(face, if face.MouthOpen then (if face.Mouths.Open then "Open" else "Scared") else expression)

	-- Lids: blinking, half-shut when smug or sad, shut asleep
	local held = if sleeping then 1 elseif expression == "Smug" then 0.35 elseif expression == "Sad" then 0.3 else 0
	local shut = math.max(held, blinkAmount(face, now))
	for _, lid in face.Lids do
		lid.Part.Size = lid.RestSize:Lerp(lid.SleepSize, shut)
		lid.Part.CFrame = pivot * lid.Rest:Lerp(lid.Sleep, shut)
	end

	-- Pupils: at the nearest player, else darting around (scared: darting fast)
	local eyeWorld = pivot:PointToWorldSpace(face.EyeCentre)
	local target = if not sleeping then nearestHead(eyeWorld) else nil
	if target and expression ~= "Scared" then
		local localDir = pivot:VectorToObjectSpace(target - eyeWorld)
		local flat = Vector2.new(localDir.X, localDir.Y)
		face.LookGoal = if flat.Magnitude > 0.01
			then flat.Unit * math.clamp(flat.Magnitude / math.max(localDir.Magnitude, 0.01) * 1.6, 0, 1)
			else Vector2.zero
	elseif now >= face.NextDart then
		face.LookGoal = Vector2.new(math.random() * 2 - 1, math.random() * 2 - 1)
		face.NextDart = now + (if expression == "Scared" then 0.15 + math.random() * 0.2 else 0.8 + math.random() * 2)
	end
	face.Look = face.Look:Lerp(face.LookGoal, math.min(1, dt * (if expression == "Scared" then 30 else 12)))
	for _, pupil in face.Pupils do
		pupil.Part.CFrame = pivot * CFrame.new(face.Look.X * pupil.MaxX, face.Look.Y * pupil.MaxY, 0) * pupil.Rest
	end

	-- Brows: up when scared, droopy (tilted out) when sad, one up when smug
	local s = face.Scale
	for _, brow in face.Brows do
		local raise, tilt = 0, 0
		if expression == "Scared" then
			raise = 0.05 * s
		elseif expression == "Sad" then
			raise, tilt = 0.02 * s, (if brow.Index == 1 then -14 else 14)
		elseif expression == "Smug" and brow.Index == 2 then
			raise = 0.04 * s
		end
		brow.Part.CFrame = pivot * CFrame.new(0, raise, 0) * brow.Rest * CFrame.Angles(0, 0, math.rad(tilt))
	end

	-- Tears: drip down and start again while sad
	for i, tear in face.Tears do
		if expression == "Sad" and not sleeping then
			local fall = ((now * 0.8 + i * 0.37) % 1) * 0.25 * s
			tear.Part.Transparency = 0
			tear.Part.CFrame = pivot * CFrame.new(0, -fall, 0) * tear.Rest
		else
			tear.Part.Transparency = 1
		end
	end
end

function KnifeFace.Init()
	for _, model in CollectionService:GetTagged("KnifeFace") do
		register(model)
	end
	CollectionService:GetInstanceAddedSignal("KnifeFace"):Connect(register)
	CollectionService:GetInstanceRemovedSignal("KnifeFace"):Connect(function(model)
		faces[model :: Model] = nil
	end)
	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		for model, face in faces do
			if not model.Parent then
				faces[model] = nil
				continue
			end
			if Lod.Near(model:GetPivot().Position) then
				step(face, now, dt)
			end
		end
	end)
end

return KnifeFace
