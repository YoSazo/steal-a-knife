--!strict
-- The biome bosses (the file keeps its old name: powers, combat and raids talk to "guards").
--
-- Every zone of the runway has one boss: a round character (Frank, Ivy, Sam, Leo, Ruby, Kate, Zoe,
-- Nick - the same people you turn into in murder rounds) standing in front of a wall of knives in
-- their lair. They never touch you while you look. Steal a knife off the wall and they come for
-- you, all the way back to the plaza; if they're already chasing someone, their shadow comes
-- instead, so every thief has their own chaser. Caught = they snatch the knife back (it goes
-- straight back on the wall) and it hurts. Make it home and the empty slot restocks a little later
-- with a freshly rolled knife (rare mutations get announced to the server).
--
-- Deeper bosses are faster (GuardSpeed) and hit harder (Damage). They only catch you by touch: knife
-- throws (Throws) are off (GameConfig.GuardThrow.Enabled). Hitting a
-- chaser with your knife staggers it: better knives stagger longer (Damage vs the zone's Health).
-- Bosses are anchored and moved by the server, so nobody can push or fling them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local InsertService = game:GetService("InsertService")

local AnimLibrary = require(ReplicatedStorage.Shared.AnimLibrary)
local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local KnifeAura = require(ReplicatedStorage.Shared.KnifeAura)
local SignTheme = require(ReplicatedStorage.Shared.SignTheme)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local CoffinModel = require(ReplicatedStorage.Shared.CoffinModel)
local KnifeHaze = require(ReplicatedStorage.Shared.KnifeHaze)
local PenMode = require(ReplicatedStorage.Shared.PenMode)
local ToyBlockModel = require(ReplicatedStorage.Shared.ToyBlockModel)
local BossTitleModel = require(ReplicatedStorage.Shared.BossTitleModel)
local BossChairs = require(ReplicatedStorage.Shared.Config.BossChairs)
local BossChairMotion = require(ReplicatedStorage.Shared.BossChairMotion)
local BossSleepFaces = require(ReplicatedStorage.Shared.Config.BossSleepFaces)
local BossChairModel = require(ReplicatedStorage.Shared.Assets.BossChairModel)

-- Retained for side-by-side verification; production lair titles use physical voxel meshes.
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local Offers = require(script.Parent.Offers)
local ManorDecor = require(script.Parent.ManorDecor)
local Disguises = require(script.Parent.Disguises)
local HedgeHound = require(ReplicatedStorage.Shared.Assets.HedgeHound)
local Toy = require(ReplicatedStorage.Shared.Toy)
local FlowerToad = require(ReplicatedStorage.Shared.Assets.FlowerToad)
local BoneWolf = require(ReplicatedStorage.Shared.Assets.BoneWolf)
local GoldScorpion = require(ReplicatedStorage.Shared.Assets.GoldScorpion)
local LavaSalamander = require(ReplicatedStorage.Shared.Assets.LavaSalamander)
local GoldenGriffin = require(ReplicatedStorage.Shared.Assets.GoldenGriffin)
local SkyPegasus = require(ReplicatedStorage.Shared.Assets.SkyPegasus)
local VoidBeast = require(ReplicatedStorage.Shared.Assets.VoidBeast)
-- Zone bosses that are creatures instead of round characters (GameConfig.Zones[i].Creature).
-- Only the Courtyard's hedge hound exists so far; the rest stay round characters until it's
-- approved.
local CREATURE_MODULES: { [string]: any } = {
	HedgeHound = HedgeHound,
	FlowerToad = FlowerToad,
	BoneWolf = BoneWolf,
	GoldScorpion = GoldScorpion,
	LavaSalamander = LavaSalamander,
	GoldenGriffin = GoldenGriffin,
	SkyPegasus = SkyPegasus,
	VoidBeast = VoidBeast,
}
-- Each creature's joint data (Config/ToyGeometry/<Name>), for the real run cycle below: Codex's
-- SetRunPhase is "a reference pose sampler, not a completed animation" by design - this is the
local creatureGeometry: { [string]: any } = {}
local function geometryFor(name: string): any
	if creatureGeometry[name] == nil then
		local source = ReplicatedStorage.Shared.Config.ToyGeometry:FindFirstChild(name)
		creatureGeometry[name] = if source and source:IsA("ModuleScript") then require(source) :: any else false
	end
	return creatureGeometry[name] or nil
end
local MapService = require(script.Parent.MapService)
local Ragdoll = require(script.Parent.Ragdoll)
local StealService = require(script.Parent.StealService)
local Analytics = require(script.Parent.Analytics)
local StuckKnives = require(script.Parent.StuckKnives)

type ZoneConfig = {
	Rarity: string,
	Creature: string?, -- a creature boss instead of a round character (CREATURE_MODULES)
	Title: string,
	Boss: string,
	BossTitle: string,
	BossWear: { string },
	Restock: number,
	GuardSpeed: number,
	Health: number,
	Damage: number,
	Throws: boolean?,
	Color: Color3,
}

type Slot = {
	Index: number,
	Item: string?, -- on the wall right now
	Out: boolean, -- someone is running off with it
	RestockAt: number?, -- empty after a successful theft until this time
	Spot: CFrame, -- where the knife floats
	Pad: BasePart,
	Plaque: Part, -- the plate behind it (tinted with the knife's colour)
	Frame: Part, -- the thin glowing border around the plate
	Display: Model?,
	Prompt: ProximityPrompt,
}

type Boss = {
	Index: number,
	Zone: MapService.Zone,
	Config: ZoneConfig,
	Name: string,
	Post: CFrame, -- where they stand guard, facing the plaza
	Folder: Model, -- the lair
	Slots: { Slot },
	Guard: Guard, -- the boss in person
}

export type Guard = {
	Model: Model,
	Zone: MapService.Zone,
	Config: ZoneConfig,
	Boss: Boss,
	IsShadow: boolean,
	Position: Vector3,
	Target: Player?, -- the thief being chased
	Returning: boolean, -- walking back to the post (shadows vanish instead)
	AlertUntil: number,
	WakeStart: number,
	WakeUntil: number, -- still getting out of the chair (doesn't turn yet)
	InChair: boolean, -- this wake-up starts in the chair (slides out of it)
	ExitAt: Vector3?, -- walk here first (out in front of the chair, clear of the torch post)
	SitStart: number?, -- back home: backing into the chair
	Alert: BillboardGui,
	Dead: boolean, -- (kept for the powers' checks; bosses never die)
	KnifeName: string,
	LastAttack: number,
	ThrowReadyAt: number,
	WindupUntil: number,
	BusyUntil: number, -- staggered / stabbing / trapped
	StaggerImmuneUntil: number,
	Tracks: { [string]: AnimationTrack },
	Playing: string?,
	Hound: any?, -- the creature module (Assets/HedgeHound), nil for a round-character boss
	FootOffset: number, -- added to Y when moving freely: 0 for a creature (its Root is already
	-- at floor level), HEIGHT for a round character (whose root is mid-body)
	HoundPhase: number, -- accumulated run-cycle phase (Assets.SetRunPhase)
}

type Projectile = {
	Model: Model,
	Position: Vector3,
	Direction: Vector3,
	Traveled: number,
	Damage: number,
	Target: Player,
	Speed: number?, -- studs/s (faster than the target runs)
	Zone: number, -- the throwing boss's zone (deeper = a bigger knock)
}

local GuardService = {}

local HEIGHT = 3 -- a boss's HumanoidRootPart centre above the floor (probe rig at BossScale, Init)
local PERSON_HEIGHT = 3 -- the same for a normal-size rig (burglars use it: RootHeight)
local PLATFORM = 0.8 -- lair floor height
local ANIMATIONS: { [string]: string } = {
	Idle = "rbxassetid://507766388",
	Walk = "rbxassetid://507777826",
	Run = "rbxassetid://507767714",
}

local nearestBoss: (Vector3) -> { Boss: Boss, Position: Vector3 }?
local emptySlots: (Boss, number) -> number
local bosses: { Boss } = {}
local chasers: { Guard } = {} -- every guard currently chasing or walking back (bosses and shadows)
local guardByModel: { [Model]: Guard } = {}
local projectiles: { Projectile } = {}
local folder: Folder
local projectileFolder: Folder
local rng = Random.new()

local function now(): number
	return os.clock()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function block(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function billboard(adornee: BasePart, size: UDim2, offset: Vector3, maxDistance: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	gui.Adornee = adornee
	gui.Parent = adornee
	return gui
end

local function text(parent: Instance, content: string, color: Color3, position: UDim2, size: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Text = content
	label.Parent = parent
	return label
end

-- Rigs -----------------------------------------------------------------------------------------

local function loadTracks(rig: Model): { [string]: AnimationTrack }
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	local animator: Animator = humanoid:FindFirstChildOfClass("Animator")
		or (function()
			local created = Instance.new("Animator")
			created.Parent = humanoid
			return created
		end)()
	local tracks: { [string]: AnimationTrack } = {}
	for key, id in ANIMATIONS do
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(animator.LoadAnimation, animator, animation)
		if ok then
			track.Looped = true
			tracks[key] = track
		end
	end
	return tracks
end

local function animate(guard: Guard, key: string, speed: number?)
	local track = guard.Tracks[key]
	if guard.Playing ~= key then
		local old = guard.Playing and guard.Tracks[guard.Playing]
		if old then
			old:Stop(0.2)
		end
		if track then
			track:Play(0.2)
		end
		guard.Playing = key
	end
	if track and speed then
		track:AdjustSpeed(speed)
	end
end

-- A creature boss (Steal An Egg style): Codex's model, plus the same name tag / "!" alert every
-- round character gets, built around a synthetic "Head" anchor (the creature has no part literally
-- named "Head" - its head parts share JointGroup "Head" instead) so the shared tag/alert/Zzz code
-- keeps working unchanged.
local function buildHoundRig(config: ZoneConfig, shadow: boolean): Model
	local creature = CREATURE_MODULES[config.Creature :: string]
	local model = creature.Build(nil, CFrame.identity, "Asleep")
	-- Sized by zone (GameConfig.CreatureHeight): SetPose and the run cycle work at any scale
	local rank = table.find(Knives.Rarities, config.Rarity) or 1
	local height = GameConfig.CreatureHeight.First + (rank - 1) * GameConfig.CreatureHeight.Step
	model:ScaleTo(height / ((model:GetAttribute("StandHeight") or height) :: number))
	model:SetAttribute("BossHeight", height)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			if part.Name:match("^Nostril") then
				-- (the griffin's and pegasus's nostrils read as a second pair of eyes on the beak tip:
				-- a tiny extra head)
				part:Destroy()
			elseif part.Material ~= Enum.Material.Neon and math.min(part.Size.X, part.Size.Y, part.Size.Z) >= 0.8 then
				-- The toy look, like every wall and floor: studs on its sides and top (after scaling,
				-- so they're the same size as everywhere else). Eyes and tiny bits stay plain.
				local material = part.Material
				Toy.Dress(part, Toy.Sides, 1, 0)
				part.Material = material
			end
		end
	end
	model.Name = if shadow then `{config.Boss}Shadow` else config.Boss
	-- A menacing aura in its zone's colour while it hunts you (setAsleep switches it), like the big
	-- games' bosses
	local torso = model:FindFirstChild("Torso") :: BasePart?
	if torso then
		local aura = Instance.new("ParticleEmitter")
		aura.Name = "HuntAura"
		aura.Texture = "rbxasset://textures/particles/fire_main.dds"
		aura.Color = ColorSequence.new(config.Color:Lerp(Color3.fromRGB(255, 40, 90), 0.5), config.Color)
		aura.LightEmission = 0.8
		aura.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 6),
			NumberSequenceKeypoint.new(1, 1),
		})
		aura.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		})
		aura.Lifetime = NumberRange.new(0.6, 1)
		aura.Rate = 40
		aura.Speed = NumberRange.new(4, 8)
		aura.SpreadAngle = Vector2.new(60, 60)
		aura.Acceleration = Vector3.new(0, 10, 0)
		aura.Enabled = false
		aura.Parent = torso
	end
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	-- Idle breathing while asleep is purely cosmetic (client/CreatureIdle), the same way a
	-- round character's chair fidget is - the server never ticks a guard at its post.
	model:AddTag("CreatureBoss")
	model:SetAttribute("Creature", config.Creature)
	local headCore = model:FindFirstChild("HeadCore") :: BasePart
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.one * 0.05
	head.Transparency = 1
	head.Anchored = true
	head.CanCollide, head.CanQuery, head.CanTouch, head.CastShadow = false, false, false, false
	head.CFrame = headCore.CFrame
	-- A real (if tiny) member of the "Head" joint group: Assets.SetPose then poses it with the
	-- rest of the head automatically, instead of it being an unposed stray part.
	head:SetAttribute("JointGroup", "Head")
	head:SetAttribute("RestOffset", Vector3.zero)
	head:SetAttribute("RestSize", Vector3.one * 0.05)
	head:SetAttribute("RestAngle", 0)
	head:SetAttribute("PoseVisibility", "Both")
	head.Parent = model
	local pool = Knives.ByRarity[config.Rarity]
	model:SetAttribute("KnifeName", pool[#pool].Name)
	local tag = billboard(head, UDim2.fromScale(6, 1.6), Vector3.new(0, 4.4, 0), 60)
	tag.Name = "BossTag"
	tag.Enabled = shadow == true
	-- A creature is called what it is ("HEDGE HOUND"), with its biome under it - not the old
	-- person's name and job ("FRANK / The Groundskeeper") from when bosses were people
	local monster = ((config :: any).Monster or config.Boss) :: string
	text(
		tag,
		if shadow then `{monster:upper()}'S SHADOW` else monster:upper(),
		config.Color:Lerp(Color3.new(1, 1, 1), 0.2),
		UDim2.fromScale(0, 0),
		UDim2.fromScale(1, 0.58)
	)
	text(tag, config.Title, Color3.fromRGB(235, 230, 240), UDim2.fromScale(0, 0.58), UDim2.fromScale(1, 0.42))
	local alert = billboard(head, UDim2.fromScale(3, 3), Vector3.new(0, 6.6, 0), 200)
	alert.Name = "Alert"
	alert.Enabled = false
	text(alert, "!", Color3.fromRGB(255, 60, 60), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
	if shadow then
		-- A shadow: a dark, nearly solid silhouette in the zone's colour (eyes stay bright - a
		-- glow in the dark reads better than darkening them)
		local dark = config.Color:Lerp(Color3.new(0, 0, 0), 0.55)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 and d.Material ~= Enum.Material.Neon then
				d.Color = dark
			end
		end
		local glow = Instance.new("Highlight")
		glow.Name = "ShadowGlow"
		glow.FillColor = config.Color
		glow.FillTransparency = 0.7
		glow.OutlineColor = config.Color:Lerp(Color3.new(1, 1, 1), 0.3)
		glow.OutlineTransparency = 0
		glow.DepthMode = Enum.HighlightDepthMode.Occluded
		glow.Parent = model
	end
	return model
end

-- A boss character: their round outfit plus their signature pieces, the zone's best knife in hand,
-- a glow in the zone's colour, and their name over their head
local function buildRig(config: ZoneConfig, shadow: boolean): Model
	local rig = Disguises.BuildCharacter(config.Boss, config.BossWear)
	-- Big enough to spot across the runway on a phone (HEIGHT is measured on a rig this size)
	rig:ScaleTo(GameConfig.BossScale)
	rig.Name = if shadow then `{config.Boss}Shadow` else config.Boss
	rig.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	rig:AddTag("Guard") -- clients animate these (fidgets, stabs, throws)
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.EvaluateStateMachine = false
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			-- CanQuery stays on so thrown knives can hit them
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	rig.PrimaryPart = root

	-- The zone's best knife, held ready
	local pool = Knives.ByRarity[config.Rarity]
	local knifeName = pool[#pool].Name
	local rightHand = rig:FindFirstChild("RightHand") :: BasePart
	local knife = KnifeModel.Build(knifeName, false)
	KnifeModel.FitLength(knife, 2.6)
	knife:PivotTo(rightHand.CFrame * CFrame.new(0, -0.3, 0) * CFrame.Angles(math.rad(-90), 0, 0))
	for _, d in knife:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rightHand
	weld.Part1 = knife.PrimaryPart :: BasePart
	weld.Parent = knife.PrimaryPart
	knife.Name = "Knife"
	knife.Parent = rig
	rig:SetAttribute("KnifeName", knifeName)

	-- A boss aura: sparks in the zone's colour and a soft light
	local torso = rig:FindFirstChild("UpperTorso") :: BasePart?
	if torso then
		local aura = Instance.new("ParticleEmitter")
		aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		aura.Color = ColorSequence.new(config.Color, Color3.new(1, 1, 1))
		aura.LightEmission = 1
		aura.Size = NumberSequence.new(0.35, 0)
		aura.Lifetime = NumberRange.new(0.8, 1.4)
		aura.Rate = 10
		aura.Speed = NumberRange.new(1, 2.5)
		aura.SpreadAngle = Vector2.new(180, 180)
		aura.Parent = torso
		local light = Instance.new("PointLight")
		light.Color = config.Color
		light.Range = 14
		light.Brightness = 1.5
		light.Parent = torso
	end

	local head = rig:FindFirstChild("Head") :: BasePart
	-- Name + title (visible from across the zone)
	local tag = billboard(head, UDim2.fromScale(6, 1.6), Vector3.new(0, 3, 0), 60) -- (studs)
	tag.Name = "BossTag"
	-- At home the lair sign and ribbon already name them; the tag only shows while they're out
	-- chasing (shadows always have theirs)
	tag.Enabled = shadow == true
	text(
		tag,
		if shadow then `{config.Boss:upper()}'S SHADOW` else config.Boss:upper(),
		config.Color:Lerp(Color3.new(1, 1, 1), 0.2),
		UDim2.fromScale(0, 0),
		UDim2.fromScale(1, 0.58)
	)
	text(tag, config.BossTitle, Color3.fromRGB(235, 230, 240), UDim2.fromScale(0, 0.58), UDim2.fromScale(1, 0.42))
	-- "!" when they start a chase
	local alert = billboard(head, UDim2.fromScale(3, 3), Vector3.new(0, 5.6, 0), 200)
	alert.Name = "Alert"
	alert.Enabled = false
	text(alert, "!", Color3.fromRGB(255, 60, 60), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))

	if shadow then
		-- A shadow: the same person as a dark, nearly solid silhouette in the zone's colour with a
		-- glowing outline (ForceField was so see-through you could miss them chasing you)
		local dark = config.Color:Lerp(Color3.new(0, 0, 0), 0.55)
		for _, d in rig:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				d.Material = Enum.Material.SmoothPlastic
				d.Color = dark
				d.Transparency = 0.15
			elseif d:IsA("Decal") then
				d.Transparency = 0.2
			elseif d:IsA("Clothing") then
				d:Destroy()
			end
		end
		local glow = Instance.new("Highlight")
		glow.Name = "ShadowGlow"
		glow.FillColor = config.Color
		glow.FillTransparency = 0.7
		glow.OutlineColor = config.Color:Lerp(Color3.new(1, 1, 1), 0.3)
		glow.OutlineTransparency = 0
		glow.DepthMode = Enum.HighlightDepthMode.Occluded
		glow.Parent = rig
	end
	return rig
end

-- Asleep in the chair at the post: the client poses the rig seated with its head down
-- (client/Moves), and a 💤 floats over it. Waking = a thief took a knife.
local function setAsleep(guard: Guard, asleep: boolean)
	guard.Model:SetAttribute("Asleep", asleep)
	local huntAura = guard.Model:FindFirstChild("HuntAura", true) :: ParticleEmitter?
	if huntAura then
		huntAura.Enabled = not asleep
	end
	if guard.Hound and asleep then
		-- (waking is a gradual blend over the step() alert window, not an instant snap - see
		-- the "t < guard.AlertUntil" branch below)
		guard.Hound.SetPose(guard.Model, "Asleep")
	end
	local head = guard.Model:FindFirstChild("Head")
	-- Eyes shut while dozing (Config/BossSleepFaces), their own face back when they wake
	local face = head and head:FindFirstChild("face") :: Decal?
	local sleepFace = BossSleepFaces[guard.Boss.Name]
	if face and sleepFace and sleepFace ~= "" then
		if face:GetAttribute("AwakeFace") == nil then
			face:SetAttribute("AwakeFace", face.Texture)
		end
		face.Texture = if asleep then sleepFace else face:GetAttribute("AwakeFace") :: string
	end
	local zzz = head and head:FindFirstChild("Zzz") :: BillboardGui?
	if zzz then
		zzz.Enabled = asleep
	elseif head and asleep then
		local gui = Instance.new("BillboardGui")
		gui.Name = "Zzz"
		gui.Size = UDim2.fromScale(2.4, 2.4) -- (studs)
		gui.StudsOffset = Vector3.new(1.6, 2.2, 0)
		gui.MaxDistance = 140
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Text = "💤"
		label.Parent = gui
		if guard.Hound then
			-- A giant creature: Steal An Egg's sleeping Z's - three of them rise out of the top of its
			-- body, grow, drift up and fade, on a loop (client/CreatureIdle animates "Z1".."Z3"). A
			-- fixed small size on screen (pixels, not studs), its bottom just inside the body's top.
			label:Destroy()
			gui.Size = UDim2.fromOffset(110, 170)
			gui.SizeOffset = Vector2.new(0.25, 0.5) -- (the gui grows up and a little to the side)
			local cf, size = guard.Model:GetBoundingBox()
			local top = cf.Position.Y + size.Y / 2
			gui.StudsOffset = Vector3.zero
			gui.StudsOffsetWorldSpace =
				Vector3.new(0, top - (head :: BasePart).Position.Y - 0.6 * guard.Model:GetScale(), 0)
			gui.MaxDistance = 260
			gui.ClipsDescendants = false
			for i = 1, 3 do
				local z = Instance.new("TextLabel")
				z.Name = `Z{i}`
				z.AnchorPoint = Vector2.new(0.5, 1)
				z.Position = UDim2.fromScale(0.3, 1)
				z.Size = UDim2.fromOffset(60, 60)
				z.BackgroundTransparency = 1
				z.Font = Enum.Font.FredokaOne
				z.Text = "Z"
				z.TextSize = 20
				z.TextColor3 = Color3.fromRGB(150, 220, 255)
				z.TextTransparency = 1
				z.Rotation = -10
				local stroke = Instance.new("UIStroke")
				stroke.Thickness = 3
				stroke.Color = Color3.fromRGB(30, 70, 150)
				stroke.Transparency = 1
				stroke.Parent = z
				z.Parent = gui
			end
		end
		gui.Parent = head
	end
end

local function newGuard(boss: Boss, shadow: boolean, at: CFrame): Guard
	local creature = CREATURE_MODULES[boss.Config.Creature :: string]
	local model = if creature then buildHoundRig(boss.Config, shadow) else buildRig(boss.Config, shadow)
	-- A creature's Root is already at floor level; the shared spawn CFrame (boss.Post / a chase
	-- hand-off) is calibrated to a round character's mid-body root, HEIGHT studs higher.
	local spawnAt = if creature then at.Rotation + (at.Position - Vector3.new(0, HEIGHT, 0)) else at
	model:PivotTo(spawnAt)
	model.Parent = folder
	local head = model:FindFirstChild("Head") :: BasePart
	local guard: Guard = {
		Model = model,
		Zone = boss.Zone,
		Config = boss.Config,
		Boss = boss,
		IsShadow = shadow,
		Position = spawnAt.Position,
		Target = nil,
		Returning = false,
		AlertUntil = 0,
		WakeStart = 0,
		WakeUntil = 0,
		InChair = false,
		ExitAt = nil,
		SitStart = nil,
		Alert = head:FindFirstChild("Alert") :: BillboardGui,
		Dead = false,
		KnifeName = model:GetAttribute("KnifeName") :: string,
		LastAttack = 0,
		ThrowReadyAt = 0,
		WindupUntil = 0,
		BusyUntil = 0,
		StaggerImmuneUntil = 0,
		Tracks = if creature then {} else loadTracks(model),
		Playing = nil,
		Hound = creature,
		FootOffset = if creature then 0 else HEIGHT,
		HoundPhase = 0,
	}
	guardByModel[model] = guard
	animate(guard, "Idle")
	return guard
end

-- The flame recipe whose body colour is closest to a zone's colour (for the lair torches)
local auraStyles = require(ReplicatedStorage.Shared.Config.KnifeAuraVariants).List
local function torchStyle(color: Color3): any
	local best, bestGap = auraStyles[1], math.huge
	for _, style in auraStyles do
		local c = style.Colors.Outer.Start
		local gap = (c.R - color.R) ^ 2 + (c.G - color.G) ^ 2 + (c.B - color.B) ^ 2
		if gap < bestGap then
			best, bestGap = style, gap
		end
	end
	return best
end

-- The wall ---------------------------------------------------------------------------------------

local function clearDisplay(slot: Slot)
	if slot.Display then
		slot.Display:Destroy()
		slot.Display = nil
	end
	slot.Plaque.Color = Color3.fromRGB(40, 36, 48)
	slot.Plaque.Material = Enum.Material.SmoothPlastic
	slot.Frame.Color = Color3.fromRGB(60, 56, 70)
	slot.Prompt.Enabled = false
end

-- Puts `item` on the wall in `slot`: floating, turning, labelled, glowing in its colour
local function setSlot(boss: Boss, slot: Slot, item: string)
	clearDisplay(slot)
	slot.Item = item
	slot.Pad:SetAttribute("KnifeItem", item)
	slot.Pad:SetAttribute("Zone", boss.Index)
	slot.Pad:SetAttribute("Slot", slot.Index)
	slot.Out = false
	slot.RestockAt = nil
	local parsed = Items.Parse(item)
	if not parsed then
		return
	end
	-- Coffins on: the boss's graveyard - a coffin in the slot instead of the knife. You can see how
	-- rare it is (size, colour, glow), never which knife is inside: that's the reveal at home.
	if PenMode.Coffins() then
		local rarity = parsed.Knife.Rarity
		local floor = CFrame.new(slot.Pad.Position + Vector3.new(0, slot.Pad.Size.Y / 2, 0)) * slot.Spot.Rotation
		local coffin = CoffinModel.Build(rarity, floor) -- (straight on the floor, no tray)
		KnifeHaze.Add(coffin, rarity)
		coffin.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		coffin.Parent = boss.Folder
		slot.Display = coffin
		-- (no label: like Steal an Egg's eggs, the coffin speaks for itself; the prompt names it)
		slot.Prompt.ObjectText = `{rarity} Coffin`
		slot.Prompt.Enabled = true
		return
	end
	local model = KnifeModel.Build(item, true)
	KnifeModel.FitLength(model, 4) -- same display size as vault knives
	model:PivotTo(slot.Spot)
	local box = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + (slot.Spot.Position - box.Position))
	model:AddTag("Spin")
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- spun whole on clients
	model.Parent = boss.Folder
	slot.Display = model
	-- No labels: the knife itself shows what it is (walk up and the prompt names it). A soft glow
	-- in its colour from the plate under it.
	local glow = Instance.new("PointLight")
	glow.Color = Items.Color(item)
	glow.Range = 8
	glow.Brightness = 1.2
	glow.Shadows = false
	glow.Parent = model.PrimaryPart
	-- The same fire as a knife in hand (KnifeAura.Hug): it hugs the blade, scaled up to the 4-stud
	-- display size, and grows with the knife's own rarity / mutation / size
	local blade = model:FindFirstChild("Blade", true)
	local guardPart = model:FindFirstChild("Guard", true)
	if blade and blade:IsA("BasePart") then
		local anchor = Instance.new("Part")
		anchor.Name = "Aura"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.CFrame = CFrame.new(if guardPart and guardPart:IsA("BasePart") then guardPart.Position else box.Position)
		anchor.Parent = model
		KnifeAura.Hug(anchor, item, blade, 4)
	end
	-- Brainrot label over the knife: name, rarity, money per second (the prompt just says Steal)
	SignTheme.knifeLabel(
		model,
		model.PrimaryPart :: BasePart,
		Items.DisplayName(item),
		parsed.Knife.Rarity,
		Knives.RarityColors[parsed.Knife.Rarity],
		`+{Format.Cash(Items.Income(item))}/s`,
		nil,
		70
	)
	slot.Prompt.ObjectText = ""
	slot.Prompt.Enabled = true
end

local function rollItem(boss: Boss): string
	return Items.RollKnife(rng, boss.Config.Rarity, 1)
end

-- A restock worth shouting about: a strong mutation or a huge size
local function announceIfRare(boss: Boss, item: string)
	local parsed = Items.Parse(item)
	if parsed and (parsed.Mutation.Rank >= 2 or parsed.Size.Rank >= 3) then
		Net.Announce(
			`💎 A {Items.DisplayName(item)} just appeared at the {GameConfig.MonsterName(boss.Index)} in {boss.Config.Title}!`,
			Items.Color(item),
			2
		)
	end
end

-- The boss's chair (Codex's per-biome chairs, Config/BossChairs): the native block version goes
-- up straight away, then the uploaded mesh model replaces it once it has downloaded. Made 1.25x
-- (seat top 3.25) to fit a BossScale boss: at 1x the boss overhung it on every side.
local CHAIR_SCALE = 1.25
-- Getting up: stand and step forward (client/Moves poses it), then
-- walks on out to CHAIR_EXIT in front of the chair before turning (the torch post stands beside it)
local CHAIR_EXIT = 7

local chairPosition = BossChairMotion.Position

-- Where a creature boss (Root at floor level) actually rests, vs. the shared Post/chairPosition
-- data (calibrated to a round character's mid-body root, Y = HEIGHT): the same spot, HEIGHT lower.
local function restSpot(guard: Guard, post: CFrame, p: number?): Vector3
	local pos = if p then chairPosition(post, p) else post.Position
	return if guard.Hound then pos - Vector3.new(0, HEIGHT, 0) else pos
end
local function mountChair(zone: number, parent: Instance, frame: CFrame)
	local spec = BossChairs[zone]
	if not spec then
		return
	end
	local native = BossChairModel.Build(zone, parent, frame)
	native:ScaleTo(CHAIR_SCALE)
	task.spawn(function()
		local loaded, asset = pcall(InsertService.LoadAsset, InsertService, spec.ModelAssetId)
		if not loaded then
			warn(`[GuardService] {spec.Boss}'s chair mesh didn't load ({asset}); keeping the block one`)
			return
		end
		local prepared, result = pcall(BossChairModel.Prepare, asset :: Model, zone, parent, frame)
		if prepared and parent.Parent then
			(result :: Model):ScaleTo(CHAIR_SCALE)
			native:Destroy()
		else
			warn(`[GuardService] {spec.Boss}'s chair mesh: {result}`)
			asset:Destroy()
		end
	end)
end

-- The footstool his feet rest on (a boss's legs are too short for the 1.25x seat): wooden legs and
-- top, a cushion in the zone's colour. Cosmetic only.
local function buildFootstool(parent: Instance, chairFrame: CFrame, cushion: Color3)
	local stool = Instance.new("Model")
	stool.Name = "Footstool"
	local wood = Color3.fromRGB(110, 70, 40)
	local function piece(name: string, size: Vector3, offset: Vector3, color: Color3)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
		part.CastShadow = false
		part.Size = size
		part.CFrame = chairFrame * CFrame.new(offset)
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		part.Parent = stool
		return part
	end
	local top = piece("Top", Vector3.new(3.6, 0.3, 1.9), Vector3.new(0, 1.1, -2.65), wood)
	piece("Cushion", Vector3.new(3.4, 0.5, 1.7), Vector3.new(0, 1.45, -2.65), cushion:Lerp(Color3.new(1, 1, 1), 0.1))
	for _, x in { -1.5, 1.5 } do
		for _, z in { -3.4, -1.9 } do
			piece("Leg", Vector3.new(0.35, 1, 0.35), Vector3.new(x, 0.5, z), wood)
		end
	end
	stool.PrimaryPart = top
	stool.Parent = parent
end

-- The lair: a raised stage across the middle of the runway, a back wall with the knife slots on
-- pedestals and a glowing plaque behind each, the boss's name in lights, torches either side
local function buildLair(index: number, zone: MapService.Zone, config: ZoneConfig): Boss
	local lair = GameConfig.BossLair
	local center = GameConfig.BossLairCenter(index)
	-- Local frame: -Z (the frame's look) points out at the runway, where the boss looks; the side
	-- wall is behind it at +Z
	local frame = CFrame.lookAt(center, Vector3.new(0, 0, center.Z))
	ManorDecor.ClearArea(center, lair.Depth / 2 + 4, lair.Width / 2 + 4)
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local model = Instance.new("Model")
	model.Name = `Lair{index}`
	model.Parent = folder
	local W, D = lair.Width, lair.Depth
	local wallZ = D / 2 - 1
	-- Coffins on: no stash wall at all - a graveyard on the open grass (Steal an Egg's eggs lying
	-- around the sleeping creature). Just the boss's chair, its speed sign and the coffins.
	local graveyard = PenMode.Coffins()
	local shell = ToyBlockModel.Build("Lair" .. config.Boss, true)
	shell:PivotTo(frame)
	shell.Parent = if graveyard then nil else model
	-- Original walking surface and back boundary remain; the block shell is cosmetic.
	if not graveyard then
		local stage = block(model, "Stage", Vector3.new(W, PLATFORM, D), at(0, PLATFORM / 2, 0), config.Color)
		stage.Transparency = 1
		local back = block(model, "BackWall", Vector3.new(W, 18, 2), at(0, 9 + PLATFORM, wallZ), config.Color)
		back.Transparency = 1
	end
	-- Mount canvases keep the original dimensions and frames, including transparent margins.
	local signWidth = math.min(W - 6, 26)
	local signSize = Vector2.new(1024, 256)
	local ribbonWidth = signWidth * 0.62
	local ribbonSize = Vector2.new(768, 128)
	local ribbonHeight = ribbonWidth * ribbonSize.Y / ribbonSize.X
	local function mount(name: string, size: Vector3, cframe: CFrame): Part
		local part = block(model, name, size, cframe, Color3.new())
		part.Transparency = 1
		part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
		part.CastShadow = false
		part:SetAttribute("BossTitleMount", true)
		return part
	end
	local sign = mount(
		"Sign",
		Vector3.new(signWidth, signWidth * signSize.Y / signSize.X, 0.2),
		at(0, PLATFORM + 14, wallZ - 1.2)
	)
	local ribbon = mount(
		"SignRibbon",
		Vector3.new(ribbonWidth, ribbonHeight, 0.2),
		at(0, PLATFORM + 14 - signWidth * signSize.Y / signSize.X / 2 - ribbonHeight / 2 + 0.3, wallZ - 1.3)
	)
	local titles = if graveyard then nil else BossTitleModel.Build(config.Boss, sign, ribbon)
	if titles then
		titles.Parent = model
	end

	-- Torches at both front corners of the stage
	for _, x in (if graveyard then {} else { -W / 2 + 2, W / 2 - 2 }) :: { number } do
		block(
			model,
			"TorchPost",
			Vector3.new(0.8, 7, 0.8),
			at(x, PLATFORM + 3.5, -D / 2 + 2),
			Color3.fromRGB(40, 32, 30),
			Enum.Material.Wood
		)
		local bowl = block(
			model,
			"TorchBowl",
			Vector3.new(1.8, 0.6, 1.8),
			at(x, PLATFORM + 7.2, -D / 2 + 2),
			Color3.fromRGB(30, 28, 34),
			Enum.Material.Metal
		)
		-- The knives' cartoon flame in the zone's colours, bigger the deeper the zone
		KnifeAura.Mount(bowl, (index - 1) * 1.6, nil, torchStyle(config.Color))
		local light = Instance.new("PointLight")
		light.Color = config.Color
		light.Range = 22
		light.Brightness = 1.6
		light.Parent = bowl
	end

	-- The boss dozes in a chair at the deeper end of the stage (Steal An Egg: the creature sleeps
	-- beside its eggs), not in front of the middle of the knife wall, turned at an angle towards
	-- the runway and the way thieves come in
	-- (just off the end of the stage, beside its pillar: on it he sat in front of the first knife)
	-- Brought forward out of the corner (it sat behind the torch post) and turned to face down the
	-- runway towards the plaza, a little in towards the middle: thieves walking up meet him face on
	-- (turned across the runway, everyone saw his side and back)
	local endA = at(W / 2 + 3.5, HEIGHT, -D / 2 - 4).Position
	local endB = at(-(W / 2 + 3.5), HEIGHT, -D / 2 - 4).Position
	local postPosition = if endA.Z > endB.Z then endA else endB
	local post = CFrame.lookAt(postPosition, Vector3.new(postPosition.X * 0.75, postPosition.Y, postPosition.Z - 60))
	-- The zone's own chair (Config/BossChairs: floor origin under the seat, front -Z, seat top 2.6).
	-- The floor is 4.9 below the post (the boss's root). The chair is deeper than a boss's thighs
	-- are long: sat back against the backrest his shins went down through the seat, so he sits
	-- forward on it, slouched back (client/Moves), knees over the front edge, feet on a footstool.
	local chairFrame = post * CFrame.new(0, -4.9, 0.9)
	-- (a creature sleeps on the ground: no chair, no footstool)
	if not config.Creature then
		mountChair(index, model, chairFrame)
		buildFootstool(model, chairFrame, config.Color)
	end
	-- The speed board beside the chair (like the wheel's sign): how much Speed you need to outrun
	-- this boss. Each player's own client turns it green with a tick once they have it (Hud).
	do
		local need = ((config :: any).SpeedNeeded or 0) :: number
		-- On the side towards the middle of the runway, facing the way the boss faces. A chair boss is
		-- person-sized: 7 studs to the side clears him. A giant creature lies right over that spot,
		-- so its sign stands clear of its body (about its height out) and higher and bigger, so a kid
		-- sees it before reaching the creature.
		local creatureHeight = if config.Creature
			then GameConfig.CreatureHeight.First
				+ ((table.find(Knives.Rarities, config.Rarity) or 1) - 1) * GameConfig.CreatureHeight.Step
			else nil
		local side = if creatureHeight then creatureHeight * 0.7 + 4 else 7
		local towardMiddle = if (chairFrame * CFrame.new(side, 0, 0)).Position.X ^ 2
				< (chairFrame * CFrame.new(-side, 0, 0)).Position.X ^ 2
			then side
			else -side
		local base = chairFrame * CFrame.new(towardMiddle, 0, -2.5)
		local poleHeight = if creatureHeight then 9 else 5
		local boardSize = if creatureHeight then Vector3.new(11, 5.3, 0.5) else Vector3.new(7, 3.4, 0.4)
		local navy = Color3.fromRGB(22, 34, 70)
		local pole = Instance.new("Part")
		pole.Name = "SpeedSignPole"
		pole.Anchored = true
		pole.Size = Vector3.new(0.6, poleHeight, 0.6)
		pole.CFrame = base * CFrame.new(0, poleHeight / 2, 0)
		pole.Color = navy
		pole.Parent = model
		local board = Instance.new("Part")
		board.Name = "SpeedSign"
		board.Anchored = true
		board.Size = boardSize
		board.CFrame = base * CFrame.new(0, poleHeight + boardSize.Y / 2 - 1.5, 0)
		board.Color = navy
		board.Parent = model
		board:SetAttribute("Need", need)
		board:AddTag("SpeedSign")
		local surface = Instance.new("SurfaceGui")
		surface.Face = Enum.NormalId.Front
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 50
		surface.LightInfluence = 0
		surface.Parent = board
		local function signText(name: string, y: number, h: number, value: string, color: Color3)
			local label = Instance.new("TextLabel")
			label.Name = name
			label.BackgroundTransparency = 1
			label.Position = UDim2.fromScale(0.04, y)
			label.Size = UDim2.fromScale(0.92, h)
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.Text = value
			label.TextColor3 = color
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 3
			stroke.Color = Color3.fromRGB(10, 14, 30)
			stroke.Parent = label
			label.Parent = surface
		end
		signText("Title", 0.06, 0.3, "SPEED NEEDED", Color3.fromRGB(255, 225, 90))
		signText("Value", 0.4, 0.5, if need > 0 then `👟 {Format.Short(need)}` else "👟 ANY", Color3.new(1, 1, 1))
	end
	local boss: Boss = {
		Index = index,
		Zone = zone,
		Config = config,
		Name = config.Boss,
		Post = post,
		Folder = model,
		Slots = {},
		Guard = nil :: any,
	}

	-- The wall slots: pedestals in a line in front of the wall, a glowing plaque behind each
	local count = GameConfig.BossWallSlots
	local span = W - 10
	-- (the graveyard: Steal an Egg's eggs lie in a loose clump right in front of the sleeping
	-- creature, a few steps from it - so you sneak up to the boss to take one. Scattered the same
	-- way on every server, spaced by how big this zone's coffins are)
	local scatter = Random.new(index * 7919)
	local chairLocal = frame:PointToObjectSpace(chairFrame.Position)
	-- (sized for the biggest coffin this stash can roll: one rarity up. Coffins lie lengthwise along
	-- local Z, turned at most TURN degrees, so two don't touch if they're a coffin-width apart side
	-- by side or a coffin-length apart end to end - close, never overlapping)
	local lengths = { 3, 4, 5.2, 6.6, 8.2, 10, 12, 14 }
	local coffinLength = lengths[math.clamp(index + 1, 1, #lengths)]
	local coffinWidth = coffinLength * 0.4
	local TURN = 12
	local slack = math.sin(math.rad(TURN)) * coffinLength
	local gap = 1.2
	local function apart(a: Vector3, b: Vector3): boolean
		return math.abs(a.X - b.X) >= coffinWidth + slack + gap or math.abs(a.Z - b.Z) >= coffinLength + slack + gap
	end
	-- Steal an Egg's eggs: scattered loosely in FRONT of the sleeping creature (between it and you,
	-- out on the floor towards the runway), some close, some further, well apart - not a clump
	-- beside it. Blue-noise: each coffin takes the best of a few random spots in a fan out from the
	-- chair, the one furthest from the coffins already down.
	local near = 4 + coffinLength * 0.6 -- (room round the chair)
	local far = near + coffinLength * 3.2 + 6
	local graves: { Vector3 } = {}
	for _ = 1, count do
		local chosen: Vector3? = nil
		local bestRoom = -math.huge
		for _ = 1, 24 do
			local angle = math.rad(scatter:NextNumber(-65, 65))
			local radius = scatter:NextNumber(near, far)
			local candidate = Vector3.new(
				math.clamp(chairLocal.X + math.sin(angle) * radius, -W / 2 - 6, W / 2 + 6),
				0,
				chairLocal.Z - math.cos(angle) * radius
			)
			local room = math.huge
			local fits = true
			for _, other in graves do
				room = math.min(room, (candidate - other).Magnitude)
				fits = fits and apart(candidate, other)
			end
			if fits and room > bestRoom then
				chosen, bestRoom = candidate, room
			end
		end
		table.insert(graves, chosen or Vector3.new(chairLocal.X, 0, chairLocal.Z - far - #graves * coffinLength))
	end
	-- A creature: its coffins lie in one tidy bunch beside it (on the side towards the middle of the
	-- runway, where thieves come from) - rows of three, a hand's width apart, never touching
	if config.Creature then
		local rank = table.find(Knives.Rarities, config.Rarity) or 1
		local height = GameConfig.CreatureHeight.First + (rank - 1) * GameConfig.CreatureHeight.Step
		local body = height * 0.45 -- (about half its width, lying down)
		local arena = MapService.Arena :: MapService.Bounds
		local ground = CFrame.new(post.Position - Vector3.new(0, HEIGHT, 0)) * post.Rotation
		local side = if (ground * CFrame.new(1, 0, 0)).Position.X ^ 2
				< (ground * CFrame.new(-1, 0, 0)).Position.X ^ 2
			then 1
			else -1
		local across = coffinWidth + 2.5 -- (side by side)
		local along = coffinLength + 2.5 -- (end to end)
		local perRow = 3
		for i = 1, count do
			local row = (i - 1) // perRow
			local column = (i - 1) % perRow
			local inRow = math.min(perRow, count - row * perRow)
			local x = side * (body + 2 + coffinWidth / 2 + column * across)
			local z = (row - (math.ceil(count / perRow) - 1) / 2) * along + (perRow - inRow) * across * 0.25
			local spot = (ground * CFrame.new(x, 0, z)).Position
			spot =
				Vector3.new(math.clamp(spot.X, arena.MinX + coffinWidth + 2, arena.MaxX - coffinWidth - 2), 0, spot.Z)
			local localSpot = frame:PointToObjectSpace(spot)
			graves[i] = Vector3.new(localSpot.X, 0, localSpot.Z)
		end
	end
	for i = 1, count do
		local x = -span / 2 + (i - 1) * span / math.max(count - 1, 1)
		if graveyard then
			local grave = graves[i]
			-- (a creature's bunch lines up with the creature, barely turned, so none touch)
			local turn = if config.Creature
				then frame.Rotation:Inverse() * post.Rotation * CFrame.Angles(0, math.rad(scatter:NextNumber(-5, 5)), 0)
				else CFrame.Angles(0, math.rad(scatter:NextNumber(-TURN, TURN)), 0)
			local pad: Part =
				block(model, "Grave", Vector3.new(4.5, 0.3, 4.5), at(grave.X, 0.15, grave.Z) * turn, config.Color)
			pad.Transparency = 1
			pad.CanCollide = false
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Steal"
			prompt.ObjectText = ""
			prompt.HoldDuration = 0.5
			prompt.MaxActivationDistance = 9
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
			prompt.Enabled = false
			prompt:SetAttribute("BossSteal", true)
			prompt.Parent = pad
			table.insert(boss.Slots, {
				Index = i,
				Item = nil,
				Out = false,
				RestockAt = nil,
				Spot = at(grave.X, 0, grave.Z) * turn,
				Pad = pad :: BasePart,
				Plaque = pad,
				Frame = pad,
				Display = nil,
				Prompt = prompt,
			})
			continue
		end
		local plaque = block(
			model,
			"Plaque",
			Vector3.new(6, 9, 0.3),
			at(x, PLATFORM + 7, wallZ - 1.15),
			Color3.fromRGB(40, 36, 48)
		)
		plaque.CanCollide = false
		plaque.Transparency = 1 -- kept for the slot record; the wall stays clean
		local border = block(
			model,
			"PlaqueFrame",
			Vector3.new(6.5, 9.5, 0.2),
			at(x, PLATFORM + 7, wallZ - 1.05),
			Color3.fromRGB(60, 56, 70),
			Enum.Material.Neon
		)
		border.CanCollide = false
		border.Transparency = 1
		local pedestal = ToyBlockModel.Build("LairPlate" .. config.Boss, true)
		pedestal:PivotTo(at(x, PLATFORM, wallZ - 6))
		pedestal.Parent = model
		-- Stone is the original interaction centre; its collision and query contract is unchanged.
		local pad: BasePart =
			block(pedestal, "Stone", Vector3.new(4.55, 1.521, 4.55), at(x, PLATFORM + 0.7605, wallZ - 6), config.Color)
		pad.Transparency = 1
		-- (no flat plate art: the pedestals are block-built now)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Steal"
		prompt.ObjectText = ""
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.Enabled = false
		prompt:SetAttribute("BossSteal", true)
		prompt.Parent = pad
		table.insert(boss.Slots, {
			Index = i,
			Item = nil,
			Out = false,
			RestockAt = nil,
			Spot = at(x, PLATFORM + 5.2, wallZ - 6) * CFrame.Angles(0, 0, math.rad(28)),
			Pad = pad,
			Plaque = plaque,
			Frame = border,
			Display = nil,
			Prompt = prompt,
		})
	end
	return boss
end

-- Chasing --------------------------------------------------------------------------------------

-- The thief is still worth chasing: alive, out of a round, still carrying this boss's knife, and not
-- yet back on the plaza or in a vault (that's the safe point)
local function chaseTarget(guard: Guard): BasePart?
	local player = guard.Target
	if not player or not player.Parent or player:GetAttribute("InRound") then
		return nil
	end
	local root = rootOf(player)
	local carry = StealService.BossCarry(player)
	if not root or not carry or carry.Zone ~= guard.Boss.Index then
		return nil
	end
	if root.Position.Z < -2 or BaseService.IsInAnyBase(root.Position) then
		return nil
	end
	return root
end

local function showTag(guard: Guard, on: boolean)
	local head = guard.Model:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("BossTag")
	if tag and tag:IsA("BillboardGui") then
		tag.Enabled = on or guard.IsShadow == true
	end
end

local function face(guard: Guard, point: Vector3)
	local look = Vector3.new(point.X, guard.Position.Y, point.Z)
	if (look - guard.Position).Magnitude > 0.1 then
		guard.Model:PivotTo(CFrame.lookAt(guard.Position, look))
	end
end

local function stopChase(guard: Guard, escaped: boolean)
	local thief = guard.Target
	guard.Target = nil
	guard.Alert.Enabled = false
	showTag(guard, false)
	guard.WindupUntil = 0
	guard.Model:SetAttribute("ChargeStart", nil)
	if thief and escaped and thief.Parent then
		Net.Notify(thief, "You got away!", "good")
		Analytics.Track(thief, "boss.escaped", { zone = guard.Boss.Index, shadow = guard.IsShadow == true })
	end
	if guard.IsShadow then
		-- Shadows just fade out
		Net.Remotes.Effect:FireAllClients("Smoke", guard.Position)
		guardByModel[guard.Model] = nil
		guard.Model:Destroy()
		guard.Dead = true
		local i = table.find(chasers, guard)
		if i then
			table.remove(chasers, i)
		end
	else
		guard.Returning = true
	end
end

-- Someone just took a knife off the wall: the boss (or a shadow of them) comes for them
local function sendChaser(boss: Boss, thief: Player, startAt: CFrame?)
	local guard = boss.Guard
	if guard.Target ~= nil and guard.Target ~= thief then
		-- Already busy with someone else: a shadow steps out of the wall
		guard = newGuard(boss, true, boss.Post)
		Net.Remotes.Effect:FireAllClients("Smoke", boss.Post.Position)
	end
	-- Waking up is its own beat (see GameConfig.BossWake): red eyes, out of the chair, then the chase.
	-- New players get longer. A chase picked back up after a round only gets the short "!".
	local wake = GameConfig.GuardAlertTime
	guard.InChair = false
	guard.ExitAt = nil
	if not startAt then
		local profile = DataService.Get(thief)
		local knives = if profile then #profile.Knives else 0
		local newcomer = knives < GameConfig.BossWake.NewcomerKnives
		wake = if guard.Hound
			then (if newcomer then GameConfig.BossWake.HoundNewcomer else GameConfig.BossWake.HoundTime)
			elseif newcomer then GameConfig.BossWake.Newcomer
			else GameConfig.BossWake.Time
		-- The boss himself gets up out of his chair (client/Moves acts it out), steps out of it and
		-- walks forward clear of the torch post before turning for you (he walked through it).
		-- A shadow steps out of the wall: no chair.
		if not guard.IsShadow and (guard.Position - guard.Boss.Post.Position).Magnitude < 1 then
			local serverNow = workspace:GetServerTimeNow()
			guard.Model:SetAttribute("WakeAt", serverNow)
			guard.Model:SetAttribute("WakeEnd", serverNow + BossChairMotion.WakeDuration(wake))
			guard.Model:SetAttribute("SitAt", nil)
			guard.Model:SetAttribute("SitEnd", nil)
			guard.InChair = true
			guard.ExitAt = (guard.Boss.Post * CFrame.new(0, 0, -CHAIR_EXIT)).Position
		end
		Net.Remotes.Effect:FireAllClients("BossWake", guard.Model, wake)
	end
	guard.WakeStart = now()
	-- A creature has no stand-and-face beat after its pose blend finishes (no chair to clear) - the
	-- blend IS the whole wake, so it ends exactly when the chase starts (see AlertUntil below), not
	-- 40% early with an idle "waiting" pause tacked on after it.
	guard.WakeUntil = if guard.Hound
		then now() + wake
		else now() + BossChairMotion.WakeDuration(wake) * GameConfig.BossHop.Done
	setAsleep(guard, false)
	guard.Target = thief
	guard.Returning = false
	guard.SitStart = nil
	guard.AlertUntil = now() + wake
	guard.Alert.Enabled = true
	showTag(guard, true)
	guard.ThrowReadyAt = now() + 2
	if not table.find(chasers, guard) then
		table.insert(chasers, guard)
	end
	if startAt then
		-- Picking a chase back up after a round: right where they were when it was interrupted
		guard.Position = startAt.Position
		guard.Model:PivotTo(startAt)
	end
	-- (the "!" stretch once they're on their feet)
	local model = guard.Model
	task.delay(if startAt then 0 else BossChairMotion.WakeDuration(wake) * GameConfig.BossHop.Done, function()
		if model.Parent then
			Net.Animate(model, "Alert")
		end
	end)
	Analytics.Track(thief, "boss.chase", {
		wake = wake,
		zone = boss.Index,
		shadow = guard.IsShadow == true,
		resumed = startAt ~= nil,
		walk_speed = (function()
			local humanoid = thief.Character and thief.Character:FindFirstChildOfClass("Humanoid")
			return if humanoid then math.floor(humanoid.WalkSpeed) else nil
		end)(),
		boss_speed = guard.Config.GuardSpeed,
	})
	Net.Remotes.Effect:FireClient(thief, "Alarm")
	Net.Notify(thief, `THE {string.upper(GameConfig.MonsterName(guard.Boss.Index))} IS COMING! RUN HOME!`, "bad")
end

-- Hurt a thief (throws, and the snatch). Shields block it.
-- How hard a boss throws you: the deeper (scarier) the monster, the further you fly - the Hedge
-- Hound tosses you, the Void Beast launches you (x1 in zone 1 up to ~x2.3 in the last zone)
local function throwPower(zone: number): number
	return 1 + (math.max(zone, 1) - 1) * 0.19
end

local function hurt(player: Player, amount: number, from: Vector3): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootOf(player)
	if not character or not humanoid or not root then
		return false
	end
	-- Bosses knock you about, they never kill you: the hit stops at 1 health (the tumble that follows
	-- is the punishment), and health comes back while you get up
	humanoid.Health = math.max(1, humanoid.Health - amount)
	if humanoid.Health <= 1 then
		task.delay(2, function()
			if humanoid.Parent and humanoid.Health > 0 and not player:GetAttribute("InRound") then
				humanoid.Health = math.max(humanoid.Health, humanoid.MaxHealth * 0.5)
			end
		end)
	end
	Net.Remotes.Effect:FireAllClients("Hit", root.Position)
	Analytics.Count(player, "boss_hits_taken")
	Net.Remotes.Effect:FireClient(player, "Hurt", from)
	if humanoid.Health > 0 then
		Net.Animate(character, "Hurt")
	end
	return true
end

-- Caught: the knife goes back on the wall, and it hurts
local function snatch(guard: Guard, thief: Player)
	local root = rootOf(thief)
	if not root then
		return
	end
	local profileNow = DataService.Get(thief)
	-- Your very first knife always makes it home: the boss still chases (the thrill), but trips
	-- at the last second. 58% of tutorial steals were caught, and every new player who never banked
	-- a knife quit, while everyone who did stayed 5-18 min.
	-- (and then gives up: a 1.5 s stun had them caught-and-saved ~3 times a run, and 23 of 34 such
	-- players quit mid-carry)
	if profileNow and not profileNow.TutorialDone and #profileNow.Knives == 0 then
		Net.Notify(thief, `The {GameConfig.MonsterName(guard.Boss.Index)} tripped! RUN HOME!`, "good")
		Analytics.Track(thief, "boss.first_steal_saved", { zone = guard.Boss.Index })
		Net.Remotes.Effect:FireAllClients("Smoke", guard.Position)
		stopChase(guard, false)
		return
	end
	local zoneNow = GameConfig.Zones[guard.Boss.Index]
	local snatchProps = {
		zone = guard.Boss.Index,
		speed = if profileNow then math.floor(profileNow.Speed) else nil,
		speed_needed = if zoneNow then zoneNow.SpeedNeeded or 0 else nil,
		too_slow = profileNow ~= nil and zoneNow ~= nil and profileNow.Speed < (zoneNow.SpeedNeeded or 0),
		carrying = StealService.BossCarry(thief) ~= nil,
		shadow = guard.IsShadow == true,
	}
	if not hurt(thief, guard.Config.Damage * 2, guard.Position) then
		Net.Notify(thief, "Your shield saved you! Keep running!", "good")
		Analytics.Track(thief, "boss.shield_saved", snatchProps)
		return
	end
	Analytics.Track(thief, "boss.snatch", snatchProps)
	-- Escape Token (Robux charge): break free with the knife, the boss reels
	if StealService.BossCarry(thief) and DataService.UseCharge(thief, "Escape") then
		GuardService.Stun(guard, GameConfig.Consumables.EscapeStun)
		Net.Notify(thief, "🗝️ You broke free! RUN!", "good")
		Net.Remotes.Effect:FireAllClients("Shield", root.Position)
		Analytics.Track(thief, "boss.escape_token", snatchProps)
		return
	end
	local item = StealService.ReturnToBoss(thief)
	if item then
		-- Caught: the two things that fix it next time
		local profile = DataService.Get(thief)
		local zone = GameConfig.Zones[guard.Boss.Index]
		if
			profile
			and zone
			and profile.Speed < (zone.SpeedNeeded or 0)
			and not DataService.BoostActive(profile, "Speed")
		then
			Offers.Show(thief, "SpeedPotion", "Run faster with a Speed Potion!")
		else
			Offers.Show(thief, "Escape3", "Caught at the last second? An Escape Token breaks you free WITH the knife.")
		end
		Net.Notify(
			thief,
			if PenMode.Coffins() then "Caught! The coffin went back." else "Caught! The knife went back.",
			"bad"
		)
		Net.Remotes.Effect:FireClient(thief, "Tip", "Caught")
		Net.Remotes.Effect:FireClient(thief, "Damage", root.Position + Vector3.new(0, 3, 0), "CAUGHT!")
	end
	-- Thrown through the air like a rag doll (Steal An Egg style)
	local away = (root.Position - guard.Position) * Vector3.new(1, 0, 1)
	local power = throwPower(guard.Boss.Index)
	local push = (if away.Magnitude > 0.1 then away.Unit else -root.CFrame.LookVector) * (50 * power)
		+ Vector3.new(0, 50 * math.sqrt(power), 0)
	Ragdoll.Tumble(thief, push, 1.6 + (power - 1) * 0.5)
	stopChase(guard, false)
end

-- Thrown knives (Epic+ bosses): aimed where the thief is heading, curving after them a little
local function throwAt(guard: Guard, aim: Vector3, target: Player)
	local hand = guard.Model:FindFirstChild("RightHand") :: BasePart?
	local origin = if hand then hand.Position else guard.Position + Vector3.new(0, 1, 0)
	local config = GameConfig.GuardThrow
	-- Always faster than the one it's thrown at (a trained thief runs 100+ studs/s: a fixed speed
	-- could never catch them), so it's the dodge that saves you, not outrunning it
	local targetRoot = rootOf(target)
	local targetHumanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	local speed =
		math.max(config.Speed, (if targetHumanoid then targetHumanoid.WalkSpeed else 0) * config.SpeedOverTarget)
	-- Lead the target: where they'll be by the time the knife gets there
	if targetRoot then
		local velocity = targetRoot.AssemblyLinearVelocity
		local flight = (targetRoot.Position - origin).Magnitude / speed
		aim = targetRoot.Position + Vector3.new(velocity.X, 0, velocity.Z) * flight * config.Lead
	end
	local flat = Vector3.new(aim.X - origin.X, 0, aim.Z - origin.Z)
	if flat.Magnitude < 0.1 then
		return
	end
	local model = KnifeModel.Build(guard.KnifeName, true)
	KnifeModel.FitLength(model, 1.9) -- thrown knives match the held size
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
		elseif d:IsA("Trail") then
			d.Enabled = true
		end
	end
	model.Parent = projectileFolder
	table.insert(projectiles, {
		Model = model,
		Position = origin,
		Direction = flat.Unit,
		Traveled = 0,
		Damage = guard.Config.Damage,
		Target = target,
		Speed = speed,
		Zone = guard.Boss.Index,
	})
	Net.Remotes.Effect:FireAllClients("Dash", origin)
end

local function stepProjectiles(dt: number)
	local config = GameConfig.GuardThrow
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { projectileFolder, folder }
	for i = #projectiles, 1, -1 do
		local p = projectiles[i]
		-- Curve gently towards the thief (capped turn rate, so a sharp sidestep still dodges it)
		local chasing = rootOf(p.Target)
		if chasing then
			local want = Vector3.new(chasing.Position.X - p.Position.X, 0, chasing.Position.Z - p.Position.Z)
			if want.Magnitude > 0.5 then
				want = want.Unit
				local angle = math.acos(math.clamp(p.Direction:Dot(want), -1, 1))
				-- Only while it's still coming at them (no U-turns once it has flown past)
				if angle > 1e-3 and angle < math.rad(100) then
					local turn = math.min(1, config.TurnRate * dt / angle)
					p.Direction = p.Direction:Lerp(want, turn).Unit
				end
			end
		end
		local stepLength = (p.Speed or config.Speed) * dt
		local nextPosition = p.Position + p.Direction * stepLength
		local done = false
		local hit = workspace:Raycast(p.Position, nextPosition - p.Position, params)
		local wall = false
		if hit and not Players:GetPlayerFromCharacter(hit.Instance:FindFirstAncestorOfClass("Model")) then
			nextPosition = hit.Position
			done = true
			wall = true
		end
		local root = rootOf(p.Target)
		if root then
			local ab = nextPosition - p.Position
			local t = math.clamp((root.Position - p.Position):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
			if (root.Position - (p.Position + ab * t)).Magnitude < config.HitRadius + 1 then
				-- A knife in the back knocks you flying (and costs you ground, not the knife)
				if hurt(p.Target, p.Damage, p.Position) then
					local power = throwPower(p.Zone)
					Ragdoll.Tumble(p.Target, p.Direction * (45 * power) + Vector3.new(0, 40 * math.sqrt(power), 0), 1)
				end
				done = true
			end
		end
		p.Position = nextPosition
		p.Traveled += stepLength
		if wall and done and hit then
			-- Missed and hit a wall: it sticks there for a minute
			StuckKnives.Stick(p.Model, hit.Position, p.Direction, 60)
			table.remove(projectiles, i)
		elseif done or p.Traveled > config.FlightRange then
			p.Model:Destroy()
			table.remove(projectiles, i)
		else
			local spin = p.Traveled * 0.5
			p.Model:PivotTo(CFrame.lookAt(p.Position, p.Position + p.Direction) * CFrame.Angles(-spin, 0, 0))
		end
	end
end

-- One step towards `destination`; true once there
-- A real trot, not Codex's bare reference swing (big hip swing + foot lift, replacing
-- Assets.SetRunPhase's fixed small swing), a strong body bounce, a forward lean into the run, and
-- a wagging tail - a sleeping lump turning into a bounding Steal An Egg creature should be obvious
-- from across the runway, not a stiff board sliding along.
local SWING = math.rad(70) -- hip swing, fore/aft (Codex's reference sampler used 22)
local LIFT = 1.4 -- studs the forward-swinging paw lifts (times the creature's scale)
local BOUNCE = 1.1 -- studs the whole body bobs, twice per stride (times the creature's scale)
local LEAN = math.rad(15) -- forward pitch while running
local HEAD_BOB = math.rad(12) -- the head pumps up and down with every stride
local TAIL_WAG = math.rad(30)
local WING_FLAP = math.rad(38) -- griffin / pegasus wings beat, twice a stride
local CLAW_SNAP = math.rad(22) -- the scorpion's pincers open and shut as it runs
local BOB = 0.45 -- studs a halo / flower bobs (times the creature's scale)

local function animateHoundRun(guard: Guard, dt: number, speed: number)
	local hound = guard.Hound
	local geometry = geometryFor(guard.Config.Creature :: string)
	hound.SetPose(guard.Model, "Awake") -- the rest pose; legs/tail are then overridden below
	guard.HoundPhase += dt * speed * 1.1
	local phase = guard.HoundPhase
	local scale = guard.Model:GetScale()
	local pivot = guard.Model:GetPivot()
	for _, p in guard.Model:GetDescendants() do
		if not p:IsA("BasePart") then
			continue
		end
		local group = p:GetAttribute("JointGroup")
		if typeof(group) ~= "string" then
			continue
		end
		if group:sub(1, 3) == "Leg" then
			local joint = (geometry.Joints :: any)[group].Awake :: CFrame
			local sign = if group == "LegFrontLeft" or group == "LegBackRight" then 1 else -1
			local swing = math.sin(phase) * sign
			local lift = math.max(0, swing) * LIFT * scale
			local hinge = pivot * CFrame.new(joint.Position * scale)
			p.CFrame = (hinge * CFrame.Angles(swing * SWING, 0, 0) * hinge:Inverse() * p.CFrame)
				+ Vector3.new(0, lift, 0)
		elseif group == "Tail" then
			local joint = (geometry.Joints :: any).Tail.Awake :: CFrame
			local hinge = pivot * CFrame.new(joint.Position * scale)
			local wag = math.sin(phase * 2) * TAIL_WAG
			p.CFrame = hinge * CFrame.Angles(0, wag, 0) * hinge:Inverse() * p.CFrame
		elseif group == "Head" then
			local joint = (geometry.Joints :: any).Head.Awake :: CFrame
			local hinge = pivot * CFrame.new(joint.Position * scale)
			local nod = math.sin(phase * 2 + 0.6) * HEAD_BOB
			p.CFrame = hinge * CFrame.Angles(nod, 0, 0) * hinge:Inverse() * p.CFrame
		elseif group == "WingLeft" or group == "WingRight" then
			-- a beat around the body's long axis, both wings together (mirrored)
			local joint = (geometry.Joints :: any)[group].Awake :: CFrame
			local hinge = pivot * CFrame.new(joint.Position * scale)
			local flap = math.sin(phase * 2) * WING_FLAP * (if group == "WingLeft" then 1 else -1)
			p.CFrame = hinge * CFrame.Angles(0, 0, flap) * hinge:Inverse() * p.CFrame
		elseif group == "ClawLeft" or group == "ClawRight" then
			local joint = (geometry.Joints :: any)[group].Awake :: CFrame
			local hinge = pivot * CFrame.new(joint.Position * scale)
			local snap = math.max(0, math.sin(phase * 3)) * CLAW_SNAP * (if group == "ClawLeft" then 1 else -1)
			p.CFrame = hinge * CFrame.Angles(0, snap, 0) * hinge:Inverse() * p.CFrame
		elseif group == "Halo" or group == "Bloom" then
			p.CFrame += Vector3.new(0, math.sin(phase * 2 + 1) * BOB * scale, 0)
		end
	end
	-- the whole body bounces twice a stride and leans into the run
	local bounce = (1 - math.cos(phase * 2)) * 0.5 * BOUNCE * scale
	guard.Model:PivotTo((pivot * CFrame.Angles(LEAN, 0, 0)) + Vector3.new(0, bounce, 0))
end

local function moveTowards(guard: Guard, destination: Vector3, speed: number, dt: number): boolean
	local offset = Vector3.new(destination.X - guard.Position.X, 0, destination.Z - guard.Position.Z)
	local distance = offset.Magnitude
	if distance < 0.3 then
		return true
	end
	local arena = MapService.Arena :: MapService.Bounds
	local stepLength = math.min(distance, speed * dt)
	local nextPos = guard.Position + offset.Unit * stepLength
	-- On the lair stage they stand a little higher than on the runway
	local lair = GameConfig.BossLairCenter(guard.Boss.Index)
	local onStage = math.abs(nextPos.X - lair.X) < GameConfig.BossLair.Depth / 2
		and math.abs(nextPos.Z - lair.Z) < GameConfig.BossLair.Width / 2
	local y = guard.FootOffset + (if onStage then PLATFORM else 0)
	nextPos = Vector3.new(
		math.clamp(nextPos.X, arena.MinX + 2, arena.MaxX - 2),
		y,
		math.clamp(nextPos.Z, arena.MinZ - 4, arena.MaxZ - 2)
	)
	guard.Position = nextPos
	guard.Model:PivotTo(CFrame.lookAt(nextPos, nextPos + offset))
	if guard.Hound then
		animateHoundRun(guard, dt, speed)
	end
	if speed > GameConfig.GuardPatrolSpeed then
		animate(guard, "Run", speed / 16)
	else
		animate(guard, "Walk", speed / 10)
	end
	return false
end

local function step(guard: Guard, dt: number)
	local t = now()
	if t < guard.BusyUntil then
		animate(guard, "Idle")
		return
	end

	-- Walking back to the post after a chase
	if guard.Returning then
		-- Walk back round to the front, turn around and settle into the chair without jumping.
		local hop = GameConfig.BossHop
		local post = guard.Boss.Post
		local front = restSpot(guard, post, 1)
		local sitStart = guard.SitStart
		if not sitStart then
			local approach = post.Position + post.LookVector * CHAIR_EXIT
			-- (come in from out front, not through the torch post)
			local towardsFront = (front - guard.Position) * Vector3.new(1, 0, 1)
			if towardsFront.Magnitude > CHAIR_EXIT - hop.Distance + 1 then
				moveTowards(guard, approach, guard.Config.GuardSpeed * 0.6, dt)
				return
			end
			if moveTowards(guard, front, guard.Config.GuardSpeed * 0.6, dt) then
				guard.SitStart = t
				guard.Position = front
				guard.Model:PivotTo(post.Rotation + front)
				animate(guard, "Idle")
				local serverNow = workspace:GetServerTimeNow()
				guard.Model:SetAttribute("WakeAt", nil)
				guard.Model:SetAttribute("WakeEnd", nil)
				guard.Model:SetAttribute("SitAt", serverNow)
				guard.Model:SetAttribute("SitEnd", serverNow + BossChairMotion.SitDuration())
			end
			return
		end
		local x = math.clamp((t - sitStart) / BossChairMotion.SitDuration(), 0, 1)
		guard.Position = restSpot(guard, post, hop.Done - x * (hop.Done - hop.Crouch))
		guard.Model:PivotTo(post.Rotation + guard.Position)
		if guard.Hound then
			-- Lying back down, not an instant snap to Asleep: legs fold, eyes close, over the
			-- same settle a round character backs into its chair with.
			guard.Hound.SetPose(guard.Model, "Waking", 1 - x)
		end
		if x >= 1 then
			guard.Returning = false
			guard.SitStart = nil
			local seat = restSpot(guard, post)
			guard.Position = seat
			guard.Model:PivotTo(post.Rotation + seat)
			setAsleep(guard, true)
			local i = table.find(chasers, guard)
			if i then
				table.remove(chasers, i)
			end
		end
		return
	end

	local thief = guard.Target
	local targetRoot = chaseTarget(guard)
	if not thief or not targetRoot then
		stopChase(guard, thief ~= nil and thief.Parent ~= nil and StealService.BossCarry(thief) == nil)
		return
	end

	-- The wake-up / "!" beat: a fair head start (still in the chair for the first part of it, so
	-- they only turn towards you once they're getting up)
	if t < guard.AlertUntil then
		if guard.Hound then
			-- Waking up (not an instant snap to Awake): eyes open, legs unfold, over the same
			-- head-start a round character gets standing from its chair.
			local span = math.max(guard.WakeUntil - guard.WakeStart, 0.1)
			local blend = math.clamp((t - guard.WakeStart) / span, 0, 1)
			guard.Hound.SetPose(guard.Model, "Waking", blend)
			-- (springing up: a hop as it stands, a big creature's whole body leaving the ground)
			local spring = math.sin(math.pi * blend) * guard.Model:GetScale() * 2.2
			guard.Model:PivotTo(guard.Boss.Post.Rotation + restSpot(guard, guard.Boss.Post) + Vector3.new(0, spring, 0))
			if t >= guard.WakeUntil then
				face(guard, targetRoot.Position)
			end
			return
		end
		if guard.InChair then
			-- Stand and step forward at 1.5x speed; the original alert/head-start time stays intact.
			local post = guard.Boss.Post
			local p = (t - guard.WakeStart)
				/ math.max(BossChairMotion.WakeDuration(guard.AlertUntil - guard.WakeStart), 0.1)
			guard.Position = chairPosition(post, p)
			guard.Model:PivotTo(post.Rotation + guard.Position)
		elseif t >= guard.WakeUntil then
			face(guard, targetRoot.Position)
		end
		animate(guard, "Idle")
		return
	end
	-- Out of the chair: first walk on out in front of it (clear of the torch post beside it), then
	-- turn for the thief
	local exitAt = guard.ExitAt
	if exitAt then
		guard.Alert.Enabled = false
		showTag(guard, false)
		if moveTowards(guard, exitAt, guard.Config.GuardSpeed, dt) then
			guard.ExitAt = nil
		end
		return
	end
	guard.Alert.Enabled = false
	showTag(guard, false)

	-- Winding up a throw: they keep running at you while the arm cranks back, and let go
	-- mid-stride (never stopping, so throwing never costs them ground)
	if guard.WindupUntil > 0 and t >= guard.WindupUntil then
		guard.WindupUntil = 0
		guard.Model:SetAttribute("ChargeStart", nil)
		local aim = targetRoot.Position
		Net.Animate(guard.Model, "Throw")
		task.delay(AnimLibrary.Clips.Throw.Release or 0.07, function()
			if not guard.Dead then
				throwAt(guard, aim, thief)
			end
		end)
	end

	local distance = ((targetRoot.Position - guard.Position) * Vector3.new(1, 0, 1)).Magnitude
	-- (a giant creature's head reaches well past its middle)
	local reachRadius = if guard.Hound
		then GameConfig.CatchRadius * ((guard.Model:GetAttribute("BossHeight") or 13) :: number) / 13
		else GameConfig.CatchRadius
	if distance <= reachRadius then
		-- Grab! They swing without stopping (stopping let a runner slip away every time) and it
		-- counts if you're still within arm's reach when the blow lands
		if t - guard.LastAttack >= GameConfig.GuardAttackCooldown * 0.6 then
			guard.LastAttack = t
			local clip = AnimLibrary.Clips.GuardStab
			Net.Animate(guard.Model, "GuardStab")
			local model = guard.Model
			task.delay(clip.Impact or 0.3, function()
				if guard.Dead or guard.Model ~= model or guard.Target ~= thief then
					return
				end
				local root = chaseTarget(guard)
				local reach = if root
					then ((root.Position - guard.Position) * Vector3.new(1, 0, 1)).Magnitude
					else math.huge
				if root and reach <= reachRadius + 4 then
					snatch(guard, thief)
				end
			end)
		end
		moveTowards(guard, targetRoot.Position, guard.Config.GuardSpeed, dt)
		return
	end
	local throwConfig = GameConfig.GuardThrow
	if
		GameConfig.GuardThrow.Enabled
		and guard.Config.Throws
		and guard.WindupUntil == 0
		and t >= guard.ThrowReadyAt
		and distance > throwConfig.MinRange
		and distance < throwConfig.MaxRange
	then
		guard.WindupUntil = t + throwConfig.Windup
		guard.ThrowReadyAt = guard.WindupUntil + throwConfig.Cooldown
		guard.Model:SetAttribute("ChargeTime", throwConfig.Windup)
		guard.Model:SetAttribute("ChargeStart", workspace:GetServerTimeNow())
	end
	moveTowards(guard, targetRoot.Position, guard.Config.GuardSpeed, dt)
end

-- Stealing -----------------------------------------------------------------------------------------

local function onSteal(player: Player, boss: Boss, slot: Slot)
	local item = slot.Item
	local root = rootOf(player)
	if not item or slot.Out or not root or player:GetAttribute("InRound") or StealService.IsCarrying(player) then
		return
	end
	if (root.Position - slot.Pad.Position).Magnitude > 14 then
		return
	end
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	if #profile.Knives >= PenMode.Capacity(profile.Slots) then
		Net.Notify(player, "Your vault is full! Sell a knife first.", "bad")
		return
	end
	-- (no "too slow" warning: Steal An Egg doesn't stop you either - grab it, run, find out)
	slot.Item = nil
	slot.Out = true
	clearDisplay(slot)
	StealService.StartCarry(player, "Knife", item, { Zone = boss.Index, Slot = slot.Index })
	sendChaser(boss, player)
end

-- A stolen boss knife left its thief's hands (StealService): back on the wall, or delivered
local function onBossCarryEnded(zone: number, slotIndex: number, item: string, delivered: boolean)
	local boss = bosses[zone]
	local slot = boss and boss.Slots[slotIndex]
	if not boss or not slot then
		return
	end
	if delivered then
		slot.Out = false
		slot.RestockAt = now() + boss.Config.Restock
	else
		setSlot(boss, slot, item)
		-- Put down (the Drop button) or lost: whoever was chasing for this boss and whose thief no
		-- longer holds one of its knives gives up and heads back
		for _, guard in table.clone(chasers) do
			local thief = guard.Target
			if guard.Boss == boss and thief and StealService.BossCarry(thief) == nil then
				stopChase(guard, false)
			end
		end
		local guard = boss.Guard
		if guard.Target and StealService.BossCarry(guard.Target) == nil then
			stopChase(guard, false)
		end
	end
end

-- API used by powers, combat and raids ------------------------------------------------------------

function GuardService.RootHeight(): number
	return PERSON_HEIGHT
end

-- Every boss and every chasing shadow (Radar, traps, Flash and Decoy look through these)
function GuardService.All(): { Guard }
	local list = {}
	for _, boss in bosses do
		table.insert(list, boss.Guard)
	end
	for _, guard in chasers do
		if guard.IsShadow and not guard.Dead then
			table.insert(list, guard)
		end
	end
	return list
end

-- Frozen in place for a while (only matters mid-chase): the Escape consumable
function GuardService.Stun(guard: Guard, seconds: number)
	if guard.Dead or not guard.Target then
		return
	end
	guard.BusyUntil = math.max(guard.BusyUntil, now() + seconds)
	guard.WindupUntil = 0
	guard.Model:SetAttribute("ChargeStart", nil)
	Net.Animate(guard.Model, "GuardHurt")
end

function GuardService.FromPart(part: Instance): Guard?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local guard = guardByModel[model]
		if guard then
			return guard
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

function GuardService.InReach(position: Vector3, look: Vector3, range: number): Guard?
	local best, bestDist = nil, range
	for _, guard in GuardService.All() do
		local offset = guard.Position - position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local dist = flat.Magnitude
		local facing = if dist > 0.1 then look:Dot(flat.Unit) else 1
		if dist < bestDist and facing > -0.1 then
			best, bestDist = guard, dist
		end
	end
	return best
end

-- Hit by a hub knife (swing or throw). A chaser staggers - longer for better knives, with a short
-- immunity after so nobody can lock one down forever. A boss at their post just ignores you.
-- What a boss shouts when you hit them (floating text over their head, for the attacker)
local QUIPS = {
	Idle = { "Ow! Rude!", "That tickles!", "HEY!", "Not the face!", "Is that all?", "Go steal something!" },
	Stagger = { "OOF!", "ARGH!", "Lucky shot!", "You'll pay for that!", "Grr...!", "OUCH!", "My knees!" },
	Resist = { "Ha! Too slow!", "Nice try!", "Missed me!", "Not again!" },
}
local function quip(guard: Guard, attacker: Player?, kind: string, extra: string?)
	if not attacker then
		return
	end
	local lines = QUIPS[kind]
	local line = lines[rng:NextInteger(1, #lines)]
	Net.Remotes.Effect:FireClient(
		attacker,
		"Damage",
		guard.Position + Vector3.new(0, 3 * GameConfig.BossScale, 0),
		if extra then `{line} {extra}` else line
	)
end

function GuardService.Damage(guard: Guard, amount: number, attacker: Player?)
	if guard.Dead then
		return
	end
	local head = guard.Model:FindFirstChild("Head") :: BasePart?
	Net.Remotes.Effect:FireAllClients("Hit", if head then head.Position else guard.Position)
	if attacker then
		Analytics.Count(attacker, if guard.Target then "boss_hits_chasing" else "boss_hits_idle")
	end
	if not guard.Target then
		quip(guard, attacker, "Idle")
		return
	end
	local t = now()
	if t < guard.StaggerImmuneUntil then
		quip(guard, attacker, "Resist")
		return
	end
	local seconds = math.clamp(amount / guard.Config.Health * 3, 0.3, 2.2)
	guard.BusyUntil = math.max(guard.BusyUntil, t + seconds)
	guard.StaggerImmuneUntil = t + seconds + 0.8
	guard.WindupUntil = 0
	guard.Model:SetAttribute("ChargeStart", nil)
	Net.Animate(guard.Model, "GuardHurt")
	if attacker then
		quip(guard, attacker, "Stagger", string.format("(%.1fs)", seconds))
		-- Knocked back a step, away from whoever hit them
		local attackerRoot = rootOf(attacker)
		if attackerRoot then
			local away = (guard.Position - attackerRoot.Position) * Vector3.new(1, 0, 1)
			if away.Magnitude > 0.1 then
				guard.Position += away.Unit * 2
				guard.Model:PivotTo(CFrame.lookAt(guard.Position, guard.Position - away))
			end
		end
	end
end

-- Init ---------------------------------------------------------------------------------------------

-- The boss whose lair is nearest a point (and that lair's centre)
nearestBoss = function(position: Vector3): { Boss: Boss, Position: Vector3 }?
	local best, bestDistance = nil, math.huge
	for index, boss in bosses do
		local center = GameConfig.BossLairCenter(index)
		local distance = (center - position).Magnitude
		if distance < bestDistance then
			best, bestDistance = { Boss = boss, Position = center }, distance
		end
	end
	return best
end

-- Slots that are empty and still waiting to restock for a while
emptySlots = function(boss: Boss, t: number): number
	local count = 0
	for _, slot in boss.Slots do
		if not slot.Item and not slot.Out and slot.RestockAt and slot.RestockAt - t > 15 then
			count += 1
		end
	end
	return count
end

-- Robux "Restock the Boss": the nearest boss's empty slots refill on the next restock tick.
-- Returns the boss's name, or nil if nothing there was waiting.
function GuardService.RestockNear(player: Player): string?
	local root = rootOf(player)
	local found = root and nearestBoss(root.Position)
	if not found then
		return nil
	end
	local t = now()
	local any = false
	for _, slot in found.Boss.Slots do
		if not slot.Item and not slot.Out and slot.RestockAt then
			slot.RestockAt = t
			any = true
		end
	end
	return if any then GameConfig.MonsterName(found.Boss.Index) else nil
end

-- The night reset (after every murder round, RoundService): every boss's stash is re-rolled at once
-- - fresh coffins everywhere, Steal An Egg's egg reset - except a slot someone is still carrying
-- off. Returns how many slots were refreshed.
function GuardService.RestockAll(): number
	local count = 0
	for _, boss in bosses do
		for _, slot in boss.Slots do
			if not slot.Out then
				local item = rollItem(boss)
				setSlot(boss, slot, item)
				announceIfRare(boss, item)
				count += 1
			end
		end
	end
	return count
end

-- Studio tests (DebugService "BossSteal"): stand the player by a stocked slot of this boss's wall
-- and steal it, exactly as the prompt would
function GuardService.DebugSteal(player: Player, zone: number): boolean
	local boss = bosses[zone]
	local root = rootOf(player)
	if not boss or not root then
		return false
	end
	for _, slot in boss.Slots do
		if slot.Item and not slot.Out then
			-- (move only if out of reach: a jump right before carrying trips the speed check)
			if (root.Position - slot.Pad.Position).Magnitude > 12 then
				root.CFrame = CFrame.new(slot.Pad.Position + Vector3.new(0, 4, 0))
				task.wait(2)
			end
			onSteal(player, boss, slot)
			return true
		end
	end
	return false
end

function GuardService.Init()
	folder = Instance.new("Folder")
	folder.Name = "Guards"
	folder.Parent = workspace:FindFirstChild("Map")
	projectileFolder = Instance.new("Folder")
	projectileFolder.Name = "GuardKnives"
	projectileFolder.Parent = workspace:FindFirstChild("Map")

	BossTitleModel.Preload()

	-- How high a rig's root sits so feet touch the floor
	local probe = Disguises.BuildCharacter("Frank")
	local function rootHeight(): number
		local probeHumanoid = probe:FindFirstChildOfClass("Humanoid") :: Humanoid
		return probeHumanoid.HipHeight + (probe:FindFirstChild("HumanoidRootPart") :: BasePart).Size.Y / 2
	end
	PERSON_HEIGHT = rootHeight()
	probe:ScaleTo(GameConfig.BossScale)
	HEIGHT = rootHeight()
	probe:Destroy()

	-- All eight lairs build side by side (each loads its boss's outfit and knives), not in turn
	local building = 0
	for i, config in GameConfig.Zones do
		building += 1
		task.spawn(function()
			local ok, err = pcall(function()
				local zone = MapService.Zones[i]
				local boss = buildLair(i, zone, config :: any)
				boss.Guard = newGuard(boss, false, boss.Post)
				setAsleep(boss.Guard, true)
				bosses[i] = boss
			end)
			if not ok then
				warn(`[GuardService] lair {i} failed: {err}`)
			end
			building -= 1
		end)
	end
	while building > 0 do
		task.wait()
	end
	for _, boss in bosses do
		for _, slot in boss.Slots do
			setSlot(boss, slot, rollItem(boss))
			local thisSlot = slot
			slot.Prompt.Triggered:Connect(function(player)
				onSteal(player, boss, thisSlot)
			end)
			-- Started holding E (vs. Triggered = finished): the gap is people who lost their nerve
			slot.Prompt.PromptButtonHoldBegan:Connect(function(player)
				Analytics.Track(player, "boss.hold", { zone = boss.Index, chasing = boss.Guard.Target ~= nil })
			end)
		end
	end

	StealService.OnBossCarryEnded = onBossCarryEnded
	StealService.OnSuspendBoss = function(player: Player, zone: number): (CFrame?, boolean)
		-- Where the boss is right now, and whether it was chasing this thief (saved across the round)
		for _, guard in chasers do
			if guard.Target == player and not guard.Dead then
				return guard.Model:GetPivot(), true
			end
		end
		local boss = bosses[zone]
		if boss and boss.Guard and not boss.Guard.Dead and boss.Guard.Target == nil then
			return boss.Guard.Model:GetPivot(), false
		end
		return nil, false
	end
	StealService.OnResumeBoss = function(player: Player, zone: number, at: CFrame?, chasing: boolean)
		local boss = bosses[zone]
		if not boss then
			return
		end
		if chasing then
			sendChaser(boss, player, at)
		elseif at and boss.Guard and boss.Guard.Target == nil then
			-- It had given up: back where it was, walking home to its post
			local guard = boss.Guard
			guard.Position = at.Position
			guard.Model:PivotTo(at)
			guard.Returning = true
			if not table.find(chasers, guard) then
				table.insert(chasers, guard)
			end
		end
	end

	-- Restocks, once a second
	local restockCheck = 0
	task.spawn(function()
		while true do
			task.wait(1)
			local t = now()
			-- Someone standing at a mostly empty wall: offer the restock (every few seconds)
			restockCheck += 1
			if restockCheck % 4 == 0 then
				for _, player in Players:GetPlayers() do
					local root = rootOf(player)
					local boss = root and nearestBoss(root.Position)
					if
						boss
						and not player:GetAttribute("Carrying")
						and (boss.Position - (root :: BasePart).Position).Magnitude < GameConfig.Consumables.RestockOfferRange
						and emptySlots(boss.Boss, t) >= 2
					then
						Offers.Show(player, "BossRestock", "This wall is empty! Fill it with new knives right now.")
					end
				end
			end
			for _, boss in bosses do
				local stocked = 0
				for _, slot in boss.Slots do
					if slot.RestockAt and t >= slot.RestockAt and not slot.Item and not slot.Out then
						local item = rollItem(boss)
						setSlot(boss, slot, item)
						Net.Remotes.Effect:FireAllClients("Smoke", slot.Spot.Position)
						announceIfRare(boss, item)
					end
					if slot.Prompt.Enabled then
						stocked += 1
					end
				end
				-- how many knives are on this wall right now (client/Guide: steal here, or wait / train)
				if boss.Folder:GetAttribute("Stocked") ~= stocked then
					boss.Folder:SetAttribute("Stocked", stocked)
					boss.Folder:SetAttribute("Zone", boss.Index)
				end
			end
		end
	end)

	-- Only chasers think; a boss at their post just stands there (the client fidgets them)
	RunService.Heartbeat:Connect(function(dt: number)
		for i = #chasers, 1, -1 do
			local guard = chasers[i]
			if guard and not guard.Dead then
				step(guard, dt)
			end
		end
		stepProjectiles(dt)
	end)
end

return GuardService
