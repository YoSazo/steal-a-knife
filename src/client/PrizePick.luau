--!strict
-- "Win the murder round - pick your prize!": before each murder round, a card in the middle with two
-- big buttons, 💵 cash or 👟 Speed (RoundPrize: the same numbers the server pays). One tap and it's
-- YOUR prize: the line under the timer, the role reel and the win card all say what you picked
-- (player attribute PrizePick, Remotes.PrizePick). No tap = Speed. The prize used to be a small line
-- under the timer nobody noticed; a choice you make is one you care about, and "your prize" is a
-- reason to stay for the next round.
-- Shows GameConfig.RoundPrize.PickFrom..PickUntil s before a round, once per break, never while
-- carrying, in a menu, the tutorial or another presentation.
-- Each choice says what it DOES, never a promise it can't keep: cash "= BIGGER VAULT" only when it
-- makes the next floor affordable (else "= FASTER WHEEL", else nothing); Speed "= UNLOCK RARE
-- KNIVES" when it reaches the next boss. (Bigger vault and a Rare knife are the two first-visit
-- moments most linked to coming back: 27% / 23% vs 11%.)
-- A/B test "prize_pick" (server Analytics): only players in "pick" get the card (attribute
-- PrizePickOn); "classic" keeps the old Speed-only prize, to measure whether the choice works.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CartoonArt = require(ReplicatedStorage.Shared.Config.CartoonArt)
local RoundPrize = require(ReplicatedStorage.Shared.RoundPrize)
local Ui = require(script.Parent.Ui)
local SimpleUi = require(script.Parent.SimpleUi)

local player = Players.LocalPlayer
local CONFIG = GameConfig.RoundPrize
local PrizePick = {}

local function secondsLeft(): number?
	if
		ReplicatedStorage:GetAttribute("Phase") ~= "Intermission"
		or ReplicatedStorage:GetAttribute("Status") ~= "🔪 MURDER ROUND in"
	then
		return nil
	end
	return ((ReplicatedStorage:GetAttribute("PhaseEndsAt") or 0) :: number) - workspace:GetServerTimeNow()
end

-- Both prizes in this player's numbers (jackpot / Double Prize included, like the timer line)
local function offers(): (RoundPrize.Prize, RoundPrize.Prize)
	local jackpot = ReplicatedStorage:GetAttribute("PrizeJackpot") == true
	local doubled = ((player:GetAttribute("Charge_DoublePrize") or 0) :: number) > 0
	local stats = RoundPrize.Stats(player)
	stats.Pick = "Cash"
	local cash = RoundPrize.For("Speed", "", jackpot, 1, stats, doubled)
	stats.Pick = "Speed"
	local speed = RoundPrize.For("Speed", "", jackpot, 1, stats, doubled)
	return cash, speed
end

-- What the cash prize buys that you can't afford now (nil if nothing new)
local function cashBuys(amount: number): string?
	local cash = (player:GetAttribute("Cash") or 0) :: number
	local after = cash + amount
	local slots = (player:GetAttribute("Slots") or GameConfig.SlotsPerFloor) :: number
	local rebirths = (player:GetAttribute("Rebirths") or 0) :: number
	local floorCost = GameConfig.SlotCost(slots)
	if
		slots < GameConfig.MaxSlots
		and rebirths >= GameConfig.FloorRebirthsFor(slots)
		and cash < floorCost
		and after >= floorCost
	then
		return "BIGGER VAULT"
	end
	local nextWheel = GameConfig.Treadmills[((player:GetAttribute("TreadmillLevel") or 1) :: number) + 1]
	if nextWheel and cash < nextWheel.Cost and after >= nextWheel.Cost then
		return "FASTER WHEEL"
	end
	return nil
end

function PrizePick.Init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local card: Frame = Ui.new("Frame", {
		Name = "PrizePick",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromOffset(460, 220),
		BackgroundColor3 = Color3.fromRGB(28, 24, 40),
		BackgroundTransparency = 0.08,
		Visible = false,
		ZIndex = 30,
	}, Ui.root)
	Ui.corner(card, 18)
	Ui.new("UIStroke", { Color = Color3.fromRGB(255, 215, 70), Thickness = 4 }, card)
	local fit = Ui.new("UIScale", {}, card) :: UIScale
	SimpleUi.text(card, "Win the murder round!", {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -70, 0, 40),
		TextColor3 = Color3.fromRGB(255, 215, 70),
		ZIndex = 31,
		Max = 34,
	})
	SimpleUi.text(card, "Pick your prize:", {
		Position = UDim2.fromOffset(16, 50),
		Size = UDim2.new(1, -32, 0, 26),
		ZIndex = 31,
		Max = 24,
	})
	local answered = false
	local function choose(pick: string)
		Remotes.PrizePick:FireServer(pick)
		answered = true
		local pop = Ui.new("UIScale", {}, card) :: UIScale
		TweenService:Create(pop, TweenInfo.new(0.15), { Scale = 1.06 }):Play()
		task.delay(0.35, function()
			card.Visible = false
			pop:Destroy()
		end)
	end
	local cashButton = SimpleUi.button(card, "", Color3.fromRGB(70, 190, 90), {
		Name = "PickCash",
		Position = UDim2.fromOffset(16, 86),
		Size = UDim2.fromOffset(206, 96),
		ZIndex = 31,
		Max = 30,
	}, function()
		choose("Cash")
	end, CartoonArt.Cash)
	local speedButton = SimpleUi.button(card, "", Color3.fromRGB(70, 140, 235), {
		Name = "PickSpeed",
		Position = UDim2.fromOffset(238, 86),
		Size = UDim2.fromOffset(206, 96),
		ZIndex = 31,
		Max = 30,
	}, function()
		choose("Speed")
	end, CartoonArt.Speed)
	-- what each one does, under its button
	local cashNote = SimpleUi.text(card, "", {
		Position = UDim2.fromOffset(16, 186),
		Size = UDim2.fromOffset(206, 26),
		TextColor3 = Color3.fromRGB(150, 245, 160),
		ZIndex = 31,
		Max = 22,
	})
	local reach = SimpleUi.text(card, "", {
		Position = UDim2.fromOffset(238, 186),
		Size = UDim2.fromOffset(206, 26),
		TextColor3 = Color3.fromRGB(140, 210, 255),
		ZIndex = 31,
		Max = 22,
	})
	SimpleUi.button(card, "X", Color3.fromRGB(230, 40, 50), {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(40, 40),
		ZIndex = 32,
		Max = 24,
	}, function()
		answered = true -- (keeps Speed, or whatever they picked last time)
		card.Visible = false
	end)

	local lastRefresh = 0
	local inWindow = false
	RunService.Heartbeat:Connect(function()
		if os.clock() - lastRefresh < 0.25 then
			return
		end
		lastRefresh = os.clock()
		local left = secondsLeft()
		local window = left ~= nil and left <= CONFIG.PickFrom and left > CONFIG.PickUntil
		if window and not inWindow then
			answered = false -- a new break: ask again
		end
		inWindow = window
		local show = window
			and not answered
			and player:GetAttribute("PrizePickOn") == true
			and not player:GetAttribute("InRound")
			and not player:GetAttribute("Carrying")
			and not Ui.menuOpen()
			and Ui.gui:GetAttribute("TutorialBar") ~= true
			and Ui.gui:GetAttribute("Presenting") ~= true
		if show and not card.Visible then
			local screen = workspace.CurrentCamera.ViewportSize
			local s = math.max(Ui.Scale.Scale, 0.01) -- (Ui.root is already scaled by this)
			fit.Scale = math.min(1, (screen.Y - 30) / (220 * s), (screen.X - 30) / (460 * s))
		end
		card.Visible = show
		if not show then
			return
		end
		local cash, speed = offers()
		SimpleUi.set(cashButton, `<b>{cash.Text}</b>`)
		SimpleUi.set(speedButton, `<b>{speed.Text}</b>`)
		-- what the Speed is for, in knives you can see ("= RARE knives!" when it gets you there)
		reach.Text = if speed.Rarity and speed.Reaches
			then `UNLOCK {string.upper(speed.Rarity)} KNIVES!`
			elseif speed.Rarity then `toward {string.upper(speed.Rarity)} knives`
			else ""
		local buys = cashBuys(cash.Amount)
		cashNote.Text = if buys then `{buys}!` else ""
	end)
end

return PrizePick
