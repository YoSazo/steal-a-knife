--!strict
-- Square-built surface details from blender/scripts/detail_knives.py.
-- Every skin fits the same dagger silhouette, in blade -X / spine +Y coordinates.
local KnifeDetailMeshes: { [string]: { { Name: string, MeshId: string, Size: Vector3, Offset: Vector3 } } } = {
	RustyShank = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://112054219427814",
			Size = Vector3.new(1.291410, 0.130220, 0.111862),
			Offset = Vector3.new(-1.283595, 0.033581, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://76791633915411",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	KitchenKnife = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://78489713165011",
			Size = Vector3.new(1.291410, 0.165117, 0.118883),
			Offset = Vector3.new(-1.283595, 0.033132, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://97626722747061",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	HunterBlade = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://89521008302395",
			Size = Vector3.new(1.291410, 0.164220, 0.118883),
			Offset = Vector3.new(-1.283595, 0.033201, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://97626722747061",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	Switchblade = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://128248036044706",
			Size = Vector3.new(1.291410, 0.164600, 0.118883),
			Offset = Vector3.new(-1.283595, 0.033391, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://97626722747061",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	Cleaver = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://109767429039046",
			Size = Vector3.new(1.291410, 0.164220, 0.118883),
			Offset = Vector3.new(-1.283595, 0.033201, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://97626722747061",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	Machete = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://126884869173050",
			Size = Vector3.new(1.291410, 0.165117, 0.119332),
			Offset = Vector3.new(-1.283595, 0.033132, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://97626722747061",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	GoldenDagger = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://102849410349517",
			Size = Vector3.new(1.291410, 0.232220, 0.119332),
			Offset = Vector3.new(-1.283595, 0.033201, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://97626722747061",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	Katana = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://89955438793195",
			Size = Vector3.new(1.250010, 0.164669, 0.119724),
			Offset = Vector3.new(-1.262895, 0.033184, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://97626722747061",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	VoidEdge = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://88716346400912",
			Size = Vector3.new(1.291410, 0.165117, 0.119332),
			Offset = Vector3.new(-1.283595, 0.033132, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://97626722747061",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	InfernoFang = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://131276442882323",
			Size = Vector3.new(1.291410, 0.198462, 0.112107),
			Offset = Vector3.new(-1.283595, 0.033080, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://97626722747061",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	PocketKnife = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://117499947427290",
			Size = Vector3.new(1.291410, 0.164669, 0.119724),
			Offset = Vector3.new(-1.283595, 0.033184, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://97626722747061",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	ThornDagger = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://81804707012838",
			Size = Vector3.new(1.352010, 0.172090, 0.119724),
			Offset = Vector3.new(-1.313895, 0.037136, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://97626722747061",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	BoneCarver = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://124673295957830",
			Size = Vector3.new(1.291410, 0.164841, 0.118883),
			Offset = Vector3.new(-1.283595, 0.033270, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://97626722747061",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	Reaper = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://75927582788731",
			Size = Vector3.new(1.291410, 0.198669, 0.112107),
			Offset = Vector3.new(-1.283595, 0.033184, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://76791633915411",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	MagmaCleaver = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://139553383546820",
			Size = Vector3.new(1.352010, 0.199117, 0.111862),
			Offset = Vector3.new(-1.313895, 0.033132, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://76791633915411",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	DemonHorn = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://82381127370309",
			Size = Vector3.new(1.291410, 0.164841, 0.119724),
			Offset = Vector3.new(-1.283595, 0.033270, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://97626722747061",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	ZeusBolt = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://72404958340231",
			Size = Vector3.new(1.291410, 0.232013, 0.118883),
			Offset = Vector3.new(-1.283595, 0.033305, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://76791633915411",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	AthenaBlade = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://128937915509252",
			Size = Vector3.new(1.291410, 0.198600, 0.112107),
			Offset = Vector3.new(-1.283595, 0.033391, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://97626722747061",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	OlympusEdge = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://89933667230788",
			Size = Vector3.new(1.291410, 0.198462, 0.112013),
			Offset = Vector3.new(-1.283595, 0.033080, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://76791633915411",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	HaloBlade = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://139530562441316",
			Size = Vector3.new(1.291410, 0.164669, 0.119724),
			Offset = Vector3.new(-1.283595, 0.033184, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://97626722747061",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	SeraphSword = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://138458502724454",
			Size = Vector3.new(1.352010, 0.172090, 0.119332),
			Offset = Vector3.new(-1.313895, 0.037136, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://118609839834100",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	AngelFeather = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://85347885863364",
			Size = Vector3.new(1.352010, 0.198220, 0.112013),
			Offset = Vector3.new(-1.313895, 0.033201, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://97626722747061",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	StarCleaver = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://133847360082381",
			Size = Vector3.new(1.250010, 0.164462, 0.119724),
			Offset = Vector3.new(-1.262895, 0.033080, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://97626722747061",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
	GalaxyKatana = {
		{
			Name = "CuttingEdge",
			MeshId = "rbxassetid://99897476624653",
			Size = Vector3.new(1.725000, 0.402346, 0.037000),
			Offset = Vector3.new(-1.262500, 0.000000, 0.000000),
		},
		{
			Name = "Inlay",
			MeshId = "rbxassetid://139144817309779",
			Size = Vector3.new(1.250010, 0.164669, 0.119724),
			Offset = Vector3.new(-1.262895, 0.033184, 0.000000),
		},
		{
			Name = "GripDetail",
			MeshId = "rbxassetid://76791633915411",
			Size = Vector3.new(0.571000, 0.123200, 0.197400),
			Offset = Vector3.new(-0.010500, 0.000000, 0.000000),
		},
	},
}
return KnifeDetailMeshes
