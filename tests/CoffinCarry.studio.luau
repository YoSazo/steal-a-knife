-- Studio CLIENT integration check on a throwaway coffin/pen save with room available.
-- Goes through the real Debug bindable-backed remote, pickup validator and PlaceAt handler.
return function()
	local p = game.Players.LocalPlayer
	assert(p and not p:GetAttribute("InRound"), "Run in the hub's client")
	local rem = game.ReplicatedStorage.Remotes
	local profile = rem.Debug:InvokeServer("Data")
	assert(#profile.Knives < profile.Slots, "The fixture needs room in its pen")
	local base = workspace.Map.Bases:FindFirstChild("Base" .. p:GetAttribute("VaultIndex"))
	p.Character:PivotTo(CFrame.new(base.Floor.Position + Vector3.new(0, 3, 0)))
	task.wait(0.2)
	rem.Debug:InvokeServer("Carry", "HunterBlade", true)
	rem.Debug:InvokeServer("Knock")
	task.wait(1.5)
	local drop = workspace.Map.DroppedKnives:FindFirstChild("DroppedCoffin")
	assert(drop and drop:GetAttribute("SealedDrop"), "Knockdown revealed an open knife")
	assert(
		drop:FindFirstChildWhichIsA("ProximityPrompt", true).ObjectText == "Rare Coffin",
		"Drop exposed its hidden contents"
	)
	p.Character:PivotTo(CFrame.new(drop.PrimaryPart.Position + Vector3.new(0, 2, 0)))
	task.wait(0.2)
	assert(rem.Debug:InvokeServer("Pickup", drop), "Registered pickup failed")
	assert(not rem.Debug:InvokeServer("Pickup", drop), "Duplicate pickup succeeded")
	rem.Debug:InvokeServer("SuspendResume")
	rem.PlaceAt:FireServer(base.Floor.Position)
	task.wait(0.7)
	local after = rem.Debug:InvokeServer("Data")
	assert(#after.Knives == #profile.Knives + 1, "Incorrect inventory grant")
	assert(#after.Sealed == #profile.Sealed + 1, "Round suspension bypassed sealing")
	assert(#after.Discovered == #profile.Discovered, "Unopened contents entered the Index")
	return true
end
