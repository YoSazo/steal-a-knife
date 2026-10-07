--!strict
-- Roblox's own "Favorite this experience?" prompt, once ever (saved like a tip: TipsSeen "Favorite").
-- Asked at the high point of the first visit: right after the first round you WON (the VS card).
-- Asked when the first knife landed, only 19% said yes; winning a round is the moment that best
-- predicts coming back (Murderer win / Sheriff: 27-33% returned vs 11%). Favourites are how players
-- find the game again.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ui = require(script.Parent.Ui)
local Telemetry = require(script.Parent.Telemetry)

local player = Players.LocalPlayer
local Favorite = {}

local asked = false

function Favorite.Ask(moment: string)
	if asked or table.find(Ui.list(player:GetAttribute("TipsSeen")), "Favorite") then
		return
	end
	asked = true
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Tutorial"):FireServer("Tip", "Favorite")
	local AvatarEditorService = game:GetService("AvatarEditorService")
	local done: RBXScriptConnection? = nil
	done = AvatarEditorService.PromptSetFavoriteCompleted:Connect(function(result)
		Telemetry.Track("favorite.prompt", { result = result.Name, moment = moment })
		if done then
			done:Disconnect()
		end
	end)
	local ok =
		pcall(AvatarEditorService.PromptSetFavorite, AvatarEditorService, game.PlaceId, Enum.AvatarItemType.Asset, true)
	if not ok and done then
		done:Disconnect()
	end
end

return Favorite
