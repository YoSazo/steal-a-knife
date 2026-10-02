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
	Case: string?, -- a sealed case of this rarity
	Tickets: number?,
	OneTime: boolean?,
}

local Monetization = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Monetization.Passes = {
	{
		Key = "DoubleCash",
		Id = 0,
		Price = 399,
		Name = "2x Cash",
		Description = "Your vault earns double cash, forever (rounds and offline earnings too).",
		Icon = "💰",
		Color = rgb(70, 200, 90),
	},
	{
		Key = "VIP",
		Id = 0,
		Price = 199,
		Name = "VIP",
		Description = "+10% income, a gold VIP tag over your head and in chat, and the free chest twice as often.",
		Icon = "👑",
		Color = rgb(255, 196, 40),
	},
	{
		Key = "FastWheel",
		Id = 0,
		Price = 299,
		Name = "2x Speed Training",
		Description = "Your Haunted Wheel trains Speed twice as fast. Reach the deep zones sooner.",
		Icon = "🎡",
		Color = rgb(70, 160, 255),
	},
	{
		Key = "PhantomTrail",
		Id = 0,
		Price = 349,
		Name = "Phantom Trail",
		Description = "A stream of glowing Void Edges follows you, and your wheel trains Speed x10.",
		Icon = "👻",
		Color = rgb(170, 70, 255),
	},
	{
		Key = "Fortified",
		Id = 0,
		Price = 299,
		Name = "Fortified Vault",
		Description = "Every wall tier's gate has +50% health. Thieves need much longer to get in.",
		Icon = "🏰",
		Color = rgb(150, 110, 80),
	},
	{
		Key = "Titan",
		Id = 0,
		Price = 299,
		Name = "Titan Health",
		Description = "Double max health in the hub, forever. Bosses and vault owners need twice the hits.",
		Icon = "❤️",
		Color = rgb(235, 60, 80),
	},
	{
		Key = "MurdererLuck",
		Id = 0,
		Price = 199,
		Name = "Murderer Luck",
		Description = "Twice the chance to be picked as the Murderer each round.",
		Icon = "🔪",
		Color = rgb(225, 50, 70),
	},
} :: { Pass }

Monetization.Products = {
	{
		Key = "Starter",
		Id = 0,
		Price = 79,
		Name = "Starter Pack",
		Description = "A head start: a pile of cash, a Rare Case and 3 Murderer Tickets. Once per player.",
		Icon = "🎁",
		Color = rgb(255, 130, 60),
		Cash = { Min = 225000, Seconds = 300 },
		Case = "Rare",
		Tickets = 3,
		OneTime = true,
	},
	{
		Key = "CashSmall",
		Id = 0,
		Price = 29,
		Name = "Pile of Cash",
		Description = "10 minutes of your vault's income, right now.",
		Icon = "💵",
		Color = rgb(90, 200, 100),
		Cash = { Min = 110000, Seconds = 600 },
	},
	{
		Key = "CashMedium",
		Id = 0,
		Price = 99,
		Name = "Bag of Cash",
		Description = "An hour of your vault's income, right now.",
		Icon = "💰",
		Color = rgb(70, 190, 90),
		Cash = { Min = 750000, Seconds = 3600 },
	},
	{
		Key = "CashBig",
		Id = 0,
		Price = 299,
		Name = "Vault of Cash",
		Description = "Four hours of your vault's income, right now.",
		Icon = "🏦",
		Color = rgb(50, 170, 80),
		Cash = { Min = 4500000, Seconds = 14400 },
	},
	{
		Key = "CaseEpic",
		Id = 0,
		Price = 49,
		Name = "Epic Case",
		Description = "Opens on the spot. Odds are shown in the Store.",
		Icon = "📦",
		Color = rgb(180, 90, 255),
		Case = "Epic",
	},
	{
		Key = "CaseLegendary",
		Id = 0,
		Price = 149,
		Name = "Legendary Case",
		Description = "Opens on the spot. Odds are shown in the Store.",
		Icon = "📦",
		Color = rgb(255, 190, 40),
		Case = "Legendary",
	},
	{
		Key = "CaseGodly",
		Id = 0,
		Price = 449,
		Name = "Godly Case",
		Description = "Opens on the spot. Odds are shown in the Store.",
		Icon = "📦",
		Color = rgb(255, 80, 120),
		Case = "Godly",
	},
	{
		Key = "HealthBoost",
		Id = 0,
		Price = 49,
		Name = "+3 Health Levels",
		Description = "Three Health upgrades right now (+75 max health).",
		Icon = "💗",
		Color = rgb(255, 90, 120),
	},
	{
		Key = "Mount",
		Id = 0,
		Price = 149,
		Name = "Next Floor",
		Description = "Your vault grows a floor: 10 more knife plates, instantly.",
		Icon = "➕",
		Color = rgb(255, 165, 50),
	},
	{
		Key = "Tickets",
		Id = 0,
		Price = 39,
		Name = "3 Murderer Tickets",
		Description = "Each one adds to your chance of being the Murderer in a round.",
		Icon = "🎟️",
		Color = rgb(225, 60, 80),
		Tickets = 3,
	},
	{
		Key = "Repair",
		Id = 0,
		Price = 15,
		Name = "Instant Repair",
		Description = "Your gate back to full health (or rebuilt if it's broken).",
		Icon = "🔧",
		Color = rgb(90, 160, 255),
	},
	{
		Key = "ServerLuck",
		Id = 0,
		Price = 249,
		Name = "2x Server Luck",
		Description = "Double mutation and size luck on every case opened in this server for 15 minutes. Everyone gets it, and everyone sees who bought it. Buying again adds time.",
		Icon = "🍀",
		Color = rgb(80, 220, 120),
	},
	{
		Key = "ChestRefill",
		Id = 0,
		Price = 25,
		Name = "Refill Free Chest",
		Description = "Your plaza chest is ready to open again, right now.",
		Icon = "🎁",
		Color = rgb(255, 200, 70),
	},
	{
		Key = "BloodMoon",
		Id = 0,
		Price = 99,
		Name = "Summon the Thief Moon",
		Description = "Raise the Thief Moon for the whole server: burglars, weak gates and double bounties. Everyone sees who did it.",
		Icon = "🌕",
		Color = rgb(200, 40, 50),
	},
} :: { Product }

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
