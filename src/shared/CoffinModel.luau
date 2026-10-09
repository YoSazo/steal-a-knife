--!strict
-- Glass coffin with a rarity-coloured knife silhouette. Only the special hint is public.
local Knives = require(script.Parent.Config.Knives)
local Items = require(script.Parent.Items)
local KnifeModel = require(script.Parent.KnifeModel)
local CoffinModel = {}

function CoffinModel.Length(rarity: string): number
	return 3 + ((table.find(Knives.Rarities, rarity) or 1) - 1) * 5 / 7
end

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, role: string?): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color:Lerp(Color3.new(0, 0, 0), 0.4)
	if role then
		p:SetAttribute("Role", role)
	end
	p.Parent = model
	return p
end

function CoffinModel.Build(rarity: string, at: CFrame, item: string?): Model
	local model = Instance.new("Model")
	model.Name = "Coffin"
	model:SetAttribute("Rarity", rarity)
	local color = Knives.RarityColors[rarity] or Color3.new(1, 1, 1)
	local length = CoffinModel.Length(rarity)
	local width, height = length * 0.55, length * 0.3
	local body = part(model, "Body", Vector3.new(width, height, length), at * CFrame.new(0, height / 2, 0), color, nil)
	body.Transparency = 1
	model.PrimaryPart = body
	-- Six-sided coffin outline: broad shoulders and tapered foot.
	local points = {
		Vector3.new(-width * 0.32, 0, -length * 0.5),
		Vector3.new(width * 0.32, 0, -length * 0.5),
		Vector3.new(width * 0.5, 0, -length * 0.23),
		Vector3.new(width * 0.3, 0, length * 0.5),
		Vector3.new(-width * 0.3, 0, length * 0.5),
		Vector3.new(-width * 0.5, 0, -length * 0.23),
	}
	local rim = math.max(0.055, length * 0.018)
	for i, point in points do
		local nextPoint = points[i % #points + 1]
		local middle = (point + nextPoint) / 2
		local distance = (point - nextPoint).Magnitude
		local side = part(
			model,
			"GlassSide",
			Vector3.new(0.035, height, distance),
			at * CFrame.lookAt(middle + Vector3.new(0, height / 2, 0), nextPoint + Vector3.new(0, height / 2, 0)),
			color,
			"Body"
		)
		side.Material, side.Transparency = Enum.Material.Glass, 0.72
		for _, y in { 0, height } do
			part(
				model,
				"Rim",
				Vector3.new(rim, rim, distance),
				at * CFrame.lookAt(middle + Vector3.new(0, y, 0), nextPoint + Vector3.new(0, y, 0)),
				color,
				nil
			)
		end
		part(
			model,
			"Corner",
			Vector3.new(rim, height, rim),
			at * CFrame.new(point + Vector3.new(0, height / 2, 0)),
			color,
			nil
		)
	end
	local lid =
		part(model, "Lid", Vector3.new(width * 0.84, 0.035, length * 0.94), at * CFrame.new(0, height, 0), color, "Lid")
	lid.Material, lid.Transparency = Enum.Material.Glass, 0.8
	local parsed = item and Items.Parse(item)
	local knife = if parsed then parsed.Knife else Knives.ByRarity[rarity][1]
	local silhouette = KnifeModel.Build(knife.Name, true)
	-- Strip detail and colour so the exact mutation remains hidden.
	for _, d in silhouette:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color, d.Material = color:Lerp(Color3.new(0, 0, 0), 0.55), Enum.Material.Neon
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
			d.CastShadow = false
		elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("Trail") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	silhouette.Name = "Silhouette"
	silhouette:SetAttribute("Item", nil)
	KnifeModel.FitLength(silhouette, length * 0.73)
	silhouette:PivotTo(at * CFrame.new(0, height * 0.5, 0) * CFrame.Angles(math.pi / 2, 0, 0))
	local box = silhouette:GetBoundingBox()
	silhouette:PivotTo(silhouette:GetPivot() + (at:PointToWorldSpace(Vector3.new(0, height * 0.5, 0)) - box.Position))
	silhouette.Parent = model
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range = color, 0.35, length * 1.5
	light.Shadows = false
	light.Parent = body
	local special = parsed ~= nil and parsed.Mutation.Rank >= 2
	model:SetAttribute("Special", special)
	model:SetAttribute("CharacterName", knife.DisplayName)
	if special then
		local glow = part(
			model,
			"SpecialGlow",
			Vector3.new(width * 0.96, 0.05, length * 0.96),
			at * CFrame.new(0, -0.02, 0),
			Color3.new(1, 1, 1),
			"Glow"
		)
		glow.Transparency = 0.6
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "SpecialSparkles"
		sparkles.Texture = require(script.Parent.Config.Textures).Glow.Flare
		sparkles.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.4))
		sparkles.Rate = 4
		sparkles.Lifetime = NumberRange.new(0.6, 1.1)
		sparkles.Speed = NumberRange.new(0.3, 0.7)
		sparkles.Size = NumberSequence.new(0.2)
		sparkles.LightEmission = 0.4
		sparkles.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		sparkles.Parent = body
	end
	return model
end

function CoffinModel.Weld(model: Model)
	local primary = model.PrimaryPart
	assert(primary, "Coffin needs a primary part")
	for _, piece in model:GetDescendants() do
		if piece:IsA("BasePart") and piece ~= primary then
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = primary, piece
			weld.Parent = piece
		end
	end
end
return CoffinModel
