--!strict
-- Sound ids in one place (all free/public: Roblox built-ins, APM Music and Pro Sound Effects from
-- the Creator Store). Classic 2010-era Roblox sword sounds for the knife, which fits the old
-- murder-game feel.

return {
	Slash = "rbxassetid://12222216", -- classic sword slash
	Lunge = "rbxassetid://12222208", -- classic sword lunge (dash / throw)
	Unsheath = "rbxassetid://12222225", -- classic sword unsheath (Murderer gets the knife)
	Gunshot = "rbxassetid://120771468205926",
	Coin = "rbxassetid://4612374807",
	Cash = "rbxassetid://134810204798705",
	-- (the old horror sounds are gone: the game is bright and toy-like now, for 9-15 year olds)
	Sting = "rbxassetid://1843946260", -- role reveal, round intro, big moments (same sting as cases)
	Death = "rbxasset://sounds/uuhhh.mp3", -- Roblox's own death sound (it was a screaming death cry)

	-- Music. HubMusic: put a cheerful looping track's id here ("" = no hub music); it was horror ambience
	HubMusic = "",
	RaidMusic = "rbxassetid://9048541013", -- "Battleground" (APM), during the Blood Moon

	-- Raids
	Alarm = "rbxassetid://9125544285", -- alarm bell (PSE): someone is robbing YOUR vault
	GateHit = "rbxassetid://9116502787", -- metal drum bang (PSE)
	GateBreak = "rbxassetid://9116635188", -- metal grate crash (PSE)
	WoodBreak = "rbxassetid://9120801590", -- wood snap (PSE): barricades
	Knockdown = "rbxasset://sounds/action_falling.mp3",
	Wind = "rbxassetid://9125742262", -- airy whooshing (PSE), louder the faster you run

	-- Cases and rewards
	DrumRoll = "rbxassetid://1842251033", -- snare roll (APM) while the reel spins
	Reveal = "rbxassetid://1843946260", -- sting (APM) when it lands
	Cheer = "rbxassetid://9112766176", -- crowd cheer (PSE) for the big ones
	Tick = "rbxasset://sounds/electronicpingshort.wav",

	-- Powers
	Flash = "rbxasset://sounds/electronicpingshort.wav",
}
