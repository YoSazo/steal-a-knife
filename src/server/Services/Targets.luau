--!strict
-- Hub targets besides bosses: StealService registers eligible carriers for knockdowns.
-- CombatService asks here after checking the bosses. Each target says whether a given attacker
-- may hit it right now and what happens when they do.

local Targets = {}

export type Target = {
	Part: BasePart, -- what reach is measured to (the closest point on its box)
	Model: Instance, -- a thrown knife hitting anything inside this counts
	CanHit: (attacker: Player) -> boolean,
	Hit: (attacker: Player, damage: number, kind: string, from: Vector3) -> (), -- kind: "Swing" | "Throw"
	Solid: boolean?, -- thrown knives stop on it
}

local registered: { [Target]: boolean } = {}
-- Lists of targets made fresh on demand (players come and go every frame)
local providers: { () -> { Target } } = {}

function Targets.Add(target: Target): () -> ()
	registered[target] = true
	return function()
		registered[target] = nil
	end
end

function Targets.AddProvider(provider: () -> { Target })
	table.insert(providers, provider)
end

local function all(): { Target }
	local list = {}
	for target in registered do
		if target.Part.Parent then
			table.insert(list, target)
		else
			registered[target] = nil
		end
	end
	for _, provider in providers do
		for _, target in provider() do
			table.insert(list, target)
		end
	end
	return list
end

-- Closest point on a part's box to `point`
local function closestPoint(part: BasePart, point: Vector3): Vector3
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	local clamped = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)
	return part.CFrame:PointToWorldSpace(clamped)
end

-- The nearest hittable target within `range` in front of `position` (for swings)
function Targets.InReach(attacker: Player, position: Vector3, look: Vector3, range: number): Target?
	local best: Target? = nil
	local bestDistance = range
	for _, target in all() do
		local point = closestPoint(target.Part, position)
		local offset = point - position
		local distance = offset.Magnitude
		local facing = if distance > 0.5 then look:Dot(offset.Unit) else 1
		if distance <= bestDistance and facing > 0.1 and target.CanHit(attacker) then
			best, bestDistance = target, distance
		end
	end
	return best
end

-- The target a raycast hit belongs to, if any
function Targets.FromPart(attacker: Player, part: Instance): Target?
	for _, target in all() do
		if (part == target.Part or part:IsDescendantOf(target.Model)) and target.CanHit(attacker) then
			return target
		end
	end
	return nil
end

-- Soft targets a thrown knife passing from a to b goes through (things the ray can't stop on,
-- like players' characters, which hub knives fly through otherwise). Solid ones are left to the ray.
function Targets.AlongPath(attacker: Player, a: Vector3, b: Vector3, radius: number): Target?
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	for _, target in all() do
		local center = target.Part.Position
		local t = if lengthSq > 0 then math.clamp((center - a):Dot(ab) / lengthSq, 0, 1) else 0
		local closest = a + ab * t
		if
			not target.Solid
			and (closestPoint(target.Part, closest) - closest).Magnitude <= radius
			and target.CanHit(attacker)
		then
			return target
		end
	end
	return nil
end

return Targets
