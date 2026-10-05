--!strict
-- Clean cuboid construction shared by the playable vault and exported previews.
-- This module only creates geometry: labels, artwork, prompts and gameplay stay with callers.
local VaultModel = {}

VaultModel.Navy = Color3.fromRGB(40, 44, 70)
VaultModel.Graphite = Color3.fromRGB(70, 80, 99)
VaultModel.Silver = Color3.fromRGB(201, 211, 226)
VaultModel.Deck = Color3.fromRGB(174, 185, 203)
VaultModel.Cyan = Color3.fromRGB(80, 215, 240)
VaultModel.FloorHeight = 22

export type Style = { Body: Color3, Secondary: Color3, Deck: Color3, Silver: Color3, Inset: Color3 }
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local styles: { Style } = {
	{
		Body = rgb(112, 76, 46),
		Secondary = rgb(65, 62, 65),
		Deck = rgb(190, 182, 169),
		Silver = rgb(153, 158, 164),
		Inset = rgb(225, 181, 90),
	},
	{
		Body = rgb(40, 44, 70),
		Secondary = rgb(70, 80, 99),
		Deck = rgb(174, 185, 203),
		Silver = rgb(201, 211, 226),
		Inset = rgb(80, 215, 240),
	},
	{
		Body = rgb(126, 70, 43),
		Secondary = rgb(51, 54, 67),
		Deck = rgb(174, 185, 203),
		Silver = rgb(229, 166, 86),
		Inset = rgb(100, 222, 212),
	},
	{
		Body = rgb(63, 39, 68),
		Secondary = rgb(37, 29, 44),
		Deck = rgb(175, 170, 187),
		Silver = rgb(126, 105, 136),
		Inset = rgb(255, 93, 112),
	},
	{
		Body = rgb(65, 35, 91),
		Secondary = rgb(34, 25, 49),
		Deck = rgb(173, 170, 196),
		Silver = rgb(153, 110, 190),
		Inset = rgb(226, 76, 255),
	},
	{
		Body = rgb(52, 73, 108),
		Secondary = rgb(31, 35, 61),
		Deck = rgb(186, 206, 217),
		Silver = rgb(182, 238, 249),
		Inset = rgb(66, 236, 255),
	},
	{
		Body = rgb(233, 227, 210),
		Secondary = rgb(203, 169, 90),
		Deck = rgb(216, 215, 209),
		Silver = rgb(240, 198, 92),
		Inset = rgb(255, 229, 130),
	},
	{
		Body = rgb(37, 33, 72),
		Secondary = rgb(70, 43, 104),
		Deck = rgb(175, 185, 211),
		Silver = rgb(237, 189, 82),
		Inset = rgb(248, 103, 232),
	},
}
function VaultModel.Style(level: number): Style
	return styles[math.clamp(math.floor(level), 1, #styles)]
end

local function block(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, neon: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Anchored = true
	p.Massless = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("VaultDetail", true)
	local role = if color == VaultModel.Navy
		then "Body"
		else if color == VaultModel.Graphite
			then "Secondary"
			else if color == VaultModel.Silver
				then "Silver"
				else if color == VaultModel.Deck then "Deck" else if color == VaultModel.Cyan then "Inset" else nil
	p:SetAttribute("VaultFinish", role)
	p.Parent = parent
	return p
end

local function model(parent: Instance, name: string): Model
	local result = Instance.new("Model")
	result.Name = name
	result.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	result.Parent = parent
	return result
end

function VaultModel.BuildFrame(
	parent: Instance,
	frame: CFrame,
	ownerColor: Color3,
	tierColor: Color3,
	floors: number,
	tierIndex: number?
): Model
	local result = model(parent, "VaultArchitecture")
	local height = floors * VaultModel.FloorHeight + 4
	local tierLevel = tierIndex or 2
	local palette = VaultModel.Style(tierLevel)
	local body = palette.Body:Lerp(tierColor, 0.04)
	local accent = palette.Inset:Lerp(ownerColor, 0.10)
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	for _, x in { -19.5, 19.5 } do
		for _, z in { -21.5, 21.5 } do
			block(result, "PillarFoot", Vector3.new(3.2, 0.7, 3.2), at(x, 0.35, z), body)
			block(result, "PillarStep", Vector3.new(2.8, 0.35, 2.8), at(x, 0.875, z), VaultModel.Graphite)
			for level = 0, floors - 1 do
				local y = level * VaultModel.FloorHeight
				for half = 0, 1 do
					block(result, "PillarBlock", Vector3.new(1.8, 10.92, 1.8), at(x, y + 5.5 + half * 11, z), body)
				end
				block(result, "PillarCollar", Vector3.new(2.25, 0.65, 2.25), at(x, y + 2.0, z), VaultModel.Silver)
				for _, dx in { -0.62, 0.62 } do
					block(
						result,
						"CollarBolt",
						Vector3.new(0.28, 0.28, 0.14),
						at(x + dx, y + 2.0, z + 1.20),
						VaultModel.Graphite
					)
				end
			end
			block(result, "PillarNeck", Vector3.new(1.8, 4.1, 1.8), at(x, height - 2.0, z), body)
			block(result, "PillarCrown", Vector3.new(2.25, 3.35, 2.25), at(x, height - 1.65, z), body)
			block(result, "CrownCollar", Vector3.new(2.6, 0.6, 2.6), at(x, height - 1.9, z), VaultModel.Silver)
			for _, dx in { -0.75, 0.75 } do
				block(
					result,
					"CrownBolt",
					Vector3.new(0.30, 0.30, 0.14),
					at(x + dx, height - 1.9, z + 1.37),
					VaultModel.Graphite
				)
			end
			block(result, "PostCap", Vector3.new(2.5, 0.35, 2.5), at(x, height + 0.175, z), VaultModel.Graphite)
			block(result, "CapStep", Vector3.new(1.7, 0.25, 1.7), at(x, height + 0.475, z), body)
		end
	end
	-- Panelized rear wall, repeated with each purchased storey.
	for level = 0, floors - 1 do
		local y = level * VaultModel.FloorHeight
		for col = 0, 3 do
			local x = -14.25 + col * 9.5
			block(result, "BackPanel", Vector3.new(9.3, 21.7, 0.28), at(x, y + 11.0, -20.65), body)
			block(
				result,
				"PanelInset",
				Vector3.new(8.5, 18.2, 0.16),
				at(x, y + 11.5, -20.43),
				VaultModel.Graphite:Lerp(body, 0.6)
			)
			block(result, "PanelSeam", Vector3.new(8.5, 0.08, 0.08), at(x, y + 11.5, -20.31), body)
			block(result, "PanelStatus", Vector3.new(2.3, 0.28, 0.12), at(x, y + 20.4, -20.25), accent, true)
			block(result, "PanelSill", Vector3.new(9.1, 0.45, 0.55), at(x, y + 0.84, -20.4), VaultModel.Graphite)
		end
		for _, x in { -19.05, -9.5, 0, 9.5, 19.05 } do
			block(result, "BackMullion", Vector3.new(0.38, 21.8, 0.42), at(x, y + 11, -20.2), VaultModel.Navy)
			block(result, "MullionSocket", Vector3.new(0.65, 0.75, 0.16), at(x, y + 1.15, -19.89), VaultModel.Silver)
			block(result, "MullionGlow", Vector3.new(0.12, 1.2, 0.10), at(x, y + 19.6, -19.91), accent, true)
		end
		-- Simple side rails; the entrance and center aisle remain open.
		for _, side in { -1, 1 } do
			local x = side * 19.3
			block(result, "SideRail", Vector3.new(0.45, 0.4, 41.2), at(x, y + 4.0, 0), body)
			block(result, "RailLower", Vector3.new(0.45, 0.3, 41.2), at(x, y + 1.05, 0), body)
			for _, z in { -13, 0, 13 } do
				block(result, "RailStanchion", Vector3.new(0.42, 3.0, 0.42), at(x, y + 2.5, z), body)
				block(result, "RailInset", Vector3.new(0.12, 0.2, 4.4), at(x - side * 0.3, y + 1.6, z), accent, true)
			end
		end
	end
	-- Flat beam caps and roof panels, with the same armor seams as the wheel rims.
	for level = 1, floors do
		local y = if level == floors then height - 0.65 else level * VaultModel.FloorHeight - 0.65
		for _, side in { -1, 1 } do
			block(result, "SideBeam", Vector3.new(1.1, 1.1, 43), at(side * 19.5, y, 0), body)
		end
		for _, z in { -21.5, 21.5 } do
			for col = 0, 4 do
				local x = -15.6 + col * 7.8
				block(result, "BeamSegment", Vector3.new(7.72, 1.1, 1.2), at(x, y, z), body)
				if col % 2 == 0 then
					block(result, "BeamSocket", Vector3.new(2.2, 0.42, 0.12), at(x, y, z + 0.68), VaultModel.Graphite)
					block(result, "BeamInset", Vector3.new(1.7, 0.22, 0.14), at(x, y, z + 0.78), accent, true)
				end
			end
		end
	end
	for col = 0, 4 do
		for row = 0, 4 do
			block(
				result,
				"RoofPanel",
				Vector3.new(7.7, 0.28, 8.52),
				at(-15.6 + col * 7.8, height + 0.04, -17.2 + row * 8.6),
				VaultModel.Deck
			)
		end
	end
	VaultModel.ApplyTier(result, tierLevel)
	VaultModel.BuildCapDetails(result, frame, height, tierLevel)
	VaultModel.BuildPillarDetails(result, frame, floors, tierLevel)
	return result
end

function VaultModel.BuildPillarDetails(parent: Instance, frame: CFrame, floors: number, tier: number)
	local palette = VaultModel.Style(tier)
	for _, x in { -19.5, 19.5 } do
		for _, z in { -21.5, 21.5 } do
			for floor = 0, floors - 1 do
				local at = frame * CFrame.new(x, floor * 22, z + 0.99)
				if tier == 1 or tier == 2 then
					for _, y in { 8, 17 } do
						block(
							parent,
							"PostStrap",
							Vector3.new(1.85, 0.6, 0.15),
							at * CFrame.new(0, y, 0),
							palette.Secondary
						)
						for _, dx in { -0.55, 0.55 } do
							block(
								parent,
								"StrapFastener",
								Vector3.new(0.2, 0.2, 0.12),
								at * CFrame.new(dx, y, 0.14),
								palette.Silver
							)
						end
					end
				elseif tier == 3 then
					for _, y in { 7, 16 } do
						block(
							parent,
							"SteamGrille",
							Vector3.new(1.5, 3.0, 0.18),
							at * CFrame.new(0, y, 0),
							palette.Secondary
						)
						for j = -2, 2 do
							block(
								parent,
								"SteamGrilleSlit",
								Vector3.new(0.95, 0.15, 0.10),
								at * CFrame.new(0, y + j * 0.45, 0.15),
								palette.Inset,
								true
							)
						end
					end
				elseif tier == 4 then
					for _, y in { 7, 16 } do
						block(
							parent,
							"HauntedRuneSocket",
							Vector3.new(1.0, 1.4, 0.18),
							at * CFrame.new(0, y, 0),
							palette.Secondary
						)
						for _, dx in { -0.3, 0.3 } do
							block(
								parent,
								"HauntedRune",
								Vector3.new(0.12, 0.85, 0.08),
								at * CFrame.new(dx, y, 0.14),
								palette.Inset,
								true
							)
						end
						for _, dy in { -0.36, 0.36 } do
							block(
								parent,
								"HauntedRune",
								Vector3.new(0.60, 0.12, 0.08),
								at * CFrame.new(0, y + dy, 0.14),
								palette.Inset,
								true
							)
						end
					end
				elseif tier == 5 then
					block(
						parent,
						"PlasmaChannel",
						Vector3.new(0.8, 15.0, 0.18),
						at * CFrame.new(0, 11.5, 0),
						palette.Secondary
					)
					for _, y in { 6.5, 11.5, 16.5 } do
						block(
							parent,
							"PlasmaInlay",
							Vector3.new(0.18, 4.3, 0.10),
							at * CFrame.new(0, y, 0.15),
							palette.Inset,
							true
						)
					end
				elseif tier == 6 then
					for _, y in { 5, 11, 17 } do
						block(
							parent,
							"PhantomBracket",
							Vector3.new(1.9, 0.6, 0.18),
							at * CFrame.new(0, y, 0),
							palette.Silver
						)
						block(
							parent,
							"PhantomSocket",
							Vector3.new(0.32, 0.32, 0.10),
							at * CFrame.new(0, y, 0.16),
							palette.Inset,
							true
						)
					end
				elseif tier == 7 then
					for _, dx in { -0.55, 0, 0.55 } do
						block(
							parent,
							"GoldFlute",
							Vector3.new(0.1, 17.8, 0.09),
							at * CFrame.new(dx, 11.8, 0),
							palette.Secondary
						)
					end
				else
					for _, y in { 7, 16 } do
						block(
							parent,
							"CosmicSocketBorder",
							Vector3.new(1.0, 1.0, 0.18),
							at * CFrame.new(0, y, 0),
							palette.Silver
						)
						block(
							parent,
							"CosmicSocket",
							Vector3.new(0.70, 0.70, 0.12),
							at * CFrame.new(0, y, 0.18),
							palette.Secondary
						)
						block(
							parent,
							"CosmicSocketCore",
							Vector3.new(0.25, 0.25, 0.09),
							at * CFrame.new(0, y, 0.30),
							palette.Inset,
							true
						)
					end
				end
			end
		end
	end
end

function VaultModel.BuildCapDetails(parent: Instance, frame: CFrame, height: number, level: number)
	local palette = VaultModel.Style(level)
	for _, x in { -19.5, 19.5 } do
		for _, z in { -21.5, 21.5 } do
			local at = frame * CFrame.new(x, height + 0.65, z)
			if level == 1 then
				block(parent, "WoodCapStrap", Vector3.new(0.45, 0.12, 1.8), at, palette.Secondary)
			elseif level == 2 then
				for _, side in { -1, 1 } do
					block(
						parent,
						"IronCapBracket",
						Vector3.new(1.65, 0.18, 0.32),
						at * CFrame.new(0, 0, side * 0.65),
						palette.Silver
					)
				end
			elseif level == 3 then
				block(
					parent,
					"SteamCapElbow",
					Vector3.new(0.28, 1.2, 0.28),
					at * CFrame.new(0.5, 0.55, 0),
					palette.Silver
				)
				block(
					parent,
					"SteamCapElbow",
					Vector3.new(1.0, 0.28, 0.28),
					at * CFrame.new(0.13, 1.0, 0),
					palette.Silver
				)
			elseif level == 4 then
				block(
					parent,
					"HauntedCapSocket",
					Vector3.new(1.1, 0.65, 1.1),
					at * CFrame.new(0, 0.28, 0),
					palette.Secondary
				)
				for _, dx in { -0.26, 0.26 } do
					block(
						parent,
						"HauntedCapEye",
						Vector3.new(0.16, 0.16, 0.09),
						at * CFrame.new(dx, 0.28, 0.60),
						palette.Inset,
						true
					)
				end
			elseif level == 5 then
				for step = 0, 2 do
					block(
						parent,
						"PlasmaCapCrystal",
						Vector3.new(0.8 - step * 0.2, 0.3, 0.8 - step * 0.2),
						at * CFrame.new(0, 0.15 + step * 0.29, 0),
						palette.Inset,
						step == 2
					)
				end
			elseif level == 6 then
				for _, side in { -1, 1 } do
					block(
						parent,
						"PhantomCapShard",
						Vector3.new(0.4, 0.75, 0.8),
						at * CFrame.new(side * 0.55, 0.35, 0),
						palette.Silver
					)
				end
			elseif level == 7 then
				block(parent, "GoldCapital", Vector3.new(1.9, 0.25, 1.9), at, palette.Silver)
				block(parent, "GoldCapitalStep", Vector3.new(1.2, 0.3, 1.2), at * CFrame.new(0, 0.27, 0), palette.Body)
			else
				block(parent, "CosmicStar", Vector3.new(0.4, 1.2, 0.4), at * CFrame.new(0, 0.5, 0), palette.Inset, true)
				block(parent, "CosmicStar", Vector3.new(1.2, 0.4, 0.4), at * CFrame.new(0, 0.5, 0), palette.Silver)
				block(parent, "CosmicStar", Vector3.new(0.4, 0.4, 1.2), at * CFrame.new(0, 0.5, 0), palette.Silver)
			end
		end
	end
end

function VaultModel.ApplyTier(parent: Instance, level: number)
	local palette = VaultModel.Style(level)
	for _, part in parent:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("VaultDetail") then
			local role = part:GetAttribute("VaultFinish")
			if type(role) == "string" then
				local color = (palette :: any)[role]
				if typeof(color) == "Color3" then
					part.Color = color
				end
			end
			if part.Name:match("^Pedestal%d+$") then
				part:SetAttribute("VaultInset", palette.Inset)
			end
		end
	end
end

function VaultModel.SetPlateTier(parent: Instance, at: CFrame, level: number)
	local old = parent:FindFirstChild("PlateTierHardware")
	if old then
		old:Destroy()
	end
	local result = model(parent, "PlateTierHardware")
	local palette = VaultModel.Style(level)
	for _, x in { -3.32, 3.32 } do
		for _, z in { -3.32, 3.32 } do
			local cf = at * CFrame.new(x, 0.46, z)
			if level == 1 then
				block(result, "WoodPlateStrap", Vector3.new(0.40, 0.04, 0.18), cf, palette.Secondary)
			elseif level == 2 then
				block(
					result,
					"IronPlateBracket",
					Vector3.new(0.48, 0.035, 0.48),
					cf * CFrame.new(0, -0.03, 0),
					palette.Silver
				)
			elseif level == 3 then
				block(result, "SteamPlateCollar", Vector3.new(0.48, 0.07, 0.18), cf, palette.Silver)
				block(result, "SteamPlateCollar", Vector3.new(0.18, 0.07, 0.48), cf, palette.Silver)
			elseif level == 4 then
				block(result, "HauntedPlateRune", Vector3.new(0.12, 0.06, 0.40), cf, palette.Inset, true)
			elseif level == 5 then
				block(
					result,
					"PlasmaPlateCrystal",
					Vector3.new(0.24, 0.18, 0.24),
					cf * CFrame.new(0, 0.09, 0),
					palette.Silver
				)
				block(
					result,
					"PlasmaPlateCrystal",
					Vector3.new(0.12, 0.12, 0.12),
					cf * CFrame.new(0, 0.24, 0),
					palette.Inset,
					true
				)
			elseif level == 6 then
				block(
					result,
					"PhantomPlateShard",
					Vector3.new(0.4, 0.06, 0.4),
					cf * CFrame.new(0, 0.04, 0),
					palette.Silver
				)
			elseif level == 7 then
				block(
					result,
					"GoldPlateStep",
					Vector3.new(0.5, 0.04, 0.5),
					cf * CFrame.new(0, -0.02, 0),
					palette.Silver
				)
				block(result, "GoldPlateStep", Vector3.new(0.32, 0.04, 0.32), cf * CFrame.new(0, 0.02, 0), palette.Body)
			else
				block(result, "StarPlateSocket", Vector3.new(0.12, 0.045, 0.45), cf, palette.Inset, true)
				block(result, "StarPlateSocket", Vector3.new(0.45, 0.045, 0.12), cf, palette.Silver)
			end
		end
	end
end

function VaultModel.BuildFloor(parent: Instance, frame: CFrame, surface: number): Model
	local result = model(parent, "VaultFloorDetails")
	for _, x in { -15.9, -7.95, 7.95, 15.9 } do
		for row = 0, 4 do
			block(
				result,
				"FloorTile",
				Vector3.new(7.83, 0.06, 8.55),
				frame * CFrame.new(x, surface + 0.03, -17.4 + row * 8.7),
				VaultModel.Deck
			)
		end
	end
	-- The central strip stops before the climb-through opening.
	for row = 0, 3 do
		block(
			result,
			"AisleTile",
			Vector3.new(7.85, 0.045, 8.46),
			frame * CFrame.new(0, surface + 0.07, -8.725 + row * 8.55),
			VaultModel.Silver
		)
	end
	for _, side in { -1, 1 } do
		block(
			result,
			"FoundationEdge",
			Vector3.new(0.45, 0.35, 43.3),
			frame * CFrame.new(side * 19.6, surface - 0.18, 0),
			VaultModel.Navy
		)
	end
	block(
		result,
		"FrontFascia",
		Vector3.new(39.6, 0.35, 0.4),
		frame * CFrame.new(0, surface - 0.18, 21.65),
		VaultModel.Navy
	)
	for _, x in { -13, 13 } do
		block(
			result,
			"FasciaInset",
			Vector3.new(3.6, 0.12, 0.06),
			frame * CFrame.new(x, surface - 0.16, 21.89),
			VaultModel.Cyan,
			true
		)
	end
	return result
end

export type Plate = { Pad: Part, Rim: Part, Details: Model }
-- The centre and each of its eight edges share the existing rack-state colour.
-- The invisible proxy keeps SlotRims a single Part without moving the prompt anchor.
function VaultModel.SetPlateGlow(rim: BasePart)
	if rim.Name ~= "PlateGlowState" then
		return
	end
	local parent = rim.Parent
	if not parent then
		return
	end
	for _, part in parent:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("PlateGlow") then
			local highlight = part:GetAttribute("PlateHighlight")
			part.Color = if type(highlight) == "number"
				then rim.Color:Lerp(Color3.new(1, 1, 1), highlight)
				else rim.Color
			part.Material = if part.Name == "CyanOctagonCourse" then Enum.Material.SmoothPlastic else rim.Material
		end
	end
end

function VaultModel.BuildPlate(parent: Instance, at: CFrame, slot: number): Plate
	local result = model(parent, `PlateDetails{slot}`)
	local gold = rgb(236, 185, 52)
	local goldLight = rgb(255, 232, 106)
	local cream = rgb(255, 245, 157)
	local metal = rgb(119, 136, 130)
	local metalLight = rgb(169, 180, 152)
	local cyan = rgb(49, 218, 220)
	local white = rgb(237, 248, 203)
	-- These finishes follow the supplied gold/cyan reference; the corner fittings
	-- still change with all eight vault upgrades.
	local function piece(name: string, size: Vector3, cf: CFrame, color: Color3, glow: boolean?): Part
		local part = block(result, name, size, cf, color, false)
		part:SetAttribute("VaultFinish", nil)
		if glow then
			part:SetAttribute("PlateGlow", true)
		end
		return part
	end
	local function atOffset(x: number, y: number, z: number): CFrame
		return at * CFrame.new(x, y, z)
	end
	-- An octagon filled with individual rectangular courses. The eight rim bars
	-- cover the ends of the courses, giving a clean chamfered silhouette.
	local function octagon(
		name: string,
		radius: number,
		y: number,
		height: number,
		color: Color3,
		glow: boolean?,
		courses: number?
	)
		local count = courses or 13
		local course = radius * 2 / count
		for row = 0, count - 1 do
			local z = -radius + course * (row + 0.5)
			local halfWidth = math.min(radius, radius * math.sqrt(2) - math.abs(z))
			local part = piece(name, Vector3.new(halfWidth * 2, height, course), atOffset(0, y, z), color, glow)
			if glow then
				part:SetAttribute("PlateHighlight", 0.23)
			end
		end
	end
	piece("PlateFoot", Vector3.new(7.15, 0.10, 7.15), atOffset(0, 0.05, 0), rgb(145, 110, 36))
	piece("GoldPlateStep", Vector3.new(6.98, 0.17, 6.98), atOffset(0, 0.185, 0), gold)
	piece("GoldPlateDeck", Vector3.new(6.72, 0.06, 6.72), atOffset(0, 0.30, 0), cream)
	for _, side in { -1, 1 } do
		piece("GoldFrameRail", Vector3.new(0.16, 0.16, 6.98), atOffset(side * 3.41, 0.33, 0), gold)
		piece("GoldFrameRail", Vector3.new(6.66, 0.16, 0.16), atOffset(0, 0.33, side * 3.41), gold)
		piece("GoldFrameHighlight", Vector3.new(0.055, 0.03, 6.66), atOffset(side * 3.30, 0.395, 0), goldLight)
		piece("GoldFrameHighlight", Vector3.new(6.66, 0.03, 0.055), atOffset(0, 0.395, side * 3.30), goldLight)
	end
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			piece("CornerGoldInset", Vector3.new(0.80, 0.045, 0.80), atOffset(x * 2.93, 0.355, z * 2.93), goldLight)
		end
	end
	octagon("MetalOctagonCourse", 2.89, 0.375, 0.09, metal, false, 25)
	octagon("CyanOctagonCourse", 2.13, 0.46, 0.09, cyan, true)
	for edge = 0, 7 do
		local angle = edge * math.pi / 4
		local function radial(radius: number, y: number): CFrame
			return at * CFrame.Angles(0, angle, 0) * CFrame.new(0, y, radius)
		end
		local span = 2 * math.tan(math.pi / 8)
		piece("MetalOctagonEdge", Vector3.new(2.89 * span + 0.12, 0.095, 0.20), radial(2.89, 0.43), metalLight)
		-- Separate pale armor tabs echo the generated reference's segmented metal ring.
		for _, side in { -1, 1 } do
			piece(
				"MetalRingTab",
				Vector3.new(0.43, 0.024, 0.23),
				radial(2.72, 0.436) * CFrame.new(side * 0.55, 0, 0),
				metalLight
			)
		end
		piece("CyanOctagonEdge", Vector3.new(2.13 * span + 0.14, 0.115, 0.26), radial(2.13, 0.48), cyan, true)
		local highlight =
			piece("CyanEdgeHighlight", Vector3.new(1.94 * span * 0.70, 0.025, 0.075), radial(1.94, 0.548), cyan, true)
		highlight:SetAttribute("PlateHighlight", 0.55)
		-- A hollow diamond is four small bars, rather than an image or decal.
		local diamond = radial(2.56, 0.44) * CFrame.Angles(0, math.pi / 4, 0)
		for _, side in { -1, 1 } do
			piece("IvoryDiamond", Vector3.new(0.30, 0.026, 0.050), diamond * CFrame.new(0, 0, side * 0.15), white)
			piece("IvoryDiamond", Vector3.new(0.050, 0.026, 0.30), diamond * CFrame.new(side * 0.15, 0, 0), white)
		end
	end
	-- Gameplay and UI continue to use the original pad size and position.
	local pad =
		block(parent, `Pedestal{slot}`, Vector3.new(6.1, 0.30, 6.1), at * CFrame.new(0, 0.15, 0), VaultModel.Cyan, true)
	pad.Transparency = 1
	pad:SetAttribute("BlockPlate", true)
	local rim = piece("PlateGlowState", Vector3.new(0.1, 0.1, 0.1), atOffset(0, 0.15, 0), cyan)
	rim.Transparency = 1
	rim.Material = Enum.Material.Neon
	VaultModel.SetPlateGlow(rim)
	return { Pad = pad, Rim = rim, Details = result }
end

function VaultModel.BuildCollectTray(parent: Instance, canvas: CFrame, slot: number): Model
	local result = model(parent, `CollectTray{slot}`)
	-- A physical surround for the existing cash pill, without changing the SurfaceGui.
	block(result, "TrayBase", Vector3.new(2.95, 0.08, 5.95), canvas * CFrame.new(0, -0.035, 0), VaultModel.Navy)
	for _, side in { -1, 1 } do
		block(
			result,
			"TrayLip",
			Vector3.new(0.14, 0.06, 5.95),
			canvas * CFrame.new(side * 1.48, 0.015, 0),
			VaultModel.Graphite
		)
		block(
			result,
			"TrayEnd",
			Vector3.new(2.8, 0.06, 0.14),
			canvas * CFrame.new(0, 0.015, side * 2.96),
			VaultModel.Silver
		)
	end
	return result
end

function VaultModel.BuildLadder(parent: Instance, frame: CFrame, bottom: number, z: number): Model
	local result = model(parent, "LadderDetails")
	for _, side in { -1, 1 } do
		block(
			result,
			"LadderRail",
			Vector3.new(0.4, 24.5, 0.4),
			frame * CFrame.new(side * 1.15, bottom + 12.25, z + 0.7),
			VaultModel.Navy
		)
		for _, y in { bottom + 2, bottom + 20 } do
			block(
				result,
				"LadderBracket",
				Vector3.new(0.65, 0.35, 0.65),
				frame * CFrame.new(side * 1.15, y, z + 0.7),
				VaultModel.Silver
			)
		end
	end
	for y = bottom + 1, bottom + 21.6, 1.6 do
		block(result, "LadderRung", Vector3.new(2.3, 0.22, 0.3), frame * CFrame.new(0, y, z + 0.7), VaultModel.Silver)
	end
	return result
end

return VaultModel
