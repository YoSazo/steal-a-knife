--!strict
-- The Blood Moon: every few intermissions (or summoned with Robux / by a Murderer's wipe), for
-- GameConfig.Raid.Duration seconds the biomes close and the vaults open: any knife on another
-- player's plates (except the one they fight with) can be stolen. Hold Steal on it, carry it home
-- and place it like any other knife. The owner (or anyone) can hit a carrier with their knife to
-- knock it loose (StealService.KnockLoose). New players are never robbed, and a vault loses at most
-- GameConfig.Raid.StealsPerVault knives per moon.
--   * on rising: a red wall closes the runway, and everyone out in the biomes is sent home (a boss's
--     knife they were carrying goes back on its wall, no penalty)
--   * state for clients: ReplicatedStorage Raid / RaidEndsAt / NextRaidAt (client/Raid lights the
--     Steal prompts up, client/Atmosphere the red sky)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local Net = require(script.Parent.Parent.Remotes)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local PowerService = require(script.Parent.PowerService)
local StealService = require(script.Parent.StealService)
local ServerEvents = require(script.Parent.ServerEvents)
local Analytics = require(script.Parent.Analytics)

local RaidService = {}

local CONFIG = GameConfig.Raid

local raiding = false
local raidEndsAt = 0
local moonWall: BasePart? = nil
local stolenFrom: { [Player]: number } = {} -- knives taken from each vault this moon

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function onRunway(position: Vector3): boolean
	return position.Z > -2 and math.abs(position.X) < GameConfig.ArenaWidth / 2 + 2
end

function RaidService.IsRaiding(): boolean
	return raiding
end

-- Players never fight each other with powers (powers are a murder-round thing now)
function RaidService.CanAttackPlayer(_attacker: Player, _victim: Player): boolean
	return false
end

function RaidService.AuraPower(item: string): number
	return Items.AuraPower(item)
end

-- Stealing from a vault ------------------------------------------------------------------------

local function steal(thief: Player, owner: Player, item: string)
	if not raiding or thief == owner or thief:GetAttribute("InRound") or StealService.IsCarrying(thief) then
		return
	end
	local profile = DataService.Get(owner)
	if not profile or DataService.IsNewPlayer(owner, profile) or owner:GetAttribute("InRound") then
		return
	end
	if (stolenFrom[owner] or 0) >= CONFIG.StealsPerVault then
		Net.Notify(thief, `{owner.DisplayName}'s vault has been robbed enough this moon!`, "bad")
		return
	end
	local index = table.find(profile.Knives, item)
	if not index or item == BaseService.ProtectedItem(owner) or not rootOf(thief) then
		return
	end
	stolenFrom[owner] = (stolenFrom[owner] or 0) + 1
	DataService.Update(owner, function(p)
		DataService.RemoveKnife(p, index)
	end)
	BaseService.RefreshRack(owner)
	StealService.StartCarry(thief, "Knife", item, owner.UserId)
	Analytics.Track(owner, "moon.robbed", { knife = Items.Name(item), value = Items.Income(item) })
	local name = Items.DisplayName(item)
	Net.Notify(owner, `🌕 {thief.DisplayName} is stealing your {name}! Hit them to knock it loose!`, "bad")
	Net.Announce(`🌕 {thief.DisplayName} stole {owner.DisplayName}'s {name}!`, Color3.fromRGB(255, 80, 80), 2)
end

-- The moon --------------------------------------------------------------------------------------

-- A glowing red wall across the start of the runway: the biomes are shut while the moon is up
local function closeBiomes()
	local wall = Instance.new("Part")
	wall.Name = "MoonWall"
	wall.Anchored = true
	wall.CanCollide = true
	wall.CastShadow = false
	wall.Material = Enum.Material.ForceField
	wall.Color = Color3.fromRGB(255, 40, 50)
	wall.Transparency = 0.2
	wall.Size = Vector3.new(GameConfig.ArenaWidth + 8, 80, 2)
	wall.CFrame = CFrame.new(0, 38, -1)
	wall.Parent = workspace:FindFirstChild("Map") or workspace
	moonWall = wall
	-- Everyone out in the biomes goes home (a boss's knife goes back on its wall, no penalty)
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and onRunway(root.Position) and not player:GetAttribute("InRound") then
			StealService.CancelBossCarry(player)
			Net.Remotes.Effect:FireClient(player, "Fade", "🌕 The Blood Moon rises - the biomes close!")
			task.delay(0.35, function()
				BaseService.TeleportHome(player)
			end)
		end
	end
end

function RaidService.Start()
	if raiding then
		return
	end
	raiding = true
	table.clear(stolenFrom)
	raidEndsAt = now() + CONFIG.Duration
	ReplicatedStorage:SetAttribute("Raid", true)
	ReplicatedStorage:SetAttribute("RaidEndsAt", raidEndsAt)
	closeBiomes()
	Analytics.Track(nil, "moon.start", { players = #Players:GetPlayers() })
	for _, player in Players:GetPlayers() do
		Analytics.Track(player, "moon.seen")
	end
	Net.Announce(
		"🌕 BLOOD MOON! The biomes are closed - steal knives from other vaults and bring them home!",
		Color3.fromRGB(255, 60, 60),
		3
	)
	Net.Remotes.Effect:FireAllClients("RaidStart", raidEndsAt)
end

function RaidService.Stop()
	if not raiding then
		return
	end
	raiding = false
	local robbed = 0
	for _, count in stolenFrom do
		robbed += count
	end
	Analytics.Track(nil, "moon.end", { steals = robbed, players = #Players:GetPlayers() })
	ReplicatedStorage:SetAttribute("Raid", nil)
	ReplicatedStorage:SetAttribute("RaidEndsAt", nil)
	if moonWall then
		moonWall:Destroy()
		moonWall = nil
	end
	Net.Announce("The Blood Moon sets. The biomes are open again!", Color3.fromRGB(200, 200, 220), 1)
	Net.Remotes.Effect:FireAllClients("RaidEnd")
end

-- Summon the Blood Moon (Robux): now if we can, otherwise as soon as the next intermission
-- allows; during one already it lasts a minute longer
local pendingSummon: string? = nil
function RaidService.Summon(player: Player)
	Analytics.Track(player, "moon.summon", { during = raiding })
	if raiding then
		raidEndsAt += 60
		ReplicatedStorage:SetAttribute("RaidEndsAt", raidEndsAt)
		Net.Announce(`🌕 {player.DisplayName} made the Blood Moon last longer!`, Color3.fromRGB(255, 70, 70), 2)
		return
	end
	pendingSummon = player.DisplayName
	Net.Notify(player, "The Blood Moon will rise as soon as the next intermission allows", "info")
end

-- Moons rise near the end of every CONFIG.Every-th intermission (StartBefore before the round)
local function schedule()
	local raidedThisIntermission = false
	local intermissions = 0
	local counted = false
	while true do
		task.wait(0.5)
		local phase = ReplicatedStorage:GetAttribute("Phase")
		local endsAt = ReplicatedStorage:GetAttribute("PhaseEndsAt")
		local waiting = ReplicatedStorage:GetAttribute("Status") ~= "🔪 MURDER ROUND in"
		if phase == "Intermission" and type(endsAt) == "number" and not waiting then
			if not counted then
				counted = true
				intermissions += 1
			end
			local left = endsAt - now()
			if pendingSummon and not raiding and left > CONFIG.Duration * 0.5 then
				local who = pendingSummon
				pendingSummon = nil
				RaidService.Start()
				raidedThisIntermission = true
				Net.Announce(`🌕 {who} summoned the BLOOD MOON!`, Color3.fromRGB(255, 60, 60), 3)
			end
			local moonDue = intermissions % CONFIG.Every == 0
			ReplicatedStorage:SetAttribute(
				"NextRaidAt",
				if raidedThisIntermission or not moonDue then nil else endsAt - CONFIG.StartBefore
			)
			if
				moonDue
				and not raidedThisIntermission
				and not raiding
				and left <= CONFIG.StartBefore
				and left > 20
				and #Players:GetPlayers() >= CONFIG.MinPlayers
			then
				raidedThisIntermission = true
				RaidService.Start()
			end
		else
			ReplicatedStorage:SetAttribute("NextRaidAt", nil)
			if phase ~= "Intermission" then
				raidedThisIntermission = false
				counted = false
			end
		end
		-- Over on time, and always before the round starts
		if raiding and (now() >= raidEndsAt or phase ~= "Intermission") then
			RaidService.Stop()
		end
	end
end

function RaidService.Init()
	BaseService.OnStealPrompt = steal
	PowerService.CanRaidPlayer = RaidService.CanAttackPlayer
	-- A Murderer wipe calls the Blood Moon (now, or as soon as the intermission allows)
	ServerEvents.OnWipe = function(name: string)
		Net.Announce(`🔪 {name}'s massacre is calling the Blood Moon!`, Color3.fromRGB(255, 70, 70), 3)
		if raiding then
			raidEndsAt += 60
			ReplicatedStorage:SetAttribute("RaidEndsAt", raidEndsAt)
		else
			pendingSummon = name
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		stolenFrom[player] = nil
	end)
	task.spawn(schedule)
end

return RaidService
