--!strict
-- The cartoon art pack (assets/ui/cartoon-pack-v1, manifest ids -> uploaded Roblox images).
-- Single PNGs, no atlases. Sizes are the delivery PNG sizes, used only for aspect ratios.
local function id(n: string): string
	return "rbxassetid://" .. n
end

return {
	-- Boss lairs, by GameConfig.Zones order (names / titles are baked into the art)
	LairSigns = {
		id("137752825165618"), -- frank
		id("90529851929781"), -- ivy
		id("107562928932529"), -- sam
		id("118628173841939"), -- leo
		id("95471004821857"), -- ruby
		id("88452279426471"), -- kate
		id("95170440531079"), -- zoe
		id("115293656617427"), -- nick
	},
	LairSignSize = Vector2.new(1024, 256),
	BossRibbons = {
		id("114530378332035"),
		id("125859087131361"),
		id("116165822576206"),
		id("138516741822457"),
		id("125815936481031"),
		id("72990091845248"),
		id("138198240786263"),
		id("87299956444528"),
	},
	BossRibbonSize = Vector2.new(768, 128),
	BossPlates = {
		id("128002480725855"),
		id("107803532482776"),
		id("131608338078173"),
		id("70812033266576"),
		id("137863355543924"),
		id("111899220692426"),
		id("79889943943274"),
		id("114067844385565"),
	},
	-- Vault knife plates by the mounted knife's rarity (Common for an empty plate)
	KnifePlates = {
		Common = id("91218497528530"),
		Rare = id("122635286237878"),
		Epic = id("113450804672093"),
		Legendary = id("97162913080613"),
		Mythic = id("72033792717664"),
		Godly = id("101904854597890"),
		Celestial = id("71820483503397"),
		Cosmic = id("117275612759953"),
	} :: { [string]: string },
	-- World signs: no baked text (prices / labels stay native and live)
	UpgradeBase = id("140357718144934"), -- 1024x512, house on the left
	Sell = id("111237297468974"), -- 1024x512
	Collect = id("75051914385786"), -- 1024x512
	-- Where each board sits in its 1024x512 PNG (measured from the alpha), and the 9-slice centre
	-- inside that crop: everything left of X (the cash stack / house) and the rounded ends stay
	-- intact; only the plain middle grows, so boards can be taller than the art without stretching.
	-- (Under 1024px, so Roblox delivers these at their real size.)
	BoardCrops = {
		Sell = { Offset = Vector2.new(20, 60), Size = Vector2.new(984, 392), Center = Rect.new(300, 230, 924, 332) },
		Collect = { Offset = Vector2.new(20, 93), Size = Vector2.new(984, 326), Center = Rect.new(300, 200, 924, 266) },
		UpgradeBase = {
			Offset = Vector2.new(20, 88),
			Size = Vector2.new(984, 336),
			Center = Rect.new(300, 200, 924, 276),
		},
	} :: { [string]: { Offset: Vector2, Size: Vector2, Center: Rect } },
	-- Thief Moon
	LootBag = id("116158582804459"), -- 512x512
	ThiefMoonTitle = id("129401343322650"), -- 1024x384, "THIEF MOON" baked in
	CaseReward = id("96356444223481"), -- 256x256
	-- HUD icons (256x256)
	Speed = id("74716351276486"), -- shoe only; pickup markers never show a shop +
	Cash = id("95697938789361"),
	Heat = id("72238436704158"),
	MurdererChance = id("135933930646875"),
	FreeChest = id("112476591476500"),
	Trophy = id("72464740035009"),
}
