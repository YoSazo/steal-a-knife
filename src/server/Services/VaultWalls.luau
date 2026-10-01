--!strict
-- Builds a vault's walls and gate for its wall tier (GameConfig.Walls). Higher tiers are taller and
-- scarier, so the plaza shows off who's doing well:
--   1 Wooden Palisade   planks, sharpened stakes, torch-lit gate posts
--   2 Stone Keep        cobblestone, battlements, torches and banners
--   3 Iron Bastion      riveted plate, spikes, red warning lamps
--   4 Bone Fortress     bleached stone, bone spikes, skulls on the gate towers
--   5 Cursed Citadel    black basalt, glowing purple runes, floating crystals
--   6 Void Sanctum      black glass edged in cyan light, orbiting shards, a portal gate
-- Everything is built in the vault's own frame (local +Z = the open side facing the plaza). The
-- gate is a portcullis between two towers; its invisible "Blocker" is what raiders hit and what
-- clients make solid for everyone but the owner (see client/Raid). Gate state lives in attributes
-- on the Blocker: Owner, Health, MaxHealth, Open, Tier.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Props = require(ReplicatedStorage.Shared.Props)

local VaultWalls = {}

local HALF_W, HALF_D = 20, 22 -- vault is 40 wide, 44 deep
local T = 1.5 -- wall thickness
local GATE_HALF = 8 -- gate opening is 16 wide
local GATE_H = 11
local TOWER = 3.2

export type Built = {
	Gate: Model,
	Blocker: Part,
	Height: number,
	BackHeight: number,
}

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

local function deco(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = block(parent, name, size, cframe, color, material)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function wedge(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = size
	w.CFrame = cframe
	w.Color = color
	w.Material = material or Enum.Material.SmoothPlastic
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.Parent = parent
	return w
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
end

local function torch(parent: Instance, cframe: CFrame)
	deco(parent, "TorchStick", Vector3.new(0.3, 1.6, 0.3), cframe, Color3.fromRGB(70, 45, 25), Enum.Material.Wood)
	local head = deco(
		parent,
		"TorchHead",
		Vector3.new(0.5, 0.5, 0.5),
		cframe * CFrame.new(0, 0.95, 0),
		Color3.fromRGB(255, 160, 60),
		Enum.Material.Neon
	)
	local fire = Instance.new("Fire")
	fire.Size = 2.5
	fire.Heat = 6
	fire.Color = Color3.fromRGB(255, 140, 50)
	fire.SecondaryColor = Color3.fromRGB(255, 220, 120)
	fire.Parent = head
	light(head, Color3.fromRGB(255, 160, 80), 16, 1.6)
end

-- Every wall's top edge in vault-local space: start, end (x/z), and the wall's height there
type Edge = { From: Vector3, To: Vector3, Height: number }

-- Things along the top of every wall, spaced `step` apart
local function alongTops(edges: { Edge }, step: number, place: (CFrame, number) -> ())
	for _, edge in edges do
		local along = edge.To - edge.From
		local length = along.Magnitude
		local count = math.max(1, math.floor(length / step))
		for i = 0, count do
			local point = edge.From + along * (i / count)
			-- Facing along the wall
			place(CFrame.lookAt(point, point + along.Unit), edge.Height)
		end
	end
end

-- A Blender prop placed as decoration: anchored, no collisions, optional scale and recolour
local function prop(
	parent: Instance,
	name: string,
	cframe: CFrame,
	scale: number?,
	recolor: { [string]: Color3 }?
): Model
	local model = Props.Build(name, true)
	if scale then
		model:ScaleTo(scale)
	end
	model:PivotTo(cframe)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			if recolor and recolor[d.Name] then
				d.Color = recolor[d.Name]
			end
		end
	end
	model.Parent = parent
	return model
end

local function skull(parent: Instance, cframe: CFrame)
	-- Faces out over the plaza (the vault's +Z), glaring red
	prop(parent, "Skull", cframe * CFrame.Angles(0, math.pi, 0), 1.35)
end

-- Builds (or rebuilds) a vault's walls into `folder`. `color` is the vault's own colour (the neon
-- strip along the top and the gate's glow), `tierIndex` its wall tier.
function VaultWalls.Build(folder: Folder, frame: CFrame, color: Color3, tierIndex: number): Built
	folder:ClearAllChildren()
	local tier = GameConfig.Walls[math.clamp(tierIndex, 1, #GameConfig.Walls)]
	local H = tier.Height
	local backH = math.max(16, H + 3)
	local wallColor, trim, material = tier.Color, tier.Trim, tier.Material
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local function wall(name: string, size: Vector3, cframe: CFrame): Part
		local p = block(folder, name, size, cframe, wallColor, material)
		if tierIndex == 6 then
			p.Transparency = 0.15
			p.Reflectance = 0.2
		end
		return p
	end

	-- The shell: back wall (taller, the trophy wall hangs on it), side walls kept inside this
	-- vault's half of the shared line so neighbours never overlap, and the front either side of the gate
	wall("BackWall", Vector3.new(HALF_W * 2, backH, T), at(0, backH / 2, -HALF_D))
	for _, side in { -1, 1 } do
		wall("SideWall", Vector3.new(T, H, HALF_D * 2), at(side * (HALF_W - T / 2), H / 2, 0))
		local frontFrom = GATE_HALF + TOWER
		local frontLength = HALF_W - frontFrom
		wall(
			"FrontWall",
			Vector3.new(frontLength, H, T),
			at(side * (frontFrom + frontLength / 2), H / 2, HALF_D - T / 2)
		)
	end
	-- Gate towers, a little taller than the walls
	local towerH = H + 3
	local towers: { CFrame } = {}
	for _, side in { -1, 1 } do
		local cf = at(side * (GATE_HALF + TOWER / 2), towerH / 2, HALF_D - TOWER / 2 + 0.3)
		local tower =
			block(folder, "GateTower", Vector3.new(TOWER, towerH, TOWER), cf, wallColor:Lerp(trim, 0.25), material)
		if tierIndex == 6 then
			tower.Transparency = 0.1
			tower.Reflectance = 0.25
		end
		deco(
			folder,
			"TowerCap",
			Vector3.new(TOWER + 0.6, 0.7, TOWER + 0.6),
			cf * CFrame.new(0, towerH / 2 + 0.35, 0),
			trim,
			if tierIndex >= 5 then Enum.Material.Neon else Enum.Material.Metal
		)
		table.insert(towers, cf * CFrame.new(0, towerH / 2 + 0.7, 0))
	end
	-- Over the gate: a lintel bridging the towers
	if H > GATE_H + 0.5 then
		wall("Lintel", Vector3.new(GATE_HALF * 2, H - GATE_H, T), at(0, GATE_H + (H - GATE_H) / 2, HALF_D - T / 2))
	end
	deco(
		folder,
		"GateBeam",
		Vector3.new(GATE_HALF * 2 + 0.4, 0.8, T + 0.3),
		at(0, GATE_H + 0.4, HALF_D - T / 2),
		trim,
		Enum.Material.Metal
	)

	-- The owner's colour, a neon line along every wall top (spot your vault from the runway)
	local edges: { Edge } = {
		{ From = Vector3.new(-HALF_W, 0, -HALF_D), To = Vector3.new(HALF_W, 0, -HALF_D), Height = backH },
	}
	for _, side in { -1, 1 } do
		table.insert(edges, {
			From = Vector3.new(side * (HALF_W - T / 2), 0, -HALF_D + 1),
			To = Vector3.new(side * (HALF_W - T / 2), 0, HALF_D - 1),
			Height = H,
		})
		table.insert(edges, {
			From = Vector3.new(side * (GATE_HALF + TOWER + 0.5), 0, HALF_D - T / 2),
			To = Vector3.new(side * (HALF_W - 0.5), 0, HALF_D - T / 2),
			Height = H,
		})
	end
	for _, edge in edges do
		local mid = (edge.From + edge.To) / 2
		local length = (edge.To - edge.From).Magnitude
		local strip = deco(
			folder,
			"Strip",
			Vector3.new(0.35, 0.35, length),
			frame
				* CFrame.lookAt(
					Vector3.new(mid.X, edge.Height + 0.15, mid.Z),
					Vector3.new(edge.To.X, edge.Height + 0.15, edge.To.Z)
				),
			color,
			Enum.Material.Neon
		)
		strip.Name = "Strip"
	end

	-- Tier decorations along the tops and on the towers
	local function topPlacer(make: (CFrame) -> ())
		return function(cf: CFrame, height: number)
			make(frame * (cf + Vector3.new(0, height, 0)))
		end
	end
	if tierIndex == 1 then
		-- Sharpened stakes
		alongTops(
			edges,
			1.6,
			topPlacer(function(cf)
				wedge(
					folder,
					"Stake",
					Vector3.new(0.9, 1.4, 0.45),
					cf * CFrame.new(0, 0.7, 0.22),
					trim,
					Enum.Material.Wood
				)
				wedge(
					folder,
					"Stake",
					Vector3.new(0.9, 1.4, 0.45),
					cf * CFrame.new(0, 0.7, -0.22) * CFrame.Angles(0, math.pi, 0),
					trim,
					Enum.Material.Wood
				)
			end)
		)
		for _, cf in towers do
			torch(folder, cf * CFrame.new(0, 0.8, 0))
		end
	elseif tierIndex == 2 or tierIndex == 3 then
		-- Battlements
		alongTops(
			edges,
			3,
			topPlacer(function(cf)
				deco(
					folder,
					"Merlon",
					Vector3.new(T + 0.3, 1.5, 1.6),
					cf * CFrame.new(0, 0.75, 0),
					wallColor:Lerp(trim, 0.3),
					material
				)
			end)
		)
		if tierIndex == 3 then
			-- Spikes between the merlons and a red warning lamp on each tower
			alongTops(
				edges,
				3,
				topPlacer(function(cf)
					wedge(
						folder,
						"Spike",
						Vector3.new(0.3, 1.8, 0.5),
						cf * CFrame.new(0, 0.9, 1.5),
						Color3.fromRGB(40, 40, 46),
						Enum.Material.Metal
					)
				end)
			)
			for _, cf in towers do
				local lamp = deco(
					folder,
					"WarningLamp",
					Vector3.new(0.9, 0.9, 0.9),
					cf * CFrame.new(0, 0.6, 0),
					Color3.fromRGB(255, 50, 40),
					Enum.Material.Neon
				)
				lamp.Shape = Enum.PartType.Ball
				lamp:AddTag("Flicker")
				light(lamp, Color3.fromRGB(255, 60, 40), 18, 1.5)
			end
		else
			for _, cf in towers do
				torch(folder, cf * CFrame.new(0, 0.8, 0))
				-- A banner in the owner's colour hanging down the tower's front
				local banner = deco(
					folder,
					"Banner",
					Vector3.new(2.2, 4.5, 0.12),
					cf * CFrame.new(0, -3.4, -TOWER / 2 - 0.4),
					color,
					Enum.Material.Fabric
				)
				banner.Name = "Banner"
			end
		end
	elseif tierIndex == 4 then
		-- Bone spikes leaning outward, skulls on the towers
		alongTops(
			edges,
			2.2,
			topPlacer(function(cf)
				-- Curved horns, each turned a little differently
				prop(
					folder,
					"BoneSpike",
					cf
						* CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
						* CFrame.Angles(math.rad(math.random(-10, 10)), 0, 0),
					0.75 + math.random() * 0.4
				)
			end)
		)
		for _, cf in towers do
			skull(folder, cf * CFrame.new(0, 0.9, 0))
			torch(folder, cf * CFrame.new(1.1, 0.6, 1.1))
		end
		-- A blood-red band around the walls
		for _, edge in edges do
			local mid = (edge.From + edge.To) / 2
			local length = (edge.To - edge.From).Magnitude
			deco(
				folder,
				"Band",
				Vector3.new(T + 0.2, 0.8, length),
				frame
					* CFrame.lookAt(
						Vector3.new(mid.X, edge.Height - 2, mid.Z),
						Vector3.new(edge.To.X, edge.Height - 2, edge.To.Z)
					),
				trim,
				Enum.Material.Fabric
			)
		end
	elseif tierIndex == 5 then
		alongTops(
			edges,
			3,
			topPlacer(function(cf)
				deco(folder, "Merlon", Vector3.new(T + 0.3, 1.8, 1.4), cf * CFrame.new(0, 0.9, 0), wallColor, material)
			end)
		)
		-- Glowing runes cut into the outside of the walls
		alongTops(
			edges,
			6,
			topPlacer(function(cf)
				for i = 1, 3 do
					deco(
						folder,
						"Rune",
						Vector3.new(T + 0.1, 0.25, 1.4),
						cf * CFrame.new(0, -2 - i * 2.2, 0) * CFrame.Angles(math.rad((i % 2) * 2 - 1) * 35, 0, 0),
						trim,
						Enum.Material.Neon
					)
				end
			end)
		)
		for _, cf in towers do
			local cluster = prop(folder, "Crystal", cf * CFrame.new(0, 0.6, 0), 1.3, { Crystal = trim })
			cluster:AddTag("Spin")
			local crystal = cluster:FindFirstChild("Crystal") :: BasePart? or cluster.PrimaryPart :: BasePart
			light(crystal, trim, 22, 2)
			local flames = Instance.new("ParticleEmitter")
			flames.Texture = "rbxasset://textures/particles/fire_main.dds"
			flames.Color = ColorSequence.new(trim, Color3.fromRGB(40, 0, 70))
			flames.LightEmission = 1
			flames.Rate = 14
			flames.Lifetime = NumberRange.new(0.6, 1.1)
			flames.Speed = NumberRange.new(2, 4)
			flames.Size = NumberSequence.new(1.2, 0)
			flames.Parent = crystal
		end
	else
		-- Void: cyan light along every edge, shards orbiting over the towers
		for _, edge in edges do
			local mid = (edge.From + edge.To) / 2
			local length = (edge.To - edge.From).Magnitude
			for _, y in { edge.Height - 0.1, 0.4 } do
				deco(
					folder,
					"VoidEdge",
					Vector3.new(0.3, 0.3, length),
					frame * CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(edge.To.X, y, edge.To.Z)),
					trim,
					Enum.Material.Neon
				)
			end
		end
		for _, cf in towers do
			for i = 1, 4 do
				local angle = i / 4 * math.pi * 2
				local shard = deco(
					folder,
					"Shard",
					Vector3.new(0.5, 1.8, 0.5),
					cf
						* CFrame.new(math.cos(angle) * 2.4, 2 + i * 0.4, math.sin(angle) * 2.4)
						* CFrame.Angles(0.4, angle, 0.3),
					Color3.fromRGB(10, 6, 18),
					Enum.Material.Glass
				)
				shard:AddTag("Spin")
			end
			local core = deco(
				folder,
				"VoidCore",
				Vector3.new(1.4, 1.4, 1.4),
				cf * CFrame.new(0, 2.6, 0),
				trim,
				Enum.Material.Neon
			)
			core.Shape = Enum.PartType.Ball
			light(core, trim, 24, 2.2)
		end
	end

	-- The gate: a portcullis (or, for the Void, a portal) filling the opening
	local gate = Instance.new("Model")
	gate.Name = "Gate"
	local gateZ = HALF_D - T / 2
	if tierIndex == 6 then
		local portal = deco(
			gate,
			"Bars",
			Vector3.new(GATE_HALF * 2, GATE_H, 0.3),
			at(0, GATE_H / 2, gateZ),
			trim,
			Enum.Material.ForceField
		)
		portal.Transparency = 0.1
	else
		local barColor = if tierIndex == 1 then Color3.fromRGB(60, 40, 26) else trim:Lerp(Color3.new(0, 0, 0), 0.35)
		local barMaterial = if tierIndex == 1 then Enum.Material.Wood else Enum.Material.Metal
		local bars = math.floor(GATE_HALF * 2 / 1.6)
		for i = 0, bars do
			local x = -GATE_HALF + 0.4 + i * (GATE_HALF * 2 - 0.8) / bars
			deco(gate, "Bars", Vector3.new(0.35, GATE_H, 0.35), at(x, GATE_H / 2, gateZ), barColor, barMaterial)
			-- Pointed bottoms
			wedge(
				gate,
				"Bars",
				Vector3.new(0.35, 0.5, 0.35),
				at(x, 0.25, gateZ) * CFrame.Angles(math.pi, 0, 0),
				barColor,
				barMaterial
			)
		end
		for _, y in { 2.4, 5.6, 8.8 } do
			deco(gate, "Bars", Vector3.new(GATE_HALF * 2, 0.35, 0.4), at(0, y, gateZ), barColor, barMaterial)
		end
		-- The owner's glow behind the bars: this vault is sealed
		local pane = deco(
			gate,
			"Pane",
			Vector3.new(GATE_HALF * 2, GATE_H, 0.1),
			at(0, GATE_H / 2, gateZ - 0.4),
			color,
			Enum.Material.ForceField
		)
		pane.Transparency = 0.35
	end
	-- What actually blocks (on clients) and what raiders hit
	local blocker =
		block(gate, "Blocker", Vector3.new(GATE_HALF * 2, GATE_H, 1.2), at(0, GATE_H / 2, gateZ), Color3.new(), nil)
	blocker.Transparency = 1
	blocker.CanCollide = false -- each client decides (the owner walks through, everyone else bumps)
	blocker.CanQuery = true
	blocker.CanTouch = false
	blocker:AddTag("VaultGate")
	for _, d in gate:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("BaseTransparency", d.Transparency)
		end
	end
	-- Health bar, shown during raids
	local gui = Instance.new("BillboardGui")
	gui.Name = "GateHealth"
	gui.Size = UDim2.fromOffset(200, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, GATE_H / 2 + 2.6, 0)
	gui.MaxDistance = 160
	gui.Enabled = false
	gui.Adornee = blocker
	gui.Parent = blocker
	local name = Instance.new("TextLabel")
	name.Name = "Title"
	name.Size = UDim2.new(1, 0, 0, 20)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0
	name.Text = tier.Name
	name.Parent = gui
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Position = UDim2.fromOffset(0, 24)
	back.Size = UDim2.new(1, 0, 0, 16)
	back.BackgroundColor3 = Color3.fromRGB(30, 20, 30)
	back.BorderSizePixel = 0
	back.Parent = gui
	Instance.new("UICorner").Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	Instance.new("UICorner").Parent = fill
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(20, 16, 24)
	stroke.Parent = back
	gate.PrimaryPart = blocker
	gate.Parent = folder

	blocker:SetAttribute("Tier", tierIndex)
	blocker:SetAttribute("MaxHealth", tier.GateHealth)
	blocker:SetAttribute("Health", tier.GateHealth)
	return { Gate = gate, Blocker = blocker, Height = H, BackHeight = backH }
end

-- Broken gates: the bars vanish (and come back when it reforges)
function VaultWalls.SetOpen(gate: Model, open: boolean)
	for _, d in gate:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Blocker" then
			local base = d:GetAttribute("BaseTransparency")
			d.Transparency = if open then 1 else (if type(base) == "number" then base else 0)
		end
	end
	local blocker = gate:FindFirstChild("Blocker")
	if blocker then
		blocker:SetAttribute("Open", open or nil)
	end
end

return VaultWalls
