--!strict
-- Loot and carrying. Watchmen drop sealed cases when they die; dropped cases and knives float
-- with a tag and a light beam. Hold the prompt to pick one up and carry it over your head back to
-- your vault (picking up alerts the guards). Cases open when you get home: a reveal rolls the
-- knife inside, its mutation and its size (Items.OpenCase). Knives stolen from other players'
-- vaults in a raid remember who they belong to - if the thief drops one, its owner can grab it
-- straight back onto their wall. If a carrier dies or gets knocked down, what they carried drops.
-- The server checks distance, state and rack space, and decides deposits from where it sees the
-- character.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local Fuel = require(script.Parent.Fuel)
local ServerEvents = require(script.Parent.ServerEvents)
local Social = require(script.Parent.Social)
local MapService = require(script.Parent.MapService)
local Offers = require(script.Parent.Offers)
local Ragdoll = require(script.Parent.Ragdoll)
local Targets = require(script.Parent.Targets)
local Analytics = require(script.Parent.Analytics)

type Carry = {
	Kind: string, -- "Case" | "Knife"
	Item: string, -- the case's rarity, or the knife item
	StolenFrom: number?, -- UserId of the vault it was stolen from
	Boss: { Zone: number, Slot: number }?,
	Helpers: { Player }, -- players who helped with a boss steal (team steal) -- taken off a biome boss's wall (GuardService)
	Visual: Model,
	LastPos: Vector3,
	LastCheck: number,
	Plate: number?, -- the plate the owner chose to put it on (Place)
	Started: number, -- os.clock() it was picked up (analytics)
	Source: string, -- "boss" | "vault" | "ground" | "case" (analytics)
	Zone: number, -- zone it was picked up in, 0 = outside the biomes (analytics)
}

local StealService = {}

-- Set by GuardService: (player, zoneIndex) when someone picks something up in the arena
StealService.OnPickup = nil :: ((Player, number) -> ())?
-- Set by GuardService: a knife taken off a boss's wall left the thief's hands. delivered = it made it
-- home (the slot restocks later); otherwise it goes straight back on the wall.
StealService.OnBossCarryEnded = nil :: ((zone: number, slot: number, item: string, delivered: boolean) -> ())?

local carriers: { [Player]: Carry } = {}
local dropFolder: Folder
local rng = Random.new()

local function rootPart(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function zoneIndexAt(position: Vector3): number?
	for _, zone in MapService.Zones do
		if MapService.InBounds(zone.Bounds, position) then
			return zone.Index
		end
	end
	return nil
end

-- The floating tag over a drop: a few lines of coloured text
local function tag(adornee: BasePart, lines: { { Text: string, Color: Color3, Height: number } })
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 0)
	for _, line in lines do
		gui.Size += UDim2.fromOffset(0, line.Height)
	end
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
	gui.MaxDistance = 120
	gui.AlwaysOnTop = true
	gui.Adornee = adornee
	gui.Parent = adornee
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = gui
	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.LayoutOrder = i
		label.Size = UDim2.new(1, 0, 0, line.Height)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = line.Color
		label.TextStrokeTransparency = 0.2
		label.Text = line.Text
		label.Parent = gui
	end
end

local function ownerName(userId: number?): string?
	if not userId then
		return nil
	end
	local owner = Players:GetPlayerByUserId(userId)
	return if owner then owner.DisplayName else nil
end

local revealPower: (Player, string) -> ()
local startCarry: (Player, string, string, number?, { Zone: number, Slot: number }?, string?, boolean?) -> ()

-- Somewhere on the floor under `position`, ignoring bodies, players and other drops
local function floorAt(position: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { dropFolder }
	local map = dropFolder.Parent
	local guardsFolder = map and map:FindFirstChild("Guards")
	if guardsFolder then
		table.insert(ignore, guardsFolder)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local ground = workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -20, 0), params)
	return if ground then ground.Position.Y else position.Y - 3
end

-- The glow, light pillar and pickup prompt every drop gets
local function dress(model: Model, color: Color3, floorY: number, at: Vector3, objectText: string): ProximityPrompt
	model:AddTag("Spin")
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- spun whole on clients
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.FillTransparency = 0.7
	highlight.OutlineColor = color
	highlight.Parent = model
	-- A light pillar so drops are easy to spot across the arena at night
	local pillar = Instance.new("Part")
	pillar.Name = "Beam"
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.Material = Enum.Material.Neon
	pillar.Color = color
	pillar.Transparency = 0.6
	pillar.Size = Vector3.new(0.6, 30, 0.6)
	pillar.CFrame = CFrame.new(Vector3.new(at.X, floorY + 15, at.Z))
	pillar.Parent = model
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 2
	light.Parent = pillar
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take"
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart
	return prompt
end

-- Common checks before anyone picks something up
local function canPickUp(player: Player, anchor: BasePart, prompt: ProximityPrompt): boolean
	local root = rootPart(player)
	local profile = DataService.Get(player)
	if not root or not profile or player:GetAttribute("InRound") or carriers[player] then
		return false
	end
	if player:GetAttribute("KnockedUntil") then
		return false
	end
	if (root.Position - anchor.Position).Magnitude > prompt.MaxActivationDistance + 6 then
		return false -- fired from too far away: exploit or lag, ignore either way
	end
	if not BaseService.GetBase(player) then
		Net.Notify(player, "No free vault here, sorry!", "bad")
		return false
	end
	if #profile.Knives >= profile.Slots then
		Net.Notify(player, "Your vault is full! Sell a knife first.", "bad")
		Offers.Show(player, "Mount", "Your wall is full! Add another mount instantly.")
		return false
	end
	return true
end

-- Puts a knife item on the floor: glowing, tagged, spinning, and gone after a while.
-- `stolenFrom` marks a knife lifted from someone's vault: its owner can take it straight back.
function StealService.DropKnife(item: string, position: Vector3, stolenFrom: number?)
	local parsed = Items.Parse(item)
	if not parsed then
		return
	end
	local floorY = floorAt(position)
	local at = Vector3.new(position.X, floorY + 2.2, position.Z)
	local model = KnifeModel.Build(item, true)
	KnifeModel.FitItem(model, item, 3.2)
	model:PivotTo(CFrame.new(at) * CFrame.Angles(0, 0, math.rad(20)))
	model.Name = `Dropped_{parsed.Name}`
	local color = Items.Color(item)
	local knife = parsed.Knife
	local anchor = model.PrimaryPart :: BasePart
	local victim = ownerName(stolenFrom)
	local lines = {
		{ Text = Items.DisplayName(item), Color = color, Height = 30 },
		{ Text = knife.Rarity:upper(), Color = Knives.RarityColors[knife.Rarity], Height = 18 },
		{
			Text = `Damage {Items.Damage(item)}  ·  {Format.Cash(Items.Income(item))}/s`,
			Color = Color3.new(1, 1, 1),
			Height = 22,
		},
	}
	if victim then
		table.insert(lines, { Text = `Stolen from {victim}!`, Color = Color3.fromRGB(255, 120, 120), Height = 18 })
	end
	tag(anchor, lines)
	local prompt = dress(model, color, floorY, at, Items.DisplayName(item))
	prompt.Triggered:Connect(function(player)
		if not model.Parent then
			return
		end
		-- The owner takes their own knife straight back
		if stolenFrom and player.UserId == stolenFrom then
			local profile = DataService.Get(player)
			local root = rootPart(player)
			if profile and root and (root.Position - anchor.Position).Magnitude < prompt.MaxActivationDistance + 6 then
				if #profile.Knives < profile.Slots then
					model:Destroy()
					DataService.Update(player, function(p)
						DataService.AddKnife(p, item)
					end)
					BaseService.RefreshRack(player)
					Net.Notify(player, `Got your {Items.DisplayName(item)} back!`, "good")
					Net.Remotes.Effect:FireAllClients("Recovered", root.Position, color)
					return
				end
			end
		end
		if not canPickUp(player, anchor, prompt) then
			return
		end
		model:Destroy()
		startCarry(
			player,
			"Knife",
			item,
			if stolenFrom and player.UserId ~= stolenFrom then stolenFrom else nil,
			nil,
			"ground"
		)
		local zone = zoneIndexAt(at)
		if zone and StealService.OnPickup then
			StealService.OnPickup(player, zone)
		end
	end)
	model.Parent = dropFolder
	task.delay(if stolenFrom then GameConfig.DroppedKnifeLifetime * 2 else GameConfig.DroppedKnifeLifetime, function()
		if model.Parent then
			model:Destroy()
			-- A stolen knife nobody picked up goes home rather than vanishing
			local owner = stolenFrom and Players:GetPlayerByUserId(stolenFrom)
			local profile = owner and DataService.Get(owner)
			if owner and profile and #profile.Knives < profile.Slots then
				DataService.Update(owner, function(p)
					DataService.AddKnife(p, item)
				end)
				BaseService.RefreshRack(owner)
				Net.Notify(owner, `Your {Items.DisplayName(item)} came back home!`, "good")
			end
		end
	end)
end

-- A sealed case on the floor (what watchmen drop)
function StealService.DropCase(rarity: string, position: Vector3)
	local color = Knives.RarityColors[rarity]
	if not color then
		return
	end
	local floorY = floorAt(position)
	local at = Vector3.new(position.X, floorY + 1.8, position.Z)
	local model = KnifeModel.BuildCase(rarity, true)
	model:PivotTo(CFrame.new(at))
	local anchor = model.PrimaryPart :: BasePart
	tag(anchor, {
		{ Text = `{rarity:upper()} CASE`, Color = color, Height = 30 },
		{ Text = "Sealed · open it at your vault", Color = Color3.fromRGB(230, 230, 240), Height = 18 },
		{ Text = "Mutation? Size? Find out!", Color = Color3.fromRGB(255, 220, 120), Height = 16 },
	})
	local prompt = dress(model, color, floorY, at, `{rarity} Case`)
	prompt.Triggered:Connect(function(player)
		if not model.Parent or not canPickUp(player, anchor, prompt) then
			return
		end
		model:Destroy()
		startCarry(player, "Case", rarity, nil, nil, "case")
		local zone = zoneIndexAt(at)
		if zone and StealService.OnPickup then
			StealService.OnPickup(player, zone)
		end
	end)
	model.Parent = dropFolder
	task.delay(GameConfig.DroppedKnifeLifetime, function()
		if model.Parent then
			model:Destroy()
		end
	end)
end

-- Ends a carry. deposited = made it home; otherwise it drops where they are
-- Analytics: what was carried, from where, for how long
local function carryProps(carry: Carry, extra: { [string]: any }?): { [string]: any }
	local parsed = if carry.Kind == "Knife" then Items.Parse(carry.Item) else nil
	local props: { [string]: any } = {
		kind = carry.Kind,
		source = carry.Source,
		zone = carry.Zone,
		knife = if parsed then parsed.Name else nil,
		rarity = if parsed then parsed.Knife.Rarity else carry.Item,
		mutation = if parsed then parsed.Mutation.Id else nil,
		size = if parsed then parsed.Size.Id else nil,
		value = if parsed then Items.Income(carry.Item) else nil,
		helpers = #carry.Helpers,
		seconds = math.floor((os.clock() - carry.Started) * 10) / 10,
	}
	if extra then
		for key, value in extra do
			props[key] = value
		end
	end
	return props
end

-- why (analytics): "home" | "caught" | "died" | "knocked" | "slipped" | "vault_full" | "moon" |
-- "recovered" | "left" | "forced" (the steal.<why> event)
local function endCarry(player: Player, deposited: boolean, dropAt: Vector3?, why: string?)
	local carry = carriers[player]
	if not carry then
		return
	end
	carriers[player] = nil
	local outcome = why or (if deposited then "home" else "dropped")
	Analytics.Track(player, "steal." .. outcome, carryProps(carry))
	if outcome == "home" then
		Analytics.Milestone(player, "knife_home", carryProps(carry))
		if carry.Source == "boss" then
			Analytics.Milestone(player, "boss_steal_home_zone_" .. carry.Zone)
		elseif carry.Source == "vault" then
			Analytics.Milestone(player, "vault_steal_home")
		end
	elseif outcome == "caught" then
		Analytics.Milestone(player, "first_caught")
	end
	player:SetAttribute("PlaceReady", nil)
	local visual = carry.Visual
	local fallback = visual.PrimaryPart and (visual.PrimaryPart :: BasePart).Position
	visual:Destroy()
	player:SetAttribute("Carrying", nil)
	player:SetAttribute("StolenFrom", nil)
	BaseService.RefreshWalkSpeed(player)
	local where = dropAt or fallback
	if carry.Boss then
		-- Boss knives never lie around: they go back on the wall (or count as delivered)
		local hook = StealService.OnBossCarryEnded
		if hook then
			hook(carry.Boss.Zone, carry.Boss.Slot, carry.Item, deposited)
		end
		return
	end
	if not deposited and where then
		if carry.Kind == "Case" then
			StealService.DropCase(carry.Item, where)
		else
			StealService.DropKnife(carry.Item, where, carry.StolenFrom)
		end
	end
end

-- Lifts something over a player's head: kind "Case" (item = rarity) or "Knife" (item string)
startCarry = function(
	player: Player,
	kind: string,
	item: string,
	stolenFrom: number?,
	boss: { Zone: number, Slot: number }?,
	source: string?,
	resumed: boolean?
)
	local character = player.Character :: Model
	local head = character:FindFirstChild("Head") :: BasePart?
	local root = rootPart(player)
	if not head or not root then
		return
	end

	-- Held up like a trophy: lying across both raised hands, centred over the head, so everyone
	-- can see who has what (the arms come from the Carry pose in AnimLibrary)
	local visual: Model
	local above: CFrame
	if kind == "Case" then
		visual = KnifeModel.BuildCase(item, false)
		above = head.CFrame * CFrame.new(0, 1.9, 0)
		visual:PivotTo(above)
	else
		visual = KnifeModel.Build(item, false)
		KnifeModel.FitItem(visual, item, 3.6)
		above = head.CFrame * CFrame.new(0, 1.05, 0) -- resting on the raised hands
		-- Blade along the shoulders (pointing left), edge facing forward
		visual:PivotTo(above * CFrame.Angles(0, 0, math.rad(90)))
	end
	for _, p in visual:GetDescendants() do
		if p:IsA("BasePart") then
			p.Massless = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Anchored = false
		end
	end
	local box = visual:GetBoundingBox()
	local off = above:PointToObjectSpace(box.Position)
	visual:PivotTo(CFrame.new(above:VectorToWorldSpace(Vector3.new(-off.X, 0, -off.Z))) * visual:GetPivot())
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = visual.PrimaryPart :: BasePart
	weld.Parent = visual
	visual.Parent = character

	-- Team steal: anyone close by when you grab a boss's knife (and your teammate, wherever they are)
	local helpers: { Player } = {}
	if boss then
		for _, other in Players:GetPlayers() do
			local otherRoot = if other ~= player then rootPart(other) else nil
			if
				otherRoot
				and not other:GetAttribute("InRound")
				and ((otherRoot.Position - root.Position).Magnitude < 35 or Social.PartnerOf(player) == other)
			then
				table.insert(helpers, other)
			end
		end
	end
	carriers[player] = {
		Helpers = helpers,
		Kind = kind,
		Item = item,
		StolenFrom = stolenFrom,
		Boss = boss,
		Visual = visual,
		LastPos = root.Position,
		LastCheck = os.clock(),
		Started = os.clock(),
		Source = source
			or (if boss then "boss" elseif kind == "Case" then "case" elseif stolenFrom then "vault" else "ground"),
		Zone = if boss then boss.Zone else (zoneIndexAt(root.Position) or 0),
	}
	if not resumed then
		local carry = carriers[player]
		Analytics.Track(player, "steal.start", carryProps(carry))
		Analytics.Milestone(player, "steal_started", carryProps(carry))
		if carry.Source == "boss" then
			Analytics.Milestone(player, "boss_steal_zone_" .. carry.Zone)
		end
	end
	Net.Animate(character, "Pickup")
	player:SetAttribute("Carrying", if kind == "Case" then `Case:{item}` else item)
	player:SetAttribute("StolenFrom", stolenFrom) -- the UserId it was taken from, if anyone
	BaseService.RefreshWalkSpeed(player)
	if kind == "Case" then
		Net.Notify(player, `You got a {item} Case! RUN HOME!`, "good")
	elseif boss then
		Net.Notify(player, `You got it! RUN HOME!`, "good")
	elseif stolenFrom then
		Net.Notify(player, `You took a {Items.DisplayName(item)}! RUN HOME!`, "good")
	else
		Net.Notify(player, `You got a {Items.DisplayName(item)}! RUN HOME!`, "good")
	end
end

function StealService.StartCarry(
	player: Player,
	kind: string,
	item: string,
	stolenFrom: number?,
	boss: { Zone: number, Slot: number }?
)
	if carriers[player] then
		return
	end
	startCarry(player, kind, item, stolenFrom, boss)
end

-- A boss caught their thief: the knife goes back on the wall (OnBossCarryEnded, not delivered)
function StealService.ReturnToBoss(player: Player): string?
	local carry = carriers[player]
	if not carry or not carry.Boss then
		return nil
	end
	local item = carry.Item
	endCarry(player, false, nil, "caught")
	Fuel.AddHeat(player, -1, "Caught by the boss!")
	Fuel.AddMeter(player, -1)
	return item
end

-- The wall slot a carrier's knife came from, if it's a boss's
function StealService.BossCarry(player: Player): { Zone: number, Slot: number }?
	local carry = carriers[player]
	return carry and carry.Boss
end

-- Rebirths bring better luck in cases
-- Set by Gamble: luck potions and the Luck pass
StealService.LuckMultiplier = nil :: ((Player, DataService.Profile) -> number)?

local function caseLuck(profile: DataService.Profile, player: Player?): number
	local luck = 1 + profile.Rebirths * GameConfig.Rebirth.LuckBonus
	if player and StealService.LuckMultiplier then
		luck *= StealService.LuckMultiplier(player, profile)
	end
	-- Someone bought Server Luck: everyone's cases roll better for a while
	local until_ = ReplicatedStorage:GetAttribute("ServerLuckUntil")
	if type(until_) == "number" and workspace:GetServerTimeNow() < until_ then
		luck *= (ReplicatedStorage:GetAttribute("ServerLuckMultiplier") or 2) :: number
	end
	return luck
end

-- Opens a sealed case straight onto a player's wall: the knife, mutation and size are rolled here,
-- the reveal plays on their screen (Effects "Unbox") and the wall updates when it lands. Used for
-- cases carried home, bought in the Case Shop and won from the free chest. nil if the wall is full,
-- unless `force` (a case paid for with Robux always opens; the knife waits in storage).
-- `lucky` = open a Lucky Block of that tier instead of a plain case (Items.LuckyBlocks)
function StealService.OpenCase(player: Player, rarity: string, force: boolean?, lucky: boolean?): string?
	local profile = DataService.Get(player)
	if not profile or (#profile.Knives >= profile.Slots and not force) then
		return nil
	end
	local rolled, upgraded
	if lucky then
		local got
		rolled, got = Items.OpenLuckyBlock(rng, rarity, caseLuck(profile, player))
		upgraded = Knives.Rank(got) > Knives.Rank(rarity)
	else
		rolled, upgraded = Items.OpenCase(rng, rarity, caseLuck(profile, player))
	end
	local item = Fuel.RollPower(player, rolled)
	local parsed = Items.Parse(item) :: Items.Item
	if parsed.Perk then
		task.delay(3.6, function()
			if player.Parent then
				revealPower(player, item)
			end
		end)
	end
	local isNew = not table.find(profile.Discovered, parsed.Name)
	local hype = Items.Hype(item)
	DataService.Update(player, function(p)
		DataService.AddKnife(p, item)
		if isNew then
			table.insert(p.Discovered, parsed.Name)
		end
		p.CasesOpened += 1
		if p.BestPull == "" or hype > Items.Hype(p.BestPull) then
			p.BestPull = item
		end
	end)
	Net.Remotes.Effect:FireClient(player, "Unbox", rarity, item, upgraded, isNew, lucky == true)
	Analytics.Track(player, if lucky then "case.lucky_block" else "case.open", {
		case = rarity,
		knife = parsed.Name,
		rarity = parsed.Knife.Rarity,
		mutation = parsed.Mutation.Id,
		size = parsed.Size.Id,
		power = parsed.Perk,
		upgraded = upgraded == true,
		new = isNew,
		hype = hype,
		paid = force == true,
		value = Items.Income(item),
	})
	Analytics.Milestone(player, "case_opened")
	task.delay(3.6, function()
		if player.Parent then
			BaseService.RefreshRack(player)
			Net.Remotes.Effect:FireAllClients("Deposit", player, parsed.Knife.Rarity)
			if player.Character then
				Net.Animate(player.Character, "Cheer")
			end
		end
	end)
	if hype >= 2 then
		task.delay(3.4, function()
			Net.Announce(`{player.DisplayName} unboxed a {Items.DisplayName(item)}!`, Items.Color(item), hype)
		end)
	end
	return item
end

-- A knife came home with a Murderer power: a big reveal for you, and the whole server hears about
-- the rare ones
revealPower = function(player: Player, item: string)
	local parsed = Items.Parse(item)
	if not parsed or not parsed.Perk then
		return
	end
	local oneIn = Items.PowerOneIn(parsed.Perk)
	-- Every knife has a power now: the big reveal is for Epic and up, the server hears Legendary+
	if oneIn < 25 then
		return
	end
	Net.Remotes.Effect:FireClient(player, "PowerRoll", item, parsed.Perk, oneIn)
	if oneIn >= 60 then
		local perk = GameConfig.Perks[parsed.Perk]
		Net.Announce(
			`{player.DisplayName} rolled {if perk then perk.DisplayName else parsed.Perk} (1 in {oneIn})!`,
			Color3.fromRGB(255, 90, 140),
			if oneIn >= 1000 then 4 else 3
		)
	end
end

local function deposit(player: Player)
	local carry = carriers[player]
	if not carry then
		return
	end
	local profile = DataService.Get(player)
	if not profile or #profile.Knives >= profile.Slots then
		Net.Notify(player, "Your vault is full! Sell a knife first.", "bad")
		Offers.Show(player, "Mount", "Your wall is full! Add another mount instantly.")
		endCarry(player, false, nil, "vault_full")
		return
	end
	if carry.Kind == "Case" then
		local rarity = carry.Item
		endCarry(player, true)
		StealService.OpenCase(player, rarity)
		return
	end
	-- Its Murderer power is rolled now, with your luck (Heat, deeper zones, bad-luck protection)
	-- Power XP: a boss's knife home, or one stolen from a vault in the Blood Moon
	if carry.Boss then
		Fuel.GivePowerXP(player, GameConfig.PowerXP.BossSteal)
	elseif carry.StolenFrom then
		Fuel.GivePowerXP(player, GameConfig.PowerXP.MoonSteal)
	end
	local item = Fuel.RollPower(player, carry.Item)
	local parsed = Items.Parse(item) :: Items.Item
	local isNew = not table.find(profile.Discovered, parsed.Name)
	if carry.Boss then
		Fuel.AddHeat(player, 1, "Stole from a boss!")
		Fuel.AddMeter(player, 1)
		ServerEvents.Progress("Steals")
		-- 🤝 Whoever helped (near you when you grabbed it, or your teammate) shares the glory
		for _, helper in carry.Helpers do
			if helper.Parent and helper ~= player then
				Fuel.AddHeat(helper, 1, `Team steal with {player.DisplayName}!`)
				Fuel.AddMeter(helper, 1)
			end
		end
		-- The last boss's knife: the deep bosses restock fast for everyone for a while
		if carry.Boss.Zone >= #GameConfig.Zones and not ServerEvents.Active("CosmicRush") then
			ServerEvents.Start("CosmicRush", player.DisplayName)
		end
	end
	if parsed.Perk then
		revealPower(player, item)
	end
	DataService.Update(player, function(p)
		DataService.AddKnife(p, item, carry.Plate)
		if isNew then
			table.insert(p.Discovered, parsed.Name)
		end
		if carry.StolenFrom then
			p.KnivesStolen += 1
		end
	end)
	local stolenFrom = carry.StolenFrom
	Analytics.Track(player, "knife.mounted", {
		knife = parsed.Name,
		rarity = parsed.Knife.Rarity,
		mutation = parsed.Mutation.Id,
		size = parsed.Size.Id,
		power = parsed.Perk,
		power_one_in = if parsed.Perk then Items.PowerOneIn(parsed.Perk) else nil,
		new = isNew,
		value = Items.Income(item),
		plate = carry.Plate,
	})
	if #profile.Knives >= 2 then
		Analytics.Milestone(player, "second_knife_home")
	end
	if isNew then
		Analytics.Milestone(player, "discovered_" .. parsed.Knife.Rarity)
	end
	endCarry(player, true)
	local name = Items.DisplayName(item)
	BaseService.RefreshRack(player)
	-- One short line (the plate's own label already shows the rest)
	Net.Notify(player, `{if isNew then "NEW! " else ""}{name} +{Format.Cash(Items.Income(item))}/s`, "good")
	Net.Remotes.Effect:FireAllClients("Deposit", player, parsed.Knife.Rarity)
	if stolenFrom then
		local victim = ownerName(stolenFrom) or "someone"
		Net.Announce(`{player.DisplayName} stole {victim}'s {name}!`, Color3.fromRGB(255, 90, 90), 1)
	end
	if player.Character then
		Net.Animate(player.Character, "Cheer")
	end
end

-- Put the carried knife on a plate: any empty, unlocked plate in your own vault. A short
-- animation (the knife flies from your hands onto the plate), then it's mounted.
function StealService.Place(player: Player, slot: number)
	local carry = carriers[player]
	local root = rootPart(player)
	local profile = DataService.Get(player)
	if not carry or carry.Kind ~= "Knife" or not root or not profile then
		return
	end
	if
		not BaseService.IsInOwnBase(player, root.Position)
		or slot < 1
		or slot > profile.Slots
		or DataService.IndexOnPlate(profile, slot) ~= nil
	then
		return
	end
	local base = BaseService.GetBase(player)
	if not base then
		return
	end
	local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
	local from = if head then head.Position + Vector3.new(0, 1.2, 0) else root.Position
	-- Hide the one overhead while the copy flies; mount it when it lands
	for _, d in carry.Visual:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
		end
	end
	if player.Character then
		Net.Animate(player.Character, "Pickup")
	end
	carry.Plate = slot
	Net.Remotes.Effect:FireAllClients("PlaceKnife", from, base.SlotCFrames[slot].Position, carry.Item)
	task.delay(0.45, function()
		if carriers[player] == carry then
			deposit(player)
		end
	end)
end

-- Deposits and the carrier speed check run on the server's view of positions
local function tick()
	local now = os.clock()
	for player, carry in carriers do
		local root = rootPart(player)
		if not root then
			-- Died (or the character went away): drop it where they were
			endCarry(player, false, carry.LastPos, "died")
			continue
		end
		local pos = root.Position
		if BaseService.IsInOwnBase(player, pos) then
			if carry.Kind == "Case" then
				deposit(player) -- cases open as soon as you're home
				continue
			end
			-- Knives: you put them on a plate yourself (Tsunami style), StealService.Place
			if not player:GetAttribute("PlaceReady") then
				player:SetAttribute("PlaceReady", true)
				local profile = DataService.Get(player)
				if profile and #profile.Knives >= profile.Slots then
					Net.Notify(player, "Your vault is full! Sell a knife first.", "bad")
					Offers.Show(player, "Mount", "Your vault is full! Add the next floor instantly.")
				else
					Net.Notify(player, "Walk to a glowing plate to put it down!", "good")
				end
			end
		elseif player:GetAttribute("PlaceReady") then
			player:SetAttribute("PlaceReady", nil)
		end
		local elapsed = now - carry.LastCheck
		if player:GetAttribute("Tumbling") then
			-- Flung by a hit (Ragdoll.Tumble): that's not cheating, start measuring again after
			carry.LastPos = pos
			carry.LastCheck = now
		elseif elapsed >= 0.5 then
			local humanoid = (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
			local flat = Vector3.new(pos.X - carry.LastPos.X, 0, pos.Z - carry.LastPos.Z).Magnitude
			local allowed = math.max(humanoid.WalkSpeed, GameConfig.BaseWalkSpeed) * elapsed * GameConfig.SpeedTolerance
				+ 3
			if flat > allowed then
				warn(
					`[StealService] {player.Name} moved {math.floor(flat)} studs in {elapsed}s while carrying, dropping it`
				)
				Net.Notify(player, "Oops! You dropped it.", "bad")
				endCarry(player, false, carry.LastPos, "slipped")
				continue
			end
			carry.LastPos = pos
			carry.LastCheck = now
		end
	end
end

function StealService.GetCarriers(): { [Player]: Carry }
	return carriers
end

function StealService.IsCarrying(player: Player): boolean
	return carriers[player] ~= nil
end

-- Rounds pull everyone out of the arena, knockdowns knock it loose: whatever they carried drops
-- `owner` caught `thief` running off with `owner`'s knife: it goes straight back on their wall
-- (or onto the floor for them to grab if the wall is full). Returns the item, or nil.
function StealService.Recover(thief: Player, owner: Player): string?
	local carry = carriers[thief]
	if not carry or carry.Kind ~= "Knife" or carry.StolenFrom ~= owner.UserId then
		return nil
	end
	local profile = DataService.Get(owner)
	if not profile or #profile.Knives >= profile.Slots then
		return nil
	end
	local item = carry.Item
	endCarry(thief, true, nil, "recovered")
	Analytics.Track(owner, "moon.recovered", { knife = Items.Name(item) })
	DataService.Update(owner, function(p)
		DataService.AddKnife(p, item)
	end)
	BaseService.RefreshRack(owner)
	return item
end

-- A round pulled a carrier in: the carry is set aside (the boss's slot stays empty) and handed back
-- on the way home (Resume, via BaseService.OnReturnedHome), so they're back where they were, still
-- holding it. Released (back to the wall / dropped) if they leave or never come back for it.
type Suspended = {
	Kind: string,
	Item: string,
	StolenFrom: number?,
	Boss: { Zone: number, Slot: number }?,
	At: Vector3?,
	ChaserAt: CFrame?,
	Chasing: boolean,
	Since: number,
}
local suspended: { [Player]: Suspended } = {}
StealService.OnResumeBoss = nil :: ((player: Player, zone: number, at: CFrame?, chasing: boolean) -> ())?
StealService.OnSuspendBoss = nil :: ((player: Player, zone: number) -> (CFrame?, boolean))?

local function release(player: Player)
	local held = suspended[player]
	suspended[player] = nil
	if not held then
		return
	end
	if held.Boss then
		local hook = StealService.OnBossCarryEnded
		if hook then
			hook(held.Boss.Zone, held.Boss.Slot, held.Item, false)
		end
	elseif held.At then
		if held.Kind == "Case" then
			StealService.DropCase(held.Item, held.At)
		else
			StealService.DropKnife(held.Item, held.At, held.StolenFrom)
		end
	end
end

function StealService.Suspend(player: Player)
	local carry = carriers[player]
	if not carry then
		return
	end
	carriers[player] = nil
	Analytics.Track(player, "steal.suspended", carryProps(carry))
	carry.Visual:Destroy()
	player:SetAttribute("Carrying", nil)
	player:SetAttribute("StolenFrom", nil)
	player:SetAttribute("PlaceReady", nil)
	BaseService.RefreshWalkSpeed(player)
	local chaserAt, chasing = nil, false
	if carry.Boss and StealService.OnSuspendBoss then
		chaserAt, chasing = StealService.OnSuspendBoss(player, carry.Boss.Zone)
	end
	suspended[player] = {
		Kind = carry.Kind,
		Item = carry.Item,
		StolenFrom = carry.StolenFrom,
		Boss = carry.Boss,
		At = carry.LastPos,
		ChaserAt = chaserAt,
		Chasing = chasing,
		Since = os.clock(),
	}
end

function StealService.Resume(player: Player)
	local held = suspended[player]
	if not held or player:GetAttribute("InRound") then
		return
	end
	suspended[player] = nil
	startCarry(player, held.Kind, held.Item, held.StolenFrom, held.Boss, nil, true)
	if not carriers[player] then
		-- couldn't hand it back (no character): don't lose it
		suspended[player] = held
		release(player)
		return
	end
	Net.Notify(player, "You still have it! RUN HOME!", "good")
	-- The boss picks the chase back up (no free escapes by waiting out a round)
	if held.Boss and StealService.OnResumeBoss then
		StealService.OnResumeBoss(player, held.Boss.Zone, held.ChaserAt, held.Chasing)
	end
end

-- Steal a Brainrot's bat, with our knives: out of the biomes, anyone carrying a stolen knife can be
-- hit by another player's hub knife. They go flying like a boss hit and the knife drops where they
-- were, for anyone to grab. Only carriers can be hit (no other PvP), never at home in their own
-- vault, never in a round, and never a new player.
local function onRunway(position: Vector3): boolean
	return position.Z > -2 and math.abs(position.X) < GameConfig.ArenaWidth / 2 + 2
end

local function canHitCarrier(attacker: Player, victim: Player): boolean
	if
		attacker == victim
		or not carriers[victim]
		or attacker:GetAttribute("InRound")
		or victim:GetAttribute("InRound")
	then
		return false
	end
	local root, attackerRoot = rootPart(victim), rootPart(attacker)
	if not root or not attackerRoot or onRunway(root.Position) or onRunway(attackerRoot.Position) then
		return false
	end
	if DataService.IsNewPlayer(victim) or victim:GetAttribute("Tumbling") then
		return false
	end
	local _, owner = BaseService.BaseAt(root.Position)
	return owner ~= victim -- safe once they're inside their own vault
end

-- Knocks the carried knife loose: it lands on the ground (a boss's knife too: that wall slot counts
-- as taken and restocks later, the knife is now anyone's)
function StealService.KnockLoose(victim: Player, attacker: Player, from: Vector3)
	local carry = carriers[victim]
	local root = rootPart(victim)
	if not carry or not root then
		return
	end
	local at = root.Position
	local item, boss = carry.Item, carry.Boss
	if boss then
		endCarry(victim, true, nil, "knocked")
		StealService.DropKnife(item, at)
	else
		endCarry(victim, false, at, "knocked")
	end
	Analytics.Track(attacker, "pvp.knocked_loose", { victim_new = DataService.IsNewPlayer(victim) })
	local away = (at - from) * Vector3.new(1, 0, 1)
	local push = (if away.Magnitude > 0.1 then away.Unit else -root.CFrame.LookVector) * 50 + Vector3.new(0, 45, 0)
	Ragdoll.Tumble(victim, push, 1.4)
	Net.Remotes.Effect:FireAllClients("Hit", at)
	Net.Notify(victim, `{attacker.DisplayName} made you drop it!`, "bad")
	Net.Remotes.Effect:FireClient(victim, "Tip", "Knocked")
	Net.Notify(attacker, "They dropped it! Grab it!", "good")
end

-- A boss's knife being carried goes straight back on its wall (no penalty: the Blood Moon closing
-- the biomes, not the boss catching you)
function StealService.CancelBossCarry(player: Player)
	local carry = carriers[player]
	if carry and carry.Boss then
		endCarry(player, false, nil, "moon")
	end
end

function StealService.ForceDrop(player: Player)
	local root = rootPart(player)
	endCarry(player, false, if root then root.Position else nil, "forced")
end

function StealService.Init()
	-- Carriers are hub-knife targets (CombatService swings and throws ask Targets)
	Targets.AddProvider(function()
		local list = {}
		for victim in carriers do
			local character = victim.Character
			local root = rootPart(victim)
			if character and root then
				table.insert(
					list,
					{
						Part = root,
						Model = character,
						CanHit = function(attacker: Player): boolean
							return canHitCarrier(attacker, victim)
						end,
						Hit = function(attacker: Player, _damage: number, _kind: string, from: Vector3)
							if canHitCarrier(attacker, victim) then
								StealService.KnockLoose(victim, attacker, from)
							end
						end,
					} :: any
				)
			end
		end
		return list
	end)
	BaseService.OnPlacePrompt = StealService.Place
	dropFolder = Instance.new("Folder")
	dropFolder.Name = "DroppedKnives"
	dropFolder.Parent = workspace:FindFirstChild("Map")

	BaseService.OnReturnedHome = StealService.Resume
	-- Never held forever: released after 10 minutes if they somehow don't come back for it
	task.spawn(function()
		while true do
			task.wait(30)
			for player, held in suspended do
				if os.clock() - held.Since > 600 then
					release(player)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		release(player)
		local carry = carriers[player]
		endCarry(player, false, if carry then carry.LastPos else nil, "left")
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.1 then
			accumulator = 0
			tick()
		end
	end)
end

return StealService
