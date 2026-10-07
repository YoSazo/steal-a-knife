--!strict
-- Where a knife character hopping around its pen is at any moment (Steal an Egg's creatures just
-- wander; ours pogo-hop on their handle). Pure maths from (seed, server time), so every client draws
-- the same knife in the same spot without the server streaming positions, and the server can ask
-- the same question (e.g. for a steal prompt later).
--   hop k: from spot(k-1) to spot(k), in the air for Air s, then a pause; spots are random points in
--   the pen (from the seed), each at most MaxHop from the last. Bigger knives hop slower and longer.
local PenHop = {}

export type Pen = { Centre: Vector3, Half: Vector2 } -- the pen floor's centre (top surface) and half size
export type Hopper = { Seed: number, Scale: number }

local MARGIN = 3 -- keep clear of the fence

local function timing(scale: number): (number, number, number)
	local air = 0.42 + scale * 0.06 -- (a Cosmic stomps: long, heavy hops)
	local pause = 0.6 + scale * 0.12
	local height = 1.2 + scale * 0.45
	return air, pause, height
end

-- A wander goal somewhere in the pen; it changes every HOPS_PER_GOAL hops
local HOPS_PER_GOAL = 7
local function goal(pen: Pen, hopper: Hopper, g: number): Vector2
	local rng = Random.new(hopper.Seed * 7919 + g)
	local margin = MARGIN + hopper.Scale * 0.6
	local hx, hz = math.max(1, pen.Half.X - margin), math.max(1, pen.Half.Y - margin)
	return Vector2.new(rng:NextNumber(-hx, hx), rng:NextNumber(-hz, hz))
end

-- The k-th resting spot (pen-local X/Z): a few hops along the way from one goal to the next, with a
-- little wobble, so it wanders the pen in short hops (never a teleport-length leap)
local function spot(pen: Pen, hopper: Hopper, k: number): Vector2
	local g = math.floor(k / HOPS_PER_GOAL)
	local along = (k - g * HOPS_PER_GOAL) / HOPS_PER_GOAL
	local base = goal(pen, hopper, g):Lerp(goal(pen, hopper, g + 1), along)
	local rng = Random.new(hopper.Seed * 104729 + k)
	local wobble = 0.6 + hopper.Scale * 0.25
	local margin = MARGIN + hopper.Scale * 0.6
	local hx, hz = math.max(1, pen.Half.X - margin), math.max(1, pen.Half.Y - margin)
	local p = base + Vector2.new(rng:NextNumber(-wobble, wobble), rng:NextNumber(-wobble, wobble))
	return Vector2.new(math.clamp(p.X, -hx, hx), math.clamp(p.Y, -hz, hz))
end

-- (world position of the knife's floor point, facing direction, 0..1 how far into the air phase)
function PenHop.At(pen: Pen, hopper: Hopper, now: number): (Vector3, Vector3, number)
	local air, pause, height = timing(hopper.Scale)
	local period = air + pause
	-- each knife starts its rhythm at its own offset, so they don't all hop together
	local t = now + (hopper.Seed % 97) * 0.173
	local k = math.floor(t / period)
	local into = t - k * period
	local from, to = spot(pen, hopper, k - 1), spot(pen, hopper, k)
	local dir = to - from
	local facing = if dir.Magnitude > 0.05 then Vector3.new(dir.X, 0, dir.Y).Unit else Vector3.new(0, 0, 1)
	if into >= air then
		return pen.Centre + Vector3.new(to.X, 0, to.Y), facing, 1
	end
	local p = into / air
	local at = from:Lerp(to, p)
	local lift = 4 * height * p * (1 - p) -- a parabola: up and back down
	return pen.Centre + Vector3.new(at.X, lift, at.Y), facing, p
end

return PenHop
