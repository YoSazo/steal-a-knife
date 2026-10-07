--!strict
-- Where a knife character hopping around its pen is at any moment (Steal an Egg's creatures just
-- wander; ours pogo-hop on their handle). Pure maths from (seed, server time), so every client draws
-- the same knife in the same spot without the server streaming positions, and the server can ask
-- the same question (e.g. for a steal prompt later).
--   hop k: from spot(k-1) to spot(k), in the air for Air s, then a pause; spots are random points in
--   the pen (from the seed), each at most MaxHop from the last. Big or small, they all hop alike.
--   With a Home (where its owner put it / where its coffin stood) it roams near that spot instead of
--   the whole pen, and with Since (server time) it sits right on Home until then and wanders off
--   from there - a knife fresh out of its coffin starts where the coffin was.
local PenHop = {}

export type Pen = { Centre: Vector3, Half: Vector2 } -- the pen floor's centre (top surface) and half size
export type Hopper = { Seed: number, Scale: number, Home: Vector2?, Since: number? } -- (Home: pen-local X/Z)

local MARGIN = 3 -- keep clear of the fence

-- (every knife hops with the same quick bounce, however big: a Colossal is as lively as a Common)
local function timing(_scale: number): (number, number, number)
	return 0.48, 0.72, 1.65 -- air time, pause, height
end

-- A wander goal somewhere in the pen; it changes every HOPS_PER_GOAL hops
local HOPS_PER_GOAL = 7
local function goal(pen: Pen, hopper: Hopper, g: number): Vector2
	local rng = Random.new(hopper.Seed * 7919 + g)
	local margin = MARGIN + hopper.Scale * 0.6
	local hx, hz = math.max(1, pen.Half.X - margin), math.max(1, pen.Half.Y - margin)
	local home = hopper.Home
	if home then
		-- (a little patch round its own spot: it stays "the one by the gate", "the one in the corner")
		local roam = 6 + hopper.Scale * 1.5
		local p = home + Vector2.new(rng:NextNumber(-roam, roam), rng:NextNumber(-roam, roam))
		return Vector2.new(math.clamp(p.X, -hx, hx), math.clamp(p.Y, -hz, hz))
	end
	return Vector2.new(rng:NextNumber(-hx, hx), rng:NextNumber(-hz, hz))
end

-- The k-th resting spot (pen-local X/Z): a few hops along the way from one goal to the next, with a
-- little wobble, so it wanders the pen in short hops (never a teleport-length leap)
local function spot(pen: Pen, hopper: Hopper, k: number): Vector2
	local g = math.floor(k / HOPS_PER_GOAL)
	local along = (k - g * HOPS_PER_GOAL) / HOPS_PER_GOAL
	local base = goal(pen, hopper, g):Lerp(goal(pen, hopper, g + 1), along)
	local rng = Random.new(hopper.Seed * 104729 + k)
	local wobble = 0.85
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
	local offset = (hopper.Seed % 97) * 0.173
	local t = now + offset
	local k = math.floor(t / period)
	local into = t - k * period
	-- Since: on its Home spot until then, then a few hops easing out from it
	local home, since = hopper.Home, hopper.Since
	local first = if home and since then math.floor((since + offset) / period) else nil
	local function rest(j: number): Vector2
		if first and home then
			if j <= first then
				return home
			end
			return home:Lerp(spot(pen, hopper, j), math.min(1, (j - first) / 4))
		end
		return spot(pen, hopper, j)
	end
	local from, to = rest(k - 1), rest(k)
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
