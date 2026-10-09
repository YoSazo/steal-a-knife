--!strict
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Lod = require(script.Parent.Lod)
local Menu = {}
local entries: { [GuiObject]: boolean } = {}
local active: GuiObject? = nil
local savedFocus: GuiObject? = nil
local backpack = true
local touchControls = GuiService.TouchControlsEnabled
local gui: ScreenGui
local backdrop: GuiObject
local transitioning = false
local changed = Instance.new("BindableEvent")
Menu.Changed = changed.Event
local blur = Instance.new("BlurEffect")
blur.Name = "MenuBlur"
blur.Size = 8
blur.Enabled = false
blur.Parent = Lighting

function Menu.CanBlur(): boolean
	local level = UserSettings().GameSettings.SavedQualityLevel.Value
	return level > 6 or (level == 0 and Lod.Profile == "High")
end

local function refresh()
	if transitioning then
		return
	end
	local nextActive: GuiObject? = nil
	for frame in entries do
		if frame.Parent and frame.Visible then
			nextActive = frame
			break
		end
	end
	local wasOpen = active ~= nil
	active = nextActive
	local open = active ~= nil
	if open and not wasOpen then
		savedFocus = GuiService.SelectedObject
		touchControls = GuiService.TouchControlsEnabled
		pcall(function()
			backpack = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
		end)
	elseif wasOpen and not open then
		GuiService.SelectedObject = nil
		if savedFocus and savedFocus.Parent and savedFocus.Visible then
			GuiService.SelectedObject = savedFocus
		end
		savedFocus = nil
	end
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, if open then false else backpack)
	end)
	GuiService.TouchControlsEnabled = if open then false else touchControls
	gui:SetAttribute("MenuOpen", open)
	gui:SetAttribute("ActiveMenu", if active then active.Name else nil)
	backdrop.Visible = open
	blur.Enabled = open and gui:GetAttribute("MenuBlurEnabled") == true and Menu.CanBlur()
	if active and UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		local close = active:FindFirstChild("Close", true)
		if close and close:IsA("GuiObject") then
			GuiService.SelectedObject = close
		end
	end
	changed:Fire(active)
end
-- A menu soaks up touches on its own background and panels, so a finger on it never also drives
-- the thumbstick or turns the camera behind it. NEVER anything inside a button (a label or icon on
-- top of a button that sinks the touch means the button never hears the tap - every menu button
-- was dead on phones) or inside a scrolling list (rows that sink touches stop the list scrolling).
local function sink(instance: Instance)
	if
		instance:IsA("GuiObject")
		and not instance:IsA("GuiButton")
		and not instance:IsA("ScrollingFrame")
		and not instance:FindFirstAncestorWhichIsA("GuiButton")
		and not instance:FindFirstAncestorWhichIsA("ScrollingFrame")
	then
		instance.Active = true
	end
end

function Menu.Register(frame: GuiObject)
	if entries[frame] then
		return
	end
	entries[frame] = true
	sink(frame)
	for _, d in frame:GetDescendants() do
		sink(d)
	end
	frame.DescendantAdded:Connect(sink)
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible and not transitioning then
			transitioning = true
			for other in entries do
				if other ~= frame then
					other.Visible = false
				end
			end
			transitioning = false
		end
		refresh()
	end)
	frame.Destroying:Connect(function()
		entries[frame] = nil
		refresh()
	end)
	if frame.Visible then
		transitioning = true
		for other in entries do
			if other ~= frame then
				other.Visible = false
			end
		end
		transitioning = false
	end
	refresh()
end
function Menu.Open(frame: GuiObject)
	frame.Visible = true
end
function Menu.Close()
	transitioning = true
	for frame in entries do
		frame.Visible = false
	end
	transitioning = false
	refresh()
end
function Menu.Toggle(frame: GuiObject)
	frame.Visible = not frame.Visible
end
function Menu.IsOpen(): boolean
	return active ~= nil
end
function Menu.Current(): GuiObject?
	return active
end
function Menu.Init(screen: ScreenGui, overlay: GuiObject)
	gui, backdrop = screen, overlay
	gui:SetAttribute("MenuBlurEnabled", false)
	gui:GetAttributeChangedSignal("MenuBlurEnabled"):Connect(refresh)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then
			Menu.Close()
		end
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("InRound"):Connect(function()
		if Players.LocalPlayer:GetAttribute("InRound") then
			Menu.Close()
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(Menu.Close)
	UserSettings().GameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
		task.defer(refresh)
	end)
end
return Menu
