--!strict
-- Each player gets a vault: a safe zone with a knife rack that pays cash every second.
-- Also owns character placement and walk speed, since both depend on where the player "lives".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local SignTheme = require(ReplicatedStorage.Shared.SignTheme)
local WorldSignModel = require(ReplicatedStorage.Shared.WorldSignModel)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local Net = require(script.Parent.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local Offers = require(script.Parent.Offers)
local Social = require(script.Parent.Social)
local MapService = require(script.Parent.MapService)
local Analytics = require(script.Parent.Analytics)
local CoffinModel = require(ReplicatedStorage.Shared.CoffinModel)
local CoffinState = require(ReplicatedStorage.Shared.CoffinState)
local PenMode = require(ReplicatedStorage.Shared.PenMode)
local PenWalls = require(script.Parent.PenWalls)
local KnifeHaze = require(ReplicatedStorage.Shared.KnifeHaze)

-- A knife as a character hopping around its pen (Shared/PenMode): Codex's character art if it has
-- one (Assets/KnifeCharacterAssets), else the plain knife standing on its pommel. Sized by rarity,
-- hazed by rarity, posed by client/PenKnives (tag PenKnife). Returns the model and the part its
-- nameplate hangs on (on top of its head, so it moves with the hops).
local characterAssets: any = nil
local function penKnife(
	item: string,
	parsed: Items.Item,
	base: MapService.BaseSite,
	slot: number,
	parent: Instance,
	since: number? -- (server time it came out of its coffin: it starts on its spot)
): (Model, BasePart)
	local scale = PenMode.Scale(parsed.Knife.Rarity) * (1 + (parsed.Size.Scale - 1) * 0.5)
	local floor = base.Folder:FindFirstChild("Floor") :: BasePart
	local floorTop = floor.Position + Vector3.new(0, floor.Size.Y / 2, 0)
	local model: Model? = nil
	if characterAssets == nil then
		local ok, loaded = pcall(function()
			return require(ReplicatedStorage.Shared.Assets.KnifeCharacterAssets) :: any
		end)
		characterAssets = if ok then loaded else false
	end
	if characterAssets then
		local ok, built =
			pcall(characterAssets.BuildCharacter, parsed.Name, nil, CFrame.new(floorTop), { Scale = scale })
		if ok then
			model = built
		end
	end
	if not model then
		-- (no character art yet: the knife itself, upright, its floor point under the pommel)
		local knife = KnifeModel.Build(item, true)
		KnifeModel.FitLength(knife, 2.4 * scale)
		local box, size = knife:GetBoundingBox()
		local root = Instance.new("Part")
		root.Name = "PenRoot"
		root.Size = Vector3.one * 0.2
		root.Transparency = 1
		root.Anchored = true
		root.CanCollide, root.CanQuery, root.CanTouch = false, false, false
		root.CFrame = CFrame.new(box.Position - Vector3.new(0, size.Y / 2, 0))
		root.Parent = knife
		knife.PrimaryPart = root
		knife:PivotTo(CFrame.new(floorTop))
		model = knife
	end
	local built = model :: Model
	local _, size = built:GetBoundingBox()
	local label = Instance.new("Part")
	label.Name = "LabelAnchor"
	label.Size = Vector3.one * 0.2
	label.Transparency = 1
	label.Anchored = true
	label.CanCollide, label.CanQuery, label.CanTouch = false, false, false
	label.CFrame = built:GetPivot() + Vector3.new(0, size.Y + 1.5, 0)
	label.Parent = built
	-- the pen it hops in, axis-aligned in the world (pens are turned 90 degrees: depth runs along X)
	built:SetAttribute("PenCentre", floorTop)
	built:SetAttribute(
		"PenHalf",
		Vector3.new(base.Bounds.MaxX - base.Bounds.MinX, 0, base.Bounds.MaxZ - base.Bounds.MinZ) / 2
	)
	built:SetAttribute("HopSeed", base.Index * 1000 + slot * 37)
	built:SetAttribute("HopScale", scale)
	-- (it roams round its own spot - where you put it down, where its coffin stood)
	built:SetAttribute("HopHome", base.SlotCFrames[slot].Position)
	built:SetAttribute("HopSince", since)
	built:SetAttribute("Rarity", parsed.Knife.Rarity)
	KnifeHaze.Add(built, parsed.Knife.Rarity)
	built:AddTag("PenKnife")
	built:AddTag("KnifeFace") -- (client/KnifeBlink)
	built.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	built.Parent = parent
	return built, label
end

local BaseService = {}

local owners: { [number]: Player } = {} -- base index -> player
local baseOf: { [Player]: MapService.BaseSite } = {}
local rackModels: { [Player]: Folder } = {}

-- Set by InventoryService: called when the owner uses a prompt on one of their mounted knives
BaseService.OnSellPrompt = nil :: ((Player, number) -> ())?
BaseService.OnEquipPrompt = nil :: ((Player, string) -> ())?
-- Set by StealService: the owner pressed Place on their next empty plate while carrying a knife
BaseService.OnPlacePrompt = nil :: ((Player, number) -> ())?
BaseService.OnOpenCoffin = nil :: ((Player, number) -> ())?
-- Set by UpgradeService: the owner pressed Upgrade Base at the sign by their gate
BaseService.OnUpgradeBase = nil :: ((Player) -> ())?

-- Rebirths multiply everything a vault earns
-- Consumable bookkeeping (for offers and boost expiry)
local hadSpeed: { [Player]: boolean } = {}
local padWalks: { [Player]: number } = {}
-- A knife fresh out of its coffin flies into you and waits in your hotbar (Steal an Egg) until you
-- tap where it goes in your pen. Not saved: leave and it's simply on its spot next time.
local hatching: { [Player]: { { Plate: number, Item: string } } } = {}
local hoppedIn: { [Player]: { [number]: number } } = {} -- plate -> server time it came home
local HATCH_FLIGHT = 1.7 -- (s: client Effects CoffinHatch - it stands there, hops, flies into you)
-- (is the knife on this plate the hatched one in your hand right now?)
local function heldOn(player: Player, plate: number): boolean
	local list = hatching[player]
	if list then
		for _, held in list do
			if held.Plate == plate then
				return true
			end
		end
	end
	return false
end
Players.PlayerRemoving:Connect(function(player)
	hadSpeed[player], padWalks[player] = nil, nil
	hatching[player], hoppedIn[player] = nil, nil
end)

function BaseService.IncomeMultiplier(player: Player): number
	local profile = DataService.Get(player)
	local multiplier = 1 + (if profile then profile.Rebirths * GameConfig.Rebirth.IncomeBonus else 0)
	-- Game passes (MonetizationService sets these attributes)
	if player:GetAttribute("Pass_DoubleCash") then
		multiplier *= 2
	end
	if player:GetAttribute("Pass_VIP") then
		multiplier *= 1.1
	end
	multiplier *= Social.FriendsMultiplier(player)
	-- 2x Cash Potion (Robux consumable)
	if profile and DataService.BoostActive(profile, "Cash") then
		multiplier *= GameConfig.Consumables.CashMultiplier
	end
	return multiplier
end

function BaseService.RackIncome(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	local total = 0
	for i, item in profile.Knives do
		if (profile.Plates[i] or i) > profile.Slots then
			continue -- (in the bag, not on show: earns nothing yet)
		end
		if not DataService.IsSealedIndex(profile, i) then -- (still in its coffin: earns nothing yet)
			total += Items.Income(item)
		end
	end
	return total * BaseService.IncomeMultiplier(player)
end
local rackIncome = BaseService.RackIncome

-- THE knife a player fights with, everywhere (the hub Tool, the Murderer's weapon, the power you
-- use in rounds, the one that can't be stolen): the one they chose (Equipped) if they still own it,
-- otherwise automatically their best POWER (its tier), then the hardest hitter. Nobody
-- has to equip anything to bring their best power into a round. (Each caller used to pick its own
-- "best" - by damage or by income - so the weapon and the power could be from different knives.)
-- Frozen while you're in a round, so a prize or a Sheriff steal never swaps it mid-round.
local roundPick: { [Player]: string } = {}
Players.PlayerRemoving:Connect(function(player)
	roundPick[player] = nil
end)
function BaseService.BestKnife(player: Player): string?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	if player:GetAttribute("InRound") then
		local kept = roundPick[player]
		if kept then
			return kept
		end
	end
	if #profile.Knives == 0 then
		return nil
	end
	local pick: string?
	local equippedAt = if profile.Equipped ~= "" then table.find(profile.Knives, profile.Equipped) else nil
	if equippedAt and not DataService.IsSealedIndex(profile, equippedAt) then
		pick = profile.Equipped
	else
		local bestDamage = -1
		for i, item in profile.Knives do
			if DataService.IsSealedIndex(profile, i) then
				continue -- (can't fight with a knife still in its coffin)
			end
			local damage = Items.Damage(item)
			if damage > bestDamage then
				pick, bestDamage = item, damage
			end
		end
	end
	if pick and not player:GetAttribute("InRound") then
		roundPick[player] = pick
	end
	return pick
end

-- The knife a player fights with can never be stolen or looted - nobody loses their weapon
function BaseService.ProtectedItem(player: Player): string?
	return BaseService.BestKnife(player)
end

function BaseService.OwnerOf(base: MapService.BaseSite): Player?
	return owners[base.Index]
end

-- The vault this point is in (and who owns it)
function BaseService.BaseAt(position: Vector3): (MapService.BaseSite?, Player?)
	for _, base in MapService.Bases do
		if MapService.InBounds(base.Bounds, position) then
			return base, owners[base.Index]
		end
	end
	return nil, nil
end

-- Walls and gate for the owner's tier (tier 1 for an empty vault)
function BaseService.RefreshWalls(base: MapService.BaseSite)
	local owner = owners[base.Index]
	local profile = owner and DataService.Get(owner)
	local tier = 1
	local penDepth = PenMode.Depth(if profile then profile.Slots else GameConfig.StartingSlots)
	MapService.FitPen(base, penDepth)
	local built = PenWalls.Build(base.WallFolder, base.Frame, base.Color, tier, penDepth)
	base.Gate = built.Gate
	base.Blocker = built.Blocker
	base.Blocker:SetAttribute("Owner", if owner then owner.UserId else nil)
	base.Blocker:SetAttribute("OwnerName", if owner then owner.DisplayName else nil)
	-- (no wall upgrades any more: vaults are open, Tsunami style)
	-- The pen room sign is its own click target.
	local function signClick(signName: string, partName: string, clickName: string, onClick: ((Player) -> ())?)
		local sign = base.Folder:FindFirstChild(signName)
		local part = sign and sign:FindFirstChild(partName) :: BasePart?
		if not part then
			return
		end
		local old = part:FindFirstChild(clickName)
		if old then
			old:Destroy()
		end
		if owner then
			local click = Instance.new("ClickDetector")
			click.Name = clickName
			click.MaxActivationDistance = WorldSignModel.UpgradeRange
			click:SetAttribute("Owner", owner.UserId)
			click.MouseClick:Connect(function(player)
				if player == owner and not player:GetAttribute("InRound") and onClick then
					onClick(player)
				end
			end)
			click.Parent = part
		end
	end
	signClick("UpgradeSign", "Board", "UpgradeBase", function(player)
		if BaseService.OnUpgradeBase then
			BaseService.OnUpgradeBase(player)
		end
	end)
	-- The vault's sign rides on top of its back wall
	base.SignPart.CFrame = base.Frame * CFrame.new(0, built.BackHeight + 2.4, -22)
	WorldSignModel.MoveAttached(base.SignPart)
end

-- A pen plate at the spot its owner tapped (profile.Spots), kept inside the pen's grass
function BaseService.ApplySpot(player: Player, plate: number)
	local base = baseOf[player]
	local profile = DataService.Get(player)
	local spot = profile and profile.Spots[tostring(plate)]
	local pad = base and base.SlotPads[plate]
	if not base or not spot or not pad then
		return
	end
	local floor = base.Folder:FindFirstChild("Floor") :: BasePart?
	local x, z = spot[1], spot[2]
	if floor then
		local centre = base.Frame:PointToObjectSpace(floor.Position)
		x = math.clamp(x, centre.X - floor.Size.X / 2 + 2, centre.X + floor.Size.X / 2 - 2)
		z = math.clamp(z, centre.Z - floor.Size.Z / 2 + 2, centre.Z + floor.Size.Z / 2 - 2)
	end
	pad.CFrame = base.Frame * CFrame.new(x, 0.7, z)
	base.SlotCFrames[plate] = base.Frame * CFrame.new(x, 4.2, z)
end

function BaseService.GetBase(player: Player): MapService.BaseSite?
	return baseOf[player]
end

function BaseService.IsInOwnBase(player: Player, position: Vector3): boolean
	local base = baseOf[player]
	return base ~= nil and MapService.InBounds(base.Bounds, position)
end

function BaseService.IsInAnyBase(position: Vector3): boolean
	for _, base in MapService.Bases do
		if MapService.InBounds(base.Bounds, position, 2) then
			return true
		end
	end
	return false
end

-- Where a murder round pulled someone from: the next trip "home" goes back there instead
-- (whether they survived the round or respawned after dying in it). The rule: a round never
-- moves you in the hub.
local returnSpots: { [Player]: CFrame? } = {}
function BaseService.SetReturnSpot(player: Player, spot: CFrame?)
	returnSpots[player] = spot
end
Players.PlayerRemoving:Connect(function(player)
	returnSpots[player] = nil
end)

-- Set by StealService: called once someone is back at their pre-round spot (hands back a carry)
BaseService.OnReturnedHome = nil :: ((player: Player) -> ())?

-- Spawning: stream the area round the spawn to the player's client FIRST, so they never drop into
-- a map that hasn't loaded yet (falling out of the sky, Roblox's "Gameplay Paused" box)
function BaseService.LoadCharacter(player: Player)
	local spawnAt = player.RespawnLocation
	if spawnAt then
		pcall(player.RequestStreamAroundAsync, player, spawnAt.Position, 6)
	end
	if player.Parent then
		player:LoadCharacterAsync()
	end
end

function BaseService.TeleportHome(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local base = baseOf[player]
	local destination = if base then base.Spawn else MapService.LobbySpawn
	local spot = returnSpots[player]
	local restored = false
	if spot and not player:GetAttribute("InRound") then
		returnSpots[player] = nil
		destination = spot
		restored = true
	end
	-- (no early jump to the spot: arriving before it has streamed in is what showed Roblox's
	-- loading spinner on the way back from a round; the screen fade covers the short wait)
	task.spawn(function()
		-- Load the vault on their client first so StreamingEnabled doesn't pause them on arrival,
		-- but never wait long: a slow stream must not leave them stranded
		local streamed = false
		task.spawn(function()
			pcall(player.RequestStreamAroundAsync, player, destination.Position, 3)
			streamed = true
		end)
		local started = os.clock()
		while not streamed and os.clock() - started < 1.5 do
			task.wait()
		end
		-- Move them, and make sure it stuck (their client owns the character and can fight a move)
		for _ = 1, 3 do
			if not character.Parent then
				return
			end
			character:PivotTo(destination)
			task.wait(0.4)
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root or (root.Position - destination.Position).Magnitude < 30 then
				-- (hands back anything kept for them over a round - restored spot or their pen)
				local _ = restored
				if BaseService.OnReturnedHome then
					BaseService.OnReturnedHome(player)
				end
				return
			end
		end
	end)
end

-- (Knife trails are bought - GameConfig.Trails, profile.TrailLevel - and drawn by client/KnifeTrails)

-- Single source of truth for walk speed: round > carrying > upgrades
function BaseService.RefreshWalkSpeed(player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local profile = DataService.Get(player)
	local speed = GameConfig.WalkSpeedFor(if profile then profile.Speed else 0)
	-- Slow mode: plain walking speed, for getting around your vault without overshooting
	if player:GetAttribute("SlowMode") then
		speed = GameConfig.WalkSpeedFor(0)
	end
	if player:GetAttribute("InRound") then
		speed = if player:GetAttribute("Role") == "Murderer"
			then (if player:GetAttribute("KnifeOut") then GameConfig.MurdererWalkSpeed else GameConfig.RoundWalkSpeed)
			else GameConfig.RoundWalkSpeed
		-- Sneakers and knife perks (both set by RoundService, cleared when the round ends)
		speed += (player:GetAttribute("RoundSpeedBonus") or 0) :: number
	else
		-- Speed Potion (Robux consumable): hub only, never in rounds
		if profile and DataService.BoostActive(profile, "Speed") and not player:GetAttribute("SlowMode") then
			speed *= GameConfig.Consumables.SpeedMultiplier
		end
		if player:GetAttribute("Carrying") then
			speed *= GameConfig.CarrySpeedMultiplier
		end
	end
	-- Stunned (a Murderer's Flash / Snare)
	local stunnedUntil = player:GetAttribute("StunnedUntil")
	if type(stunnedUntil) == "number" and workspace:GetServerTimeNow() < stunnedUntil then
		speed = 0
	end
	humanoid.WalkSpeed = speed
end

-- The label floating over a knife on its pedestal (Steal a Brainrot style): its name in its
-- colour, its rarity, and what it earns

-- The aura a mounted knife gives off. Better knives (rarity, mutation, size) get a wider, more
-- dramatic upright flame. The floor ring still shows the unchanged slowdown radius.

local function makePrompt(parent: Instance, props: { [string]: any }): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.HoldDuration = 0
	p.MaxActivationDistance = 8
	p.RequiresLineOfSight = false
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

-- Carrying a knife right now
local function carryingKnife(player: Player): boolean
	return type(player:GetAttribute("Carrying")) == "string"
end

-- Worth a second tap before it's sold: rare knives, mutations, big sizes

-- Tsunami-style sell sign: a thin board standing between the plate and its cash pad, leaning back a
-- little, "SELL $11K". Tap / click it to sell (precious knives ask for a second tap).
local sellSignPressed: { [Instance]: (Player) -> () } = {}

function BaseService.RefreshRack(player: Player)
	local base = baseOf[player]
	local profile = DataService.Get(player)
	if not base or not profile then
		return
	end
	-- Room in the pen again (sold one / bigger pen): knives waiting in the bag move in
	DataService.Update(player, function(p)
		for i in p.Knives do
			if (p.Plates[i] or i) > p.Slots then
				local free = DataService.FreePlate(p)
				if not free then
					break
				end
				p.Plates[i] = free
			end
		end
	end)
	local folder = rackModels[player]
	folder:ClearAllChildren()
	for _, pad in base.SlotPads do
		for _, old in pad:GetChildren() do
			if old:IsA("ProximityPrompt") then
				old:Destroy()
			end
		end
	end
	-- Bought a floor: the vault grows (and its frame with it)
	-- (a pen bought longer, or a vault a floor taller: rebuild the walls to fit)
	if base.Blocker:GetAttribute("PenDepth") ~= PenMode.Depth(profile.Slots) then
		BaseService.RefreshWalls(base)
	end
	-- Every plate where its owner put it down (profile.Spots; after the walls, which re-lay the pen)
	for plate in base.SlotPads do
		BaseService.ApplySpot(player, plate)
	end
	local multiplier = BaseService.IncomeMultiplier(player)
	for slot, pad in base.SlotPads do
		local rim = base.SlotRims[slot]
		local unlocked = slot <= profile.Slots
		-- (a pen has no plates: knives and coffins stand on the grass; the pad stays as an
		-- invisible anchor for prompts)
		for _, part in { pad, rim } do
			part.Transparency = 1
			for _, d in part:GetDescendants() do
				if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
					(d :: any).Transparency = 1
				end
			end
		end
		-- Knives keep their own plate (profile.Plates), so selling one never shuffles the rest
		local index = DataService.IndexOnPlate(profile, slot)
		local item = if index then profile.Knives[index] else nil
		local parsed = item and Items.Parse(item)
		local readyAt = if index then DataService.SealedReadyAt(profile, slot) else nil
		if unlocked and index and item and parsed and readyAt then
			-- Still in its coffin (CoffinService): the coffin, its countdown, "Open now" for the owner.
			-- No income, no equip / sell / steal until it opens. (client/Coffins: countdown, rattle)
			local slotCF = base.SlotCFrames[slot]
			local grass = base.Folder:FindFirstChild("Floor") :: BasePart?
			local floorY = if grass then grass.Position.Y + grass.Size.Y / 2 else pad.Position.Y + pad.Size.Y / 2
			local floorCF = CFrame.new(pad.Position.X, floorY, pad.Position.Z) * slotCF.Rotation
			local coffin = CoffinModel.Build(parsed.Knife.Rarity, floorCF, item)
			coffin:SetAttribute("Owner", player.UserId)
			coffin:SetAttribute("Plate", slot)
			-- (server time, so every client counts down to the same moment)
			coffin:SetAttribute("OpensAt", workspace:GetServerTimeNow() + (readyAt - os.time()))
			-- (round-based: how many murder rounds are left - the label shows that, not a clock)
			local sealed = DataService.SealedEntry(profile, slot)
			coffin:SetAttribute("RoundsLeft", if sealed and sealed.Rounds then math.ceil(sealed.Rounds) else nil)
			local ready = sealed ~= nil and CoffinState.Ready(sealed.Rounds, sealed.ReadyAt, os.time())
			coffin:SetAttribute("Ready", ready)
			coffin:AddTag("Coffin")
			-- (whole or not at all: client/Coffins swings and shatters every lid piece it finds)
			coffin.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			coffin.Parent = folder
			local open = makePrompt(pad, {
				ActionText = if ready then "READY! Open" else "Unlock R$19",
				ObjectText = `{parsed.Knife.Rarity} Coffin`,
			})
			open:SetAttribute("Owner", player.UserId)
			open:SetAttribute("CoffinPlate", slot)
			local body = coffin.PrimaryPart :: BasePart
			body.CanQuery = true
			local click = Instance.new("ClickDetector")
			click.MaxActivationDistance = 18
			click.Parent = body
			click.MouseClick:Connect(function(who)
				local root = who.Character and who.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if
					who == player
					and root
					and (root.Position - body.Position).Magnitude <= 20
					and BaseService.OnOpenCoffin
				then
					BaseService.OnOpenCoffin(who, slot)
				end
			end)
		elseif
			unlocked
			and index
			and item
			and parsed
			and not heldOn(player, slot) -- (in your hand right now)
		then
			-- A pen: the knife is a character hopping around (equip / sell from the Knives menu)
			local since = hoppedIn[player] and hoppedIn[player][slot]
			local penModel, labelAnchor = penKnife(item, parsed, base, slot, folder, since)
			-- (no name tags from afar - Steal an Egg shows only money popping off its creatures,
			-- client/PenKnives; the tag shows up close)
			local perSecond = Items.Income(item) * multiplier
			penModel:SetAttribute("Income", perSecond)
			local tag = SignTheme.knifeLabel(
				folder,
				labelAnchor,
				Items.DisplayName(item),
				parsed.Knife.Rarity,
				Knives.RarityColors[parsed.Knife.Rarity],
				`{Format.Cash(math.floor(perSecond * 10 + 0.5) / 10)}/s`,
				nil,
				40 -- (only up close: from afar a pen is just its knives and their money pops, Steal an Egg)
			)
			-- Steal an Egg's labels: the same small size on screen, shown only when you're close
			tag.Size = UDim2.fromOffset(130, 52)
		end
	end
	player:SetAttribute("Income", rackIncome(player))
	-- Your waiting coffins for the Coffins panel (client/CoffinList): "plate,rarity,roundsLeft,opensAt;..."
	-- (roundsLeft -1 = a plain timer; opensAt in server time, the offline fallback / timer)
	local coffins = {}
	local readyCount = 0
	for _, entry in profile.Sealed do
		local index = DataService.IndexOnPlate(profile, entry.Plate)
		local parsed = if index then Items.Parse(profile.Knives[index]) else nil
		if parsed then
			if CoffinState.Ready(entry.Rounds, entry.ReadyAt, os.time()) then
				readyCount += 1
			end
			local opensAt = workspace:GetServerTimeNow() + (entry.ReadyAt - os.time())
			table.insert(
				coffins,
				`{entry.Plate},{parsed.Knife.Rarity},{if entry.Rounds then math.ceil(entry.Rounds) else -1},{math.floor(
					opensAt
				)}`
			)
		end
	end
	player:SetAttribute("CoffinList", table.concat(coffins, ";"))
	player:SetAttribute("CoffinsReady", readyCount)
	-- (the Knives menu hides these: a coffin's knife stays a secret until it opens)
	local sealedKnives = {}
	for i in profile.Knives do
		if DataService.IsSealedIndex(profile, i) then
			table.insert(sealedKnives, i)
		end
	end
	player:SetAttribute("SealedKnives", table.concat(sealedKnives, ","))
end

local function claimBase(player: Player)
	for i, base in MapService.Bases do
		if not owners[i] then
			owners[i] = player
			baseOf[player] = base
			base.Sign.Text = `{player.DisplayName}'s Pen`
			local folder = Instance.new("Folder")
			folder.Name = `Rack_{player.Name}`
			folder.Parent = workspace:FindFirstChild("Map")
			rackModels[player] = folder
			player:SetAttribute("VaultIndex", i)
			-- You spawn straight into your vault (no stop at the lobby plate first): an invisible
			-- SpawnLocation on the vault's spawn spot is your RespawnLocation
			local map = workspace:FindFirstChild("Map") or workspace
			local spawnPad = map:FindFirstChild(`VaultSpawn{i}`) :: SpawnLocation?
			if not spawnPad then
				local made = Instance.new("SpawnLocation")
				made.Name = `VaultSpawn{i}`
				made.Anchored = true
				made.CanCollide = false
				made.CanQuery = false
				made.CanTouch = false
				made.Transparency = 1
				made.Size = Vector3.new(4, 1, 4)
				made.CFrame = base.Spawn - Vector3.new(0, 3.3, 0)
				made.Duration = 0
				made.Neutral = true
				made.Parent = map
				spawnPad = made
			end
			player.RespawnLocation = spawnPad :: SpawnLocation
			-- The empty plates' "Place Knife" prompts only show while carrying a knife
			player:GetAttributeChangedSignal("Carrying"):Connect(function()
				local carrying = carryingKnife(player)
				for _, pad in base.SlotPads do
					for _, prompt in pad:GetChildren() do
						if prompt:IsA("ProximityPrompt") and prompt:GetAttribute("Place") then
							prompt.Enabled = carrying
						end
					end
				end
			end)
			BaseService.RefreshRack(player)
			BaseService.RefreshWalls(base)
			return
		end
	end
	warn(`[BaseService] no free base for {player.Name} - set the place's max players to {MapService.MaxBases}`)
end

local function releaseBase(player: Player)
	local base = baseOf[player]
	if base then
		owners[base.Index] = nil
		base.Sign.Text = "Empty Pen"
		for _, pad in base.SlotPads do
			pad.Color = Color3.fromRGB(40, 38, 46)
			for _, prompt in pad:GetChildren() do
				if prompt:IsA("ProximityPrompt") then
					prompt:Destroy()
				end
			end
		end
		for _, rim in base.SlotRims do
			rim.Color = Color3.fromRGB(30, 28, 34)
			rim.Material = Enum.Material.SmoothPlastic
		end
	end
	if rackModels[player] then
		rackModels[player]:Destroy()
	end
	baseOf[player] = nil
	rackModels[player] = nil
	if base then
		BaseService.RefreshWalls(base)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	character:WaitForChild("HumanoidRootPart")
	task.defer(function()
		if not player:GetAttribute("InRound") then
			BaseService.TeleportHome(player)
		end
		BaseService.RefreshWalkSpeed(player)
	end)
end

local function hatchTool(player: Player, plate: number): Tool?
	for _, container in { player.Character, player:FindFirstChildOfClass("Backpack") } :: { Instance? } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("HatchPlate") == plate then
					return child
				end
			end
		end
	end
	return nil
end

-- (gives the Tool if it's missing - a respawn or a round empties the backpack)
local function giveHatchTool(player: Player, held: { Plate: number, Item: string }, equip: boolean)
	if hatchTool(player, held.Plate) or player:GetAttribute("InRound") then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not humanoid or not backpack then
		return
	end
	local tool = KnifeModel.BuildTool(held.Item)
	tool:SetAttribute("HatchPlate", held.Plate) -- (client/PlaceTap: tap your pen to put it down)
	tool.ToolTip = "Tap your pen to put it down"
	tool.Parent = backpack
	if equip and not player:GetAttribute("Carrying") then
		humanoid:EquipTool(tool)
	end
end

-- CoffinService.Reveal: the knife pops out, flies into you (client Effects CoffinHatch) and waits
-- in your hotbar until you tap where it goes in your pen (Steal an Egg)
function BaseService.HoldHatched(player: Player, plate: number, item: string)
	local list = hatching[player] or {}
	hatching[player] = list
	local held = { Plate = plate, Item = item }
	table.insert(list, held)
	task.delay(HATCH_FLIGHT, function()
		if player.Parent and table.find(list, held) then
			giveHatchTool(player, held, true)
			player:SetAttribute("HoldingHatch", #list)
		end
	end)
	BaseService.RefreshRack(player)
end

-- client/PlaceTap -> StealService.PlaceAt: put the hatched knife in your hand down where you tapped
function BaseService.PlaceHatched(player: Player, position: Vector3)
	local list = hatching[player]
	local base = baseOf[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local tool = character and character:FindFirstChildOfClass("Tool")
	local plate = tool and tool:GetAttribute("HatchPlate")
	if not list or not base or not root or not tool or type(plate) ~= "number" then
		return
	end
	if not BaseService.IsInOwnBase(player, root.Position) or not MapService.InBounds(base.Bounds, position, -2) then
		return
	end
	local index: number? = nil
	for i, held in list do
		if held.Plate == plate then
			index = i
		end
	end
	if not index then
		return
	end
	local held = table.remove(list, index) :: { Plate: number, Item: string }
	player:SetAttribute("HoldingHatch", if #list > 0 then #list else nil)
	local here = base.Frame:PointToObjectSpace(position)
	DataService.Update(player, function(p)
		p.Spots[tostring(plate)] = { math.floor(here.X * 10) / 10, math.floor(here.Z * 10) / 10 }
	end)
	BaseService.ApplySpot(player, plate)
	local hand = character and character:FindFirstChild("RightHand") :: BasePart?
	local from = if hand then hand.Position else root.Position
	tool:Destroy()
	if character then
		Net.Animate(character, "Pickup")
	end
	local FLIGHT = 0.5
	local perPlate = hoppedIn[player] or {}
	hoppedIn[player] = perPlate
	perPlate[plate] = workspace:GetServerTimeNow() + FLIGHT + 1 -- (lands, then a beat before it hops off)
	Net.Remotes.Effect:FireAllClients("HatchHome", from, held.Item, base.SlotCFrames[plate].Position, FLIGHT)
	task.delay(FLIGHT, function()
		if player.Parent then
			BaseService.RefreshRack(player)
		end
	end)
end

function BaseService.Init()
	-- Hatched knives in hand: still yours? still in your hotbar (respawns / rounds empty it)?
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player, list in hatching do
				local profile = DataService.Get(player)
				for i = #list, 1, -1 do
					local held = list[i]
					local index = profile and DataService.IndexOnPlate(profile, held.Plate)
					if not profile or not index or profile.Knives[index] ~= held.Item then
						table.remove(list, i) -- (sold / traded / stolen meanwhile)
						local tool = hatchTool(player, held.Plate)
						if tool then
							tool:Destroy()
						end
					elseif player:GetAttribute("InRound") then
						-- (a murder round: only the round's weapons in your hotbar; it's back after)
						local tool = hatchTool(player, held.Plate)
						if tool then
							tool:Destroy()
						end
					else
						giveHatchTool(player, held, false)
					end
				end
				player:SetAttribute("HoldingHatch", if #list > 0 then #list else nil)
			end
		end
	end)
	Net.Remotes.SellSign.OnServerEvent:Connect(function(player: Player, sign: unknown)
		local pressed = typeof(sign) == "Instance" and sellSignPressed[sign :: Instance] or nil
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if pressed and root and ((sign :: BasePart).Position - root.Position).Magnitude < 30 then
			pressed(player)
		end
	end)
	Net.Remotes.SlowMode.OnServerEvent:Connect(function(player: Player, on: unknown)
		player:SetAttribute("SlowMode", if on == true then true else nil)
		BaseService.RefreshWalkSpeed(player)
	end)
	-- The hub floats in space: anyone who falls off the island is caught and sent home (whatever
	-- they were carrying drops where they fell, like any other fall)
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				-- (a dead body's loose root part sinks through the floor: that's not a fall, and
				-- rescuing it would use up their after-round return spot)
				if
					root
					and humanoid
					and humanoid.Health > 0
					and root.Position.Y < -45
					and not player:GetAttribute("InRound")
				then
					root.AssemblyLinearVelocity = Vector3.zero
					BaseService.TeleportHome(player)
				end
			end
		end
	end)
	DataService.PlayerLoaded:Connect(function(player: Player)
		claimBase(player)
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end)
	local function watchCharacters(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end
	Players.PlayerAdded:Connect(watchCharacters)
	for _, player in Players:GetPlayers() do
		watchCharacters(player)
	end
	Players.PlayerRemoving:Connect(releaseBase)
	DataService.Changed:Connect(function(player: Player, _profile: DataService.Profile)
		BaseService.RefreshWalkSpeed(player)
	end)
	-- The equipped knife's plaque glows white
	local function watchEquipped(player: Player)
		player:GetAttributeChangedSignal("Equipped"):Connect(function()
			BaseService.RefreshRack(player)
		end)
	end
	Players.PlayerAdded:Connect(watchEquipped)
	for _, player in Players:GetPlayers() do
		watchEquipped(player)
	end

	-- Every knife earns onto its own cash pad once a second (Tsunami style); the pads show what's
	-- waiting
	task.spawn(function()
		while true do
			task.wait(1)
			for player, base in baseOf do
				local profile = DataService.Get(player)
				if not profile then
					continue
				end
				local multiplier = BaseService.IncomeMultiplier(player)
				-- A Speed Potion just ended: back to normal speed
				local speedOn = DataService.BoostActive(profile, "Speed")
				if speedOn ~= (hadSpeed[player] or false) then
					hadSpeed[player] = speedOn
					BaseService.RefreshWalkSpeed(player)
				end
				DataService.Update(player, function(p)
					for index, item in p.Knives do
						local plate = p.Plates[index] or index
						if plate <= p.Slots and not DataService.SealedReadyAt(p, plate) then
							p.Pending[plate] = (p.Pending[plate] or 0) + Items.Income(item) * multiplier
						end
					end
				end)
				local pendingTotal = 0
				for slot, label in base.CashLabels do
					local waiting = profile.Pending[slot] or 0
					base.CashPads[slot]:SetAttribute("Waiting", if slot <= profile.Slots then waiting else 0)
					label.Text = if waiting > 0 and slot <= profile.Slots then Format.Cash(waiting) else ""
					if slot <= profile.Slots then
						pendingTotal += waiting
					end
				end
				-- (client/Guide: "Grab your money!" when it's worth the walk)
				player:SetAttribute("PendingCash", math.floor(pendingTotal))
			end
		end
	end)

	-- Walking over a cash pad collects it (only the owner's own pads)
	task.spawn(function()
		while true do
			task.wait(0.15)
			for player, base in baseOf do
				local profile = DataService.Get(player)
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not profile or not root or player:GetAttribute("InRound") then
					continue
				end
				-- Auto Collect pass: every pad empties itself, wherever you are
				-- (or the one-visit Robux version: SessionAutoCollect, never saved)
				local auto = player:GetAttribute("Pass_AutoCollect") == true
					or player:GetAttribute("SessionAutoCollect") == true
				if not auto and not MapService.InBounds(base.Bounds, root.Position, 2) then
					continue
				end
				-- a pen: being anywhere inside it collects everything (Steal an Egg); no pads to walk over
				for slot, pad in base.CashPads do
					local waiting = profile.Pending[slot] or 0
					if waiting <= 0 or not pad.Parent or not pad:IsDescendantOf(workspace) then
						continue
					end
					DataService.Update(player, function(p)
						p.Pending[slot] = 0
					end)
					pad:SetAttribute("Waiting", 0)
					DataService.AddCash(player, waiting, "income")
					Analytics.Milestone(player, "cash_collected")
					Analytics.Count(player, if auto then "pad_auto" else "pad_walks")
					base.CashLabels[slot].Text = ""
					player:SetAttribute(
						"PendingCash",
						math.max(0, ((player:GetAttribute("PendingCash") or 0) :: number) - math.floor(waiting))
					)
					Net.Remotes.Effect:FireClient(player, "CashBurst", pad.Position, waiting, auto)
					-- Lots of pad-walking this visit: offer to do it for them
					if not auto then
						padWalks[player] = (padWalks[player] or 0) + 1
						if padWalks[player] % 15 == 0 then
							Offers.Show(
								player,
								"CollectSession",
								"Tired of walking over every pad? Collect everything automatically this visit."
							)
						end
					end
				end
			end
		end
	end)
end

return BaseService
