local Resolve = require(game.ReplicatedStorage.Shared.WorldSignTarget).Resolve
local Range = require(game.ReplicatedStorage.Shared.WorldSignModel).UpgradeRange
return function(t)
	local function board(name)
		local part = Instance.new("Part")
		part.Position = Vector3.zero
		local cd = Instance.new("ClickDetector")
		cd.Name = name
		cd.MaxActivationDistance = Range
		cd:SetAttribute("Owner", 123)
		cd.Parent = part
		return part
	end
	t.test("own wheel sign works 40 studs away", function()
		local p = board("UpgradeWheel")
		t.expect.equal(Resolve(p, Vector3.new(40, 0, 0), 123).Action, "Speed")
		p:Destroy()
	end)
	t.test("own Bigger Vault sign has the same range", function()
		local p = board("UpgradeBase")
		t.expect.equal(Resolve(p, Vector3.new(40, 0, 0), 123).Action, "Slot")
		p:Destroy()
	end)
	t.test("tapping the visible lettering reaches its owning board", function()
		local p = board("UpgradeWheel")
		local m = Instance.new("Model")
		m.Parent = p
		local letter = Instance.new("Part")
		letter.Parent = m
		t.expect.equal(Resolve(letter, Vector3.zero, 123).Part, p)
		p:Destroy()
	end)
	t.test("out of range and other players' signs stay inactive", function()
		local p = board("UpgradeWheel")
		t.expect.equal(Resolve(p, Vector3.new(Range + 1, 0, 0), 123), nil)
		t.expect.equal(Resolve(p, Vector3.zero, 456), nil)
		p:Destroy()
	end)
	t.test("sell signs keep their original range", function()
		local p = board("Sell")
		p:SetAttribute("SellOwner", 123)
		p:FindFirstChildOfClass("ClickDetector").MaxActivationDistance = 28
		t.expect.equal(Resolve(p, Vector3.new(40, 0, 0), 123), nil)
		p:Destroy()
	end)
end
