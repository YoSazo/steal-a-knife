--!strict
-- Pens (Shared/PenMode): carrying a coffin / knife into your own pen, you TAP (or click) where it
-- goes - Steal an Egg's "hold the egg, tap the ground". A glowing ring follows your mouse over your
-- pen's grass (on a phone it shows where you last touched); the tap sends Remotes.PlaceAt and the
-- server checks it's really inside your pen (StealService.PlaceAt). Active while the server says
-- PlaceReady (you're carrying, standing in your pen, with room).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local TopLine = require(script.Parent.TopLine)

local player = Players.LocalPlayer
local PlaceTap = {}

-- A knife fresh out of its coffin, in your hand (BaseService.HoldHatched)
local function holdingHatched(): boolean
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool:GetAttribute("HatchPlate") ~= nil
end

local function ready(): boolean
	return (player:GetAttribute("PlaceReady") == true and player:GetAttribute("Carrying") ~= nil) or holdingHatched()
end

-- Your own pen's grass
local function floor(): BasePart?
	local map = workspace:FindFirstChild("Map")
	local bases = map and map:FindFirstChild("Bases")
	local base = bases and bases:FindFirstChild(`Base{player:GetAttribute("VaultIndex")}`)
	return base and base:FindFirstChild("Floor") :: BasePart?
end

-- Where a screen point lands on your pen's grass (nil = not on it)
local function hit(screen: Vector2): Vector3?
	local grass = floor()
	if not grass then
		return nil
	end
	local ray = workspace.CurrentCamera:ViewportPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { grass }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 600, params)
	return result and result.Position
end

function PlaceTap.Init()
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local ring = Instance.new("Part")
	ring.Name = "PlaceGhost"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 6, 6)
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(120, 255, 140)
	ring.Transparency = 1
	ring.Anchored = true
	ring.CanCollide, ring.CanQuery, ring.CanTouch = false, false, false
	ring.CastShadow = false
	ring.Parent = workspace

	local lastSent = 0
	local function place(at: Vector3)
		if os.clock() - lastSent < 0.4 then
			return
		end
		lastSent = os.clock()
		Remotes:WaitForChild("PlaceAt"):FireServer(at)
	end

	-- (holding a hatched knife: say what to do with it)
	local hinted = false
	RunService.RenderStepped:Connect(function()
		local holding = holdingHatched()
		if holding and not hinted then
			TopLine.Show("🏠 Tap your pen to put your new knife down!", 4, "PlaceHatched")
		end
		hinted = holding
		if not ready() then
			ring.Transparency = 1
			return
		end
		-- (a mouse: the ring follows it; a phone: it stays where you last touched)
		if UserInputService.MouseEnabled then
			local at = hit(UserInputService:GetMouseLocation())
			if at then
				ring.CFrame = CFrame.new(at + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
				ring.Transparency = 0.35 + math.sin(os.clock() * 6) * 0.15
				return
			end
		end
		ring.Transparency = if UserInputService.MouseEnabled then 1 else ring.Transparency
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not ready() then
			return
		end
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		local screen = if kind == Enum.UserInputType.Touch
			then Vector2.new(input.Position.X, input.Position.Y)
			else UserInputService:GetMouseLocation()
		-- (touch positions don't include the top bar inset; the mouse location does)
		if kind == Enum.UserInputType.Touch then
			local inset = game:GetService("GuiService"):GetGuiInset()
			screen += inset
		end
		local at = hit(screen)
		if at then
			ring.CFrame = CFrame.new(at + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
			ring.Transparency = 0.2
			place(at)
		end
	end)
end

return PlaceTap
