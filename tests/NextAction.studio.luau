-- NextAction ladder: every row picks the expected action (run with tests/RunUnitTest.studio.luau,
-- or require it and call it with a tiny `t` from the Studio command bar)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NextAction = require(ReplicatedStorage.Shared.NextAction)

local function base(): any
	return {
		InRound = false,
		Carrying = nil,
		InVault = false,
		FreePlate = false,
		KnifeCount = 3,
		Slots = 10,
		Rebirths = 0,
		Cash = 0,
		Income = 100,
		PendingCash = 0,
		AutoCollect = false,
		Speed = 0,
		Training = false,
		BestOwnedRank = 1,
		Stocked = { 5, 5, 5, 5, 5, 5, 5, 5 },
		Gift = false,
		IndexClaimable = 0,
		WheelCost = 15000,
		TutorialDone = true,
	}
end

return function(t)
	local function id(change: (any) -> ()): string?
		local s = base()
		change(s)
		local a = NextAction.Pick(s)
		return a and a.Id
	end
	t.test("in a round: no hub action", function()
		t.expect.equal(id(function(s) s.InRound = true end), nil)
	end)
	t.test("carrying outside: run home", function()
		t.expect.equal(id(function(s) s.Carrying = "Katana" end), "carry_home")
	end)
	t.test("carrying inside with a free plate: place it", function()
		t.expect.equal(id(function(s) s.Carrying = "Katana"; s.InVault = true; s.FreePlate = true end), "carry_place")
	end)
	t.test("carrying a case", function()
		t.expect.equal(id(function(s) s.Carrying = "Case:Rare" end), "carry_case")
	end)
	t.test("carrying, vault full, floor affordable", function()
		t.expect.equal(id(function(s) s.Carrying = "Katana"; s.KnifeCount = 10; s.Cash = 2e6 end), "carry_bigger")
	end)
	t.test("carrying, vault full, can't afford", function()
		t.expect.equal(id(function(s) s.Carrying = "Katana"; s.KnifeCount = 10 end), "carry_full")
	end)
	t.test("gift waiting", function()
		t.expect.equal(id(function(s) s.Gift = true end), "gift")
	end)
	t.test("fast enough for Rare: new tier", function()
		t.expect.equal(id(function(s) s.Speed = 6000 end), "new_tier")
	end)
	t.test("new tier but that wall is empty: steal the best you can", function()
		t.expect.equal(id(function(s) s.Speed = 6000; s.Stocked[2] = 0 end), "steal")
	end)
	t.test("index reward", function()
		t.expect.equal(id(function(s) s.IndexClaimable = 2 end), "index")
	end)
	t.test("vault full, can't afford: sell", function()
		t.expect.equal(id(function(s) s.KnifeCount = 10 end), "vault_full")
	end)
	t.test("wheel upgrade affordable", function()
		t.expect.equal(id(function(s) s.Cash = 20000 end), "wheel_upgrade")
	end)
	t.test("in the wheel: keep training", function()
		t.expect.equal(id(function(s) s.Training = true end), "train")
	end)
	t.test("money worth collecting", function()
		t.expect.equal(id(function(s) s.PendingCash = 5000 end), "collect")
	end)
	t.test("auto collect: never walk to pads", function()
		t.expect.equal(id(function(s) s.PendingCash = 5000; s.AutoCollect = true end), "steal")
	end)
	t.test("default: steal another knife", function()
		t.expect.equal(id(function() end), "steal")
	end)
	t.test("every wall empty: train", function()
		t.expect.equal(id(function(s) s.Stocked = { 0, 0, 0, 0, 0, 0, 0, 0 } end), "train")
	end)
end
