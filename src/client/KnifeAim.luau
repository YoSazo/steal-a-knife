--!strict
-- Joystick visuals with native touch-pan sensitivity (Roblox CameraInput).
-- Camera motion follows finger movement, never a fixed time-based turn rate.
local Aim = {}
Aim.ButtonSize = 160
function Aim.Axis(pointer: Vector2, origin: Vector2): Vector2
	local offset = (pointer - origin) / 48
	return if offset.Magnitude > 1 then offset.Unit else offset
end
function Aim.RotationDelta(camera: CFrame, pixels: Vector2, invertY: number?): Vector2
	local pitch = math.asin(math.clamp(camera.LookVector.Y, -1, 1))
	local vertical = 1
	if pixels.Y * pitch < 0 then
		vertical = (1 - (2 * math.abs(pitch) / math.pi) ^ 0.75) * 0.75 + 0.25
	end
	return Vector2.new(math.rad(pixels.X), math.rad(pixels.Y * 0.66) * vertical * (invertY or 1))
end
function Aim.Rotate(camera: CFrame, focus: Vector3, pixels: Vector2, invertY: number?): CFrame
	if pixels == Vector2.zero then
		return camera
	end
	local distance = (camera.Position - focus).Magnitude
	local delta = Aim.RotationDelta(camera, pixels, invertY)
	local look = camera.LookVector
	local yaw = math.atan2(-look.X, -look.Z) - delta.X
	local pitch = math.clamp(math.asin(look.Y) - delta.Y, math.rad(-80), math.rad(80))
	local rotation = CFrame.fromOrientation(pitch, yaw, 0)
	local position = if distance < 1 then camera.Position else focus - rotation.LookVector * distance
	return CFrame.new(position) * rotation
end
return Aim
