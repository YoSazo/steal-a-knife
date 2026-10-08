--!strict
-- Owned knives are "items": a catalog knife plus a mutation and a size (Items.RollKnife). Stored as one string so profiles, attributes and round loot stay simple:
--   "Katana"              plain, normal size (every save from before cases still works)
--   "Katana|Gold|Big"     Gold mutation, Big size ("Katana||Huge" = no mutation, Huge)
--   "Katana|Gold|Big|SpamKnife"  ...carrying a set Murderer power (old rolled saves, the tutorial's
--                         first knife). Without one ("", "?", missing or unknown) a knife has its
--                         knife type's power (Config/Knives Perk).
-- Mutations and sizes multiply income; they also make the knife hit a little harder.

local Knives = require(script.Parent.Config.Knives)

export type Mutation = {
	Id: string,
	DisplayName: string,
	Income: number, -- income multiplier
	Damage: number, -- damage multiplier
	Weight: number, -- roll weight (out of the total)
	Color: Color3,
	Rank: number, -- 0 = none; higher = rarer (announcements, sorting)
}

export type Size = {
	Id: string,
	DisplayName: string,
	Scale: number, -- how big the model is
	Income: number,
	Damage: number,
	Weight: number,
	Rank: number,
}

export type Item = {
	Item: string,
	Name: string,
	Knife: Knives.Knife,
	Mutation: Mutation,
	Size: Size,
	Perk: string?, -- the Murderer power this one carries (GameConfig.Perks id)
}

local Items = {}

Items.Mutations = {
	{
		Id = "",
		DisplayName = "",
		Income = 1,
		Damage = 1,
		Weight = 8000,
		Color = Color3.new(1, 1, 1),
		Rank = 0,
	},
	{
		Id = "Gold",
		DisplayName = "Gold",
		Income = 2,
		Damage = 1.1,
		Weight = 1250,
		Color = Color3.fromRGB(255, 200, 40),
		Rank = 1,
	},
	{
		Id = "Diamond",
		DisplayName = "Diamond",
		Income = 3,
		Damage = 1.2,
		Weight = 500,
		Color = Color3.fromRGB(120, 230, 255),
		Rank = 2,
	},
	{
		Id = "Rainbow",
		DisplayName = "Rainbow",
		Income = 5,
		Damage = 1.35,
		Weight = 200,
		Color = Color3.fromRGB(255, 110, 220),
		Rank = 3,
	},
	{
		Id = "Void",
		DisplayName = "Void",
		Income = 10,
		Damage = 1.6,
		Weight = 50,
		Color = Color3.fromRGB(150, 60, 255),
		Rank = 4,
	},
} :: { Mutation }

Items.Sizes = {
	{ Id = "Tiny", DisplayName = "Tiny", Scale = 0.7, Income = 0.75, Damage = 0.9, Weight = 1400, Rank = 0 },
	{ Id = "Small", DisplayName = "Small", Scale = 0.85, Income = 0.9, Damage = 0.95, Weight = 2400, Rank = 0 },
	{ Id = "", DisplayName = "", Scale = 1, Income = 1, Damage = 1, Weight = 4200, Rank = 0 },
	{ Id = "Big", DisplayName = "Big", Scale = 1.2, Income = 1.25, Damage = 1.05, Weight = 1500, Rank = 1 },
	{ Id = "Huge", DisplayName = "Huge", Scale = 1.45, Income = 1.6, Damage = 1.1, Weight = 440, Rank = 2 },
	{
		Id = "Colossal",
		DisplayName = "Colossal",
		Scale = 1.8,
		Income = 2.5,
		Damage = 1.2,
		Weight = 60,
		Rank = 3,
	},
} :: { Size }

-- Knife powers (Config/KnifePowers): every knife carries one
local KnifePowers = require(script.Parent.Config.KnifePowers)

-- What players see for a power id ("Invisiknife" -> "Shadow")
function Items.PowerName(power: string?): string
	local entry = power and KnifePowers.ById[power]
	return if entry then entry.Name else (power or "")
end

local mutationById: { [string]: Mutation } = {}
for _, m in Items.Mutations do
	mutationById[m.Id] = m
end
local sizeById: { [string]: Size } = {}
for _, s in Items.Sizes do
	sizeById[s.Id] = s
end
Items.MutationById = mutationById
Items.SizeById = sizeById

local cache: { [string]: Item } = {}
local invalid: { [string]: boolean } = {}

-- nil when the knife isn't in the catalog (or the string is garbage)
function Items.Parse(item: string): Item?
	local cached = cache[item]
	if cached or invalid[item] then
		return cached
	end
	local fields = string.split(item, "|")
	local name, mutation, size, power = fields[1], fields[2] or "", fields[3] or "", fields[4]
	local knife = Knives.ByName[name]
	local m = mutationById[mutation]
	local s = sizeById[size]
	-- Murderer powers are cut (docs/PLAN.md item 4): every Murderer plays by the same MM2 rules, and
	-- the knife is a flex (looks, rarity, mutation), not an ability. Perk stays in the type so old
	-- 4-field items still parse; it's always nil now, which turns every power branch off.
	local _ = power
	local perk: string? = nil
	if not knife or not m or not s or #fields > 4 then
		invalid[item] = true
		return nil
	end
	local parsed: Item = {
		Item = item,
		Name = name,
		Knife = knife,
		Mutation = m,
		Size = s,
		Perk = perk,
	}
	cache[item] = parsed
	return parsed
end

function Items.Make(name: string, mutation: string?, size: string?, power: string?): string
	local m, s = mutation or "", size or ""
	if power then
		return `{name}|{m}|{s}|{power}`
	end
	if m == "" and s == "" then
		return name
	end
	return `{name}|{m}|{s}`
end

-- The same knife with a set power (the tutorial's first knife: KnifePowers.Starter)
function Items.WithPower(item: string, power: string): string
	local p = Items.Parse(item)
	if not p then
		return item
	end
	return Items.Make(p.Name, p.Mutation.Id, p.Size.Id, power)
end

function Items.Valid(item: unknown): boolean
	return type(item) == "string" and Items.Parse(item) ~= nil
end

function Items.Name(item: string): string
	local parsed = Items.Parse(item)
	return if parsed then parsed.Name else item
end

-- Cash per second on the wall (before rebirth / boosts)
function Items.Income(item: string): number
	local p = Items.Parse(item)
	if not p then
		return 0
	end
	return math.floor(p.Knife.Income * p.Mutation.Income * p.Size.Income * 10 + 0.5) / 10
end

function Items.Damage(item: string): number
	local p = Items.Parse(item)
	if not p then
		return 0
	end
	return math.floor(p.Knife.Damage * p.Mutation.Damage * p.Size.Damage)
end

-- "Gold Huge Sakura Katana"
function Items.DisplayName(item: string): string
	local p = Items.Parse(item)
	if not p then
		return item
	end
	local parts = {}
	if p.Mutation.DisplayName ~= "" then
		table.insert(parts, p.Mutation.DisplayName)
	end
	if p.Size.DisplayName ~= "" then
		table.insert(parts, p.Size.DisplayName)
	end
	table.insert(parts, p.Knife.DisplayName)
	return table.concat(parts, " ")
end

-- How special this one is, for announcements: 0 = everyday, 3+ = the whole server should know
function Items.Hype(item: string): number
	local p = Items.Parse(item)
	if not p then
		return 0
	end
	local rarityRank = (table.find(Knives.Rarities, p.Knife.Rarity) or 1) - 1
	return math.max(rarityRank - 1, p.Mutation.Rank + (if p.Mutation.Rank > 0 then 1 else 0), p.Size.Rank)
end

-- The colour that best describes it: its mutation if it has one, else its rarity
function Items.Color(item: string): Color3
	local p = Items.Parse(item)
	if not p then
		return Color3.new(1, 1, 1)
	end
	return if p.Mutation.Rank > 0 then p.Mutation.Color else Knives.RarityColors[p.Knife.Rarity]
end

-- How strong a mounted knife's aura is: rarity, mutation and size all add up (0 .. ~10). The
-- aura is drawn around it on the wall and slows anyone who isn't the owner within AuraRadius.
function Items.AuraPower(item: string): number
	local p = Items.Parse(item)
	if not p then
		return 0
	end
	local rarity = (table.find(Knives.Rarities, p.Knife.Rarity) or 1) - 1
	return rarity * 1.2 + p.Mutation.Rank * 1.1 + p.Size.Rank * 0.6
end

function Items.AuraRadius(power: number): number
	-- Capped so the best knives still fit their floor of the vault
	return math.min(4 + power * 1.1, 15)
end

local function weighted<T>(rng: Random, list: { T }, weightOf: (T) -> number): T
	local total = 0
	for _, entry in list do
		total += weightOf(entry)
	end
	local roll = rng:NextNumber() * total
	for _, entry in list do
		roll -= weightOf(entry)
		if roll <= 0 then
			return entry
		end
	end
	return list[#list]
end

-- Rolls a mutation and a size. `luck` >= 1 makes everything past "none" / "normal" likelier.
function Items.Roll(rng: Random, luck: number?): (Mutation, Size)
	local boost = math.max(1, luck or 1)
	local mutation = weighted(rng, Items.Mutations, function(m: Mutation)
		return if m.Rank > 0 then m.Weight * boost else m.Weight
	end)
	local size = weighted(rng, Items.Sizes, function(s: Size)
		return if s.Rank > 0 then s.Weight * boost else s.Weight
	end)
	return mutation, size
end

-- A random knife of `rarity` (or, 4% of the time, the next one up), with a mutation and a size:
-- what's inside a coffin, and what a boss keeps on its wall. Returns the item and whether it
-- jumped a rarity.
function Items.RollKnife(rng: Random, rarity: string, luck: number?): (string, boolean)
	local rarityIndex = table.find(Knives.Rarities, rarity) or 1
	local upgraded = rarityIndex < #Knives.Rarities and rng:NextNumber() < 0.04
	if upgraded then
		rarityIndex += 1
	end
	local pool = Knives.ByRarity[Knives.Rarities[rarityIndex]]
	local knife = pool[rng:NextInteger(1, #pool)]
	local mutation, size = Items.Roll(rng, luck)
	return Items.Make(knife.Name, mutation.Id, size.Id), upgraded
end

return Items
