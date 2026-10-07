--!strict
-- ClickDetectors stop answering while a Tool is equipped. Route the same owned signs through
-- their existing purchase/sell handlers. Touch buys only on a short, still finger release.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Ui = require(script.Parent.Ui)
local WorldSignTarget = require(ReplicatedStorage.Shared.WorldSignTarget)
local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

export type Target = WorldSignTarget.Target
local WorldSignInput = {}
local initialized = false
local lastTap = -math.huge

WorldSignInput.Resolve = WorldSignTarget.Resolve

-- InputObject.Position and GetMouseLocation are raw viewport pixels, including the top inset.
-- Use one coordinate space for mouse and touch, so a tap hits the visible sign instead of below it.
function WorldSignInput.Target(at: Vector2): Target?
	if Ui.menuOpen() or player:GetAttribute("InRound") then
		return nil
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local camera = workspace.CurrentCamera
	if not root or not humanoid or humanoid.Health <= 0 or not camera then
		return nil
	end
	local ray = camera:ViewportPointToRay(at.X, at.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character :: Instance }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	return WorldSignInput.Resolve(hit and hit.Instance, root.Position, player.UserId)
end

local function heldTool(): boolean
	return player.Character ~= nil and player.Character:FindFirstChildOfClass("Tool") ~= nil
end

function WorldSignInput.Tap(target: Target)
	if os.clock() - lastTap < 0.3 then
		return
	end
	lastTap = os.clock()
	if target.Action == "Sell" then
		(Remotes:WaitForChild("SellSign") :: RemoteEvent):FireServer(target.Part)
	elseif target.Action == "RobuxWheel" then
		if Ui.Buy then
			Ui.Buy("Product", "SpeedUpgrade")
		end
	else
		task.spawn(function()
			-- The server calculates cost/limits and sends the normal purchase reply.
			pcall(function()
				(Remotes:WaitForChild("Purchase") :: RemoteFunction):InvokeServer(target.Action)
			end)
		end)
	end
end

function WorldSignInput.Init()
	if initialized then
		return
	end
	initialized = true
	local touches: { [InputObject]: { At: number, From: Vector2, Travel: number, Target: Target } } = {}
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not heldTool() then
			return -- no Tool: Roblox's native ClickDetector already handles this
		end
		local touch = input.UserInputType == Enum.UserInputType.Touch
		if not touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local at = if touch
			then Vector2.new(input.Position.X, input.Position.Y)
			else UserInputService:GetMouseLocation()
		local target = WorldSignInput.Target(at)
		if not target then
			return
		end
		if touch then
			touches[input] = { At = os.clock(), From = at, Travel = 0, Target = target }
		else
			WorldSignInput.Tap(target)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local start = touches[input]
		if start then
			local at = Vector2.new(input.Position.X, input.Position.Y)
			start.Travel = math.max(start.Travel, (at - start.From).Magnitude)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local start = touches[input]
		touches[input] = nil
		if not start or not heldTool() or os.clock() - start.At > 0.45 then
			return
		end
		local at = Vector2.new(input.Position.X, input.Position.Y)
		if math.max(start.Travel, (at - start.From).Magnitude) > 12 then
			return -- camera pan/hold: never buy something as a side effect
		end
		local target = WorldSignInput.Target(at)
		if target and target.Part == start.Target.Part then
			WorldSignInput.Tap(target)
		end
	end)
end

return WorldSignInput
