--!strict
-- Temporary Studio server Script; this file is outside the published Rojo tree.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
assert(RunService:IsStudio(), "Map detail audit is Studio-only")
ServerStorage:WaitForChild("Debug", 60)
local Shared = ReplicatedStorage.Shared
local Props = require(Shared.Props)
local Specs = require(Shared.Config.MapDetailMeshes)
local GameConfig = require(Shared.Config.GameConfig)
local Services = game:GetService("ServerScriptService").Server.Services
local VaultWalls = require(Services.VaultWalls)
local ManorDecor = require(Services.ManorDecor)
local result = { Passed = 0, Failed = 0, Errors = {} :: { string } }
local function check(condition: boolean, message: string)
	if condition then
		result.Passed += 1
	else
		result.Failed += 1
		table.insert(result.Errors, message)
	end
end
for name, specs in Specs do
	check(Props.Has(name), name .. ": mesh template missing")
	if not Props.Has(name) then
		continue
	end
	local model = Props.Build(name, true)
	check(model.PrimaryPart ~= nil and model.PrimaryPart.Name == "Root", name .. ": lost placement origin")
	local target = CFrame.new(23, 7, -43) * CFrame.Angles(0, math.rad(73), 0)
	model:ScaleTo(1.7)
	model:PivotTo(target)
	for _, spec in specs do
		local part = model:FindFirstChild(spec.Name)
		check(part ~= nil and part:IsA("MeshPart"), name .. ": missing material batch " .. spec.Name)
		if not part or not part:IsA("MeshPart") then
			continue
		end
		check(part.MeshId == spec.MeshId, name .. ": wrong geometry " .. spec.Name)
		local expected = spec.Size * 1.7
		check((part.Size - expected).Magnitude < 0.01, name .. ": incorrect size " .. spec.Name)
		check(
			(target:PointToObjectSpace(part.Position) - spec.Offset * 1.7).Magnitude < 0.01,
			name .. ": incorrect origin " .. spec.Name
		)
		check(part.Color == spec.Color, name .. ": wrong finish " .. spec.Name)
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			check(part.Anchored and part.Massless, name .. ": unexpected physics " .. part.Name)
			check(
				not part.CanCollide and not part.CanQuery and not part.CanTouch,
				name .. ": scenery obstructs combat " .. part.Name
			)
		end
	end
	model:Destroy()
end

local fixture = Instance.new("Folder")
fixture.Name = "CodexMapDetailTestFixture"
fixture.Parent = ServerStorage
for tierIndex, tier in GameConfig.Walls do
	for _, floors in { 1, 4 } do
		local built =
			VaultWalls.Build(fixture, CFrame.new(6000, 0, 0), Color3.fromRGB(240, 112, 118), tierIndex, floors)
		check(built.Blocker:GetAttribute("MaxHealth") == tier.GateHealth, "Gate health changed")
		check(built.Blocker:GetAttribute("Floors") == floors, "Gate floors changed")
		check(built.Blocker.CanQuery and not built.Blocker.CanTouch, "Gate hit target changed")
		local hardwareCount = 0
		for _, model in built.Gate:GetChildren() do
			if model:IsA("Model") and model.Name == "DetailGateHardware" then
				hardwareCount += 1
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						check(part:GetAttribute("Keep") == true, "Gate hardware disappears on break")
						check(
							not part.CanCollide and not part.CanQuery and not part.CanTouch,
							"Gate hardware intercepts hits"
						)
					end
				end
			end
		end
		check(hardwareCount == 2, "Gate needs two detailed posts")
		VaultWalls.SetOpen(built.Gate, true)
		check(built.Blocker:GetAttribute("Open") == true, "Gate does not break open")
		for _, part in built.Gate:GetDescendants() do
			if part:IsA("BasePart") and part.Name == "Pane" then
				check(part.Transparency == 1, "Broken gate laser remains visible")
			elseif part:IsA("BasePart") and part:GetAttribute("Keep") and part.Name ~= "Root" then
				check(part.Transparency < 1, "Fixed gate hardware hidden")
			end
		end
		VaultWalls.SetOpen(built.Gate, false)
		for _, part in built.Gate:GetDescendants() do
			if part:IsA("BasePart") and part.Name == "Pane" then
				check(math.abs(part.Transparency - 0.15) < 0.001, "Repaired laser not restored")
			end
		end
		check(
			#fixture:GetChildren() > 0 and fixture:FindFirstChild("Gate") == built.Gate,
			"Wall rebuild contract changed"
		)
	end
end
fixture:Destroy()

local decor = workspace.Map.Decor
local counts: { [string]: number } = {}
for _, child in decor:GetChildren() do
	if child:IsA("Model") and child:GetAttribute("MapDetail") then
		counts[child.Name] = (counts[child.Name] or 0) + 1
		for _, part in child:GetDescendants() do
			if part:IsA("BasePart") then
				check(
					not part.CanCollide and not part.CanQuery and not part.CanTouch,
					child.Name .. ": live map obstruction"
				)
			end
		end
		if child.Name == "DetailFountain" then
			check(math.abs(child:GetPivot().Position.X) >= 16, "Fountain obscures central running route")
		elseif child.Name == "DetailAngel" then
			local cf = child:GetPivot()
			check(cf.LookVector.X * cf.Position.X < 0, "Statue faces the outside wall instead of the player route")
		end
	end
end
for _, name in
	{
		"DetailLamp",
		"DetailBench",
		"DetailFountain",
		"DetailGazebo",
		"DetailTopiary",
		"DetailMausoleum",
		"DetailGravestone",
		"DetailColumn",
		"DetailSpire",
		"DetailAngel",
		"DetailOrrery",
		"DetailManorWindow",
		"DetailFlowerBed",
	}
do
	check((counts[name] or 0) > 0, "Scenery missing from live map: " .. name)
end

-- The prop's anchor is outside the clear rectangle, but its actual edge overlaps it.
local marker = Props.Build("DetailBench", true)
marker.Name = "CodexClearanceProbe"
marker:SetAttribute("MapDetail", true)
marker:PivotTo(CFrame.new(6002.6, 0, 6000) * CFrame.Angles(0, math.rad(45), 0))
marker.Parent = decor
ManorDecor.ClearArea(Vector3.new(6000, 0, 6000), 0.5, 0.5)
check(marker.Parent == nil, "Rotated scenery survives boss/wheel clearance")
if marker.Parent then
	marker:Destroy()
end
local output = Instance.new("StringValue")
output.Name = "CodexMapDetailAuditResult"
output.Value =
	HttpService:JSONEncode({ Passed = result.Passed, Failed = result.Failed, Errors = result.Errors, Counts = counts })
output.Parent = ServerStorage
print("[MapDetailAudit] " .. output.Value)
