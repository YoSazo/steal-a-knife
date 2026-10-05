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
local KnifeAura = require(ReplicatedStorage.Shared.KnifeAura)
local Net = require(script.Parent.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local Fuel = require(script.Parent.Fuel)
local Offers = require(script.Parent.Offers)
local ServerEvents = require(script.Parent.ServerEvents)
local Social = require(script.Parent.Social)
local MapService = require(script.Parent.MapService)
local Analytics = require(script.Parent.Analytics)
local VaultWalls = require(script.Parent.VaultWalls)
local VaultModel = require(ReplicatedStorage.Shared.VaultModel)

local BaseService = {}

local owners: { [number]: Player } = {} -- base index -> player
local baseOf: { [Player]: MapService.BaseSite } = {}
local rackModels: { [Player]: Folder } = {}

-- Set by InventoryService: called when the owner uses a prompt on one of their mounted knives
BaseService.OnSellPrompt = nil :: ((Player, number) -> ())?
BaseService.OnEquipPrompt = nil :: ((Player, string) -> ())?
-- Set by RaidService: someone held "Steal" on a knife on another player's plate (Blood Moon)
BaseService.OnStealPrompt = nil :: ((thief: Player, owner: Player, item: string) -> ())?
-- Set by RaidService: a vault's walls were rebuilt (new tier, or the vault changed hands)
BaseService.OnWallsBuilt = nil :: ((MapService.BaseSite, Player?) -> ())?
BaseService.OnUpgradeWalls = nil :: ((Player) -> ())?
-- Set by StealService: the owner pressed Place on their next empty plate while carrying a knife
BaseService.OnPlacePrompt = nil :: ((Player, number) -> ())?
-- Set by UpgradeService: the owner pressed Upgrade Base at the sign by their gate
BaseService.OnUpgradeBase = nil :: ((Player) -> ())?

-- Rebirths multiply everything a vault earns
-- Consumable bookkeeping (for offers and boost expiry)
local trainedFor: { [Player]: number } = {}
local hadBoost: { [Player]: boolean } = {}
local hadSpeed: { [Player]: boolean } = {}
local padWalks: { [Player]: number } = {}
local trainingSince: { [Player]: number } = {} -- analytics: how long each wheel session lasts
Players.PlayerRemoving:Connect(function(player)
	trainedFor[player], hadBoost[player], hadSpeed[player], padWalks[player] = nil, nil, nil, nil
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
	-- 🔥 Heat from playing both games, friends playing with you, and the server's Cash Rush
	multiplier *= Fuel.IncomeMultiplier(player) * Social.FriendsMultiplier(player)
	if ServerEvents.Active("CashRush") then
		multiplier *= 2
	end
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
		if i > profile.Slots then
			break
		end
		total += Items.Income(item)
	end
	return total * BaseService.IncomeMultiplier(player)
end
local rackIncome = BaseService.RackIncome

-- The knife a player fights with (equipped, or their hardest-hitting one) can never be stolen or
-- looted - nobody loses their weapon
function BaseService.ProtectedItem(player: Player): string?
	local profile = DataService.Get(player)
	if not profile or #profile.Knives == 0 then
		return nil
	end
	if profile.Equipped ~= "" and table.find(profile.Knives, profile.Equipped) then
		return profile.Equipped
	end
	local best, bestDamage = nil, -1
	for _, item in profile.Knives do
		local damage = Items.Damage(item)
		if damage > bestDamage then
			best, bestDamage = item, damage
		end
	end
	return best
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
	local tier = if profile then profile.WallLevel else 1
	local floors = if profile then GameConfig.FloorsFor(profile.Slots) else 1
	MapService.SetFloors(base, floors)
	local built = VaultWalls.Build(base.WallFolder, base.Frame, base.Color, tier, floors)
	MapService.SetVaultTier(base, tier)
	base.Gate = built.Gate
	base.Blocker = built.Blocker
	base.Blocker:SetAttribute("Owner", if owner then owner.UserId else nil)
	base.Blocker:SetAttribute("OwnerName", if owner then owner.DisplayName else nil)
	-- (no wall upgrades any more: vaults are open, Tsunami style)
	-- The Upgrade Base sign by the gate: the owner buys the next floor there
	local upgradeSign = base.Folder:FindFirstChild("UpgradeSign")
	local board = upgradeSign and upgradeSign:FindFirstChild("Board") :: BasePart?
	if board then
		local old = board:FindFirstChild("UpgradeBase")
		if old then
			old:Destroy()
		end
		if owner then
			-- Same as the sell sign: click the sign itself (its green pill is the button), no
			-- separate hold-E prompt to explain.
			local click = Instance.new("ClickDetector")
			click.Name = "UpgradeBase"
			click.MaxActivationDistance = 28
			click:SetAttribute("Owner", owner.UserId)
			click.MouseClick:Connect(function(player)
				if player == owner and not player:GetAttribute("InRound") and BaseService.OnUpgradeBase then
					BaseService.OnUpgradeBase(player)
				end
			end)
			click.Parent = board
		end
	end
	-- The vault's sign rides on top of its back wall
	base.SignPart.CFrame = base.Frame * CFrame.new(0, built.BackHeight + 2.4, -22)
	WorldSignModel.MoveAttached(base.SignPart)
	if BaseService.OnWallsBuilt then
		BaseService.OnWallsBuilt(base, owner)
	end
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
	if restored then
		-- Straight there (no frame at the vault spawn first); the stream below still loads it
		character:PivotTo(destination)
	end
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
				if restored and BaseService.OnReturnedHome then
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
		speed += (player:GetAttribute("PerkSpeed") or 0) :: number
		speed += (player:GetAttribute("PowerSpeed") or 0) :: number -- Rush (an Innocent power)
	else
		-- Speed Potion (Robux consumable): hub only, never in rounds
		if profile and DataService.BoostActive(profile, "Speed") and not player:GetAttribute("SlowMode") then
			speed *= GameConfig.Consumables.SpeedMultiplier
		end
		if player:GetAttribute("Carrying") then
			speed *= GameConfig.CarrySpeedMultiplier
		end
		-- Pushing through the aura of someone else's powerful knives
		local aura = player:GetAttribute("AuraSlow")
		if type(aura) == "number" then
			speed *= aura
		end
	end
	-- Caught in a bear trap
	local stunnedUntil = player:GetAttribute("StunnedUntil")
	if type(stunnedUntil) == "number" and workspace:GetServerTimeNow() < stunnedUntil then
		speed = 0
	end
	humanoid.WalkSpeed = speed
end

-- The label floating over a knife on its pedestal (Steal a Brainrot style): its name in its
-- colour, its rarity, and what it earns
local function nameplate(parent: Instance, adornee: BasePart, item: string, perSecond: number)
	local parsed = Items.Parse(item) :: Items.Item
	local perk = parsed.Perk and GameConfig.Perks[parsed.Perk]
	SignTheme.knifeLabel(
		parent,
		adornee,
		Items.DisplayName(item),
		parsed.Knife.Rarity,
		Knives.RarityColors[parsed.Knife.Rarity],
		`{Format.Cash(math.floor(perSecond * 10 + 0.5) / 10)}/s`,
		if perk then `🔪 {perk.DisplayName}` else nil,
		45
	)
end

-- The aura a mounted knife gives off. Better knives (rarity, mutation, size) get a wider, more
-- dramatic upright flame. The floor ring still shows the unchanged slowdown radius.
local function aura(folder: Instance, model: Model, base: MapService.BaseSite, item: string, color: Color3)
	local power = Items.AuraPower(item)
	local boxCF, boxSize = model:GetBoundingBox()
	local anchor = Instance.new("Part")
	anchor.Name = "Aura"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	-- The flame grows out of the guard (fallback: a bit under the middle of the knife)
	local guard = model:FindFirstChild("Guard", true)
	anchor.CFrame = if guard and guard:IsA("BasePart")
		then CFrame.new(guard.Position)
		else CFrame.new(boxCF.Position - Vector3.new(0, boxSize.Y * 0.2, 0))
	anchor.Parent = folder
	local clearance: number? = nil
	local level = math.floor((boxCF.Position.Y - base.Frame.Position.Y) / MapService.FloorHeight) + 1
	if level < MapService.Floors then
		clearance = base.Frame.Position.Y + level * MapService.FloorHeight - 1.5 - anchor.Position.Y
	end
	local blade = model:FindFirstChild("Blade", true)
	KnifeAura.Mount(
		anchor,
		KnifeAura.Power(item),
		clearance,
		KnifeAura.Variation(item),
		if blade and blade:IsA("BasePart") then blade else nil
	)
	if power >= 1 then
		-- How far it reaches, as a faint glowing circle on the floor
		local radius = Items.AuraRadius(power)
		local floorPoint = (base.Frame * CFrame.new(0, 0.62, 0)).Position
		local center = Vector3.new(boxCF.Position.X, floorPoint.Y, boxCF.Position.Z)
		local ring = Instance.new("Part")
		ring.Name = "AuraRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Material = Enum.Material.Neon
		ring.Color = color
		ring.Transparency = 0.95
		ring.Size = Vector3.new(0.05, radius * 2, radius * 2)
		ring.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = folder
		ring:AddTag("AuraRing")
		ring:SetAttribute("Power", power)
		-- A glowing dashed edge marks exactly where the slowdown starts
		local dashes = math.clamp(math.floor(radius * 1.6), 12, 40)
		for i = 0, dashes - 1 do
			local angle = i / dashes * math.pi * 2
			local dash = Instance.new("Part")
			dash.Name = "AuraEdge"
			dash.Anchored = true
			dash.CanCollide = false
			dash.CanQuery = false
			dash.CanTouch = false
			dash.CastShadow = false
			dash.Material = Enum.Material.Neon
			dash.Color = color
			dash.Transparency = 0.35
			dash.Size = Vector3.new(0.25, 0.08, 2 * math.pi * radius / dashes * 0.55)
			dash.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * radius, 0.03, math.sin(angle) * radius))
				* CFrame.Angles(0, -angle, 0)
			dash.Parent = folder
		end
	end
end

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

-- Carrying a knife (not a case) right now
local function carryingKnife(player: Player): boolean
	local carrying = player:GetAttribute("Carrying")
	return type(carrying) == "string" and carrying:sub(1, 5) ~= "Case:"
end

-- Worth a second tap before it's sold: rare knives, mutations, big sizes
local function precious(item: string): boolean
	local parsed = Items.Parse(item)
	return parsed ~= nil
		and (Knives.Rank(parsed.Knife.Rarity) >= 4 or parsed.Mutation.Rank > 0 or parsed.Size.Rank >= 2)
end

-- Tsunami-style sell sign: a thin board standing between the plate and its cash pad, leaning back a
-- little, "SELL $11K". Tap / click it to sell (precious knives ask for a second tap).
local sellSignPressed: { [Instance]: (Player) -> () } = {}

local function sellSign(
	folder: Instance,
	base: MapService.BaseSite,
	owner: Player,
	plate: number,
	index: number,
	item: string
)
	local pad = base.CashPads[plate]
	local stone = base.SlotPads[plate]
	if not pad or not stone then
		return
	end
	local toPlate = (stone.Position - pad.Position) * Vector3.new(1, 0, 1)
	if toPlate.Magnitude < 0.1 then
		return
	end
	toPlate = toPlate.Unit
	local at = pad.Position + toPlate * 2.9 + Vector3.new(0, 1.1, 0)
	local board = Instance.new("Part")
	board.Name = "SellSign"
	board.Anchored = true
	board.CanCollide = false
	board.CanTouch = false
	board.CastShadow = false
	board.Size = Vector3.new(5.6, 1.9, 0.16) -- a Tsunami pill, bigger and easier to read
	-- Standing straight up (not leaning back like an easel) so it reads clearly, front face
	-- toward the walkway
	board.CFrame = CFrame.lookAt(at, at - toPlate)
	board.Color = Color3.fromRGB(255, 160, 40)
	board.Material = Enum.Material.SmoothPlastic
	board.Transparency = 1
	board.Parent = folder
	-- Tsunami pill: "Sell $6.4K" in one line
	local gui = SignTheme.face(board, Enum.NormalId.Front, 50, 60)
	local price = math.floor(Items.Income(item) * GameConfig.SellSeconds)
	local label = SignTheme.cashPill(gui)
	label.Name = "SalePrice"
	label.Text = `Sell {Format.Cash(price)}`
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 28
	click.Parent = board
	board:SetAttribute("SellOwner", owner.UserId)
	local armedUntil = 0
	local function pressed(who: Player)
		if who ~= owner or owner:GetAttribute("InRound") then
			return
		end
		local profile = DataService.Get(owner)
		-- Still the same knife on this plate? (the wall may have changed since the sign was made)
		if not profile or DataService.IndexOnPlate(profile, plate) ~= index or profile.Knives[index] ~= item then
			return
		end
		if precious(item) and os.clock() > armedUntil then
			armedUntil = os.clock() + 3
			label.Text = "Tap again to sell"
			task.delay(3, function()
				if label.Parent and os.clock() >= armedUntil then
					label.Text = `Sell {Format.Cash(price)}`
				end
			end)
			return
		end
		-- Off the plate with a puff and a burst of cash, then the wall updates
		local spot = base.SlotCFrames[plate].Position
		Net.Remotes.Effect:FireAllClients("Smoke", spot)
		Net.Remotes.Effect:FireClient(owner, "CashBurst", spot, price)
		if BaseService.OnSellPrompt then
			BaseService.OnSellPrompt(owner, index)
		end
	end
	click.MouseClick:Connect(pressed)
	-- With a knife in hand Roblox doesn't fire ClickDetectors: the client spots the tap itself
	-- (client/Effects) and sends this sign (Remotes.SellSign)
	sellSignPressed[board] = pressed
	board.Destroying:Connect(function()
		sellSignPressed[board] = nil
	end)
end

function BaseService.RefreshRack(player: Player)
	local base = baseOf[player]
	local profile = DataService.Get(player)
	if not base or not profile then
		return
	end
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
	if base.Blocker:GetAttribute("Floors") ~= GameConfig.FloorsFor(profile.Slots) then
		BaseService.RefreshWalls(base)
	end
	local equipped = profile.Equipped
	local multiplier = BaseService.IncomeMultiplier(player)
	for slot, pad in base.SlotPads do
		local rim = base.SlotRims[slot]
		local unlocked = slot <= profile.Slots
		-- Reference-built plates stay cyan; grey and white still communicate rack state.
		local vaultInset = pad:GetAttribute("VaultInset")
		rim.Color = if unlocked
			then (if pad:GetAttribute("BlockPlate")
				then Color3.fromRGB(49, 218, 220)
				else (if typeof(vaultInset) == "Color3" then vaultInset else Color3.fromRGB(30, 160, 215)))
			else Color3.fromRGB(150, 150, 160)
		rim.Material = if unlocked then Enum.Material.Neon else Enum.Material.SmoothPlastic
		-- Knives keep their own plate (profile.Plates), so selling one never shuffles the rest
		local index = DataService.IndexOnPlate(profile, slot)
		local item = if index then profile.Knives[index] else nil
		local parsed = item and Items.Parse(item)
		if unlocked and index and item and parsed then
			local model = KnifeModel.Build(item, true)
			-- Bigger items float bigger (a Colossal towers over its pedestal)
			KnifeModel.FitLength(model, 4 * (1 + (parsed.Size.Scale - 1) * 0.5)) -- universal display size (was 6)
			-- Centre the blade over the pedestal, then let clients bob and turn it (tag Spin)
			model:PivotTo(base.SlotCFrames[slot])
			local boxCF = model:GetBoundingBox()
			model:PivotTo(model:GetPivot() + (base.SlotCFrames[slot].Position - boxCF.Position))
			model:AddTag("Spin")
			model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- spun whole on clients
			model.Parent = folder
			local glow = Items.Color(item)
			-- The knife you fight with lights its plate up white
			if item == equipped then
				rim.Color = Color3.new(1, 1, 1)
				rim.Material = Enum.Material.Neon
			end
			-- Fire supplies the pedestal glow; an opaque beam would hide its long wisps.
			local anchor = model.PrimaryPart :: BasePart
			nameplate(folder, anchor, item, Items.Income(item) * multiplier)
			aura(folder, model, base, item, glow)

			-- One prompt per knife (the client hides prompts with someone else's Owner): Equip.
			-- Selling is the thin sign standing by the plate (sellSign).
			local name = Items.DisplayName(item)
			local equip = makePrompt(pad, {
				ActionText = if item == equipped then "Equipped" else "Equip",
				ObjectText = name,
			})
			equip:SetAttribute("Owner", player.UserId)
			equip.Triggered:Connect(function(who)
				if who == player and BaseService.OnEquipPrompt then
					BaseService.OnEquipPrompt(player, item)
				end
			end)
			sellSign(folder, base, player, slot, index, item)
			-- Blood Moon: other players can steal it (client/Raid only lights this up for them, and only
			-- while the moon is up; the knife you fight with can't be taken)
			if item ~= BaseService.ProtectedItem(player) then
				local steal = makePrompt(pad, {
					ActionText = "Steal",
					ObjectText = name,
					HoldDuration = GameConfig.Raid.StealTime,
					KeyboardKeyCode = Enum.KeyCode.F,
				})
				steal:SetAttribute("Owner", player.UserId)
				steal:SetAttribute("Steal", true)
				steal.Enabled = false
				steal.Triggered:Connect(function(who)
					if who ~= player and BaseService.OnStealPrompt then
						BaseService.OnStealPrompt(who, player, item)
					end
				end)
			end
		elseif unlocked and not index then
			-- An empty plate takes the knife you're carrying (any of them, not just the next one)
			local place = makePrompt(pad, {
				ActionText = "Place Knife",
				ObjectText = "",
				HoldDuration = 0,
			})
			place:SetAttribute("Owner", player.UserId)
			place:SetAttribute("Place", true)
			place.Enabled = carryingKnife(player)
			local plate = slot
			place.Triggered:Connect(function(who)
				if who == player and BaseService.OnPlacePrompt then
					BaseService.OnPlacePrompt(player, plate)
				end
			end)
		end
		VaultModel.SetPlateGlow(rim)
	end
	player:SetAttribute("Income", rackIncome(player))
	MapService.SetWheelTier(base, profile.TreadmillLevel)
end

local function claimBase(player: Player)
	for i, base in MapService.Bases do
		if not owners[i] then
			owners[i] = player
			baseOf[player] = base
			base.Sign.Text = `{player.DisplayName}'s Vault`
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
		base.Sign.Text = "Empty Vault"
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
			VaultModel.SetPlateGlow(rim)
		end
	end
	if rackModels[player] then
		rackModels[player]:Destroy()
	end
	baseOf[player] = nil
	rackModels[player] = nil
	if base then
		base.Wheel:SetAttribute("Spinning", nil)
		MapService.SetWheelTier(base, 1)
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

function BaseService.Init()
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
	DataService.Changed:Connect(function(player: Player, profile: DataService.Profile)
		BaseService.RefreshWalkSpeed(player)
		-- New walls go up when the tier changes (upgrade, rebirth)
		local base = baseOf[player]
		if base then
			MapService.SetWheelTier(base, profile.TreadmillLevel)
		end
		if base and base.Blocker:GetAttribute("Tier") ~= profile.WallLevel then
			BaseService.RefreshWalls(base)
			BaseService.RefreshRack(player) -- restore equipped/locked plate finishes after the theme swap
		end
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

	-- Haunted Wheel: stand inside your vault's wheel to train Speed (AFK is fine)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.25)
			local now = os.clock()
			local dt = now - last
			last = now
			for player, base in baseOf do
				local profile = DataService.Get(player)
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local on = false
				if profile and root and humanoid and humanoid.Health > 0 and not player:GetAttribute("InRound") then
					local localPos = base.Treadmill.CFrame:PointToObjectSpace(root.Position)
					local size = base.Treadmill.Size
					on = math.abs(localPos.X) < size.X / 2 + 0.5
						and math.abs(localPos.Z) < size.Z / 2 + 0.5
						and localPos.Y > 0
						and localPos.Y < 6
				end
				if player:GetAttribute("Training") ~= (on or nil) then
					if on then
						trainingSince[player] = os.clock()
						Analytics.Milestone(player, "wheel_trained")
					elseif trainingSince[player] then
						Analytics.Track(player, "wheel.session", {
							seconds = math.floor(os.clock() - trainingSince[player]),
							speed_after = profile and math.floor(profile.Speed),
						})
						trainingSince[player] = nil
					end
					player:SetAttribute("Training", on or nil)
					base.Wheel:SetAttribute("Spinning", on or nil) -- clients spin it
					if on and root and profile then
						-- Face the way the rungs roll, so it looks like running up the steps
						local hub = (base.Wheel.PrimaryPart :: BasePart).CFrame
						local forward = hub:VectorToWorldSpace(Vector3.zAxis)
						root.CFrame = CFrame.lookAt(root.Position, root.Position + forward)
					end
				end
				-- Better wheels spin faster (and the runner's legs keep up, see Moves)
				if on and profile then
					base.Wheel:SetAttribute("SpinRate", 1.4 + profile.TreadmillLevel * 0.55)
				end
				if on and profile then
					local rate = GameConfig.Treadmills[profile.TreadmillLevel].Rate
						* (1 + profile.Rebirths * GameConfig.Rebirth.SpeedBonus)
						* (if player:GetAttribute("Pass_FastWheel") then 2 else 1)
						* (if DataService.BoostActive(profile, "Training")
							then GameConfig.Consumables.TrainingMultiplier
							else 1)
						* GameConfig.TrailMultiplier(
							profile.TrailLevel,
							player:GetAttribute("Pass_PhantomTrail") == true
						)
					DataService.Update(player, function(p)
						p.Speed += rate * dt
					end)
					-- A long stint on the wheel: that's the grind a Training Potion cuts
					trainedFor[player] = (trainedFor[player] or 0) + dt
					if
						trainedFor[player] > GameConfig.Consumables.TrainingOfferAfter
						and not DataService.BoostActive(profile, "Training")
					then
						trainedFor[player] = 0
						Offers.Show(
							player,
							"TrainingPotion",
							"Training takes ages? 3x Speed from the wheel for 15 minutes."
						)
					end
				end
			end
		end
	end)

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
				local boostUntil = player:GetAttribute("BoostUntil")
				local boosted = type(boostUntil) == "number" and workspace:GetServerTimeNow() < boostUntil
				if boosted then
					multiplier *= GameConfig.BoostMultiplier
				end
				-- The free 2x (survivor / Thief Moon) just ran out: that's when a Cash Potion feels best
				if hadBoost[player] and not boosted and not DataService.BoostActive(profile, "Cash") then
					Offers.Show(
						player,
						"CashPotion",
						"Your 2x boost ran out! Keep your vault on 2x for 15 more minutes."
					)
				end
				hadBoost[player] = boosted
				-- A Speed Potion just ended: back to normal speed
				local speedOn = DataService.BoostActive(profile, "Speed")
				if speedOn ~= (hadSpeed[player] or false) then
					hadSpeed[player] = speedOn
					BaseService.RefreshWalkSpeed(player)
				end
				DataService.Update(player, function(p)
					for index, item in p.Knives do
						local plate = p.Plates[index] or index
						if plate <= p.Slots then
							p.Pending[plate] = (p.Pending[plate] or 0) + Items.Income(item) * multiplier
						end
					end
				end)
				for slot, label in base.CashLabels do
					local waiting = profile.Pending[slot] or 0
					label.Text = if waiting > 0 and slot <= profile.Slots then Format.Cash(waiting) else ""
				end
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
				for slot, pad in base.CashPads do
					local waiting = profile.Pending[slot] or 0
					if waiting <= 0 or not pad.Parent or not pad:IsDescendantOf(workspace) then
						continue
					end
					local offset = pad.CFrame:PointToObjectSpace(root.Position)
					if
						auto
						or math.abs(offset.X) < pad.Size.X / 2 + 0.8
							and math.abs(offset.Z) < pad.Size.Z / 2 + 0.8
							and offset.Y > 0
							and offset.Y < 6
					then
						DataService.Update(player, function(p)
							p.Pending[slot] = 0
						end)
						DataService.AddCash(player, waiting, "income")
						Analytics.Milestone(player, "cash_collected")
						Analytics.Count(player, if auto then "pad_auto" else "pad_walks")
						base.CashLabels[slot].Text = ""
						Net.Remotes.Effect:FireClient(player, "CashBurst", pad.Position, waiting)
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
		end
	end)
end

return BaseService
