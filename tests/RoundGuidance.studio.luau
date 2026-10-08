local RoundGuidance = require(game:GetService("ReplicatedStorage").Shared.RoundGuidance)

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
			Perk = "Invisiknife",
			PerkPassive = false,
			PerkUsesLeft = 1,
			PerkWait = 0,
			Spam = false,
			GunNearby = false,
			Input = "Keyboard",
			Stunned = 0,
		}
	end
	t.test("innocents collect coins and stay safe (Classic too)", function()
		local s = state()
		t.expect.equal(RoundGuidance.Pick(s).Id, "innocent_coins")
		s.Classic = true
		t.expect.equal(RoundGuidance.Pick(s).Id, "classic_coins")
	end)
	t.test("gun ownership comes first: draw then reload then shoot", function()
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
