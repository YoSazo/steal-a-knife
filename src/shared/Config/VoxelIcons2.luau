--!strict
-- Transparent icon art only. Claude builds and wires the simple menus/world signs.
-- Wheel is the training/hamster wheel; use the existing VoxelUi.Hud.Spin for the prize wheel.
export type Asset = { Image: string, AssetId: number, Size: Vector2, File: string }
local assets: { [string]: Asset } = {
	["UpgradeBaseHouse"] = {
		Image = "rbxassetid://122226412194681",
		AssetId = 122226412194681,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/UpgradeBaseHouse.png",
	},
	["Vanish"] = {
		Image = "rbxassetid://84164839277435",
		AssetId = 84164839277435,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Vanish.png",
	},
	["Radar"] = {
		Image = "rbxassetid://80498499544898",
		AssetId = 80498499544898,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Radar.png",
	},
	["BearTrap"] = {
		Image = "rbxassetid://72708362600238",
		AssetId = 72708362600238,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/BearTrap.png",
	},
	["Shield"] = {
		Image = "rbxassetid://86576658294834",
		AssetId = 86576658294834,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Shield.png",
	},
	["Decoy"] = {
		Image = "rbxassetid://121621085510086",
		AssetId = 121621085510086,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Decoy.png",
	},
	["Flash"] = {
		Image = "rbxassetid://84946891731920",
		AssetId = 84946891731920,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Flash.png",
	},
	["Barricade"] = {
		Image = "rbxassetid://71978972732972",
		AssetId = 71978972732972,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Barricade.png",
	},
	["Mimic"] = {
		Image = "rbxassetid://88337804447294",
		AssetId = 88337804447294,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Mimic.png",
	},
	["Rebirth"] = {
		Image = "rbxassetid://94712775495596",
		AssetId = 94712775495596,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Rebirth.png",
	},
	["VIP"] = {
		Image = "rbxassetid://116478827475694",
		AssetId = 116478827475694,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/VIP.png",
	},
	["Trade"] = {
		Image = "rbxassetid://83901010234658",
		AssetId = 83901010234658,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Trade.png",
	},
	["Invite"] = {
		Image = "rbxassetid://97304641285177",
		AssetId = 97304641285177,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Invite.png",
	},
	["Wheel"] = {
		Image = "rbxassetid://113872167575703",
		AssetId = 113872167575703,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Wheel.png",
	},
	["Health"] = {
		Image = "rbxassetid://92543209029351",
		AssetId = 92543209029351,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Health.png",
	},
	["Trail"] = {
		Image = "rbxassetid://70791950248703",
		AssetId = 70791950248703,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Trail.png",
	},
	["Floor"] = {
		Image = "rbxassetid://82130919479220",
		AssetId = 82130919479220,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Floor.png",
	},
	["Padlock"] = {
		Image = "rbxassetid://84009784334768",
		AssetId = 84009784334768,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Padlock.png",
	},
	["Gift"] = {
		Image = "rbxassetid://136881718526545",
		AssetId = 136881718526545,
		Size = Vector2.new(512, 512),
		File = "assets/voxel-icons-2/png/Gift.png",
	},
}

local icons: { [string]: string } = {}
for name, asset in assets do
	icons[name] = asset.Image
end

local powers: { [string]: string } = {
	Vanish = icons.Vanish,
	Radar = icons.Radar,
	BearTrap = icons.BearTrap,
	Shield = icons.Shield,
	Decoy = icons.Decoy,
	Flash = icons.Flash,
	Barricade = icons.Barricade,
	Mimic = icons.Mimic,
	["Bear Trap"] = icons.BearTrap,
}

return {
	Version = 1,
	Assets = assets,
	Icons = icons,
	Powers = powers,
}
