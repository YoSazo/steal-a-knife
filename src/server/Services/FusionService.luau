--!strict
-- Earned mutations only: three visible duplicates and one banked win charge.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local Rules = require(ReplicatedStorage.Shared.FusionRules)
local DataService = require(script.Parent.DataService)
local BaseService = require(script.Parent.BaseService)
local Net = require(script.Parent.Parent.Remotes)
local Analytics = require(script.Parent.Analytics)
local FusionService = {}
local machines: { [Player]: Model } = {}
local last: { [Player]: number } = {}
local CONFIG = GameConfig.Fusion

local function block(model: Model, name: string, size: Vector3, at: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, at, color
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Studs
	p.Parent = model
	return p
end
local function build(player: Player)
	local base = BaseService.GetBase(player)
	if not base then
		return
	end
	local at = base.Frame * CFrame.new(22, 0.6, 20)
	local model = Instance.new("Model")
	model.Name = "FuseMachine"
	model:SetAttribute("Owner", player.UserId)
	local bed = block(model, "Bed", Vector3.new(8, 1, 6), at, Color3.fromRGB(150, 80, 230))
	model.PrimaryPart = bed
	for i = -1, 1 do
		local pad = block(
			model,
			"Input",
			Vector3.new(1.6, 0.3, 1.6),
			at * CFrame.new(i * 2.2, 0.65, 1.5),
			Color3.fromRGB(70, 200, 120)
		)
		pad.CanCollide = false
	end
	local output =
		block(model, "Output", Vector3.new(3, 0.4, 2), at * CFrame.new(0, 0.7, -1.2), Color3.fromRGB(255, 195, 45))
	output.Material = Enum.Material.Neon
	output.CanCollide = false
	local back = block(model, "Back", Vector3.new(7, 3, 0.5), at * CFrame.new(0, 2, -2.6), Color3.fromRGB(95, 50, 165))
	local gui = Instance.new("BillboardGui")
	gui.Name = "FuseLabel"
	gui.Size = UDim2.fromOffset(200, 64)
	gui.StudsOffset = Vector3.new(0, 2.8, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Parent = back
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "FUSE\n3 → 1 · ⚡1"
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 26
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Parent = label
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Fuse"
	prompt.ObjectText = "3 → 1 · ⚡1"
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt:SetAttribute("FuseOwner", player.UserId)
	prompt.Parent = back
	model.Parent = base.Folder
	machines[player] = model
end
local function fuse(player: Player, key: unknown): (boolean, string)
	if type(key) ~= "string" or #key > 80 then
		return false, "Choose a knife!"
	end
	if os.clock() - (last[player] or 0) < 0.5 then
		return false, "Wait a moment!"
	end
	last[player] = os.clock()
	local model = machines[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if
		not model
		or not root
		or not humanoid
		or humanoid.Health <= 0
		or player:GetAttribute("InRound")
		or player:GetAttribute("Carrying")
		or not BaseService.IsInOwnBase(player, root.Position)
		or (root.Position - model:GetPivot().Position).Magnitude > 80
	then
		return false, "Get home first!"
	end
	if BaseService.HasHatch(player) then
		return false, "Place your new knife first!"
	end
	local profile = DataService.Get(player)
	if not profile then
		return false, "Wait a moment!"
	end
	if profile.FuseCharges < 1 then
		return false, "Win a round for ⚡1!"
	end
	local sealed: { [number]: boolean } = {}
	for index in profile.Knives do
		if DataService.IsSealedIndex(profile, index) then
			sealed[index] = true
		end
	end
	local chosen: Rules.Group? = nil
	for _, group in Rules.Groups(profile.Knives, sealed) do
		if group.Key == key then
			chosen = group
			break
		end
	end
	if not chosen or chosen.Count < CONFIG.Required then
		return false, "Need 3 same unlocked knives!"
	end
	local indexes = {}
	local parsed = Items.Parse(chosen.Item) :: Items.Item
	local size = parsed.Size
	for i = 1, CONFIG.Required do
		local index = chosen.Indexes[i]
		table.insert(indexes, index)
		local item = Items.Parse(profile.Knives[index]) :: Items.Item
		if item.Size.Income > size.Income then
			size = item.Size
		end
	end
	local output = Items.Make(parsed.Name, Items.Mutations[parsed.Mutation.Rank + 2].Id, size.Id)
	local plate = profile.Plates[indexes[1]]
	table.sort(indexes, function(a, b)
		return a > b
	end)
	local banked = 0
	DataService.Update(player, function(p)
		p.FuseCharges -= 1
		local replacingPick = false
		for _, index in indexes do
			local slot = p.Plates[index]
			banked += p.Pending[slot] or 0
			p.Pending[slot] = nil
			p.Spots[tostring(slot)] = nil
			if p.Equipped == p.Knives[index] then
				replacingPick = true
			end
			DataService.RemoveKnife(p, index)
		end
		DataService.AddKnife(p, output, plate)
		p.Cash += banked
		if replacingPick and not table.find(p.Knives, p.Equipped) then
			p.Equipped = output
		end
	end)
	if banked > 0 then
		DataService.CashFlow(player, banked, "fusion_income")
	end
	BaseService.RefreshRack(player)
	Analytics.Track(
		player,
		"knife.fused",
		{ knife = parsed.Name, mutation = (Items.Parse(output) :: Items.Item).Mutation.Id }
	)
	Net.Remotes.Effect:FireAllClients("Deposit", player, parsed.Knife.Rarity)
	Net.Notify(player, `✨ {Items.DisplayName(output)}!`, "good")
	return true, "Fused!"
end
function FusionService.Init()
	Net.Remotes.Fuse.OnServerInvoke = Analytics.Remote("Fuse", fuse)
	BaseService.Claimed:Connect(build)
	Players.PlayerRemoving:Connect(function(player)
		if machines[player] then
			machines[player]:Destroy()
		end
		machines[player] = nil
		last[player] = nil
	end)
end
return FusionService
