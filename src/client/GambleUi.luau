--!strict
-- The Lucky Wheel panel (server: Gamble) and the luck-potion timer. No HUD button: the wheel stands
-- on the plaza.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local WheelArt = require(ReplicatedStorage.Shared.Config.LuckyWheelArt).Images :: { [string]: string }
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local new = Ui.new

local GambleUi = {}

local PINK = Color3.fromRGB(255, 90, 190)
local PURPLE = Color3.fromRGB(150, 80, 255)
-- A plain white triangle (point at the hub end, black-outlined), tinted per prize via
-- ImageColor3 - a real pizza wedge, not a rectangle (assets/ui/wedge/WedgeTriangle.png).
local WEDGE_IMAGE = "rbxassetid://136440766940606"

local function today(): number
	return math.floor(workspace:GetServerTimeNow()) // 86400
end

-- Lucky Wheel ---------------------------------------------------------------------------------------

local function buildWheel()
	local prizes = GameConfig.Spin.Prizes
	local total = 0
	for _, prize in prizes do
		total += prize.Weight
	end
	local frame, body = Theme.shell("LuckyWheel", "Lucky Wheel", PINK, "Spin", 660, 860)
	-- The wheel: a disc with one coloured spoke + label per prize, turned to land on the prize
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(440, 440),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, body)
	-- `disc` stands for Codex's 512x512 reference canvas, scaled down to fit the holder; every
	-- position below is taken straight from the art's own measurements (HANDOFF.md) so the rim's
	-- opening, the hub and the pointer's tip all line up with the code-drawn wedges.
	local disc = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, holder)
	local step = 360 / #prizes
	local colors = { PINK, Color3.fromRGB(80, 200, 255), Color3.fromRGB(255, 200, 60), Color3.fromRGB(120, 230, 110) }
	for i, prize in prizes do
		-- A full-size layer per slice, turned about the wheel's centre (a GuiObject turns about its
		-- own centre, so the slice itself can't be rotated directly); the slice runs from the centre
		-- up to just under the rim's inner edge
		local layer = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Rotation = (i - 1) * step,
			BackgroundTransparency = 1,
			ZIndex = 8,
		}, disc)
		-- An actual triangle (point at the hub, wide at the rim) tinted per prize, not a plain
		-- rectangle - a rectangle reads as a square slice, not a pizza wedge. ScaleType.Stretch
		-- maps the image's square canvas onto this narrow box, which is what elongates the
		-- triangle into a proper wedge.
		-- (wedges reach almost the whole radius now: no decorative rim, just a plain circle, so
		-- the prize text can be big enough to read on a phone)
		local slice = new("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(2 * 0.47 * math.tan(math.rad(step / 2)), 0.47),
			BackgroundTransparency = 1,
			Image = WEDGE_IMAGE,
			ImageColor3 = colors[(i - 1) % #colors + 1],
			ScaleType = Enum.ScaleType.Stretch,
			ZIndex = 8,
		}, layer)
		local text = Theme.text(slice, prize.Label, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 8),
			Size = UDim2.fromScale(0.86, 0.42),
			MaximumTextSize = 30,
			ZIndex = 9,
		})
		text.TextWrapped = true
	end
	-- A plain circle round the edge and a small dot in the middle (no decorated rim)
	local ring = new("Frame", {
		Name = "Rim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.95, 0.95),
		BackgroundTransparency = 1,
		ZIndex = 9,
	}, disc)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	new("UIStroke", { Color = Color3.fromRGB(16, 14, 24), Thickness = 6 }, ring)
	local hub = new("Frame", {
		Name = "Hub",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.1, 0.1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 10,
	}, disc)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, hub)
	new("UIStroke", { Color = Color3.fromRGB(16, 14, 24), Thickness = 4 }, hub)
	-- The pointer stays fixed (outside `disc`, which spins) at twelve o'clock, its painted tip
	-- anchored so it reaches just over the winning wedge rather than sitting against the rim.
	new("ImageLabel", {
		Name = "Pointer",
		AnchorPoint = Vector2.new(255 / 512, 447 / 512),
		Position = UDim2.fromScale(0.5, 0.075), -- the tip just over the circle's top edge
		Size = UDim2.fromScale(96 / 512, 96 / 512),
		BackgroundTransparency = 1,
		Image = WheelArt.WheelPointer,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 12,
	}, holder)
	-- Odds list on the right: one small coloured pill per prize (matching its wedge), Powers-style.
	-- A fixed width (not "parent minus a constant") so it can't ever run past the window's edge.
	local ODDS_WIDTH = 350
	local ODDS_HEIGHT = 398
	local list = new("ScrollingFrame", {
		Position = UDim2.fromOffset(470, 6),
		Size = UDim2.fromOffset(ODDS_WIDTH, ODDS_HEIGHT),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 7,
	}, body)
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	Theme.text(list, "ODDS", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 30), MaximumTextSize = 26 })
	for i, prize in prizes do
		local chance = prize.Weight / total * 100
		local pillColor = colors[(i - 1) % #colors + 1]
		-- Leaves a little room on the right for the scrollbar so it doesn't sit on top of the %.
		local row = Theme.surface(list, { LayoutOrder = i, Size = UDim2.new(1, -8, 0, 38) }, pillColor)
		Theme.text(row, prize.Label, {
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -86, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaximumTextSize = 22,
		})
		Theme.text(row, string.format(if chance < 1 then "%.1f" else "%.0f", chance) .. "%", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(68, 28),
			MaximumTextSize = 22,
		})
	end
	-- A soft dark fade at the bottom of the list instead of an abrupt hard cut, hinting there's
	-- more below without a row looking half-chopped-off.
	local fade = new("Frame", {
		Position = UDim2.fromOffset(470, 6 + ODDS_HEIGHT - 28),
		Size = UDim2.fromOffset(ODDS_WIDTH, 28),
		BackgroundColor3 = Color3.fromRGB(14, 16, 26),
		BorderSizePixel = 0,
		ZIndex = 8,
	}, body)
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0.25),
		}),
	}, fade)
	local status = Theme.text(body, "", {
		Position = UDim2.new(0, 470, 1, -140),
		Size = UDim2.fromOffset(ODDS_WIDTH, 30),
		MaximumTextSize = 22,
	})
	local spinning = false
	local spinButton: TextButton
	spinButton = Theme.button(body, "SPIN!", Theme.Green, {
		Position = UDim2.new(0, 470, 1, -104),
		Size = UDim2.new(0.5, -246, 0, 90),
		MaximumTextSize = 44,
	}, function()
		if spinning then
			return
		end
		local ok, _message, index = Remotes.Gamble:InvokeServer("Spin")
		if not ok or type(index) ~= "number" then
			return
		end
		spinning = true
		-- Land the chosen spoke under the pointer, after a few full turns
		local target = -((index - 1) * step) + 360 * 6 + math.random(-8, 8)
		disc.Rotation %= 360
		local tween = TweenService:Create(
			disc,
			TweenInfo.new(GameConfig.Spin.RevealDelay - 0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Rotation = target }
		)
		tween:Play()
		tween.Completed:Wait()
		spinning = false
	end)
	Theme.button(body, "Get spins", PURPLE, {
		Position = UDim2.new(0.5, 240, 1, -104),
		Size = UDim2.new(0.5, -246, 0, 90),
		MaximumTextSize = 32,
	}, function()
		if Ui.Buy then
			Ui.Buy("Product", "Spins10")
		end
	end)
	local function refresh()
		local spins = (player:GetAttribute("Spins") or 0) :: number
		local free = player:GetAttribute("FreeSpinDay") ~= today()
		status.Text = if free then "Your FREE daily spin is ready!" else `Spins: {spins}  (+1 every 15 min played)`
		Theme.enabled(spinButton, free or spins > 0)
	end
	player:GetAttributeChangedSignal("Spins"):Connect(refresh)
	player:GetAttributeChangedSignal("FreeSpinDay"):Connect(refresh)
	frame:GetPropertyChangedSignal("Visible"):Connect(refresh)
	refresh()
	return frame
end

-- Luck timer pill -----------------------------------------------------------------------------------

local function buildLuckTimer()
	local pill = Theme.text(Ui.gui, "", {
		Name = "LuckTimer",
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.fromOffset(190, 30),
		MaximumTextSize = 20,
		TextColor3 = Color3.fromRGB(120, 255, 130),
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
	})
	pill.RichText = true
	-- Every running boost, one line each, so you can see it ticking down (and top it up)
	local BOOSTS = {
		{ "LuckUntil", "🍀 2x Luck", "#78FF82" },
		{ "Boost_Speed", "⚡ Speed", "#FFDC3C" },
		{ "Boost_Cash", "💵 2x Cash", "#78FF82" },
		{ "Boost_Training", "🎡 3x Training", "#78C8FF" },
	}
	local last = ""
	RunService.Heartbeat:Connect(function()
		local lines = {}
		for _, boost in BOOSTS do
			local ends = player:GetAttribute(boost[1])
			local left = if type(ends) == "number" then ends - os.time() else 0
			if left > 0 then
				table.insert(lines, `<font color="{boost[3]}">{boost[2]} {Ui.clock(left)}</font>`)
			end
		end
		pill.Visible = #lines > 0 and not Ui.menuOpen() and Ui.inHub()
		-- Sits just above the Speed / Cash readout (bottom left), out of the buttons' way
		local stats = Ui.gui:FindFirstChild("Stats") :: GuiObject?
		local holder = pill.Parent :: GuiObject?
		if stats and holder and holder:IsA("GuiBase2d") then
			local factor = Ui.Scale.Scale
			local at = (stats.AbsolutePosition - holder.AbsolutePosition) / factor
			-- (phones: the readout is up top-left, so above it ran under Roblox's own buttons -
			-- go under it instead)
			pill.Position = if Ui.Phone
				then UDim2.fromOffset(at.X, at.Y + stats.AbsoluteSize.Y / factor + 4)
				else UDim2.fromOffset(at.X, at.Y - 4)
			pill.AnchorPoint = if Ui.Phone then Vector2.zero else Vector2.new(0, 1)
		end
		local text = table.concat(lines, "\n")
		if text ~= last then
			last = text
			pill.Text = text
			pill.Size = UDim2.fromOffset(190, 26 * math.max(1, #lines))
		end
	end)
end

function GambleUi.Init()
	local wheel = buildWheel()
	buildLuckTimer()
	-- No HUD button: the Lucky Wheel stands on the plaza (server PlazaWheel); stepping onto its ring
	-- opens this panel (client/Menus)
	Ui.Panels.Spin = wheel
	-- Over the wheel: "🎁 2 FREE SPINS!" (just yours), and the wheel face turns slowly
	local badgeGui = new("BillboardGui", {
		Name = "FreeSpins",
		Size = UDim2.fromScale(9, 1.6), -- (studs: shrinks with distance)
		LightInfluence = 0,
		MaxDistance = 260,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	local badgeText = new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 235, 90),
		Text = "",
	}, badgeGui)
	Ui.textStroke(badgeText, 3)
	local function spinCount(): number
		local spins = (player:GetAttribute("Spins") or 0) :: number
		local free = player:GetAttribute("FreeSpinDay") ~= today()
		return spins + (if free then 1 else 0)
	end
	local turn = 0
	RunService.Heartbeat:Connect(function(dt: number)
		local anchor = CollectionService:GetTagged("LuckyWheelBadge")[1]
		local count = spinCount()
		badgeGui.Adornee = anchor
		badgeGui.Enabled = anchor ~= nil and count > 0 and Ui.inHub()
		badgeText.Text = if count == 1 then "🎁 1 FREE SPIN!" else `🎁 {count} FREE SPINS!`
		turn = (turn + dt * 12) % 360
		local face = CollectionService:GetTagged("LuckyWheelFace")[1]
		local disc = face and face:FindFirstChild("Disc", true) :: GuiObject?
		if disc and not wheel.Visible then
			disc.Rotation = turn
		end
	end)
end

return GambleUi
