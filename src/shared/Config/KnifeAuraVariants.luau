--!strict
-- Fifty authored color/motion recipes; all reuse the same independently tinted atlases.
export type Layer = { Start: Color3, Finish: Color3 }
export type Motion = { Id: string, Width: number, Body: number, Curl: number, Tempo: number, Drift: number }
export type Style = { Id: string, Name: string, Colors: { [string]: Layer }, Motion: Motion }
local Variants = {}
Variants.LayerNames = table.freeze({ "Outer", "Core", "Tongues", "Smoke", "Glow", "Embers" })
local rgb = Color3.fromRGB
local function layer(start: Color3, finish: Color3): Layer
	return table.freeze({ Start = start, Finish = finish })
end
local palettes: { { string | Color3 } } = {
	{
		"Volcano",
		rgb(255, 65, 4),
		rgb(255, 226, 30),
		rgb(255, 155, 5),
		rgb(174, 206, 229),
		rgb(255, 104, 6),
		rgb(255, 238, 108),
	},
	{
		"Glacier",
		rgb(19, 116, 236),
		rgb(152, 255, 249),
		rgb(42, 218, 246),
		rgb(199, 225, 255),
		rgb(43, 152, 255),
		rgb(229, 255, 252),
	},
	{
		"Phantom",
		rgb(105, 28, 193),
		rgb(193, 255, 123),
		rgb(204, 99, 255),
		rgb(164, 194, 177),
		rgb(125, 66, 242),
		rgb(236, 255, 170),
	},
	{
		"Storm",
		rgb(36, 81, 175),
		rgb(255, 236, 71),
		rgb(137, 204, 255),
		rgb(181, 204, 232),
		rgb(72, 151, 245),
		rgb(255, 248, 151),
	},
	{
		"Sakura",
		rgb(232, 48, 131),
		rgb(255, 216, 119),
		rgb(255, 145, 195),
		rgb(223, 186, 237),
		rgb(255, 93, 158),
		rgb(255, 244, 205),
	},
	{
		"Venom",
		rgb(13, 143, 72),
		rgb(215, 255, 67),
		rgb(67, 238, 117),
		rgb(172, 214, 184),
		rgb(34, 209, 78),
		rgb(241, 255, 157),
	},
	{
		"Solar",
		rgb(243, 120, 18),
		rgb(255, 242, 122),
		rgb(255, 183, 30),
		rgb(209, 211, 229),
		rgb(255, 183, 34),
		rgb(255, 252, 216),
	},
	{
		"Ember",
		rgb(172, 33, 48),
		rgb(255, 187, 53),
		rgb(240, 71, 18),
		rgb(177, 187, 209),
		rgb(235, 73, 39),
		rgb(255, 227, 134),
	},
	{
		"Dream",
		rgb(139, 58, 226),
		rgb(121, 246, 244),
		rgb(255, 137, 205),
		rgb(207, 192, 236),
		rgb(196, 79, 222),
		rgb(247, 215, 255),
	},
	{
		"Tidal",
		rgb(13, 138, 169),
		rgb(167, 255, 214),
		rgb(64, 207, 231),
		rgb(183, 209, 226),
		rgb(30, 185, 192),
		rgb(224, 255, 175),
	},
}
local motions: { Motion } = {
	{ Id = "rolling", Width = 1, Body = 1, Curl = 1, Tempo = 1, Drift = 1 },
	{ Id = "boiling", Width = 1.1, Body = 0.92, Curl = 0.82, Tempo = 1.15, Drift = 0.8 },
	{ Id = "whirling", Width = 0.95, Body = 1, Curl = 1.1, Tempo = 1.05, Drift = 0.9 },
	{ Id = "floating", Width = 1, Body = 0.95, Curl = 1.12, Tempo = 0.8, Drift = 0.7 },
	{ Id = "surging", Width = 0.94, Body = 1, Curl = 1.08, Tempo = 1.2, Drift = 1 },
}
for _, motion in motions do
	table.freeze(motion)
end
Variants.List = {} :: { Style }
Variants.ById = {} :: { [string]: Style }
for _, palette in palettes do
	local name = palette[1] :: string
	for index, motion in motions do
		local outer, core, tongues, smoke, glow, embers =
			palette[2] :: Color3,
			palette[3] :: Color3,
			palette[4] :: Color3,
			palette[5] :: Color3,
			palette[6] :: Color3,
			palette[7] :: Color3
		-- Accent mixing is independent for each role, never a single hue tint over the whole effect.
		local accent = (index - 1) * 0.075
		local colors = {
			Outer = layer(outer:Lerp(tongues, accent * 0.5), outer:Lerp(rgb(30, 20, 43), 0.15)),
			Core = layer(core:Lerp(embers, accent), core:Lerp(tongues, 0.55)),
			Tongues = layer(tongues:Lerp(core, accent), tongues:Lerp(outer, 0.55)),
			Smoke = layer(tongues:Lerp(smoke, 0.65 + accent * 0.5), smoke),
			Glow = layer(glow:Lerp(tongues, accent), outer),
			Embers = layer(embers:Lerp(core, accent), tongues),
		}
		local style: Style = table.freeze({
			Id = string.lower(name) .. "-" .. motion.Id,
			Name = name .. " " .. motion.Id,
			Colors = table.freeze(colors),
			Motion = motion,
		})
		table.insert(Variants.List, style)
		Variants.ById[style.Id] = style
	end
end

-- Pick each layer from a different recipe, or supply original start/end colors per layer.
function Variants.Compose(baseId: string, sources: { [string]: string }?, overrides: { [string]: Layer }?): Style
	local base = Variants.ById[baseId]
	assert(base, "Unknown aura variation: " .. baseId)
	local colors = table.clone(base.Colors)
	for role, id in pairs(sources or {}) do
		assert(colors[role], "Unknown aura layer: " .. role)
		local source = Variants.ById[id]
		assert(source, "Unknown source variation: " .. id)
		colors[role] = source.Colors[role]
	end
	for role, pair in pairs(overrides or {}) do
		assert(colors[role], "Unknown aura layer: " .. role)
		colors[role] = layer(pair.Start, pair.Finish)
	end
	return table.freeze({
		Id = base.Id .. "-mix",
		Name = base.Name .. " mix",
		Colors = table.freeze(colors),
		Motion = base.Motion,
	})
end
table.freeze(Variants.List)
table.freeze(Variants.ById)
return table.freeze(Variants)
