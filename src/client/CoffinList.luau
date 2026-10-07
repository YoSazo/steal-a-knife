--!strict
-- Steal an Egg's "Growing Eggs" panel, for coffins: a Coffins button on the right (with a red count
-- badge) opens a list of your waiting coffins - each one's rarity, a progress bar and what's left
-- ("1 murder round left", "12s"), and an "Open" button (Robux product CoffinOpen for that coffin).
-- Reads the player attribute CoffinList (BaseService: "plate,rarity,roundsLeft,opensAt;...").
-- Only shown while you have coffins waiting (and in the hub, no menu open).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local Format = require(ReplicatedStorage.Shared.Format)
local VoxelUi = require(ReplicatedStorage.Shared.Config.VoxelUi)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.MenuTheme)
local SimpleUi = require(script.Parent.SimpleUi)

local player = Players.LocalPlayer
local CoffinList = {}

local PURPLE = Color3.fromRGB(150, 90, 230)
local CONFIG = GameConfig.Coffins

type Entry = { Plate: number, Rarity: string, Rounds: number, OpensAt: number }

local function parse(): { Entry }
	local out: { Entry } = {}
	local raw = player:GetAttribute("CoffinList")
	for plate, rarity, rounds, opensAt in
		(if type(raw) == "string" then raw else ""):gmatch("(%d+),(%a+),(%-?%d+),(%d+)")
	do
		table.insert(out, {
			Plate = tonumber(plate) :: number,
			Rarity = rarity :: string,
			Rounds = tonumber(rounds) :: number,
			OpensAt = tonumber(opensAt) :: number,
		})
	end
	-- soonest first
	table.sort(out, function(a, b)
		if a.Rounds ~= b.Rounds then
			return a.Rounds < b.Rounds
		end
		return a.OpensAt < b.OpensAt
	end)
	return out
end

function CoffinList.Init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local phone = Ui.Phone
	local frame, body = SimpleUi.window(
		"Coffins",
		"Coffins",
		VoxelUi.Hud.Knives,
		PURPLE,
		if phone then Vector2.new(560, 420) else Vector2.new(640, 560)
	)
	Ui.Panels.Coffins = frame
	local rowH = if phone then 70 else 84
	local list: ScrollingFrame = Ui.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 6,
	}, body)
	Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	Ui.new("UIPadding", { PaddingRight = UDim.new(0, 10) }, list)

	type Row = { Frame: Frame, Bar: Frame, Left: TextLabel, Name: TextLabel }
	local rows: { Row } = {}
	local entries: { Entry } = {}
	local function row(i: number): Row
		local existing = rows[i]
		if existing then
			return existing
		end
		local f: Frame = Ui.new("Frame", {
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, rowH),
			BackgroundColor3 = Color3.fromRGB(40, 42, 58),
			ZIndex = 6,
		}, list)
		Ui.corner(f, 10)
		local name = SimpleUi.text(f, "", {
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(0.3, -12, 1, -12),
			TextXAlignment = Enum.TextXAlignment.Left,
			Max = 26,
		})
		local track: Frame = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.3, 0.5),
			Size = UDim2.new(0.45, 0, 0, rowH * 0.42),
			BackgroundColor3 = Color3.fromRGB(18, 18, 26),
			ZIndex = 7,
		}, f)
		Ui.corner(track, 6)
		local bar: Frame = Ui.new("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = Color3.fromRGB(70, 220, 90),
			ZIndex = 8,
		}, track)
		Ui.corner(bar, 6)
		local left = SimpleUi.text(track, "", {
			Size = UDim2.fromScale(1, 1),
			ZIndex = 9,
			Max = 22,
		})
		SimpleUi.button(f, "Open R$19", Color3.fromRGB(0, 176, 111), {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0.22, -10, 0, rowH * 0.62),
			ZIndex = 8,
			Max = 22,
		}, function()
			local entry = entries[i]
			if entry and Ui.Buy then
				Remotes:WaitForChild("CoffinTarget"):FireServer(entry.Plate)
				Ui.Buy("Product", "CoffinOpen")
			end
		end)
		local made = { Frame = f, Bar = bar, Left = left, Name = name }
		rows[i] = made
		return made
	end

	-- the button on the right, under Powers, with a count badge
	local button = Theme.button(Ui.gui, "⚰️ Coffins", PURPLE, {
		AnchorPoint = Vector2.new(1, 0),
		Name = "CoffinsButton",
		Position = UDim2.new(1, -12, 0, 160),
		Size = UDim2.fromOffset(120, 44),
		MaximumTextSize = 20,
		Visible = false,
	}, function()
		Ui.Menu.Toggle(frame)
	end)
	local badge = Theme.badge(button)
	-- (phones turn it into a small square: PhoneHud hides the words, so a coffin fills it)
	if Ui.Phone then
		local glyph = SimpleUi.text(button, "⚰️", {
			Name = "Glyph",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.8, 0.8),
			ZIndex = button.ZIndex + 2,
			Max = 40,
		})
		glyph.Name = "Glyph"
	end

	local last = 0
	RunService.Heartbeat:Connect(function()
		if os.clock() - last < 0.25 then
			return
		end
		last = os.clock()
		entries = parse()
		button.Visible = #entries > 0 and Ui.inHub() and not Ui.menuOpen()
		badge.Visible = #entries > 0
		badge.Text = tostring(#entries)
		if not frame.Visible then
			return
		end
		local now = workspace:GetServerTimeNow()
		for i, entry in entries do
			local r = row(i)
			r.Frame.Visible = true
			r.Name.Text = `{entry.Rarity} Coffin`
			r.Name.TextColor3 = Knives.RarityColors[entry.Rarity] or Color3.new(1, 1, 1)
			local done: number
			if entry.Rounds >= 0 then
				-- the murder rounds are its clock
				local total = math.max(1, CONFIG.Rounds[entry.Rarity] or 1)
				done = 1 - entry.Rounds / total
				r.Left.Text = if entry.Rounds <= 0
					then "Opening!"
					elseif entry.Rounds == 1 then "1 murder round left"
					else `{entry.Rounds} murder rounds left`
			else
				local left = math.max(0, entry.OpensAt - now)
				done = 1 - left / math.max(1, CONFIG.CommonSeconds)
				r.Left.Text = if left > 0.5 then Format.Duration(left) else "Opening!"
			end
			r.Bar.Size = UDim2.fromScale(math.clamp(done, 0.04, 1), 1)
		end
		for i = #entries + 1, #rows do
			rows[i].Frame.Visible = false
		end
		if #entries == 0 then
			frame.Visible = false
		end
	end)
end

return CoffinList
