--!strict
-- Pure gesture policy: only the pointer that pressed the knife can release it.
-- No world input, rendering, or server requests belong in this module.
local Gesture = {}
Gesture.__index = Gesture

export type State = {
	owner: any,
	started: number,
	mode: string,
}

function Gesture.new(): State
	return { owner = nil, started = 0, mode = "idle" }
end

function Gesture.press(state: State, owner: any, now: number): boolean
	if state.owner ~= nil then
		return false
	end
	state.owner, state.started, state.mode = owner, now, "pending"
	return true
end

function Gesture.tick(state: State, now: number, canCharge: boolean): string?
	if state.owner == nil or now - state.started < 0.2 then
		return nil
	end
	if state.mode == "pending" then
		state.mode = if canCharge then "charging" else "blocked"
		return if canCharge then "charge" else "cooldown"
	end
	return nil
end

function Gesture.cancel(state: State)
	state.owner, state.mode = nil, "idle"
end

function Gesture.release(state: State, owner: any, now: number): string?
	if state.owner ~= owner or state.owner == nil then
		return nil
	end
	local mode = state.mode
	local tap = mode == "pending" and now - state.started < 0.2
	Gesture.cancel(state)
	if tap then
		return "swing"
	end
	return if mode == "charging" then "throw" else nil
end

return Gesture
