--!strict
-- Small raised, square details follow each existing outfit rather than replacing its artwork.
-- Everything is welded, massless and non-queryable so combat and movement keep their old shape.
local CharacterDetails = {}
local rgb = Color3.fromRGB
type Finish = { Style: string, Cloth: Color3, Accent: Color3, Shoe: Color3, Sole: Color3 }
local FINISHES: { [string]: Finish } = {
	Mortimer = {
		Style = "Suit",
		Cloth = rgb(70, 30, 40),
		Accent = rgb(220, 190, 90),
		Shoe = rgb(30, 26, 30),
		Sole = rgb(15, 15, 18),
	},
	Nick = {
		Style = "Zip",
		Cloth = rgb(20, 190, 200),
		Accent = rgb(230, 240, 245),
		Shoe = rgb(240, 240, 240),
		Sole = rgb(150, 164, 175),
	},
	Frank = {
		Style = "Jacket",
		Cloth = rgb(38, 38, 42),
		Accent = rgb(178, 180, 188),
		Shoe = rgb(91, 58, 34),
		Sole = rgb(42, 26, 16),
	},
	Rose = {
		Style = "Bracelet",
		Cloth = rgb(244, 244, 244),
		Accent = rgb(25, 25, 28),
		Shoe = rgb(107, 107, 112),
		Sole = rgb(58, 58, 62),
	},
	Lucy = {
		Style = "Knit",
		Cloth = rgb(154, 90, 200),
		Accent = rgb(255, 111, 174),
		Shoe = rgb(200, 38, 74),
		Sole = rgb(250, 250, 250),
	},
	Jake = {
		Style = "Sport",
		Cloth = rgb(240, 240, 240),
		Accent = rgb(204, 42, 42),
		Shoe = rgb(204, 42, 42),
		Sole = rgb(250, 250, 250),
	},
	Emma = {
		Style = "Buttons",
		Cloth = rgb(47, 143, 78),
		Accent = rgb(240, 240, 230),
		Shoe = rgb(58, 37, 22),
		Sole = rgb(30, 20, 12),
	},
	Oscar = {
		Style = "Hoodie",
		Cloth = rgb(255, 154, 40),
		Accent = rgb(30, 30, 34),
		Shoe = rgb(240, 240, 240),
		Sole = rgb(120, 125, 135),
	},
	Mia = {
		Style = "Sport",
		Cloth = rgb(255, 226, 90),
		Accent = rgb(255, 120, 180),
		Shoe = rgb(250, 250, 250),
		Sole = rgb(180, 190, 210),
	},
	Leo = {
		Style = "Suit",
		Cloth = rgb(168, 30, 44),
		Accent = rgb(220, 190, 90),
		Shoe = rgb(15, 15, 18),
		Sole = rgb(5, 5, 5),
	},
	Zoe = {
		Style = "Zip",
		Cloth = rgb(60, 200, 230),
		Accent = rgb(250, 250, 250),
		Shoe = rgb(60, 200, 230),
		Sole = rgb(250, 250, 250),
	},
	Max = {
		Style = "Field",
		Cloth = rgb(74, 107, 58),
		Accent = rgb(160, 138, 94),
		Shoe = rgb(58, 42, 24),
		Sole = rgb(20, 15, 10),
	},
	Ruby = {
		Style = "Bracelet",
		Cloth = rgb(200, 40, 60),
		Accent = rgb(240, 200, 90),
		Shoe = rgb(20, 20, 22),
		Sole = rgb(10, 10, 10),
	},
	Sam = {
		Style = "Hoodie",
		Cloth = rgb(122, 122, 132),
		Accent = rgb(240, 240, 240),
		Shoe = rgb(240, 240, 240),
		Sole = rgb(42, 42, 50),
	},
	Ivy = {
		Style = "Bow",
		Cloth = rgb(250, 250, 250),
		Accent = rgb(122, 60, 160),
		Shoe = rgb(250, 250, 250),
		Sole = rgb(200, 200, 210),
	},
	Ben = {
		Style = "Sport",
		Cloth = rgb(255, 255, 255),
		Accent = rgb(168, 34, 42),
		Shoe = rgb(240, 240, 240),
		Sole = rgb(170, 176, 188),
	},
	Kate = {
		Style = "Bracelet",
		Cloth = rgb(244, 244, 244),
		Accent = rgb(230, 230, 235),
		Shoe = rgb(25, 25, 28),
		Sole = rgb(240, 240, 240),
	},
}

local function detail(
	folder: Model,
	anchor: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	metal: boolean?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = anchor.CFrame * offset
	p.Color = color
	p.Material = if metal then Enum.Material.Metal else Enum.Material.SmoothPlastic
	p.Reflectance = if metal then 0.04 else 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchor
	weld.Part1 = p
	weld.Parent = p
	p.Parent = folder
	return p
end

function CharacterDetails.Apply(character: Model, name: string)
	local old = character:FindFirstChild("DisguiseDetails")
	if old then
		old:Destroy()
	end
	local finish = FINISHES[name]
	if not finish then
		return
	end
	local folder = Instance.new("Model")
	folder.Name = "DisguiseDetails"
	folder.Parent = character
	local head = character:FindFirstChild("Head") :: BasePart?
	if head then
		local k = head.Size.Y / 1.2
		for _, side in { -1, 1 } do
			local skin = head.Color
			detail(
				folder,
				head,
				"Ear",
				Vector3.new(0.1, 0.25, 0.22) * k,
				CFrame.new(side * head.Size.X * 0.48, -0.04 * k, 0),
				skin
			)
			detail(
				folder,
				head,
				"EarInset",
				Vector3.new(0.025, 0.13, 0.11) * k,
				CFrame.new(side * (head.Size.X * 0.48 + 0.054 * k), -0.04 * k, -0.01 * k),
				skin:Lerp(rgb(155, 89, 72), 0.18)
			)
		end
	end
	local torso = character:FindFirstChild("UpperTorso") :: BasePart?
	if torso then
		local front = -torso.Size.Z / 2 - 0.028
		local w, h = torso.Size.X, torso.Size.Y
		local function chest(
			label: string,
			x: number,
			y: number,
			width: number,
			height: number,
			color: Color3,
			metal: boolean?
		)
			detail(
				folder,
				torso,
				label,
				Vector3.new(width, height, 0.045),
				CFrame.new(x * w, y * h, front),
				color,
				metal
			)
		end
		if finish.Style == "Zip" then
			chest("ZipTrack", 0, -0.03, 0.035, h * 0.79, finish.Accent)
			chest("ZipPull", 0.025, 0.27, 0.07, 0.12, finish.Accent, true)
		elseif finish.Style == "Buttons" or finish.Style == "Jacket" or finish.Style == "Suit" then
			for i = 1, 3 do
				chest(
					"SquareButton",
					if finish.Style == "Jacket" then -0.22 else 0,
					0.12 - i * 0.17,
					0.06,
					0.06,
					finish.Accent,
					true
				)
			end
			if finish.Style ~= "Buttons" then
				for _, side in { -1, 1 } do
					chest("LapelTop", side * 0.2, 0.3, w * 0.11, h * 0.15, finish.Cloth:Lerp(rgb(255, 255, 255), 0.12))
					chest(
						"LapelStep",
						side * 0.17,
						0.18,
						w * 0.075,
						h * 0.09,
						finish.Cloth:Lerp(rgb(255, 255, 255), 0.08)
					)
				end
			end
		elseif finish.Style == "Hoodie" then
			for _, side in { -1, 1 } do
				chest("Drawstring", side * 0.12, 0.23, 0.035, h * 0.22, finish.Accent)
				chest("DrawstringTip", side * 0.12, 0.1, 0.055, 0.075, finish.Accent, true)
			end
		elseif finish.Style == "Bow" then
			chest("BowKnot", 0, 0.35, 0.12, 0.12, finish.Accent:Lerp(rgb(25, 20, 40), 0.2))
			for _, side in { -1, 1 } do
				chest("BowWing", side * 0.065, 0.35, 0.14, 0.18, finish.Accent)
			end
		elseif finish.Style == "Field" then
			for _, side in { -1, 1 } do
				chest("PocketFlap", side * 0.23, 0.06, w * 0.22, 0.1, finish.Cloth:Lerp(rgb(255, 255, 255), 0.08))
				chest("PocketSnap", side * 0.23, 0.02, 0.045, 0.045, finish.Accent, true)
			end
		end
	end
	for _, side in { "Left", "Right" } do
		local hand = character:FindFirstChild(side .. "Hand") :: BasePart?
		if hand then
			-- A few low-relief squares imply knuckles without changing the mitten silhouette or grip.
			for index = -1, 1 do
				detail(
					folder,
					hand,
					"Knuckle",
					Vector3.new(0.07, 0.07, 0.035),
					CFrame.new(index * hand.Size.X * 0.2, -hand.Size.Y * 0.15, -hand.Size.Z / 2 - 0.012),
					hand.Color
				)
			end
		end
		local arm = character:FindFirstChild(side .. "LowerArm") :: BasePart?
		if arm and finish.Style == "Bracelet" then
			local y = -arm.Size.Y * 0.3
			detail(
				folder,
				arm,
				"Wristband",
				Vector3.new(arm.Size.X + 0.025, 0.12, arm.Size.Z + 0.025),
				CFrame.new(0, y, 0),
				rgb(25, 25, 28)
			)
			for index = -1, 1 do
				detail(
					folder,
					arm,
					"WristStud",
					Vector3.new(0.055, 0.055, 0.045),
					CFrame.new(index * arm.Size.X * 0.22, y, -arm.Size.Z / 2 - 0.03),
					finish.Accent,
					true
				)
			end
		end
		local foot = character:FindFirstChild(side .. "Foot") :: BasePart?
		if foot then
			detail(
				folder,
				foot,
				"ToeTrim",
				Vector3.new(foot.Size.X * 0.86, 0.09, 0.045),
				CFrame.new(0, -foot.Size.Y * 0.06, -foot.Size.Z / 2 - 0.018),
				finish.Shoe
			)
			detail(
				folder,
				foot,
				"SoleEdge",
				Vector3.new(foot.Size.X + 0.025, 0.07, foot.Size.Z + 0.025),
				CFrame.new(0, -foot.Size.Y * 0.35, 0),
				finish.Sole
			)
			detail(
				folder,
				foot,
				"HeelTab",
				Vector3.new(foot.Size.X * 0.38, 0.09, 0.04),
				CFrame.new(0, foot.Size.Y * 0.12, foot.Size.Z / 2 + 0.018),
				finish.Accent
			)
			if finish.Style ~= "Suit" then
				for i = 1, 2 do
					detail(
						folder,
						foot,
						"Lace",
						Vector3.new(foot.Size.X * 0.52, 0.035, 0.055),
						CFrame.new(0, foot.Size.Y / 2 + 0.012, -foot.Size.Z * (0.12 + i * 0.12)),
						finish.Sole:Lerp(rgb(255, 255, 255), 0.65)
					)
				end
			end
		end
	end
end

return CharacterDetails
