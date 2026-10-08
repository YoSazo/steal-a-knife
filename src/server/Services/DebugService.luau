--!strict
-- Studio-only test hooks (never created in a live server). Command-bar / MCP code runs in its own
-- module instances, so it reaches the real game state through this BindableFunction:
--   game.ServerStorage.Debug:Invoke("Give", player, { "Katana", ... }, equip?)
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
local InventoryService = require(script.Parent.InventoryService)
local Analytics = require(script.Parent.Analytics)
local Net = require(script.Parent.Parent.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Items)
local RoundService = require(script.Parent.RoundService)
local StealService = require(script.Parent.StealService)
local CoffinService = require(script.Parent.CoffinService)
local GuardService = require(script.Parent.GuardService)

local DebugService = {}

local commands: { [string]: (Player, ...any) -> any } = {
	-- equip = true also makes the last one given your fighting / Murderer knife
	Give = function(player: Player, names: { string }, equip: boolean?)
		DataService.Update(player, function(p)
			for _, item in names do
				DataService.AddKnife(p, item)
				local name = Items.Name(item)
				if not table.find(p.Discovered, name) then
					table.insert(p.Discovered, name)
				end
			end
			if equip and #names > 0 then
				p.Equipped = names[#names]
			end
		end)
		BaseService.RefreshRack(player)
		return true
	end,
	-- The last n analytics events (newest last), each as "event {json props}"
	-- raw = the exact JSON body the ingest server would get
	Analytics = function(_player: Player, n: number?, raw: boolean?)
		if raw then
			return game:GetService("HttpService"):JSONEncode({ batch = Analytics.Recent(n) })
		end
		local out = {}
		for _, event in Analytics.Recent(n) do
			table.insert(out, `{event.event} {game:GetService("HttpService"):JSONEncode(event.props)}`)
		end
		return out
	end,
	-- A surprise gift right now, in front of you
	Gift = function(player: Player)
		(require(script.Parent.SurpriseGifts) :: any).DebugDrop(player)
		return true
	end,
	Cash = function(player: Player, amount: number)
		DataService.AddCash(player, amount, "debug")
		return true
	end,
	Data = function(player: Player)
		return DataService.Get(player)
	end,
	-- Speed stat; nil = enough for max walk speed (GameConfig.MaxWalkSpeed)
	Speed = function(player: Player, amount: number?)
		local target = amount or 7e8
		DataService.Update(player, function(p)
			p.Speed = target
		end)
		BaseService.RefreshWalkSpeed(player)
		return GameConfig.WalkSpeedFor(target)
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
	-- Pretend this is an old save with cash-bought powers, then run the migration (tests the refund)
	OldPowers = function(player: Player)
		DataService.Update(player, function(p)
			p.Powers = { Vanish = 2, Radar = 1 }
			p.Loadout = { "Vanish" }
			local index = table.find(p.Bought, "PowerRefund")
			if index then
				table.remove(p.Bought, index)
			end
		end)
		local profile = DataService.Get(player)
		if profile then
			InventoryService.DebugRefund(player, profile)
		end
		return true
	end,
	-- Offer tests reach the real pending-token/cooldown state, rather than a command-bar module copy.
	Offer = function(player: Player, key: string)
		require(script.Parent.Offers).Show(player, key, "Studio offer check", true)
		return true
	end,
	Heat = function(player: Player, amount: number)
		DataService.Update(player, function(p)
			p.Heat = math.clamp(amount, 0, GameConfig.Fuel.MaxHeat)
		end)
		return true
	end,
	Home = function(player: Player)
		BaseService.SetReturnSpot(player, nil)
		BaseService.TeleportHome(player)
		return true
	end,
	-- Steal from a boss's wall for real (the boss chases you): tests guard hits and thrown knives
	BossSteal = function(player: Player, zone: number?)
		return GuardService.DebugSteal(player, zone or 1)
	end,
	-- Start carrying a knife right now, as if just stolen (tests the run home / placing)
	Carry = function(player: Player, name: string?, sealed: boolean?)
		StealService.StartCarry(player, "Knife", name or "KitchenKnife", nil, if sealed then "coffin" else nil)
		return true
	end,
	Knock = function(player: Player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			StealService.KnockLoose(player, player, root.Position - Vector3.xAxis)
		end
		return root ~= nil
	end,
	Pickup = function(player: Player, model: Model)
		return StealService.TakeDrop(player, model)
	end,
	SuspendResume = function(player: Player)
		StealService.Suspend(player)
		StealService.Resume(player)
		return true
	end,
	-- A mystery coffin, as a gift / wheel prize / daily streak would give it
	Coffin = function(player: Player, rarity: string?)
		return CoffinService.GiveRarity(player, rarity or "Epic", "Studio") ~= nil
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
