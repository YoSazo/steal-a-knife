--!strict
-- The guide: one next action while learning, with coaching retired after demonstrated use.
-- Its text and ground arrows step aside as the player follows the route. NextAction resolves
-- available actions; GuidePolicy chooses how much help to show. What to do comes from shared/NextAction;
-- where it is from client/Places. The status line under it (client/TopLine) keeps the timer, the
-- prize and notices - information, never instructions.
--
-- Hidden while the tutorial owns the hub arrows, in menus, fades and big cards (Ui.gui "Presenting").
-- RoundGuidance chooses round actions. Arrows can be turned off under More (session).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")

local Ui = require(script.Parent.Ui)
local Places = require(script.Parent.Places)
local Arrows = require(script.Parent.Arrows)
local Telemetry = require(script.Parent.Telemetry)
local NextAction = require(ReplicatedStorage.Shared.NextAction)
local GuidePolicy = require(ReplicatedStorage.Shared.GuidePolicy)
local IndexRewards = require(ReplicatedStorage.Shared.IndexRewards)
local RoundGuidance = require(ReplicatedStorage.Shared.RoundGuidance)
local RoundPrize = require(ReplicatedStorage.Shared.RoundPrize)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local player = Players.LocalPlayer
local Guide = {}

local FADE = 56
local HOLD = 0 -- state changes resolve on the next 4 Hz tick; target selection itself is sticky
local STUCK = 60 -- seconds on one action with no progress: log it (that's where kids get lost)

-- Actions that switch at once (something just happened to you)
local URGENT: { [string]: boolean } = {
	carry_home = true,
	carry_place = true,
	carry_full = true,
	carry_bigger = true,
	gift = true,
	new_tier = true,
}
local observedReach = 1
local unlockedTier: number? = nil
local committed = false

local function indexClaimable(): number
	return #IndexRewards.Pending(
		(player:GetAttribute("Discovered") or "") :: string,
		(player:GetAttribute("IndexClaimed") or "") :: string,
		Ui.gui:GetAttribute("IndexAcknowledged") :: string?
	)
end

local function state(): NextAction.State
	local root = Places.Root()
	local stocked: { [number]: number? } = {}
	for i = 1, #GameConfig.Zones do
		stocked[i] = Places.Stocked(i)
	end
	local carrying = player:GetAttribute("Carrying")
	local gift = Places.Gift()
	local spare, spareItem = Places.SpareSale()
	local speed = (player:GetAttribute("Speed") or 0) :: number
	local reach = NextAction.Reachable(speed)
	local bestRank = RoundPrize.Stats(player).BestRank
	local rebirths = (player:GetAttribute("Rebirths") or 0) :: number
	local plateAt: Vector3? = nil
	if type(carrying) == "string" then
		local _, at = Places.FreePlate()
		plateAt = at
	end
	return {
		InRound = player:GetAttribute("InRound") == true,
		CoffinsReady = (player:GetAttribute("CoffinsReady") or 0) :: number,
		Carrying = if type(carrying) == "string" then carrying else nil,
		InVault = root ~= nil and Places.InVault(root.Position),
		FreePlate = plateAt ~= nil,
		KnifeCount = (player:GetAttribute("KnifeCount") or 0) :: number,
		Slots = (player:GetAttribute("Slots") or GameConfig.StartingSlots) :: number,
		Rebirths = (player:GetAttribute("Rebirths") or 0) :: number,
		Cash = (player:GetAttribute("Cash") or 0) :: number,
		Income = (player:GetAttribute("Income") or 0) :: number,
		PendingCash = (player:GetAttribute("PendingCash") or 0) :: number,
		AutoCollect = player:GetAttribute("Pass_AutoCollect") == true
			or player:GetAttribute("SessionAutoCollect") == true,
		Speed = speed,
		BestOwnedRank = bestRank,
		Stocked = stocked,
		Gift = gift ~= nil,
		GiftNearby = root ~= nil and gift ~= nil and (root.Position - gift).Magnitude <= 20,
		Committed = committed,
		IndexClaimable = indexClaimable(),
		TutorialDone = player:GetAttribute("TutorialDone") == true,
		NewTier = unlockedTier,
		Spare = spare ~= nil,
		BetterReplacement = Places.BetterReplacement(reach, spareItem),
		CanRebirth = rebirths < GameConfig.Rebirth.Max
			and ((player:GetAttribute("Cash") or 0) :: number) >= GameConfig.RebirthCost(rebirths)
			and bestRank >= Knives.Rank(GameConfig.RebirthNeeds(rebirths)),
	}
end

local function toolWith(attribute: string, heldOnly: boolean?): Tool?
	for _, container in { player.Character, if heldOnly then nil else player:FindFirstChildOfClass("Backpack") } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute(attribute) then
					return child
				end
			end
		end
	end
	return nil
end

local roundTargets: { [string]: Instance } = {}
local targetChecked: { [string]: number } = {}
local function visibleRoundTarget(tag: string, radius: number): Instance?
	local root = Places.Root()
	if not root then
		return nil
	end
	local kept = roundTargets[tag]
	if os.clock() - (targetChecked[tag] or 0) < 0.25 and (not kept or kept.Parent) then
		return kept
	end
	targetChecked[tag] = os.clock()
	local function valid(object: Instance): (boolean, number)
		if not object:IsDescendantOf(workspace) then
			return false, math.huge
		end
		local at = if object:IsA("Model")
			then object:GetPivot().Position
			else if object:IsA("BasePart") then object.Position else nil
		if not at then
			return false, math.huge
		end
		local distance = (at - root.Position).Magnitude
		if distance > radius then
			return false, distance
		end
		local _, onScreen = workspace.CurrentCamera:WorldToViewportPoint(at)
		if not onScreen then
			return false, distance
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character :: Model }
		local hit = workspace:Raycast(root.Position, at - root.Position, params)
		return hit == nil or hit.Instance:IsDescendantOf(object), distance
	end
	if kept and valid(kept) then
		return kept
	end
	local best, nearest = nil, radius
	for _, object in CollectionService:GetTagged(tag) do
		local okay, distance = valid(object)
		if okay and distance < nearest then
			best, nearest = object, distance
		end
	end
	roundTargets[tag] = best
	return best
end

local function roundAction(): NextAction.Action
	local now = workspace:GetServerTimeNow()
	local gun = toolWith("Revolver")
	local murderer = player:GetAttribute("Role") == "Murderer"
	Ui.gui:SetAttribute("GuideRole", if murderer then "Murderer" else if gun then "Sheriff" else "Innocent")
	local input = if Ui.Phone
		then "Touch"
		else if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then "Gamepad" else "Keyboard"
	local reward = player:GetAttribute("RoundStepSpeed")
	if type(reward) == "number" then
		local kills = player:GetAttribute("RoundStepKills")
		local due = player:GetAttribute("RoundStepAt")
		if
			player:GetAttribute("RoundHide")
			or (not murderer and (not gun or toolWith("Revolver", true)))
			or toolWith("MurderKnife", true)
		then
			local step = if type(kills) == "number"
				then `🔪 {kills}`
				else `{if player:GetAttribute("RoundHide") then "" else "⏱ "}{math.max(
					0,
					math.ceil((if type(due) == "number" then due else now) - now)
				)}s`
			return {
				Id = "round_speed",
				Text = `{if player:GetAttribute("RoundHide") then "🔪 HIDE! " else ""}{step} → +{Ui.abbreviate(
					reward
				)} 👟`,
			}
		end
	end
	return RoundGuidance.Pick({
		Murderer = murderer,
		HasKnife = toolWith("MurderKnife") ~= nil,
		KnifeOut = toolWith("MurderKnife", true) ~= nil,
		HasGun = gun ~= nil,
		GunOut = toolWith("Revolver", true) ~= nil,
		WeaponWait = math.max(0, ((player:GetAttribute("WeaponAt") or now) :: number) - now),
		Reload = math.max(0, ((player:GetAttribute("RevolverReadyAt") or 0) :: number) - now),
		GunNearby = not murderer and not gun and visibleRoundTarget("RoundGunPickup", 45) ~= nil,
		Input = input,
	})
end

-- Where an action points: (the ⬇ spot, a ring on the ground, a thing that glows)
local function place(action: NextAction.Action): (Vector3?, Vector3?, Instance?)
	local kind = action.Target
	if kind == "Plate" then
		local model, at = Places.FreePlate()
		if at then
			return at + Vector3.new(0, 1, 0), nil, model
		end
		return Places.HomeSpot(), nil, nil
	elseif kind == "Coffin" then
		local coffin = Places.ReadyCoffin()
		return if coffin then coffin:GetPivot().Position else Places.HomeSpot(), nil, coffin
	elseif kind == "Home" then
		return Places.HomeSpot(), nil, nil
	elseif kind == "Vault" then
		return Places.VaultDoor(), nil, nil
	elseif kind == "Lair" and action.Zone then
		local zone = action.Zone
		local spot = Places.LairSpot(zone)
		local pad = Places.LairKnife(zone, true)
		if pad then
			return pad.Position + Vector3.new(0, 4, 0), nil, Places.KnifeOver(pad)
		end
		return spot, spot, nil
	elseif kind == "VaultSign" then
		local vault = Places.Vault()
		return Places.Sign("UpgradeSign"), nil, vault and vault:FindFirstChild("UpgradeSign")
	elseif kind == "Pad" then
		return Places.CashPad(), nil, nil
	elseif kind == "Gift" then
		for _, gift in CollectionService:GetTagged("SurpriseGift") do
			if gift:GetAttribute("Owner") == player.UserId then
				return Places.Gift(), nil, gift
			end
		end
		return nil, nil, nil
	elseif kind == "Sell" then
		local sale = Places.SpareSale()
		return if sale then sale.Position else Places.VaultDoor(), nil, sale
	elseif kind == "RoundCoin" or kind == "RoundGun" then
		local target = visibleRoundTarget(
			if kind == "RoundCoin" then "Coin" else "RoundGunPickup",
			if kind == "RoundCoin" then 80 else 45
		)
		if target then
			local at = if target:IsA("Model") then target:GetPivot().Position else (target :: BasePart).Position
			return at, nil, target
		end
	end
	return nil, nil, nil
end

function Guide.Init()
	Places.Init()
	local learned = GuidePolicy.Parse((player:GetAttribute("GuidanceLearned") or "") :: string)
	local reported: { [string]: boolean } = {}
	local function learn(skill: string)
		local limit = GuidePolicy.Limit(skill)
		if limit and (learned[skill] or 0) < limit and not reported[skill] then
			reported[skill] = true
			learned[skill] = limit
			ReplicatedStorage.Remotes.Tutorial:FireServer("GuideLearn", skill)
		end
	end
	Ui.LearnGuidance = learn
	player:GetAttributeChangedSignal("GuidanceLearned"):Connect(function()
		for skill, count in GuidePolicy.Parse((player:GetAttribute("GuidanceLearned") or "") :: string) do
			learned[skill] = math.max(learned[skill] or 0, count)
		end
	end)
	Ui.gui:SetAttribute("GuidanceMode", player:GetAttribute("GuidanceMode") or "Auto")
	player:GetAttributeChangedSignal("GuidanceMode"):Connect(function()
		Ui.gui:SetAttribute("GuidanceMode", player:GetAttribute("GuidanceMode") or "Auto")
	end)
	observedReach = NextAction.Reachable((player:GetAttribute("Speed") or 0) :: number)
	player:GetAttributeChangedSignal("Speed"):Connect(function()
		local reach = NextAction.Reachable((player:GetAttribute("Speed") or 0) :: number)
		if reach > observedReach then
			unlockedTier = reach
		end
		observedReach = reach
	end)
	Ui.gui:SetAttribute("GuideArrows", true)

	-- The DO line: like the status line, a thin dark band that fades out at both ends
	local band = Ui.new("CanvasGroup", {
		Name = "DoLine",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(8, 10, 22),
		BorderSizePixel = 0,
		Visible = false,
		GroupTransparency = 1,
		ZIndex = 41,
	}, Ui.gui) :: CanvasGroup
	Ui.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.16, 0.3),
			NumberSequenceKeypoint.new(0.84, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, band)
	local label = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		TextScaled = false,
		RichText = true,
		TextColor3 = Color3.fromRGB(255, 235, 120),
		Text = "",
		ZIndex = 42,
	}, band) :: TextLabel
	Ui.textStroke(label, 2)
	local pop = Ui.new("UIScale", { Scale = 1 }, label) :: UIScale

	local shownText = ""
	local displayAction: NextAction.Action? = nil
	local function fit()
		local _, bounds = Ui.bounds()
		-- (the objective: big, the first thing a kid reads - was 19 / 22)
		label.TextSize = if Ui.Phone then 28 else 36
		local strip = Ui.topStrip()
		local plain = shownText:gsub("<[^>]->", "")
		local width = TextService:GetTextSize(plain, label.TextSize, label.Font, Vector2.new(4000, 100)).X
		if width > (if strip then strip.W else math.huge) - 32 and displayAction and displayAction.Short then
			shownText = displayAction.Short
			label.Text = shownText
			plain = shownText:gsub("<[^>]->", "")
			width = TextService:GetTextSize(plain, label.TextSize, label.Font, Vector2.new(4000, 100)).X
		end
		-- Roblox's top bar is narrow on a phone (~280 px at 640 wide): a line that won't fit there even
		-- at the smallest size (20) goes just under it instead, across the whole screen (it overflowed
		-- the bar, cut off at both ends: "the screen to draw your")
		if strip then
			local smallest = TextService:GetTextSize(plain, 20, label.Font, Vector2.new(4000, 100)).X
			if smallest > strip.W - 32 then
				strip = nil
			end
		end
		local fade = if strip then 16 else FADE
		local room = if strip then strip.W else math.min(900, bounds.X - 24)
		local lane = room - 2 * fade
		if width > lane then
			-- shorter words first (down to 20), never two lines
			label.TextSize = math.max(20, math.floor(label.TextSize * lane / width))
			width = TextService:GetTextSize(plain, label.TextSize, label.Font, Vector2.new(4000, 100)).X
		end
		local height = if Ui.Phone then 44 else 54
		if strip then
			height = math.min(height, strip.H)
			band.Position = UDim2.fromOffset(strip.X, strip.Y + (strip.H - height) / 2)
		else
			band.Position = UDim2.fromScale(0.5, 0)
		end
		band.Size = UDim2.fromOffset(math.min(width + 8, lane) + 2 * fade, height)
		label.Size = UDim2.new(1, -2 * fade, 1, 0)
		Ui.gui:SetAttribute("DoLineInStrip", strip ~= nil)
		Ui.gui:SetAttribute("DoLineHeight", height)
	end
	Ui.Layout.Changed:Connect(fit)

	local current: NextAction.Action? = nil
	local completedCurrent = false
	local shownLogged = false
	local menuAction: NextAction.Action? = nil
	local since = os.clock() -- when the current action started
	local candidate: string? = nil
	local candidateSince = 0
	local stuckLogged = false
	local lastPos: Vector3? = nil
	local lastMoveAt = os.clock()
	local started = false
	local initialDistance: number? = nil
	local pathTarget: Vector3? = nil
	local indexEntered: number? = nil
	local idleHelp = false
	local helpMovement: Vector3? = nil

	local function show(action: NextAction.Action?)
		current = action
		committed = action ~= nil and not player:GetAttribute("InRound") and action.Id ~= "gift"
		completedCurrent = false
		shownLogged = false
		displayAction = action
		since = os.clock()
		stuckLogged = false
		started, initialDistance, pathTarget = false, nil, nil
		idleHelp, helpMovement = false, nil
		if action then
			Ui.gui:SetAttribute("GuideAction", action.Id)
			Ui.gui:SetAttribute("GuideActionAt", workspace:GetServerTimeNow())
			shownText = action.Text
			label.Text = action.Text
			fit()
			-- A change is not a completion (death, lost targets and interruptions change actions too).
			pop.Scale = 1.12
			TweenService:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end
	local function completed()
		if current and not completedCurrent then
			completedCurrent = true
			committed = false
			if shownLogged then
				Telemetry.Track("guide.done", { id = current.Id, seconds = math.floor(os.clock() - since) })
			end
			label.TextColor3 = Color3.fromRGB(120, 255, 140)
			TweenService:Create(label, TweenInfo.new(0.6), { TextColor3 = Color3.fromRGB(255, 235, 120) }):Play()
		end
	end
	player:GetAttributeChangedSignal("KnifePlacementSerial"):Connect(function()
		local item = player:GetAttribute("LastPlacedKnife")
		if type(item) == "string" and unlockedTier then
			local parsed = require(ReplicatedStorage.Shared.Items).Parse(item)
			if parsed and Knives.Rank(parsed.Knife.Rarity) >= unlockedTier then
				unlockedTier = nil
			end
		end
		if current and (current.Id:find("carry") or current.Id == "steal" or current.Id == "new_tier") then
			completed()
		end
	end)
	ReplicatedStorage.Remotes.Effect.OnClientEvent:Connect(function(kind: string)
		if kind == "CashBurst" then
			learn("collect")
		elseif kind == "IndexClaim" then
			learn("index")
		elseif kind == "SpeedPickup" and player:GetAttribute("InRound") then
			learn("coins")
			started = true
		end
		if
			current
			and ((kind == "CashBurst" and current.Id == "collect") or (kind == "IndexClaim" and current.Id == "index"))
		then
			completed()
		end
	end)
	for _, name in { "Slots" } do
		local previous = player:GetAttribute(name)
		player:GetAttributeChangedSignal(name):Connect(function()
			local value = player:GetAttribute(name)
			if type(previous) == "number" and type(value) == "number" and value > previous then
				learn("vault")
			end
			previous = value
			if current and (current.Id == "vault_bigger" or current.Id == "carry_bigger") then
				completed()
			end
		end)
	end
	for _, name in { "RevolverReadyAt" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			local ready = player:GetAttribute(name)
			if player:GetAttribute("InRound") and type(ready) == "number" and ready > workspace:GetServerTimeNow() then
				learn("gun_shoot")
			end
		end)
	end
	local function uiTarget(action: NextAction.Action?): GuiObject?
		if not action or not action.Ui then
			return nil
		end
		local target: GuiObject? = Ui.GuideTargets[action.Ui]
		if action.Ui == "Index" then
			target = if Ui.Panels.Index and Ui.Panels.Index.Visible
				then Ui.GuideTargets.IndexClaim
				else if Ui.menuOpen() then nil else Ui.GuideTargets.Index
		elseif action.Ui == "Rebirth" and not Ui.menuOpen() then
			target = Ui.GuideTargets.More
		end
		return target
	end
	local pulsed: { [GuiObject]: boolean } = {}
	local function pulseButton(button: GuiObject)
		if pulsed[button] then
			return
		end
		pulsed[button] = true
		local flash = Ui.new("Frame", {
			Name = "GuideButtonPulse",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = button.ZIndex,
			Active = false,
		}, button) :: Frame
		Ui.corner(flash, 9)
		local tween = TweenService:Create(
			flash,
			TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 2, true),
			{ BackgroundTransparency = 0.65 }
		)
		tween.Completed:Connect(function()
			flash:Destroy()
		end)
		tween:Play()
	end
	local function rendered(target: GuiObject): boolean
		local ancestor: Instance? = target
		while ancestor do
			if ancestor:IsA("GuiObject") and not ancestor.Visible then
				return false
			end
			if ancestor:IsA("ScreenGui") and not ancestor.Enabled then
				return false
			end
			ancestor = ancestor.Parent
		end
		return target.Parent ~= nil
	end

	local lastEval = 0
	local function hubAction(): NextAction.Action?
		local snapshot = state()
		if Ui.gui:GetAttribute("GuidanceMode") == "Auto" and (learned.index or 0) >= 1 then
			snapshot.IndexClaimable = 0 -- routine rewards remain on the badge, without blocking another lesson
		end
		return NextAction.Pick(snapshot)
	end
	RunService.Heartbeat:Connect(function(dt)
		local inRound = player:GetAttribute("InRound") == true
		if Ui.menuOpen() then
			if current and current.Ui then
				menuAction = current
			end
		else
			menuAction = nil
		end
		local tutorial = (Ui.gui:GetAttribute("TutorialRunning") == true or Arrows.Owner() == "Tutorial")
			and not inRound
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local indexPanel: GuiObject? = Ui.Panels.Index
		local indexOpen = indexPanel ~= nil
			and indexPanel.Visible
			and current ~= nil
			and current.Id == "index"
			and indexClaimable() > 0
		if indexOpen then
			indexEntered = indexEntered or os.clock()
		else
			indexEntered = nil
		end
		local blocked = tutorial
			or (Ui.menuOpen() and not indexOpen)
			or Ui.gui:GetAttribute("FadeCover") == true
			or Ui.gui:GetAttribute("Presenting") == true
			or not humanoid
			or humanoid.Health <= 0
			or (not inRound and not Ui.inHub())
			or player:GetAttribute("DataLoaded") ~= true
		if blocked then
			since += dt
		end
		if inRound then
			if toolWith("MurderKnife", true) then
				learn("knife_draw")
			end
			if toolWith("Revolver", true) then
				learn("gun_draw")
			end
		end
		-- Evaluate 4 times a second (and the arrows every frame)
		if os.clock() - lastEval >= 0.25 then
			lastEval = os.clock()
			if current and current.Id == "index" and indexClaimable() == 0 then
				completed()
				show(nil)
				menuAction = nil
			end
			local picked: NextAction.Action? = if blocked or indexOpen
				then current
				else if player:GetAttribute("Spectating")
					then {
						Id = "spectating",
						Text = "Back to stealing - tap the eye!",
						Ui = "SpectateExit",
					} :: NextAction.Action
					else if inRound then roundAction() else hubAction()
			local pickedId = picked and picked.Id
			if picked and current and pickedId == current.Id and picked.Zone == current.Zone then
				-- same action: keep it, but its words can change (Speed left)
				if picked.Text ~= shownText then
					shownText = picked.Text
					label.Text = picked.Text
					fit()
				end
				current = picked
				displayAction = picked
				candidate = nil
			elseif picked == nil then
				if current then
					show(nil)
				end
				candidate = nil
			else
				if candidate ~= pickedId then
					candidate, candidateSince = pickedId, os.clock()
				end
				if not current or inRound or URGENT[pickedId :: string] or os.clock() - candidateSince >= HOLD then
					show(picked)
					candidate = nil
				end
			end
			-- Stuck: same action a minute with no progress (standing still)
			local root = Places.Root()
			if root then
				if not lastPos or (root.Position - lastPos).Magnitude > 3 then
					lastPos, lastMoveAt = root.Position, os.clock()
				end
			end
			if inRound then
				lastMoveAt = os.clock()
			end
			if
				current
				and shownLogged
				and not blocked
				and not stuckLogged
				and os.clock() - since > STUCK
				and os.clock() - lastMoveAt > 20
			then
				stuckLogged = true
				Telemetry.Track("guide.stuck", { id = current.Id })
			end
		end
		local mode = (Ui.gui:GetAttribute("GuidanceMode") or "Auto") :: string
		local target: Vector3? = nil
		local ring: Vector3? = nil
		local glow: Instance? = nil
		if current then
			target, ring, glow = place(current)
		end
		local root = Places.Root()
		if target and root then
			if not pathTarget or (target - pathTarget).Magnitude > 6 then
				pathTarget, initialDistance = target, (root.Position - target).Magnitude
			end
			if initialDistance and initialDistance - (root.Position - target).Magnitude >= 6 then
				started = true
			end
		end
		-- Offer familiar help again only after a long idle; moving resumes independent play.
		if mode == "Auto" and not blocked and not inRound and os.clock() - lastMoveAt > 60 then
			if not idleHelp then
				idleHelp, helpMovement = true, root and root.Position
			end
		elseif idleHelp and root and helpMovement and (root.Position - helpMovement).Magnitude > 6 then
			idleHelp = false
		end
		local skill = current and GuidePolicy.Skill(current.Id)
		local visible = current ~= nil
			and not blocked
			and GuidePolicy.Visible({
				Mode = mode,
				Id = if current then current.Id else "",
				Skill = skill,
				Learned = learned,
				Age = os.clock() - (indexEntered or since),
				Started = started,
				Help = idleHelp,
			})
		if visible and current then
			if not shownLogged then
				shownLogged = true
				since = os.clock()
				Telemetry.Track(
					"guide.shown",
					{ id = current.Id, zone = current.Zone, source = if inRound then "round" else "hub" }
				)
			end
			local words = if indexOpen
				then "Tap CLAIM ALL!"
				else if mode == "Auto"
						and current.Id == "new_tier"
						and current.Zone
					then `You can outrun the {string.upper(GameConfig.MonsterName(current.Zone))}!`
					else current.Text
			if words ~= shownText then
				shownText, label.Text = words, words
				local decorated = table.clone(current)
				if indexOpen or (mode == "Auto" and current.Id == "new_tier") then
					decorated.Short = words
				end
				displayAction = decorated
				fit()
			end
		end
		local messageVisible = visible and (inRound or Ui.gui:GetAttribute("TopLineNotice") ~= true)
		local targetButton = uiTarget(current or menuAction)
		if messageVisible and targetButton and rendered(targetButton) and not tutorial then
			pulseButton(targetButton)
		end
		local alpha = if messageVisible then 0 else 1
		band.GroupTransparency += math.clamp(alpha - band.GroupTransparency, -dt / 0.25, dt / 0.25)
		band.Visible = not blocked and band.GroupTransparency < 1
		if Ui.gui:GetAttribute("DoLine") ~= band.Visible then
			Ui.gui:SetAttribute("DoLine", band.Visible)
		end
		-- the arrows
		if tutorial then
			return
		end
		local action = current
		-- (the trail on the ground is for new players: after a few murder rounds the DO line is enough)
		-- (except the core loop - steal, run home, place it - whose red trail is always on, like
		-- Steal An Egg / Steal from the Rich)
		local coreLoop = skill == "delivery"
		local beginner = coreLoop
			or ((player:GetAttribute("RoundsPlayed") or 0) :: number) < 3
				and ((player:GetAttribute("Rebirths") or 0) :: number) == 0
		if not visible or not action or not beginner or Ui.gui:GetAttribute("GuideArrows") == false then
			Arrows.Hide("Guide")
			return
		end
		if target and root then
			Arrows.Draw("Guide", {
				Target = target,
				Aim = Places.Aim(root.Position, target),
				Ring = ring,
				Glow = glow,
			})
		else
			Arrows.Hide("Guide")
		end
	end)
end

return Guide
