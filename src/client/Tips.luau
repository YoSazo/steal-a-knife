--!strict
-- One-time tips, at the moment they matter (after the first-minutes guide in client/Tutorial). Each
-- shows once ever (saved: player TipsSeen, Remotes.Tutorial "Tip") in a slim bar under the timer,
-- in the words for this device. Triggers:
--   * server Effect "Tip": Caught (a boss took your knife back), Knocked (someone hit it loose)
--   * dying in a round: stealing stays available while the round continues
-- Controls and next steps belong to Guide, so these notices never give a competing instruction.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PenMode = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PenMode"))

local Ui = require(script.Parent.Ui)
local TopLine = require(script.Parent.TopLine)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer
local Tips = {}
Tips.Show = nil :: ((id: string) -> ())? -- set by Init

local function touch(): boolean
	return Ui.Phone
end

-- id -> text (phone, desktop)
local TEXT: { [string]: { string } } = {
	Caught = {
		if PenMode.Coffins() then "Caught! The coffin went back." else "Caught! Your knife went back.",
		if PenMode.Coffins() then "Caught! The coffin went back." else "Caught! Your knife went back.",
	},
	Knocked = {
		"You dropped your knife!",
		"You dropped your knife!",
	},
	Spectate = {
		"You're out - steal while they play!",
		"You're out - steal while they play!",
	},
}

function Tips.Init()
	-- (tips go on the top line - client/TopLine - like the tutorial; they had their own bar under
	-- the timer, on top of whatever else was there)
	local shown: { [string]: boolean } = {}
	local function show(id: string)
		local text = TEXT[id]
		if not text or shown[id] or table.find(Ui.list(player:GetAttribute("TipsSeen")), id) then
			return
		end
		shown[id] = true
		Remotes.Tutorial:FireServer("Tip", id)
		TopLine.Show("💡 " .. (if touch() then text[1] else text[2]), 7, "Tip")
	end
	Tips.Show = show

	-- From the server
	Remotes:WaitForChild("Effect").OnClientEvent:Connect(function(kind: string, id: unknown)
		if kind == "Tip" and type(id) == "string" then
			show(id)
		end
	end)
	-- Leaving a still-running round: the hub guide resumes after respawning.
	local wasInRound = false
	local function roundChanged()
		local inRound = player:GetAttribute("InRound") == true
		if not inRound and wasInRound and ReplicatedStorage:GetAttribute("Phase") == "Round" then
			task.delay(3, function()
				show("Spectate")
			end)
		end
		wasInRound = inRound
	end
	player:GetAttributeChangedSignal("InRound"):Connect(roundChanged)
end

return Tips
