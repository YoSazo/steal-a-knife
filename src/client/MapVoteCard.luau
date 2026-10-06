--!strict
-- The vote card: in the last GameConfig.MapVoteWindow seconds before a murder round, a small card
-- on the right with one big button per map (its emoji, name and votes; a tick on yours). Tapping
-- votes (Remotes.MapVote), the same as standing on that map's pad at the back of the plaza (server
-- MapVote). The X hides it until the next break. Hidden in rounds, menus and the tutorial.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Ui = require(script.Parent.Ui)
local SimpleUi = require(script.Parent.SimpleUi)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RoundMapInfo = require(ReplicatedStorage.Shared.Config.RoundMapInfo)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local MapVoteCard = {}

-- "Office=2;Mansion=1" -> { Office = 2, Mansion = 1 }
function MapVoteCard.Counts(): { [string]: number }
	local out = {}
	local raw = ReplicatedStorage:GetAttribute("MapVotes")
	for name, n in (if type(raw) == "string" then raw else ""):gmatch("(%w+)=(%d+)") do
		out[name] = tonumber(n) :: number
	end
	return out
end

-- Seconds until the round while the vote is open, else nil
function MapVoteCard.Open(): number?
	if
		ReplicatedStorage:GetAttribute("Phase") ~= "Intermission"
		or ReplicatedStorage:GetAttribute("Status") ~= "🔪 MURDER ROUND in"
		or player:GetAttribute("InRound")
	then
		return nil
	end
	local left = ((ReplicatedStorage:GetAttribute("PhaseEndsAt") or 0) :: number) - workspace:GetServerTimeNow()
	return if left > 0 and left <= GameConfig.MapVoteWindow then left else nil
end

function MapVoteCard.Init()
	-- Desktop: a card on the right. Phones: one slim row centred just under the timer lines
	-- ([Office · 2] [Mansion · 3] [X]) - stress-tested at 600 x 300, smaller than any iPhone: a card
	-- on the right ran into the knife stick
	local phone = Ui.Phone
	local count = #RoundMapInfo.List
	local card: Frame
	local closeSize = if phone then 30 else 38
	if phone then
		local rowW = 110 * count + closeSize + 8 * (count + 2)
		card = Ui.new("Frame", {
			Name = "MapVoteCard",
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(rowW, closeSize + 10),
			BackgroundColor3 = Color3.fromRGB(34, 38, 56),
			BackgroundTransparency = 0.15,
			Visible = false,
			ZIndex = 20,
		}, Ui.gui)
		local function place()
			card.Position = UDim2.new(0.5, 0, 0, ((Ui.gui:GetAttribute("HudTop") or 60) :: number) + 24)
		end
		Ui.gui:GetAttributeChangedSignal("HudTop"):Connect(place)
		place()
	else
		card = Ui.new("Frame", {
			Name = "MapVoteCard",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -84, 0.46, 0),
			Size = UDim2.fromOffset(280, 54 + count * 66 + 4 + 34),
			BackgroundColor3 = Color3.fromRGB(34, 38, 56),
			BackgroundTransparency = 0.15,
			Visible = false,
			ZIndex = 20,
		}, Ui.gui)
		SimpleUi.text(card, "🗳️ Vote the murder map!", {
			Position = UDim2.fromOffset(10, 7),
			Size = UDim2.new(1, -(closeSize + 22), 0, 40),
			TextXAlignment = Enum.TextXAlignment.Left,
			Max = 26,
			ZIndex = 21,
		})
		SimpleUi.text(card, "or stand on a pad at the back of the plaza", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 10, 1, -6),
			Size = UDim2.new(1, -20, 0, 22),
			TextColor3 = Color3.fromRGB(205, 215, 240),
			Max = 15,
			ZIndex = 21,
		})
	end
	Ui.corner(card, if phone then 10 else 14)
	Ui.new("UIStroke", { Color = Color3.fromRGB(255, 225, 90), Thickness = if phone then 2 else 3 }, card)
	local dismissed = false
	SimpleUi.button(card, "X", Color3.fromRGB(230, 40, 50), {
		Name = "Close",
		AnchorPoint = if phone then Vector2.new(1, 0.5) else Vector2.new(1, 0),
		Position = if phone then UDim2.new(1, -5, 0.5, 0) else UDim2.new(1, -7, 0, 7),
		Size = UDim2.fromOffset(closeSize, closeSize),
		ZIndex = 22,
		Max = 24,
	}, function()
		dismissed = true
	end)
	type Row = { Button: TextButton, Name: string }
	local rows: { Row } = {}
	for i, info in RoundMapInfo.List do
		local button = SimpleUi.button(card, "", info.Color, {
			Name = `Vote{info.Name}`,
			Position = if phone then UDim2.fromOffset(8 + (i - 1) * 118, 5) else UDim2.fromOffset(8, 54 + (i - 1) * 66),
			Size = if phone then UDim2.fromOffset(110, closeSize) else UDim2.new(1, -16, 0, 60),
			ZIndex = 21,
			Max = if phone then 17 else 28,
		}, function()
			Remotes.MapVote:FireServer(info.Name)
		end)
		table.insert(rows, { Button = button, Name = info.Name })
	end

	local lastRefresh = 0
	local wasOpen = false
	RunService.Heartbeat:Connect(function()
		if os.clock() - lastRefresh < 0.25 then
			return
		end
		lastRefresh = os.clock()
		local open = MapVoteCard.Open() ~= nil
		if open and not wasOpen then
			dismissed = false -- a new break: show it again
		end
		wasOpen = open
		card.Visible = open and not dismissed and not Ui.menuOpen() and Ui.gui:GetAttribute("TutorialBar") ~= true
		if not card.Visible then
			return
		end
		local tally = MapVoteCard.Counts()
		local mine = player:GetAttribute("MapVote")
		for _, row in rows do
			local info = RoundMapInfo.ByName[row.Name]
			local n = tally[row.Name] or 0
			SimpleUi.set(
				row.Button,
				if phone
					then `{if mine == row.Name then "✓ " else ""}{row.Name} · {n}`
					else `{if mine == row.Name then "✓ " else ""}{info.Emoji} {row.Name}  ·  {n}`,
				info.Color,
				true
			)
		end
	end)
end

return MapVoteCard
