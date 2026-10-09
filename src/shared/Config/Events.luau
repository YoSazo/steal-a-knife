--!strict
-- Weekly events (PLAN item 25). Every Saturday at 3 PM US Eastern, for an hour, every server runs
-- the week's event by itself (no one has to be online), cycling Golden -> Luck -> Speed. The owner
-- can start one any time with the chat command "/event golden 30" (kind, minutes) and stop it with
-- "/event stop"; that reaches every server (MessagingService). One event at a time, each is one
-- banner and one multiplier: EventService sets that ReplicatedStorage attribute while it runs.

export type Kind = {
	Title: string, -- the banner / board line
	-- the ReplicatedStorage attribute it sets: RoundSpeedMultiplier (the survival ladder) and
	-- DeliverySpeedMultiplier (Speed for a delivered coffin), both in RoundProgress.budget;
	-- MutationLuckMultiplier (coffin luck, CoffinService.Luck)
	Channel: string,
	Multiplier: number,
}

local Events = {
	-- Roblox user ids allowed to run /event (the number in roblox.com/users/<id>/profile):
	-- the owner (R_F1ow, the place creator)
	AdminUserIds = { 1068989182 },
	Weekly = {
		Weekday = 7, -- Saturday (os.date's wday: 1 = Sunday)
		Hour = 15, -- 3 PM, US Eastern (daylight saving handled in server/Services/EventService)
		Minute = 0,
		Minutes = 60,
	},
	Order = { "Golden", "Luck", "Speed" }, -- one per week, in turn
	WarnMinutes = 5, -- "starts in 5 minutes!" to everyone in the server
	MaxAdminMinutes = 180,
	Kinds = {
		Golden = { Title = "🌟 GOLDEN ROUNDS: 2x round Speed!", Channel = "RoundSpeedMultiplier", Multiplier = 2 },
		Luck = {
			Title = "🍀 LUCK STORM: rare coffins 2x more likely!",
			Channel = "MutationLuckMultiplier",
			Multiplier = 2,
		},
		Speed = {
			Title = "👟 SPEED RUSH: 2x Speed from coffins!",
			Channel = "DeliverySpeedMultiplier",
			Multiplier = 2,
		},
	} :: { [string]: Kind },
}

return Events
