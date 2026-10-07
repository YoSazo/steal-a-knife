local RoundGuidance = require(game:GetService("ReplicatedStorage").Shared.RoundGuidance)
local KnifePowers = require(game:GetService("ReplicatedStorage").Shared.Config.KnifePowers)

return function(t)
	local function state(): any
		return {
			Murderer = false,
			HasKnife = false,
			KnifeOut = false,
			HasGun = false,
			GunOut = false,
			WeaponWait = 0,
			Reload = 0,
			Classic = false,
			Energy = 1,
			UsesLeft = 1,
			Power = "Vanish",
			Perk = "Invisiknife",
			PerkPassive = false,
			PerkUsesLeft = 1,
			PerkWait = 0,
			Spam = false,
			SecondLifeUsed = false,
			GunNearby = false,
			Input = "Keyboard",
			Stunned = 0,
		}
	end
	t.test("starter needs four coins", function()
		local action = RoundGuidance.Pick(state())
		t.expect.equal(action.Id, "power_coins")
		t.expect.truthy(action.Text:find("4 coins", 1, true))
	end)
	t.test("ready desktop power uses Z, touch uses tap, controller uses d-pad", function()
		for input, binding in { Keyboard = "Z", Touch = "Tap", Gamepad = "D-pad Left" } do
			local s = state()
			s.Energy, s.Input = 5, input
			local action = RoundGuidance.Pick(s)
			t.expect.equal(action.Id, "power_ready")
			t.expect.truthy(action.Text:find(binding, 1, true))
		end
	end)
	t.test("exhausted powers never appear ready", function()
		local s = state()
		s.Energy, s.UsesLeft = 6, 0
		t.expect.equal(RoundGuidance.Pick(s).Id, "innocent_coins")
	end)
	t.test("all innocent powers have an achievable action", function()
		for _, power in KnifePowers.List do
			local s = state()
			s.Power, s.Energy, s.UsesLeft = power.Innocent, 6, -1
			local action = RoundGuidance.Pick(s)
			t.expect.equal(action.Id, if s.Power == "SecondLife" then "second_life" else "power_ready")
		end
	end)
	t.test("Classic and Second Life do not ask players to activate a power", function()
		local s = state()
		s.Classic, s.Energy = true, 6
		t.expect.equal(RoundGuidance.Pick(s).Id, "classic_coins")
		s.Classic, s.Power, s.SecondLifeUsed = false, "SecondLife", true
		t.expect.truthy(RoundGuidance.Pick(s).Text:find("used", 1, true))
	end)
	t.test("gun ownership supersedes innocent power, draw then reload then shoot", function()
		local s = state()
		s.HasGun = true
		t.expect.equal(RoundGuidance.Pick(s).Id, "sheriff_draw")
		s.GunOut, s.Reload = true, 2
		t.expect.equal(RoundGuidance.Pick(s).Id, "sheriff_reload")
		s.Reload = 0
		t.expect.equal(RoundGuidance.Pick(s).Id, "sheriff_shoot")
	end)
	t.test("only a public nearby gun creates pickup guidance", function()
		local s = state()
		s.GunNearby = true
		t.expect.equal(RoundGuidance.Pick(s).Id, "gun_pickup")
	end)
	t.test("Murderer grace, draw, passive, active, exhausted, spam", function()
		local s = state()
		s.Murderer, s.WeaponWait = true, 10
		t.expect.equal(RoundGuidance.Pick(s).Id, "murderer_grace")
		s.HasKnife = true
		t.expect.equal(RoundGuidance.Pick(s).Id, "murderer_draw")
		s.KnifeOut, s.PerkPassive = true, true
		t.expect.equal(RoundGuidance.Pick(s).Id, "murderer_passive")
		s.PerkPassive = false
		t.expect.equal(RoundGuidance.Pick(s).Id, "murderer_perk")
		s.PerkUsesLeft = 0
		t.expect.equal(RoundGuidance.Pick(s).Id, "murderer_fight")
		s.Spam = true
		t.expect.equal(RoundGuidance.Pick(s).Id, "murderer_spam")
	end)
end
