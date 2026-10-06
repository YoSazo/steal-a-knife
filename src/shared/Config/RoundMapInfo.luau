--!strict
-- What the players see of each round map: on the vote boards at the back of the plaza
-- (server MapVote) and the vote card (client MapVoteCard). Names match RoundMaps.Names.
-- Image: an in-game shot of the map (taken in Studio, assets/map-shots), shown on its vote board
export type Info = { Name: string, Emoji: string, Color: Color3, Blurb: string, Image: string }

local List: { Info } = {
	{
		Name = "Office",
		Emoji = "🏢",
		Color = Color3.fromRGB(70, 130, 210),
		Blurb = "2 floors · 17 rooms",
		Image = "rbxassetid://118986350300575",
	},
	{
		Name = "Mansion",
		Emoji = "🏰",
		Color = Color3.fromRGB(190, 50, 60),
		Blurb = "2 floors · 14 rooms",
		Image = "rbxassetid://94619359745443",
	},
}

local ByName: { [string]: Info } = {}
for _, info in List do
	ByName[info.Name] = info
end

return { List = List, ByName = ByName }
