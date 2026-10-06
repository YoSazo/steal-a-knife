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
	-- One slim row centred just under the timer lines, on every screen: [Office · 2] [Mansion · 3] [X]
	-- (desktop had a card on the right that sat on the Knives / Powers buttons; on phones a card ran
	-- into the knife stick). It takes the Murderer chance line's place while it's up (Hud VoteRow).
	local phone = Ui.Phone
	local count = #RoundMapInfo.List
	local closeSize = if phone then 30 else 38
	local buttonW = if phone then 110 else 170
	local gap = 8
	local card: Frame = Ui.new("Frame", {
		Name = "MapVoteCard",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset((buttonW + gap) * count + closeSize + gap * 2, closeSize + 10),
		BackgroundColor3 = Color3.fromRGB(34, 38, 56),
		BackgroundTransparency = 0.15,
		Visible = false,
		ZIndex = 20,
	}, Ui.gui)
	local function place()
		card.Position = UDim2.new(0.5, 0, 0, ((Ui.gui:GetAttribute("HudTop") or 60) :: number) + 2)
	end
	Ui.gui:GetAttributeChangedSignal("HudTop"):Connect(place)
	place()
	Ui.corner(card, 10)
	Ui.new("UIStroke", { Color = Color3.fromRGB(255, 225, 90), Thickness = 2 }, card)
	local dismissed = false
	SimpleUi.button(card, "X", Color3.fromRGB(230, 40, 50), {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -5, 0.5, 0),
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
			Position = UDim2.fromOffset(gap + (i - 1) * (buttonW + gap), 5),
			Size = UDim2.fromOffset(buttonW, closeSize),
			ZIndex = 21,
			Max = if phone then 17 else 22,
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
		if Ui.gui:GetAttribute("VoteRow") ~= card.Visible then
			Ui.gui:SetAttribute("VoteRow", card.Visible)
		end
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
