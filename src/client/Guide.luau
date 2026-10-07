--!strict
-- The guide: after the tutorial, ALWAYS one thing to do, shown two ways - the DO line at the very top
-- (one short instruction that never takes turns with anything) and the tutorial's arrows on the
-- ground to where it is (client/Arrows). What to do comes from shared/NextAction (pure, tested);
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
	carry_case = true,
	carry_full = true,
	carry_bigger = true,
	gift = true,
	new_tier = true,
}
local observedReach = 1
local unlockedTier: number? = nil
local committed = false

local function indexClaimable(): number
	local claimed = {}
	for _, name in Ui.list(player:GetAttribute("IndexClaimed")) do
		claimed[name] = true
	end
	local count = 0
	for _, name in Ui.list(player:GetAttribute("Discovered")) do
		if not claimed[name] and Knives.ByName[name] then
			count += 1
		end
	end
	return count
end

local function state(): NextAction.State
	local root = Places.Root()
	local stocked: { [number]: number? } = {}
	for i = 1, #GameConfig.Zones do
		stocked[i] = Places.Stocked(i)
	end
	local nextUpgrade = GameConfig.NextSpeedUpgrade(
		(player:GetAttribute("TreadmillLevel") or 1) :: number,
		(player:GetAttribute("TrailLevel") or 0) :: number
	)
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
		Carrying = if type(carrying) == "string" then carrying else nil,
		InVault = root ~= nil and Places.InVault(root.Position),
		FreePlate = plateAt ~= nil,
		KnifeCount = (player:GetAttribute("KnifeCount") or 0) :: number,
		Slots = (player:GetAttribute("Slots") or GameConfig.SlotsPerFloor) :: number,
		Rebirths = (player:GetAttribute("Rebirths") or 0) :: number,
		Cash = (player:GetAttribute("Cash") or 0) :: number,
		Income = (player:GetAttribute("Income") or 0) :: number,
		PendingCash = (player:GetAttribute("PendingCash") or 0) :: number,
		AutoCollect = player:GetAttribute("Pass_AutoCollect") == true
			or player:GetAttribute("SessionAutoCollect") == true,
		Speed = speed,
		Training = player:GetAttribute("Training") == true,
		BestOwnedRank = bestRank,
		Stocked = stocked,
		Gift = gift ~= nil,
		GiftNearby = root ~= nil and gift ~= nil and (root.Position - gift).Magnitude <= 20,
		Committed = committed,
		IndexClaimable = indexClaimable(),
		WheelCost = nextUpgrade and nextUpgrade.Cost,
		TutorialDone = player:GetAttribute("TutorialDone") == true,
		NewTier = unlockedTier,
		Spare = spare ~= nil,
		BetterReplacement = Places.BetterReplacement(reach, spareItem),
		WheelName = nextUpgrade and nextUpgrade.Name,
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
	return RoundGuidance.Pick({
		Murderer = murderer,
		HasKnife = toolWith("MurderKnife") ~= nil,
		KnifeOut = toolWith("MurderKnife", true) ~= nil,
		HasGun = gun ~= nil,
		GunOut = toolWith("Revolver", true) ~= nil,
		WeaponWait = math.max(0, ((player:GetAttribute("WeaponAt") or now) :: number) - now),
		Reload = math.max(0, ((player:GetAttribute("RevolverReadyAt") or 0) :: number) - now),
		Classic = ReplicatedStorage:GetAttribute("Classic") == true,
		Energy = (player:GetAttribute("Energy") or 0) :: number,
		UsesLeft = player:GetAttribute("PowerUsesLeft") :: number?,
		Power = player:GetAttribute("RoundPower") :: string?,
		Perk = player:GetAttribute("PowerId") :: string?,
		PerkPassive = player:GetAttribute("PerkPassive") == true,
		PerkUsesLeft = player:GetAttribute("PerkUsesLeft") :: number?,
		PerkWait = math.max(0, ((player:GetAttribute("PerkReadyAt") or 0) :: number) - now),
		Spam = ((player:GetAttribute("SpamUntil") or 0) :: number) > now,
		SecondLifeUsed = player:GetAttribute("SecondLifeUsed") == true,
		GunNearby = not murderer and not gun and visibleRoundTarget("RoundGunPickup", 45) ~= nil,
		Input = input,
		Stunned = math.max(0, ((player:GetAttribute("StunnedUntil") or 0) :: number) - now),
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
	elseif kind == "Wheel" then
		return Places.Wheel(), nil, nil
	elseif kind == "VaultSign" then
		local vault = Places.Vault()
		return Places.Sign("UpgradeSign"), nil, vault and vault:FindFirstChild("UpgradeSign")
	elseif kind == "WheelSign" then
		local vault = Places.Vault()
		return Places.Sign("WheelUpgradeSign"), nil, vault and vault:FindFirstChild("WheelUpgradeSign")
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
	local band = Ui.new("Frame", {
		Name = "DoLine",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(8, 10, 22),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 41,
	}, Ui.gui) :: Frame
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
		label.TextSize = if Ui.Phone then 19 else 22
		local strip = Ui.topStrip()
		local fade = if strip then 16 else FADE
		local room = if strip then strip.W else math.min(900, bounds.X - 24)
		local plain = shownText:gsub("<[^>]->", "")
		local width = TextService:GetTextSize(plain, label.TextSize, label.Font, Vector2.new(4000, 100)).X
		local lane = room - 2 * fade
		if width > lane and displayAction and displayAction.Short then
			shownText = displayAction.Short
			label.Text = shownText
			plain = shownText:gsub("<[^>]->", "")
			width = TextService:GetTextSize(plain, label.TextSize, label.Font, Vector2.new(4000, 100)).X
		end
		if width > lane then
			-- shorter words first (down to 14), never two lines
			label.TextSize = math.max(14, math.floor(label.TextSize * lane / width))
			width = TextService:GetTextSize(plain, label.TextSize, label.Font, Vector2.new(4000, 100)).X
		end
		local height = if Ui.Phone then 34 else 38
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
	local menuAction: NextAction.Action? = nil
	local since = os.clock() -- when the current action started
	local candidate: string? = nil
	local candidateSince = 0
	local stuckLogged = false
	local lastPos: Vector3? = nil
	local lastMoveAt = os.clock()

	local function show(action: NextAction.Action?)
		current = action
		committed = action ~= nil and not player:GetAttribute("InRound") and action.Id ~= "gift"
		completedCurrent = false
		displayAction = action
		since = os.clock()
		stuckLogged = false
		if action then
			Telemetry.Track("guide.shown", {
				id = action.Id,
				zone = action.Zone,
				source = if player:GetAttribute("InRound") then "round" else "hub",
			})
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
			Telemetry.Track("guide.done", { id = current.Id, seconds = math.floor(os.clock() - since) })
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
		if
			current
			and (
				(kind == "CashBurst" and current.Id == "collect")
				or (kind == "IndexClaim" and current.Id == "index")
				or (kind == "PowerUsed" and current.Id == "power_ready")
			)
		then
			completed()
		end
	end)
	for _, name in { "TreadmillLevel", "TrailLevel", "Slots" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			if
				current
				and (current.Id == "wheel_upgrade" or current.Id == "vault_bigger" or current.Id == "carry_bigger")
			then
				completed()
			end
		end)
	end
	local cue = Ui.new(
		"Frame",
		{ Name = "GuideUiCue", BackgroundTransparency = 1, Visible = false, ZIndex = 80 },
		Ui.gui
	) :: Frame
	Ui.new("UIStroke", { Color = Color3.fromRGB(255, 225, 80), Thickness = 3 }, cue)
	local function uiTarget(action: NextAction.Action?): GuiObject?
		if not action or not action.Ui then
			return nil
		end
		local target: GuiObject? = Ui.GuideTargets[action.Ui]
		if action.Ui == "Index" then
			target = if Ui.menuOpen()
				then Ui.gui:FindFirstChild("ClaimAll", true) :: GuiObject?
				else Ui.GuideTargets.Index
		elseif action.Ui == "Rebirth" and not Ui.menuOpen() then
			target = Ui.GuideTargets.More
		end
		return target
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
	RunService.Heartbeat:Connect(function()
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
		local blocked = tutorial
			or Ui.menuOpen()
			or Ui.gui:GetAttribute("FadeCover") == true
			or Ui.gui:GetAttribute("Presenting") == true
			or not humanoid
			or humanoid.Health <= 0
			or (not inRound and not Ui.inHub())
			or player:GetAttribute("DataLoaded") ~= true
		-- Evaluate 4 times a second (and the arrows every frame)
		if os.clock() - lastEval >= 0.25 then
			lastEval = os.clock()
			local picked = if blocked
				then current
				else if player:GetAttribute("Spectating")
					then { Id = "spectating", Text = "Back to stealing - tap the eye!", Ui = "SpectateExit" }
					else if inRound then roundAction() else NextAction.Pick(state())
			local pickedId = picked and picked.Id
			if picked and current and pickedId == current.Id then
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
			if player:GetAttribute("Training") or inRound then
				lastMoveAt = os.clock()
			end
			if
				current
				and not blocked
				and not stuckLogged
				and os.clock() - since > STUCK
				and os.clock() - lastMoveAt > 20
			then
				stuckLogged = true
				Telemetry.Track("guide.stuck", { id = current.Id })
			end
		end
		local visible = current ~= nil and not blocked
		local targetButton = uiTarget(current or menuAction)
		cue.Visible = targetButton ~= nil and rendered(targetButton) and not tutorial
		if cue.Visible and targetButton then
			local origin = Ui.root.AbsolutePosition
			local scale = math.max(Ui.Scale.Scale, 0.01)
			cue.Position = UDim2.fromOffset(
				(targetButton.AbsolutePosition.X - origin.X) / scale,
				(targetButton.AbsolutePosition.Y - origin.Y) / scale
			)
			cue.Size = UDim2.fromOffset(targetButton.AbsoluteSize.X / scale, targetButton.AbsoluteSize.Y / scale)
		end
		band.Visible = visible
		if Ui.gui:GetAttribute("DoLine") ~= visible then
			Ui.gui:SetAttribute("DoLine", visible)
		end
		-- the arrows
		if tutorial then
			return
		end
		local action = current
		if not visible or not action or Ui.gui:GetAttribute("GuideArrows") == false then
			Arrows.Hide("Guide")
			return
		end
		local target, ring, glow = place(action)
		local root = Places.Root()
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
