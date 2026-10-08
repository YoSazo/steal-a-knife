local Policy = require(game.ReplicatedStorage.Shared.GuidePolicy)
return function(t)
	local function visible(change)
		local s = { Mode = "Auto", Id = "steal", Skill = "delivery", Learned = {}, Age = 10, Started = false }
		if change then
			change(s)
		end
		return Policy.Visible(s)
	end
	t.test("first delivery remains coached", function()
		t.expect.equal(visible(), true)
	end)
	t.test("three real deliveries retire the whole routine", function()
		t.expect.equal(
			visible(function(s)
				s.Learned.delivery = 3
			end),
			false
		)
		t.expect.equal(Policy.Skill("carry_place"), "delivery")
	end)
	t.test("after one delivery, a familiar route is only a brief cue", function()
		t.expect.equal(
			visible(function(s)
				s.Learned.delivery = 1
			end),
			false
		)
		t.expect.equal(
			visible(function(s)
				s.Learned.delivery = 1
				s.Age = 2
				s.Started = true
			end),
			true
		)
		t.expect.equal(
			visible(function(s)
				s.Learned.delivery = 1
				s.Age = 4
				s.Started = true
			end),
			false
		)
	end)
	t.test("starting the correct action steps the words aside", function()
		t.expect.equal(
			visible(function(s)
				s.Started = true
				s.Age = 4
			end),
			false
		)
	end)
	t.test("On restores coaching and Off disables idle help too", function()
		t.expect.equal(
			visible(function(s)
				s.Mode = "On"
				s.Learned.delivery = 3
			end),
			true
		)
		t.expect.equal(
			visible(function(s)
				s.Mode = "Off"
				s.Help = true
			end),
			false
		)
	end)
	t.test("new tier is a short announcement", function()
		t.expect.equal(
			visible(function(s)
				s.Id = "new_tier"
				s.Age = 2
			end),
			true
		)
		t.expect.equal(
			visible(function(s)
				s.Id = "new_tier"
				s.Age = 9
			end),
			false
		)
	end)
	t.test("another Murderer power gets its own first-use coaching", function()
		local a = {
			Mode = "Auto",
			Id = "murderer_perk",
			Skill = Policy.Skill("murderer_perk", "Snare"),
			Learned = { ["perk:Snare"] = 1 },
			Age = 0,
			Started = false,
		}
		t.expect.equal(Policy.Visible(a), false)
		a.Skill = Policy.Skill("murderer_perk", "FlashKnife")
		t.expect.equal(Policy.Visible(a), true)
	end)
	t.test("saved learning parses, clamps and rejects unknown lessons", function()
		local learned = Policy.Parse("delivery=900,index=1,perk:Snare=1,nonsense=55")
		t.expect.equal(learned.delivery, 3)
		t.expect.equal(learned.index, 1)
		t.expect.equal(learned["perk:Snare"], 1)
		t.expect.equal(learned.nonsense, nil)
	end)
	t.test("a long idle can restore familiar help", function()
		t.expect.equal(
			visible(function(s)
				s.Learned.delivery = 3
				s.Help = true
			end),
			true
		)
	end)
end
