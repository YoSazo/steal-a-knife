--!strict
-- The guide: after the tutorial, ALWAYS one thing to do, shown two ways - the DO line at the very top
-- (one short instruction that never takes turns with anything) and the tutorial's arrows on the
-- ground to where it is (client/Arrows). What to do comes from shared/NextAction (pure, tested);
-- where it is from client/Places. The status line under it (client/TopLine) keeps the timer, the
-- prize and notices - information, never instructions.
--
-- Hidden while the tutorial runs (it owns the arrows), in rounds (the round has its own line), in
-- menus, fades and big cards (Ui.gui "Presenting"). Arrows can be turned off under More (session).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Places = require(script.Parent.Places)
local Arrows = require(script.Parent.Arrows)
local Telemetry = require(script.Parent.Telemetry)
local NextAction = require(ReplicatedStorage.Shared.NextAction)
local RoundPrize = require(ReplicatedStorage.Shared.RoundPrize)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local player = Players.LocalPlayer
local Guide = {}

local FADE = 56
local HOLD = 1 -- seconds a new action must last before the line switches (no flicker)
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
		Speed = (player:GetAttribute("Speed") or 0) :: number,
		Training = player:GetAttribute("Training") == true,
		BestOwnedRank = RoundPrize.Stats(player).BestRank,
		Stocked = stocked,
		Gift = Places.Gift() ~= nil,
		IndexClaimable = indexClaimable(),
		WheelCost = nextUpgrade and nextUpgrade.Cost,
		TutorialDone = player:GetAttribute("TutorialDone") == true,
	}
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
		local root = Places.Root()
		local close = root
			and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(spot.X, 0, spot.Z)).Magnitude < 16
		if close then
			-- at the wall: point at a knife on it, glowing
			local pad = Places.LairKnife(zone)
			if pad then
				return pad.Position + Vector3.new(0, 4, 0), nil, Places.KnifeOver(pad)
			end
		end
		return spot, spot, nil
	elseif kind == "Wheel" then
		return Places.Wheel(), nil, nil
	elseif kind == "VaultSign" then
		return Places.Sign("UpgradeSign"), nil, nil
	elseif kind == "WheelSign" then
		return Places.Sign("WheelUpgradeSign"), nil, nil
	elseif kind == "Pad" then
		return Places.CashPad(), nil, nil
	elseif kind == "Gift" then
		return Places.Gift(), nil, nil
	end
	return nil, nil, nil
end

function Guide.Init()
	Places.Init()
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
	local function fit()
		local _, bounds = Ui.bounds()
		label.TextSize = if Ui.Phone then 19 else 22
		local strip = Ui.topStrip()
		local fade = if strip then 16 else FADE
		local room = if strip then strip.W else math.min(900, bounds.X - 24)
		local plain = shownText:gsub("<[^>]->", "")
		local width = TextService:GetTextSize(plain, label.TextSize, label.Font, Vector2.new(4000, 100)).X
		local lane = room - 2 * fade
		if width > lane then
			-- shorter words first (down to 14), never two lines
			label.TextSize = math.max(14, math.floor(label.TextSize * lane / width))
			width = TextService:GetTextSize(plain, label.TextSize, label.Font, Vector2.new(4000, 100)).X
		end
		local height = if Ui.Phone then 34 else 38
		if strip then
			height = math.min(height, strip.H - 8)
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
	local since = os.clock() -- when the current action started
	local candidate: string? = nil
	local candidateSince = 0
	local stuckLogged = false
	local lastPos: Vector3? = nil
	local lastMoveAt = os.clock()

	local function show(action: NextAction.Action?)
		local previous = current
		current = action
		if previous and (not action or action.Id ~= previous.Id) then
			Telemetry.Track("guide.done", { id = previous.Id, seconds = math.floor(os.clock() - since) })
		end
		since = os.clock()
		stuckLogged = false
		if action then
			Telemetry.Track("guide.shown", { id = action.Id, zone = action.Zone })
			shownText = action.Text
			label.Text = action.Text
			fit()
			-- the switch: a little pop, and a green tick flash for the thing you just did
			pop.Scale = 1.12
			TweenService:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			if previous then
				label.TextColor3 = Color3.fromRGB(120, 255, 140)
				TweenService:Create(label, TweenInfo.new(0.6), { TextColor3 = Color3.fromRGB(255, 235, 120) }):Play()
			end
		end
	end

	local lastEval = 0
	RunService.RenderStepped:Connect(function()
		local tutorial = Arrows.Owner() == "Tutorial"
		local blocked = tutorial
			or Ui.menuOpen()
			or Ui.gui:GetAttribute("FadeCover") == true
			or Ui.gui:GetAttribute("Presenting") == true
			or player:GetAttribute("InRound") == true
			or player:GetAttribute("Spectating") == true
			or player:GetAttribute("DataLoaded") ~= true
		-- Evaluate 4 times a second (and the arrows every frame)
		if os.clock() - lastEval >= 0.25 then
			lastEval = os.clock()
			local picked = if blocked then nil else NextAction.Pick(state())
			local pickedId = picked and picked.Id
			if picked and current and pickedId == current.Id then
				-- same action: keep it, but its words can change (Speed left)
				if picked.Text ~= shownText then
					shownText = picked.Text
					label.Text = picked.Text
					fit()
				end
				current = picked
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
				if not current or URGENT[pickedId :: string] or os.clock() - candidateSince >= HOLD then
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
			if current and not stuckLogged and os.clock() - since > STUCK and os.clock() - lastMoveAt > 20 then
				stuckLogged = true
				Telemetry.Track("guide.stuck", { id = current.Id })
			end
		end
		local visible = current ~= nil and not blocked
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
