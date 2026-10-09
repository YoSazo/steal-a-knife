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
local pending = false
local waiting: { () -> () } = {}
local function finish()
	pending = false
	local callbacks = table.clone(waiting)
	table.clear(waiting)
	for _, callback in callbacks do
		task.defer(callback)
	end
end
function Favorite.Ask(moment: string, completed: (() -> ())?, force: boolean?)
	if pending or (not force and (asked or table.find(Ui.list(player:GetAttribute("TipsSeen")), "Favorite"))) then
		if completed then
			if pending then
				table.insert(waiting, completed)
			else
				task.defer(completed)
			end
		end
		return
	end
	asked = true
	pending = true
	if completed then
		table.insert(waiting, completed)
	end
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Tutorial"):FireServer("Tip", "Favorite")
	local service = game:GetService("AvatarEditorService")
	local done: RBXScriptConnection? = nil
	done = service.PromptSetFavoriteCompleted:Connect(function(result: Enum.AvatarPromptResult)
		Telemetry.Track("favorite.prompt", { result = result.Name, moment = moment })
		if result == Enum.AvatarPromptResult.Success then
			player:SetAttribute("FavoriteConfirmed", true)
		end
		if done then
			done:Disconnect()
		end
		finish()
	end)
	local ok = pcall(service.PromptSetFavorite, service, game.PlaceId, Enum.AvatarItemType.Asset, true)
	if not ok then
		if done then
			done:Disconnect()
		end
		finish()
	end
end

return Favorite
