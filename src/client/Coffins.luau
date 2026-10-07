--!strict
-- Coffins on vault plates (server CoffinService, tag "Coffin", attribute OpensAt = server time):
-- a countdown over each one ("RARE COFFIN 0:42"), a rattle now and then (something's in there!),
-- the seam glow pulsing faster as it gets close, and the owner's "Open now" prompt -> Robux product
-- CoffinOpen (Remotes.CoffinTarget names the coffin first).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Format = require(ReplicatedStorage.Shared.Format)
local Knives = require(ReplicatedStorage.Shared.Config.Knives)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer
local Coffins = {}

type Tracked = { Model: Model, Label: TextLabel, Home: CFrame, NextRattle: number, Glow: { BasePart } }

function Coffins.Init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local tracked: { [Model]: Tracked } = {}

	local function add(model: Instance)
		if not model:IsA("Model") or tracked[model] then
			return
		end
		local body = model:WaitForChild("Body", 5) :: BasePart?
		if not body then
			return
		end
		local rarity = tostring(model:GetAttribute("Rarity") or "")
		local gui = Instance.new("BillboardGui")
		gui.Name = "CoffinTimer"
		gui.Size = UDim2.fromOffset(120, 44) -- (a fixed small size on screen, like Steal an Egg's "Egg 35s")
		gui.StudsOffsetWorldSpace = Vector3.new(0, body.Size.Y * 2.2 + 1.5, 0)
		gui.MaxDistance = 220
		gui.LightInfluence = 0
		gui.Adornee = body
		local title = Instance.new("TextLabel")
		title.Size = UDim2.fromScale(1, 0.45)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.FredokaOne
		title.TextScaled = true
		title.Text = `{string.upper(rarity)} COFFIN`
		title.TextColor3 = Knives.RarityColors[rarity] or Color3.new(1, 1, 1)
		title.Parent = gui
		local label = Instance.new("TextLabel")
		label.Position = UDim2.fromScale(0, 0.45)
		label.Size = UDim2.fromScale(1, 0.55)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = ""
		label.Parent = gui
		for _, text in { title, label } do
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2.5
			stroke.Color = Color3.fromRGB(20, 15, 30)
			stroke.Parent = text
		end
		gui.Parent = model
		local glow = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and (d:GetAttribute("Role") == "Glow" or d:GetAttribute("Role") == "Peek") then
				table.insert(glow, d)
			end
		end
		tracked[model] = {
			Model = model,
			Label = label,
			Home = model:GetPivot(),
			NextRattle = os.clock() + math.random() * 3,
			Glow = glow,
		}
	end
	for _, model in CollectionService:GetTagged("Coffin") do
		task.spawn(add, model)
	end
	CollectionService:GetInstanceAddedSignal("Coffin"):Connect(function(model)
		task.spawn(add, model)
	end)
	CollectionService:GetInstanceRemovedSignal("Coffin"):Connect(function(model)
		tracked[model :: Model] = nil
	end)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local serverNow = workspace:GetServerTimeNow()
		for model, info in tracked do
			if not model.Parent then
				tracked[model] = nil
				continue
			end
			local left = ((model:GetAttribute("OpensAt") or serverNow) :: number) - serverNow
			-- the murder rounds are its clock: "2 rounds left" (a Common counts down in seconds)
			local rounds = model:GetAttribute("RoundsLeft")
			if type(rounds) == "number" then
				info.Label.Text = if rounds <= 0
					then "Opening!"
					elseif rounds == 1 then "1 round left"
					else `{rounds} rounds left`
				left = if rounds <= 0 then 0 else 999 -- (the rattle speeds up when it's about to open)
			else
				info.Label.Text = if left > 0.5 then Format.Duration(left) else "Opening!"
			end
			-- the seam and the peeking eyes pulse, faster in the last 10 s
			local speed = if left < 10 then 10 else 3
			local pulse = 0.25 + 0.25 * math.sin(now * speed)
			for _, part in info.Glow do
				part.Transparency = pulse
			end
			-- a rattle every few seconds (all the time near the end): something wants out
			if now >= info.NextRattle then
				local strength = if left < 10 then 6 else 3
				local t = now - info.NextRattle
				if t < 0.45 then
					local shake = math.sin(t * 60) * (1 - t / 0.45)
					model:PivotTo(
						info.Home
							* CFrame.Angles(0, 0, math.rad(shake * strength))
							* CFrame.new(0, math.abs(shake) * 0.15, 0)
					)
				else
					model:PivotTo(info.Home)
					info.NextRattle = now + (if left < 10 then 0.6 else 2 + math.random() * 3)
				end
			end
		end
	end)

	-- "Open now" on your own coffin: buy it (Robux), for this coffin
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		local plate = prompt:GetAttribute("CoffinPlate")
		if who ~= player or type(plate) ~= "number" or prompt:GetAttribute("Owner") ~= player.UserId then
			return
		end
		Remotes:WaitForChild("CoffinTarget"):FireServer(plate)
		if Ui.Buy then
			Ui.Buy("Product", "CoffinOpen")
		end
	end)
end

return Coffins
