--!strict
-- One-time tips, at the moment they matter (after the first-minutes guide in client/Tutorial). Each
-- shows once ever (saved: player TipsSeen, Remotes.Tutorial "Tip") in a slim bar under the timer,
-- in the words for this device. Triggers:
--   * server Effect "Tip": Caught (a boss took your knife back), Knocked (someone hit it loose)
--   * your first round as the Murderer / an Innocent / the Sheriff: how to fight on this device
--   * dying in a round: the spectate eye
--   * the first Blood Moon: what to do
--   * the first time you can afford a rebirth: what it needs

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Ui = require(script.Parent.Ui)
local TopLine = require(script.Parent.TopLine)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
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
		"Caught! Bosses take the knife back. Train Speed on your wheel to outrun them.",
		"Caught! Bosses take the knife back. Train Speed on your wheel to outrun them.",
	},
	Knocked = {
		"Someone hit your knife loose! You can do it too: hit anyone carrying a knife.",
		"Someone hit your knife loose! You can do it too: click anyone carrying a knife.",
	},
	Murderer = {
		"You're the MURDERER! Tap to stab, THROW to throw. Don't get shot!",
		"You're the MURDERER! Click to stab, hold click to throw. Don't get shot!",
	},
	Innocent = {
		"Survive! Grab coins, hide, and use your power (the button at the bottom).",
		"Survive! Grab coins, hide, and use your power (keys 1-3).",
	},
	Sheriff = {
		"You have the Revolver! Pull it out and TAP the Murderer to shoot.",
		"You have the Revolver! Pull it out and CLICK the Murderer to shoot.",
	},
	Spectate = {
		"You're out! Tap the 👁 on the left to watch the rest of the round.",
		"You're out! Click the 👁 on the left to watch the rest of the round.",
	},
	BloodMoon = {
		"BLOOD MOON! Hold Steal on a knife in someone else's vault and run it home!",
		"BLOOD MOON! Hold F on a knife in someone else's vault and run it home!",
	},
	Rebirth = {
		"You can afford a Rebirth! More ▸ Rebirth: a permanent money boost.",
		"You can afford a Rebirth! More ▸ Rebirth: a permanent money boost.",
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
	-- Rounds: your role, the Revolver, dying
	local wasInRound = false
	local function roundChanged()
		local inRound = player:GetAttribute("InRound") == true
		if inRound then
			task.delay(4, function() -- after the role card
				local role = player:GetAttribute("Role")
				if role == "Murderer" or role == "Innocent" then
					show(role :: string)
				end
			end)
		elseif wasInRound and ReplicatedStorage:GetAttribute("Phase") == "Round" then
			task.delay(3, function()
				show("Spectate")
			end)
		end
		wasInRound = inRound
	end
	player:GetAttributeChangedSignal("InRound"):Connect(roundChanged)
	local function watchBackpack(backpack: Instance)
		backpack.ChildAdded:Connect(function(tool)
			if tool:IsA("Tool") and tool:GetAttribute("Revolver") and player:GetAttribute("InRound") then
				task.delay(4.5, function()
					show("Sheriff")
				end)
			end
		end)
	end
	watchBackpack(player:WaitForChild("Backpack"))
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			watchBackpack(child)
		end
	end)
	-- The Blood Moon
	ReplicatedStorage:GetAttributeChangedSignal("Raid"):Connect(function()
		if ReplicatedStorage:GetAttribute("Raid") == true and not player:GetAttribute("InRound") then
			show("BloodMoon")
		end
	end)
	-- First affordable rebirth
	local lastCheck = 0
	RunService.Heartbeat:Connect(function()
		if os.clock() - lastCheck < 2 or shown.Rebirth then
			return
		end
		lastCheck = os.clock()
		local rebirths = (player:GetAttribute("Rebirths") or 0) :: number
		local cash = (player:GetAttribute("Cash") or 0) :: number
		if rebirths < GameConfig.Rebirth.Max and cash >= GameConfig.RebirthCost(rebirths) and Ui.inHub() then
			show("Rebirth")
		end
	end)
end

return Tips
