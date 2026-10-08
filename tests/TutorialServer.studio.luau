-- Execute original server module sources with isolated data, effects and scheduled callbacks.
-- No live profile writes, network calls or DataStores. Call through the Studio test runner.
return function(t)
	local function noOp() end
	local function fixture(moduleName, completed)
		local folder = Instance.new("Folder")
		folder.Parent = game.ServerStorage.UnitTest
		local envModule = Instance.new("ModuleScript")
		envModule.Name = "Environment"
		envModule.Source = "return {}"
		envModule.Parent = folder
		local deps = require(envModule)
		local attributes = Instance.new("Folder")
		attributes.Parent = folder
		local player = { Name = "TutorialTest", DisplayName = "TutorialTest", UserId = -1, Parent = folder }
		function player:GetAttribute(name)
			return attributes:GetAttribute(name)
		end
		function player:SetAttribute(name, value)
			attributes:SetAttribute(name, value)
		end
		local character = Instance.new("Model")
		character.Parent = folder
		for _, name in { "Head", "HumanoidRootPart" } do
			local part = Instance.new("Part")
			part.Name = name
			part.Parent = character
		end
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = character
		player.Character = character
		local profile = {
			Knives = {},
			Plates = {},
			Slots = 2,
			Discovered = {},
			TutorialDone = completed or false,
			TutorialStep = 2,
			KnivesStolen = 0,
			Cash = 0,
			Rebirths = 0,
			Luck = 0,
			Heat = 0,
			CasesOpened = 0,
			BestPull = "",
			LuckUntil = 0,
		}
		local queue, flow, notifications, effects = {}, {}, {}, {}
		local f = {
			Player = player,
			Profile = profile,
			Folder = folder,
			InBase = true,
			CashFlow = flow,
			Notifications = notifications,
			Effects = effects,
		}
		deps.task = {
			delay = function(_, fn)
				table.insert(queue, fn)
			end,
			spawn = noOp,
		}
		deps.GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
		deps.Items = require(game.ReplicatedStorage.Shared.Items)
		deps.Knives = require(game.ReplicatedStorage.Shared.Config.Knives)
		deps.Format = require(game.ReplicatedStorage.Shared.Format)
		deps.DataService = {
			Get = function()
				return profile
			end,
			Update = function(_, fn)
				fn(profile)
				player:SetAttribute("KnifeCount", #profile.Knives)
			end,
			AddKnife = function(p, item, plate)
				table.insert(p.Knives, item)
				table.insert(p.Plates, plate or #p.Knives)
				return plate or #p.Knives
			end,
			IndexOnPlate = function(p, plate)
				return table.find(p.Plates, plate)
			end,
			CashFlow = function(_, amount)
				table.insert(flow, amount)
			end,
			PlayerLoaded = { Connect = noOp },
		}
		local base = { SlotCFrames = { CFrame.new(), CFrame.new(2, 0, 0) } }
		deps.BaseService = {
			IsInOwnBase = function()
				return f.InBase
			end,
			GetBase = function()
				return base
			end,
			RefreshRack = noOp,
			RefreshWalkSpeed = noOp,
		}
		local function model()
			local m = Instance.new("Model")
			local p = Instance.new("Part")
			p.Name = "Blade"
			p.Parent = m
			m.PrimaryPart = p
			return m
		end
		deps.KnifeModel = { Build = model, FitItem = noOp }
		deps.Fuel = {
			AddHeat = noOp,
			AddMeter = noOp,
		}
		deps.Analytics = {
			Track = noOp,
			Milestone = noOp,
			Remote = function(_, fn)
				return fn
			end,
		}
		deps.MapService = { Zones = {} }
		deps.Offers = { Show = noOp }
		deps.Social = { PartnerOf = noOp }
		deps.ServerEvents = {
			Active = function()
				return false
			end,
			Progress = noOp,
			Start = noOp,
		}
		deps.Ragdoll = {}
		deps.Targets = {}
		deps.WorldSignModel = {}
		deps.ToyBlockModel = {}
		local serverEvent = {}
		function serverEvent:Connect(fn)
			self.Callback = fn
		end
		function serverEvent:Fire(...)
			self.Callback(...)
		end
		local remotes = {
			Tutorial = { OnServerEvent = serverEvent },
			Effect = {
				FireAllClients = noOp,
				FireClient = function(_, _, kind)
					table.insert(effects, kind)
				end,
			},
		}
		for _, name in { "ClaimIndex", "ClaimDaily", "ClaimFreeChest" } do
			remotes[name] = {}
		end
		deps.Net = {
			Remotes = remotes,
			Notify = function(_, text)
				table.insert(notifications, text)
			end,
			Announce = noOp,
			Animate = noOp,
		}
		deps.Remotes = deps.Net
		deps.StealService = {}
		deps.game = {
			GetService = function(_, name)
				return if name == "Players"
					then {
						GetPlayers = function()
							return {}
						end,
					}
					else game:GetService(name)
			end,
		}
		local map = Instance.new("Folder")
		map.Parent = folder
		deps.workspace = {
			FindFirstChild = function()
				return map
			end,
		}
		local source = game.ServerScriptService.Server.Services[moduleName].Source
		source = source:gsub("local (%w+) = require%(([^\n]+)%)", function(name)
			return "local " .. name .. " = deps." .. (if name == "Net" then "Net" else name)
		end)
		if moduleName == "Rewards" then
			-- World chest construction is outside the tutorial remote's contract.
			source = source:gsub("\n\tbuildChest%(folder%)", "\n\t-- isolated world artwork")
		end
		local module = Instance.new("ModuleScript")
		module.Parent = folder
		module.Source = "local deps = require(script.Parent.Environment)\nlocal game, task, workspace = deps.game, deps.task, deps.workspace\n"
			.. source
		f.Module = require(module)
		function f:Flush()
			local pending = queue
			queue = {}
			for _, fn in pending do
				fn()
			end
		end
		function f:Start(kind)
			self.Module.StartCarry(
				player,
				kind or "Knife",
				if kind == "Case" then "Common" else "RustyShank",
				nil,
				{ Zone = 1, Slot = 1 }
			)
		end
		function f:Request(step, at)
			serverEvent:Fire(player, step, at)
		end
		return f
	end
	local function case(name, moduleName, fn, completed)
		t.test(name, function()
			local f = fixture(moduleName, completed)
			local ok, err = pcall(fn, f)
			f.Folder:Destroy()
			if not ok then
				error(err, 0)
			end
		end)
	end

	-- Success records inventory and the resumable milestone, without paying completion cash.
	case("successful placement increments serial and saves step 3", "StealService", function(f)
		f:Start()
		f.Module.Place(f.Player, 1)
		f:Flush()
		t.expect.equal(#f.Profile.Knives, 1)
		t.expect.equal(f.Player:GetAttribute("KnifePlacementSerial"), 1)
		t.expect.equal(f.Player:GetAttribute("LastPlacedKnife"), f.Profile.Knives[1])
		t.expect.equal(f.Player:GetAttribute("LastPlacedKnifePlate"), f.Profile.Plates[1])
		t.expect.equal(f.Profile.TutorialStep, 3)
		t.expect.equal(f.Profile.Cash, 0)
		t.expect.equal(f.Profile.TutorialDone, false)
	end)
	-- Double-tapping Place cannot produce two successful deposits.
	case("power deposit shows its power without an income toast", "StealService", function(f)
		f.Module.StartCarry(f.Player, "Knife", "RustyShank|||SpamKnife", nil, { Zone = 1, Slot = 1 })
		f.Module.Place(f.Player, 1)
		f:Flush()
		t.expect.truthy(table.find(f.Effects, "PowerRoll"))
		for _, notification in f.Notifications do
			t.expect.equal(notification:find("/s", 1, true), nil)
		end
	end)
	case("duplicate placement increments once", "StealService", function(f)
		f:Start()
		f.Module.Place(f.Player, 1)
		f.Module.Place(f.Player, 1)
		f:Flush()
		t.expect.equal(#f.Profile.Knives, 1)
		t.expect.equal(f.Player:GetAttribute("KnifePlacementSerial"), 1)
	end)
	-- Existing completed saves keep their progress when another knife is placed.
	case("completed tutorial keeps its saved step", "StealService", function(f)
		f.Profile.TutorialStep = 6
		f.Player:SetAttribute("KnifePlacementSerial", 7)
		f:Start()
		f.Module.Place(f.Player, 1)
		f:Flush()
		t.expect.equal(f.Player:GetAttribute("KnifePlacementSerial"), 8)
		t.expect.equal(f.Profile.TutorialStep, 6)
	end, true)
	-- Invalid plate, occupied plate and outside-vault requests do not confirm placement.
	for _, reason in { "invalid", "occupied", "outside", "case", "dead" } do
		case("rejects " .. reason .. " placement", "StealService", function(f)
			f:Start(if reason == "case" then "Case" else "Knife")
			if reason == "occupied" then
				table.insert(f.Profile.Knives, "KitchenKnife")
				table.insert(f.Profile.Plates, 1)
			end
			if reason == "outside" then
				f.InBase = false
			end
			if reason == "dead" then
				f.Player.Character.Humanoid.Health = 0
			end
			f.Module.Place(f.Player, if reason == "invalid" then 0 else 1)
			f:Flush()
			t.expect.equal(f.Player:GetAttribute("KnifePlacementSerial"), nil)
			t.expect.equal(f.Player:GetAttribute("LastPlacedKnife"), nil)
			t.expect.equal(f.Player:GetAttribute("LastPlacedKnifePlate"), nil)
			t.expect.equal(f.Profile.TutorialStep, 2)
		end)
	end
	-- The vault can fill during the placement animation; that failure is not a deposit.
	case("vault filling before landing cannot confirm placement", "StealService", function(f)
		f:Start()
		f.Module.Place(f.Player, 1)
		f.Profile.Knives = { "KitchenKnife", "RustyShank" }
		f.Profile.Plates = { 1, 2 }
		f:Flush()
		t.expect.equal(f.Player:GetAttribute("KnifePlacementSerial"), nil)
		t.expect.equal(f.Profile.TutorialStep, 2)
	end)
	-- Being captured before the animation lands cannot confirm a pending placement.
	case("capture cancels pending placement", "StealService", function(f)
		f:Start()
		f.Module.Place(f.Player, 1)
		f.Module.ReturnToBoss(f.Player)
		f:Flush()
		t.expect.equal(#f.Profile.Knives, 0)
		t.expect.equal(f.Player:GetAttribute("KnifePlacementSerial"), nil)
	end)
	-- Cases add inventory but never count as manual carried-knife placement.
	case("opening a case never increments placement serial", "StealService", function(f)
		f.Module.OpenCase(f.Player, "Common")
		f:Flush()
		t.expect.equal(#f.Profile.Knives, 1)
		t.expect.equal(f.Player:GetAttribute("KnifePlacementSerial"), nil)
		t.expect.equal(f.Profile.TutorialStep, 2)
	end)
	-- Late client step 2 must not overwrite a committed placement milestone.
	case("saved steps cannot move backward", "Rewards", function(f)
		f.Module.Init()
		f.Profile.TutorialStep = 3
		f:Request("Step", 2)
		t.expect.equal(f.Profile.TutorialStep, 3)
		f:Request("Step", 5)
		f:Request("Step", 1)
		t.expect.equal(f.Profile.TutorialStep, 5)
	end)
	-- Completing twice pays exactly once, with the original configured amount.
	case("completion reward is paid once", "Rewards", function(f)
		f.Module.Init()
		f:Request("Done")
		f:Request("Done")
		t.expect.equal(f.Profile.Cash, require(game.ReplicatedStorage.Shared.Config.GameConfig).TutorialReward)
		t.expect.equal(#f.CashFlow, 1)
		t.expect.equal(f.Profile.TutorialDone, true)
	end)
	-- Skip retains its no-reward behavior; completed saves ignore further step messages.
	case("skip and completed step messages cannot grant rewards", "Rewards", function(f)
		f.Module.Init()
		f:Request("Skip")
		f:Request("Done")
		f:Request("Step", 6)
		t.expect.equal(f.Profile.Cash, 0)
		t.expect.equal(f.Profile.TutorialStep, 2)
	end)
end
