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

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local KnifeModel = require(ReplicatedStorage.Shared.KnifeModel)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local Offers = require(script.Parent.Offers)

type Carry = {
	Kind: string, -- "Case" | "Knife"
	Item: string, -- the case's rarity, or the knife item
	StolenFrom: number?, -- UserId of the vault it was stolen from
	Visual: Model,
	LastPos: Vector3,
	LastCheck: number,
}

local StealService = {}

-- Set by GuardService: (player, zoneIndex) when someone picks something up in the arena
StealService.OnPickup = nil :: ((Player, number) -> ())?

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

local startCarry: (Player, string, string, number?) -> ()

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
		Net.Notify(player, "No free vault on this server, you can't store knives.", "bad")
		return false
	end
	if #profile.Knives >= profile.Slots then
		Net.Notify(player, "Your vault wall is full! Sell a knife or buy another mount.", "bad")
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
			Text = `Damage {Items.Damage(item)}  ·  ${Items.Income(item)}/s`,
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
						table.insert(p.Knives, item)
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
		startCarry(player, "Knife", item, if stolenFrom and player.UserId ~= stolenFrom then stolenFrom else nil)
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
					table.insert(p.Knives, item)
				end)
				BaseService.RefreshRack(owner)
				Net.Notify(owner, `Your {Items.DisplayName(item)} found its way home.`, "good")
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
		startCarry(player, "Case", rarity, nil)
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
local function endCarry(player: Player, deposited: boolean, dropAt: Vector3?)
	local carry = carriers[player]
	if not carry then
		return
	end
	carriers[player] = nil
	local visual = carry.Visual
	local fallback = visual.PrimaryPart and (visual.PrimaryPart :: BasePart).Position
	visual:Destroy()
	player:SetAttribute("Carrying", nil)
	player:SetAttribute("StolenFrom", nil)
	BaseService.RefreshWalkSpeed(player)
	local where = dropAt or fallback
	if not deposited and where then
		if carry.Kind == "Case" then
			StealService.DropCase(carry.Item, where)
		else
			StealService.DropKnife(carry.Item, where, carry.StolenFrom)
		end
	end
end

-- Lifts something over a player's head: kind "Case" (item = rarity) or "Knife" (item string)
startCarry = function(player: Player, kind: string, item: string, stolenFrom: number?)
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

	carriers[player] = {
		Kind = kind,
		Item = item,
		StolenFrom = stolenFrom,
		Visual = visual,
		LastPos = root.Position,
		LastCheck = os.clock(),
	}
	Net.Animate(character, "Pickup")
	player:SetAttribute("Carrying", if kind == "Case" then `Case:{item}` else item)
	player:SetAttribute("StolenFrom", stolenFrom) -- the UserId it was taken from, if anyone
	BaseService.RefreshWalkSpeed(player)
	if kind == "Case" then
		Net.Notify(player, `You grabbed a {item} Case! The guards know - RUN!`, "good")
	elseif stolenFrom then
		Net.Notify(player, `You stole a {Items.DisplayName(item)}! Get it home before they catch you!`, "good")
	else
		Net.Notify(player, `You grabbed a {Items.DisplayName(item)}! RUN!`, "good")
	end
end

function StealService.StartCarry(player: Player, kind: string, item: string, stolenFrom: number?)
	if carriers[player] then
		return
	end
	startCarry(player, kind, item, stolenFrom)
end

-- Rebirths bring better luck in cases
local function caseLuck(profile: DataService.Profile): number
	local luck = 1 + profile.Rebirths * GameConfig.Rebirth.LuckBonus
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
function StealService.OpenCase(player: Player, rarity: string, force: boolean?): string?
	local profile = DataService.Get(player)
	if not profile or (#profile.Knives >= profile.Slots and not force) then
		return nil
	end
	local item, upgraded = Items.OpenCase(rng, rarity, caseLuck(profile))
	local parsed = Items.Parse(item) :: Items.Item
	local isNew = not table.find(profile.Discovered, parsed.Name)
	local hype = Items.Hype(item)
	DataService.Update(player, function(p)
		table.insert(p.Knives, item)
		if isNew then
			table.insert(p.Discovered, parsed.Name)
		end
		p.CasesOpened += 1
		if p.BestPull == "" or hype > Items.Hype(p.BestPull) then
			p.BestPull = item
		end
	end)
	Net.Remotes.Effect:FireClient(player, "Unbox", rarity, item, upgraded, isNew)
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

local function deposit(player: Player)
	local carry = carriers[player]
	if not carry then
		return
	end
	local profile = DataService.Get(player)
	if not profile or #profile.Knives >= profile.Slots then
		Net.Notify(player, "Your vault wall is full! Sell a knife to make room.", "bad")
		Offers.Show(player, "Mount", "Your wall is full! Add another mount instantly.")
		endCarry(player, false)
		return
	end
	if carry.Kind == "Case" then
		local rarity = carry.Item
		endCarry(player, true)
		StealService.OpenCase(player, rarity)
		return
	end
	local item = carry.Item
	local parsed = Items.Parse(item) :: Items.Item
	local isNew = not table.find(profile.Discovered, parsed.Name)
	DataService.Update(player, function(p)
		table.insert(p.Knives, item)
		if isNew then
			table.insert(p.Discovered, parsed.Name)
		end
		if carry.StolenFrom then
			p.KnivesStolen += 1
		end
	end)
	local stolenFrom = carry.StolenFrom
	endCarry(player, true)
	local name = Items.DisplayName(item)
	BaseService.RefreshRack(player)
	Net.Notify(player, `{name} is on your wall! +${Items.Income(item)}/s`, "good")
	Net.Remotes.Effect:FireAllClients("Deposit", player, parsed.Knife.Rarity)
	if stolenFrom then
		local victim = ownerName(stolenFrom) or "someone"
		Net.Announce(`{player.DisplayName} stole {victim}'s {name}!`, Color3.fromRGB(255, 90, 90), 1)
	end
	if isNew then
		Net.Notify(player, `NEW! {parsed.Knife.DisplayName} added to your collection`, "info")
	end
	if player.Character then
		Net.Animate(player.Character, "Cheer")
	end
end

-- Deposits and the carrier speed check run on the server's view of positions
local function tick()
	local now = os.clock()
	for player, carry in carriers do
		local root = rootPart(player)
		if not root then
			-- Died (or the character went away): drop it where they were
			endCarry(player, false, carry.LastPos)
			continue
		end
		local pos = root.Position
		if BaseService.IsInOwnBase(player, pos) then
			deposit(player)
			continue
		end
		local elapsed = now - carry.LastCheck
		if elapsed >= 0.5 then
			local humanoid = (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
			local flat = Vector3.new(pos.X - carry.LastPos.X, 0, pos.Z - carry.LastPos.Z).Magnitude
			local allowed = math.max(humanoid.WalkSpeed, GameConfig.BaseWalkSpeed) * elapsed * GameConfig.SpeedTolerance
				+ 3
			if flat > allowed then
				warn(
					`[StealService] {player.Name} moved {math.floor(flat)} studs in {elapsed}s while carrying, dropping it`
				)
				Net.Notify(player, "Whoa, too fast! It slipped out of your hands.", "bad")
				endCarry(player, false, carry.LastPos)
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
	endCarry(thief, true, nil)
	DataService.Update(owner, function(p)
		table.insert(p.Knives, item)
	end)
	BaseService.RefreshRack(owner)
	return item
end

function StealService.ForceDrop(player: Player)
	local root = rootPart(player)
	endCarry(player, false, if root then root.Position else nil)
end

function StealService.Init()
	dropFolder = Instance.new("Folder")
	dropFolder.Name = "DroppedKnives"
	dropFolder.Parent = workspace:FindFirstChild("Map")

	Players.PlayerRemoving:Connect(function(player)
		local carry = carriers[player]
		endCarry(player, false, if carry then carry.LastPos else nil)
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
