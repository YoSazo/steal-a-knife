--!strict
-- One immediate round action, using server availability and the player's actual tools.
local GameConfig = require(script.Parent.Config.GameConfig)
local KnifePowers = require(script.Parent.Config.KnifePowers)

local RoundGuidance = {}
export type State = {
	Murderer: boolean,
	HasKnife: boolean,
	KnifeOut: boolean,
	HasGun: boolean,
	GunOut: boolean,
	WeaponWait: number,
	Reload: number,
	Classic: boolean,
	Energy: number,
	UsesLeft: number?,
	Power: string?,
	Perk: string?,
	PerkPassive: boolean,
	PerkUsesLeft: number?,
	PerkWait: number,
	Spam: boolean,
	SecondLifeUsed: boolean,
	GunNearby: boolean,
	Input: string,
	Stunned: number,
}
export type Action = { Id: string, Text: string, Short: string?, Ui: string?, Target: string?, Zone: number? }

local BENEFITS = {
	Vanish = "turn invisible",
	Radar = "find the Murderer",
	Trap = "set a trap",
	Shield = "block a stab",
	Decoy = "send out a fake you",
	Mimic = "hide as furniture",
	Flash = "blind the Murderer",
	Barricade = "block the way",
	Rush = "run super fast",
	Dash = "blink forward",
	SmokeBurst = "push the Murderer back",
	PhoenixWall = "make a wall of fire",
}

function RoundGuidance.Pick(s: State): Action
	local touch, pad = s.Input == "Touch", s.Input == "Gamepad"
	if s.Stunned > 0 then
		return {
			Id = "round_stunned",
			Text = `Trapped for {math.ceil(s.Stunned)}s - get ready to run!`,
			Short = `Trapped - {math.ceil(s.Stunned)}s`,
		}
	end
	if s.Murderer then
		if not s.HasKnife then
			return {
				Id = "murderer_grace",
				Text = `Find someone to surprise - knife in {math.max(0, math.ceil(s.WeaponWait))}s`,
				Short = `Knife in {math.max(0, math.ceil(s.WeaponWait))}s - get ready!`,
			}
		end
		if not s.KnifeOut then
			return {
				Id = "murderer_draw",
				Text = if touch
					then "Tap your knife to pull it out!"
					else if pad then "Select your knife to pull it out!" else "Press 1 to pull out your knife!",
				Ui = "KnifeDraw",
			}
		end
		if s.Spam then
			return {
				Id = "murderer_spam",
				Text = if touch
					then "Tap to throw knives!"
					else if pad then "Press RT to throw knives!" else "Click to throw knives!",
				Ui = "KnifeThrow",
			}
		end
		local short = s.Perk and KnifePowers.Short[s.Perk]
		if not s.Classic and short and s.PerkPassive then
			return {
				Id = "murderer_passive",
				Text = `{if touch then "Tap" else if pad then "RT" else "Click"} to stab - {string.lower(short[1])}`,
				Short = short[1],
			}
		end
		if not s.Classic and short and s.PerkUsesLeft ~= 0 and s.PerkWait <= 0 then
			return {
				Id = "murderer_perk",
				Text = `{if touch then "Tap your power" else if pad then "LT" else "Press Q"}: {string.lower(short[1])}`,
				Short = `{if touch then "Tap power" else if pad then "LT" else "Q"}: {short[1]}`,
				Ui = "Perk",
			}
		end
		return {
			Id = "murderer_fight",
			Text = if touch
				then "Tap to stab - hold THROW to throw!"
				else if pad then "RT to stab - hold LT to throw!" else "Click to stab - hold click to throw!",
			Short = if touch
				then "Tap to stab - hold THROW!"
				else if pad then "RT: stab - LT: throw" else "Click: stab - hold: throw",
		}
	end
	if s.HasGun then
		if not s.GunOut then
			return {
				Id = "sheriff_draw",
				Text = if touch
					then "Tap the screen to pull out your gun!"
					else if pad then "Select your gun to pull it out!" else "Press 1 to pull out your gun!",
				Short = if touch then "Tap the screen to draw your gun!" else "Pull out your gun!",
				Ui = "GunDraw",
			}
		end
		if s.Reload > 0 then
			return {
				Id = "sheriff_reload",
				Text = `Keep moving - gun ready in {math.ceil(s.Reload)}s!`,
				Short = `Reloading - {math.ceil(s.Reload)}s`,
			}
		end
		return {
			Id = "sheriff_shoot",
			Text = `Find the Murderer - {if touch then "tap" else if pad then "RT" else "click"} to shoot!`,
			Short = `Find the Murderer - {if touch then "tap" else if pad then "RT" else "click"} to shoot!`,
		}
	end
	if s.GunNearby then
		return { Id = "gun_pickup", Text = "Grab the gun to stop the Murderer!", Target = "RoundGun" }
	end
	if s.Classic then
		return {
			Id = "classic_coins",
			Text = "Collect coins and stay safe - no powers this round!",
			Short = "Collect coins and stay safe!",
			Target = "RoundCoin",
		}
	end
	if s.Power == "SecondLife" then
		return {
			Id = "second_life",
			Text = if s.SecondLifeUsed
				then "Second Life used - collect coins and stay safe!"
				else "Collect coins - your knife saves you from one stab!",
			Short = if s.SecondLifeUsed then "Second Life used - stay safe!" else "One extra life - collect coins!",
			Target = "RoundCoin",
		}
	end
	local power: any = nil
	for _, entry in GameConfig.Powers do
		if entry.Id == s.Power then
			power = entry
			break
		end
	end
	if not power or s.UsesLeft == 0 then
		return {
			Id = "innocent_coins",
			Text = if power then "Power used up - collect coins and stay safe!" else "Collect coins and stay safe!",
			Short = "Collect coins and stay safe!",
			Target = "RoundCoin",
		}
	end
	local cost = power.Energy[math.clamp(GameConfig.RoundPowerLevel, 1, #power.Energy)]
	local benefit = BENEFITS[power.Id] or string.lower(power.DisplayName)
	if s.Energy < cost then
		local coins = math.ceil((cost - s.Energy) / GameConfig.EnergyPerCoin)
		return {
			Id = "power_coins",
			Text = `Grab {coins} {if coins == 1 then "coin" else "coins"} to {benefit}!`,
			Target = "RoundCoin",
		}
	end
	local input = if touch then "Tap your power" else if pad then "D-pad Left" else "Press Z"
	return {
		Id = "power_ready",
		Text = `{input} to {benefit}!`,
		Short = `{if touch then "Tap power" else if pad then "D-pad Left" else "Z"}: {benefit}!`,
		Ui = "Power1",
	}
end

return RoundGuidance
