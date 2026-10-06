--!strict
-- Client entry point. The client is display + requests only; the server owns every number.
-- Works with mouse, touch and gamepad.

local clientStart = os.clock() -- requires included: some wait on replicated modules
local Lod = require(script.Parent.Lod)
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
local Transitions = require(script.Parent.Transitions)
local Overheads = require(script.Parent.Overheads)
local Footsteps = require(script.Parent.Footsteps)
local RoundIntro = require(script.Parent.RoundIntro)
local Tumble = require(script.Parent.Tumble)
local WorldLabels = require(script.Parent.WorldLabels)
local KnifeOutlines = require(script.Parent.KnifeOutlines)
local GambleUi = require(script.Parent.GambleUi)
local QuickBar = require(script.Parent.QuickBar)
local TopLine = require(script.Parent.TopLine)
local TreadmillLock = require(script.Parent.TreadmillLock)
local ShiftLock = require(script.Parent.ShiftLock)
local Spectate = require(script.Parent.Spectate)
local Tips = require(script.Parent.Tips)
local BiomeShells = require(script.Parent.BiomeShells)
local PhoneHud = require(script.Parent.PhoneHud)
local HudSkin = require(script.Parent.HudSkin)
local Telemetry = require(script.Parent.Telemetry)
local ZoneLighting = require(script.Parent.ZoneLighting)

-- Timed, so slow starts show up in the output (the summary prints once everything is up)
local clientTimings: { string } = {}
local function timed(name: string, fn: () -> ())
	local t = os.clock()
	fn()
	table.insert(clientTimings, string.format("%s %.0fms", name, (os.clock() - t) * 1000))
end
timed("Telemetry", Telemetry.Init) -- first: the device and every button from the start
timed("Lod", Lod.Init)
timed("Moves", Moves.Init)
timed("Effects", Effects.Init)
timed("TopLine", TopLine.Init)
timed("Hud", Hud.Init)
timed("Menus", Menus.Init)
timed("Abilities", Abilities.Init)
timed("PowerBar", PowerBar.Init)
timed("Unbox", Unbox.Init)
timed("Raid", Raid.Init)
timed("Atmosphere", Atmosphere.Init)
timed("Welcome", Welcome.Init)
timed("Store", Store.Init)
timed("KnifeTrails", KnifeTrails.Init)
timed("Transitions", Transitions.Init)
timed("Overheads", Overheads.Init)
timed("Footsteps", Footsteps.Init)
timed("RoundIntro", RoundIntro.Init)
timed("Tumble", Tumble.Init)
timed("WorldLabels", WorldLabels.Init)
timed("KnifeOutlines", KnifeOutlines.Init)
timed("GambleUi", GambleUi.Init)
timed("QuickBar", QuickBar.Init)
timed("TreadmillLock", TreadmillLock.Init)
timed("ShiftLock", ShiftLock.Init)
timed("Spectate", Spectate.Init)
timed("Tips", Tips.Init)
timed("BiomeShells", BiomeShells.Init)
timed("ZoneLighting", ZoneLighting.Init)
timed("HudSkin", HudSkin.Init)
timed("PhoneHud", PhoneHud.Init) -- last: lays out what the others built
task.spawn(Tutorial.Init)
print(
	string.format(
		"[Steal and Murder] client ready in %.2fs (%s)",
		os.clock() - clientStart,
		table.concat(clientTimings, ", ")
	)
)

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
