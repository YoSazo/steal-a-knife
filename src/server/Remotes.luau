--!strict
-- All client<->server traffic. Clients can only ask (Purchase); the server decides everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = Instance.new("Folder")
folder.Name = "Remotes"
folder.Parent = ReplicatedStorage

local function event(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local function func(name: string): RemoteFunction
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local Remotes = {
	Notify = event("Notify"), -- server -> client: (text, kind)
	Role = event("Role"), -- server -> client: ("Murderer" | "Innocent")
	Purchase = func("Purchase"), -- client -> server: (kind) -> (ok, message)
}

return {
	Remotes = Remotes,
	-- kind: "info" | "good" | "bad"
	Notify = function(player: Player, text: string, kind: string?)
		Remotes.Notify:FireClient(player, text, kind or "info")
	end,
}
