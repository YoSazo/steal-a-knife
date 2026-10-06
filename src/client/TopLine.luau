--!strict
-- One line across the top of the screen for short notices, in the tutorial's style (Steal An Egg's
-- top line): a thin dark band that fades out at both ends, only as wide as its words, plain white
-- (or coloured) text. Zone titles, server announcements and "Round over!" go here one at a time,
-- instead of each having its own big box in the middle of the screen.
--
-- While a notice is up: Ui.gui attribute TopLine = true (client/Hud moves the timer lines down under
-- it) and ZoneTitle = true (the tutorial's own line steps aside, it's in the same spot).
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)

local TopLine = {}

local FADE = 60
type Entry = { Text: string, Seconds: number, Key: string? }
local queue: { Entry } = {}
local showing: Entry? = nil
local token = 0
local band: Frame? = nil
local label: TextLabel? = nil

local function height(): number
	return if Ui.Phone then 36 else 34
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
			NumberSequenceKeypoint.new(0.18, 0.45),
			NumberSequenceKeypoint.new(0.82, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, frame)
	local text = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, 1),
		TextScaled = false,
		TextColor3 = Color3.new(1, 1, 1),
		RichText = true,
		Text = "",
		ZIndex = 41,
	}, frame)
	Ui.textStroke(text, 1.5)
	band, label = frame, text
end

local function layout()
	local frame, text = band, label
	if not frame or not text then
		return
	end
	local _, bounds = Ui.bounds()
	text.TextSize = if Ui.Phone then 19 else 20
	local maxLane = math.max(120, math.min(900, bounds.X - 24 - 2 * FADE))
	-- (RichText tags don't take space: measure the words only)
	local plain = text.Text:gsub("<[^>]->", "")
	local words = TextService:GetTextSize(plain, text.TextSize, text.Font, Vector2.new(maxLane, 1000))
	local lane = math.min(maxLane, words.X + 8)
	-- (a long tip wraps onto a second line: the band grows to fit it)
	local tall = math.max(height(), words.Y + 10)
	text.TextWrapped = true
	frame.Size = UDim2.fromOffset(math.min(bounds.X, lane + 2 * FADE), tall)
	text.Size = UDim2.new(0, lane, 1, 0)
	Ui.gui:SetAttribute("TopLineHeight", tall)
end

local function nextOne()
	local entry = table.remove(queue, 1)
	showing = entry
	local frame, text = band, label
	if not entry or not frame or not text then
		if frame then
			frame.Visible = false
		end
		Ui.gui:SetAttribute("TopLine", false)
		Ui.gui:SetAttribute("ZoneTitle", false)
		return
	end
	token += 1
	local mine = token
	text.Text = entry.Text
	text.TextTransparency = 0
	local stroke = text:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	layout()
	frame.Visible = true
	frame.Position = UDim2.new(0.5, 0, 0, -8)
	TweenService:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(0.5, 0) }):Play()
	Ui.gui:SetAttribute("TopLine", true)
	Ui.gui:SetAttribute("ZoneTitle", true)
	task.delay(entry.Seconds, function()
		if mine ~= token then
			return
		end
		TweenService:Create(text, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		end
		task.wait(0.3)
		if mine == token then
			nextOne()
		end
	end)
end

-- Shows `text` (RichText allowed) for `seconds`. A `key` replaces a queued or showing notice with the
-- same key (walking through three zones fast shows the last one, not all three in turn).
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
	-- (never a long wait behind old news)
	while #queue > 3 do
		table.remove(queue, 1)
	end
	if not showing then
		nextOne()
	end
end

-- Takes it down now (a menu opened, a round started)
function TopLine.Clear()
	table.clear(queue)
	token += 1
	nextOne()
end

function TopLine.Init()
	if not band then
		build()
	end
	Ui.Layout.Changed:Connect(layout)
end

return TopLine
