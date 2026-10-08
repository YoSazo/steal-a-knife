--!strict
-- Everything sold for Robux. Create each one on the Creator Dashboard (Monetization > Passes /
-- Developer Products) with the same name, price and description, then paste its id here. Until an
-- id is filled in, Studio fakes the purchase so it can be tested (MonetizationService).
--
-- Rules we stick to (young audience, Roblox policy): nothing that wins a round for you, the odds of
-- every Robux case are shown, no fake timers or fake scarcity, offers only where they fix the thing
-- you just ran into, and never mid-round.

export type Pass = {
	Key: string,
	Id: number,
	Price: number, -- display only; the real price is whatever the dashboard says
	Name: string,
	Description: string,
	Icon: string,
	Color: Color3,
}

export type Product = {
	Key: string,
	Id: number,
	Price: number,
	Name: string,
	Description: string,
	Icon: string,
	Color: Color3,
	Cash: { Min: number, Seconds: number }?, -- seconds of the buyer's income, at least Min
	Speed: { Share: number, Min: number }?, -- Speed: this share of the buyer's Speed, at least Min
	Coffin: string?, -- a coffin of this rarity (CoffinService.GiveRarity)
	Spins: number?, -- Lucky Wheel spins
	Luck: number?, -- seconds of 2x luck (potion)
	Hidden: boolean?, -- not listed in the Store grid
	Tickets: number?,
	OneTime: boolean?,
	Boost: { Name: string, Seconds: number }?, -- a timed boost (profile.Boosts): Speed, Cash, Training
	Charge: { Name: string, Count: number }?, -- charges (profile.Charges): Escape, Insurance
}

local Monetization = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Monetization.Passes = {
	{
		Key = "DoubleCash",
		Id = 2006121392,
		Price = 399,
		Name = "2x Cash",
		Description = "2x money, forever.",
		Icon = "💰",
		Color = rgb(70, 200, 90),
	},
	{
		Key = "VIP",
		Id = 2005917480,
		Price = 199,
		Name = "VIP",
		Description = "+10% money and a gold VIP tag, forever.",
		Icon = "👑",
		Color = rgb(255, 196, 40),
	},
	{
		Key = "FastWheel",
		Id = 2005863459,
		Price = 299,
		Name = "2x Speed Training",
		Description = "Your wheel makes you faster 2x quicker. Reach the deep bosses sooner.",
		Icon = "🎡",
		Color = rgb(70, 160, 255),
	},
	{
		Key = "PhantomTrail",
		Id = 2006913350,
		Price = 349,
		Name = "Phantom Trail",
		Description = "Glowing knives follow you, and your wheel makes you faster 10x quicker.",
		Icon = "👻",
		Color = rgb(170, 70, 255),
	},
	{
		Key = "AutoCollect",
		Id = 2005113417,
		Price = 199,
		Name = "Auto Collect",
		Description = "Your money comes to you without walking to it, forever.",
		Icon = "🧲",
		Color = rgb(60, 200, 120),
	},
	{
		Key = "Luck",
		Id = 2005341434,
		Price = 299,
		Name = "2x Luck",
		Description = "Better knives in every coffin you get, forever.",
		Icon = "🍀",
		Color = rgb(80, 220, 90),
	},
	{
		Key = "OfflinePlus",
		Id = 2005983403,
		Price = 149,
		Name = "Offline Earnings+",
		Description = "Make full money while you're away (up to 24 hours).",
		Icon = "🌙",
		Color = rgb(110, 120, 255),
	},
	{
		Key = "ExtraFloor",
		Id = 2005371425,
		Price = 249,
		Name = "Vault Floor",
		Description = "+10 room in your vault, right now.",
		Icon = "🏢",
		Color = rgb(255, 170, 60),
	},
} :: { Pass }

-- Passes we no longer sell (id -> price): an owner gets their Robux back as cash, once
-- (MonetizationService.checkPasses, Bought "RetiredPass:<id>")
Monetization.RetiredPasses = {
	[2004975371] = 299, -- Titan Health (health levels were cut)
} :: { [number]: number }

Monetization.Products = {
	{
		Key = "Starter",
		Id = 3716624495,
		Price = 79,
		Name = "Starter Pack",
		Description = "A head start: a pile of cash and a Legendary Coffin. Once per player.",
		Icon = "🎁",
		Color = rgb(255, 130, 60),
		Cash = { Min = 225000, Seconds = 300 },
		Coffin = "Legendary",
		OneTime = true,
	},
	{
		Key = "CashSmall",
		Id = 3716624498,
		Price = 29,
		Name = "Pile of Cash",
		Description = "10 minutes of your vault's income, right now.",
		Icon = "💵",
		Color = rgb(90, 200, 100),
		Cash = { Min = 110000, Seconds = 600 },
	},
	{
		Key = "CashMedium",
		Id = 3716624500,
		Price = 99,
		Name = "Bag of Cash",
		Description = "An hour of your vault's income, right now.",
		Icon = "💰",
		Color = rgb(70, 190, 90),
		Cash = { Min = 750000, Seconds = 3600 },
	},
	{
		Key = "CashBig",
		Id = 3716624502,
		Price = 299,
		Name = "Vault of Cash",
		Description = "Four hours of your vault's income, right now.",
		Icon = "🏦",
		Color = rgb(50, 170, 80),
		Cash = { Min = 4500000, Seconds = 14400 },
	},
	-- Speed packs (Steal An Egg's "+150K Speed" ... "+1B Speed"), scaled to the buyer's Speed like the
	-- cash packs are to income, so they're worth the same to everyone
	{
		Key = "SpeedSmall",
		Id = 3716826960,
		Price = 29,
		Name = "Speed Pack",
		Description = "+25% Speed, right now.",
		Icon = "👟",
		Color = rgb(80, 190, 255),
		Speed = { Share = 0.25, Min = 2000 },
	},
	{
		Key = "SpeedMedium",
		Id = 3716826962,
		Price = 99,
		Name = "Big Speed Pack",
		Description = "2x your Speed, right now.",
		Icon = "👟",
		Color = rgb(60, 160, 255),
		Speed = { Share = 1, Min = 15000 },
	},
	{
		Key = "SpeedBig",
		Id = 3716826967,
		Price = 299,
		Name = "Huge Speed Pack",
		Description = "5x your Speed, right now.",
		Icon = "👟",
		Color = rgb(40, 120, 255),
		Speed = { Share = 4, Min = 120000 },
	},
	-- Lucky Blocks (Steal a Brainrot style): wide odds, every knife's chance shown in the Store
	-- Lucky Wheel spins and luck potions
	{
		Key = "Spins3",
		Id = 3716624520,
		Price = 49,
		Name = "3 Wheel Spins",
		Description = "Three spins of the Lucky Wheel.",
		Icon = "🎡",
		Color = rgb(255, 120, 200),
		Spins = 3,
	},
	{
		Key = "Spins10",
		Id = 3716624522,
		Price = 129,
		Name = "10 Wheel Spins",
		Description = "Ten spins of the Lucky Wheel.",
		Icon = "🎡",
		Color = rgb(255, 80, 170),
		Spins = 10,
	},
	{
		Key = "LuckPotion",
		Id = 3716624527,
		Price = 39,
		Name = "Luck Potion (15 min)",
		Description = "Better knives from cases, Lucky Blocks and the wheel for 15 minutes.",
		Icon = "🧪",
		Color = rgb(80, 220, 90),
		Luck = 900,
	},
	{
		Key = "LuckPotionBig",
		Id = 3716624530,
		Price = 119,
		Name = "Luck Potion (1 hour)",
		Description = "Better knives from cases, Lucky Blocks and the wheel for a whole hour.",
		Icon = "🧪",
		Color = rgb(40, 190, 70),
		Luck = 3600,
	},
	-- Gifts (bought from the gift picker for another player in the server)
	-- Consumables: each fixes a friction you run into every session (GameConfig.Consumables)
	{
		Key = "SpeedPotion",
		Id = 3716624543,
		Price = 29,
		Name = "Speed Potion (10 min)",
		Description = "Run faster for 10 minutes: outrun a deeper boss!",
		Icon = "⚡",
		Color = rgb(255, 210, 40),
		Boost = { Name = "Speed", Seconds = 600 },
	},
	{
		Key = "SpeedPotionBig",
		Id = 3716624546,
		Price = 99,
		Name = "Speed Potion (1 hour)",
		Description = "Run faster for a whole hour.",
		Icon = "⚡",
		Color = rgb(255, 170, 20),
		Boost = { Name = "Speed", Seconds = 3600 },
	},
	{
		Key = "CashPotion",
		Id = 3716624548,
		Price = 49,
		Name = "2x Cash Potion (15 min)",
		Description = "Your vault earns double for 15 minutes. Stacks with everything else.",
		Icon = "💵",
		Color = rgb(70, 200, 80),
		Boost = { Name = "Cash", Seconds = 900 },
	},
	{
		Key = "CashPotionBig",
		Id = 3716624549,
		Price = 149,
		Name = "2x Cash Potion (1 hour)",
		Description = "Your vault earns double for a whole hour.",
		Icon = "💵",
		Color = rgb(40, 170, 60),
		Boost = { Name = "Cash", Seconds = 3600 },
	},
	{
		Key = "TrainingPotion",
		Id = 3716624552,
		Price = 39,
		Name = "Training Potion (15 min)",
		Description = "Your wheel makes you faster 3x quicker, for 15 minutes.",
		Icon = "🎡",
		Color = rgb(90, 160, 255),
		Boost = { Name = "Training", Seconds = 900 },
	},
	{
		-- (Id 0 until created: Studio fakes it; analytics/ npm run setup creates it on Roblox)
		Key = "CoffinOpen",
		Id = 3717127486,
		Price = 19,
		Name = "Open Coffin Now",
		Description = "Open a coffin right now - no waiting.",
		Icon = "⚰️",
		Color = rgb(150, 90, 230),
	},
	{
		Key = "CollectSession",
		Id = 3716624561,
		Price = 25,
		Name = "Auto Collect (this visit)",
		Description = "Your money comes to you without walking to it - until you leave.",
		Icon = "🧲",
		Color = rgb(60, 200, 120),
	},
	{
		Key = "Escape3",
		Id = 3716624564,
		Price = 49,
		Name = "3 Escape Tokens",
		Description = "When a boss catches you, you get away WITH the knife.",
		Icon = "🗝️",
		Color = rgb(170, 110, 255),
		Charge = { Name = "Escape", Count = 3 },
	},
	{
		Key = "Escape10",
		Id = 3716624565,
		Price = 129,
		Name = "10 Escape Tokens",
		Description = "Ten boss escapes.",
		Icon = "🗝️",
		Color = rgb(140, 80, 235),
		Charge = { Name = "Escape", Count = 10 },
	},
	{
		Key = "Insurance3",
		Id = 3716624566,
		Price = 39,
		Name = "Knife Insurance x3",
		Description = "The Murderer can't take your knife, for 3 rounds.",
		Icon = "🛡️",
		Color = rgb(60, 170, 255),
		Charge = { Name = "Insurance", Count = 3 },
	},
	{
		Key = "Insurance10",
		Id = 3716624568,
		Price = 99,
		Name = "Knife Insurance x10",
		Description = "The Murderer can't take your knife, for 10 rounds.",
		Icon = "🛡️",
		Color = rgb(30, 130, 230),
		Charge = { Name = "Insurance", Count = 10 },
	},
	{
		Key = "BossRestock",
		Id = 3716624574,
		Price = 35,
		Name = "Restock the Boss",
		Description = "The nearest boss gets new knives right now.",
		Icon = "🔄",
		Color = rgb(255, 120, 80),
	},
	{
		Key = "OfflineDouble",
		Id = 3716624577,
		Price = 29,
		Name = "Double Offline Earnings",
		Description = "Get your away money again.",
		Icon = "💤",
		Color = rgb(120, 200, 255),
		Hidden = true,
	},
	{
		Key = "StreakSave",
		Id = 3716624582,
		Price = 19,
		Name = "Save My Streak",
		Description = "Missed a day? Keep your daily streak going.",
		Icon = "📅",
		Color = rgb(255, 190, 60),
		Hidden = true,
	},
	{
		Key = "Mount",
		Id = 3716624587,
		Price = 149,
		Name = "Next Floor",
		Description = "Your vault grows a floor: 10 more knife plates, instantly.",
		Icon = "➕",
		Color = rgb(255, 165, 50),
	},
	{
		Key = "ServerLuck",
		Id = 3716624588,
		Price = 249,
		Name = "2x Server Luck",
		Description = "Double mutation and size luck on every case opened in this server for 15 minutes. Everyone gets it, and everyone sees who bought it. Buying again adds time.",
		Icon = "🍀",
		Color = rgb(80, 220, 120),
	},
	{
		Key = "DoublePrize",
		Id = 3716821469,
		Price = 25,
		Name = "Double Your Round Prize",
		Description = "Win the next murder round and get double the prize - double the cash, Speed, knives, spins or boost.",
		Icon = "🎁",
		Color = rgb(255, 200, 60),
		Charge = { Name = "DoublePrize", Count = 1 },
	},
	{
		-- The Robux button on the "Upgrade Wheel" sign (Steal An Egg's treadmill sign: cash or R$)
		Key = "SpeedUpgrade",
		Id = 3716826969,
		Price = 49,
		Name = "Upgrade Wheel",
		Description = "Your Haunted Wheel's next speed upgrade, right now: you train Speed faster.",
		Icon = "⚡",
		Color = rgb(80, 200, 255),
	},
} :: { Product }

-- Paid random items (Roblox policy): a coffin bought with Robux (the Starter Pack's). Refused for
-- players where PolicyService says paid random items are restricted (attribute
-- PaidRandomRestricted): they get its cash value instead.
-- What a speed pack gives a player with this much Speed (client shows it, server grants it)
function Monetization.SpeedFor(product: Product, speed: number): number
	local pack = product.Speed
	if not pack then
		return 0
	end
	return math.floor(math.max(speed * pack.Share, pack.Min))
end

function Monetization.IsPaidRandom(product: Product): boolean
	return product.Coffin ~= nil
end

-- Products that are no longer sold (their systems were cut), by product id -> Robux price. A receipt
-- for one that arrives late (bought just before an update, or retried by Roblox) still pays: cash
-- worth the Robux (MonetizationService.processReceipt), never a "never granted" purchase.
Monetization.Retired = {
	[3716624556] = 49, -- 3 Reroll Tokens (knife power rerolls)
	[3716624560] = 129, -- 10 Reroll Tokens
	[3716624504] = 49, -- Epic Case (cases)
	[3716624507] = 149, -- Legendary Case (cases)
	[3716624511] = 449, -- Godly Case (cases)
	[3716624512] = 175, -- Mythic Lucky Block (lucky blocks)
	[3716624517] = 399, -- Godly Lucky Block (lucky blocks)
	[3716624519] = 1499, -- Cosmic Lucky Block (lucky blocks)
	[3716624534] = 175, -- Gift: Mythic Lucky Block (gifts to a player)
	[3716624539] = 399, -- Gift: Godly Lucky Block (gifts to a player)
	[3716624540] = 129, -- Gift: 10 Wheel Spins (gifts to a player)
	[3716624541] = 39, -- Gift: Luck Potion (gifts to a player)
	[3716624592] = 25, -- Refill Free Chest (the free chest)
	[3716624594] = 99, -- Summon the Blood Moon (raids)
	[3716624573] = 25, -- Full Heat (Heat)
	[3716624585] = 49, -- +3 Health Levels (health levels)
} :: { [number]: number }

Monetization.PassByKey = {} :: { [string]: Pass }
Monetization.ProductByKey = {} :: { [string]: Product }
for _, pass in Monetization.Passes do
	Monetization.PassByKey[pass.Key] = pass
end
for _, product in Monetization.Products do
	Monetization.ProductByKey[product.Key] = product
end

-- Contextual offers: at most one every OfferGap seconds, the same one at most every
-- SameOfferGap, none in a player's first FirstOfferAfter seconds, and never during a round
Monetization.ServerLuck = { Multiplier = 2, Minutes = 15 }

Monetization.OfferGap = 180
Monetization.SameOfferGap = 900
Monetization.FirstOfferAfter = 150

return Monetization
