--!strict
-- Staged art only; regenerate tools/build_knife_characters.py. Floor pivot, front -Z.
export type Block = {
	Name: string,
	Size: Vector3,
	Offset: Vector3,
	Color: Color3,
	Role: string,
	Angle: number?,
	Hidden: boolean?,
	Neon: boolean?,
	EyeIndex: number?,
	Follow: string?,
	SleepSize: Vector3?,
	SleepOffset: Vector3?,
	Pulse: boolean?,
}
local blocks: { Block } = {
	{
		Name = "PostBase_0",
		Size = Vector3.new(0.98, 0.2, 0.98),
		Offset = Vector3.new(0, 0.1, 0),
		Color = Color3.fromRGB(28, 48, 79),
		Role = "Post",
	},
	{
		Name = "PostBody_0",
		Size = Vector3.new(0.8, 1.95, 0.8),
		Offset = Vector3.new(0, 1.175, 0),
		Color = Color3.fromRGB(28, 48, 79),
		Role = "Post",
	},
	{
		Name = "PostCyanBand_0",
		Size = Vector3.new(0.83, 0.15, 0.83),
		Offset = Vector3.new(0, 2.18, 0),
		Color = Color3.fromRGB(52, 196, 226),
		Role = "Post",
	},
	{
		Name = "PostCap_0",
		Size = Vector3.new(0.95, 0.22, 0.95),
		Offset = Vector3.new(0, 2.365, 0),
		Color = Color3.fromRGB(238, 191, 48),
		Role = "Post",
	},
	{
		Name = "CapStud_0_-1",
		Size = Vector3.new(0.18, 0.09, 0.18),
		Offset = Vector3.new(-0.19, 2.5, 0),
		Color = Color3.fromRGB(238, 191, 48),
		Role = "Post",
	},
	{
		Name = "CapStud_0_1",
		Size = Vector3.new(0.18, 0.09, 0.18),
		Offset = Vector3.new(0.19, 2.5, 0),
		Color = Color3.fromRGB(238, 191, 48),
		Role = "Post",
	},
}
return blocks
