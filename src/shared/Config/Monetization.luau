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
	Case: string?, -- a sealed case of this rarity
	LuckyBlock: string?, -- a Lucky Block of this tier (Items.LuckyBlocks)
	Spins: number?, -- Lucky Wheel spins
	Luck: number?, -- seconds of 2x luck (potion)
	Gift: string?, -- a gift: grants the product with this key to the chosen player (Gamble.GiftTarget)
	Hidden: boolean?, -- not listed in the Store grid (gifts are bought from the gift picker)
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
		Description = "Your vault earns double cash, forever (rounds and offline earnings too).",
		Icon = "💰",
		Color = rgb(70, 200, 90),
	},
	{
		Key = "VIP",
		Id = 2005917480,
		Price = 199,
		Name = "VIP",
		Description = "+10% income, a gold VIP tag over your head and in chat, and the free chest twice as often.",
		Icon = "👑",
		Color = rgb(255, 196, 40),
	},
	{
		Key = "FastWheel",
		Id = 2005863459,
		Price = 299,
		Name = "2x Speed Training",
		Description = "Your Haunted Wheel trains Speed twice as fast. Reach the deep zones sooner.",
		Icon = "🎡",
		Color = rgb(70, 160, 255),
	},
	{
		Key = "PhantomTrail",
		Id = 2006913350,
		Price = 349,
		Name = "Phantom Trail",
		Description = "A stream of glowing Void Edges follows you, and your wheel trains Speed x10.",
		Icon = "👻",
		Color = rgb(170, 70, 255),
	},
	{
		Key = "AutoCollect",
		Id = 2005113417,
		Price = 199,
		Name = "Auto Collect",
		Description = "Your cash pads empty themselves into your cash. Never walk the vault again.",
		Icon = "🧲",
		Color = rgb(60, 200, 120),
	},
	{
		Key = "Luck",
		Id = 2005341434,
		Price = 299,
		Name = "2x Luck",
		Description = "Double luck on every case, Lucky Block and wheel case, forever. Stacks with potions.",
		Icon = "🍀",
		Color = rgb(80, 220, 90),
	},
	{
		Key = "OfflinePlus",
		Id = 2005983403,
		Price = 149,
		Name = "Offline Earnings+",
		Description = "Earn your full income while you're away (not half), for up to 24 hours.",
		Icon = "🌙",
		Color = rgb(110, 120, 255),
	},
	{
		Key = "ExtraFloor",
		Id = 2005371425,
		Price = 249,
		Name = "Vault Floor",
		Description = "An extra vault floor (10 more plates) the moment you buy it.",
		Icon = "🏢",
		Color = rgb(255, 170, 60),
	},
	{
		Key = "Titan",
		Id = 2004975371,
		Price = 299,
		Name = "Titan Health",
		Description = "Double max health in the hub, forever. Bosses and vault owners need twice the hits.",
		Icon = "❤️",
		Color = rgb(235, 60, 80),
	},
} :: { Pass }

Monetization.Products = {
	{
		Key = "Starter",
		Id = 3716624495,
		Price = 79,
		Name = "Starter Pack",
		Description = "A head start: a pile of cash and a Rare Case. Once per player.",
		Icon = "🎁",
		Color = rgb(255, 130, 60),
		Cash = { Min = 225000, Seconds = 300 },
		Case = "Rare",
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
		Id = 0,
		Price = 29,
		Name = "Speed Pack",
		Description = "A quarter more Speed, right now.",
		Icon = "👟",
		Color = rgb(80, 190, 255),
		Speed = { Share = 0.25, Min = 2000 },
	},
	{
		Key = "SpeedMedium",
		Id = 0,
		Price = 99,
		Name = "Big Speed Pack",
		Description = "Double your Speed, right now.",
		Icon = "👟",
		Color = rgb(60, 160, 255),
		Speed = { Share = 1, Min = 15000 },
	},
	{
		Key = "SpeedBig",
		Id = 0,
		Price = 299,
		Name = "Huge Speed Pack",
		Description = "Five times your Speed, right now.",
		Icon = "👟",
		Color = rgb(40, 120, 255),
		Speed = { Share = 4, Min = 120000 },
	},
	{
		Key = "CaseEpic",
		Id = 3716624504,
		Price = 49,
		Name = "Epic Case",
		Description = "Opens on the spot. Odds are shown in the Store.",
		Icon = "📦",
		Color = rgb(180, 90, 255),
		Case = "Epic",
	},
	{
		Key = "CaseLegendary",
		Id = 3716624507,
		Price = 149,
		Name = "Legendary Case",
		Description = "Opens on the spot. Odds are shown in the Store.",
		Icon = "📦",
		Color = rgb(255, 190, 40),
		Case = "Legendary",
	},
	{
		Key = "CaseGodly",
		Id = 3716624511,
		Price = 449,
		Name = "Godly Case",
		Description = "Opens on the spot. Odds are shown in the Store.",
		Icon = "📦",
		Color = rgb(255, 80, 120),
		Case = "Godly",
	},
	-- Lucky Blocks (Steal a Brainrot style): wide odds, every knife's chance shown in the Store
	{
		Key = "LuckyMythic",
		Id = 3716624512,
		Price = 175,
		Name = "Mythic Lucky Block",
		Description = "Legendary to Celestial. Every knife's odds are on the block.",
		Icon = "🎁",
		Color = rgb(235, 60, 60),
		LuckyBlock = "Mythic",
	},
	{
		Key = "LuckyGodly",
		Id = 3716624517,
		Price = 399,
		Name = "Godly Lucky Block",
		Description = "Mythic to Cosmic. Every knife's odds are on the block.",
		Icon = "🎁",
		Color = rgb(70, 110, 255),
		LuckyBlock = "Godly",
	},
	{
		Key = "LuckyCosmic",
		Id = 3716624519,
		Price = 1499,
		Name = "Cosmic Lucky Block",
		Description = "Godly to Cosmic. Every knife's odds are on the block.",
		Icon = "🎁",
		Color = rgb(40, 36, 60),
		LuckyBlock = "Cosmic",
	},
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
		Description = "2x luck on cases, Lucky Blocks and the wheel for 15 minutes. Stacks up time.",
		Icon = "🧪",
		Color = rgb(80, 220, 90),
		Luck = 900,
	},
	{
		Key = "LuckPotionBig",
		Id = 3716624530,
		Price = 119,
		Name = "Luck Potion (1 hour)",
		Description = "2x luck on cases, Lucky Blocks and the wheel for a whole hour.",
		Icon = "🧪",
		Color = rgb(40, 190, 70),
		Luck = 3600,
	},
	-- Gifts (bought from the gift picker for another player in the server)
	{
		Key = "GiftLuckyMythic",
		Id = 3716624534,
		Price = 175,
		Name = "Gift: Mythic Lucky Block",
		Description = "A Mythic Lucky Block for a friend.",
		Icon = "🎁",
		Color = rgb(235, 60, 60),
		Gift = "LuckyMythic",
		Hidden = true,
	},
	{
		Key = "GiftLuckyGodly",
		Id = 3716624539,
		Price = 399,
		Name = "Gift: Godly Lucky Block",
		Description = "A Godly Lucky Block for a friend.",
		Icon = "🎁",
		Color = rgb(70, 110, 255),
		Gift = "LuckyGodly",
		Hidden = true,
	},
	{
		Key = "GiftSpins10",
		Id = 3716624540,
		Price = 129,
		Name = "Gift: 10 Wheel Spins",
		Description = "Ten Lucky Wheel spins for a friend.",
		Icon = "🎁",
		Color = rgb(255, 80, 170),
		Gift = "Spins10",
		Hidden = true,
	},
	{
		Key = "GiftLuckPotion",
		Id = 3716624541,
		Price = 39,
		Name = "Gift: Luck Potion",
		Description = "15 minutes of 2x luck for a friend.",
		Icon = "🎁",
		Color = rgb(80, 220, 90),
		Gift = "LuckPotion",
		Hidden = true,
	},
	-- Consumables: each fixes a friction you run into every session (GameConfig.Consumables)
	{
		Key = "SpeedPotion",
		Id = 3716624543,
		Price = 29,
		Name = "Speed Potion (10 min)",
		Description = "Run 25% faster in the hub for 10 minutes. Outrun bosses a zone deeper! Stacks up time.",
		Icon = "⚡",
		Color = rgb(255, 210, 40),
		Boost = { Name = "Speed", Seconds = 600 },
	},
	{
		Key = "SpeedPotionBig",
		Id = 3716624546,
		Price = 99,
		Name = "Speed Potion (1 hour)",
		Description = "Run 25% faster in the hub for a whole hour.",
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
		Description = "3x Speed from your Haunted Wheel for 15 minutes.",
		Icon = "🎡",
		Color = rgb(90, 160, 255),
		Boost = { Name = "Training", Seconds = 900 },
	},
	{
		Key = "Reroll3",
		Id = 3716624556,
		Price = 49,
		Name = "3 Reroll Tokens",
		Description = "The Enchanter re-rolls the power on the knife you fight with - one token each, no cash.",
		Icon = "🔮",
		Color = rgb(170, 90, 255),
		Charge = { Name = "Reroll", Count = 3 },
	},
	{
		Key = "Reroll10",
		Id = 3716624560,
		Price = 129,
		Name = "10 Reroll Tokens",
		Description = "Ten re-rolls at the Enchanter. Chase that Mythic power!",
		Icon = "🔮",
		Color = rgb(130, 60, 230),
		Charge = { Name = "Reroll", Count = 10 },
	},
	{
		Key = "CollectSession",
		Id = 3716624561,
		Price = 25,
		Name = "Auto Collect (this visit)",
		Description = "Every cash pad pays straight into your cash, wherever you are - until you leave. (The Auto Collect pass keeps it forever.)",
		Icon = "🧲",
		Color = rgb(60, 200, 120),
	},
	{
		Key = "Escape3",
		Id = 3716624564,
		Price = 49,
		Name = "3 Escape Tokens",
		Description = "When a boss catches you, a token breaks you free WITH the knife (and stuns the boss).",
		Icon = "🗝️",
		Color = rgb(170, 110, 255),
		Charge = { Name = "Escape", Count = 3 },
	},
	{
		Key = "Escape10",
		Id = 3716624565,
		Price = 129,
		Name = "10 Escape Tokens",
		Description = "Ten boss escapes. Never lose a steal at the last second again.",
		Icon = "🗝️",
		Color = rgb(140, 80, 235),
		Charge = { Name = "Escape", Count = 10 },
	},
	{
		Key = "Insurance3",
		Id = 3716624566,
		Price = 39,
		Name = "Knife Insurance x3",
		Description = "If the Murderer gets you, they can't loot your knife. Three rounds of protection.",
		Icon = "🛡️",
		Color = rgb(60, 170, 255),
		Charge = { Name = "Insurance", Count = 3 },
	},
	{
		Key = "Insurance10",
		Id = 3716624568,
		Price = 99,
		Name = "Knife Insurance x10",
		Description = "Ten rounds where the Murderer can't take your knife.",
		Icon = "🛡️",
		Color = rgb(30, 130, 230),
		Charge = { Name = "Insurance", Count = 10 },
	},
	{
		Key = "HeatRefill",
		Id = 3716624573,
		Price = 25,
		Name = "Full Heat",
		Description = "Your 🔥 Heat jumps to max: more vault income and better power luck.",
		Icon = "🔥",
		Color = rgb(255, 110, 40),
	},
	{
		Key = "BossRestock",
		Id = 3716624574,
		Price = 35,
		Name = "Restock the Boss",
		Description = "The nearest boss's empty wall fills up with new knives right now. Everyone sees who did it.",
		Icon = "🔄",
		Color = rgb(255, 120, 80),
	},
	{
		Key = "OfflineDouble",
		Id = 3716624577,
		Price = 29,
		Name = "Double Offline Earnings",
		Description = "Get what your vault earned while you were away, again.",
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
		Key = "HealthBoost",
		Id = 3716624585,
		Price = 49,
		Name = "+3 Health Levels",
		Description = "Three Health upgrades right now (+75 max health).",
		Icon = "💗",
		Color = rgb(255, 90, 120),
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
		Key = "ChestRefill",
		Id = 3716624592,
		Price = 25,
		Name = "Refill Free Chest",
		Description = "Your plaza chest is ready to open again, right now.",
		Icon = "🎁",
		Color = rgb(255, 200, 70),
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
		Id = 0,
		Price = 49,
		Name = "Upgrade Wheel",
		Description = "Your Haunted Wheel's next speed upgrade, right now: you train Speed faster.",
		Icon = "⚡",
		Color = rgb(80, 200, 255),
	},
	{
		Key = "BloodMoon",
		Id = 3716624594,
		Price = 99,
		Name = "Summon the Blood Moon",
		Description = "Raise the Blood Moon for the whole server: the biomes close and everyone can steal from each other's vaults. Everyone sees who did it.",
		Icon = "🌕",
		Color = rgb(200, 40, 50),
	},
} :: { Product }

-- Paid random items (Roblox policy): Robux cases and Lucky Blocks. Hidden and refused for players
-- where PolicyService says paid random items are restricted (player attribute PaidRandomRestricted).
-- What a speed pack gives a player with this much Speed (client shows it, server grants it)
function Monetization.SpeedFor(product: Product, speed: number): number
	local pack = product.Speed
	if not pack then
		return 0
	end
	return math.floor(math.max(speed * pack.Share, pack.Min))
end

function Monetization.IsPaidRandom(product: Product): boolean
	if product.Gift then
		local inner = Monetization.ProductByKey[product.Gift]
		return inner ~= nil and Monetization.IsPaidRandom(inner)
	end
	return product.Case ~= nil or product.LuckyBlock ~= nil
end

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
