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
	-- The daytime sky the map floats in (tools/make_sky_day.py); Roblox draws the real sun on top.
	-- Regenerated to match Egg's own sky pixel-for-pixel (clear sky sits at G/B ~255 - a flat
	-- painted sky hits that without the global Saturation push needed to fake it cooking skin/walls.
	Day = {
		Ft = "rbxassetid://133629020225640",
		Bk = "rbxassetid://121611227462677",
		Lf = "rbxassetid://112408100556124",
		Rt = "rbxassetid://105730453586847",
		Up = "rbxassetid://130651846807231",
		Dn = "rbxassetid://107384874170226",
	},
	-- Soft light sprites for auras (Shared/KnifeHaze): a round glow and a 4-point flare, white on
	-- transparent, tinted per knife (generated with PIL, uploaded via Studio)
	Glow = {
		Soft = "rbxassetid://90958089594860",
		Flare = "rbxassetid://139779604711269",
	},
	-- Art only: tools/make_aura_sprites.py. Existing Glow sprites above are preserved.
	AuraSprites = {
		SlimeDrip = { Id = "rbxassetid://78150221812929", Flipbook = "Grid4x4", Loop = true },
		Spiral = { Id = "rbxassetid://113212498369880" },
		LightningShard = { Id = "rbxassetid://73038089248263" },
		LightningBolt = { Id = "rbxassetid://91437977789073", Flipbook = "Grid4x4", Loop = false },
		SmokeWisp = { Id = "rbxassetid://118299896019808", Flipbook = "Grid4x4", Loop = true },
		Star = { Id = "rbxassetid://124854871484890" },
		Ember = { Id = "rbxassetid://98348187767598", Flipbook = "Grid2x2", Loop = true },
		RainbowArc = { Id = "rbxassetid://75916291727116" },
		ShockRing = { Id = "rbxassetid://125086362106104" },
		LightRays = { Id = "rbxassetid://88911631872318" },
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
