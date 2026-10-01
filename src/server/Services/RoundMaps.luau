--!strict
-- Indoor round maps in the style of the classic murder games (The Mad Murderer era): real
-- buildings with rooms that each look like a place - an open-plan office with cubicles and a
-- storage room where the bulbs won't stop flickering, a mansion with a fireplace, a four-poster
-- bed and a dining table set for twelve. Built from RoundMapKit (walls with trim, windows,
-- lights, furniture). One map is picked at random each round (no voting), like the original.
--
-- Layouts keep the same rooms, doors and spawns the chases were tuned on: every room has two
-- ways out so there's always somewhere to run.

local Kit = require(script.Parent.RoundMapKit)

local RoundMaps = {}

export type Built = {
	Name: string,
	Folder: Folder,
	Spawns: { CFrame },
	Size: Vector2, -- floor size (x, z) around the centre, for coin placement
}

local rgb = Kit.rgb
local at = Kit.at
local wall = Kit.wall

local folder: Folder

-- Office -------------------------------------------------------------------------------------
-- A marble corridor through the middle with four rooms on each side. Two doors per room
-- (corridor + neighbour) so there's always a way to loop away from the Murderer.
--   north: open-plan office | staff lounge | meeting room | the boss's office
--   south: storage          | office       | break room   | reception

local function buildOffice(): Built
	local W, D = 150, 110
	local WALL: Kit.WallStyle = {
		Color = rgb(218, 216, 208),
		Material = Enum.Material.Plaster,
		Base = rgb(70, 70, 75),
		Door = rgb(120, 80, 48),
	}
	local STORAGE: Kit.WallStyle = {
		Color = rgb(160, 162, 160),
		Material = Enum.Material.Concrete,
		Base = rgb(60, 60, 62),
		Crown = rgb(150, 150, 150),
	}
	local BOSS: Kit.WallStyle = { Color = rgb(70, 52, 40), Material = Enum.Material.Wood, Wainscot = rgb(50, 32, 22) }

	Kit.floor(0, 0, W, D, rgb(232, 226, 212), Enum.Material.Marble)
	Kit.ceiling(W, D, rgb(240, 240, 238))
	Kit.ceilingGrid(0, 0, W, D, 6, rgb(205, 205, 205))

	-- Outer walls (the boss and the storage room get their own panelling)
	wall(-W / 2, D / 2, 37.5, D / 2, WALL)
	wall(37.5, D / 2, W / 2, D / 2, WALL, nil, BOSS)
	wall(-W / 2, -D / 2, -37.5, -D / 2, STORAGE)
	wall(-37.5, -D / 2, W / 2, -D / 2, WALL)
	wall(-W / 2, -D / 2, -W / 2, -7, STORAGE)
	wall(-W / 2, -7, -W / 2, D / 2, WALL)
	wall(W / 2, -D / 2, W / 2, 7, WALL)
	wall(W / 2, 7, W / 2, D / 2, WALL, nil, BOSS)

	-- Corridor walls and the walls between rooms
	local roomX = { -56.25, -18.75, 18.75, 56.25 }
	wall(-W / 2, 7, 37.5, 7, WALL, roomX)
	wall(37.5, 7, W / 2, 7, BOSS, { 56.25 }, WALL)
	wall(-W / 2, -7, -37.5, -7, WALL, { -56.25 }, STORAGE)
	wall(-37.5, -7, W / 2, -7, WALL, { -18.75, 18.75, 56.25 })
	wall(-37.5, 7, -37.5, D / 2, WALL, { 31 })
	wall(0, 7, 0, D / 2, WALL, { 31 })
	wall(37.5, 7, 37.5, D / 2, BOSS, { 31 }, WALL)
	wall(-37.5, -D / 2, -37.5, -7, WALL, { -31 }, STORAGE)
	wall(0, -D / 2, 0, -7, WALL, { -31 })
	wall(37.5, -D / 2, 37.5, -7, WALL, { -31 })

	-- Room floors
	local carpet = Enum.Material.Carpet
	Kit.roomFloor(-56.25, 31, 37.5, 48, rgb(84, 96, 118), carpet)
	Kit.roomFloor(-18.75, 31, 37.5, 48, rgb(150, 110, 75), Enum.Material.WoodPlanks)
	Kit.roomFloor(18.75, 31, 37.5, 48, rgb(96, 104, 112), carpet)
	Kit.roomFloor(56.25, 31, 37.5, 48, rgb(90, 30, 32), carpet)
	Kit.roomFloor(-56.25, -31, 37.5, 48, rgb(120, 120, 118), Enum.Material.Concrete)
	Kit.roomFloor(-18.75, -31, 37.5, 48, rgb(84, 96, 118), carpet)
	Kit.checker(18.75, -31, 37.5, 48, 4.7, rgb(235, 235, 230), rgb(190, 192, 196))
	Kit.roomFloor(56.25, -31, 37.5, 48, rgb(205, 200, 190), Enum.Material.Marble)

	-- Lights: strip lights in the rooms, downlights down the corridor, bare bulbs in storage
	for x = -66, 66, 12 do
		Kit.downlight(x, 0, nil, 0.15)
	end
	for i, x in roomX do
		Kit.fluorescent(x - 9, 31, 0)
		Kit.fluorescent(x + 9, 31, 0)
		if i ~= 1 then
			Kit.fluorescent(x - 9, -31, 0)
			Kit.fluorescent(x + 9, -31, 0)
		end
	end
	Kit.pendant(-56, -20, 3, 0.7)
	Kit.pendant(-56, -42, 3, 0.7)

	-- Corridor: lift at one end, glass front doors at the other, plates over every door
	Kit.elevator(-W / 2 + 0.5, 0, -90)
	Kit.glassDoors(W / 2 - 0.5, 0, 90, "BLACKWOOD & CO.")
	Kit.exitSign(W / 2 - 0.5, 11.6, 0, 90)
	Kit.exitSign(-W / 2 + 0.5, 11.6, 4.5, -90)
	local plates =
		{ "OPEN OFFICE", "LOUNGE", "MEETING", "MR. BLACKWOOD", "STORAGE", "OFFICE B", "BREAK ROOM", "RECEPTION" }
	for i, x in roomX do
		Kit.sign(x, 10.9, 6.5, 0, plates[i], Vector2.new(4, 0.8), rgb(40, 40, 46), rgb(235, 235, 235))
		Kit.sign(x, 10.9, -6.5, 180, plates[i + 4], Vector2.new(4, 0.8), rgb(40, 40, 46), rgb(235, 235, 235))
		Kit.lightSwitch(x + 4.6, 4.5, 6.5, 0)
		Kit.lightSwitch(x - 4.6, 4.5, -6.5, 180)
	end
	Kit.bench(-37.5, 5.3, 0)
	Kit.bench(37.5, -5.3, 180)
	Kit.plant(-69, 4.8, "Tall")
	Kit.plant(69, -4.8, "Tall")
	Kit.plant(69, 4.8, "Fern")
	Kit.extinguisher(-30, 6.5, 0)
	Kit.extinguisher(30, -6.5, 180)
	Kit.corkboard(-4.5, 6.2, 6.5, 0)
	Kit.clock(0, 10.6, -6.5, 180)
	Kit.picture(-8, 6.6, -6.5, 180, "Portrait", rgb(212, 175, 80), 0.8)
	Kit.sign(-8, 4.1, -6.5, 180, "EMPLOYEE OF THE MONTH", Vector2.new(3.4, 0.6), rgb(212, 175, 80), rgb(40, 30, 10))
	Kit.trashBin(-44, -5.4)
	Kit.trashBin(44, 5.4)

	-- North 1: open-plan office, three rows of desks with partitions between them
	for _, dz in { 18, 30, 42 } do
		Kit.desk(-64, dz, 0)
		Kit.desk(-50, dz, 0)
	end
	for _, z in { 24, 36 } do
		Kit.cubicle(-64, z, 7.4, 0)
		Kit.cubicle(-50, z, 7.4, 0)
	end
	Kit.filingCabinet(-73.3, 11, -90)
	Kit.filingCabinet(-73.3, 13.2, -90)
	Kit.printer(-39.2, 12, 90)
	Kit.whiteboard(
		-56.25,
		6.6,
		54.5,
		0,
		"  TO DO:\n  - finish reports\n  - fix the lights in storage!!\n  - who keeps taking my knife?"
	)
	Kit.window(-64.25, 54.5, 0)
	Kit.window(-48.25, 54.5, 0)
	Kit.window(-74.5, 31, -90)
	Kit.clock(-74.5, 10.4, 45, -90)
	Kit.plant(-72, 52, "Bush")
	Kit.plant(-40, 52, "Tall")
	Kit.trashBin(-57, 15)
	Kit.trashBin(-57, 40)

	-- North 2: staff lounge
	Kit.rug(-18.75, 31, 24, 26, rgb(150, 40, 45), rgb(110, 25, 30))
	Kit.sofa(-18.75, 48, 0, rgb(30, 36, 48), 12)
	Kit.sofa(-32, 31, -90, rgb(30, 36, 48), 10)
	Kit.sofa(-5.5, 31, 90, rgb(30, 36, 48), 10)
	Kit.coffeeTable(-18.75, 31, 6, 4)
	Kit.floorLamp(-34.5, 40)
	Kit.floorLamp(-3, 40)
	Kit.plant(-34, 52, "Fern")
	Kit.plant(-3, 52, "Bush")
	Kit.arcade(-34, 12, -90)
	Kit.tv(-8, 8.6, 180)
	Kit.window(-29, 54.5, 0)
	Kit.window(-8.5, 54.5, 0)
	Kit.picture(-18.75, 7.4, 54.5, 0, "Sea")

	-- North 3: meeting room
	Kit.tableWithChairs(18.75, 33, 20, 7, rgb(60, 40, 28))
	Kit.projectorScreen(18.75, 8.4, 54.5, 0)
	Kit.waterCooler(34, 12)
	Kit.plant(3, 12, "Tall")
	Kit.window(5, 54.5, 0)
	Kit.window(32.5, 54.5, 0)
	Kit.whiteboard(0.5, 6.6, 45, -90, "  MEETING 3PM\n  agenda:\n  1. the missing staff\n  2. ???")
	Kit.clock(37, 10.4, 45, 90)

	-- North 4: the boss's office
	Kit.rug(56.25, 33, 22, 20, rgb(120, 30, 35), rgb(212, 175, 80))
	Kit.executiveDesk(56.25, 40, 0, "THE BOSS")
	Kit.bookshelf(73.4, 24, 90, rgb(60, 38, 25))
	Kit.bookshelf(73.4, 38, 90, rgb(60, 38, 25))
	Kit.window(74.5, 31, 90, { Curtains = rgb(110, 25, 30) })
	Kit.window(46, 54.5, 0, { Curtains = rgb(110, 25, 30) })
	Kit.window(66.5, 54.5, 0, { Curtains = rgb(110, 25, 30) })
	Kit.sofa(42, 22, -90, rgb(90, 30, 25), 10)
	Kit.coffeeTable(47.5, 22, 3, 6)
	Kit.safe(72.5, 50.5, 90)
	Kit.globe(67, 14)
	Kit.plant(40, 52, "Tall")
	Kit.floorLamp(48.5, 50, rgb(220, 190, 140))
	Kit.floorLamp(64, 50, rgb(220, 190, 140))
	Kit.picture(56.25, 8.6, 54.2, 0, "Portrait", rgb(212, 175, 80), 1.2)

	-- South 1: storage - no windows, bare bulbs, shelves of junk
	Kit.crates(-64, -24)
	Kit.crates(-50, -44)
	Kit.crates(-66, -46)
	Kit.crates(-48, -20)
	Kit.shelfUnit(-73.5, -18, -90)
	Kit.shelfUnit(-73.5, -32, -90)
	Kit.shelfUnit(-58, -53.5, 180)
	Kit.mopBucket(-42, -12)
	Kit.sign(-38, 6, -46, 90, "STAFF ONLY", Vector2.new(3, 1), rgb(200, 30, 30), rgb(255, 255, 255))

	-- South 2: office
	for _, dz in { -18, -30, -42 } do
		Kit.desk(-26, dz, 180)
		Kit.desk(-12, dz, 180)
	end
	for _, z in { -24, -36 } do
		Kit.cubicle(-26, z, 7.4, 0)
		Kit.cubicle(-12, z, 7.4, 0)
	end
	Kit.filingCabinet(-36.3, -12, -90)
	Kit.filingCabinet(-36.3, -14.2, -90)
	Kit.printer(-1.9, -48, 90)
	Kit.window(-30, -54.5, 180)
	Kit.window(-8, -54.5, 180)
	Kit.clock(-0.5, 10.4, -15, 90)
	Kit.plant(-34, -52, "Bush")
	Kit.trashBin(-19, -45)

	-- South 3: break room
	Kit.counter(15, -53.2, 24, 180, { Sink = 0, Coffee = 9, Microwave = -8 })
	Kit.window(15, -54.5, 180, { Sill = 4.6, Height = 5.5 })
	Kit.fridge(31, -53, 180)
	Kit.vending(35.5, -16, 90, rgb(200, 30, 40))
	Kit.vending(35.5, -21, 90, rgb(30, 90, 190))
	Kit.tableWithChairs(18.75, -30, 8, 5, rgb(240, 240, 240))
	Kit.trashBin(4, -48)
	Kit.plant(4, -12, "Bush")
	Kit.clock(0.5, 10.4, -20, -90)
	Kit.corkboard(0.5, 6.2, -42, -90, "MISSING\n\nDave from Accounts\n\nLast seen near the Manor")

	-- South 4: reception
	Kit.rug(56.25, -31, 30, 30, rgb(40, 70, 130), rgb(25, 45, 90))
	Kit.receptionDesk(56.25, -46, 180)
	Kit.sign(
		56.25,
		8.5,
		-54.5,
		180,
		"BLACKWOOD & CO.",
		Vector2.new(14, 2.4),
		rgb(30, 30, 34),
		rgb(212, 175, 80),
		{ Font = Enum.Font.Garamond }
	)
	Kit.sofa(56.25, -14, 0, rgb(120, 30, 35), 12)
	Kit.window(74.5, -20, 90)
	Kit.window(74.5, -42, 90)
	Kit.plant(42, -52, "Tall")
	Kit.plant(70.5, -52, "Tall")
	Kit.waterCooler(72, -11)
	Kit.armchair(69.5, -28.5, 90, rgb(120, 30, 35))
	Kit.armchair(69.5, -37.5, 90, rgb(120, 30, 35))
	Kit.sideTable(70.5, -33, true)
	Kit.clock(38, 10.4, -15, -90)
	Kit.picture(38, 7, -42, -90, "Abstract")

	local spawns = {}
	for _, x in roomX do
		table.insert(spawns, at(x, 3, 22))
		table.insert(spawns, at(x, 3, -22))
		table.insert(spawns, at(x - 6, 3, 0))
		table.insert(spawns, at(x + 6, 3, 0))
	end
	return { Name = "Office", Folder = folder, Spawns = spawns, Size = Vector2.new(W, D) }
end

-- Mansion ------------------------------------------------------------------------------------
-- A long central hall from the front doors to the fireplace, and a wing on each side:
--   west: kitchen (north) and dining room (south)
--   east: master bedroom (north) and library (south)

local function buildMansion(): Built
	local W, D = 150, 110
	local trim = rgb(232, 222, 196)
	local door = rgb(70, 40, 25)
	local HALL: Kit.WallStyle = {
		Color = rgb(110, 34, 40),
		Material = Enum.Material.Plaster,
		Wainscot = rgb(78, 48, 30),
		Crown = trim,
		Door = door,
	}
	local KITCHEN: Kit.WallStyle = {
		Color = rgb(222, 208, 160),
		Material = Enum.Material.Plaster,
		Wainscot = rgb(236, 234, 226),
		Crown = trim,
		Door = door,
	}
	local DINING: Kit.WallStyle = {
		Color = rgb(46, 78, 58),
		Material = Enum.Material.Plaster,
		Wainscot = rgb(78, 48, 30),
		Crown = trim,
		Door = door,
	}
	local BEDROOM: Kit.WallStyle = {
		Color = rgb(92, 110, 142),
		Material = Enum.Material.Plaster,
		Wainscot = rgb(226, 216, 192),
		Crown = trim,
		Door = door,
	}
	local LIBRARY: Kit.WallStyle = {
		Color = rgb(96, 66, 44),
		Material = Enum.Material.Wood,
		Wainscot = rgb(58, 36, 22),
		Crown = trim,
		Door = door,
	}

	Kit.floor(0, 0, W, D, rgb(92, 58, 36), Enum.Material.WoodPlanks)
	Kit.ceiling(W, D, rgb(196, 182, 160))

	-- Outer walls, papered per room
	wall(-W / 2, D / 2, -25, D / 2, KITCHEN)
	wall(-25, D / 2, 25, D / 2, HALL)
	wall(25, D / 2, W / 2, D / 2, BEDROOM)
	wall(-W / 2, -D / 2, -25, -D / 2, DINING)
	wall(-25, -D / 2, 25, -D / 2, HALL)
	wall(25, -D / 2, W / 2, -D / 2, LIBRARY)
	wall(-W / 2, -D / 2, -W / 2, 0, DINING)
	wall(-W / 2, 0, -W / 2, D / 2, KITCHEN)
	wall(W / 2, -D / 2, W / 2, 0, LIBRARY)
	wall(W / 2, 0, W / 2, D / 2, BEDROOM)

	-- The hall's side walls (two doors into each room) and the walls splitting each wing
	wall(-25, -D / 2, -25, 0, HALL, { -38, -15 }, DINING)
	wall(-25, 0, -25, D / 2, HALL, { 15, 38 }, KITCHEN)
	wall(25, -D / 2, 25, 0, LIBRARY, { -38, -15 }, HALL)
	wall(25, 0, 25, D / 2, BEDROOM, { 15, 38 }, HALL)
	wall(-W / 2, 0, -25, 0, KITCHEN, { -50 }, DINING)
	wall(25, 0, W / 2, 0, BEDROOM, { 50 }, LIBRARY)

	local curtains = { Curtains = rgb(120, 20, 30), Frame = rgb(232, 222, 196) }

	-- Hall --------------------------------------------------------------------------------
	Kit.checker(0, -45, 50, 20, 5, rgb(235, 230, 218), rgb(40, 38, 40))
	Kit.rug(0, 6, 12, 74, rgb(140, 22, 32), rgb(212, 175, 80))
	for z = -30, 50, 10 do
		Kit.part("Beam", Vector3.new(50, 0.8, 1), at(0, Kit.WALL_HEIGHT - 0.4, z), Kit.DARK_WOOD, Enum.Material.Wood).CanCollide =
			false
	end
	Kit.chandelier(0, -30)
	Kit.chandelier(0, 0)
	Kit.chandelier(0, 30)
	for _, z in { -26.5, 0, 26.5 } do
		Kit.sconce(-24.5, 6.6, z, Vector3.new(1, 0, 0))
		Kit.sconce(24.5, 6.6, z, Vector3.new(-1, 0, 0))
	end
	Kit.frontDoors(0, -54.5, 180)
	Kit.armor(-8, -51, 180)
	Kit.armor(8, -51, 180)
	Kit.window(-17, -54.5, 180, curtains)
	Kit.window(17, -54.5, 180, curtains)
	Kit.roundTable(0, -25, 2.6)
	Kit.grandfatherClock(-23.7, -48, -90)
	Kit.coatRack(21.5, -50)
	Kit.fireplace(0, 53, 0)
	Kit.sofa(-11, 40, -90, rgb(110, 30, 34), 10)
	Kit.sofa(11, 40, 90, rgb(110, 30, 34), 10)
	Kit.coffeeTable(0, 40, 4, 6)
	Kit.window(-17, 54.5, 0, curtains)
	Kit.window(17, 54.5, 0, curtains)
	Kit.piano(15, 8, 90)
	Kit.sideTable(-22.5, 22, true)
	Kit.sideTable(22.5, -5, true)
	Kit.picture(-24.5, 7.2, 7.5, -90, "Portrait", rgb(212, 175, 80))
	Kit.picture(24.5, 7.2, -7.5, 90, "Portrait", rgb(212, 175, 80))
	Kit.picture(24.5, 7.2, -46, 90, "Landscape", rgb(212, 175, 80))
	Kit.plant(-21, 51, "Tall")
	Kit.plant(21, 51, "Tall")

	-- Kitchen ---------------------------------------------------------------------------------
	Kit.checker(-50, 27.5, 50, 55, 4.2, rgb(240, 240, 235), rgb(30, 30, 34))
	Kit.counter(-63, 53.2, 22, 0, { KnifeBlock = -6, Coffee = 7 })
	Kit.stove(-49.5, 53.1, 0)
	Kit.counter(-38.5, 53.2, 17, 0, { Sink = 0 })
	Kit.window(-38.5, 54.5, 0, { Sill = 4.6, Height = 5.5, Frame = rgb(240, 240, 235) })
	Kit.potRail(-63, 8, 54.5, 0, 14)
	Kit.counter(-73.2, 35, 16, -90, { Microwave = 3 })
	Kit.fridge(-72.9, 20, -90)
	Kit.window(-74.5, 8, -90, { Frame = rgb(240, 240, 235) })
	Kit.kitchenIsland(-50, 30, 10, 0)
	Kit.pendant(-53, 30, 4.5)
	Kit.pendant(-47, 30, 4.5)
	Kit.downlight(-62, 14)
	Kit.downlight(-38, 14)
	Kit.downlight(-38, 42)
	Kit.trashBin(-28, 50)
	Kit.plant(-28, 4, "Fern")
	Kit.clock(-35, 10.4, 0.5, 180)

	-- Dining room -----------------------------------------------------------------------------
	Kit.roomFloor(-50, -27.5, 50, 55, rgb(120, 78, 46), Enum.Material.WoodPlanks)
	Kit.rug(-50, -28, 30, 16, rgb(46, 60, 100), rgb(212, 175, 80))
	Kit.diningTable(-50, -28, 22, 7, rgb(140, 25, 35))
	Kit.chandelier(-50, -28)
	Kit.chinaCabinet(-73.4, -28, -90)
	Kit.window(-62, -54.5, 180, curtains)
	Kit.window(-38, -54.5, 180, curtains)
	Kit.window(-74.5, -12, -90, curtains)
	Kit.window(-74.5, -44, -90, curtains)
	Kit.picture(-50, 7.4, -54.5, 180, "Landscape", rgb(212, 175, 80))
	Kit.counter(-62, -1.8, 10, 0, { Body = Kit.DARK_WOOD, Top = rgb(40, 26, 18) })
	Kit.sideTable(-28.5, -50)
	Kit.plant(-28.5, -4, "Tall")

	-- Master bedroom --------------------------------------------------------------------------
	Kit.roomFloor(50, 27.5, 50, 55, rgb(140, 100, 110), Enum.Material.Carpet)
	Kit.rug(52, 30, 18, 12, rgb(200, 170, 110), rgb(140, 30, 40))
	Kit.fourPosterBed(52, 47, 0, rgb(120, 25, 40))
	Kit.nightstand(46.5, 51.5, 0)
	Kit.nightstand(57.5, 51.5, 0)
	Kit.wardrobe(73.3, 20, 90)
	Kit.vanity(70, 53.4, 0)
	Kit.armchair(66, 30, 90, rgb(170, 140, 90))
	Kit.floorLamp(70.5, 36)
	Kit.chandelier(50, 27)
	Kit.window(35, 54.5, 0, curtains)
	Kit.window(74.5, 38, 90, curtains)
	Kit.window(74.5, 8, 90, curtains)
	Kit.picture(25.5, 7.2, 48, -90, "Sea", rgb(212, 175, 80))
	Kit.plant(28, 4, "Bush")

	-- Library ---------------------------------------------------------------------------------
	Kit.roomFloor(50, -27.5, 50, 55, rgb(80, 50, 32), Enum.Material.WoodPlanks)
	Kit.rug(50, -44, 22, 14, rgb(90, 50, 110), rgb(212, 175, 80))
	Kit.tv(50, -53.4, 180)
	Kit.sofa(50, -40, 0, rgb(40, 60, 110), 12)
	Kit.coffeeTable(50, -46.5, 6, 3)
	for _, z in { -12, -24, -36 } do
		Kit.bookshelf(73.4, z, 90, rgb(60, 38, 25))
	end
	Kit.window(74.5, -47, 90, curtains)
	Kit.window(35, -54.5, 180, curtains)
	Kit.window(66, -54.5, 180, curtains)
	Kit.armchair(33.5, -3, 0, rgb(30, 80, 60))
	Kit.armchair(40.5, -3, 0, rgb(30, 80, 60))
	Kit.sideTable(37, -2.4, true)
	Kit.globe(64, -6)
	Kit.chandelier(50, -27)
	Kit.picture(25.5, 7.2, -27, -90, "Portrait", rgb(212, 175, 80))

	local spawns = {}
	for _, z in { -40, -20, 20, 40 } do
		table.insert(spawns, at(-6, 3, z))
		table.insert(spawns, at(6, 3, z))
	end
	for _, x in { -50, 50 } do
		table.insert(spawns, at(x, 3, 15))
		table.insert(spawns, at(x, 3, -15))
		table.insert(spawns, at(x - 12, 3, 38))
		table.insert(spawns, at(x + 12, 3, -40))
	end
	return { Name = "Mansion", Folder = folder, Spawns = spawns, Size = Vector2.new(W, D) }
end

RoundMaps.Builders = {
	Office = buildOffice,
	Mansion = buildMansion,
}
RoundMaps.Names = { "Office", "Mansion" }

-- Tears down the previous round map and builds `name` (or a random one) around `center`
function RoundMaps.Build(parent: Instance, center: Vector3, name: string?): Built
	local old = parent:FindFirstChild("RoundMap")
	if old then
		old:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "RoundMap"
	Kit.Begin(folder, center)
	local chosen = name or RoundMaps.Names[math.random(1, #RoundMaps.Names)]
	local built = RoundMaps.Builders[chosen]()
	-- Everyone spawns facing the middle of the building
	for i, spawn in built.Spawns do
		built.Spawns[i] = CFrame.lookAt(spawn.Position, Vector3.new(center.X, spawn.Position.Y, center.Z))
	end
	folder.Parent = parent
	return built
end

return RoundMaps
