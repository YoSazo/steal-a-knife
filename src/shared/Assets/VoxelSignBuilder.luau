--!strict
-- Shared physical cuboids, block letters and plain live text faces.
local Geometry = {
	Signs = {
		UpgradeBase = require(script.Parent.UpgradeBaseGeometry),
		VaultOwner = require(script.Parent.VaultOwnerGeometry),
		HauntedWheel = require(script.Parent.HauntedWheelGeometry),
		FreeChestLabel = require(script.Parent.FreeChestLabelGeometry),
		EventBoard = require(script.Parent.EventBoardGeometry),
		GateHealth = require(script.Parent.GateHealthGeometry),
		ProjectorScreen = require(script.Parent.ProjectorScreenGeometry),
	},
}
local WorldSignModel = {}
local function vec(a: { number }): Vector3
	return Vector3.new(a[1], a[2], a[3])
end
local function block(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
	p.Anchored, p.CastShadow = true, false
	p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p:SetAttribute("WorldSignBlock", true)
	p.Parent = model
	return p
end
local function basis(anchor: BasePart, side: Enum.NormalId): (CFrame, number, number, number)
	if side == Enum.NormalId.Top then
		return anchor.CFrame * CFrame.Angles(-math.pi / 2, 0, 0) * CFrame.Angles(0, 0, math.pi / 2),
			anchor.Size.Z,
			anchor.Size.X,
			anchor.Size.Y / 2
	end
	return anchor.CFrame * (if side == Enum.NormalId.Front then CFrame.Angles(0, math.pi, 0) else CFrame.identity),
		anchor.Size.X,
		anchor.Size.Y,
		anchor.Size.Z / 2
end
function WorldSignModel.Attach(kind: string, anchor: BasePart, side: Enum.NormalId?): (Model, Part)
	local spec = Geometry.Signs[kind]
	assert(spec, `Unknown world sign {kind}`)
	local old = anchor:FindFirstChild("VoxelSign")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "VoxelSign"
	model:SetAttribute("WorldSignKind", kind)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local root = block(model, "Root", Vector3.one * 0.1, anchor.CFrame, Color3.new())
	root.Transparency = 1
	model.PrimaryPart = root
	local cf, width, height, depth = basis(anchor, side or Enum.NormalId.Back)
	local scale = Vector3.new(width / spec.Width, height / spec.Height, 1)
	cf *= CFrame.new(0, 0, depth)
	for _, p in spec.Parts do
		block(
			model,
			p.Name,
			vec(p.Size) * scale,
			cf * CFrame.new(vec(p.Position) * scale),
			Color3.fromRGB(table.unpack(p.Color))
		)
	end
	local pill = kind == "CollectPad" or kind == "SellSign"
	if not pill then
		block(
			model,
			"Backing",
			Vector3.new(width, height, 0.4),
			cf * CFrame.new(0, 0, -0.12),
			Color3.fromRGB(table.unpack(spec.FaceColor))
		)
	end
	local fh = if kind == "HauntedWheel"
		then height * 0.18
		elseif kind == "VaultOwner" then height * 0.39
		elseif kind == "FreeChestLabel" then height * 0.23
		else height * 0.77
	local fy = if kind == "HauntedWheel"
		then -height * 0.4
		elseif kind == "VaultOwner" then -height * 0.24
		elseif kind == "FreeChestLabel" then -height * 0.34
		else 0
	local fw = if pill then width * 0.83 else width * 0.91
	local face = block(
		model,
		"TextFace",
		Vector3.new(fw, fh, 0.08),
		cf * CFrame.new(0, fy, 0.39),
		Color3.fromRGB(table.unpack(spec.FaceColor))
	)
	if kind == "ShopMortimer" or kind == "ShopVesper" or kind == "SafeZone" or kind == "ProjectorScreen" then
		face.Transparency = 1
	end
	anchor.Transparency = 1
	if kind == "GateHealth" then
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") then
				p:SetAttribute("Keep", true)
			end
		end
	end
	model.Parent = anchor
	return model, face
end
function WorldSignModel.MoveAttached(anchor: BasePart)
	local model = anchor:FindFirstChild("VoxelSign")
	if model and model:IsA("Model") then
		model:PivotTo(anchor.CFrame)
	end
end
function WorldSignModel.Surface(anchor: BasePart, face: BasePart, name: string, maximum: number?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name, gui.Adornee, gui.Face = name, face, Enum.NormalId.Back
	gui.SizingMode, gui.PixelsPerStud = Enum.SurfaceGuiSizingMode.PixelsPerStud, 50
	gui.LightInfluence, gui.Brightness, gui.MaxDistance = 0, 0.95, maximum or 100
	gui.Parent = anchor
	return gui
end
function WorldSignModel.LiveText(gui: Instance, name: string, text: string, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name, label.Text = name, text
	label.Size, label.BackgroundTransparency = UDim2.fromScale(1, 1), 1
	label.Font, label.TextScaled = Enum.Font.FredokaOne, true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeColor3, label.TextStrokeTransparency = Color3.fromRGB(20, 24, 36), 0.2
	label.Parent = gui
	return label
end
function WorldSignModel.SetVisible(model: Model, visible: boolean)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local original = part:GetAttribute("SignTransparency")
			if type(original) ~= "number" then
				original = part.Transparency
				part:SetAttribute("SignTransparency", original)
			end
			part.Transparency = if visible then original :: number else 1
		end
	end
end

function WorldSignModel.Build(kind: string, frame: CFrame, size: Vector3, side: Enum.NormalId?): (Model, Part, Part)
	local model = Instance.new("Model")
	model.Name = kind
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local anchor = block(model, "Mount", size, frame, Color3.new())
	anchor.Transparency = 1
	local details, face = WorldSignModel.Attach(kind, anchor, side)
	details.Parent = model
	model.PrimaryPart = anchor
	model:SetAttribute("AssetKind", kind)
	return model, face, anchor
end

return WorldSignModel
