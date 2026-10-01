--!strict
-- Each player gets a vault: a safe zone with a knife rack that pays cash every second.
-- Also owns character placement and walk speed, since both depend on where the player "lives".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local Textures = require(ReplicatedStorage.Shared.Config.Textures)
local DataService = require(script.Parent.DataService)
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
	local built = VaultWalls.Build(base.WallFolder, base.Frame, base.Color, tier)
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
		prompt.ActionText = `Upgrade Walls (${nextTier.Cost})`
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

function BaseService.TeleportHome(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local base = baseOf[player]
	character:PivotTo(if base then base.Spawn else MapService.LobbySpawn)
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
	if player:GetAttribute("InRound") then
		speed = if player:GetAttribute("Role") == "Murderer"
			then GameConfig.MurdererWalkSpeed
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
	gui.Size = UDim2.fromOffset(200, 64)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Adornee = adornee
	gui.Parent = parent
	local lines = {
		{ Text = Items.DisplayName(item), Color = Items.Color(item), Height = 24 },
		{
			Text = parsed.Knife.Rarity,
			Color = Color3.fromRGB(230, 230, 240):Lerp(Knives.RarityColors[parsed.Knife.Rarity], 0.6),
			Height = 16,
		},
		{ Text = `${math.floor(perSecond * 10 + 0.5) / 10}/s`, Color = Color3.fromRGB(120, 255, 120), Height = 24 },
	}
	local y = 0
	for _, line in lines do
		local label = Instance.new("TextLabel")
		label.Position = UDim2.fromOffset(0, y)
		label.Size = UDim2.new(1, 0, 0, line.Height)
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
-- dramatic one: drifting sparks, then rising flames, then crackling lightning, and a glowing ring
-- on the floor showing how far it reaches (raiders inside it are slowed, see RaidService). The
-- light beam over each pedestal grows with it too (RefreshRack).
local function aura(folder: Instance, model: Model, base: MapService.BaseSite, item: string, color: Color3)
	local power = Items.AuraPower(item)
	if power < 0.5 then
		return
	end
	local boxCF, boxSize = model:GetBoundingBox()
	local anchor = Instance.new("Part")
	anchor.Name = "Aura"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = boxSize
	anchor.CFrame = boxCF
	anchor.Parent = folder
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Texture = Textures.Sparkle
	sparks.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	sparks.LightEmission = 1
	sparks.Rate = 3 + power * 3
	sparks.Lifetime = NumberRange.new(1, 2)
	sparks.Speed = NumberRange.new(0.5, 1.5)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, 1.5, 0)
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.3 + power * 0.07),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Parent = anchor
	local glowLight = Instance.new("PointLight")
	glowLight.Color = color
	glowLight.Range = 6 + power * 1.8
	glowLight.Brightness = 0.8 + power * 0.25
	glowLight.Parent = anchor
	if power >= 2 then
		-- Flames licking up the blade
		local flames = Instance.new("ParticleEmitter")
		flames.Name = "Flames"
		flames.Texture = Textures.Fire
		flames.Color = ColorSequence.new(color, color:Lerp(Color3.new(0, 0, 0), 0.6))
		flames.LightEmission = 1
		flames.Rate = power * 5
		flames.Lifetime = NumberRange.new(0.5, 1)
		flames.Speed = NumberRange.new(1, 3)
		flames.Acceleration = Vector3.new(0, 2, 0)
		flames.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(0.4, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		flames.Size = NumberSequence.new(0.4 + power * 0.12, 0)
		flames.Parent = anchor
	end
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
	if power >= 7 then
		-- The very best crackle with lightning-bright sparks
		local crackle = Instance.new("ParticleEmitter")
		crackle.Name = "Crackle"
		crackle.Texture = Textures.Sparkle
		crackle.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		crackle.LightEmission = 1
		crackle.Rate = 12
		crackle.Lifetime = NumberRange.new(0.15, 0.3)
		crackle.Speed = NumberRange.new(6, 12)
		crackle.SpreadAngle = Vector2.new(180, 180)
		crackle.Size = NumberSequence.new(0.9, 0)
		crackle.Parent = anchor
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
	local equipped = profile.Equipped
	local protected = BaseService.ProtectedItem(player)
	local multiplier = BaseService.IncomeMultiplier(player)
	for slot, pad in base.SlotPads do
		local rim = base.SlotRims[slot]
		local unlocked = slot <= profile.Slots
		-- Locked pedestals stay dark; unlocked empty ones glow faintly
		pad.Color = if unlocked then Color3.fromRGB(78, 70, 92) else Color3.fromRGB(34, 32, 40)
		rim.Color = if unlocked then Color3.fromRGB(70, 90, 110) else Color3.fromRGB(26, 24, 30)
		rim.Material = if unlocked then Enum.Material.Neon else Enum.Material.SmoothPlastic
		local item = profile.Knives[slot]
		local parsed = item and Items.Parse(item)
		if unlocked and item and parsed then
			local knife = parsed.Knife
			local model = KnifeModel.Build(item, true)
			-- Bigger items float bigger (a Colossal towers over its pedestal)
			KnifeModel.FitLength(model, 3.6 * (1 + (parsed.Size.Scale - 1) * 0.7))
			-- Centre the blade over the pedestal, then let clients bob and turn it (tag Spin)
			model:PivotTo(base.SlotCFrames[slot])
			local boxCF = model:GetBoundingBox()
			model:PivotTo(model:GetPivot() + (base.SlotCFrames[slot].Position - boxCF.Position))
			model:AddTag("Spin")
			model.Parent = folder
			local glow = Items.Color(item)
			rim.Color = if item == equipped then Color3.new(1, 1, 1) else glow
			rim.Material = Enum.Material.Neon
			-- A beam of light up from the pedestal, and the label floating over it
			local beam = Instance.new("Part")
			beam.Name = "PedestalBeam"
			beam.Anchored = true
			beam.CanCollide = false
			beam.CanQuery = false
			beam.CanTouch = false
			beam.CastShadow = false
			beam.Shape = Enum.PartType.Cylinder
			beam.Material = Enum.Material.Neon
			beam.Color = glow
			beam.Transparency = 0.78
			-- From just over the knife's tip up into the dark, so the blade itself stays clear
			local _, knifeSize = model:GetBoundingBox()
			local beamFrom = base.SlotCFrames[slot].Position.Y + knifeSize.Y / 2 + 0.6
			local beamLength = 9 + Items.AuraPower(item) * 1.5
			beam.Size = Vector3.new(beamLength, 0.9, 0.9)
			beam.CFrame = CFrame.new(Vector3.new(rim.Position.X, beamFrom + beamLength / 2, rim.Position.Z))
				* CFrame.Angles(0, 0, math.rad(90))
			beam.Parent = folder
			local spot = Instance.new("PointLight")
			spot.Range = 9
			spot.Brightness = 1.6
			spot.Color = glow:Lerp(Color3.new(1, 1, 1), 0.3)
			spot.Parent = beam
			local anchor = model.PrimaryPart :: BasePart
			nameplate(folder, anchor, item, Items.Income(item) * multiplier)
			aura(folder, model, base, item, glow)

			-- Owner prompts (the client hides prompts with someone else's Owner)
			local name = Items.DisplayName(item)
			local equip = makePrompt(pad, {
				ActionText = if item == equipped then "Equipped" else "Equip",
				ObjectText = `{name} · Damage {Items.Damage(item)} · +${Items.Income(item) * multiplier}/s`,
			})
			equip:SetAttribute("Owner", player.UserId)
			equip.Triggered:Connect(function(who)
				if who == player and BaseService.OnEquipPrompt then
					BaseService.OnEquipPrompt(player, item)
				end
			end)
			local sell = makePrompt(pad, {
				ActionText = `Sell ${math.floor(Items.Income(item) * GameConfig.SellSeconds)}`,
				ObjectText = name,
				HoldDuration = 1,
				KeyboardKeyCode = Enum.KeyCode.F,
				GamepadKeyCode = Enum.KeyCode.ButtonY,
				UIOffset = Vector2.new(0, 80),
			})
			sell:SetAttribute("Owner", player.UserId)
			sell.Triggered:Connect(function(who)
				if who == player and BaseService.OnSellPrompt then
					BaseService.OnSellPrompt(player, slot)
				end
			end)
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
						BaseService.OnStealPrompt(who, player, slot)
					end
				end)
			end
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

	-- Pay every rack once a second
	task.spawn(function()
		while true do
			task.wait(1)
			for player in baseOf do
				local income = rackIncome(player)
				local boostUntil = player:GetAttribute("BoostUntil")
				if type(boostUntil) == "number" and workspace:GetServerTimeNow() < boostUntil then
					income *= GameConfig.BoostMultiplier
				end
				if income > 0 then
					DataService.AddCash(player, income)
				end
			end
		end
	end)
end

return BaseService
