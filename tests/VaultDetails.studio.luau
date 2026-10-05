--!strict
-- Detached fixtures only. The runner supplies fresh modules to avoid Studio's require cache.
local VaultModel = require(script.Parent.VaultModel)
local VaultWalls = require(script.Parent.VaultWalls)
local MapStyle = require(script.Parent.MapStyle)
local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local passed = 0
local function check(ok: boolean, message: string)
	assert(ok, message)
	passed += 1
end

local function decorate(folder: Instance, frame: CFrame, floors: number, tier: number)
	local floorsList, pads, arts, cash = {}, {}, {}, {}
	for floor = 1, floors do
		local level = Instance.new("Folder")
		level.Name = `Floor{floor}`
		level.Parent = folder
		floorsList[floor] = level
		local surface = if floor == 1 then 0.6 else (floor - 1) * 22
		VaultModel.BuildFloor(level, frame, surface)
		if floor > 1 then
			VaultModel.BuildLadder(level, frame, if floor == 2 then 0.6 else surface - 22, -17)
		end
		for index = 1, 10 do
			local side = if index <= 5 then -1 else 1
			local z = -17 + (index - 1) % 5 * 8
			local slot = (floor - 1) * 10 + index
			local at = frame * CFrame.new(side * 12, surface, z)
			local plate = VaultModel.BuildPlate(level, at, slot)
			check(plate.Pad.Transparency == 1 and plate.Rim ~= plate.Pad, "Plate state must not reveal a square pad")
			local counts = {}
			for _, part in plate.Details:GetChildren() do
				if part:IsA("BasePart") then
					counts[part.Name] = (counts[part.Name] or 0) + 1
				end
			end
			check(counts.MetalOctagonEdge == 8 and counts.CyanOctagonEdge == 8, "Plate must have eight distinct edges")
			check(counts.IvoryDiamond == 32, "Eight hollow diamonds must be actual blocks")
			check(counts.GoldFrameRail == 4, "Reference gold frame missing")
			for _, state in { Color3.fromRGB(150, 150, 160), Color3.new(1, 1, 1), Color3.fromRGB(49, 218, 220) } do
				plate.Rim.Color = state
				plate.Rim.Material = if state == Color3.fromRGB(150, 150, 160)
					then Enum.Material.SmoothPlastic
					else Enum.Material.Neon
				VaultModel.SetPlateGlow(plate.Rim)
				for _, part in plate.Details:GetChildren() do
					if part:IsA("BasePart") and part:GetAttribute("PlateGlow") then
						local highlight = part:GetAttribute("PlateHighlight")
						local expected = if type(highlight) == "number"
							then state:Lerp(Color3.new(1, 1, 1), highlight)
							else state
						check(
							math.abs(part.Color.R - expected.R) < 1 / 255
								and math.abs(part.Color.G - expected.G) < 1 / 255
								and math.abs(part.Color.B - expected.B) < 1 / 255,
							"Locked/equipped state failed on an octagon segment"
						)
					end
				end
			end
			VaultModel.SetPlateTier(plate.Details, at, tier)
			pads[slot] = plate.Pad
			local art = Instance.new("ImageLabel")
			art.Name = "PreservedPlateArt"
			art.Image = "rbxassetid://123"
			art.Size = UDim2.fromScale(1, 1)
			art.Parent = plate.Pad
			arts[slot] = art
			local padAt = (frame * CFrame.new(side * 6.2, surface + 0.06, z)).Position
			local toward = frame:VectorToWorldSpace(Vector3.new(side, 0, 0))
			local cashPad = Instance.new("Part")
			cashPad.Name = `CashPad{slot}`
			cashPad.CFrame = CFrame.lookAt(padAt, padAt - toward) * CFrame.Angles(0, math.pi / 2, 0)
			cashPad.Size = Vector3.new(3.8, 0.12, 5.2)
			cashPad.Parent = level
			cash[slot] = cashPad
			VaultModel.BuildCollectTray(level, cashPad.CFrame * CFrame.new(0, 0.04, 0), slot)
		end
		VaultModel.ApplyTier(level, tier)
	end
	return { FloorFolders = floorsList, SlotPads = pads, PlateArts = arts, CashPads = cash, Folder = folder }
end

for tier, spec in GameConfig.Walls do
	for _, floors in { 1, 2, 3, 4 } do
		local fixture = Instance.new("Folder")
		local frame = CFrame.new(51, 0, -87) * CFrame.Angles(0, math.rad(90), 0)
		local built = VaultWalls.Build(fixture, frame, Color3.fromRGB(110, 210, 255), tier, floors)
		check(built.Height == floors * 22 + 4, "Vault height or floor spacing changed")
		check(built.Blocker:GetAttribute("Health") == spec.GateHealth, "Raid health changed")
		check(built.Blocker:GetAttribute("Floors") == floors, "Raid floor count changed")
		check(built.Blocker.Size == Vector3.new(16, 11, 1.2), "Raid hitbox changed")
		check(built.Blocker.CanQuery and not built.Blocker.CanTouch, "Raid hit target changed")
		local health = built.Blocker:FindFirstChild("GateHealth") :: BillboardGui
		check(health ~= nil and health.Size == UDim2.fromScale(10, 2.3), "Gate health UI changed")
		check((health:FindFirstChild("Title") :: TextLabel).Text == spec.Name, "Gate UI text changed")
		local base = decorate(fixture, frame, floors, tier)
		local anchors, cashFrames = {}, {}
		for slot, pad in base.SlotPads do
			anchors[slot] = pad.CFrame
			cashFrames[slot] = base.CashPads[slot].CFrame
			check(
				pad.Position
					== (frame * CFrame.new(
						if (slot - 1) % 10 < 5 then -12 else 12,
						(if slot <= 10 then 0.6 else ((slot - 1) // 10) * 22) + 0.15,
						-17 + (slot - 1) % 5 * 8
					)).Position,
				"Plate prompt anchor moved"
			)
		end
		MapStyle.SetVaultTier(base :: any, 9 - tier)
		for slot, pad in base.SlotPads do
			check(pad.CFrame == anchors[slot], "Tier swap moved a prompt anchor")
			check(base.CashPads[slot].CFrame == cashFrames[slot], "Tier swap moved a collection hitbox")
			check(base.PlateArts[slot].Image == "rbxassetid://123", "Tier swap changed artwork")
			check(base.PlateArts[slot].Size == UDim2.fromScale(1, 1), "Tier swap resized UI")
			check(pad:GetAttribute("VaultInset") == VaultModel.Style(9 - tier).Inset, "Plate finish failed to upgrade")
		end
		MapStyle.SetVaultTier(base :: any, tier)
		for _, part in fixture:GetDescendants() do
			if part:IsA("BasePart") and part:GetAttribute("VaultDetail") then
				check(
					part.Anchored and not part.CanCollide and not part.CanQuery and not part.CanTouch,
					"Decoration blocks gameplay"
				)
				check(part:IsA("Part") and part.Shape == Enum.PartType.Block, "Vault detail is not block-built")
			end
		end
		VaultWalls.SetOpen(built.Gate, true)
		check(built.Blocker:GetAttribute("Open") == true, "Raid gate cannot open")
		VaultWalls.SetOpen(built.Gate, false)
		check(built.Blocker:GetAttribute("Open") == nil, "Raid gate cannot reclose")
		local architecture = fixture:FindFirstChild("VaultArchitecture") :: Model
		check(architecture ~= nil, "Tier architecture missing")
		for _, level in base.FloorFolders do
			local tiles = level:FindFirstChild("VaultFloorDetails") :: Model
			for _, tile in tiles:GetChildren() do
				if tile:IsA("BasePart") and tile.Name == "AisleTile" then
					local at = frame:PointToObjectSpace(tile.Position)
					check(at.Z - tile.Size.Z / 2 >= -13, "Floor trim covers the ladder opening")
				end
			end
			local hardware = 0
			for _, p in level:GetDescendants() do
				if p.Name == "PlateTierHardware" then
					hardware += 1
				end
			end
			check(hardware == 10, "Tier refresh leaked duplicate plate hardware")
		end
		fixture:Destroy()
	end
end
return { Passed = passed, Tiers = #GameConfig.Walls, FloorCounts = { 1, 2, 3, 4 }, UIUnchanged = true }
