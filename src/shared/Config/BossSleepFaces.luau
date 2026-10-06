--!strict
-- Each boss's sleeping face (face decal while they doze in their chair; GuardService setAsleep swaps
-- it in and puts their own face back when they wake). Same 512x512 transparent PNG style as their
-- awake faces (tools/make_faces.py). "" = no sleeping face yet: they keep their awake one.
return {
	Frank = "rbxassetid://119605985373097",
	Ivy = "rbxassetid://84021250676208",
	Sam = "rbxassetid://78813734800782",
	Leo = "rbxassetid://71537067074669",
	Ruby = "rbxassetid://118689644156314",
	Kate = "rbxassetid://120679401488349",
	Zoe = "rbxassetid://80182804866673",
	Nick = "rbxassetid://73893746791595",
} :: { [string]: string }
