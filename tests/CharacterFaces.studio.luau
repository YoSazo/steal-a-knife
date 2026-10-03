--!strict
-- Run as a temporary server Script in Studio. Builds a disposable, non-interactive gallery.
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
assert(RunService:IsStudio(), "Character face audit is Studio-only")
ServerStorage:WaitForChild("Debug", 45)
local services = game:GetService("ServerScriptService").Server.Services
local Disguises = require(services.Disguises)
local CharacterFaces = require(services.CharacterFaces)
local CharacterDetails = require(services.CharacterDetails)
local names = {
	"Nick",
	"Frank",
	"Rose",
	"Lucy",
	"Jake",
	"Emma",
	"Oscar",
	"Mia",
	"Leo",
	"Zoe",
	"Max",
	"Ruby",
	"Sam",
	"Ivy",
	"Ben",
	"Kate",
}
local gallery = Instance.new("Folder")
gallery.Name = "CharacterFaceAuditGallery"
gallery.Parent = workspace
local result = { Passed = 0, Failed = 0, Errors = {} :: { string } }
local function check(condition: boolean, message: string)
	if condition then
		result.Passed += 1
	else
		result.Failed += 1
		table.insert(result.Errors, message)
	end
end
for index, name in names do
	local rig = Disguises.BuildCharacter(name)
	rig.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local head = rig:FindFirstChild("Head") :: BasePart
	check(head:IsA("Part"), name .. ": not a classic Part head")
	local mesh = head:FindFirstChildOfClass("SpecialMesh")
	check(mesh ~= nil and mesh.MeshType == Enum.MeshType.Head and mesh.TextureId == "", name .. ": baked face remains")
	local faces = 0
	for _, child in head:GetChildren() do
		if child:IsA("Decal") then
			faces += 1
			check(child.Face == Enum.NormalId.Front and child.Texture ~= "", name .. ": invalid expression")
		end
	end
	check(faces == 1, name .. ": duplicate face")
	local neck = head:FindFirstChild("Neck")
	check(neck ~= nil, name .. ": neck missing")
	if neck and neck:IsA("AnimationConstraint") then
		check(neck.Attachment1 ~= nil and neck.Attachment1.Parent == head, name .. ": neck attachment detached")
	end
	local face = head:FindFirstChild("face") :: Decal
	local texture = face.Texture
	local repeated = CharacterFaces.Apply(head, texture)
	check(repeated == head and #head:GetChildren() > 1, name .. ": reapply replaced the classic head")
	check((head:FindFirstChild("face") :: Decal).Texture == texture, name .. ": expression changed on reapply")
	local details = rig:FindFirstChild("DisguiseDetails")
	check(details ~= nil, name .. ": detail finish missing")
	local detailCount = 0
	if details then
		for _, child in details:GetDescendants() do
			if child:IsA("BasePart") then
				detailCount += 1
				check(
					child.Massless and not child.CanCollide and not child.CanQuery and not child.CanTouch,
					name .. ": detail affects physics"
				)
			end
		end
	end
	check(detailCount <= 40, name .. ": detail part budget exceeded")
	CharacterDetails.Apply(rig, name)
	check(rig:FindFirstChild("DisguiseDetails") ~= details, name .. ": detail reapply not rebuilt")
	local detailGroups = 0
	for _, child in rig:GetChildren() do
		if child.Name == "DisguiseDetails" then
			detailGroups += 1
		end
	end
	check(detailGroups == 1, name .. ": duplicate detail sets")
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	rig:PivotTo(CFrame.new(6000 + ((index - 1) % 4) * 9, 3, math.floor((index - 1) / 4) * 14))
	rig.Parent = gallery
end
-- Both legacy Motor6D rigs and current AnimationConstraint rigs must keep their references.
local fixture = Instance.new("Model")
local original = Instance.new("MeshPart")
original.Name = "Head"
original.Size = Vector3.new(1.2, 1.2, 1.2)
original.Parent = fixture
local torso = Instance.new("Part")
torso.Name = "UpperTorso"
torso.Parent = fixture
local neck = Instance.new("Motor6D")
neck.Part0 = torso
neck.Part1 = original
neck.Parent = original
local socket = Instance.new("Attachment")
socket.Parent = original
local accessory = Instance.new("WeldConstraint")
accessory.Part0 = original
accessory.Part1 = torso
accessory.Parent = torso
local noCollision = Instance.new("NoCollisionConstraint")
noCollision.Part0 = original
noCollision.Part1 = torso
noCollision.Parent = torso
local label = Instance.new("BillboardGui")
label.Adornee = original
label.Parent = original
local clean = CharacterFaces.Apply(original, "rbxassetid://80477324382185")
check(neck.Part1 == clean, "legacy neck not rebound")
check(accessory.Part0 == clean, "accessory not rebound")
check(noCollision.Part0 == clean, "collision constraint not rebound")
check(socket.Parent == clean, "attachment not preserved")
check(label.Adornee == clean, "billboard not rebound")
local duplicate = Instance.new("Decal")
duplicate.Name = "Face"
duplicate.Parent = clean
CharacterFaces.Apply(clean, "rbxassetid://137483136763270")
local count = 0
for _, child in clean:GetChildren() do
	if child:IsA("Decal") then
		count += 1
	end
end
check(count == 1, "reapply leaves duplicate decals")
fixture:Destroy()
local players = game:GetService("Players")
local player = players:GetPlayers()[1] or players.PlayerAdded:Wait()
local character = player.Character or player.CharacterAdded:Wait()
local storage = game:GetService("ReplicatedStorage")
if storage:GetAttribute("Phase") == "Intermission" and not player:GetAttribute("InRound") then
	local before = character:FindFirstChild("Head") :: BasePart
	local originalClass = before.ClassName
	local originalMesh = if before:IsA("MeshPart") then before.MeshId else ""
	local originalTexture = if before:IsA("MeshPart") then before.TextureID else ""
	Disguises.Assign({ player })
	local disguised = character:FindFirstChild("Head") :: BasePart
	check(
		disguised:IsA("Part") and disguised:GetAttribute("ClassicCharacterFace") == true,
		"player disguise has a dynamic head"
	)
	check((character:FindFirstChildOfClass("Humanoid") :: Humanoid).Health > 0, "player died when replacing head")
	Disguises.Remove(player)
	local deadline = os.clock() + 15
	repeat
		task.wait(0.1)
		local current = character:FindFirstChild("Head")
		if current and current:GetAttribute("ClassicCharacterFace") ~= true then
			break
		end
	until os.clock() > deadline
	local restored = character:FindFirstChild("Head") :: BasePart
	check(
		restored.ClassName == originalClass and restored:GetAttribute("ClassicCharacterFace") ~= true,
		"original head not restored"
	)
	if restored:IsA("MeshPart") then
		check(restored.MeshId == originalMesh and restored.TextureID == originalTexture, "original avatar face changed")
	end
	check(
		character:FindFirstChild("DisguiseDetails") == nil and character:FindFirstChild("DisguiseHat") == nil,
		"disguise accessories survive removal"
	)
	check(player:GetAttribute("Disguise") == nil, "disguise identity not cleared")
	check((character:FindFirstChildOfClass("Humanoid") :: Humanoid).Health > 0, "player died restoring head")
else
	result.Failed += 1
	table.insert(result.Errors, "Avatar restoration test needs an intermission")
end
workspace:SetAttribute("CharacterFaceAuditResult", HttpService:JSONEncode(result))
print("[CharacterFaceAudit] " .. HttpService:JSONEncode(result))
