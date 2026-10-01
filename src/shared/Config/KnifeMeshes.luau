--!strict
-- Mesh data for the Blender knives (blender/scripts/make_knives.py -> tools/upload_model.py).
-- Read out of the uploaded models in Studio: each part's MeshId, size and offset from the grip,
-- in the model's own frame (blade along -X, spine up +Y). KnifeModel turns these into MeshParts.
-- Regenerate after re-uploading: insert each model id from blender/uploaded_assets.json in
-- Studio and read Handle.CFrame:ToObjectSpace(part.CFrame) for every MeshPart.

export type MeshPartSpec = { Name: string, MeshId: string, Size: Vector3, Offset: Vector3 }

local KnifeMeshes: { [string]: { MeshPartSpec } } = {
	RustyShank = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://136184575161880",
			Size = Vector3.new(1.200, 0.300, 0.100),
			Offset = Vector3.new(-1.000, 0.000, 0.000),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://137697278978541",
			Size = Vector3.new(0.060, 0.150, 0.130),
			Offset = Vector3.new(-0.370, -0.030, 0.000),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://81663778122088",
			Size = Vector3.new(0.700, 0.160, 0.168),
			Offset = Vector3.new(0.000, 0.000, 0.000),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://121310977463784",
			Size = Vector3.new(0.190, 0.200, 0.200),
			Offset = Vector3.new(0.400, 0.000, 0.000),
		},
	},
	KitchenKnife = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://106305903606401",
			Size = Vector3.new(1.500, 0.400, 0.100),
			Offset = Vector3.new(-1.200, 0.000, 0.000),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://108611750885280",
			Size = Vector3.new(0.552, 0.060, 0.228),
			Offset = Vector3.new(0.000, 0.000, 0.000),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://105001001497546",
			Size = Vector3.new(0.140, 0.220, 0.160),
			Offset = Vector3.new(-0.390, -0.060, 0.000),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://134945261219768",
			Size = Vector3.new(0.800, 0.152, 0.160),
			Offset = Vector3.new(0.000, 0.000, 0.000),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://110818574757448",
			Size = Vector3.new(0.190, 0.200, 0.200),
			Offset = Vector3.new(0.450, 0.000, 0.000),
		},
	},
	HunterBlade = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://136693473791845",
			Size = Vector3.new(1.700, 0.360, 0.100),
			Offset = Vector3.new(-1.300, 0.000, 0.000),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://75836668439234",
			Size = Vector3.new(0.450, 0.178, 0.187),
			Offset = Vector3.new(-0.050, 0.000, 0.000),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://81420146381893",
			Size = Vector3.new(0.133, 0.932, 0.160),
			Offset = Vector3.new(-0.400, 0.000, 0.000),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://74196481900563",
			Size = Vector3.new(0.800, 0.162, 0.170),
			Offset = Vector3.new(0.000, 0.000, 0.000),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://89890994800670",
			Size = Vector3.new(0.190, 0.200, 0.200),
			Offset = Vector3.new(0.450, 0.000, 0.000),
		},
	},
	Switchblade = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://129871321388844",
			Size = Vector3.new(1.400, 0.228, 0.100),
			Offset = Vector3.new(-1.250, 0.006, 0.000),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://107525083124334",
			Size = Vector3.new(0.120, 0.080, 0.050),
			Offset = Vector3.new(-0.300, 0.104, 0.000),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://72587266761337",
			Size = Vector3.new(0.060, 0.120, 0.130),
			Offset = Vector3.new(-0.520, -0.024, 0.000),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://115864079188792",
			Size = Vector3.new(1.000, 0.208, 0.128),
			Offset = Vector3.new(0.000, 0.000, 0.000),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://101848157247081",
			Size = Vector3.new(0.190, 0.200, 0.200),
			Offset = Vector3.new(0.550, 0.000, 0.000),
		},
	},
	Cleaver = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://137263037038051",
			Size = Vector3.new(1.350, 0.800, 0.100),
			Offset = Vector3.new(-1.125, 0.000, 0.000),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://102121709904445",
			Size = Vector3.new(1.913, 0.334, 0.238),
			Offset = Vector3.new(-0.681, 0.137, 0.000),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://129265606420769",
			Size = Vector3.new(0.060, 0.400, 0.130),
			Offset = Vector3.new(-0.420, -0.080, 0.000),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://90416435678805",
			Size = Vector3.new(0.800, 0.162, 0.170),
			Offset = Vector3.new(0.000, 0.000, 0.000),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://89144799148148",
			Size = Vector3.new(0.190, 0.200, 0.200),
			Offset = Vector3.new(0.450, 0.000, 0.000),
		},
	},
	Machete = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://82334913023888",
			Size = Vector3.new(2.300, 0.438, 0.100),
			Offset = Vector3.new(-1.625, 0.009, 0.000),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://133475917488017",
			Size = Vector3.new(0.100, 0.546, 0.220),
			Offset = Vector3.new(-0.425, 0.000, 0.000),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://120711326708528",
			Size = Vector3.new(0.850, 0.181, 0.190),
			Offset = Vector3.new(0.000, 0.000, 0.000),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://96725313519303",
			Size = Vector3.new(0.190, 0.200, 0.200),
			Offset = Vector3.new(0.475, 0.000, 0.000),
		},
	},
	GoldenDagger = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://95132533074411",
			Size = Vector3.new(1.800, 0.424, 0.100),
			Offset = Vector3.new(-1.300, 0.000, 0.000),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://87348845474437",
			Size = Vector3.new(1.892, 0.150, 0.143),
			Offset = Vector3.new(-0.489, 0.000, 0.000),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://127620573199913",
			Size = Vector3.new(0.133, 1.064, 0.160),
			Offset = Vector3.new(-0.350, 0.000, 0.000),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://103606595555070",
			Size = Vector3.new(0.700, 0.152, 0.160),
			Offset = Vector3.new(0.000, 0.000, 0.000),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://123652607262180",
			Size = Vector3.new(0.190, 0.200, 0.200),
			Offset = Vector3.new(0.400, 0.000, 0.000),
		},
	},
	Katana = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://139386318983264",
			Size = Vector3.new(2.800, 0.372, 0.100),
			Offset = Vector3.new(-2.050, 0.076, 0.000),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://76089660113844",
			Size = Vector3.new(0.120, 0.253, 0.080),
			Offset = Vector3.new(-0.710, 0.011, 0.000),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://94548352789283",
			Size = Vector3.new(0.050, 0.429, 0.440),
			Offset = Vector3.new(-0.620, 0.000, 0.000),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://85176144156012",
			Size = Vector3.new(1.200, 0.170, 0.179),
			Offset = Vector3.new(0.000, 0.000, 0.000),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://125386731006611",
			Size = Vector3.new(0.090, 0.175, 0.184),
			Offset = Vector3.new(0.630, 0.000, 0.000),
		},
	},
	VoidEdge = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://114512663774985",
			Size = Vector3.new(2.300, 0.594, 0.100),
			Offset = Vector3.new(-1.625, 0.008, 0.000),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://70687251176884",
			Size = Vector3.new(1.290, 0.975, 0.140),
			Offset = Vector3.new(-1.331, 0.024, 0.000),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://108948417972677",
			Size = Vector3.new(0.183, 1.244, 0.180),
			Offset = Vector3.new(-0.442, 0.000, 0.000),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://125212434663608",
			Size = Vector3.new(0.850, 0.162, 0.170),
			Offset = Vector3.new(0.000, 0.000, 0.000),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://108001852420915",
			Size = Vector3.new(0.280, 0.173, 0.200),
			Offset = Vector3.new(0.555, 0.000, 0.000),
		},
	},
	InfernoFang = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://119871541048590",
			Size = Vector3.new(2.000, 0.988, 0.100),
			Offset = Vector3.new(-1.475, 0.244, 0.000),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://91226163868246",
			Size = Vector3.new(1.351, 0.502, 0.120),
			Offset = Vector3.new(-1.345, 0.437, 0.000),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://113027827070832",
			Size = Vector3.new(0.183, 1.244, 0.180),
			Offset = Vector3.new(-0.442, 0.000, 0.000),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://140154255442511",
			Size = Vector3.new(0.850, 0.171, 0.180),
			Offset = Vector3.new(0.000, 0.000, 0.000),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://108001852420915",
			Size = Vector3.new(0.280, 0.173, 0.200),
			Offset = Vector3.new(0.555, 0.000, 0.000),
		},
	},
}

return KnifeMeshes
