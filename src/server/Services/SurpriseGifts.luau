--!strict
-- Surprise gifts (Steal An Egg's "keep playing, something might drop"): every few minutes of play,
-- at a random moment, a glowing present lands just outside YOUR vault's gate (a spot you can always
-- reach - dropped in front of you, it landed in odd places or mid-chase). Usually cash or a wheel
-- spin, sometimes luck or a case, rarely a big case the whole server hears about. Only its owner
-- sees it: the parts are invisible on the server and the owner's client shows them (client/Effects),
-- so nobody mistakes someone else's gift for theirs. Never during a round or while carrying a knife.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(script.Parent.Parent.Remotes)
local Analytics = require(script.Parent.Analytics)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local Gamble = require(script.Parent.Gamble)
local StealService = require(script.Parent.StealService)

local SurpriseGifts = {}

type Prize = { Kind: string, Weight: number, Seconds: number?, Rarity: string?, Count: number?, Announce: boolean? }
local CONFIG = GameConfig.SurpriseGift
local PRIZES = CONFIG.Prizes :: { Prize }

local rng = Random.new()
local nextAt: { [Player]: number } = {} -- seconds of hub play left until the next gift
local gifts: { [Player]: Model } = {}
local folder: Folder

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function roll(): Prize
	local total = 0
	for _, prize in PRIZES do
		total += prize.Weight
	end
	local pick = rng:NextNumber() * total
	for _, prize in PRIZES do
		pick -= prize.Weight
		if pick <= 0 then
			return prize
		end
	end
	return PRIZES[1]
end

-- A present: a box in a bright colour, a gold ribbon both ways and a bow, glowing a little
local COLORS = {
	Color3.fromRGB(255, 80, 120),
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(120, 220, 90),
	Color3.fromRGB(190, 110, 255),
}
local function buildGift(at: CFrame): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "SurpriseGift"
	local function part(name: string, size: Vector3, offset: CFrame, color: Color3, neon: boolean?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = at * offset
		p.Color = color
		p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
		p:SetAttribute("Look", 0)
		p.Transparency = 1
		p.Parent = model
		return p
	end
	local body = part("Box", Vector3.new(3, 2.6, 3), CFrame.new(), COLORS[rng:NextInteger(1, #COLORS)])
	local gold = Color3.fromRGB(255, 215, 80)
	part("RibbonA", Vector3.new(3.1, 2.7, 0.5), CFrame.new(), gold, true)
	part("RibbonB", Vector3.new(0.5, 2.7, 3.1), CFrame.new(), gold, true)
	part("Lid", Vector3.new(3.3, 0.5, 3.3), CFrame.new(0, 1.4, 0), body.Color)
	part("BowL", Vector3.new(1, 0.7, 0.4), CFrame.new(-0.45, 1.95, 0) * CFrame.Angles(0, 0, math.rad(30)), gold, true)
	part("BowR", Vector3.new(1, 0.7, 0.4), CFrame.new(0.45, 1.95, 0) * CFrame.Angles(0, 0, math.rad(-30)), gold, true)
	model.PrimaryPart = body
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = gold
	sparkles.Enabled = false
	sparkles.Parent = body
	return model, body
end

local function give(player: Player, prize: Prize): string
	local income = math.max(1, BaseService.RackIncome(player))
	if prize.Kind == "Cash" then
		local cash = math.max(CONFIG.MinCash, math.floor(income * (prize.Seconds or 60)))
		DataService.AddCash(player, cash, "gift")
		return `+{Format.Cash(cash)}`
	elseif prize.Kind == "Spin" then
		Gamble.AddSpins(player, prize.Count or 1)
		return if (prize.Count or 1) > 1 then `{prize.Count} free spins` else "a free spin"
	elseif prize.Kind == "Luck" then
		Gamble.AddLuck(player, prize.Seconds or 300)
		return `2x luck for {math.floor((prize.Seconds or 300) / 60)} min`
	elseif prize.Kind == "Case" then
		local rarity = prize.Rarity or "Rare"
		if StealService.OpenCase(player, rarity) then
			if prize.Announce then
				Net.Announce(
					`🎁 {player.DisplayName} found a {rarity} Case in a gift!`,
					Color3.fromRGB(255, 200, 80),
					2
				)
			end
			return `a {rarity} Case`
		end
		-- vault full: the case's worth in cash instead
		local cash = math.max(CONFIG.MinCash, math.floor(income * 600))
		DataService.AddCash(player, cash, "gift")
		return `+{Format.Cash(cash)}`
	end
	return ""
end

local function clear(player: Player)
	local gift = gifts[player]
	gifts[player] = nil
	if gift then
		gift:Destroy()
	end
end

local function drop(player: Player)
	local root = rootOf(player)
	if not root or gifts[player] then
		return
	end
	local spot: Vector3
	local base = BaseService.GetBase(player)
	if base then
		local gate = base.Gate:GetPivot().Position
		local outward = base.Frame:VectorToWorldSpace(Vector3.zAxis)
		local toWheel = base.Treadmill.Position - gate
		local side = toWheel - outward * toWheel:Dot(outward)
		side = if side.Magnitude > 0.1 then side.Unit else base.Frame.RightVector
		spot = gate + outward * 8 - side * 7
	else
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		look = if look.Magnitude > 0.1 then look.Unit else Vector3.zAxis
		spot = root.Position + look * 9
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { (player.Character :: any) :: Instance, folder }
	-- Down from a little above, skipping invisible walls and blockers
	local ground = spot.Y - 5
	local from = Vector3.new(spot.X, spot.Y + 6, spot.Z)
	for _ = 1, 6 do
		local hit = workspace:Raycast(from, Vector3.new(0, -30, 0), params)
		if not hit then
			break
		end
		if hit.Instance.Transparency < 0.95 and hit.Instance.CanCollide then
			ground = hit.Position.Y
			break
		end
		from = hit.Position - Vector3.new(0, 0.05, 0)
	end
	local model, body = buildGift(CFrame.new(spot.X, ground + 1.8, spot.Z))
	model:SetAttribute("Owner", player.UserId)
	model:AddTag("SurpriseGift")
	model:AddTag("Spin")
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = "Gift"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	model.Parent = folder
	gifts[player] = model
	Net.Remotes.Effect:FireClient(player, "GiftDrop", body.Position)
	Net.Notify(player, "🎁 Gift waiting at your vault.", "good")
	Analytics.Track(player, "gift.drop")
	prompt.Triggered:Connect(function(who)
		if who ~= player or gifts[player] ~= model then
			return
		end
		gifts[player] = nil
		local at = body.Position
		model:Destroy()
		local prize = roll()
		local what = give(player, prize)
		Net.Remotes.Effect:FireClient(player, "GiftOpen", at, what, prize.Kind)
		Net.Notify(player, `🎁 You got {what}!`, "good")
		Analytics.Track(player, "gift.open", { prize = prize.Kind, rarity = prize.Rarity, seconds = prize.Seconds })
		Analytics.Milestone(player, "gift_opened")
	end)
	task.delay(CONFIG.Lifetime, function()
		if gifts[player] == model then
			clear(player)
			Analytics.Track(player, "gift.expired")
		end
	end)
end

local function schedule(player: Player)
	nextAt[player] = rng:NextNumber(CONFIG.MinGap, CONFIG.MaxGap)
end

-- Bring the next gift forward to `seconds` from now (after dying to the Murderer)
function SurpriseGifts.Soon(player: Player, seconds: number)
	local left = nextAt[player]
	if left and left > seconds then
		nextAt[player] = seconds
	end
end

-- Studio: drop one now (DebugService "Gift")
function SurpriseGifts.DebugDrop(player: Player)
	clear(player)
	drop(player)
end

function SurpriseGifts.Init()
	folder = Instance.new("Folder")
	folder.Name = "SurpriseGifts"
	folder.Parent = workspace:FindFirstChild("Map") or workspace
	DataService.PlayerLoaded:Connect(function(player: Player)
		-- the first one comes a bit sooner, so a new player meets it early
		nextAt[player] = rng:NextNumber(CONFIG.FirstMin, CONFIG.FirstMax)
	end)
	Players.PlayerRemoving:Connect(function(player)
		clear(player)
		nextAt[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(5)
			for player, left in nextAt do
				-- the clock only runs while you're playing in the hub
				if
					player:GetAttribute("InRound")
					or not rootOf(player)
					or gifts[player]
					or StealService.IsCarrying(player)
				then
					continue
				end
				left -= 5
				if left <= 0 then
					drop(player)
					schedule(player)
				else
					nextAt[player] = left
				end
			end
			-- a round pulls you away: your waiting gift goes
			for player in gifts do
				if player:GetAttribute("InRound") then
					clear(player)
				end
			end
		end
	end)
end

return SurpriseGifts
