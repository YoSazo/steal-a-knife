--!strict
-- THE line across the top of the screen, in the tutorial's style (Steal An Egg's top line): a thin
-- dark band that fades out at both ends, only as wide as its words.
--
-- Most of the time it rests on what client/Hud gives it (TopLine.Resting: "🔪 MURDER ROUND in 3:12",
-- in the last minute the prize lines in turn, after the tutorial your next goal, in a round "Office
-- 2:15 · 2 alive"). A notice (TopLine.Show: zone titles, announcements, "Equipped", tips, "Round
-- over!") takes its place for a few seconds, one at a time, and then it goes back.
--
-- It sits right under the tutorial's own line while that's up (Ui.gui TutorialBar /
-- TutorialBarHeight). Ui.gui TopLineHeight = how far down it reaches (client/Hud puts the rest under
-- it).
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)

local TopLine = {}

export type Rest = { Text: string, Pill: boolean?, Pulse: boolean? }
-- Set by client/Hud: what the line says when no notice is up (nil = hidden)
TopLine.Resting = nil :: (() -> Rest?)?

local FADE = 56
type Entry = { Text: string, Seconds: number, Key: string? }
local queue: { Entry } = {}
local showing: Entry? = nil
local token = 0
local band: Frame? = nil
local label: TextLabel? = nil
local pill: GuiObject? = nil
local pulse: UIScale? = nil
local shownText = ""
local shownPill = false

local function baseHeight(): number
	return if Ui.Phone then 32 else 34
end

local function build()
	local frame = Ui.new("Frame", {
		Name = "TopLine",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(8, 10, 22),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 40,
	}, Ui.gui) :: Frame
	Ui.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.16, 0.45),
			NumberSequenceKeypoint.new(0.84, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, frame)
	local text = Ui.label({
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(FADE, 0),
		TextScaled = false,
		TextColor3 = Color3.new(1, 1, 1),
		TextWrapped = true,
		RichText = true,
		Text = "",
		ZIndex = 41,
	}, frame)
	Ui.textStroke(text, 1.5)
	pulse = Ui.new("UIScale", { Scale = 1 }, text) :: UIScale
	band, label = frame, text
end

-- Size the band to `text` (and the pill after it) and place it under the tutorial's line
local function fit(text: string, withPill: boolean)
	local frame, words = band, label
	if not frame or not words then
		return
	end
	local _, bounds = Ui.bounds()
	words.TextSize = if Ui.Phone then 18 else 20
	local pillWidth = if withPill and pill then pill.AbsoluteSize.X / math.max(Ui.Scale.Scale, 0.01) + 8 else 0
	-- (phones: keep the words between the left and right button columns)
	local maxLane = math.max(160, math.min(860, bounds.X - (if Ui.Phone then 2 * 175 else 2 * FADE + 24)) - pillWidth)
	local plain = text:gsub("<[^>]->", "") -- (RichText tags take no space)
	-- A bit too long for one line: smaller words first (down to 14), wrapping only after that
	local oneLine = TextService:GetTextSize(plain, words.TextSize, words.Font, Vector2.new(4000, 1000)).X
	if oneLine > maxLane then
		words.TextSize = math.max(14, math.floor(words.TextSize * maxLane / oneLine))
	end
	local size = TextService:GetTextSize(plain, words.TextSize, words.Font, Vector2.new(maxLane, 1000))
	local lane = math.min(maxLane, size.X + 6)
	local tall = math.max(baseHeight(), size.Y + 8)
	frame.Size = UDim2.fromOffset(math.min(bounds.X, lane + pillWidth + 2 * FADE), tall)
	words.Size = UDim2.fromOffset(lane, tall)
	if pill then
		pill.Visible = withPill
		pill.AnchorPoint = Vector2.new(0, 0.5)
		pill.Position = UDim2.new(0, FADE + lane + 8, 0.5, 0)
	end
	local top = if Ui.gui:GetAttribute("TutorialBar") == true
		then ((Ui.gui:GetAttribute("TutorialBarHeight") or 36) :: number) + 2
		else 0
	frame.Position = UDim2.new(0.5, 0, 0, top)
	local bottom = if frame.Visible then top + tall + 2 else top
	if Ui.gui:GetAttribute("TopLineHeight") ~= bottom then
		Ui.gui:SetAttribute("TopLineHeight", bottom)
	end
end

local function nextOne()
	showing = table.remove(queue, 1)
	token += 1
	local entry = showing
	if not entry then
		shownText = "" -- (back to resting: the next tick redraws it)
		return
	end
	local mine = token
	local text = label :: TextLabel
	text.TextTransparency = 0
	shownText = entry.Text
	shownPill = false
	text.Text = entry.Text
	if band then
		band.Visible = true
	end
	fit(entry.Text, false)
	local scale = pulse :: UIScale
	scale.Scale = 1.08
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(entry.Seconds, function()
		if mine == token then
			nextOne()
		end
	end)
end

-- Shows `text` (RichText allowed) for `seconds` in place of the resting line. A `key` replaces a
-- queued or showing notice with the same key (three zones walked through fast: just the last).
function TopLine.Show(text: string, seconds: number?, key: string?)
	if not band then
		build()
	end
	local entry: Entry = { Text = text, Seconds = seconds or 2.5, Key = key }
	if key then
		for i = #queue, 1, -1 do
			if queue[i].Key == key then
				table.remove(queue, i)
			end
		end
		local current = showing
		if current and current.Key == key then
			table.insert(queue, 1, entry)
			nextOne()
			return
		end
	end
	table.insert(queue, entry)
	while #queue > 3 do -- (never a long wait behind old news)
		table.remove(queue, 1)
	end
	if not showing then
		nextOne()
	end
end

-- Hands a button to the line (Hud's "x2 R$25"): it sits after the words when the resting line asks
function TopLine.SetPill(button: GuiObject)
	if not band then
		build()
	end
	pill = button
	button.Parent = band
	button.Visible = false
	button.ZIndex = 42
end

function TopLine.Init()
	if not band then
		build()
	end
	-- Resting: redraw when the words change (the timer ticks once a second)
	RunService.RenderStepped:Connect(function()
		local frame, text = band, label
		if not frame or not text or showing then
			return
		end
		local resting = TopLine.Resting
		local rest = if resting then resting() else nil
		if not rest then
			if frame.Visible then
				frame.Visible = false
				shownText = ""
				fit("", false)
			end
			return
		end
		frame.Visible = true
		local scale = pulse :: UIScale
		scale.Scale = if rest.Pulse then 1.06 + 0.06 * math.abs(math.sin(os.clock() * math.pi)) else 1
		local wantsPill = rest.Pill == true and pill ~= nil
		if rest.Text ~= shownText or wantsPill ~= shownPill then
			shownText, shownPill = rest.Text, wantsPill
			text.Text = rest.Text
			fit(rest.Text, wantsPill)
		end
	end)
	local function refit()
		if band and band.Visible then
			fit(shownText, shownPill)
		end
	end
	Ui.Layout.Changed:Connect(refit)
	Ui.gui:GetAttributeChangedSignal("TutorialBar"):Connect(refit)
	Ui.gui:GetAttributeChangedSignal("TutorialBarHeight"):Connect(refit)
end

return TopLine
