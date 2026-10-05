--!strict
-- Our own loading screen. Roblox's default one is dropped right away, and this covers the screen
-- until the game is actually playable: the server has built the world (the first players in a
-- new server wait a few seconds for the Blender meshes), our character has spawned and the HUD
-- exists. Without it you'd stare at the bare floor from the default camera. Then it fades out.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "Loading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()

local function new(className: string, props: { [string]: any }, parent: Instance): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

-- The same bright sky blue as the hub
local back = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1) }, gui)
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(Color3.fromRGB(30, 140, 235), Color3.fromRGB(120, 200, 250)),
}, back)

local function label(props: { [string]: any }): TextLabel
	local text = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
	}, back)
	for key, value in props do
		(text :: any)[key] = value
	end
	new("UIStroke", { Thickness = 4, Color = Color3.fromRGB(20, 40, 80), LineJoinMode = Enum.LineJoinMode.Round }, text)
	return text
end

local knife = label({ Position = UDim2.fromScale(0.5, 0.33), Size = UDim2.fromScale(0.16, 0.16), Text = "🔪" })
new("UIAspectRatioConstraint", {}, knife)
local title = label({ Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.7, 0.13), Text = "STEAL A KNIFE" })
local status = label({ Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.fromScale(0.5, 0.05), Text = "Loading" })
local tip = label({
	Position = UDim2.fromScale(0.5, 0.88),
	Size = UDim2.fromScale(0.8, 0.04),
	TextColor3 = Color3.fromRGB(230, 245, 255),
	Text = "",
})

local TIPS = {
	"Steal knives from the biome bosses and carry them home",
	"Every knife in your vault earns cash every second",
	"Train speed in the Haunted Wheel to outrun the deep bosses",
	"Team up with a friend: you're picked together in Double Trouble rounds",
	"Break into vaults to steal knives - but the owner can catch you!",
	"Fill the server goal together for a server-wide boost",
}
local firstTip = math.random(1, #TIPS)

local started = os.clock()
local animating = RunService.RenderStepped:Connect(function()
	local t = os.clock() - started
	knife.Rotation = math.sin(t * 3) * 18
	title.Size = UDim2.fromScale(0.7 * (1 + math.sin(t * 2) * 0.02), 0.13)
	status.Text = "Loading" .. string.rep(".", math.floor(t * 3) % 4)
	tip.Text = TIPS[(firstTip + math.floor(t / 3.5) - 1) % #TIPS + 1]
end)

-- Ready = the game has loaded, we have a character standing in the world and the HUD is up
local function ready(): boolean
	local character = player.Character
	return game:IsLoaded()
		and character ~= nil
		and character:FindFirstChild("HumanoidRootPart") ~= nil
		and playerGui:FindFirstChild("HUD") ~= nil
end
while not ready() and os.clock() - started < 45 do
	task.wait(0.1)
end
task.wait(0.4) -- let the camera settle on the character before revealing it
-- (client/Telemetry reports this: how long people stare at the loading screen; -1 = gave up waiting)
playerGui:SetAttribute("LoadedIn", if ready() then math.floor((os.clock() - started) * 10) / 10 else -1)

animating:Disconnect()
local fade = TweenInfo.new(0.5, Enum.EasingStyle.Quad)
TweenService:Create(back, fade, { BackgroundTransparency = 1 }):Play()
for _, d in back:GetDescendants() do
	if d:IsA("TextLabel") then
		TweenService:Create(d, fade, { TextTransparency = 1 }):Play()
	elseif d:IsA("UIStroke") then
		TweenService:Create(d, fade, { Transparency = 1 }):Play()
	end
end
task.wait(0.55)
gui:Destroy()
