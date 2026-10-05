--!strict
-- Asset data only. Origin (0,0,0) = Courtyard entrance; +Z goes deeper.
return {
	Version = 1,
	Name = "CourtyardShell",
	Boss = "Frank",
	BossTitle = "The Groundskeeper",
	Origin = { 0, 0, 0 },
	FrontAxis = "-Z at the entrance; travel/deeper axis +Z",
	Bounds = { ["MinX"] = -80, ["MaxX"] = 80, ["MinZ"] = 0, ["MaxZ"] = 220, ["WallHeight"] = 120, ["FloorTop"] = 0.2 },
	ClearLane = { ["MinX"] = -56, ["MaxX"] = 56, ["MinZ"] = 0, ["MaxZ"] = 220, ["OverheadClearance"] = 52 },
	ReservedLair = {
		["Center"] = { -73, 0, 132 },
		["StageX"] = { -80, -66 },
		["StageZ"] = { 111, 153 },
		["ClearX"] = { -80, -62 },
		["ClearZ"] = { 105, 159 },
		["ClearHeight"] = 32,
	},
	PartCount = 2428,
	LowPartCount = 1321,
	Features = {
		["FountainCenter"] = { 68, 0, 195 },
		["EntrancePlane"] = 0,
		["ExitPlane"] = 220,
		["GateCenters"] = { 6, 214 },
		["PortalCenterZ"] = 132,
	},
	Groups = {
		LeftWall = require(script.Parent.CourtyardShell.LeftWall),
		RightWall = require(script.Parent.CourtyardShell.RightWall),
		Entrance = require(script.Parent.CourtyardShell.Entrance),
		Exit = require(script.Parent.CourtyardShell.Exit),
		Fountain = require(script.Parent.CourtyardShell.Fountain),
		Floor = require(script.Parent.CourtyardShell.Floor),
	},
}
