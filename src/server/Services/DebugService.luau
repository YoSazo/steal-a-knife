--!strict
-- Studio-only test hooks (never created in a live server). Command-bar / MCP code runs in its own
-- module instances, so it reaches the real game state through this BindableFunction:
--   game.ServerStorage.Debug:Invoke("Give", player, { "Katana", ... })
--   game.ServerStorage.Debug:Invoke("Cash", player, 5000)
--   game.ServerStorage.Debug:Invoke("Data", player) -> profile
--   game.ServerStorage.Debug:Invoke("StartRound", player) -> starts/skips to a one-player round
--   game.ServerStorage.Debug:Invoke("Drop", player, "Katana") -> drops that knife in front of them
--   game.ServerStorage.Debug:Invoke("BotRound", player, "Murderer" | "Innocent") -> a round with bots

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local Net = require(script.Parent.Parent.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local RoundService = require(script.Parent.RoundService)
local StealService = require(script.Parent.StealService)
local RaidService = require(script.Parent.RaidService)

local DebugService = {}

local commands: { [string]: (Player, ...any) -> any } = {
	Give = function(player: Player, names: { string })
		DataService.Update(player, function(p)
			for _, item in names do
				table.insert(p.Knives, item)
				local name = Items.Name(item)
				if not table.find(p.Discovered, name) then
					table.insert(p.Discovered, name)
				end
			end
		end)
		BaseService.RefreshRack(player)
		return true
	end,
	Cash = function(player: Player, amount: number)
		DataService.AddCash(player, amount)
		return true
	end,
	Data = function(player: Player)
		return DataService.Get(player)
	end,
	StartRound = function(player: Player)
		ReplicatedStorage:SetAttribute("DebugMinPlayers", 1)
		ReplicatedStorage:SetAttribute("DebugSkip", true)
		Net.Notify(player, "Studio debug: starting a one-player round...", "info")
		return true
	end,
	Drop = function(player: Player, name: string)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			StealService.DropKnife(name, root.Position + root.CFrame.LookVector * 5)
		end
		return root ~= nil
	end,
	Case = function(player: Player, rarity: string?)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			StealService.DropCase(rarity or "Common", root.Position + root.CFrame.LookVector * 5)
		end
		return root ~= nil
	end,
	Raid = function(player: Player)
		if RaidService.IsRaiding() then
			RaidService.Stop()
		else
			RaidService.Start()
		end
		Net.Notify(player, "Studio debug: raid toggled", "info")
		return true
	end,
	Walls = function(player: Player, level: number)
		DataService.Update(player, function(p)
			p.WallLevel = math.clamp(level, 1, #GameConfig.Walls)
		end)
		return true
	end,
	BotRound = function(player: Player, role: string)
		if ReplicatedStorage:GetAttribute("Phase") ~= "Intermission" then
			Net.Notify(player, "Wait for this round to end first", "bad")
			return false
		end
		RoundService.DebugBotRound(player, role)
		Net.Notify(player, `Bot round: you're the {if role == "Innocent" then "Innocent" else "Murderer"}!`, "info")
		return true
	end,
}

function DebugService.Init()
	if not RunService:IsStudio() then
		return
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "Debug"
	hook.OnInvoke = function(command: string, player: Player, ...)
		local fn = commands[command]
		return if fn then fn(player, ...) else nil
	end
	hook.Parent = ServerStorage

	Net.Remotes.Debug.OnServerInvoke = function(player: Player, command: string, ...)
		local fn = commands[command]
		return if fn then fn(player, ...) else nil
	end
end

return DebugService
