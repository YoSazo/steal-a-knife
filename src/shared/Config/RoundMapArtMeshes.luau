--!strict
-- Blender stair/landing art. Flight 28 deep x 8 wide; rises 15. Floor pivot; bottom +Z.
export type Mesh = { Name: string, MeshId: string, Size: Vector3, Offset: Vector3, Color: Color3 }
local meshes: { [string]: { Mesh } } = {
	-- Uploaded model 93782231220180
	OfficeStairs = {
		{
			Name = "RightRail_1",
			MeshId = "rbxassetid://89921330079214",
			Size = Vector3.new(0.660000, 17.849998, 29.115000),
			Offset = Vector3.new(3.600000, 9.674999, 0.927500),
			Color = Color3.fromRGB(55, 65, 78),
		},
		{
			Name = "RightRail_2",
			MeshId = "rbxassetid://82078243260806",
			Size = Vector3.new(0.800000, 14.490000, 27.400000),
			Offset = Vector3.new(3.600000, 11.595000, 0.000000),
			Color = Color3.fromRGB(154, 171, 189),
		},
		{
			Name = "LeftRail_3",
			MeshId = "rbxassetid://115373607355708",
			Size = Vector3.new(0.660000, 17.849998, 29.115000),
			Offset = Vector3.new(-3.600000, 9.674999, 0.927500),
			Color = Color3.fromRGB(55, 65, 78),
		},
		{
			Name = "LeftRail_4",
			MeshId = "rbxassetid://105440112631710",
			Size = Vector3.new(0.800000, 14.490000, 27.400000),
			Offset = Vector3.new(-3.600000, 11.595000, 0.000000),
			Color = Color3.fromRGB(154, 171, 189),
		},
		{
			Name = "Steps_5",
			MeshId = "rbxassetid://95552773360332",
			Size = Vector3.new(8.000000, 15.000000, 28.000000),
			Offset = Vector3.new(0.000000, 7.500000, 0.000000),
			Color = Color3.fromRGB(154, 171, 189),
		},
	},
	-- Uploaded model 122703709070393
	MansionStairs = {
		{
			Name = "RightRail_1.001",
			MeshId = "rbxassetid://79601672319411",
			Size = Vector3.new(0.660000, 17.849998, 29.115000),
			Offset = Vector3.new(3.600000, 9.674999, 0.927500),
			Color = Color3.fromRGB(91, 53, 30),
		},
		{
			Name = "RightRail_2.001",
			MeshId = "rbxassetid://73220565634582",
			Size = Vector3.new(0.480000, 16.650000, 25.656506),
			Offset = Vector3.new(3.650000, 9.075000, 0.700001),
			Color = Color3.fromRGB(139, 88, 47),
		},
		{
			Name = "RightRail_3",
			MeshId = "rbxassetid://82078243260806",
			Size = Vector3.new(0.800000, 14.490000, 27.400000),
			Offset = Vector3.new(3.600000, 11.595000, 0.000000),
			Color = Color3.fromRGB(221, 178, 71),
		},
		{
			Name = "LeftRail_4.001",
			MeshId = "rbxassetid://79637399098692",
			Size = Vector3.new(0.660000, 17.849998, 29.115000),
			Offset = Vector3.new(-3.600000, 9.674999, 0.927500),
			Color = Color3.fromRGB(91, 53, 30),
		},
		{
			Name = "LeftRail_5",
			MeshId = "rbxassetid://81438147563873",
			Size = Vector3.new(0.480000, 16.650000, 25.656506),
			Offset = Vector3.new(-3.650000, 9.075000, 0.700001),
			Color = Color3.fromRGB(139, 88, 47),
		},
		{
			Name = "LeftRail_6",
			MeshId = "rbxassetid://82078243260806",
			Size = Vector3.new(0.800000, 14.490000, 27.400000),
			Offset = Vector3.new(-3.600000, 11.595000, 0.000000),
			Color = Color3.fromRGB(221, 178, 71),
		},
		{
			Name = "Steps_7",
			MeshId = "rbxassetid://95552773360332",
			Size = Vector3.new(8.000000, 15.000000, 28.000000),
			Offset = Vector3.new(0.000000, 7.500000, 0.000000),
			Color = Color3.fromRGB(139, 88, 47),
		},
	},
	-- Uploaded model 107077352853490
	OfficeBalustrade = {
		{
			Name = "Body_1",
			MeshId = "rbxassetid://118611307948101",
			Size = Vector3.new(8.000000, 3.280000, 0.460000),
			Offset = Vector3.new(0.000000, 1.880000, 0.000000),
			Color = Color3.fromRGB(55, 65, 78),
		},
		{
			Name = "Body_2",
			MeshId = "rbxassetid://135140121597066",
			Size = Vector3.new(7.680000, 2.840000, 0.180000),
			Offset = Vector3.new(0.000000, 1.860000, 0.000000),
			Color = Color3.fromRGB(154, 171, 189),
		},
	},
	-- Uploaded model 74548422958197
	MansionBalustrade = {
		{
			Name = "Body_1.001",
			MeshId = "rbxassetid://118611307948101",
			Size = Vector3.new(8.000000, 3.280000, 0.460000),
			Offset = Vector3.new(0.000000, 1.880000, 0.000000),
			Color = Color3.fromRGB(91, 53, 30),
		},
		{
			Name = "Body_2.001",
			MeshId = "rbxassetid://84273131171745",
			Size = Vector3.new(7.930000, 2.650000, 0.408954),
			Offset = Vector3.new(0.000000, 1.725000, 0.000000),
			Color = Color3.fromRGB(139, 88, 47),
		},
	},
}
return meshes
