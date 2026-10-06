--!strict
-- Each boss's sleeping face (face decal while they doze in their chair; GuardService setAsleep swaps
-- it in and puts their own face back when they wake). Same 512x512 transparent PNG style as their
-- awake faces (tools/make_faces.py). "" = no sleeping face yet: they keep their awake one.
return {
	Frank = "",
	Ivy = "",
	Sam = "",
	Leo = "",
	Ruby = "",
	Kate = "",
	Zoe = "",
	Nick = "",
} :: { [string]: string }
