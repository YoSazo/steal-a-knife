--!strict
-- Reference-led sparse lawn. Existing Build/LOD hooks are preserved.
local Builder = require(script.Parent.SimpleBiomeShell)
local Geometry = require(script.Parent.Parent.Config.ToyGeometry.ProgressiveBiomes.GardensShellData)
local Shell = { Geometry = Geometry }
function Shell.Build(parent: Instance?, origin: CFrame?, options: Builder.Options?): Model
	return Builder.Build(Geometry, parent, origin, options)
end
Shell.StepWater = Builder.StepWater
Shell.SetDetailVisible = Builder.SetDetailVisible
return Shell
