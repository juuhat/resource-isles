extends SceneTree

# Bakes the seed-1 world into island designs and a world map, once (step 2 of
# docs/world-map-and-island-designs.md). Today's thirteen generated islands are written to
# assets/world/islands/ and assets/world/world_map.cfg, each at the place it holds now, under the
# ids in IDS. They keep the order a new game generates them in, so the map's default names come
# out as today's "World N".
#
# Then it reads them back and checks that building every island from the map gives what the
# generator made, cell for cell: the same land, deposits, items, wreck and K9-DA's spot, and the
# same coast. The generator's coast stops at its 30 x 24 canvas, so a design may have more of it
# past that edge, and none of the canvas's deep water, which is open sea.
#
# The designs are meant to be edited by hand from here on, so it won't bake over an existing world
# map; pass --force to do it anyway. It loads no scene and touches no save.
#
#   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/bake_world_map.gd [-- --force]

const IslandDesignScript := preload("res://scripts/island/island_design.gd")
const WorldMapScript := preload("res://scripts/world/world_map.gd")

const SEED := 1
# Each island's id on the map, in the order a new game generates them, and what it's named for:
# its part in the progression (docs/rescue-metals-and-cargo.md), or the power tier planned for its
# ring (docs/island-generation.md). Rings 2 to 4 hold iron, coal and stone like ring 1 for now.
const IDS := [
	["crash_site", "Named for the wreck the robot wakes beside"],
	["iron_isle", "Named for Strike Iron, the first iron mined on the frontier"],
	["copper_isle", "Named for its copper"],
	["windward_isle", "Named for ring 1's power tier, the coastal windmill"],
	["coal_isle", "Named for ring 2's planned power tier, the coal generator"],
	["cinder_isle", "Named for ring 2's planned power tier, the coal generator"],
	["ember_isle", "Named for ring 2's planned power tier, the coal generator"],
	["oil_isle", "Named for ring 3's planned power tier, oil"],
	["tar_isle", "Named for ring 3's planned power tier, oil"],
	["seep_isle", "Named for ring 3's planned power tier, oil from seeps"],
	["crystal_isle", "Named for the rare materials planned for the outer ring"],
	["uranium_isle", "Named for the nuclear power planned for the outer ring"],
	["rim_isle", "Named for the edge of the disc, close by"],
]
const ROLES := {
	IslandProfiles.Biome.STARTER: "the crash site, where the robot starts",
	IslandProfiles.Biome.COPPER: "K9-DA's island: copper and stone",
	IslandProfiles.Biome.STONE: "iron, coal and stone",
}

var failures := 0


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	if FileAccess.file_exists(WorldMapScript.PATH) and not OS.get_cmdline_user_args().has("--force"):
		printerr("%s already exists; pass -- --force to bake over it" % WorldMapScript.PATH)
		quit(1)
		return

	var manager := BuildingManager.new()
	var world := WorldData.new()
	WorldBuilder.ensure_generated(world, SEED, manager)
	WorldBuilder.place_dog(world, SEED)
	if IDS.size() != world.island_count():
		printerr("IDS names %d islands, but the world has %d" % [IDS.size(), world.island_count()])
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(IslandDesignScript.DIRECTORY)

	var map_text := "; Every island in the world: which design, where its middle sits, and its role.\n"
	map_text += "; See docs/world-map-and-island-designs.md and scripts/world/world_map.gd.\n"
	map_text += "; Baked from the seed-1 world by tools/bake_world_map.gd; edit it by hand from here on.\n"
	var stone_designs := 0
	var index := 0
	for coord: Vector2i in world.ordered_coords():
		var island := world.get_island(coord)
		var biome := IslandProfiles.biome_for_coord(coord, SEED)
		var design_name := "starter"
		if biome == IslandProfiles.Biome.COPPER:
			design_name = "copper_01"
		elif biome == IslandProfiles.Biome.STONE:
			stone_designs += 1
			design_name = "stone_%02d" % stone_designs
		var role: String = ROLES[biome]
		var dog_cell := world.dog_cell if coord == world.dog_coord else GameTypes.NO_CELL
		var origin := _grid_origin(island)
		var header := "%s, ring %d: %s. Baked from the seed-1 world." % [island.island_name, WorldData.ring_of(coord), role]
		var file := FileAccess.open(IslandDesignScript.path_for(design_name), FileAccess.WRITE)
		file.store_string(_design_text(island, origin, dog_cell, header))
		file.close()

		# The grid is the world shifted by an even number of rows, so its middle lands at middle + origin.
		var design := IslandDesignScript.load_named(design_name)
		map_text += "\n; %s, ring %d: %s. %s.\n" % [island.island_name, WorldData.ring_of(coord), role, IDS[index][1]]
		map_text += "[%s]\n" % IDS[index][0]
		index += 1
		map_text += "design = \"%s\"\n" % design_name
		map_text += "center = %s\n" % var_to_str(design.middle() + origin)
		if coord == WorldData.CENTER:
			map_text += "start = true\n"
		if coord == world.dog_coord:
			map_text += "k9da = true\n"
		print("Baked %s (%s) as %s" % [island.island_name, coord, design_name])

	var map_file := FileAccess.open(WorldMapScript.PATH, FileAccess.WRITE)
	map_file.store_string(map_text)
	map_file.close()

	_verify(world, manager)
	print("World map bake: PASS" if failures == 0 else "World map bake: FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)


# The grid's top-left cell: the corner of the island's land, moved up a row when that row is odd.
# The grid is then the world shifted by an even number of rows, which keeps every row's column
# numbers and its half-hex indent.
func _grid_origin(island: IslandData) -> Vector2i:
	var top_left := Vector2i(1 << 30, 1 << 30)
	for cell: Vector2i in island.terrain:
		if not GameTypes.is_water(island.get_terrain(cell)):
			top_left = Vector2i(mini(top_left.x, cell.x), mini(top_left.y, cell.y))
	return Vector2i(top_left.x, top_left.y - posmod(top_left.y, 2))


func _design_text(island: IslandData, origin: Vector2i, dog_cell: Vector2i, header: String) -> String:
	var bottom_right := origin
	for cell: Vector2i in island.terrain:
		if not GameTypes.is_water(island.get_terrain(cell)):
			bottom_right = Vector2i(maxi(bottom_right.x, cell.x), maxi(bottom_right.y, cell.y))

	var text := "# %s\n[grid]\n" % header
	for row in range(bottom_right.y - origin.y + 1):
		var characters := PackedStringArray()
		for column in range(bottom_right.x - origin.x + 1):
			characters.append(_character(island, origin + Vector2i(column, row)))
		text += (" " if row % 2 == 1 else "") + " ".join(characters) + "\n"

	if not island.buildings.is_empty():
		text += "\n[landmarks]\n"
		for anchor: Vector2i in island.buildings:
			var building: Dictionary = island.buildings[anchor]
			var local := anchor - origin
			text += "%s %d,%d %d\n" % [String(GameTypes.BuildingType.find_key(building.type)).to_lower(),
				local.x, local.y, int(building.get("rotation", 0))]
	if dog_cell != GameTypes.NO_CELL:
		var local := dog_cell - origin
		text += "\n[markers]\nk9da %d,%d\n" % [local.x, local.y]
	return text


# The legend character for the cell's ground and whatever deposit or item is on it.
func _character(island: IslandData, cell: Vector2i) -> String:
	var terrain := island.get_terrain(cell)
	if GameTypes.is_water(terrain):
		return "."
	var resource := island.get_resource_node_type(cell)
	var item := island.get_item_type(cell)
	for character: String in IslandDesignScript.LEGEND:
		var entry: Dictionary = IslandDesignScript.LEGEND[character]
		if entry.terrain == terrain and entry.get("resource", -1) == resource and entry.get("item", -1) == item:
			return character
	push_error("No legend character for %s: terrain %d, deposit %d, item %d" % [cell, terrain, resource, item])
	failures += 1
	return "?"


func _verify(world: WorldData, manager: BuildingManager) -> void:
	var map := WorldMapScript.load_file()
	expect(map.errors.is_empty(), "The world map reads: %s" % "; ".join(map.errors))
	var coords := world.ordered_coords()
	expect(map.placements.size() == coords.size(), "The map has all %d islands" % coords.size())
	for index in mini(map.placements.size(), coords.size()):
		var placement: WorldMapScript.Placement = map.placements[index]
		var coord: Vector2i = coords[index]
		var expected := world.get_island(coord)
		var label := "%s (%s)" % [placement.id, expected.island_name]
		var design := IslandDesignScript.load_named(placement.design)
		expect(design.errors.is_empty(), "%s's design reads: %s" % [label, "; ".join(design.errors)])
		var built := design.build(placement.center, placement.rotation, placement.mirror, manager)
		expect(design.build_errors.is_empty(), "%s builds: %s" % [label, "; ".join(design.build_errors)])

		var mismatches := 0
		for cell: Vector2i in expected.terrain:
			var terrain := expected.get_terrain(cell)
			if terrain == GameTypes.Terrain.WATER:
				mismatches += int(built.has_cell(cell))
			else:
				mismatches += int(not built.has_cell(cell) or built.get_terrain(cell) != terrain)
		for cell: Vector2i in built.terrain:
			if not expected.has_cell(cell):
				mismatches += int(built.get_terrain(cell) != GameTypes.Terrain.COAST)
		expect(mismatches == 0, "%s has the generated island's ground (%d cells differ)" % [label, mismatches])
		expect(built.resources == expected.resources, "%s has the same deposits" % label)
		expect(built.items == expected.items, "%s has the same items" % label)
		expect(built.buildings.size() == expected.buildings.size(), "%s has the same landmarks" % label)
		for anchor: Vector2i in expected.buildings:
			var want: Dictionary = expected.buildings[anchor]
			var got: Dictionary = built.buildings.get(anchor, {})
			expect(not got.is_empty() and got.type == want.type and got.cells == want.cells
				and int(got.rotation) == int(want.get("rotation", 0)), "%s has its %s in place" % [label, want.type])
		expect(placement.start == (coord == WorldData.CENTER), "%s starts the game only if it is the centre" % label)
		expect(placement.k9da == (coord == world.dog_coord), "%s is K9-DA's island only if the dog is there" % label)
		if placement.k9da:
			expect(design.marker_cell("k9da", placement.center, placement.rotation, placement.mirror) == world.dog_cell,
				"K9-DA waits where the generated world puts it")
