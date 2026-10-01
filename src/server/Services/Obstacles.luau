--!strict
-- Breakable things in the way: Barricades (the Innocent Power) for now. Guards, burglars and the
-- Murderer (player or bot) ask here whether something blocks them and smash it instead of walking
-- through. Whoever creates an obstacle says what a hit does.

local Obstacles = {}

export type Obstacle = {
	Part: BasePart,
	Owner: Player?,
	Hit: (by: string) -> (), -- by: "Guard" | "Murderer" | "Burglar" | "Player"
}

local list: { Obstacle } = {}

function Obstacles.Add(obstacle: Obstacle): () -> ()
	table.insert(list, obstacle)
	return function()
		local index = table.find(list, obstacle)
		if index then
			table.remove(list, index)
		end
	end
end

local function closestPoint(part: BasePart, point: Vector3): Vector3
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	return part.CFrame:PointToWorldSpace(
		Vector3.new(
			math.clamp(localPoint.X, -half.X, half.X),
			math.clamp(localPoint.Y, -half.Y, half.Y),
			math.clamp(localPoint.Z, -half.Z, half.Z)
		)
	)
end

-- The obstacle within `range` of `position` (in front of `look`, if given)
function Obstacles.Near(position: Vector3, range: number, look: Vector3?): Obstacle?
	local best: Obstacle? = nil
	local bestDistance = range
	for _, obstacle in list do
		if not obstacle.Part.Parent then
			continue
		end
		local offset = closestPoint(obstacle.Part, position) - position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local distance = flat.Magnitude
		local facing = if look and distance > 0.5 then look:Dot(flat.Unit) else 1
		if distance <= bestDistance and facing > 0 then
			best, bestDistance = obstacle, distance
		end
	end
	return best
end

-- Would moving from `from` to `to` (a body `radius` wide) run into one?
function Obstacles.Blocks(from: Vector3, to: Vector3, radius: number): Obstacle?
	for _, obstacle in list do
		local part = obstacle.Part
		if not part.Parent then
			continue
		end
		local localTo = part.CFrame:PointToObjectSpace(to)
		local half = part.Size / 2 + Vector3.new(radius, 0, radius)
		if math.abs(localTo.X) <= half.X and math.abs(localTo.Z) <= half.Z then
			-- Only if it's moving into it (not already inside, walking out)
			local localFrom = part.CFrame:PointToObjectSpace(from)
			if math.abs(localFrom.X) > half.X or math.abs(localFrom.Z) > half.Z then
				return obstacle
			end
		end
	end
	return nil
end

return Obstacles
