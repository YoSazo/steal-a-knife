--!strict
-- Pure gesture policy: only the pointer that pressed the knife can release it.
-- No world input, rendering, or server requests belong in this module.
local Gesture = {}
Gesture.__index = Gesture

export type State = {
	owner: any,
	started: number,
	mode: string,
	lastRepeat: number,
}

function Gesture.new(): State
	return { owner = nil, started = 0, mode = "idle", lastRepeat = 0 }
end

function Gesture.press(state: State, owner: any, now: number): boolean
	if state.owner ~= nil then
		return false
	end
	state.owner, state.started, state.mode = owner, now, "pending"
	return true
end

function Gesture.tick(state: State, now: number, canCharge: boolean, spam: boolean): string?
	if state.owner == nil or now - state.started < 0.2 then
		return nil
	end
	if spam and (state.mode == "pending" or state.mode == "spam") then
		if state.mode == "pending" or now - state.lastRepeat >= 0.1 then
			state.mode, state.lastRepeat = "spam", now
			return "spam"
		end
	elseif state.mode == "pending" then
		state.mode = if canCharge then "charging" else "blocked"
		return if canCharge then "charge" else "cooldown"
	elseif state.mode == "spam" and not spam then
		state.mode = "blocked"
	end
	return nil
end

function Gesture.cancel(state: State)
	state.owner, state.mode = nil, "idle"
end

function Gesture.release(state: State, owner: any, now: number, spam: boolean): string?
	if state.owner ~= owner or state.owner == nil then
		return nil
	end
	local mode = state.mode
	local tap = mode == "pending" and now - state.started < 0.2
	Gesture.cancel(state)
	if tap then
		return if spam then "spam" else "swing"
	end
	return if mode == "charging" then "throw" else nil
end

return Gesture
