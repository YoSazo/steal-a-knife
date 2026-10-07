--!strict
local GameConfig = require(script.Parent.Config.GameConfig)
local Motion = { Speed = 1.5 }

function Motion.WakeDuration(wake: number): number
	return wake / Motion.Speed
end
function Motion.SitDuration(): number
	return GameConfig.BossHop.SitTime / Motion.Speed
end
function Motion.Progress(p: number): number
	local beats = GameConfig.BossHop
	local x = math.clamp((p - beats.Crouch) / (beats.Done - beats.Crouch), 0, 1)
	return x * x * (3 - 2 * x)
end
function Motion.Position(post: CFrame, p: number): Vector3
	local forward = post.LookVector * Vector3.new(1, 0, 1)
	return post.Position + forward * GameConfig.BossHop.Distance * Motion.Progress(p)
end
function Motion.Pose(p: number): (number, number)
	local x = Motion.Progress(p)
	return 1 - x, math.sin(x * math.pi) * 0.25 -- seated → slight forward lean → standing, no airborne pose
end

return Motion
