--!strict
-- A big pink "Drop" button at the bottom centre while you're carrying something in the hub
-- (Tsunami style): don't want that knife after all? Tap it. A boss's knife goes back on its wall
-- and the chase ends; anything else lands at your feet (server: StealService.Drop).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ui = require(script.Parent.Ui)
local SimpleUi = require(script.Parent.SimpleUi)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local DropButton = {}

function DropButton.Init()
	-- Tsunami's size: a slim pill low in the middle, under your character, not over it
	local button = SimpleUi.button(Ui.gui, "🗑️ Drop", Color3.fromRGB(240, 60, 120), {
		Name = "DropButton",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = if Ui.Phone then UDim2.new(0.5, 0, 1, -14) else UDim2.new(0.5, 0, 1, -80),
		Size = if Ui.Phone then UDim2.fromOffset(132, 40) else UDim2.fromOffset(190, 52),
		Visible = false,
		ZIndex = 20,
		Max = if Ui.Phone then 24 else 30,
	}, function()
		Remotes:WaitForChild("Drop"):FireServer()
	end)
	local function refresh()
		local carrying = player:GetAttribute("Carrying")
		button.Visible = type(carrying) == "string"
			and carrying ~= ""
			and not player:GetAttribute("InRound")
			and not Ui.menuOpen()
	end
	player:GetAttributeChangedSignal("Carrying"):Connect(refresh)
	player:GetAttributeChangedSignal("InRound"):Connect(refresh)
	Ui.gui:GetAttributeChangedSignal("ActiveMenu"):Connect(refresh)
	refresh()
end

return DropButton
