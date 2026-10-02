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
	-- Biome knives (blender/scripts/make_knives.py, second batch)
	PocketKnife = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://121107804211996",
			Size = Vector3.new(1.050, 0.285, 0.100),
			Offset = Vector3.new(-1.000, 0.008, 0),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://129029923714275",
			Size = Vector3.new(0.602, 0.174, 0.228),
			Offset = Vector3.new(0, 0.057, 0),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://117135558034888",
			Size = Vector3.new(0.060, 0.150, 0.130),
			Offset = Vector3.new(-0.445, -0.030, 0),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://90756128982335",
			Size = Vector3.new(0.850, 0.208, 0.128),
			Offset = Vector3.new(0, 0, 0),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://84563917297194",
			Size = Vector3.new(0.190, 0.200, 0.200),
			Offset = Vector3.new(0.475, 0, 0),
		},
	},
	ThornDagger = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://138265604593376",
			Size = Vector3.new(1.600, 0.383, 0.100),
			Offset = Vector3.new(-1.225, 0, 0),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://74105472012113",
			Size = Vector3.new(1.298, 0.565, 0.070),
			Offset = Vector3.new(-1.193, 0.006, 0),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://71490172015943",
			Size = Vector3.new(0.133, 0.976, 0.160),
			Offset = Vector3.new(-0.375, 0, 0),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://98739592027978",
			Size = Vector3.new(0.750, 0.170, 0.179),
			Offset = Vector3.new(0, 0, 0),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://115530054862675",
			Size = Vector3.new(0.190, 0.200, 0.200),
			Offset = Vector3.new(0.425, 0, 0),
		},
	},
	BoneCarver = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://131795264434869",
			Size = Vector3.new(2.000, 0.455, 0.100),
			Offset = Vector3.new(-1.450, 0.017, 0),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://74086225217345",
			Size = Vector3.new(1.587, 0.393, 0.100),
			Offset = Vector3.new(-1.440, 0.083, 0),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://135942622361301",
			Size = Vector3.new(0.100, 0.546, 0.220),
			Offset = Vector3.new(-0.400, 0, 0),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://107785768336633",
			Size = Vector3.new(0.800, 0.171, 0.180),
			Offset = Vector3.new(0, 0, 0),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://110818574757448",
			Size = Vector3.new(0.190, 0.200, 0.200),
			Offset = Vector3.new(0.450, 0, 0),
		},
	},
	Reaper = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://90711531188931",
			Size = Vector3.new(2.100, 1.403, 0.100),
			Offset = Vector3.new(-1.750, -0.426, 0),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://71018395520412",
			Size = Vector3.new(0.247, 0.290, 0.260),
			Offset = Vector3.new(0.820, 0.005, 0),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://119078451546391",
			Size = Vector3.new(0.183, 1.309, 0.180),
			Offset = Vector3.new(-0.667, 0, 0),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://123785653804787",
			Size = Vector3.new(1.300, 0.170, 0.179),
			Offset = Vector3.new(0, 0, 0),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://75065695483666",
			Size = Vector3.new(0.280, 0.173, 0.200),
			Offset = Vector3.new(0.780, 0, 0),
		},
	},
	MagmaCleaver = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://103466754478999",
			Size = Vector3.new(1.400, 0.850, 0.100),
			Offset = Vector3.new(-1.150, 0, 0),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://98648691172734",
			Size = Vector3.new(1.137, 0.320, 0.140),
			Offset = Vector3.new(-1.143, -0.565, 0),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://81967363865876",
			Size = Vector3.new(0.183, 1.699, 0.180),
			Offset = Vector3.new(-0.417, 0, 0),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://88455387253308",
			Size = Vector3.new(0.800, 0.171, 0.180),
			Offset = Vector3.new(0, 0, 0),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://138650036862205",
			Size = Vector3.new(0.280, 0.173, 0.200),
			Offset = Vector3.new(0.530, 0, 0),
		},
	},
	DemonHorn = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://121237619814948",
			Size = Vector3.new(2.200, 0.900, 0.100),
			Offset = Vector3.new(-1.575, 0.200, 0),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://132060899000548",
			Size = Vector3.new(1.685, 0.787, 0.498),
			Offset = Vector3.new(-1.564, 0.159, 0),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://108948417972677",
			Size = Vector3.new(0.183, 1.244, 0.180),
			Offset = Vector3.new(-0.442, 0, 0),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://140154255442511",
			Size = Vector3.new(0.850, 0.171, 0.180),
			Offset = Vector3.new(0, 0, 0),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://108001852420915",
			Size = Vector3.new(0.280, 0.173, 0.200),
			Offset = Vector3.new(0.555, 0, 0),
		},
	},
	ZeusBolt = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://133670471440824",
			Size = Vector3.new(2.500, 0.602, 0.100),
			Offset = Vector3.new(-1.750, 0.003, 0),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://136360554472827",
			Size = Vector3.new(1.985, 0.615, 0.060),
			Offset = Vector3.new(-1.773, -0.020, 0),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://90601350686681",
			Size = Vector3.new(0.050, 0.429, 0.440),
			Offset = Vector3.new(-0.470, 0, 0),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://117214991262990",
			Size = Vector3.new(0.900, 0.152, 0.160),
			Offset = Vector3.new(0, 0, 0),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://117818467761992",
			Size = Vector3.new(0.090, 0.175, 0.184),
			Offset = Vector3.new(0.480, 0, 0),
		},
	},
	AthenaBlade = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://78400886922427",
			Size = Vector3.new(2.100, 0.462, 0.100),
			Offset = Vector3.new(-1.500, 0, 0),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://127798819064328",
			Size = Vector3.new(1.418, 1.342, 0.075),
			Offset = Vector3.new(-0.949, 0, 0),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://93862487053895",
			Size = Vector3.new(0.133, 1.064, 0.160),
			Offset = Vector3.new(-0.400, 0, 0),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://138940889968738",
			Size = Vector3.new(0.800, 0.152, 0.160),
			Offset = Vector3.new(0, 0, 0),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://118916890708095",
			Size = Vector3.new(0.190, 0.200, 0.200),
			Offset = Vector3.new(0.450, 0, 0),
		},
	},
	OlympusEdge = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://140124995476720",
			Size = Vector3.new(2.400, 0.500, 0.100),
			Offset = Vector3.new(-1.675, 0, 0),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://103843737237164",
			Size = Vector3.new(1.058, 0.936, 0.400),
			Offset = Vector3.new(0.003, 0, 0),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://115502100310324",
			Size = Vector3.new(0.133, 1.240, 0.160),
			Offset = Vector3.new(-0.425, 0, 0),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://125212434663608",
			Size = Vector3.new(0.850, 0.162, 0.170),
			Offset = Vector3.new(0, 0, 0),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://90001289756033",
			Size = Vector3.new(0.190, 0.200, 0.200),
			Offset = Vector3.new(0.475, 0, 0),
		},
	},
	HaloBlade = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://109839551419674",
			Size = Vector3.new(2.600, 0.300, 0.100),
			Offset = Vector3.new(-1.800, 0, 0),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://116671682899607",
			Size = Vector3.new(0.069, 0.740, 0.377),
			Offset = Vector3.new(-0.850, 0, 0),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://133733676917286",
			Size = Vector3.new(0.133, 0.800, 0.160),
			Offset = Vector3.new(-0.450, 0, 0),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://117214991262990",
			Size = Vector3.new(0.900, 0.152, 0.160),
			Offset = Vector3.new(0, 0, 0),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://95523586980949",
			Size = Vector3.new(0.190, 0.200, 0.200),
			Offset = Vector3.new(0.500, 0, 0),
		},
	},
	SeraphSword = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://106608206104502",
			Size = Vector3.new(2.900, 0.360, 0.100),
			Offset = Vector3.new(-2.000, 0, 0),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://108709215311684",
			Size = Vector3.new(1.299, 1.099, 0.143),
			Offset = Vector3.new(-0.043, 0, 0),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://87808696790434",
			Size = Vector3.new(0.100, 0.468, 0.220),
			Offset = Vector3.new(-0.500, 0, 0),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://93751395109778",
			Size = Vector3.new(1.000, 0.162, 0.170),
			Offset = Vector3.new(0, 0, 0),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://123387704286527",
			Size = Vector3.new(0.190, 0.200, 0.200),
			Offset = Vector3.new(0.550, 0, 0),
		},
	},
	AngelFeather = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://132236070757054",
			Size = Vector3.new(2.200, 0.444, 0.100),
			Offset = Vector3.new(-1.550, 0.019, 0),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://71612334515583",
			Size = Vector3.new(1.980, 0.035, 0.080),
			Offset = Vector3.new(-1.440, 0.030, 0),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://81590516150059",
			Size = Vector3.new(0.060, 0.250, 0.130),
			Offset = Vector3.new(-0.420, -0.050, 0),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://104231418037518",
			Size = Vector3.new(0.800, 0.133, 0.140),
			Offset = Vector3.new(0, 0, 0),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://136927225229844",
			Size = Vector3.new(0.190, 0.200, 0.200),
			Offset = Vector3.new(0.450, 0, 0),
		},
	},
	StarCleaver = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://83722431544656",
			Size = Vector3.new(1.500, 0.900, 0.100),
			Offset = Vector3.new(-1.225, 0, 0),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://119729240700772",
			Size = Vector3.new(1.334, 0.424, 0.130),
			Offset = Vector3.new(-1.217, 0.033, 0),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://88070363122628",
			Size = Vector3.new(0.060, 0.450, 0.130),
			Offset = Vector3.new(-0.445, -0.090, 0),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://106717951282949",
			Size = Vector3.new(0.850, 0.171, 0.180),
			Offset = Vector3.new(0, 0, 0),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://93470676548287",
			Size = Vector3.new(0.190, 0.200, 0.200),
			Offset = Vector3.new(0.475, 0, 0),
		},
	},
	GalaxyKatana = {
		{
			Name = "Blade",
			MeshId = "rbxassetid://73448549102692",
			Size = Vector3.new(3.000, 0.405, 0.100),
			Offset = Vector3.new(-2.175, 0.083, 0),
		},
		{
			Name = "Extra",
			MeshId = "rbxassetid://106992503051027",
			Size = Vector3.new(2.350, 0.265, 0.114),
			Offset = Vector3.new(-2.167, 0.281, 0),
		},
		{
			Name = "Guard",
			MeshId = "rbxassetid://80526358541354",
			Size = Vector3.new(0.050, 0.429, 0.440),
			Offset = Vector3.new(-0.645, 0, 0),
		},
		{
			Name = "Handle",
			MeshId = "rbxassetid://107181861872721",
			Size = Vector3.new(1.250, 0.170, 0.179),
			Offset = Vector3.new(0, 0, 0),
		},
		{
			Name = "Pommel",
			MeshId = "rbxassetid://134823945076074",
			Size = Vector3.new(0.090, 0.175, 0.184),
			Offset = Vector3.new(0.655, 0, 0),
		},
	},
}

return KnifeMeshes
