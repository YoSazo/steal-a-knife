--!strict
-- Client half of our analytics (server/Services/Analytics, docs/ANALYTICS.md). The server sees what
-- players DO; this reports what only the client knows: the device, how long loading took, which
-- menus get opened and for how long, every button tapped, store prompts and whether they bought,
-- and frame rate / ping. Sent through Remotes.Track; the server whitelists names and fields and
-- rate limits, so nothing here can be trusted for anything but analytics.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")

local Ui = require(script.Parent.Ui)
local Monetization =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Monetization"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local Telemetry = {}

-- The server only listens once our data has loaded (that's when the session starts): anything
-- earlier waits here and goes out in order
local trackRemote: RemoteEvent? = nil
type Queued = { Name: string, Props: { [string]: any } }
local waiting: { Queued }? = {}
function Telemetry.Track(name: string, props: { [string]: any }?)
	if waiting then
		table.insert(waiting, { Name = name, Props = props or {} })
		return
	end
	trackRemote = trackRemote or Remotes:FindFirstChild("Track") :: RemoteEvent?
	if trackRemote then
		trackRemote:FireServer(name, props or {})
	end
end
task.spawn(function()
	while not player:GetAttribute("DataLoaded") do
		player:GetAttributeChangedSignal("DataLoaded"):Wait()
	end
	task.wait(1) -- (the server opens the session on the same signal)
	local queued: { Queued } = waiting or {}
	waiting = nil
	for _, entry in queued do
		Telemetry.Track(entry.Name, entry.Props)
	end
end)

local function menuName(): string
	local active = Ui.gui and Ui.gui:GetAttribute("ActiveMenu")
	return if type(active) == "string" then active else "hud"
end

-- "Buy 3 for $1.2K" -> "Buy # for $#": the same button groups together however much it costs
local function clean(text: string): string
	text = text:gsub("%b<>", "")
	text = text:gsub("%$?%d[%d%.,]*%s?[KMBTQSONDkmbtqsond]?[a-z]?%f[%A]", "#")
	text = text:gsub("[\r\n]+", " ")
	return (text:sub(1, 40))
end

local GENERIC = { TextButton = true, ImageButton = true, Button = true, Frame = true }
local function buttonName(button: GuiButton): string
	local name = button.Name
	local label = if button:IsA("TextButton") and button.Text ~= "" then button.Text else nil
	if not label then
		local child = button:FindFirstChild("Label") or button:FindFirstChildWhichIsA("TextLabel", true)
		if child and child:IsA("TextLabel") and child.Text ~= "" then
			label = child.Text
		end
	end
	if GENERIC[name] then
		return clean(label or name)
	end
	return if label then `{name}: {clean(label)}` else name
end

-- Store prompts: what was offered, where from, and (below) whether they bought
local promptAt: { [string]: number } = {}
local lastOffer: { Key: string, At: number }? = nil
function Telemetry.OfferShown(key: string)
	lastOffer = { Key = key, At = os.clock() }
end
function Telemetry.Prompt(kind: string, key: string)
	local source = if lastOffer and lastOffer.Key == key and os.clock() - lastOffer.At < 30 then "offer" else "store"
	promptAt[key] = os.clock()
	Telemetry.Track("store.prompt", { kind = kind, key = key, source = source, menu = menuName() })
end

local function finished(kind: string, key: string?, bought: boolean)
	if not key then
		return
	end
	local since = promptAt[key]
	promptAt[key] = nil
	Telemetry.Track("store.result", {
		kind = kind,
		key = key,
		bought = bought,
		seconds = if since then math.floor((os.clock() - since) * 10) / 10 else nil,
	})
end

function Telemetry.Init()
	-- Script errors on this device (a bug on someone's phone was invisible before): each different
	-- error once a session, at most 10 (the server allow-lists it as error.client)
	local reported: { [string]: boolean } = {}
	local count = 0
	game:GetService("ScriptContext").Error:Connect(function(message: string, trace: string, source: Instance?)
		local where = if source then source.Name else "?"
		local line = (trace:match("[Ll]ine (%d+)") or message:match(":(%d+):") or "?") :: string
		local key = `{where}:{line}:{message:sub(1, 60)}`
		if reported[key] or count >= 10 then
			return
		end
		reported[key] = true
		count += 1
		Telemetry.Track("error.client", { script = where, line = line, message = message:gsub("^.-:%d+: ", "") })
	end)
	-- The device, once (the server keeps it on every later event)
	local camera = workspace.CurrentCamera
	local quality = UserSettings().GameSettings.SavedQualityLevel.Value
	Telemetry.Track("client.device", {
		touch = UserInputService.TouchEnabled,
		keyboard = UserInputService.KeyboardEnabled,
		mouse = UserInputService.MouseEnabled,
		gamepad = UserInputService.GamepadEnabled,
		vr = UserInputService.VREnabled,
		phone = Ui.Phone and camera ~= nil and math.min(camera.ViewportSize.X, camera.ViewportSize.Y) < 500,
		screen_w = if camera then math.floor(camera.ViewportSize.X) else nil,
		screen_h = if camera then math.floor(camera.ViewportSize.Y) else nil,
		quality = quality,
		locale = player.LocaleId,
	})

	-- Loading: how long until they could play (the loading screen marks it on PlayerGui)
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		local started = os.clock()
		while playerGui:GetAttribute("LoadedIn") == nil and os.clock() - started < 90 do
			task.wait(0.5)
		end
		Telemetry.Track("client.loaded", {
			seconds = playerGui:GetAttribute("LoadedIn") or -1,
			first_frame = math.floor(time() * 10) / 10,
		})
	end)

	-- Menus: which ones, and how long they stay open
	local openMenu: string? = nil
	local openedAt = 0
	Ui.gui:GetAttributeChangedSignal("ActiveMenu"):Connect(function()
		local now = os.clock()
		local active = Ui.gui:GetAttribute("ActiveMenu")
		local nextMenu = if type(active) == "string" then active else nil
		if nextMenu == openMenu then
			return
		end
		if openMenu then
			Telemetry.Track("ui.menu", { menu = openMenu, seconds = math.floor((now - openedAt) * 10) / 10 })
		end
		openMenu, openedAt = nextMenu, now
		if nextMenu then
			Telemetry.Track("ui.menu", { menu = nextMenu })
		end
	end)

	-- Every button anyone taps, anywhere (named by its label, numbers stripped)
	local lastClick = 0
	local function watch(instance: Instance)
		if instance:IsA("GuiButton") then
			local button = instance
			button.Activated:Connect(function()
				local now = os.clock()
				if now - lastClick < 0.35 then
					return
				end
				lastClick = now
				Telemetry.Track("ui.click", { button = buttonName(button), menu = menuName() })
			end)
		end
	end
	local playerGui = player:WaitForChild("PlayerGui")
	for _, d in playerGui:GetDescendants() do
		watch(d)
	end
	playerGui.DescendantAdded:Connect(watch)

	-- Purchases: did the prompt end in a buy?
	local productKey: { [number]: string } = {}
	for _, product in Monetization.Products do
		if product.Id > 0 then
			productKey[product.Id] = product.Key
		end
	end
	local passKey: { [number]: string } = {}
	for _, pass in Monetization.Passes do
		if pass.Id > 0 then
			passKey[pass.Id] = pass.Key
		end
	end
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, id: number, bought: boolean)
		if userId == player.UserId then
			finished("Product", productKey[id], bought)
		end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who: Player, id: number, bought: boolean)
		if who == player then
			finished("Pass", passKey[id], bought)
		end
	end)

	-- Frame rate and ping every two minutes (the worst second too: stutters lose players)
	task.spawn(function()
		local frames, worst = 0, math.huge
		local windowFrames, windowStart = 0, os.clock()
		RunService.RenderStepped:Connect(function()
			frames += 1
			windowFrames += 1
			local now = os.clock()
			if now - windowStart >= 1 then
				worst = math.min(worst, windowFrames / (now - windowStart))
				windowFrames, windowStart = 0, now
			end
		end)
		while true do
			local from = os.clock()
			frames, worst = 0, math.huge
			task.wait(120)
			Telemetry.Track("perf", {
				fps = math.floor(frames / (os.clock() - from)),
				fps_min = if worst < math.huge then math.floor(worst) else nil,
				ping = math.floor(player:GetNetworkPing() * 1000),
				memory = math.floor(Stats:GetTotalMemoryUsageMb()),
				quality = UserSettings().GameSettings.SavedQualityLevel.Value,
			})
		end
	end)
end

return Telemetry
