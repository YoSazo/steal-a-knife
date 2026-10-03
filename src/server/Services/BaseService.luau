--!strict
-- Each player gets a vault: a safe zone with a knife rack that pays cash every second.
-- Also owns character placement and walk speed, since both depend on where the player "lives".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local SignTheme = require(ReplicatedStorage.Shared.SignTheme)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local KnifeAura = require(ReplicatedStorage.Shared.KnifeAura)
local Net = require(script.Parent.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local Fuel = require(script.Parent.Fuel)
local ServerEvents = require(script.Parent.ServerEvents)
local Social = require(script.Parent.Social)
local MapService = require(script.Parent.MapService)
local VaultWalls = require(script.Parent.VaultWalls)

local BaseService = {}

local owners: { [number]: Player } = {} -- base index -> player
local baseOf: { [Player]: MapService.BaseSite } = {}
local rackModels: { [Player]: Folder } = {}

-- Set by InventoryService: called when the owner uses a prompt on one of their mounted knives
BaseService.OnSellPrompt = nil :: ((Player, number) -> ())?
BaseService.OnEquipPrompt = nil :: ((Player, string) -> ())?
-- Set by RaidService: someone held "Steal" on a knife on another player's wall
BaseService.OnStealPrompt = nil :: ((Player, Player, number) -> ())?
-- Set by RaidService: a vault's walls were rebuilt (new tier, or the vault changed hands)
BaseService.OnWallsBuilt = nil :: ((MapService.BaseSite, Player?) -> ())?
BaseService.OnUpgradeWalls = nil :: ((Player) -> ())?
-- Set by StealService: the owner pressed Place on their next empty plate while carrying a knife
BaseService.OnPlacePrompt = nil :: ((Player, number) -> ())?
-- Set by UpgradeService: the owner pressed Upgrade Base at the sign by their gate
BaseService.OnUpgradeBase = nil :: ((Player) -> ())?

-- Rebirths multiply everything a vault earns
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
	base.Gate = built.Gate
	base.Blocker = built.Blocker
	-- Fortified Vault pass: +50% gate health on every tier
	if owner and owner:GetAttribute("Pass_Fortified") then
		local max = (built.Blocker:GetAttribute("MaxHealth") or 0) :: number
		built.Blocker:SetAttribute("MaxHealth", max * 1.5)
		built.Blocker:SetAttribute("Health", max * 1.5)
	end
	base.Blocker:SetAttribute("Owner", if owner then owner.UserId else nil)
	base.Blocker:SetAttribute("OwnerName", if owner then owner.DisplayName else nil)
	local nextTier = GameConfig.Walls[tier + 1]
	if owner and nextTier then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "UpgradeWalls"
		prompt.ActionText = `Upgrade Walls ({Format.Cash(nextTier.Cost)})`
		prompt.ObjectText = `{GameConfig.Walls[tier].Name} - {GameConfig.Walls[tier].GateHealth} HP`
		prompt.KeyboardKeyCode = Enum.KeyCode.G
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("WallUpgrade", true)
		prompt:SetAttribute("Owner", owner.UserId)
		prompt.Triggered:Connect(function(player)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if
				player == owner
				and root
				and not player:GetAttribute("InRound")
				and (root.Position - base.Blocker.Position).Magnitude <= 15
				and BaseService.OnUpgradeWalls
			then
				BaseService.OnUpgradeWalls(player)
			end
		end)
		prompt.Parent = base.Blocker
	end
	-- The Upgrade Base sign by the gate: the owner buys the next floor there
	local upgradeSign = base.Folder:FindFirstChild("UpgradeSign")
	local board = upgradeSign and upgradeSign:FindFirstChild("Board") :: BasePart?
	if board then
		local old = board:FindFirstChild("UpgradeBase")
		if old then
			old:Destroy()
		end
		if owner then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "UpgradeBase"
			prompt.ActionText = "Upgrade Base"
			prompt.ObjectText = "+1 floor, 10 more plates"
			prompt.HoldDuration = 0.3
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt:SetAttribute("Owner", owner.UserId)
			prompt.Triggered:Connect(function(player)
				if player == owner and not player:GetAttribute("InRound") and BaseService.OnUpgradeBase then
					BaseService.OnUpgradeBase(player)
				end
			end)
			prompt.Parent = board
		end
	end
	-- The vault's sign rides on top of its back wall
	base.SignPart.CFrame = base.Frame * CFrame.new(0, built.BackHeight + 2.4, -22)
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

function BaseService.TeleportHome(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local base = baseOf[player]
	local destination = if base then base.Spawn else MapService.LobbySpawn
	local spot = returnSpots[player]
	if spot and not player:GetAttribute("InRound") then
		returnSpots[player] = nil
		destination = spot
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
	else
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
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nameplate"
	gui.Size = UDim2.fromScale(4.4, 1.4) -- studs: shrinks with distance
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.4, 0)
	gui.MaxDistance = 40
	gui.LightInfluence = 0
	gui.Adornee = adornee
	gui.Parent = parent
	local lines = {
		{ Text = parsed.Knife.Rarity, Color = Knives.RarityColors[parsed.Knife.Rarity], Height = 16 },
		{ Text = Items.DisplayName(item), Color = Color3.new(1, 1, 1), Height = 20 },
		{
			Text = `{Format.Cash(math.floor(perSecond * 10 + 0.5) / 10)}/s`,
			Color = Color3.fromRGB(110, 255, 110),
			Height = 18,
		},
	}
	-- Its Murderer power, so you know what it does in a round
	local perk = parsed.Perk and GameConfig.Perks[parsed.Perk]
	if perk then
		table.insert(lines, 1, {
			Text = `🔪 {perk.DisplayName} · Murderer power`,
			Color = Color3.fromRGB(255, 120, 140),
			Height = 15,
		})
		gui.Size = UDim2.fromScale(4.8, 1.8)
	end
	local total = 0
	for _, line in lines do
		total += line.Height
	end
	local y = 0
	for _, line in lines do
		local label = Instance.new("TextLabel")
		label.Position = UDim2.fromScale(0, y / total)
		label.Size = UDim2.fromScale(1, line.Height / total)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = line.Color
		label.TextStrokeTransparency = 0
		label.Text = line.Text
		label.Parent = gui
		y += line.Height
	end
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
	board.Size = Vector3.new(4.6, 1.9, 0.16)
	-- Front face looks at the walkway; leaning back like a little easel
	board.CFrame = CFrame.lookAt(at, at - toPlate) * CFrame.Angles(math.rad(-18), 0, 0)
	board.Color = Color3.fromRGB(255, 160, 40)
	board.Material = Enum.Material.SmoothPlastic
	board.Transparency = 1
	board.Parent = folder
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Brightness = 0.9
	gui.MaxDistance = 60
	gui.Parent = board
	local panel = Instance.new("Frame")
	panel.Position = UDim2.fromOffset(5, 5)
	panel.Size = UDim2.new(1, -10, 1, -10)
	panel.Parent = gui
	SignTheme.surface(panel, SignTheme.Gold)
	SignTheme.cashIcon(panel, UDim2.fromScale(0.02, 0.15), UDim2.fromScale(0.19, 0.7))
	local price = math.floor(Items.Income(item) * GameConfig.SellSeconds)
	-- "SELL" small on top, the price big under it (the Steal An Egg upgrade sign)
	local label = Instance.new("TextLabel")
	label.Name = "SellWord"
	label.Position = UDim2.fromScale(0.23, 0.04)
	label.Size = UDim2.fromScale(0.74, 0.36)
	label.Text = "SELL"
	label.Parent = panel
	SignTheme.text(label, 30)
	local amount = Instance.new("TextLabel")
	amount.Name = "SalePrice"
	amount.Position = UDim2.fromScale(0.23, 0.36)
	amount.Size = UDim2.fromScale(0.74, 0.6)
	amount.Text = Format.Cash(price)
	amount.Parent = panel
	SignTheme.text(amount, 64, SignTheme.NumberFont)
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 28
	click.Parent = board
	local armedUntil = 0
	click.MouseClick:Connect(function(who)
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
			label.Text = "TAP AGAIN"
			task.delay(3, function()
				if label.Parent and os.clock() >= armedUntil then
					label.Text = "SELL"
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
	local protected = BaseService.ProtectedItem(player)
	local multiplier = BaseService.IncomeMultiplier(player)
	for slot, pad in base.SlotPads do
		local rim = base.SlotRims[slot]
		local unlocked = slot <= profile.Slots
		-- Tsunami plates: navy and cyan when unlocked, grey while locked
		rim.Color = if unlocked then Color3.fromRGB(70, 214, 245) else Color3.fromRGB(150, 150, 160)
		rim.Material = Enum.Material.SmoothPlastic
		-- Knives keep their own plate (profile.Plates), so selling one never shuffles the rest
		local index = DataService.IndexOnPlate(profile, slot)
		local item = if index then profile.Knives[index] else nil
		local parsed = item and Items.Parse(item)
		if unlocked and index and item and parsed then
			local knife = parsed.Knife
			local model = KnifeModel.Build(item, true)
			-- Bigger items float bigger (a Colossal towers over its pedestal)
			KnifeModel.FitLength(model, 6 * (1 + (parsed.Size.Scale - 1) * 0.5))
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
			-- Raiders' prompt: only shown when this vault is open to them (client/Raid). The
			-- knife the owner fights with is always safe.
			if item ~= protected then
				local steal = makePrompt(pad, {
					ActionText = "Steal",
					ObjectText = `{name} ({knife.Rarity})`,
					HoldDuration = GameConfig.Raid.StealTime,
				})
				steal:SetAttribute("Owner", player.UserId)
				steal:SetAttribute("Steal", true)
				steal.Triggered:Connect(function(who)
					if who ~= player and BaseService.OnStealPrompt then
						BaseService.OnStealPrompt(who, player, index)
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
	end
	player:SetAttribute("Income", rackIncome(player))
	base.TreadmillSign.Text = GameConfig.Treadmills[profile.TreadmillLevel].Name
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

function BaseService.Init()
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
		if base and base.Blocker:GetAttribute("Tier") ~= profile.WallLevel then
			BaseService.RefreshWalls(base)
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
						* GameConfig.TrailMultiplier(
							profile.TrailLevel,
							player:GetAttribute("Pass_PhantomTrail") == true
						)
					DataService.Update(player, function(p)
						p.Speed += rate * dt
					end)
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
				if type(boostUntil) == "number" and workspace:GetServerTimeNow() < boostUntil then
					multiplier *= GameConfig.BoostMultiplier
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
				if not MapService.InBounds(base.Bounds, root.Position, 2) then
					continue
				end
				for slot, pad in base.CashPads do
					local waiting = profile.Pending[slot] or 0
					if waiting <= 0 or not pad.Parent or not pad:IsDescendantOf(workspace) then
						continue
					end
					local offset = pad.CFrame:PointToObjectSpace(root.Position)
					if
						math.abs(offset.X) < pad.Size.X / 2 + 0.8
						and math.abs(offset.Z) < pad.Size.Z / 2 + 0.8
						and offset.Y > 0
						and offset.Y < 6
					then
						DataService.Update(player, function(p)
							p.Pending[slot] = 0
						end)
						DataService.AddCash(player, waiting)
						base.CashLabels[slot].Text = ""
						Net.Remotes.Effect:FireClient(player, "CashBurst", pad.Position, waiting)
					end
				end
			end
		end
	end)
end

return BaseService
