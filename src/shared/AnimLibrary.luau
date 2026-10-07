--!strict
-- Every custom animation in the game, as keyframes of joint offsets. Clients play them on top of
-- whatever Roblox's Animator is doing (walk, run, idle), so you can stab while running. Shared so
-- the server knows when a swing actually lands (Impact) and times damage to match.
--
-- Poses store angles in degrees (not CFrames) so blends go the long way round when asked to -
-- an arm cranked to 205 degrees swings over the top, not back down. Each is applied to the R15
-- joint's Transform:
--   Shoulders/elbows: +X raises forward (180 = straight up, beyond = behind the head),
--                     +Z swings the RIGHT arm outward (the left arm goes outward with -Z)
--   Waist/Neck:       +Y twists to the left, +X bends forward
--   RootMove:         studs to move the whole body (hops, crouches, lunges)

export type Pose = { [string]: Vector3 }
export type Key = { T: number, Pose: Pose, Ease: Enum.EasingStyle?, Dir: Enum.EasingDirection? }
export type Clip = {
	Length: number,
	Keys: { Key },
	Impact: number?, -- when the blade connects (server applies damage at this moment)
	Trail: { number }?, -- {from, to}: when the knife's motion trail is on
	Release: number?, -- throws: when the knife leaves the hand
}

local function R(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function T(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local OUT = Enum.EasingDirection.Out
local IN = Enum.EasingDirection.In
local INOUT = Enum.EasingDirection.InOut
local QUAD = Enum.EasingStyle.Quad
local BACK = Enum.EasingStyle.Back
local SINE = Enum.EasingStyle.Sine
local EXPO = Enum.EasingStyle.Exponential

-- The fully cranked-back throwing pose, shared by the charge and the start of the release
local CRANKED: Pose = {
	RightShoulder = R(205, -10, 35), -- up and back behind the head
	RightElbow = R(95, 0, 0), -- knife cocked behind the head
	RightWrist = R(-30, 0, 0),
	LeftShoulder = R(85, 0, -8), -- off-hand points at the target
	LeftElbow = R(5, 0, 0),
	Waist = R(-8, -42, 0), -- twisted right, leaning back
	Neck = R(4, 34, 0), -- head stays on the target
	RootMove = T(0, -0.25, 0),
}

local Clips: { [string]: Clip } = {
	-- Player / Murderer ---------------------------------------------------------------------

	-- Overhand stab: raise, drive down and forward, off-hand swings back for balance
	Stab = {
		Length = 0.46,
		Impact = 0.15,
		Trail = { 0.09, 0.24 },
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.1,
				Ease = QUAD,
				Dir = OUT,
				Pose = {
					RightShoulder = R(160, 0, -12),
					RightElbow = R(50, 0, 0),
					RightWrist = R(-20, 0, 0),
					Waist = R(-6, -20, 0),
					Neck = R(-4, 12, 0),
					LeftShoulder = R(20, 0, -10),
				},
			},
			{
				T = 0.17,
				Ease = EXPO,
				Dir = OUT,
				Pose = {
					RightShoulder = R(55, 0, 8),
					RightElbow = R(-4, 0, 0),
					RightWrist = R(25, 0, 0),
					Waist = R(12, 24, 0),
					Neck = R(-10, -14, 0),
					LeftShoulder = R(-35, 0, -12),
					LeftElbow = R(20, 0, 0),
					RootMove = T(0, -0.15, -0.3),
				},
			},
			{
				T = 0.27,
				Ease = SINE,
				Dir = OUT,
				Pose = {
					RightShoulder = R(50, 0, 8),
					RightElbow = R(5, 0, 0),
					Waist = R(9, 18, 0),
					LeftShoulder = R(-25, 0, -10),
				},
			},
			{ T = 0.46, Ease = QUAD, Dir = INOUT, Pose = {} },
		},
	},

	-- Wide horizontal slash from the right side across to the left
	Slash = {
		Length = 0.44,
		Impact = 0.16,
		Trail = { 0.08, 0.25 },
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.1,
				Ease = QUAD,
				Dir = OUT,
				Pose = {
					RightShoulder = R(95, 20, 75),
					RightElbow = R(40, 0, 0),
					RightWrist = R(0, 0, 30),
					Waist = R(0, -38, 0),
					Neck = R(0, 20, 0),
					LeftShoulder = R(40, 0, -30),
				},
			},
			{
				T = 0.19,
				Ease = EXPO,
				Dir = OUT,
				Pose = {
					RightShoulder = R(100, -10, -55),
					RightElbow = R(5, 0, 0),
					RightWrist = R(0, 0, -25),
					Waist = R(4, 40, 0),
					Neck = R(0, -18, 0),
					LeftShoulder = R(-20, 0, -25),
					RootMove = T(0, -0.1, -0.25),
				},
			},
			{
				T = 0.28,
				Ease = SINE,
				Dir = OUT,
				Pose = {
					RightShoulder = R(90, -10, -50),
					Waist = R(3, 32, 0),
				},
			},
			{ T = 0.44, Ease = QUAD, Dir = INOUT, Pose = {} },
		},
	},

	-- Hold to charge: sampled by charge fraction (0..1), not time
	Charge = {
		Length = 1,
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.3,
				Ease = SINE,
				Dir = OUT,
				Pose = {
					RightShoulder = R(140, -5, 25),
					RightElbow = R(60, 0, 0),
					LeftShoulder = R(55, 0, -8),
					Waist = R(-4, -22, 0),
					Neck = R(2, 18, 0),
				},
			},
			{ T = 1, Ease = QUAD, Dir = OUT, Pose = CRANKED },
		},
	},

	-- Letting go: whip forward past the target, follow through, recover
	Throw = {
		Length = 0.55,
		Release = 0.07,
		Trail = { 0, 0.16 },
		Keys = {
			{ T = 0, Pose = CRANKED },
			{
				T = 0.08,
				Ease = EXPO,
				Dir = OUT,
				Pose = {
					RightShoulder = R(70, 0, -15),
					RightElbow = R(-5, 0, 0),
					RightWrist = R(30, 0, 0),
					LeftShoulder = R(-30, 0, -15),
					LeftElbow = R(25, 0, 0),
					Waist = R(14, 38, 0),
					Neck = R(-8, -20, 0),
					RootMove = T(0, -0.3, -0.35),
				},
			},
			{
				T = 0.2,
				Ease = SINE,
				Dir = OUT,
				Pose = {
					RightShoulder = R(35, 0, -25),
					RightElbow = R(10, 0, 0),
					Waist = R(10, 30, 0),
					LeftShoulder = R(-20, 0, -10),
				},
			},
			{ T = 0.55, Ease = QUAD, Dir = INOUT, Pose = {} },
		},
	},

	-- Taking a hit: snap back, arms flinch up
	Hurt = {
		Length = 0.34,
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.06,
				Ease = EXPO,
				Dir = OUT,
				Pose = {
					Waist = R(-16, 0, 6),
					Neck = R(-22, 8, 0),
					RightShoulder = R(35, 0, 30),
					LeftShoulder = R(35, 0, -30),
					RootMove = T(0, 0, 0.35),
				},
			},
			{ T = 0.34, Ease = QUAD, Dir = OUT, Pose = {} },
		},
	},

	-- Knocked down in a raid: shoved off your feet, flat on your back seeing stars, then back up
	Knockdown = {
		Length = 2.2,
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.2,
				Ease = EXPO,
				Dir = OUT,
				Pose = {
					Root = R(-84, 0, 6),
					RootMove = T(0, -2.1, 0.8),
					Neck = R(18, 0, 0),
					RightShoulder = R(140, 0, 50),
					LeftShoulder = R(140, 0, -50),
					RightElbow = R(30, 0, 0),
					LeftElbow = R(30, 0, 0),
					RightHip = R(35, 0, 0),
					LeftHip = R(10, 0, 0),
					RightKnee = R(-30, 0, 0),
					LeftKnee = R(-10, 0, 0),
				},
			},
			{
				T = 0.34,
				Ease = QUAD,
				Dir = OUT,
				Pose = {
					Root = R(-90, 0, 4),
					RootMove = T(0, -2.3, 1),
					Neck = R(-6, 0, 0),
					RightShoulder = R(100, 0, 70),
					LeftShoulder = R(100, 0, -70),
					RightHip = R(20, 0, 0),
					LeftHip = R(5, 0, 0),
					RightKnee = R(-20, 0, 0),
					LeftKnee = R(-5, 0, 0),
				},
			},
			{
				T = 1.7,
				Ease = SINE,
				Dir = INOUT,
				Pose = {
					Root = R(-88, 0, -4),
					RootMove = T(0, -2.3, 1),
					Neck = R(-10, 20, 0),
					RightShoulder = R(95, 0, 75),
					LeftShoulder = R(95, 0, -75),
					RightHip = R(25, 0, 0),
					LeftHip = R(8, 0, 0),
					RightKnee = R(-25, 0, 0),
					LeftKnee = R(-8, 0, 0),
				},
			},
			{ T = 2.2, Ease = BACK, Dir = OUT, Pose = {} },
		},
	},

	-- Grabbing a knife off the floor
	Pickup = {
		Length = 0.5,
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.16,
				Ease = QUAD,
				Dir = OUT,
				Pose = {
					RootMove = T(0, -1.1, 0),
					Waist = R(42, 0, 0),
					Neck = R(15, 0, 0),
					RightShoulder = R(75, 0, 10),
					LeftShoulder = R(40, 0, -10),
					RightHip = R(55, 0, 0),
					LeftHip = R(55, 0, 0),
					RightKnee = R(-70, 0, 0),
					LeftKnee = R(-70, 0, 0),
				},
			},
			{
				T = 0.3,
				Ease = QUAD,
				Dir = IN,
				Pose = {
					RootMove = T(0, -0.3, 0),
					Waist = R(-5, 0, 0),
					RightShoulder = R(170, 0, -10),
					LeftShoulder = R(170, 0, 10),
				},
			},
			{ T = 0.5, Ease = SINE, Dir = OUT, Pose = {} },
		},
	},

	-- Knife made it home: arms up, little hops
	Cheer = {
		Length = 1.3,
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.15,
				Ease = BACK,
				Dir = OUT,
				Pose = {
					RightShoulder = R(175, 0, 25),
					LeftShoulder = R(175, 0, -25),
					Neck = R(-15, 0, 0),
					RootMove = T(0, 0.9, 0),
				},
			},
			{
				T = 0.35,
				Ease = SINE,
				Dir = INOUT,
				Pose = {
					RightShoulder = R(150, 0, 45),
					LeftShoulder = R(150, 0, -45),
					RightElbow = R(30, 0, 0),
					LeftElbow = R(30, 0, 0),
					RootMove = T(0, 0, 0),
				},
			},
			{
				T = 0.55,
				Ease = BACK,
				Dir = OUT,
				Pose = {
					RightShoulder = R(178, 0, 20),
					LeftShoulder = R(178, 0, -20),
					Neck = R(-15, 0, 0),
					RootMove = T(0, 0.9, 0),
				},
			},
			{
				T = 0.8,
				Ease = SINE,
				Dir = INOUT,
				Pose = {
					RightShoulder = R(150, 0, 45),
					LeftShoulder = R(150, 0, -45),
					RootMove = T(0, 0, 0),
				},
			},
			{ T = 1.3, Ease = QUAD, Dir = INOUT, Pose = {} },
		},
	},

	-- The Murderer gets the knife: flourish it up to the face and look at it
	Draw = {
		Length = 1.1,
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.25,
				Ease = BACK,
				Dir = OUT,
				Pose = {
					RightShoulder = R(110, 20, -35),
					RightElbow = R(95, 0, 0),
					RightWrist = R(0, 180, 0),
					Neck = R(-12, -25, 0),
					Waist = R(0, -10, 0),
				},
			},
			{
				T = 0.55,
				Ease = SINE,
				Dir = INOUT,
				Pose = {
					RightShoulder = R(115, 20, -35),
					RightElbow = R(100, 0, 0),
					RightWrist = R(0, 360, 0),
					Neck = R(-12, -25, 0),
					Waist = R(0, -10, 0),
				},
			},
			{ T = 1.1, Ease = QUAD, Dir = INOUT, Pose = {} },
		},
	},

	-- Revolver kick
	Recoil = {
		Length = 0.35,
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.04,
				Ease = EXPO,
				Dir = OUT,
				Pose = {
					RightShoulder = R(35, 0, 0),
					RightElbow = R(35, 0, 0),
					Waist = R(-6, 0, 0),
					Neck = R(-6, 0, 0),
				},
			},
			{ T = 0.35, Ease = QUAD, Dir = OUT, Pose = {} },
		},
	},

	-- Guards ----------------------------------------------------------------------------------

	-- Heavier, slower overhand stab with a lunge; damage lands at Impact
	GuardStab = {
		Length = 0.7,
		Impact = 0.3,
		Trail = { 0.2, 0.38 },
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.22,
				Ease = QUAD,
				Dir = OUT,
				Pose = {
					RightShoulder = R(175, 0, -10),
					RightElbow = R(60, 0, 0),
					Waist = R(-12, -18, 0),
					Neck = R(-8, 10, 0),
					LeftShoulder = R(60, 0, -20),
					RootMove = T(0, 0.2, 0.4),
				},
			},
			{
				T = 0.3,
				Ease = EXPO,
				Dir = OUT,
				Pose = {
					RightShoulder = R(40, 0, 10),
					RightElbow = R(-5, 0, 0),
					RightWrist = R(30, 0, 0),
					Waist = R(20, 22, 0),
					Neck = R(-12, -10, 0),
					LeftShoulder = R(-30, 0, -15),
					RootMove = T(0, -0.4, -1),
				},
			},
			{
				T = 0.45,
				Ease = SINE,
				Dir = OUT,
				Pose = {
					RightShoulder = R(40, 0, 10),
					Waist = R(16, 18, 0),
					RootMove = T(0, -0.3, -0.8),
				},
			},
			{ T = 0.7, Ease = QUAD, Dir = INOUT, Pose = {} },
		},
	},

	-- Spotting someone: feet planted, lantern raised (50% faster).
	Alert = {
		Length = 0.7 / 1.5,
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.12 / 1.5,
				Ease = BACK,
				Dir = OUT,
				Pose = {
					LeftShoulder = R(150, 0, -20),
					LeftElbow = R(30, 0, 0),
					RightShoulder = R(40, 0, 25),
					Neck = R(-18, 0, 0),
				},
			},
			{
				T = 0.35 / 1.5,
				Ease = QUAD,
				Dir = IN,
				Pose = {
					LeftShoulder = R(135, 0, -20),
					Neck = R(-8, 0, 0),
				},
			},
			{ T = 0.7 / 1.5, Ease = QUAD, Dir = OUT, Pose = {} },
		},
	},

	-- Getting hit: bigger stagger than a player's flinch
	GuardHurt = {
		Length = 0.45,
		Keys = {
			{ T = 0, Pose = {} },
			{
				T = 0.07,
				Ease = EXPO,
				Dir = OUT,
				Pose = {
					Waist = R(-22, 10, 8),
					Neck = R(-28, -10, 0),
					RightShoulder = R(50, 0, 40),
					LeftShoulder = R(60, 0, -45),
					RootMove = T(0, 0, 0.6),
				},
			},
			{ T = 0.45, Ease = QUAD, Dir = OUT, Pose = {} },
		},
	},
}

-- Poses held for as long as a state lasts (sampled every frame, not played once)
local Loops: { [string]: Pose } = {
	-- Carrying a knife over your head: both arms straight up, hands under the blade
	Carry = {
		RightShoulder = R(176, 0, 4),
		LeftShoulder = R(176, 0, -4),
		RightElbow = R(8, 0, 0),
		LeftElbow = R(8, 0, 0),
		Neck = R(-12, 0, 0),
		Waist = R(-4, 0, 0),
	},
	-- Holding the Revolver out at arm's length
	Aim = {
		RightShoulder = R(88, 0, 0),
		RightElbow = R(0, 0, 0),
		LeftShoulder = R(75, 0, -35),
		LeftElbow = R(40, 0, 0),
		Waist = R(0, 12, 0),
	},
}

local AnimLibrary = {
	Clips = Clips,
	Loops = Loops,
	Cranked = CRANKED,
	ChargeTime = 0.9, -- seconds to crank all the way back
}

local function lerpPose(a: Pose, b: Pose, alpha: number, out: Pose)
	for joint, va in a do
		out[joint] = va:Lerp(b[joint] or Vector3.zero, alpha)
	end
	for joint, vb in b do
		if not a[joint] then
			out[joint] = vb * alpha
		end
	end
end

-- Pose value -> the CFrame applied to a joint
function AnimLibrary.ToCFrame(angles: Vector3, move: Vector3?): CFrame
	local rotation = CFrame.Angles(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
	return if move then CFrame.new(move) * rotation else rotation
end

-- The pose of a clip at time t (seconds, or charge fraction for Charge)
function AnimLibrary.Sample(clip: Clip, t: number): Pose
	local keys = clip.Keys
	local pose: Pose = {}
	if t <= keys[1].T then
		lerpPose(keys[1].Pose, keys[1].Pose, 0, pose)
		return pose
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b.T then
			local alpha = (t - a.T) / math.max(b.T - a.T, 1e-4)
			alpha = game:GetService("TweenService"):GetValue(alpha, b.Ease or QUAD, b.Dir or INOUT)
			lerpPose(a.Pose, b.Pose, alpha, pose)
			return pose
		end
	end
	lerpPose(keys[#keys].Pose, keys[#keys].Pose, 0, pose)
	return pose
end

return AnimLibrary
