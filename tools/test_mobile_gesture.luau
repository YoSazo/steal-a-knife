--!strict
-- Run this module in Studio with the client KnifeGesture and KnifeAim modules.
return function(Gesture: any, Aim: any): number
	local checks = 0
	local function check(value: boolean, message: string)
		assert(value, message)
		checks += 1
	end
	local finger, movement, jump = {}, {}, {}
	check(Aim.ButtonSize == 160, "Large rendered thumb target")
	local state = Gesture.new()
	check(Gesture.release(state, finger, 1, false) == nil, "World release cannot attack")
	check(Gesture.press(state, finger, 0), "Knife accepts its initial finger")
	check(not Gesture.press(state, jump, 0.01), "Second finger cannot take ownership")
	check(
		Gesture.release(state, movement, 0.1, false) == nil and state.owner == finger,
		"Movement release retains attack"
	)
	check(Gesture.release(state, finger, 0.19, false) == "swing", "Quick tap swings once")
	check(Gesture.release(state, finger, 0.19, false) == nil, "Duplicate release cannot swing")
	Gesture.press(state, finger, 0)
	check(Gesture.tick(state, 0.199, true, false) == nil, "No swing or charge before threshold")
	check(Gesture.tick(state, 0.2, true, false) == "charge", "Hold charges at threshold")
	check(Gesture.tick(state, 5, true, false) == nil, "Full charge does not auto-fire")
	check(Gesture.release(state, jump, 5, false) == nil and state.owner == finger, "Jump release cannot throw")
	check(Gesture.release(state, finger, 5, false) == "throw", "Owner release throws once")
	Gesture.press(state, finger, 0)
	check(Gesture.tick(state, 0.3, false, false) == "cooldown", "Cooldown hold blocks charge")
	check(Gesture.tick(state, 2, true, false) == nil, "Blocked hold does not retry after cooldown")
	check(Gesture.release(state, finger, 2, false) == nil, "Blocked hold neither throws nor stabs")
	Gesture.press(state, finger, 0)
	check(Gesture.release(state, finger, 0.1, false) == "swing", "Tap still stabs during throw cooldown")
	Gesture.press(state, finger, 0)
	Gesture.tick(state, 0.3, true, false)
	Gesture.cancel(state)
	check(Gesture.release(state, finger, 1, false) == nil and state.owner == nil, "Cancel never attacks")
	Gesture.press(state, finger, 0)
	check(Gesture.release(state, finger, 0.1, true) == "spam", "Spam tap throws without melee")
	Gesture.press(state, finger, 0)
	check(Gesture.tick(state, 0.2, true, true) == "spam", "Spam hold starts cadence")
	check(Gesture.tick(state, 0.25, true, true) == nil, "Spam cadence cannot run early")
	check(Gesture.tick(state, 0.31, true, true) == "spam", "Spam hold repeats at allowed cadence")
	check(Gesture.release(state, finger, 0.32, true) == nil, "Spam release does not add a throw")
	check(Aim.Axis(Vector2.zero, Vector2.zero) == Vector2.zero, "Neutral joystick")
	check(math.abs(Aim.Axis(Vector2.new(500, 500), Vector2.zero).Magnitude - 1) < 0.0001, "Joystick clamps far drags")
	local focus = Vector3.new(10, 5, 20)
	local camera = CFrame.lookAt(focus + Vector3.new(0, 0, 12), focus)
	check(Aim.Rotate(camera, focus, Vector2.zero, 1) == camera, "Stationary finger preserves camera")
	local rotated = Aim.Rotate(camera, focus, Vector2.new(12, -12), 1)
	check(math.abs((rotated.Position - focus).Magnitude - 12) < 0.0001, "Aim preserves third-person distance")
	for _ = 1, 100 do
		rotated = Aim.Rotate(rotated, focus, Vector2.new(0, -12), 1)
	end
	check(math.asin(rotated.LookVector.Y) <= math.rad(80) + 0.0001, "Aim respects pitch limit")
	local firstPerson = CFrame.new(focus)
	check(Aim.Rotate(firstPerson, focus, Vector2.xAxis, 1).Position == focus, "First-person aim preserves position")
	local delta = Aim.RotationDelta(camera, Vector2.new(90, 20), 1)
	check(math.abs(delta.X - math.rad(90)) < 0.0001, "Native horizontal touch sensitivity")
	check(math.abs(delta.Y - math.rad(20 * 0.66)) < 0.0001, "Native vertical touch sensitivity")
	check(Aim.RotationDelta(camera, Vector2.new(0, 20), -1).Y == -delta.Y, "Honor camera Y inversion")
	check(
		math.abs(Aim.RotationDelta(camera, Vector2.new(0.25, 0), 1).X - math.rad(0.25)) < 0.0001,
		"No aiming deadzone"
	)
	local oneFrame = Aim.Rotate(camera, focus, Vector2.new(100, 0), 1)
	local tenFrames = camera
	for _ = 1, 10 do
		tenFrames = Aim.Rotate(tenFrames, focus, Vector2.new(10, 0), 1)
	end
	check(
		(oneFrame.LookVector - tenFrames.LookVector).Magnitude < 0.0001,
		"Sensitivity independent of event/frame rate"
	)
	local upward = CFrame.fromOrientation(math.rad(60), 0, 0)
	check(Aim.RotationDelta(upward, Vector2.new(0, -10), 1).Y > math.rad(-6.6), "Native pitch taper away from horizon")
	check(
		math.abs(Aim.RotationDelta(upward, Vector2.new(0, 10), 1).Y - math.rad(6.6)) < 0.0001,
		"Full pitch sensitivity toward horizon"
	)
	return checks
end
