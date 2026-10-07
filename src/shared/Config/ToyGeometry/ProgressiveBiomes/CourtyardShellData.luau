--!strict
-- Regenerate tools/build_progressive_biomes.py. Floor origin, +Z deeper.
export type Block = {
	Name: string,
	Size: { number },
	Offset: { number },
	Color: { number },
	Detail: boolean?,
	Stud: boolean?,
	WaterFace: string?,
	Ambient: boolean?,
	Hidden: boolean?,
	Neon: boolean?,
	ProfileSource: string?,
}
export type Data = {
	Name: string,
	BiomeIndex: number,
	Origin: { number },
	Depth: number,
	BossLocalZ: number,
	Bounds: { MinX: number, MaxX: number, MinZ: number, MaxZ: number },
	ReservedLair: { LocalCenter: { number }, ClearZ: { number }, ClearHeight: number },
	Groups: { [string]: { Block } },
	PartCount: number,
	LowPartCount: number,
}
local data: Data = {
	["Name"] = "CourtyardShell",
	["BiomeIndex"] = 1,
	["Origin"] = { 0, 0, 0 },
	["Depth"] = 90,
	["BossLocalZ"] = 50,
	["Bounds"] = { ["MinX"] = -80, ["MaxX"] = 80, ["MinZ"] = 0, ["MaxZ"] = 90 },
	["ReservedLair"] = { ["LocalCenter"] = { -73, 0, 50 }, ["ClearZ"] = { 23, 77 }, ["ClearHeight"] = 32 },
	["Groups"] = {
		["Border"] = {
			{
				["Name"] = "LowBorder_-1_0",
				["Size"] = { 2, 1.5, 23 },
				["Offset"] = { -79, 0.95, 11.5 },
				["Color"] = { 40, 109, 35 },
				["Stud"] = true,
			},
			{
				["Name"] = "LowBorder_-1_1",
				["Size"] = { 2, 1.5, 13 },
				["Offset"] = { -79, 0.95, 83.5 },
				["Color"] = { 40, 109, 35 },
				["Stud"] = true,
			},
			{
				["Name"] = "LowBorder_1_0",
				["Size"] = { 2, 1.5, 90 },
				["Offset"] = { 79, 0.95, 45 },
				["Color"] = {
					40,
					109,
					35,
				},
				["Stud"] = true,
			},
			{
				["Name"] = "CornerBlock_-1_4",
				["Size"] = { 3, 2.4, 3 },
				["Offset"] = { -77.5, 1.4, 4 },
				["Color"] = { 70, 156, 45 },
				["Stud"] = true,
			},
			{
				["Name"] = "CornerBlock_-1_86",
				["Size"] = { 3, 2.4, 3 },
				["Offset"] = { -77.5, 1.4, 86 },
				["Color"] = { 70, 156, 45 },
				["Stud"] = true,
			},
			{
				["Name"] = "CornerBlock_1_4",
				["Size"] = { 3, 2.4, 3 },
				["Offset"] = { 77.5, 1.4, 4 },
				["Color"] = { 70, 156, 45 },
				["Stud"] = true,
			},
			{
				["Name"] = "CornerBlock_1_86",
				["Size"] = { 3, 2.4, 3 },
				["Offset"] = { 77.5, 1.4, 86 },
				["Color"] = { 70, 156, 45 },
				["Stud"] = true,
			},
		},
		["Entrance"] = {
			{
				["Name"] = "EdgeThreshold_Entrance_-1",
				["Size"] = { 20, 0.12, 3 },
				["Offset"] = { -70, 0.3, 1.5 },
				["Color"] = { 40, 109, 35 },
				["Stud"] = true,
			},
			{
				["Name"] = "EdgeThreshold_Entrance_1",
				["Size"] = { 20, 0.12, 3 },
				["Offset"] = { 70, 0.3, 1.5 },
				["Color"] = { 40, 109, 35 },
				["Stud"] = true,
			},
		},
		["Exit"] = {
			{
				["Name"] = "EdgeThreshold_Exit_-1",
				["Size"] = { 20, 0.12, 3 },
				["Offset"] = { -70, 0.3, 88.5 },
				["Color"] = { 40, 109, 35 },
				["Stud"] = true,
			},
			{
				["Name"] = "EdgeThreshold_Exit_1",
				["Size"] = { 20, 0.12, 3 },
				["Offset"] = { 70, 0.3, 88.5 },
				["Color"] = { 40, 109, 35 },
				["Stud"] = true,
			},
		},
	},
	["PartCount"] = 15,
	["LowPartCount"] = 15,
}
return data
