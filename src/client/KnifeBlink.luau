--!strict
-- Knife characters blink (pens and the knife in your hand): every 2-5 s at their own random moment
-- (sometimes twice), each eye's white, pupil and shine hide for a tenth of a second and a thin dark
-- line - the pixel-art closed eye - shows across the middle instead. The faces are Codex's traced
-- blocks (TraceWhite_* / TracePupil_* / TraceShine_* / TraceRim_*), so nothing about the art moves;
-- the blink only hides and shows. Models tagged "KnifeFace" (BaseService pen knives, KnifeModel held
-- characters); only near the camera (client/Lod).
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Lod = require(script.Parent.Lod)

local KnifeBlink = {}

type Eye = { Parts: { BasePart }, Lid: BasePart }
type Face = { Root: Instance, Eyes: { Eye }, NextBlink: number, Until: number, Double: boolean }

local faces: { [Instance]: Face } = {}
local LID_COLOR = Color3.fromRGB(20, 21, 32)

local function register(root: Instance)
	if faces[root] then
		return
	end
	local pupils: { BasePart } = {}
	local others: { BasePart } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name:match("^TracePupil") then
				table.insert(pupils, d)
			elseif d.Name:match("^TraceWhite") or d.Name:match("^TraceShine") or d.Name:match("^TraceRim") then
				table.insert(others, d)
			end
		end
	end
	if #pupils == 0 then
		return -- (no traced face: a stand-in knife)
	end
	local eyes: { Eye } = {}
	local groups: { { BasePart } } = {}
	for i, pupil in pupils do
		groups[i] = { pupil }
	end
	-- each white / shine / rim belongs to the nearest pupil
	for _, part in others do
		local best, bestDistance = 1, math.huge
		for i, pupil in pupils do
			local distance = (part.Position - pupil.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = i, distance
			end
		end
		table.insert(groups[best], part)
	end
	for _, group in groups do
		-- the eye's outline, from its largest piece (the white)
		local white = group[1]
		for _, part in group do
			if part.Size.X * part.Size.Y > white.Size.X * white.Size.Y then
				white = part
			end
		end
		local lid = Instance.new("Part")
		lid.Name = "BlinkLid"
		lid.Size = Vector3.new(white.Size.X, white.Size.Y * 0.18, white.Size.Z * 1.5)
		lid.CFrame = white.CFrame * CFrame.new(0, 0, -white.Size.Z) -- (just in front of the white)
		lid.Color = LID_COLOR
		lid.Material = Enum.Material.SmoothPlastic
		lid.Transparency = 1
		lid.Anchored = false
		lid.Massless = true
		lid.CanCollide, lid.CanQuery, lid.CanTouch = false, false, false
		lid.CastShadow = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = white, lid
		weld.Parent = lid
		lid.Parent = white
		for _, part in group do
			part:SetAttribute("OpenTransparency", part.Transparency)
		end
		table.insert(eyes, { Parts = group, Lid = lid :: BasePart })
	end
	faces[root] = {
		Root = root,
		Eyes = eyes,
		NextBlink = os.clock() + 1 + math.random() * 3,
		Until = 0,
		Double = false,
	}
end

local function setShut(face: Face, shut: boolean)
	for _, eye in face.Eyes do
		for _, part in eye.Parts do
			part.Transparency = if shut then 1 else (part:GetAttribute("OpenTransparency") or 0) :: number
		end
		eye.Lid.Transparency = if shut then 0 else 1
	end
end

function KnifeBlink.Init()
	local function add(root: Instance)
		task.defer(register, root) -- (once its parts are in)
	end
	for _, root in CollectionService:GetTagged("KnifeFace") do
		add(root)
	end
	CollectionService:GetInstanceAddedSignal("KnifeFace"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("KnifeFace"):Connect(function(root)
		faces[root] = nil
	end)
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for root, face in faces do
			if not root.Parent then
				faces[root] = nil
				continue
			end
			if face.Until > 0 then
				-- shut: a blink lasts 0.11 s; a double blink opens for 0.1 s and shuts again
				local t = face.Until - now
				local shut = if face.Double then (t > 0.21 or t < 0.11) else true
				if t <= 0 then
					face.Until = 0
					face.NextBlink = now + 2 + math.random() * 3
					setShut(face, false)
				else
					setShut(face, shut)
				end
			elseif now >= face.NextBlink then
				local anchor = face.Eyes[1] and face.Eyes[1].Lid
				if anchor and Lod.Near(anchor.Position, 120) then
					face.Double = math.random() < 0.2
					face.Until = now + (if face.Double then 0.32 else 0.11)
					setShut(face, true)
				else
					face.NextBlink = now + 1 + math.random() * 2
				end
			end
		end
	end)
end

return KnifeBlink
