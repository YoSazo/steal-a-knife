--!strict
-- Classic murder-game disguises: for a round, every player becomes a pre-made character with a
-- first name and a fixed outfit ("Nick", "Frank", "Rose"...), so nobody can tell who is behind
-- the Murderer. Blocky default bodies wearing painted classic clothing (tools/make_clothing.py),
-- cartoon face decals and Blender hair / hats (blender/scripts/accessories.py -> PropMeshes).
-- The real look comes back when the round ends.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Props = require(ReplicatedStorage.Shared.Props)
local CharacterFaces = require(script.Parent.CharacterFaces)
local CharacterDetails = require(script.Parent.CharacterDetails)

local Disguises = {}

-- One accessory: a PropMeshes key, recoloured. Color paints the Hair / Hat / Frame parts, Trim the
-- Trim / Tie parts (hat bands, brims, ponytail ties, headphone cups).
export type Wear = { Prop: string, Color: Color3?, Trim: Color3?, On: string? } -- On: body part (default Head)

type Outfit = {
	Name: string,
	Skin: Color3,
	Shirt: string, -- classic shirt template (uploaded image)
	Pants: string,
	Face: string,
	Wear: { Wear },
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Same order as SKIN in tools/make_clothing.py (that list is 0-based)
local SKIN = { rgb(255, 204, 153), rgb(234, 184, 146), rgb(204, 142, 105), rgb(124, 92, 70), rgb(245, 205, 48) }

-- Drawn by tools/make_faces.py (512px, 4x supersampled), uploaded as images
local FACES = {
	Angry = "rbxassetid://84558222936421",
	Cheeky = "rbxassetid://94635670686306",
	Chill = "rbxassetid://77301303588999",
	Determined = "rbxassetid://132969218020669",
	Freckles = "rbxassetid://108002712515013",
	Grin = "rbxassetid://83376711920116",
	Happy = "rbxassetid://80477324382185",
	Lashes = "rbxassetid://120029999967726",
	Smile = "rbxassetid://137483136763270",
	Smirk = "rbxassetid://93391310013128",
	Surprised = "rbxassetid://75573684402533",
	Wink = "rbxassetid://138211541316773",
}

local OUTFITS: { Outfit } = {
	{
		Name = "Nick",
		Skin = SKIN[5],
		Shirt = "rbxassetid://95677480024122",
		Pants = "rbxassetid://138894592345744",
		Face = FACES.Determined,
		Wear = {
			{ Prop = "HairSwoop", Color = rgb(105, 40, 30) },
			{ Prop = "ShutterShades", Color = rgb(245, 245, 245) },
		},
	},
	{
		Name = "Frank",
		Skin = SKIN[1],
		Shirt = "rbxassetid://121001848108826",
		Pants = "rbxassetid://118712505468034",
		Face = FACES.Angry,
		Wear = { { Prop = "Cap", Color = rgb(200, 30, 40), Trim = rgb(200, 30, 40) } },
	},
	{
		Name = "Rose",
		Skin = SKIN[2],
		Shirt = "rbxassetid://107934248336704",
		Pants = "rbxassetid://73411295491442",
		Face = FACES.Lashes,
		Wear = { { Prop = "HairLong", Color = rgb(255, 210, 90) } },
	},
	{
		Name = "Lucy",
		Skin = SKIN[1],
		Shirt = "rbxassetid://74568680751515",
		Pants = "rbxassetid://127963485526269",
		Face = FACES.Wink,
		Wear = {
			{ Prop = "HairBob", Color = rgb(80, 45, 25) },
			{ Prop = "Beanie", Color = rgb(230, 40, 40), Trim = rgb(245, 245, 245) },
		},
	},
	{
		Name = "Jake",
		Skin = SKIN[3],
		Shirt = "rbxassetid://102089062714861",
		Pants = "rbxassetid://93715269903522",
		Face = FACES.Happy,
		Wear = { { Prop = "HairMessy", Color = rgb(120, 80, 45) } },
	},
	{
		Name = "Emma",
		Skin = SKIN[2],
		Shirt = "rbxassetid://119790783596328",
		Pants = "rbxassetid://122789398619655",
		Face = FACES.Freckles,
		Wear = {
			{ Prop = "HairPonytail", Color = rgb(80, 45, 25), Trim = rgb(90, 200, 120) },
			{ Prop = "RoundGlasses", Color = rgb(25, 25, 28) },
		},
	},
	{
		Name = "Oscar",
		Skin = SKIN[4],
		Shirt = "rbxassetid://110710971824580",
		Pants = "rbxassetid://95926429468333",
		Face = FACES.Chill,
		Wear = {
			{ Prop = "HairAfro", Color = rgb(30, 20, 14) },
		},
	},
	{
		Name = "Mia",
		Skin = SKIN[1],
		Shirt = "rbxassetid://129412155369857",
		Pants = "rbxassetid://86579477798846",
		Face = FACES.Lashes,
		Wear = { { Prop = "HairBuns", Color = rgb(255, 150, 200), Trim = rgb(255, 255, 255) } },
	},
	{
		Name = "Leo",
		Skin = SKIN[3],
		Shirt = "rbxassetid://122887375166293",
		Pants = "rbxassetid://119111877490533",
		Face = FACES.Smirk,
		Wear = { { Prop = "TopHat", Color = rgb(25, 25, 28), Trim = rgb(170, 30, 40) } },
	},
	{
		Name = "Zoe",
		Skin = SKIN[4],
		Shirt = "rbxassetid://89539205752774",
		Pants = "rbxassetid://126825022549279",
		Face = FACES.Happy,
		Wear = {
			{ Prop = "HairBob", Color = rgb(20, 20, 20) },
			{ Prop = "Headphones", Color = rgb(245, 245, 245), Trim = rgb(60, 200, 230) },
		},
	},
	{
		Name = "Max",
		Skin = SKIN[5],
		Shirt = "rbxassetid://103738904240948",
		Pants = "rbxassetid://78808631904474",
		Face = FACES.Grin,
		Wear = { { Prop = "CowboyHat", Color = rgb(130, 85, 45), Trim = rgb(60, 35, 20) } },
	},
	{
		Name = "Ruby",
		Skin = SKIN[2],
		Shirt = "rbxassetid://131782825573769",
		Pants = "rbxassetid://83645273066066",
		Face = FACES.Determined,
		Wear = { { Prop = "HairLong", Color = rgb(200, 60, 30) } },
	},
	{
		Name = "Sam",
		Skin = SKIN[1],
		Shirt = "rbxassetid://94783315712898",
		Pants = "rbxassetid://133849304341480",
		Face = FACES.Surprised,
		Wear = {
			{ Prop = "Beanie", Color = rgb(40, 140, 60), Trim = rgb(30, 30, 30) },
			{ Prop = "ShutterShades", Color = rgb(20, 20, 22) },
		},
	},
	{
		Name = "Ivy",
		Skin = SKIN[3],
		Shirt = "rbxassetid://113848148510369",
		Pants = "rbxassetid://73173985298360",
		Face = FACES.Smile,
		Wear = {
			{ Prop = "HairPonytail", Color = rgb(240, 220, 170), Trim = rgb(122, 60, 160) },
			{ Prop = "RoundGlasses", Color = rgb(122, 60, 160) },
		},
	},
	{
		Name = "Ben",
		Skin = SKIN[5],
		Shirt = "rbxassetid://92608771511347",
		Pants = "rbxassetid://92208132645825",
		Face = FACES.Cheeky,
		Wear = { { Prop = "HairSpiky", Color = rgb(250, 215, 90) } },
	},
	{
		Name = "Kate",
		Skin = SKIN[2],
		Shirt = "rbxassetid://111093050431184",
		Pants = "rbxassetid://109086968383414",
		Face = FACES.Smirk,
		Wear = {
			{ Prop = "HairLong", Color = rgb(150, 20, 30) },
			{ Prop = "ShutterShades", Color = rgb(20, 20, 22) },
		},
	},
}

local HEAD_HEIGHT = 1.2 -- the default R15 head the accessories were modelled on

local originals: { [Player]: HumanoidDescription } = {}

-- Part-built stand-ins for when a Blender accessory isn't loaded ------------------------------

local function hatPart(
	head: BasePart,
	model: Model,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	if shape then
		p.Shape = shape
	end
	p.CFrame = head.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
	return p
end

local function fallbackWear(head: BasePart, model: Model, wear: Wear)
	local s = head.Size
	local top = s.Y / 2
	local color = wear.Color or Color3.new(0.2, 0.2, 0.2)
	local trim = wear.Trim or color
	local prop = wear.Prop
	if prop == "Beanie" then
		hatPart(
			head,
			model,
			"Hat",
			Vector3.new(s.X * 1.08, s.Y * 0.5, s.Z * 1.08),
			CFrame.new(0, top - s.Y * 0.05, 0),
			color
		)
		hatPart(
			head,
			model,
			"Trim",
			Vector3.new(s.X * 1.14, s.Y * 0.14, s.Z * 1.14),
			CFrame.new(0, top - s.Y * 0.28, 0),
			trim
		)
		hatPart(
			head,
			model,
			"Pompom",
			Vector3.one * s.X * 0.35,
			CFrame.new(0, top + s.Y * 0.28, 0),
			Color3.new(1, 1, 1),
			Enum.PartType.Ball
		)
	elseif prop == "Cap" then
		hatPart(
			head,
			model,
			"Hat",
			Vector3.new(s.X * 1.06, s.Y * 0.35, s.Z * 1.06),
			CFrame.new(0, top + s.Y * 0.05, 0),
			color
		)
		hatPart(
			head,
			model,
			"Trim",
			Vector3.new(s.X * 0.9, s.Y * 0.06, s.Z * 0.55),
			CFrame.new(0, top - s.Y * 0.08, -s.Z * 0.72),
			trim
		)
	elseif prop == "TopHat" then
		hatPart(
			head,
			model,
			"Brim",
			Vector3.new(s.X * 1.5, s.Y * 0.07, s.Z * 1.5),
			CFrame.new(0, top + s.Y * 0.03, 0),
			color
		)
		hatPart(
			head,
			model,
			"Hat",
			Vector3.new(s.X * 0.95, s.Y * 0.95, s.Z * 0.95),
			CFrame.new(0, top + s.Y * 0.5, 0),
			color
		)
		hatPart(
			head,
			model,
			"Trim",
			Vector3.new(s.X * 0.97, s.Y * 0.15, s.Z * 0.97),
			CFrame.new(0, top + s.Y * 0.12, 0),
			trim
		)
	elseif prop == "CowboyHat" then
		hatPart(
			head,
			model,
			"Brim",
			Vector3.new(s.X * 1.9, s.Y * 0.07, s.Z * 1.6),
			CFrame.new(0, top + s.Y * 0.02, 0),
			color
		)
		hatPart(
			head,
			model,
			"Hat",
			Vector3.new(s.X * 1.0, s.Y * 0.5, s.Z * 0.9),
			CFrame.new(0, top + s.Y * 0.27, 0),
			color
		)
	elseif prop == "ShutterShades" or prop == "RoundGlasses" then
		hatPart(
			head,
			model,
			"Frame",
			Vector3.new(s.X * 0.9, s.Y * 0.2, 0.1),
			CFrame.new(0, s.Y * 0.1, -s.Z / 2 - 0.03),
			color
		)
	elseif prop == "Headphones" then
		hatPart(
			head,
			model,
			"Hat",
			Vector3.new(s.X * 1.15, s.Y * 0.1, s.Z * 0.2),
			CFrame.new(0, top + s.Y * 0.04, 0),
			color
		)
		for _, x in { -1, 1 } do
			hatPart(
				head,
				model,
				"Trim",
				Vector3.new(s.X * 0.15, s.Y * 0.4, s.Z * 0.4),
				CFrame.new(x * s.X * 0.56, 0, 0),
				trim
			)
		end
	elseif string.sub(prop, 1, 4) == "Hair" then
		hatPart(head, model, "Hair", Vector3.new(s.X * 1.08, s.Y * 0.3, s.Z * 1.08), CFrame.new(0, top, 0), color)
		hatPart(
			head,
			model,
			"Hair",
			Vector3.new(s.X * 1.08, s.Y * 0.75, s.Z * 0.25),
			CFrame.new(0, s.Y * 0.1, s.Z * 0.47),
			color
		)
	end
end

-- Accessories ---------------------------------------------------------------------------------

-- Hats sit on top of the sculpted hair, so over hair they're worn a size up
local HATS: { [string]: boolean } =
	{ Beanie = true, Cap = true, TopHat = true, CowboyHat = true, Crown = true, Headphones = true }
local OVER_HAIR = 1.12

local function wearOn(head: BasePart, model: Model, wear: Wear, overHair: boolean?)
	if not Props.Has(wear.Prop) then
		fallbackWear(head, model, wear)
		return
	end
	local prop = Props.Build(wear.Prop)
	-- Some pieces sit on the body rather than the head (angel wings on the UpperTorso)
	local anchor: BasePart = head
	if wear.On then
		local part = head.Parent and head.Parent:FindFirstChild(wear.On)
		if part and part:IsA("BasePart") then
			anchor = part
		end
	end
	for _, d in prop:GetDescendants() do
		if d:IsA("BasePart") then
			if (d.Name == "Hair" or d.Name == "Hat" or d.Name == "Frame") and wear.Color then
				d.Color = wear.Color
			elseif (d.Name == "Trim" or d.Name == "Tie") and wear.Trim then
				d.Color = wear.Trim
			end
			-- Glasses lenses and the space helmet's bubble are see-through
			if d.Name == "Lens" then
				d.Transparency = if wear.Prop == "SpaceHelmet" then 0.82 else 0.78
				d.Reflectance = 0.03
				d.CastShadow = false
			end
			if d.Name == "Hair" then
				d.Material = Enum.Material.SmoothPlastic
				d.Reflectance = 0
			elseif d.Name == "Frame" or d.Name == "Trim" then
				d.Reflectance = 0.05
			end
		end
	end
	-- Made for the default head; guards / odd rigs get it scaled to fit
	local scale = head.Size.Y / HEAD_HEIGHT
	if overHair and HATS[wear.Prop] then
		scale *= OVER_HAIR
	end
	if math.abs(scale - 1) > 0.02 then
		prop:ScaleTo(scale)
	end
	prop:PivotTo(anchor.CFrame)
	local root = prop.PrimaryPart :: BasePart
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchor
	weld.Part1 = root
	weld.Parent = root
	prop.Parent = model
end

local function buildWear(head: BasePart, wears: { Wear }): Model
	local old = head.Parent and head.Parent:FindFirstChild("DisguiseHat")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "DisguiseHat"
	local hasHair = false
	for _, wear in wears do
		if string.sub(wear.Prop, 1, 4) == "Hair" then
			hasHair = true
		end
	end
	for _, wear in wears do
		wearOn(head, model, wear, hasHair)
	end
	model.Parent = head.Parent
	return model
end

-- Body ----------------------------------------------------------------------------------------

local function describe(outfit: Outfit): HumanoidDescription
	local d = Instance.new("HumanoidDescription")
	-- Bare skin everywhere: the clothing templates paint sleeves, shorts and socks themselves
	d.HeadColor = outfit.Skin
	d.TorsoColor = outfit.Skin
	d.LeftArmColor = outfit.Skin
	d.RightArmColor = outfit.Skin
	d.LeftLegColor = outfit.Skin
	d.RightLegColor = outfit.Skin
	-- Everything else stays at 0/"" = the default blocky body, no catalog items
	return d
end

local function stripClothing(character: Model)
	for _, child in character:GetChildren() do
		if child:IsA("Clothing") or child:IsA("ShirtGraphic") then
			child:Destroy()
		end
	end
end

-- Template clothes + face + accessories on a rig that already has the outfit's description
local function dress(character: Model, outfit: Outfit)
	stripClothing(character)
	local shirt = Instance.new("Shirt")
	shirt.Name = "DisguiseShirt"
	shirt.ShirtTemplate = outfit.Shirt
	shirt.Parent = character
	local pants = Instance.new("Pants")
	pants.Name = "DisguisePants"
	pants.PantsTemplate = outfit.Pants
	pants.Parent = character
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	head = CharacterFaces.Apply(head, outfit.Face)
	buildWear(head, outfit.Wear)
	CharacterDetails.Apply(character, outfit.Name)
end

local function putOn(player: Player, outfit: Outfit)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return
	end
	if not originals[player] then
		local ok, current = pcall(humanoid.GetAppliedDescription, humanoid)
		if ok then
			originals[player] = current
		end
	end
	local ok, err = pcall(humanoid.ApplyDescriptionResetAsync, humanoid, describe(outfit))
	if not ok then
		warn(`[Disguises] couldn't dress {player.Name}: {err}`)
	end
	if character.Parent then
		dress(character, outfit)
	end
	humanoid.DisplayName = outfit.Name
	player:SetAttribute("Disguise", outfit.Name)
end

-- Hands out a different outfit to each player (loops if there are more than 16)
function Disguises.Assign(players: { Player }): { [Player]: string }
	local pool = table.clone(OUTFITS)
	local rng = Random.new()
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local names = {}
	local pending = 0
	for i, player in players do
		local outfit = pool[(i - 1) % #pool + 1]
		names[player] = outfit.Name
		if not player.Character then
			continue
		end
		-- Applying a description yields, so dress everyone at the same time
		pending += 1
		task.spawn(function()
			putOn(player, outfit)
			pending -= 1
		end)
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < 5 do
		task.wait()
	end
	return names
end

-- ShapeShifter perk: swap to an outfit nobody in `taken` is wearing. Returns the new name.
function Disguises.Shift(player: Player, taken: { [string]: boolean }): string?
	local free = {}
	for _, outfit in OUTFITS do
		if not taken[outfit.Name] then
			table.insert(free, outfit)
		end
	end
	if #free == 0 then
		return nil
	end
	local outfit = free[Random.new():NextInteger(1, #free)]
	putOn(player, outfit)
	return outfit.Name
end

-- Back to their own avatar (only needed for people who are still alive; respawns reload it anyway)
function Disguises.Remove(player: Player)
	player:SetAttribute("Disguise", nil)
	local original = originals[player]
	originals[player] = nil
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return
	end
	local hat = character:FindFirstChild("DisguiseHat")
	if hat then
		hat:Destroy()
	end
	for _, name in { "DisguiseShirt", "DisguisePants", "DisguiseDetails" } do
		local item = character:FindFirstChild(name)
		if item then
			item:Destroy()
		end
	end
	humanoid.DisplayName = player.DisplayName
	if original then
		task.spawn(function()
			pcall(humanoid.ApplyDescriptionResetAsync, humanoid, original)
		end)
	end
end

-- Hat for any rig's head (the guards and burglars use this too): a PropMeshes key or one of the
-- old names ("Cowboy" = CowboyHat)
function Disguises.AddHat(head: BasePart, hat: string, color: Color3, shades: boolean?): Model
	local wears: { Wear } = { { Prop = if hat == "Cowboy" then "CowboyHat" else hat, Color = color, Trim = color } }
	if shades then
		table.insert(wears, { Prop = "ShutterShades", Color = Color3.new(0.05, 0.05, 0.05) })
	end
	return buildWear(head, wears)
end

-- Build a complete accessory set at once; AddHat replaces the set rather than appending to it.
function Disguises.AddAccessories(head: BasePart, wears: { Wear }): Model
	return buildWear(head, wears)
end

-- A dressed R15 rig for a round bot, wearing an outfit nobody in `taken` has. Returns its name.
function Disguises.BuildBot(taken: { [string]: boolean }): (Model, string)
	local free = {}
	for _, outfit in OUTFITS do
		if not taken[outfit.Name] then
			table.insert(free, outfit)
		end
	end
	local pool = if #free > 0 then free else OUTFITS
	local outfit = pool[Random.new():NextInteger(1, #pool)]
	local rig = Players:CreateHumanoidModelFromDescription(describe(outfit), Enum.HumanoidRigType.R15)
	dress(rig, outfit)
	return rig, outfit.Name
end

-- A dressed R15 rig of one named character (the biome bosses are round characters), with extra
-- Blender pieces on top of their usual outfit (crown, halo, horns, wings...)
local BODY_PIECES: { [string]: string } = { AngelWings = "UpperTorso" }
function Disguises.BuildCharacter(name: string, extra: { string }?): Model
	local outfit = OUTFITS[1]
	for _, candidate in OUTFITS do
		if candidate.Name == name then
			outfit = candidate
		end
	end
	local rig = Players:CreateHumanoidModelFromDescription(describe(outfit), Enum.HumanoidRigType.R15)
	dress(rig, outfit)
	if extra and #extra > 0 then
		local wears = table.clone(outfit.Wear)
		for _, prop in extra do
			table.insert(wears, { Prop = prop, On = BODY_PIECES[prop] })
		end
		local head = rig:FindFirstChild("Head") :: BasePart?
		if head then
			buildWear(head, wears)
		end
	end
	rig.Name = outfit.Name
	return rig
end

function Disguises.Forget(player: Player)
	originals[player] = nil
end

return Disguises
