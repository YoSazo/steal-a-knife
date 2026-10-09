--!strict
-- Coffins in pens (server CoffinService, tag "Coffin": attributes Owner, Plate, Rarity, OpensAt =
-- server time, RoundsLeft): a small countdown over each one, a rattle now and then (something's in
-- there!), the seam glow pulsing, the owner's "Open now" prompt (Robux product CoffinOpen), and the
-- OPENING: glowing eyes peek out of the crack when it's about to open (1 round / 10 s left), then
-- the "CoffinPop" effect - it shakes harder and harder, the lid flies open on its hinge in a burst
-- of light with a beam up into the sky (bigger and louder the rarer it is) - and one beat later the
-- server shows the knife (CoffinService.Reveal -> Effects CoffinHatch).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Format = require(ReplicatedStorage.Shared.Format)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local Ui = require(script.Parent.Ui)
local Effects = require(script.Parent.Effects)
local Lod = require(script.Parent.Lod)

local player = Players.LocalPlayer
local Coffins = {}

local SHAKE_TIME = 0.6 -- the pop: shaking harder and harder...
local LID_TIME = 0.35 -- ...then the lid swings open
local OPEN_DEGREES = 105

type Tracked = {
	Model: Model,
	Label: TextLabel,
	Home: CFrame,
	NextRattle: number,
	Glow: { BasePart },
	Peek: { BasePart },
	Lids: { BasePart },
	LidRel: { [BasePart]: CFrame }, -- each lid piece relative to the body
	HingeRel: CFrame, -- the hinge relative to the body
	Body: BasePart,
	PopAt: number?,
	Rank: number,
	Boomed: boolean,
	Cracked: boolean, -- (lid pushed up a little: it's about to open)
}

-- 0 -> 1 with a little overshoot (the lid slams open and settles)
local function easeOutBack(t: number): number
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

function Coffins.Init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local tracked: { [Model]: Tracked } = {}

	local function add(model: Instance)
		if not model:IsA("Model") or tracked[model] then
			return
		end
		local body = model:WaitForChild("Body", 5) :: BasePart?
		if not body then
			return
		end
		local rarity = tostring(model:GetAttribute("Rarity") or "")
		local gui = Instance.new("BillboardGui")
		gui.Name = "CoffinTimer"
		gui.Size = UDim2.fromOffset(170, 44) -- (a fixed small size on screen, like Steal an Egg's "Egg 35s")
		gui.StudsOffsetWorldSpace = Vector3.new(0, body.Size.Y * 2.2 + 1.5, 0)
		gui.MaxDistance = 220
		gui.LightInfluence = 0
		gui.Adornee = body
		local title = Instance.new("TextLabel")
		title.Size = UDim2.fromScale(1, 0.45)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.FredokaOne
		title.TextScaled = true
		title.Text = `{if model:GetAttribute("Special") then "✨ " else ""}{rarity} {model:GetAttribute(
			"CharacterName"
		) or "Coffin"}`
		title.TextColor3 = Knives.RarityColors[rarity] or Color3.new(1, 1, 1)
		title.Parent = gui
		local label = Instance.new("TextLabel")
		label.Position = UDim2.fromScale(0, 0.45)
		label.Size = UDim2.fromScale(1, 0.55)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = ""
		label.Parent = gui
		for _, text in { title, label } do
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2.5
			stroke.Color = Color3.fromRGB(20, 15, 30)
			stroke.Parent = text
		end
		gui.Parent = model
		local glow, peek, lids = {}, {}, {}
		local lidRel: { [BasePart]: CFrame } = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				local role = d:GetAttribute("Role")
				if role == "Glow" then
					table.insert(glow, d)
				elseif role == "Peek" then
					d.Transparency = 1 -- (the eyes only show when it's about to open)
					table.insert(peek, d)
				elseif role == "Lid" then
					table.insert(lids, d)
					lidRel[d] = body.CFrame:ToObjectSpace(d.CFrame)
				end
			end
		end
		-- the hinge: Codex's coffins say where (LidHinge, from the floor-centre root), else the back
		-- top edge of the body
		local root = model:FindFirstChild("Root") :: BasePart?
		local hinge = model:GetAttribute("LidHinge")
		local hingeWorld = if root and typeof(hinge) == "CFrame"
			then root.CFrame * CFrame.new((hinge :: CFrame).Position * model:GetScale())
			else body.CFrame * CFrame.new(0, body.Size.Y / 2, body.Size.Z / 2)
		tracked[model] = {
			Model = model,
			Label = label,
			Home = model:GetPivot(),
			NextRattle = os.clock() + math.random() * 3,
			Glow = glow,
			Peek = peek,
			Lids = lids,
			LidRel = lidRel,
			HingeRel = body.CFrame:ToObjectSpace(hingeWorld),
			Body = body,
			PopAt = nil,
			Rank = table.find(Knives.Rarities, rarity) or 1,
			Boomed = false,
			Cracked = false,
		}
	end
	for _, model in CollectionService:GetTagged("Coffin") do
		task.spawn(add, model)
	end
	CollectionService:GetInstanceAddedSignal("Coffin"):Connect(function(model)
		task.spawn(add, model)
	end)
	CollectionService:GetInstanceRemovedSignal("Coffin"):Connect(function(model)
		tracked[model :: Model] = nil
	end)

	-- Lid at `degrees` open (rigid pieces swung round the hinge)
	local function setLid(info: Tracked, degrees: number)
		local base = info.Body.CFrame
		local swing = info.HingeRel * CFrame.Angles(math.rad(degrees), 0, 0) * info.HingeRel:Inverse()
		for _, lid in info.Lids do
			lid.CFrame = base * swing * info.LidRel[lid]
		end
	end

	-- The coffin bursts apart (Steal an Egg's shell): the lid flies up and off, the two halves of the
	-- box fall away to the sides, the pieces lie on the grass a moment and fade. Client-only debris.
	local function shatter(info: Tracked)
		local body = info.Body.CFrame
		local groups: { [string]: { BasePart } } = { Lid = {}, Left = {}, Right = {} }
		for _, d in info.Model:GetDescendants() do
			if d:IsA("BillboardGui") or d:IsA("ParticleEmitter") then
				(d :: any).Enabled = false
			end
			if not d:IsA("BasePart") or d == info.Body or d.Transparency >= 1 then
				continue
			end
			local role = d:GetAttribute("Role")
			if role ~= "Lid" and role ~= "Body" then
				d.Transparency = 1 -- (eyes, glow seam, crack: gone with the coffin)
				continue
			end
			local key = if role == "Lid"
				then "Lid"
				elseif body:PointToObjectSpace(d.Position).X < 0 then "Left"
				else "Right"
			local piece = d:Clone()
			piece:ClearAllChildren()
			table.insert(groups[key], piece)
			d.Transparency = 1
		end
		local folder = Instance.new("Folder")
		folder.Name = "CoffinDebris"
		folder.Parent = workspace
		local all: { BasePart } = {}
		for key, parts in groups do
			if #parts == 0 then
				continue
			end
			-- one solid hull per chunk (so it lands on the grass), the pieces welded to it
			local holder = Instance.new("Model")
			for _, p in parts do
				p.Parent = holder
			end
			local cf, size = holder:GetBoundingBox()
			local hull = Instance.new("Part")
			hull.Name = "Hull"
			hull.Size =
				Vector3.new(math.max(0.4, size.X * 0.8), math.max(0.3, size.Y * 0.8), math.max(0.4, size.Z * 0.8))
			hull.CFrame = cf
			hull.Transparency = 1
			hull.CanQuery, hull.CanTouch = false, false
			hull.Parent = folder
			for _, p in parts do
				p.Anchored = false
				p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
				p.Massless = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1 = hull, p
				weld.Parent = p
				p.Parent = folder
				table.insert(all, p)
			end
			holder:Destroy()
			local rank = info.Rank
			local up = body.UpVector
			local side = body.RightVector
			local push = if key == "Lid"
				then up * (22 + rank * 2) - body.LookVector * 6
				elseif key == "Left" then -side * (10 + rank) + up * 9
				else side * (10 + rank) + up * 9
			hull.AssemblyLinearVelocity = push
			hull.AssemblyAngularVelocity = Vector3.new(
				(math.random() - 0.5) * 14,
				(math.random() - 0.5) * 6,
				(if key == "Left" then 1 elseif key == "Right" then -1 else 0) * 6 + (math.random() - 0.5) * 6
			)
		end
		-- lie there a moment, then fade away
		task.delay(2.2, function()
			for _, p in all do
				TweenService:Create(p, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			end
			task.delay(0.7, function()
				folder:Destroy()
			end)
		end)
	end

	-- The moment the lid goes: a burst, a crack, a beam of light up into the sky, a shake (rarer =
	-- bigger and louder)
	local function boom(info: Tracked)
		local at = info.Body.Position
		shatter(info)
		local rarity = tostring(info.Model:GetAttribute("Rarity") or "Common")
		local color = Knives.RarityColors[rarity] or Color3.fromRGB(255, 230, 120)
		local rank = info.Rank
		Effects.Burst(at + Vector3.new(0, 2, 0), color, 30 + rank * 9, 16 + rank * 2, 0.7 + rank * 0.05)
		Effects.Burst(at + Vector3.new(0, 2, 0), Color3.new(1, 1, 1), 14 + rank * 3, 12, 0.5)
		Effects.Sound(Sounds.WoodBreak, at, 1)
		if rank >= 3 then
			Effects.Sound(Sounds.Reveal, at, 0.8)
		end
		if rank >= 5 then
			Effects.Sound(Sounds.Sting, at, 0.7)
		end
		local mine = info.Model:GetAttribute("Owner") == player.UserId
		if mine or Lod.Near(at, 70) then
			Effects.Shake(math.min(8, 1.5 + rank * 0.9), 0.35)
		end
		-- the beam of light (Neon, in its colour), taller the rarer
		local height = 30 + rank * 14
		local beam = Instance.new("Part")
		beam.Name = "CoffinBeam"
		beam.Anchored = true
		beam.CanCollide, beam.CanQuery, beam.CanTouch = false, false, false
		beam.CastShadow = false
		beam.Material = Enum.Material.Neon
		beam.Color = color
		beam.Transparency = 0.3
		beam.Size = Vector3.new(2 + rank * 0.4, 1, 2 + rank * 0.4)
		beam.CFrame = CFrame.new(at + Vector3.new(0, 1, 0))
		beam.Parent = workspace
		local grow = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(beam, grow, {
			Size = Vector3.new(beam.Size.X, height, beam.Size.Z),
			CFrame = CFrame.new(at + Vector3.new(0, height / 2, 0)),
		}):Play()
		task.delay(0.15, function()
			TweenService:Create(beam, TweenInfo.new(0.9), {
				Transparency = 1,
				Size = Vector3.new(0.2, height, 0.2),
			}):Play()
		end)
		task.delay(1.2, function()
			beam:Destroy()
		end)
	end

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local serverNow = workspace:GetServerTimeNow()
		for model, info in tracked do
			if not model.Parent then
				tracked[model] = nil
				continue
			end
			local left = ((model:GetAttribute("OpensAt") or serverNow) :: number) - serverNow
			-- the murder rounds are its clock: "2 murder rounds left" (a Common counts down in seconds)
			local rounds = model:GetAttribute("RoundsLeft")
			local close = false
			if type(rounds) == "number" then
				info.Label.Text = if rounds <= 0
					then "Opening!"
					elseif rounds == 1 then "1 murder round left"
					else `{rounds} murder rounds left`
				left = if rounds <= 0 then 0 else 999 -- (the rattle speeds up when it's about to open)
				close = rounds <= 1
			else
				info.Label.Text = if left > 0.5 then Format.Duration(left) else "Opening!"
				close = left < 10
			end
			local popping = info.PopAt ~= nil
			-- the seam pulses, faster near the end
			local speed = if close or popping then 10 else 3
			local pulse = 0.25 + 0.25 * math.sin(now * speed)
			for _, part in info.Glow do
				part.Transparency = if popping then 0 else pulse
			end
			-- the eyes in the crack: only once it's close
			for _, eye in info.Peek do
				eye.Transparency = if popping or close then math.max(0, pulse - 0.15) else 1
			end
			if popping then
				local t = now - (info.PopAt :: number)
				if t < SHAKE_TIME then
					-- shaking harder and harder
					local amount = 2 + 8 * (t / SHAKE_TIME) ^ 1.5
					model:PivotTo(
						info.Home
							* CFrame.Angles(
								math.rad((math.random() - 0.5) * amount),
								0,
								math.rad((math.random() - 0.5) * amount)
							)
							* CFrame.new(
								(math.random() - 0.5) * 0.12,
								math.abs(math.random()) * 0.1,
								(math.random() - 0.5) * 0.12
							)
					)
				else
					model:PivotTo(info.Home)
					if not info.Boomed then
						info.Boomed = true
						boom(info)
					end
					local lidT = math.clamp((t - SHAKE_TIME) / LID_TIME, 0, 1)
					setLid(info, OPEN_DEGREES * easeOutBack(lidT))
				end
				continue
			end
			-- a rattle every few seconds (all the time near the end): something wants out
			if now >= info.NextRattle then
				local strength = if close then 6 else 3
				local t = now - info.NextRattle
				if t < 0.45 then
					local shake = math.sin(t * 60) * (1 - t / 0.45)
					model:PivotTo(
						info.Home
							* CFrame.Angles(0, 0, math.rad(shake * strength))
							* CFrame.new(0, math.abs(shake) * 0.15, 0)
					)
				else
					model:PivotTo(info.Home)
					info.NextRattle = now + (if close then 0.6 else 2 + math.random() * 3)
				end
			end
			-- about to open: something inside pushes the lid up a crack and peeks out
			if close then
				info.Cracked = true
				setLid(info, 8 + 4 * math.sin(now * 5))
			elseif info.Cracked then
				info.Cracked = false
				setLid(info, 0)
			end
		end
	end)

	-- The server says a coffin is popping (CoffinService.Open): find it and start its show
	Remotes:WaitForChild("Effect").OnClientEvent:Connect(function(kind: string, userId: number, plate: number)
		if kind ~= "CoffinPop" then
			return
		end
		for model, info in tracked do
			if model:GetAttribute("Owner") == userId and model:GetAttribute("Plate") == plate and not info.PopAt then
				info.PopAt = os.clock()
				info.Home = model:GetPivot()
			end
		end
	end)

	-- "Open now" on your own coffin: buy it (Robux), for this coffin
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		local plate = prompt:GetAttribute("CoffinPlate")
		if who ~= player or type(plate) ~= "number" or prompt:GetAttribute("Owner") ~= player.UserId then
			return
		end
		Remotes:WaitForChild("CoffinTarget"):FireServer(plate)
		if Ui.Buy then
			Ui.Buy("Product", "CoffinOpen")
		end
	end)
end

return Coffins
