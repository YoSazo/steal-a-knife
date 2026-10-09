--!strict
local CoffinState = {}
export type Entry = { Plate: number, Rounds: number, OpensAt: number }
function CoffinState.Ready(rounds: number?, deadline: number, now: number): boolean
	return if rounds ~= nil and rounds >= 0 then rounds <= 0 else deadline <= now
end
-- The waiting coffin's line: "Unlocks after 2 murder rounds" / "after 1 murder round"
function CoffinState.RoundsText(rounds: number): string
	local n = math.max(1, math.ceil(rounds))
	return `Unlocks after {n} murder {if n == 1 then "round" else "rounds"}`
end
function CoffinState.Parse(raw: any): { [number]: Entry }
	local out: { [number]: Entry } = {}
	for plate, rounds, deadline in (if type(raw) == "string" then raw else ""):gmatch("(%d+),%a+,(%-?%d+),(%d+)") do
		local id = tonumber(plate) :: number
		out[id] = { Plate = id, Rounds = tonumber(rounds) :: number, OpensAt = tonumber(deadline) :: number }
	end
	return out
end
return CoffinState
