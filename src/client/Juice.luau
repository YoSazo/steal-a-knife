--!strict
-- Feel (the toy-like polish every big Roblox sim has), for EVERY button and menu, in one place:
--   * press: any button squishes to 80% under your finger and springs back past full size with a
--     wobble when you let go (plus a little click, a bit higher or lower each time)
--   * hover (mouse): grows a touch
--   * a menu opening: the window pops from half size with a bounce, then its pieces (header, rows,
--     buttons) pop in one after another, quickly - and a "pop" sound; a lower pop when it closes
-- Purely decoration: taps still fire the moment they land (the button's own Activated), nothing waits
-- on an animation. Buttons that track your finger (the knife / throw sticks) are left alone, and so
-- are Roblox's own touch controls. JUICE = false switches it all off.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)

local Juice = {}

local JUICE = true
local PRESSED = 0.8 -- how far a held button squishes
local OVERSHOOT = 1.16 -- how far it springs past full size on release
local HOVER = 1.07
local SKIP_NAMES: { [string]: boolean } = { KnifeButton = true, ThrowButton = true }

local player = Players.LocalPlayer

type State = { Scale: UIScale, Base: number, Busy: Tween?, Held: boolean, Hover: boolean }
local states: { [GuiButton]: State } = setmetatable({}, { __mode = "k" }) :: any

-- Sounds ------------------------------------------------------------------------------------------

local function sound(id: string, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Parent = SoundService
	return s
end
local clickSound: Sound? = nil
local openSound: Sound? = nil
local closeSound: Sound? = nil

local function play(s: Sound?, speed: number, length: number?)
	if not s then
		return
	end
	s.PlaybackSpeed = speed
	s.TimePosition = 0
	s:Play()
	if length then
		-- (the pop file holds several pops: just the first one)
		task.delay(length, function()
			if s.TimePosition >= length * speed * 0.9 then
				s:Stop()
			end
		end)
	end
end

-- Buttons -----------------------------------------------------------------------------------------

local function tween(state: State, target: number, seconds: number, style: Enum.EasingStyle): Tween
	if state.Busy then
		state.Busy:Cancel()
	end
	local t = TweenService:Create(state.Scale, TweenInfo.new(seconds, style, Enum.EasingDirection.Out), {
		Scale = state.Base * target,
	})
	state.Busy = t
	t:Play()
	return t
end

local function stateOf(button: GuiButton): State
	local state = states[button]
	if not state then
		local scale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Parent = button
		state = { Scale = scale, Base = scale.Scale, Busy = nil, Held = false, Hover = false }
		states[button] = state
	end
	-- (the scale may belong to something else too: take its resting value while idle)
	if not state.Busy and not state.Held and not state.Hover then
		state.Base = state.Scale.Scale
	end
	return state
end

local function press(button: GuiButton)
	local state = stateOf(button)
	state.Held = true
	tween(state, PRESSED, 0.07, Enum.EasingStyle.Quad)
	play(clickSound, 0.95 + math.random() * 0.25)
end

local function release(button: GuiButton)
	local state = states[button]
	if not state or not state.Held then
		return
	end
	state.Held = false
	local up = tween(state, OVERSHOOT, 0.08, Enum.EasingStyle.Quad)
	up.Completed:Connect(function(status)
		if status == Enum.PlaybackState.Completed and not state.Held then
			local settle = tween(state, if state.Hover then HOVER else 1, 0.32, Enum.EasingStyle.Back)
			settle.Completed:Connect(function(done)
				if done == Enum.PlaybackState.Completed and state.Busy == settle then
					state.Busy = nil
				end
			end)
		end
	end)
end

local function hover(button: GuiButton, on: boolean)
	local state = stateOf(button)
	state.Hover = on
	if state.Held then
		return
	end
	local t = tween(state, if on then HOVER else 1, 0.12, Enum.EasingStyle.Quad)
	t.Completed:Connect(function(done)
		if done == Enum.PlaybackState.Completed and state.Busy == t then
			state.Busy = nil
		end
	end)
end

local function skip(button: GuiButton): boolean
	if SKIP_NAMES[button.Name] or button:GetAttribute("NoJuice") then
		return true
	end
	local screen = button:FindFirstAncestorWhichIsA("ScreenGui")
	return screen ~= nil and screen.Name == "TouchGui" -- (Roblox's thumbstick and jump button)
end

-- Touches by when they started: only a touch that STARTS on a button presses it (the thumbstick
-- finger sliding across one used to squish it, and on touch screens there's no hover at all)
local touchStarted: { [InputObject]: number } = setmetatable({}, { __mode = "k" }) :: any
UserInputService.TouchStarted:Connect(function(input)
	touchStarted[input] = os.clock()
end)
local function freshTouch(input: InputObject): boolean
	local began = touchStarted[input]
	return began == nil or os.clock() - began < 0.15
end

local function hook(instance: Instance)
	if not instance:IsA("GuiButton") or skip(instance) then
		return
	end
	local button = instance :: GuiButton
	button.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or (kind == Enum.UserInputType.Touch and freshTouch(input)) then
			press(button)
		elseif kind == Enum.UserInputType.MouseMovement and not UserInputService.TouchEnabled then
			hover(button, true)
		end
	end)
	button.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			release(button)
		elseif kind == Enum.UserInputType.MouseMovement and not UserInputService.TouchEnabled then
			hover(button, false)
			release(button)
		end
	end)
	-- a gamepad / keyboard press
	button.Activated:Connect(function(input)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			press(button)
			task.delay(0.07, release, button)
		end
	end)
end

-- Menus -------------------------------------------------------------------------------------------

local running: { Tween } = {}
local resting: { [UIScale]: number } = {}

local function settleAll()
	for _, t in running do
		t:Cancel()
	end
	table.clear(running)
	for scale, value in resting do
		if scale.Parent then
			scale.Scale = value
		end
	end
	table.clear(resting)
end

local function popIn(object: GuiObject, delay: number, from: number, seconds: number)
	local s: UIScale = object:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	if not s.Parent then
		s.Name = "JuicePop"
		s.Parent = object
	end
	local target = resting[s] or s.Scale
	resting[s] = target
	s.Scale = target * from
	local t = TweenService:Create(
		s,
		TweenInfo.new(seconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay),
		{ Scale = target }
	)
	table.insert(running, t)
	t:Play()
end

-- The pieces that build in: the window's own parts, then the rows of every list in it (only the
-- ones you can see, top to bottom, at most 14)
local function pieces(menu: GuiObject): { GuiObject }
	local list = {}
	local function consider(object: Instance)
		if object:IsA("GuiObject") and object.Visible and object.AbsoluteSize.X > 4 and object.AbsoluteSize.Y > 4 then
			table.insert(list, object)
		end
	end
	for _, child in menu:GetChildren() do
		consider(child)
	end
	for _, d in menu:GetDescendants() do
		if d:IsA("ScrollingFrame") and d.Visible then
			local top, bottom = d.AbsolutePosition.Y, d.AbsolutePosition.Y + d.AbsoluteSize.Y
			for _, row in d:GetChildren() do
				if
					row:IsA("GuiObject")
					and row.Visible
					and row.AbsolutePosition.Y < bottom
					and row.AbsolutePosition.Y + row.AbsoluteSize.Y > top
				then
					consider(row)
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if math.abs(a.AbsolutePosition.Y - b.AbsolutePosition.Y) > 4 then
			return a.AbsolutePosition.Y < b.AbsolutePosition.Y
		end
		return a.AbsolutePosition.X < b.AbsolutePosition.X
	end)
	while #list > 14 do
		table.remove(list)
	end
	return list
end

local function open(menu: GuiObject)
	settleAll()
	play(openSound, 1.2, 0.18)
	-- (deferred: after the menu has sized itself to the screen)
	task.defer(function()
		if not menu.Visible then
			return
		end
		-- the window: half size -> a bouncy overshoot -> settled
		popIn(menu, 0, 0.5, 0.38)
		-- then everything in it, one after another
		for i, piece in pieces(menu) do
			popIn(piece, 0.05 + (i - 1) * 0.025, 0.3, 0.3)
		end
	end)
end

-- Closing: the opening in reverse. Menus hide instantly all over the code, so a snapshot of the menu
-- takes its place for a moment and shrinks away with a little wind-up (Back, In), then it's gone.
local function close(menu: GuiObject)
	local parent = menu.Parent
	if not parent then
		return
	end
	local ghost = menu:Clone()
	ghost.Name = "ClosingGhost"
	for _, d in ghost:GetDescendants() do
		if d:IsA("GuiObject") then
			d.Active = false
		end
		if d:IsA("GuiButton") then
			d.AutoButtonColor = false
			d.Interactable = false
		end
	end
	local scale: UIScale = ghost:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = ghost
	local menuScale = menu:FindFirstChildOfClass("UIScale")
	scale.Scale = resting[menuScale :: UIScale] or (if menuScale then menuScale.Scale else 1)
	ghost.Visible = true
	ghost.Parent = parent
	local shrink = TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Scale = 0,
	})
	shrink.Completed:Connect(function()
		ghost:Destroy()
	end)
	shrink:Play()
end

function Juice.Init()
	if not JUICE then
		return
	end
	clickSound = sound(Sounds.ReelTick, 0.35)
	openSound = sound(Sounds.MenuPop, 0.6)
	closeSound = sound(Sounds.MenuPop, 0.45)
	local playerGui = player:WaitForChild("PlayerGui")
	for _, d in playerGui:GetDescendants() do
		hook(d)
	end
	playerGui.DescendantAdded:Connect(hook)
	local last: GuiObject? = nil
	Ui.Menu.Changed:Connect(function(active: GuiObject?)
		if last and last ~= active then
			close(last) -- (switching menus: the old one shrinks away while the new one pops in)
		end
		if active and active ~= last then
			open(active)
		elseif not active and last then
			settleAll()
			play(closeSound, 0.85, 0.2)
		end
		last = active
	end)
end

return Juice
