--!strict
-- Client entry point. The client is display + requests only; the server owns every number.
-- Works with mouse, touch and gamepad.

local Effects = require(script.Parent.Effects)
local Hud = require(script.Parent.Hud)
local Menus = require(script.Parent.Menus)
local Abilities = require(script.Parent.Abilities)
local Moves = require(script.Parent.Moves)
local PowerBar = require(script.Parent.PowerBar)
local Unbox = require(script.Parent.Unbox)
local Raid = require(script.Parent.Raid)
local Atmosphere = require(script.Parent.Atmosphere)
local Tutorial = require(script.Parent.Tutorial)
local Welcome = require(script.Parent.Welcome)
local Store = require(script.Parent.Store)
local KnifeTrails = require(script.Parent.KnifeTrails)

Moves.Init()
Effects.Init()
Hud.Init()
Menus.Init()
Abilities.Init()
PowerBar.Init()
Unbox.Init()
Raid.Init()
Atmosphere.Init()
Welcome.Init()
Store.Init()
KnifeTrails.Init()
task.spawn(Tutorial.Init)

-- No tumbling: Roblox's FallingDown / Ragdoll states knock you over after hard landings, bumps and
-- dashes into walls. The client owns its character's state machine, so they're turned off here.
-- (Dying still ragdolls - that's the Dead state, handled by the server.)
local player = game:GetService("Players").LocalPlayer
local function steady(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	end
end
if player.Character then
	task.spawn(steady, player.Character)
end
player.CharacterAdded:Connect(steady)
