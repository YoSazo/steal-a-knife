--!strict
-- Sound ids in one place (all free/public: Roblox built-ins, APM Music and Pro Sound Effects from
-- the Creator Store - the licensed libraries, so no copyright strikes and nothing goes private).

return {
	Slash = "rbxassetid://9116197039", -- Knife Shing, Metal Swipe (PSE)
	Lunge = "rbxassetid://9126047581", -- Synth Air Whoosh, karate swish (PSE): dashes and blinks
	Unsheath = "rbxassetid://9116197252", -- Knife Shing, remove from scabbard (PSE): equipping / drawing
	Throw = "rbxassetid://9126283272", -- Wood Swish, Fast Movement in Air (PSE): every thrown knife
	Gunshot = "rbxassetid://120771468205926",
	Coin = "rbxassetid://4612374807",
	Announce = "rbxassetid://4612374495", -- a quick sparkly ding when someone in the server rolls something big
	Cash = "rbxassetid://134810204798705",
	-- (the old horror sounds are gone: the game is bright and toy-like now, for 9-15 year olds)
	Sting = "rbxassetid://1843946260", -- role reveal, round intro, big moments (same sting as cases)
	Death = "rbxasset://sounds/uuhhh.mp3", -- Roblox's own death sound (it was a screaming death cry)

	-- Music
	HubMusic = "rbxassetid://1845444990", -- "Coffee Break" (APM, Manfred Paulsen): light jazz under the hub

	-- Raids
	Alarm = "rbxassetid://9125544285", -- alarm bell (PSE): someone is robbing YOUR vault
	-- A boss waking up (Effects BossWake): a rising gliss while the eyes go red, a roar as they stand
	BossWake = "rbxassetid://1846544949", -- "Bass Gliss Up" (APM)
	BossRoar = "rbxassetid://9116302511", -- Lion Roar, Short Blast (PSE)
	-- You just stole from a boss: one quick siren whoop (Steal An Egg's alarm), cut to ~1 s
	StealSiren = "rbxassetid://3261279556", -- "Professional Swedish Ambulance - Whoop 1" (1.4 s)
	GateHit = "rbxassetid://9116502787", -- metal drum bang (PSE)
	GateBreak = "rbxassetid://9116635188", -- metal grate crash (PSE)
	WoodBreak = "rbxassetid://9120801590", -- wood snap (PSE): barricades
	Knockdown = "rbxasset://sounds/action_falling.mp3",
	Wind = "rbxassetid://9125742262", -- airy whooshing (PSE), louder the faster you run

	-- Cases and rewards
	DrumRoll = "rbxassetid://1842251033", -- snare roll (APM) while the reel spins
	-- The role reel's landing (client/Hud "You are..."), one per role (APM stings)
	RoleMurderer = "rbxassetid://9047102381", -- "Game Day Warrior" sting: big and punchy
	RoleSheriff = "rbxassetid://9047103106", -- "All It Takes" sting
	RoleInnocent = "rbxassetid://9040476898", -- "Early Bird" hit: bouncy, upbeat
	ReelTick = "rbxassetid://9120098629", -- a crisp little switch click (PSE) per knife going past
	Reveal = "rbxassetid://4612374036", -- a quick sparkly "big diamond" ding: any reveal (case, power roll, gift)
	Tick = "rbxasset://sounds/electronicpingshort.wav",
	-- Winning a round (client/Transitions): the win card's jingle, and one "got it" as the shoes land
	Win = "rbxassetid://139651791574775", -- "Aquapark SFX - finish" (procedurally generated, original)
	PrizeLand = "rbxassetid://3416831713", -- "Token_Get"
	MenuPop = "rbxassetid://9117848029", -- "Pops, Mouth Popping" (PSE): a menu opening (higher) / closing (lower)

	-- Footsteps (one picked at random per step, client/Footsteps)
	Steps = {
		"rbxassetid://111340116520328",
		"rbxassetid://139406838352611",
		"rbxassetid://111792114329462",
		"rbxassetid://115839208850044",
		"rbxassetid://75231057179896",
	},

	-- Powers
	Flash = "rbxasset://sounds/electronicpingshort.wav",
}
