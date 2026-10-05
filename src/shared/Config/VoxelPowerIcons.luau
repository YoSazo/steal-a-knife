--!strict
-- Art-only metadata. Claude owns UI integration; no behaviour or layouts here.
-- Innocent keys are ability IDs; KnifePowers keys are stable Config/KnifePowers IDs.
export type Asset = { Image: string, AssetId: number, Size: Vector2, File: string }
local assets: { [string]: Asset } = {
	["Innocent.Vanish"] = {
		Image = "rbxassetid://84164839277435",
		AssetId = 84164839277435,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Vanish.png",
	},
	["Innocent.Radar"] = {
		Image = "rbxassetid://80498499544898",
		AssetId = 80498499544898,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Radar.png",
	},
	["Innocent.Trap"] = {
		Image = "rbxassetid://72708362600238",
		AssetId = 72708362600238,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/BearTrap.png",
	},
	["Innocent.Shield"] = {
		Image = "rbxassetid://86576658294834",
		AssetId = 86576658294834,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Shield.png",
	},
	["Innocent.Decoy"] = {
		Image = "rbxassetid://121621085510086",
		AssetId = 121621085510086,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Decoy.png",
	},
	["Innocent.Flash"] = {
		Image = "rbxassetid://84946891731920",
		AssetId = 84946891731920,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Flash.png",
	},
	["Innocent.Barricade"] = {
		Image = "rbxassetid://71978972732972",
		AssetId = 71978972732972,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Barricade.png",
	},
	["Innocent.Mimic"] = {
		Image = "rbxassetid://88337804447294",
		AssetId = 88337804447294,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Mimic.png",
	},
	["Innocent.Rush"] = {
		Image = "rbxassetid://92452969828551",
		AssetId = 92452969828551,
		Size = Vector2.new(512, 512),
		File = "assets/power-icons-v1/png/innocent/Rush.png",
	},
	["Innocent.Dash"] = {
		Image = "rbxassetid://81473983431382",
		AssetId = 81473983431382,
		Size = Vector2.new(512, 512),
		File = "assets/power-icons-v1/png/innocent/Dash.png",
	},
	["Innocent.SmokeBurst"] = {
		Image = "rbxassetid://100976695090554",
		AssetId = 100976695090554,
		Size = Vector2.new(512, 512),
		File = "assets/power-icons-v1/png/innocent/SmokeBurst.png",
	},
	["Innocent.SecondLife"] = {
		Image = "rbxassetid://107411918614749",
		AssetId = 107411918614749,
		Size = Vector2.new(512, 512),
		File = "assets/power-icons-v1/png/innocent/SecondLife.png",
	},
	["Innocent.PhoenixWall"] = {
		Image = "rbxassetid://85866716093998",
		AssetId = 85866716093998,
		Size = Vector2.new(512, 512),
		File = "assets/power-icons-v1/png/innocent/PhoenixWall.png",
	},
	["Knife.Shadow"] = {
		Image = "rbxassetid://87095312239147",
		AssetId = 87095312239147,
		Size = Vector2.new(512, 512),
		File = "assets/power-icons-v1/png/knife-powers/Shadow.png",
	},
	["Knife.Sense"] = {
		Image = "rbxassetid://121199510059116",
		AssetId = 121199510059116,
		Size = Vector2.new(512, 512),
		File = "assets/power-icons-v1/png/knife-powers/Sense.png",
	},
	["Knife.Snare"] = {
		Image = "rbxassetid://127726583944333",
		AssetId = 127726583944333,
		Size = Vector2.new(512, 512),
		File = "assets/power-icons-v1/png/knife-powers/Snare.png",
	},
	["Knife.Disguise"] = {
		Image = "rbxassetid://77617605163895",
		AssetId = 77617605163895,
		Size = Vector2.new(512, 512),
		File = "assets/power-icons-v1/png/knife-powers/Disguise.png",
	},
	["Knife.Decoy"] = {
		Image = "rbxassetid://89619713533362",
		AssetId = 89619713533362,
		Size = Vector2.new(512, 512),
		File = "assets/power-icons-v1/png/knife-powers/Decoy.png",
	},
	["Knife.Flash"] = {
		Image = "rbxassetid://96455188607520",
		AssetId = 96455188607520,
		Size = Vector2.new(512, 512),
		File = "assets/power-icons-v1/png/knife-powers/Flash.png",
	},
	["Knife.Bulwark"] = {
		Image = "rbxassetid://78900065355182",
		AssetId = 78900065355182,
		Size = Vector2.new(512, 512),
		File = "assets/power-icons-v1/png/knife-powers/Bulwark.png",
	},
	["Knife.Phantom"] = {
		Image = "rbxassetid://94649146568283",
		AssetId = 94649146568283,
		Size = Vector2.new(512, 512),
		File = "assets/power-icons-v1/png/knife-powers/Phantom.png",
	},
	["Knife.Fury"] = {
		Image = "rbxassetid://110428934531130",
		AssetId = 110428934531130,
		Size = Vector2.new(512, 512),
		File = "assets/power-icons-v1/png/knife-powers/Fury.png",
	},
	["Knife.Laser"] = {
		Image = "rbxassetid://130508621048991",
		AssetId = 130508621048991,
		Size = Vector2.new(512, 512),
		File = "assets/power-icons-v1/png/knife-powers/Laser.png",
	},
	["Knife.Blast"] = {
		Image = "rbxassetid://71666320772323",
		AssetId = 71666320772323,
		Size = Vector2.new(512, 512),
		File = "assets/power-icons-v1/png/knife-powers/Blast.png",
	},
	["Knife.SpamKnife"] = {
		Image = "rbxassetid://78416995647502",
		AssetId = 78416995647502,
		Size = Vector2.new(512, 512),
		File = "assets/power-icons-v1/png/knife-powers/SpamKnife.png",
	},
	["Knife.Hellfire"] = {
		Image = "rbxassetid://78403209667941",
		AssetId = 78403209667941,
		Size = Vector2.new(512, 512),
		File = "assets/power-icons-v1/png/knife-powers/Hellfire.png",
	},
}

local innocent: { [string]: string } = {
	["Barricade"] = assets["Innocent.Barricade"].Image,
	["Dash"] = assets["Innocent.Dash"].Image,
	["Decoy"] = assets["Innocent.Decoy"].Image,
	["Flash"] = assets["Innocent.Flash"].Image,
	["Mimic"] = assets["Innocent.Mimic"].Image,
	["PhoenixWall"] = assets["Innocent.PhoenixWall"].Image,
	["Radar"] = assets["Innocent.Radar"].Image,
	["Rush"] = assets["Innocent.Rush"].Image,
	["SecondLife"] = assets["Innocent.SecondLife"].Image,
	["Shield"] = assets["Innocent.Shield"].Image,
	["SmokeBurst"] = assets["Innocent.SmokeBurst"].Image,
	["Trap"] = assets["Innocent.Trap"].Image,
	["Vanish"] = assets["Innocent.Vanish"].Image,
}
innocent.BearTrap = innocent.Trap
innocent["Bear Trap"] = innocent.Trap
innocent["Smoke Burst"] = innocent.SmokeBurst
innocent["Second Life"] = innocent.SecondLife
innocent["Phoenix Wall"] = innocent.PhoenixWall

local knifePowers: { [string]: string } = {
	["Invisiknife"] = assets["Knife.Shadow"].Image,
	["Identifier"] = assets["Knife.Sense"].Image,
	["Snare"] = assets["Knife.Snare"].Image,
	["ShapeShifter"] = assets["Knife.Disguise"].Image,
	["DecoyKnife"] = assets["Knife.Decoy"].Image,
	["FlashKnife"] = assets["Knife.Flash"].Image,
	["Bulletproof"] = assets["Knife.Bulwark"].Image,
	["GhostKnife"] = assets["Knife.Phantom"].Image,
	["Fury"] = assets["Knife.Fury"].Image,
	["LaserKnife"] = assets["Knife.Laser"].Image,
	["ExplodingKnife"] = assets["Knife.Blast"].Image,
	["SpamKnife"] = assets["Knife.SpamKnife"].Image,
	["Hellfire"] = assets["Knife.Hellfire"].Image,
}

local byName: { [string]: string } = {
	["Shadow"] = knifePowers["Invisiknife"],
	["Sense"] = knifePowers["Identifier"],
	["Snare"] = knifePowers["Snare"],
	["Disguise"] = knifePowers["ShapeShifter"],
	["Decoy"] = knifePowers["DecoyKnife"],
	["Flash"] = knifePowers["FlashKnife"],
	["Bulwark"] = knifePowers["Bulletproof"],
	["Phantom"] = knifePowers["GhostKnife"],
	["Fury"] = knifePowers["Fury"],
	["Laser"] = knifePowers["LaserKnife"],
	["Blast"] = knifePowers["ExplodingKnife"],
	["Spam Knife"] = knifePowers["SpamKnife"],
	["Hellfire"] = knifePowers["Hellfire"],
}

return {
	Version = 1,
	Assets = assets,
	Innocent = innocent,
	KnifePowers = knifePowers,
	ByName = byName,
}
