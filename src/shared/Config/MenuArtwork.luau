--!strict
-- Voxel knives are individual PNGs. Existing menu-symbol atlas awaits caller wiring.
return {
	Icons = "rbxassetid://133699882433723",
	-- Roblox transcodes uploaded images to a maximum 1024px edge.
	IconSize = Vector2.new(1024, 1024),
	Knives = "", -- legacy knife atlas disabled; current callers already use KnifeIcons
	KnifeImages = require(script.Parent.VoxelUi).Knives,
	KnifeSize = Vector2.new(512, 512),
	KnifeNames = {
		"RustyShank",
		"KitchenKnife",
		"HunterBlade",
		"Switchblade",
		"Cleaver",
		"Machete",
		"GoldenDagger",
		"Katana",
		"VoidEdge",
		"InfernoFang",
		"PocketKnife",
		"ThornDagger",
		"BoneCarver",
		"Reaper",
		"MagmaCleaver",
		"DemonHorn",
		"ZeusBolt",
		"OlympusEdge",
		"AthenaBlade",
		"HaloBlade",
		"AngelFeather",
		"StarCleaver",
		"SeraphSword",
		"GalaxyKatana",
	},
}
