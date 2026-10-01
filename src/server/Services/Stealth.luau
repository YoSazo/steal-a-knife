--!strict
-- Hiding characters: Vanish (invisible for a while) and the body-hiding half of Mimic. Sets the
-- player attributes guards and the HUD look at ("Invisible", "Mimic"), and puts everything back
-- exactly as it was afterwards - including if it gets cut short.

local Net = require(script.Parent.Parent.Remotes)

local Stealth = {}

local restores: { [Player]: () -> () } = {}

-- Makes the whole character (tools, carried knife, hats) see-through and hides its name tag.
-- Returns the function that undoes it.
function Stealth.Hide(player: Player): (() -> ())?
	local character = player.Character
	if not character then
		return nil
	end
	local saved: { [Instance]: number } = {}
	for _, d in character:GetDescendants() do
		if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
			saved[d] = (d :: any).Transparency;
			(d :: any).Transparency = 1
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	return function()
		for instance, transparency in saved do
			if instance.Parent then
				(instance :: any).Transparency = transparency
			end
		end
		if humanoid and humanoid.Parent then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		end
	end
end

-- Invisible for `duration` seconds (or until Reveal). Guards drop you as a target.
function Stealth.Vanish(player: Player, duration: number)
	Stealth.Reveal(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		Net.Remotes.Effect:FireAllClients("Smoke", root.Position)
	end
	local undo = Stealth.Hide(player)
	if not undo then
		return
	end
	player:SetAttribute("Invisible", true)
	local function finish()
		if restores[player] == finish then
			restores[player] = nil
			player:SetAttribute("Invisible", nil)
			undo()
		end
	end
	restores[player] = finish
	task.delay(duration, finish)
end

-- Ends any hiding early (hit by the Murderer, used another power, round ended...)
function Stealth.Reveal(player: Player)
	local restore = restores[player]
	if restore then
		restore()
	end
end

-- For other hiding effects (Mimic) that want Reveal to end them too
function Stealth.Register(player: Player, finish: () -> ())
	Stealth.Reveal(player)
	restores[player] = finish
end

function Stealth.Unregister(player: Player, finish: () -> ())
	if restores[player] == finish then
		restores[player] = nil
	end
end

return Stealth
