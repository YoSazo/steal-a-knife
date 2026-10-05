--!strict
-- Three transparent artwork layers only. Dynamic prize wedges stay code-drawn.
-- Pixel coordinates are measured against a 512 x 512 rim canvas; Claude wires the UI.
export type Asset = { Image: string, AssetId: number, Size: Vector2, SliceCenter: Rect? }
local assets: { [string]: Asset } = {
	WheelRim = {
		Image = "rbxassetid://118134067956386",
		AssetId = 118134067956386,
		Size = Vector2.new(512, 512),
	},
	WheelPointer = {
		Image = "rbxassetid://77319137036398",
		AssetId = 77319137036398,
		Size = Vector2.new(512, 512),
	},
	WheelHub = {
		Image = "rbxassetid://138527918133409",
		AssetId = 138527918133409,
		Size = Vector2.new(512, 512),
	},
}

return {
	Version = 1,
	Assets = assets,
	Images = {
		WheelRim = assets.WheelRim.Image,
		WheelPointer = assets.WheelPointer.Image,
		WheelHub = assets.WheelHub.Image,
	},
	Layout = {
		ReferenceSize = Vector2.new(512, 512),
		WheelCenter = Vector2.new(256, 256),
		WedgeRadius = 159,
		PointerCanvasSize = Vector2.new(96, 96),
		PointerTip = Vector2.new(255.0, 447),
		PointerTipTarget = Vector2.new(256, 118),
		HubCanvasSize = Vector2.new(112, 112),
	},
}
