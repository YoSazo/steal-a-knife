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
	Sting = "rbxassetid://9042321568", -- role reveal
	Death = "rbxassetid://9125652443", -- short death cry (Pro Sound Effects), players and guards

	-- Music
	HubMusic = "rbxassetid://77171316401592", -- dark ambient, the hub at night
	RaidMusic = "rbxassetid://9048541013", -- "Battleground" (APM), during raids
	Heartbeat = "rbxassetid://9043365842", -- "Heartbeat 96BPM" (APM), the Murderer is near

	-- Raids
	Alarm = "rbxassetid://9125544285", -- alarm bell (PSE): your gate is under attack
	GateHit = "rbxassetid://9116502787", -- metal drum bang (PSE)
	GateBreak = "rbxassetid://9116635188", -- metal grate crash (PSE)
	WoodBreak = "rbxassetid://9120801590", -- wood snap (PSE): barricades
	Knockdown = "rbxasset://sounds/action_falling.mp3",

	-- Cases and rewards
	DrumRoll = "rbxassetid://1842251033", -- snare roll (APM) while the reel spins
	Reveal = "rbxassetid://1843946260", -- sting (APM) when it lands
	Cheer = "rbxassetid://9112766176", -- crowd cheer (PSE) for the big ones
	Tick = "rbxasset://sounds/electronicpingshort.wav",

	-- Powers
	Flash = "rbxasset://sounds/electronicpingshort.wav",
}
