--!strict
-- Sequential presentation of rewards already granted by StealService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Ui = require(script.Parent.Ui)
local Items = require(ReplicatedStorage.Shared.Items)
local View = require(script.Parent.UnboxView)
local Unbox = {}
local queue: { { Rarity: string, Item: string, Upgraded: boolean, IsNew: boolean } } = {}
local playing = false
local function drain()
	if playing then
		return
	end
	playing = true
	local returnTo = Ui.Menu.Current()
	local character = Players.LocalPlayer.Character
	local phase = ReplicatedStorage:GetAttribute("Phase")
	while #queue > 0 do
		local reward = table.remove(queue, 1)
		if reward then
			View.Play(reward.Rarity, reward.Item, reward.Upgraded, reward.IsNew)
		end
	end
	playing = false
	-- Return to the cash/Robux case menu after all queued reveals finish.
	if
		returnTo
		and returnTo.Parent
		and (returnTo.Name == "Mortimer's Knife Cases" or returnTo.Name == "Store")
		and not Ui.menuOpen()
		and not Players.LocalPlayer:GetAttribute("InRound")
		and Players.LocalPlayer.Character == character
		and ReplicatedStorage:GetAttribute("Phase") == phase
	then
		returnTo.Visible = true
	end
end
function Unbox.Init()
	ReplicatedStorage.Remotes.Effect.OnClientEvent:Connect(function(kind: string, ...)
		if kind ~= "Unbox" then
			return
		end
		local rarity, item, upgraded, isNew = ...
		if type(rarity) ~= "string" or type(item) ~= "string" or not Items.Parse(item) then
			return
		end
		table.insert(queue, { Rarity = rarity, Item = item, Upgraded = upgraded == true, IsNew = isNew == true })
		task.spawn(drain)
	end)
end
return Unbox
