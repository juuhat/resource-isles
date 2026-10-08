extends SceneTree

# Headless check for island designs and the world map (docs/world-map-and-island-designs.md):
#   - the legend only puts deposits on ground they may sit on;
#   - a grid reads as drawn: an odd row's cells sit half a hex to the right, as on the game's grid;
#   - a placed design keeps its shape at any centre and in every orientation, its middle lands on
#     the centre, and it owns its land plus the coast ring around it, lagoons included;
#   - landmarks and markers move and turn with the island, and so do [heights];
#   - mistakes in a design or the world map are reported, a design's with its file line;
#   - every design in assets/world/islands loads and builds in all twelve orientations, and once
#     there is a world map, so does every island on it.
#
#   powershell -ExecutionPolicy Bypass -File tools/run_checks.ps1 -Filter island_design

const CheckWatchdog := preload("res://tools/check_watchdog.gd")
const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const IslandDesignScript := preload("res://scripts/island/island_design.gd")
const WorldMapScript := preload("res://scripts/world/world_map.gd")

# The atoll from the docs: a ring of land around a lagoon.
const ATOLL := """
[grid]
. . s s s . .
 . s g T s s .
. s g . . g s
 s S . . g s .
. s g g g s .
 . . s s s . .
"""
const ATOLL_LAND := 24
const LAGOON: Array[Vector2i] = [Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(3, 3)]

const CRASH_SITE := """
[grid]
. g g g .
 g g g g .
. g a g g
 . g g g .

[landmarks]
crashed_spaceship 2,1 1

[markers]
k9da 3,2   # beside the axe
"""

const MAP := """
[home]
design = "atoll_small"
center = Vector2i(0, 0)
start = true

[rescue]
design = "atoll_small"
center = Vector2i(-25, -57)
rotation = 3
mirror = true
name = "Rescue Atoll"
k9da = true
"""

const CENTERS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(-25, -58), Vector2i(40, 7), Vector2i(-3, -11)]

var failures := 0


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	CheckWatchdog.install(self)
	_check_legend()
	_check_layout()
	_check_atoll()
	_check_placement()
	_check_landmarks_and_markers()
	_check_heights()
	_check_design_mistakes()
	_check_world_map()
	_check_design_files()
	_check_world_map_file()
	_check_adding_islands()
	print("Island designs: PASS" if failures == 0 else "Island designs: FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)


func _check_legend() -> void:
	for character in IslandDesignScript.LEGEND:
		var entry: Dictionary = IslandDesignScript.LEGEND[character]
		var island := IslandData.new(1, 1)
		island.set_terrain(Vector2i.ZERO, entry.terrain)
		if entry.has("resource"):
			expect(island.can_place_resource(Vector2i.ZERO, entry.resource),
				"Legend '%s' puts its deposit on ground it may sit on" % character)
		if entry.has("item"):
			expect(not GameTypes.is_water(entry.terrain), "Legend '%s' puts its item on land" % character)


# In the text, row 1 is indented: the cell drawn down-left of an even-row cell must be its
# south-west neighbour in the game, and the one down-right its south-east neighbour.
func _check_layout() -> void:
	var design := IslandDesignScript.parse("[grid]\n. g .\n s r\n", "layout")
	expect(design.errors.is_empty(), "A two-row grid reads: %s" % "; ".join(design.errors))
	var top := Vector2i(1, 0)
	expect(design.land.get(top) == GameTypes.Terrain.GRASS, "The grass is at 1,0")
	expect(design.land.get(HexGridScript.neighbor(top, 4)) == GameTypes.Terrain.SAND,
		"The cell drawn down-left is the south-west neighbour")
	expect(design.land.get(HexGridScript.neighbor(top, 5)) == GameTypes.Terrain.STONE,
		"The cell drawn down-right is the south-east neighbour")
	var ragged := IslandDesignScript.parse("[grid]\n. g g g\n g\n", "ragged")
	expect(ragged.errors.is_empty() and ragged.size == Vector2i(4, 2) and ragged.land.size() == 4,
		"A short row ends in water")


func _check_atoll() -> void:
	var design := IslandDesignScript.parse(ATOLL, "atoll")
	expect(design.errors.is_empty(), "The atoll reads: %s" % "; ".join(design.errors))
	expect(design.size == Vector2i(7, 6), "The atoll is 7 x 6, not %s" % design.size)
	expect(design.land.size() == ATOLL_LAND, "The atoll has %d land cells, not %d" % [ATOLL_LAND, design.land.size()])
	expect(design.resources == {Vector2i(3, 1): GameTypes.ResourceNodeType.TREE, Vector2i(1, 3): GameTypes.ResourceNodeType.STONE},
		"The atoll has its tree and stone deposit: %s" % design.resources)
	expect(design.land.get(Vector2i(1, 3)) == GameTypes.Terrain.STONE, "The stone deposit sits on rock")
	for cell in LAGOON:
		expect(not design.land.has(cell), "%s is lagoon, not land" % cell)

	var center := Vector2i(-3, -11)
	var island := design.build(center)
	expect(design.build_errors.is_empty(), "The atoll builds: %s" % "; ".join(design.build_errors))
	var placed_land := {}
	for cell in design.land:
		var placed := design.world_cell(cell, center)
		placed_land[placed] = true
		expect(island.get_terrain(placed) == design.land[cell], "Land %s keeps its terrain" % cell)
	for cell in LAGOON:
		expect(island.get_terrain(design.world_cell(cell, center)) == GameTypes.Terrain.COAST, "Lagoon %s is coast" % cell)
	expect(island.get_resource_node_type(design.world_cell(Vector2i(3, 1), center)) == GameTypes.ResourceNodeType.TREE,
		"The tree stands where it was drawn")

	# The island owns exactly its land and the water within COAST_RINGS steps of it, as coast.
	var expected := placed_land.duplicate()
	for cell in placed_land:
		for near in ExplorationMap.cells_around(cell, IslandDesignScript.COAST_RINGS):
			expected[near] = true
	expect(island.terrain.size() == expected.size(), "The atoll owns %d cells, not %d" % [expected.size(), island.terrain.size()])
	for cell in island.terrain:
		expect(expected.has(cell), "%s belongs to the atoll" % cell)
		if not placed_land.has(cell):
			expect(island.get_terrain(cell) == GameTypes.Terrain.COAST, "Water %s around the atoll is coast" % cell)


# At even- and odd-row centres, mirrored or not and turned any way, every pair of land cells stays
# the same number of steps apart, and the middle lands on the centre.
func _check_placement() -> void:
	var design := IslandDesignScript.parse(ATOLL, "atoll")
	var cells: Array = design.land.keys()
	for center in CENTERS:
		for mirror in [false, true]:
			for rotation in 6:
				var label := "at %s, rotation %d%s" % [center, rotation, ", mirrored" if mirror else ""]
				expect(design.world_cell(design.middle(), center, rotation, mirror) == center, "The middle lands on the centre " + label)
				var placed := cells.map(func(cell: Vector2i) -> Vector2i: return design.world_cell(cell, center, rotation, mirror))
				var kept := true
				for a in cells.size():
					for b in range(a + 1, cells.size()):
						kept = kept and HexGridScript.distance(placed[a], placed[b]) == HexGridScript.distance(cells[a], cells[b])
				expect(kept, "The atoll keeps its shape " + label)

	# One turn takes the cell east of the middle north-east of the centre; mirroring takes it west.
	var east := HexGridScript.neighbor(design.middle(), 0)
	for center in CENTERS:
		expect(design.world_cell(east, center, 1) == HexGridScript.neighbor(center, 1), "One turn is 60 degrees counter-clockwise at %s" % center)
		expect(design.world_cell(east, center, 0, true) == HexGridScript.neighbor(center, 3), "Mirroring flips east and west at %s" % center)
		expect(design.world_cell(east, center, 6) == design.world_cell(east, center), "Six turns come back round at %s" % center)


func _check_landmarks_and_markers() -> void:
	var design := IslandDesignScript.parse(CRASH_SITE, "crash_site")
	expect(design.errors.is_empty(), "The crash site reads: %s" % "; ".join(design.errors))
	expect(design.landmarks.size() == 1 and design.markers.get("k9da") == Vector2i(3, 2), "The crash site has its wreck and K9-DA's spot")
	var manager := BuildingManager.new()
	for center in CENTERS:
		for mirror in [false, true]:
			for rotation in 6:
				var label := "at %s, rotation %d%s" % [center, rotation, ", mirrored" if mirror else ""]
				var island := design.build(center, rotation, mirror, manager)
				expect(design.build_errors.is_empty(), "The crash site builds %s: %s" % [label, "; ".join(design.build_errors)])
				var anchor := design.world_cell(Vector2i(2, 1), center, rotation, mirror)
				expect(island.get_building_type(anchor) == GameTypes.BuildingType.CRASHED_SPACESHIP, "The wreck moves with the island " + label)
				# Drawn at rotation 1; a mirrored island faces it the mirrored way (3 - 1).
				expect(island.get_building_rotation(anchor) == posmod((2 if mirror else 1) + rotation, 6), "The wreck turns with the island " + label)
				expect(island.get_item_type(design.world_cell(Vector2i(2, 2), center, rotation, mirror)) == GameTypes.ItemType.AXE,
					"The axe moves with the island " + label)
				var spot := design.marker_cell("k9da", center, rotation, mirror)
				expect(spot == design.world_cell(Vector2i(3, 2), center, rotation, mirror) and WorldBuilder.is_open_ground(island, spot),
					"K9-DA's spot moves with the island and is open ground " + label)
	expect(design.marker_cell("nobody", Vector2i.ZERO) == GameTypes.NO_CELL, "A missing marker has no cell")

	design.build(Vector2i.ZERO)
	expect(not design.build_errors.is_empty(), "Landmarks can't be placed without a BuildingManager")
	var on_sand := IslandDesignScript.parse("[grid]\ng s g\n[landmarks]\ncrashed_spaceship 1,0", "on_sand")
	on_sand.build(Vector2i.ZERO, 0, false, manager)
	expect(_has_error(on_sand.build_errors, "doesn't fit"), "A wreck on sand doesn't fit")
	var covered := IslandDesignScript.parse("[grid]\ng g g\n[landmarks]\ncrashed_spaceship 1,0\n[markers]\nk9da 1,0", "covered")
	covered.build(Vector2i.ZERO, 0, false, manager)
	expect(_has_error(covered.build_errors, "under a landmark"), "K9-DA's spot can't be under the wreck")


# [heights] gives land cells their own elevation, laid out like the grid; the rest keep their
# ground's usual level, and the heights move and turn with the island.
func _check_heights() -> void:
	var design := IslandDesignScript.parse("[grid]\n. g g r\n s s g\n[heights]\n. 4 . 5\n 0\n", "cliffs")
	expect(design.errors.is_empty(), "A grid with heights reads: %s" % "; ".join(design.errors))
	expect(design.heights == {Vector2i(1, 0): 4, Vector2i(3, 0): 5, Vector2i(0, 1): 0},
		"Only the cells given a height have one: %s" % design.heights)
	for mirror in [false, true]:
		for rotation in 6:
			var label := "at rotation %d%s" % [rotation, ", mirrored" if mirror else ""]
			var island := design.build(Vector2i(-3, -11), rotation, mirror)
			var at := func(cell: Vector2i) -> int: return island.get_elevation(design.world_cell(cell, Vector2i(-3, -11), rotation, mirror))
			expect(at.call(Vector2i(1, 0)) == 4 and at.call(Vector2i(3, 0)) == 5, "The cliffs move with the island " + label)
			expect(at.call(Vector2i(2, 0)) == 1 and at.call(Vector2i(1, 1)) == 0 and at.call(Vector2i(2, 1)) == 1,
				"Cells without a height keep their ground's usual level " + label)

	var manager := BuildingManager.new()
	var ledge := IslandDesignScript.parse("[grid]\ng g g\n[heights]\n3 3 3\n[landmarks]\ncrashed_spaceship 1,0", "ledge")
	ledge.build(Vector2i.ZERO, 0, false, manager)
	expect(ledge.build_errors.is_empty(), "A wreck fits on a raised plateau: %s" % "; ".join(ledge.build_errors))


func _check_design_mistakes() -> void:
	var mistakes := [
		["[grid]\n. x .\n", "isn't in the legend"],
		["[grid]\n. s .\n. s .\n", "should be indented 1"],
		["[grid]\n. ss .\n", "joined"],
		["[grid]\n.  s\n", "two spaces"],
		["[grid]\n\t. s\n", "tab"],
		["[grid]\n. s .\n[gird]\n", "unknown section [gird]"],
		[". s .\n", "needs to be in a section"],
		["# Nothing drawn yet.\n", "there is no grid"],
		["[grid]\n. s\n[grid]\n s .\n", "a second [grid]"],
		["[grid]\n. g g\n[landmarks]\nspaceship 1,0\n", "isn't a building type"],
		["[grid]\n. g g\n[landmarks]\ncrashed_spaceship 0,0\n", "isn't on the island's land"],
		["[grid]\n. g g\n[landmarks]\ncrashed_spaceship 1;0\n", "isn't a cell"],
		["[grid]\n. g g\n[landmarks]\ncrashed_spaceship 1,0 6\n", "rotation is a whole number"],
		["[grid]\n. g g\n[markers]\ndog 1,0\n", "isn't a marker"],
		["[grid]\n. g T\n[markers]\nk9da 2,0\n", "needs open ground"],
		["[grid]\n. g g\n[markers]\nk9da 1,0\nk9da 2,0\n", "a second k9da marker"],
		["[grid]\n. g g\n[heights]\n. 9 .\n", "isn't a height"],
		["[grid]\n. g g\n[heights]\n. x .\n", "isn't a height"],
		["[grid]\n. g g\n[heights]\n2 . .\n", "only land has a height"],
		["[grid]\n. g g\n[heights]\n. 2 .\n. 2\n", "should be indented 1"],
	]
	for mistake in mistakes:
		var design := IslandDesignScript.parse(mistake[0], "mistake")
		expect(_has_error(design.errors, mistake[1]), "Reports \"%s\", got: %s" % [mistake[1], "; ".join(design.errors)])
	var errors := IslandDesignScript.parse("[grid]\n. s .\n s x\n", "lines").errors
	expect(errors.size() == 1 and errors[0].begins_with("lines.island:3: "), "A mistake names its file and line: %s" % "; ".join(errors))
	expect(_has_error(IslandDesignScript.load_named("no_such_island").errors, "there is no design file"), "A missing design is reported")


func _check_world_map() -> void:
	var map := WorldMapScript.parse(MAP)
	expect(map.errors.is_empty(), "The map reads: %s" % "; ".join(map.errors))
	expect(map.placements.size() == 2 and map.placements[0].id == &"home" and map.placements[1].id == &"rescue",
		"The map keeps its islands in file order")
	if map.placements.size() == 2:
		var home: WorldMapScript.Placement = map.placements[0]
		var rescue: WorldMapScript.Placement = map.placements[1]
		expect(home.start and not home.k9da and home.rotation == 0 and not home.mirror and home.name == "", "The home island reads, with defaults")
		expect(rescue.k9da and rescue.center == Vector2i(-25, -57) and rescue.rotation == 3 and rescue.mirror and rescue.name == "Rescue Atoll",
			"The rescue island reads")

	var home_entry := "design = \"atoll_small\"\ncenter = Vector2i(0, 0)"
	var mistakes := [
		[MAP + "colour = \"red\"\n", "unknown key colour"],
		[MAP.replace("center = Vector2i(0, 0)", "center = \"0, 0\""), "center should be a Vector2i"],
		[MAP.replace(home_entry, "center = Vector2i(0, 0)"), "[home]: needs a design"],
		[MAP.replace(home_entry, "design = \"no_such_island\"\ncenter = Vector2i(0, 0)"), "there is no design no_such_island"],
		[MAP.replace("rotation = 3", "rotation = 6"), "rotation is 0 to 5"],
		[MAP.replace("center = Vector2i(-25, -57)", "center = Vector2i(0, 0)"), "[rescue]: has the same center as [home]"],
		[MAP.replace("k9da = true", "start = true"), "exactly one island needs start = true, not 2"],
		[MAP.replace("k9da = true", ""), "exactly one island needs k9da = true, not 0"],
		[MAP + "\n[home]\ndesign = \"atoll_small\"\n", "[home]: two islands have this id"],
		[MAP + "rotation = 1\n", "[rescue]: rotation is set twice"],
	]
	for mistake in mistakes:
		var broken := WorldMapScript.parse(mistake[0])
		expect(_has_error(broken.errors, mistake[1]), "Reports \"%s\", got: %s" % [mistake[1], "; ".join(broken.errors)])


func _check_design_files() -> void:
	var names := IslandDesignScript.all_names()
	expect(not names.is_empty(), "There are designs in %s" % IslandDesignScript.DIRECTORY)
	var manager := BuildingManager.new()
	for design_name in names:
		var design := IslandDesignScript.load_named(design_name)
		expect(design.errors.is_empty(), "%s loads: %s" % [design_name, "; ".join(design.errors)])
		expect(not design.land.is_empty(), "%s has land" % design_name)
		for mirror in [false, true]:
			for rotation in 6:
				design.build(Vector2i(7, 3), rotation, mirror, manager)
				expect(design.build_errors.is_empty(), "%s builds at rotation %d%s: %s"
					% [design_name, rotation, ", mirrored" if mirror else "", "; ".join(design.build_errors)])


# Skipped until there is a world map.
func _check_world_map_file() -> void:
	if not FileAccess.file_exists(WorldMapScript.PATH):
		return
	var map := WorldMapScript.load_file()
	expect(map.errors.is_empty(), "The world map reads: %s" % "; ".join(map.errors))
	var manager := BuildingManager.new()
	for placement in map.placements:
		var design := IslandDesignScript.load_named(placement.design)
		design.build(placement.center, placement.rotation, placement.mirror, manager)
		expect(design.errors.is_empty() and design.build_errors.is_empty(), "[%s] builds: %s"
			% [placement.id, "; ".join(design.errors + design.build_errors)])
		if placement.k9da:
			expect(design.markers.has("k9da"), "[%s] K9-DA's island marks where K9-DA waits" % placement.id)


# WorldBuilder.add_map_islands: a new world gets every island on the map in map order, starts on
# the start island with K9-DA at its marker, and every island starts with an empty stock. A saved
# world keeps its own islands as they were, even one the map has moved since, and gains islands
# added to the map since, but not one that would overlap an island already there.
func _check_adding_islands() -> void:
	var map_text := FileAccess.get_file_as_string(WorldMapScript.PATH)
	var map := WorldMapScript.parse(map_text)
	var manager := BuildingManager.new()
	var world := WorldData.new()
	WorldBuilder.add_map_islands(world, map, manager)
	expect(world.island_count() == map.placements.size(), "A new world gets every island on the map")
	var start: WorldMapScript.Placement = map.placements.filter(func(placement) -> bool: return placement.start)[0]
	var rescue: WorldMapScript.Placement = map.placements.filter(func(placement) -> bool: return placement.k9da)[0]
	expect(world.start_coord == start.center and world.current_coord == start.center, "A new world starts on the start island")
	var marker := IslandDesignScript.load_named(rescue.design).marker_cell("k9da", rescue.center, rescue.rotation, rescue.mirror)
	expect(world.dog_coord == rescue.center and world.dog_cell == marker, "K9-DA waits at its marker on its island")
	expect(world.get_island(start.center).island_name == "World 1", "Islands are named in map order")
	for coord: Vector2i in world.islands:
		var island: IslandData = world.islands[coord]
		expect(island.inventory.amounts.is_empty(), "%s starts with an empty stock" % island.map_id)

	var saved := WorldData.from_dict(world.to_dict(0.0), 0.0)
	saved.get_island(start.center).inventory.add_amount(GameTypes.ResourceType.WOOD, 5)
	# Moved out to open sea, where only its map id says the saved world already has it.
	var moved: WorldMapScript.Placement = map.placements[1]
	var moved_to := Vector2i(-60, 20)
	var later_text := map_text.replace("center = %s" % var_to_str(moved.center), "center = %s" % var_to_str(moved_to))
	later_text += "\n[little_atoll]\ndesign = \"atoll_small\"\ncenter = Vector2i(25, -29)\n"
	later_text += "\n[clash]\ndesign = \"atoll_small\"\ncenter = Vector2i(2, 1)\n"
	WorldBuilder.add_map_islands(saved, WorldMapScript.parse(later_text), manager)
	expect(saved.island_count() == world.island_count() + 1, "A saved world gains the new island, but not one that would overlap")
	var atoll := saved.get_island(Vector2i(25, -29))
	expect(atoll != null and atoll.map_id == &"little_atoll" and atoll.island_name == "World %d" % saved.island_count(),
		"The new island is named after the saved ones")
	expect(saved.get_island(start.center).inventory.get_amount(GameTypes.ResourceType.WOOD) == 5, "A saved island stays as saved")
	expect(saved.get_island(moved.center) != null and saved.get_island(moved.center).map_id == moved.id
		and not saved.has_island(moved_to), "A saved island stays where it was, though the map has moved it")
	expect(saved.start_coord == start.center and saved.dog_coord == rescue.center, "A saved world keeps its start and K9-DA")


func _has_error(errors: PackedStringArray, text: String) -> bool:
	for error in errors:
		if error.contains(text):
			return true
	return false
