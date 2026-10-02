--!strict
-- Custom textures rendered in Blender (blender/scripts/make_textures.py) and uploaded as images.

return {
	KnifeTrail = "rbxassetid://110004816808182", -- flying knife silhouettes; speed trails
	Slash = "rbxassetid://135816525413775", -- crescent arc; swing effects
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	-- The space skybox around the floating map (tools/make_skybox.py)
	Space = {
		Ft = "rbxassetid://96731493337049",
		Bk = "rbxassetid://77499163213232",
		Lf = "rbxassetid://119221244217739",
		Rt = "rbxassetid://133009825265527",
		Up = "rbxassetid://102524642996610",
		Dn = "rbxassetid://102230386394138",
	},
	-- The toy look (tools/make_toy_textures.py): studs + big checker over floors and walls, and the
	-- swirl / money particles mounted knives give off
	Toy = {
		Stud = "rbxassetid://100551703588786",
		Checker = "rbxassetid://78121429932787",
		Swirl = "rbxassetid://108719891117380",
		Money = "rbxassetid://76716007732214",
	},
	-- The daytime sky the map floats in (tools/make_sky_day.py); Roblox draws the real sun on top
	Day = {
		Ft = "rbxassetid://83399161022636",
		Bk = "rbxassetid://73082797676258",
		Lf = "rbxassetid://86757023267568",
		Rt = "rbxassetid://108523761045371",
		Up = "rbxassetid://110235716882201",
		Dn = "rbxassetid://80516369739171",
	},
	-- Murderer perk badges (blender/scripts/make_icons.py)
	PerkIcons = {
		Fury = "rbxassetid://84497392515820",
		Identifier = "rbxassetid://114749869904247",
		Bulletproof = "rbxassetid://72004794067050",
		ShapeShifter = "rbxassetid://87566964486559",
		SpamKnife = "rbxassetid://79390759693486",
		GhostKnife = "rbxassetid://132874441064554",
		Invisiknife = "rbxassetid://102166172630486",
		LaserKnife = "rbxassetid://76151515289505",
		ExplodingKnife = "rbxassetid://130020986918800",
		Hellfire = "rbxassetid://93051345463571",
	} :: { [string]: string },
}
