--!strict
-- Only the Murderer chance meter remains: playing adds to it; selection empties it.
local DataService = require(script.Parent.DataService)
local ChanceMeter = {}
function ChanceMeter.Add(player: Player, delta: number)
	DataService.Update(player, function(p)
		p.Luck = math.max(0, p.Luck + delta)
	end)
end
return ChanceMeter
