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
	-- Phones (iPhone 13 landscape is ~750 x 340 points): small, up on the right under the top line,
	-- clear of the knife stick, the jump button and the Knives / Powers buttons
	local phone = Ui.Phone
	local width = if phone then 190 else 280
	local rowH = if phone then 36 else 60
	local titleH = if phone then 26 else 40
	local closeSize = if phone then 26 else 38
	local footerH = if phone then 0 else 34
	local top = titleH + 14
	local card: Frame = Ui.new("Frame", {
		Name = "MapVoteCard",
		AnchorPoint = if phone then Vector2.new(1, 0) else Vector2.new(1, 0.5),
		Position = if phone then UDim2.new(1, -70, 0, 92) else UDim2.new(1, -84, 0.46, 0),
		Size = UDim2.fromOffset(width, top + #RoundMapInfo.List * (rowH + 6) + 4 + footerH),
		BackgroundColor3 = Color3.fromRGB(34, 38, 56),
		BackgroundTransparency = 0.15,
		Visible = false,
		ZIndex = 20,
	}, Ui.gui)
	Ui.corner(card, 14)
	Ui.new("UIStroke", { Color = Color3.fromRGB(255, 225, 90), Thickness = 3 }, card)
	SimpleUi.text(card, if phone then "🗳️ Vote the map!" else "🗳️ Vote the murder map!", {
		Position = UDim2.fromOffset(10, 7),
		Size = UDim2.new(1, -(closeSize + 22), 0, titleH),
		TextXAlignment = Enum.TextXAlignment.Left,
		Max = if phone then 18 else 26,
		ZIndex = 21,
	})
	local dismissed = false
	SimpleUi.button(card, "X", Color3.fromRGB(230, 40, 50), {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -7, 0, 7),
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
			Position = UDim2.fromOffset(8, top + (i - 1) * (rowH + 6)),
			Size = UDim2.new(1, -16, 0, rowH),
			ZIndex = 21,
			Max = if phone then 18 else 28,
		}, function()
			Remotes.MapVote:FireServer(info.Name)
		end)
		table.insert(rows, { Button = button, Name = info.Name })
	end
	local footer = SimpleUi.text(card, "or stand on a pad at the back of the plaza", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -6),
		Size = UDim2.new(1, -20, 0, 22),
		TextColor3 = Color3.fromRGB(205, 215, 240),
		Max = 15,
		ZIndex = 21,
	})
	footer.Visible = not phone -- (no room on a phone; the top line says it too)

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
				`{if mine == row.Name then "✓ " else ""}{info.Emoji} {row.Name}  ·  {n}`,
				info.Color,
				true
			)
		end
	end)
end

return MapVoteCard
