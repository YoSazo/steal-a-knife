--!strict
-- Loot and carrying. Dropped knives float with a tag and a light beam. Hold the prompt to pick one
-- up and carry it over your head back to your vault (a boss's knife travels as a coffin on coffin
-- servers). Knives stolen from other players' vaults in a raid remember who they belong to - if the thief drops one, its owner can grab it
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
local ChanceMeter = require(script.Parent.ChanceMeter)
local MapService = require(script.Parent.MapService)
local Offers = require(script.Parent.Offers)
local Ragdoll = require(script.Parent.Ragdoll)
local Targets = require(script.Parent.Targets)
local Analytics = require(script.Parent.Analytics)
local CoffinService = require(script.Parent.CoffinService)
local PenMode = require(ReplicatedStorage.Shared.PenMode)
local CoffinModel = require(ReplicatedStorage.Shared.CoffinModel)

type Carry = {
	Kind: string, -- "Knife"
	Item: string, -- the knife item
	ReadySince: number?, -- (pens) when they walked into their pen holding it: PlaceAfter fallback
	Boss: { Zone: number, Slot: number }?,
	Helpers: { Player }, -- players who helped with a boss steal (team steal) -- taken off a biome boss's wall (GuardService)
	Visual: Model,
	LastPos: Vector3,
	LastCheck: number,
	Plate: number?, -- the plate the owner chose to put it on (Place)
	Started: number, -- os.clock() it was picked up (analytics)
	Source: string, -- "boss" | "ground" (analytics)
	Zone: number, -- zone it was picked up in, 0 = outside the biomes (analytics)
}

local Progress = require(script.Parent.RoundProgress)
local StealService = {}

-- Set by GuardService: (player, zoneIndex) when someone picks something up in the arena
StealService.OnPickup = nil :: ((Player, number) -> ())?
-- Set by GuardService: a knife taken off a boss's wall left the thief's hands. delivered = it made it
-- home (the slot restocks later); otherwise it goes straight back on the wall.
StealService.OnBossCarryEnded = nil :: ((zone: number, slot: number, item: string, delivered: boolean) -> ())?

StealService.OnCancelPausedChase = nil :: ((Player) -> ())?
StealService.OnPauseChase = nil :: ((Player) -> Vector3?)?
StealService.OnResumeChase = nil :: ((Player, number, Vector3?, number) -> ())?
local carriers: { [Player]: Carry } = {}
type SavedRun = {
	Carry: Carry,
	Frame: CFrame,
	Health: number,
	Chaser: Vector3?,
	Elapsed: number,
	Queued: boolean,
	NeedsChase: boolean,
}
local savedRuns: { [Player]: SavedRun } = {}
local dropFolder: Folder
local carriedFolder: Folder

local function rootPart(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function zoneIndexAt(position: Vector3): number?
	return MapService.ZoneAt(position)
end

-- The floating tag over a drop: a few lines of coloured text
local function tag(adornee: BasePart, lines: { { Text: string, Color: Color3, Height: number } })
	local gui = Instance.new("BillboardGui")
	-- (studs, ~30 px a stud: shrinks with distance)
	local height = 0
	for _, line in lines do
		height += line.Height
	end
	gui.Size = UDim2.fromScale(8, height / 30)
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
		label.Size = UDim2.fromScale(1, line.Height / height)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = line.Color
		label.TextStrokeTransparency = 0.2
		label.Text = line.Text
		label.Parent = gui
	end
end

local startCarry: (Player, string, string, { Zone: number, Slot: number }?, string?) -> ()
local dropped: { [Model]: { Item: string, Prompt: ProximityPrompt, Sealed: boolean } } = {}

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
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if
		not root
		or not profile
		or not humanoid
		or humanoid.Health <= 0
		or player:GetAttribute("InRound")
		or carriers[player]
	then
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
		Offers.Show(player, "Mount", "Your vault is full! Get more room right now.")
		return false
	end
	return true
end

-- One authoritative pickup path for native prompts and Studio regression checks. Invalidating
-- the registered drop before granting its carry also prevents duplicate pickup requests.
function StealService.TakeDrop(player: Player, model: Model): boolean
	local entry = dropped[model]
	local anchor = model.PrimaryPart
	if
		not entry
		or not anchor
		or not model:IsDescendantOf(dropFolder)
		or not canPickUp(player, anchor, entry.Prompt)
	then
		return false
	end
	dropped[model] = nil
	model:Destroy()
	startCarry(player, "Knife", entry.Item, nil, if entry.Sealed then "coffin" else "ground")
	local zone = zoneIndexAt(anchor.Position)
	if zone and StealService.OnPickup then
		StealService.OnPickup(player, zone)
	end
	return carriers[player] ~= nil
end

-- Puts a knife item on the floor: glowing, tagged, spinning, and gone after a while.
function StealService.DropKnife(item: string, position: Vector3, sealed: boolean?)
	local parsed = Items.Parse(item)
	if not parsed then
		return
	end
	local floorY = floorAt(position)
	local at = Vector3.new(position.X, floorY + 2.2, position.Z)
	local coffin = sealed == true and PenMode.Coffins()
	local model = if coffin
		then CoffinModel.Build(parsed.Knife.Rarity, CFrame.identity, item)
		else KnifeModel.Build(item, true)
	if not coffin then
		KnifeModel.FitItem(model, item, 3.2)
	end
	model:PivotTo(CFrame.new(at) * CFrame.Angles(0, 0, math.rad(20)))
	model.Name = if coffin then "DroppedCoffin" else `Dropped_{parsed.Name}`
	model:SetAttribute("SealedDrop", coffin)
	local color = if coffin then Knives.RarityColors[parsed.Knife.Rarity] else Items.Color(item)
	local knife = parsed.Knife
	local anchor = model.PrimaryPart :: BasePart
	local lines = if coffin
		then {
			{ Text = `{knife.Rarity:upper()} COFFIN`, Color = color, Height = 30 },
		}
		else {
			{ Text = Items.DisplayName(item), Color = color, Height = 30 },
			{ Text = knife.Rarity:upper(), Color = Knives.RarityColors[knife.Rarity], Height = 18 },
			{
				Text = `{Format.Cash(Items.Income(item))}/s`,
				Color = Color3.new(1, 1, 1),
				Height = 22,
			},
		}
	tag(anchor, lines)
	local prompt = dress(model, color, floorY, at, if coffin then `{knife.Rarity} Coffin` else Items.DisplayName(item))
	dropped[model] = { Item = item, Prompt = prompt, Sealed = coffin }
	model.Destroying:Connect(function()
		dropped[model] = nil
	end)
	prompt.Triggered:Connect(function(player)
		StealService.TakeDrop(player, model)
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

-- why (analytics): "home" | "caught" | "died" | "knocked" | "slipped" | "vault_full" |
-- "left" | "forced" | "drop" (the steal.<why> event)
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
			local target = player:GetAttribute("PrizeTargetZone")
			if type(target) == "number" and carry.Zone >= target then
				Analytics.Track(player, "prize.followup", { stage = "home", zone = carry.Zone, target = target })
				player:SetAttribute("PrizeTargetZone", nil)
			end
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
	player:SetAttribute("BossCarry", nil)
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
		StealService.DropKnife(carry.Item, where, carry.Source == "coffin")
	end
end

-- Lifts a knife (kind "Knife", item string) over a player's head
startCarry = function(
	player: Player,
	kind: string,
	item: string,
	boss: { Zone: number, Slot: number }?,
	source: string?
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
	if (boss or source == "coffin") and PenMode.Coffins() then
		-- a boss's coffin, held over your head (what's in it stays a secret until it opens)
		local parsed = Items.Parse(item)
		visual = CoffinModel.Build(if parsed then parsed.Knife.Rarity else "Common", CFrame.identity, item)
		CoffinModel.Weld(visual) -- (all of it rides on your head, not just one piece)
		-- (full size, as it lay in the graveyard: a big one is a big haul, and everyone sees it)
		local _, size = visual:GetBoundingBox()
		above = head.CFrame * CFrame.new(0, 0.9 + size.Y / 2, 0)
		visual:PivotTo(above * CFrame.Angles(0, math.rad(90), 0))
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
	-- Avatar restoration can replace Head after this function returns. The root survives it.
	weld.Name = "CarryAttachment"
	weld.Part0 = root
	weld.Part1 = visual.PrimaryPart :: BasePart
	weld.Parent = visual
	-- Keep carried models outside the avatar so appearance resets cannot delete/hide them.
	visual:SetAttribute("CarryOwner", player.UserId)
	visual.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	visual.Parent = carriedFolder

	-- Team steal: anyone close by when you grab a boss's knife (and your teammate, wherever they are)
	local helpers: { Player } = {}
	if boss then
		for _, other in Players:GetPlayers() do
			local otherRoot = if other ~= player then rootPart(other) else nil
			if
				otherRoot
				and not other:GetAttribute("InRound")
				and (otherRoot.Position - root.Position).Magnitude < 35
			then
				table.insert(helpers, other)
			end
		end
	end
	carriers[player] = {
		Helpers = helpers,
		Kind = kind,
		Item = item,
		Boss = boss,
		Visual = visual,
		LastPos = root.Position,
		LastCheck = os.clock(),
		Started = os.clock(),
		Source = source or (if boss then "boss" else "ground"),
		Zone = if boss then boss.Zone else (zoneIndexAt(root.Position) or 0),
	}
	local carry = carriers[player]
	Analytics.Track(player, "steal.start", carryProps(carry))
	Analytics.Milestone(player, "steal_started", carryProps(carry))
	if carry.Source == "boss" then
		Analytics.Milestone(player, "boss_steal_zone_" .. carry.Zone)
		-- the round prize's Speed in use: a steal from the boss it was for (or deeper)
		local target = player:GetAttribute("PrizeTargetZone")
		if type(target) == "number" and carry.Zone >= target then
			Analytics.Track(player, "prize.followup", { stage = "attempt", zone = carry.Zone, target = target })
		end
	end
	Net.Animate(character, "Pickup")
	player:SetAttribute("Carrying", if boss or source == "coffin" then Items.Name(item) else item)
	player:SetAttribute("BossCarry", if boss then boss.Zone else nil) -- (a boss is after you)
	BaseService.RefreshWalkSpeed(player)
	-- (a boss steal gets no toast: GuardService already says "RUN HOME!")
	if boss then
		return
	else
		Net.Notify(player, `{if source == "coffin" then "Coffin!" else Items.DisplayName(item)} RUN HOME!`, "good")
	end
end

function StealService.StartCarry(
	player: Player,
	kind: string,
	item: string,
	boss: { Zone: number, Slot: number }?,
	source: string?
)
	if carriers[player] or savedRuns[player] then
		return
	end
	startCarry(player, kind, item, boss, source)
end

-- A boss caught their thief: the knife goes back on the wall (OnBossCarryEnded, not delivered)
function StealService.ReturnToBoss(player: Player): string?
	local carry = carriers[player]
	if not carry or not carry.Boss then
		return nil
	end
	local item = carry.Item
	endCarry(player, false, nil, "caught")
	ChanceMeter.Add(player, -1)
	return item
end

-- The wall slot a carrier's knife came from, if it's a boss's
function StealService.BossCarry(player: Player): { Zone: number, Slot: number }?
	local carry = carriers[player]
	return carry and carry.Boss
end

local function deposit(player: Player)
	local carry = carriers[player]
	if not carry then
		return
	end
	local profile = DataService.Get(player)
	local needsCoffin = (carry.Boss ~= nil or carry.Source == "coffin") and CoffinService.On(player)
	if profile and needsCoffin and not DataService.FreePlate(profile) then
		Net.Notify(player, "PEN FULL! Buy a spot or sell a knife in My Knives.", "bad")
		return -- keep the coffin in their hands while they make room
	end
	if not profile or #profile.Knives >= PenMode.Capacity(profile.Slots) then
		Net.Notify(player, "Your vault is full! Sell a knife first.", "bad")
		Offers.Show(player, "Mount", "Your vault is full! Get more room right now.")
		endCarry(player, false, nil, "vault_full")
		return
	end
	-- (pen full, bag has room: it goes in the bag - no coffin to sit in the pen)
	local toBag = #profile.Knives >= profile.Slots
	if needsCoffin and not DataService.FreePlate(profile) then
		Net.Notify(player, "Your pen is full! Make room before placing the coffin.", "bad")
		return -- keep carrying it; storage must not turn a sealed coffin into an open knife
	end
	-- The tutorial's first knife always gets the starter power (Shadow: vanish), so every new player
	-- starts with the same simple, easy-to-show power; after that it's the knife type's own power
	local starter = not profile.TutorialDone and profile.TutorialStep <= 2 and #profile.Knives <= 1
	local item = carry.Item
	local parsed = Items.Parse(item) :: Items.Item
	local isNew = not table.find(profile.Discovered, parsed.Name)
	-- A boss's knife comes home in a COFFIN that opens later (CoffinService) - never in the tutorial
	local sealed = needsCoffin
	-- (the tutorial's coffin: it lands and counts down a few seconds - Steal an Egg's egg - then opens)
	local quick = sealed and (starter or not profile.TutorialDone)

	if carry.Boss then
		ChanceMeter.Add(player, 1)
		-- 🤝 Whoever helped (near you when you grabbed it, or your teammate) shares the glory
		for _, helper in carry.Helpers do
			if helper.Parent and helper ~= player then
				ChanceMeter.Add(helper, 1)
			end
		end
	end
	local placedPlate: number? = nil
	local opensIn: string? = nil
	DataService.Update(player, function(p)
		placedPlate = DataService.AddKnife(p, item, carry.Plate)
		if sealed then
			opensIn = CoffinService.SealInto(
				p,
				placedPlate :: number,
				item,
				if quick then GameConfig.Coffins.TutorialSeconds else nil
			)
		end
		-- Save placement with the inventory change, even if the client leaves before step 3 appears.
		if not p.TutorialDone then
			p.TutorialStep = math.max(p.TutorialStep, 3)
		end
		if isNew and not sealed then -- (a coffin's knife joins your Index when it opens)
			table.insert(p.Discovered, parsed.Name)
		end
		if carry.Boss then
			p.KnivesStolen += 1 -- (the "Stolen" leaderboard: knives taken from bosses)
		end
	end)
	-- Only this successful carried-knife deposit confirms placement. Unboxes use the cosmetic
	-- Deposit effect too, so the tutorial must not infer success from that effect or inventory size.
	-- Publish the exact mounted item/plate before confirmation, so the guide can point at it.
	player:SetAttribute("LastPlacedKnife", if sealed then Items.Name(item) else item)
	player:SetAttribute("LastPlacedKnifePlate", placedPlate)
	local placementSerial = (player:GetAttribute("KnifePlacementSerial") or 0) :: number
	player:SetAttribute("KnifePlacementSerial", placementSerial + 1)
	Analytics.Track(player, "knife.mounted", {
		knife = parsed.Name,
		rarity = parsed.Knife.Rarity,
		mutation = parsed.Mutation.Id,
		size = parsed.Size.Id,
		new = isNew,
		value = Items.Income(item),
		plate = carry.Plate,
	})
	if #profile.Knives >= 2 then
		Analytics.Milestone(player, "second_knife_home")
	end
	if isNew and not sealed then
		Analytics.Milestone(player, "discovered_" .. parsed.Knife.Rarity)
	end
	if carry.Boss or carry.Source == "coffin" then
		Progress.Delivered(player, if carry.Boss then carry.Boss.Zone else Knives.Rank(parsed.Knife.Rarity))
	end
	endCarry(player, true)
	local name = Items.DisplayName(item)
	BaseService.RefreshRack(player)
	-- The plate already labels name/income. Let a Murderer-power reveal have the screen to itself.
	if toBag then
		Net.Notify(player, `Pen full! {name} is in your bag.`, "info")
		Offers.Show(player, "Mount", "Your pen is full! Get more room right now.")
	elseif not opensIn then
		-- (a coffin you just put down yourself and watched land needs no toast)
		Net.Notify(player, `{if isNew then "NEW! " else ""}{name} +{Format.Cash(Items.Income(item))}/s`, "good")
	end
	Net.Remotes.Effect:FireAllClients("Deposit", player, parsed.Knife.Rarity)
	if player.Character then
		Net.Animate(player.Character, "Cheer")
	end
end

-- Put the carried knife on a plate: any empty, unlocked plate in your own vault. A short
-- animation (the knife flies from your hands onto the plate), then it's mounted.
-- Pens: put what you carry down at `position` (a tap on your pen's grass: client/PlaceTap). It
-- takes the first free plate and that plate's spot moves to where you tapped (saved: profile.Spots)
function StealService.PlaceAt(player: Player, position: Vector3)
	local carry = carriers[player]
	local root = rootPart(player)
	local profile = DataService.Get(player)
	local base = BaseService.GetBase(player)
	if not carry then
		BaseService.PlaceHatched(player, position) -- (a knife fresh out of its coffin, in your hand)
		return
	end
	if not carry or carry.Kind ~= "Knife" or not root or not profile or not base then
		return
	end
	if not BaseService.IsInOwnBase(player, root.Position) or not MapService.InBounds(base.Bounds, position, -2) then
		return
	end
	local plate = DataService.FreePlate(profile)
	if not plate then
		return
	end
	local here = base.Frame:PointToObjectSpace(position)
	DataService.Update(player, function(p)
		p.Spots[tostring(plate)] = { math.floor(here.X * 10) / 10, math.floor(here.Z * 10) / 10 }
	end)
	BaseService.ApplySpot(player, plate)
	StealService.Place(player, plate)
end

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
	-- (a boss's knife / a stolen coffin lands as a coffin: the flying thing must not reveal the knife)
	local asCoffin = (carry.Boss ~= nil or carry.Source == "coffin") and CoffinService.On(player)
	local parsed = Items.Parse(carry.Item)
	Net.Remotes.Effect:FireAllClients(
		"PlaceKnife",
		from,
		base.SlotCFrames[slot].Position,
		carry.Item,
		if asCoffin and parsed then parsed.Knife.Rarity else nil
	)
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
			-- A pen: you tap where to put it down (client/PlaceTap -> Remotes.PlaceAt). A full pen
			-- (bag only) takes it straight away; and nobody stands holding it forever (PlaceAfter)
			local profile = DataService.Get(player)
			if profile and not DataService.FreePlate(profile) then
				deposit(player)
				continue
			end
			if not player:GetAttribute("PlaceReady") then
				player:SetAttribute("PlaceReady", true)
				carry.ReadySince = now
				Net.Notify(player, "Tap where you want to put it!", "good")
			elseif now - (carry.ReadySince or now) > GameConfig.Pens.PlaceAfter then
				deposit(player)
			end
			continue
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

-- A stolen monster coffin waits through the round. Its reserved slot is never re-rolled.
function StealService.EndForRound(player: Player): boolean
	local carry, root = carriers[player], rootPart(player)
	if carry and root then
		local humanoid = (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
		local pause = StealService.OnPauseChase
		savedRuns[player] = {
			Carry = carry,
			Frame = root.CFrame,
			Health = humanoid.Health,
			Chaser = if pause then pause(player) else nil,
			Elapsed = os.clock() - carry.Started,
			Queued = false,
			NeedsChase = carry.Boss ~= nil
				and root.Position.Z > 0
				and math.abs(root.Position.X) < GameConfig.ArenaWidth / 2,
		}
		root.Anchored = true
		root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		carriers[player] = nil
		task.delay(2, function()
			carry.Visual:Destroy()
		end)
		player:SetAttribute("Carrying", nil)
		player:SetAttribute("BossCarry", nil)
		player:SetAttribute("PlaceReady", nil)
		player:SetAttribute("RunSaved", true)
		BaseService.RefreshWalkSpeed(player)
		Net.Remotes.Effect:FireClient(player, "RunSaved")
		local saved = savedRuns[player]
		task.spawn(function()
			while player.Parent and savedRuns[player] == saved do
				pcall(player.RequestStreamAroundAsync, player, saved.Frame.Position, 1)
				task.wait(8)
			end
		end)
		return true
	end
	endCarry(player, false, nil, "round_reset")
	return false
end

function StealService.HasSavedRun(player: Player): boolean
	return savedRuns[player] ~= nil
end

function StealService.CancelSavedRun(player: Player)
	local saved = savedRuns[player]
	if not saved then
		return
	end
	savedRuns[player] = nil
	if StealService.OnCancelPausedChase then
		StealService.OnCancelPausedChase(player)
	end
	player:SetAttribute("RunSaved", nil)
	local boss = saved.Carry.Boss
	local hook = StealService.OnBossCarryEnded
	if boss and hook then
		hook(boss.Zone, boss.Slot, saved.Carry.Item, false)
	end
end

function StealService.ReturnAfterRound(player: Player)
	local saved = savedRuns[player]
	if not saved or saved.Queued then
		return
	end
	saved.Queued = true
	task.spawn(function()
		-- The round is over: return directly to the saved scene, without a hub stop or fade.
		if savedRuns[player] ~= saved or not player.Parent then
			return
		end
		if not rootPart(player) then
			pcall(player.LoadCharacterAsync, player)
		end
		local readyBy = os.clock() + 10
		while savedRuns[player] == saved and player.Parent and not rootPart(player) and os.clock() < readyBy do
			task.wait(0.05)
		end
		local root = rootPart(player)
		if not root or not player.Character or savedRuns[player] ~= saved or not player.Parent then
			saved.Queued = false
			if player.Parent and savedRuns[player] == saved then
				task.delay(1, StealService.ReturnAfterRound, player)
			end
			return
		end
		root.Anchored = true
		player.Character:PivotTo(saved.Frame)
		root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid") :: Humanoid
		humanoid.Health = math.clamp(saved.Health, 1, humanoid.MaxHealth)
		savedRuns[player] = nil
		local carry = saved.Carry
		startCarry(player, carry.Kind, carry.Item, carry.Boss, carry.Source)
		local live = carriers[player]
		if not live then
			local boss, hook = carry.Boss, StealService.OnBossCarryEnded
			if boss and hook then
				hook(boss.Zone, boss.Slot, carry.Item, false)
			end
			root.Anchored = false
			if StealService.OnCancelPausedChase then
				StealService.OnCancelPausedChase(player)
			end
			player:SetAttribute("RunSaved", nil)
			return
		end
		live.Helpers, live.Started = carry.Helpers, os.clock() - saved.Elapsed
		if not saved.NeedsChase then
			root.Anchored = false
			player:SetAttribute("RunSaved", nil)
			if StealService.OnCancelPausedChase then
				StealService.OnCancelPausedChase(player)
			end
			return
		end
		local deadline = workspace:GetServerTimeNow() + 3
		player:SetAttribute("RunResumeAt", deadline)
		local resume = StealService.OnResumeChase
		if resume and carry.Boss then
			resume(player, carry.Boss.Zone, saved.Chaser, 3)
		end
		Net.Remotes.Effect:FireClient(player, "RunResume", deadline)
		task.delay(3, function()
			if player:GetAttribute("RunResumeAt") == deadline then
				player:SetAttribute("RunResumeAt", nil)
				if root.Parent then
					root.Anchored = false
				end
				player:SetAttribute("RunSaved", nil)
			end
		end)
	end)
end

local function onRunway(position: Vector3): boolean
	return position.Z > 0 and math.abs(position.X) < GameConfig.ArenaWidth / 2
end

local safeZoneToldAt: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

local function canHitCarrier(attacker: Player, victim: Player): boolean
	if
		attacker == victim
		or not carriers[victim]
		or attacker:GetAttribute("InRound")
		or victim:GetAttribute("InRound")
		or ((victim:GetAttribute("RunResumeAt") or 0) :: number) > workspace:GetServerTimeNow()
	then
		return false
	end
	local root, attackerRoot = rootPart(victim), rootPart(attacker)
	if not root or not attackerRoot or victim:GetAttribute("Tumbling") then
		return false
	end
	-- Knocking a coffin loose is a runway thing (on the way home): past the SAFE ZONE line, the
	-- plaza and the pens, nobody can, so the sign tells the truth. (CanHit only runs for a target
	-- that was really in reach of a swing or throw, so this is the moment to say why.)
	if not onRunway(root.Position) or not onRunway(attackerRoot.Position) then
		local now = os.clock()
		if now - (safeZoneToldAt[attacker] or 0) > 3 then
			safeZoneToldAt[attacker] = now
			Net.Notify(attacker, "Can't attack in the safe zone!", "bad")
		end
		return false
	end
	return true
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
		StealService.DropKnife(item, at, PenMode.Coffins())
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

-- The Drop button (Tsunami style): don't want it after all? A boss's knife goes straight back on
-- its wall (the chase ends, nothing lost); anything else lands at your feet.
function StealService.Drop(player: Player)
	if
		not carriers[player]
		or player:GetAttribute("InRound")
		or ((player:GetAttribute("RunResumeAt") or 0) :: number) > workspace:GetServerTimeNow()
	then
		return
	end
	local root = rootPart(player)
	endCarry(player, false, if root then root.Position else nil, "drop")
end

function StealService.ForceDrop(player: Player)
	local root = rootPart(player)
	endCarry(player, false, if root then root.Position else nil, "forced")
end

function StealService.Init()
	Net.Remotes.Drop.OnServerEvent:Connect(StealService.Drop)
	Net.Remotes.PlaceAt.OnServerEvent:Connect(function(player: Player, position: unknown)
		if typeof(position) == "Vector3" then
			StealService.PlaceAt(player, position)
		end
	end)
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
	carriedFolder = Instance.new("Folder")
	carriedFolder.Name = "CarriedItems"
	carriedFolder.Parent = dropFolder.Parent

	Players.PlayerRemoving:Connect(function(player)
		StealService.CancelSavedRun(player)
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
