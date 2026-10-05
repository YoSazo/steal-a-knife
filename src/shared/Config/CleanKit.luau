--!strict
-- UI frame kit cut straight from the original Powers mockup (assets/visual-expansion/mockups) by
-- assets/voxel-ui/clean-kit: real pixels of the reference, interiors widened so they 9-slice.
-- Text and icons are never baked in (except the close button's X).
export type Piece = { Image: string, Size: Vector2, Slice: Rect? }
local function id(n: string): string
	return "rbxassetid://" .. n
end
return {
	PrimaryButton = { Image = id("74528377408943"), Size = Vector2.new(166, 56), Slice = Rect.new(12, 12, 154, 44) },
	SecondaryButton = { Image = id("128944287026326"), Size = Vector2.new(166, 56), Slice = Rect.new(12, 12, 154, 44) },
	CloseButton = { Image = id("72760474364712"), Size = Vector2.new(90, 84) },
	TitlePlate = { Image = id("135912769036007"), Size = Vector2.new(656, 110), Slice = Rect.new(26, 26, 630, 84) },
	CurrencyPill = { Image = id("124520985370853"), Size = Vector2.new(250, 76), Slice = Rect.new(16, 16, 234, 60) },
	NavItem = { Image = id("118073335437142"), Size = Vector2.new(214, 70), Slice = Rect.new(14, 14, 200, 56) },
	NavActive = { Image = id("100026714276512"), Size = Vector2.new(232, 74), Slice = Rect.new(16, 16, 216, 58) },
	ProgressTrack = { Image = id("105736368817492"), Size = Vector2.new(334, 31), Slice = Rect.new(10, 8, 324, 23) },
	ProgressFill = { Image = id("75852687581493"), Size = Vector2.new(70, 25), Slice = Rect.new(6, 6, 64, 19) },
	Card = { Image = id("140233975376571"), Size = Vector2.new(384, 366), Slice = Rect.new(26, 26, 358, 340) },
	-- The HUD's universal button tile (navy, blue border, cyan block corners), from MainHud-phone.png
	HudTile = { Image = id("75703574167205"), Size = Vector2.new(329, 136), Slice = Rect.new(30, 30, 299, 106) },
	LoadoutSlot = { Image = id("84193248399786"), Size = Vector2.new(174, 114), Slice = Rect.new(22, 22, 152, 92) },
} :: { [string]: Piece }
