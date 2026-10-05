extends SceneTree

# Version 1 saves counted each island's cells from (0, 0); version 2 keys everything by the world
# lattice. Checks that the upgrade puts every cell exactly where version 1 drew it, keeps building
# order and blueprints, moves old per-island boats into the world, and that an upgraded save
# boots. Also checks SaveManager: it reads the version 1 file only while there is no version 2
# save, never writes it, and doesn't bring it back once the save is deleted (New Game).
#
# The boot and file parts write saves, so they only run in the throwaway user:// folder that
# tools/run_checks.ps1 gives each check.

const GameScene := preload("res://game.tscn")
const Nav := preload("res://scripts/world/world_navigation.gd")
const HOME := WorldData.CENTER
# A ring-1 slot in negative rows, with an island whose middle row is odd: version 1's grid was then
# not a plain row/column shift of the world lattice.
const AWAY := Vector2i(0, -1)
const HOME_SIZE := Vector2i(5, 4)
const AWAY_SIZE := Vector2i(5, 6)
const CAMP := GameTypes.BuildingType.LOGGER_CAMP
const QUARRY := GameTypes.BuildingType.QUARRY

var failures := 0
var navigation := Nav.new()


func _initialize() -> void:
	call_deferred("_run")


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAILED: " + message)


func _run() -> void:
	_check_upgrade()
	if OS.get_environment("RESOURCE_ISLES_ISOLATED_USER_DIR") == "1":
		_remove_saves()
		await _check_boot()
		_check_files()
		_remove_saves()
	else:
		print("Save migration: boot and save file checks skipped (they run through tools/run_checks.ps1)")
	print("Save migration: PASS" if failures == 0 else "Save migration: FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)


func _check_upgrade() -> void:
	var payload := _v1_payload()
	var upgraded := SaveMigration.upgrade(payload)
	expect(upgraded.version == 2, "Upgraded to version 2")
	expect(payload.version == 1 and payload.world.islands[AWAY].has("width"), "The payload read is left as it was")

	var world: Dictionary = upgraded.world
	for coord in [HOME, AWAY]:
		var size: Vector2i = HOME_SIZE if coord == HOME else AWAY_SIZE
		var old: Dictionary = payload.world.islands[coord]
		var migrated: Dictionary = world.islands[coord]
		var expected_terrain := {}
		for local in old.terrain:
			expected_terrain[_v1_drawn_at(coord, size, local)] = old.terrain[local]
		expect(migrated.terrain == expected_terrain, "Every cell lands where version 1 drew it")
		expect(migrated.terrain.keys() == expected_terrain.keys(), "Cells keep their order")

		var camp := _v1_drawn_at(coord, size, Vector2i(1, 1))
		var quarry := _v1_drawn_at(coord, size, Vector2i(3, 2))
		var tree := _v1_drawn_at(coord, size, Vector2i(2, 1))
		expect(migrated.buildings.keys() == [quarry, camp], "Buildings keep their order")
		expect(migrated.buildings[camp].cells == [camp], "Footprints move with their buildings")
		expect(migrated.buildings[quarry].build_progress == 0.5, "Blueprints stay blueprints")
		expect(migrated.resources.keys() == [tree] and migrated.scavenged_cells.keys() == [tree], "Resources move")
		expect(migrated.items.keys() == [_v1_drawn_at(coord, size, Vector2i(1, 2))], "Items move")
		expect(migrated.next_production_times.keys() == [camp] and migrated.consumer_powered_states.keys() == [camp],
			"Timers and power state move with their building")
		expect(not migrated.has("width") and not migrated.has("height") and not migrated.has("boats"),
			"Islands lose their grid size and their own boats")

	expect(world.boats.size() == 2 and world.boats[0].cell == Vector2i(40, 3), "World boats stay")
	expect(world.boats[1].cell == _v1_drawn_at(AWAY, AWAY_SIZE, Vector2i.ZERO) and world.boats[1].yaw == 0.5,
		"Old island boats join the world")
	expect(world.piloted_boat == 1, "The robot still pilots its boat")
	expect(world.dog_cell == _v1_drawn_at(AWAY, AWAY_SIZE, Vector2i(2, 2)), "K9-DA keeps its spot")
	var unplaced := _v1_payload()
	unplaced.world.dog_cell = Vector2i(-1, -1)
	expect(SaveMigration.upgrade(unplaced).world.dog_cell == GameTypes.NO_CELL, "An unplaced K9-DA stays unplaced")

	var loaded := WorldData.from_dict(world, 0.0)
	var away := loaded.get_island(AWAY)
	expect(away.get_building_type(_v1_drawn_at(AWAY, AWAY_SIZE, Vector2i(1, 1))) == CAMP
		and away.is_under_construction(_v1_drawn_at(AWAY, AWAY_SIZE, Vector2i(3, 2))), "The upgraded world loads")
	navigation.setup(loaded)
	expect(navigation.slot_at(_v1_drawn_at(AWAY, AWAY_SIZE, Vector2i(1, 1))) == AWAY
		and navigation.slot_at(_v1_drawn_at(HOME, HOME_SIZE, Vector2i(1, 1))) == HOME, "Each island owns its cells")


# An upgraded save boots: on the island it was saved on, with its buildings drawn exactly where
# version 1 drew them and the robot back aboard its boat. The first save goes to the version 2
# file; the version 1 file stays as it was.
func _check_boot() -> void:
	_write_v1_save(_v1_payload())
	var v1_bytes := FileAccess.get_file_as_bytes(SaveManager.V1_SAVE_PATH)
	var game: Node = GameScene.instantiate()
	root.add_child(game)
	await process_frame

	var camp := _v1_drawn_at(AWAY, AWAY_SIZE, Vector2i(1, 1))
	expect(game.world.current_coord == AWAY and game.current_island == game.world.get_island(AWAY), "Boots on the island it was saved on")
	expect(game.current_island.get_building_type(camp) == CAMP, "Buildings stand where they were")
	expect(game.renderer.get_water_center(camp).is_equal_approx(_v1_drawn_position(AWAY, AWAY_SIZE, Vector2i(1, 1))),
		"The island is drawn where version 1 drew it")
	expect(game.player_unit.boat_id == 1 and game.player_unit.current_cell == _v1_drawn_at(AWAY, AWAY_SIZE, Vector2i.ZERO),
		"The robot is back aboard its boat")
	expect(FileAccess.file_exists(SaveManager.SAVE_PATH), "The game saves in version 2")
	expect(FileAccess.get_file_as_bytes(SaveManager.V1_SAVE_PATH) == v1_bytes, "The version 1 file is left as it was")
	game.queue_free()
	await process_frame


func _check_files() -> void:
	_remove_saves()
	_write_v1_save(_v1_payload())
	var v1_bytes := FileAccess.get_file_as_bytes(SaveManager.V1_SAVE_PATH)
	expect(SaveManager.has_save(), "A version 1 save counts as a save")
	var loaded := SaveManager.read()
	expect(int(loaded.get("version", 0)) == SaveManager.SAVE_VERSION, "A version 1 save is read upgraded")

	var newer := loaded.duplicate(true)
	newer.seed_value = 99
	expect(SaveManager.write(newer), "Write a version 2 save")
	expect(int(SaveManager.read().get("seed_value", 0)) == 99, "A version 2 save wins over version 1")
	expect(FileAccess.get_file_as_bytes(SaveManager.V1_SAVE_PATH) == v1_bytes, "The version 1 file is never written")

	SaveManager.delete_save()
	expect(not FileAccess.file_exists(SaveManager.SAVE_PATH), "Deleting removes the version 2 save")
	expect(FileAccess.file_exists(SaveManager.V1_SAVE_PATH), "Deleting leaves the version 1 file to older builds")
	expect(not SaveManager.has_save() and SaveManager.read().is_empty(), "A deleted save doesn't fall back to version 1")


# Where version 1 drew a cell of the island at `coord`: its grid's middle cell sat on the slot's
# centre, and every other cell kept its place around it.
func _v1_drawn_position(coord: Vector2i, size: Vector2i, local: Vector2i) -> Vector3:
	var from_middle := HexGrid.cell_center_3d(local, Nav.CELL_SIZE) - HexGrid.cell_center_3d(size / 2, Nav.CELL_SIZE)
	return Nav.slot_center(coord) + from_middle


func _v1_drawn_at(coord: Vector2i, size: Vector2i, local: Vector2i) -> Vector2i:
	return navigation.cell_from_position(_v1_drawn_position(coord, size, local))


func _v1_payload() -> Dictionary:
	var away := _v1_island(AWAY_SIZE)
	# Before the shared world, boats were kept per island.
	away.boats = {7: {cell = Vector2i(0, 0), yaw = 0.5}}
	away.piloted_boat = 7
	return {
		version = 1,
		seed_value = 1,
		stats = {},
		completed_quests = {},
		world = {
			current_coord = AWAY,
			revealed_rings = 1,
			islands = {HOME: _v1_island(HOME_SIZE), AWAY: away},
			trade_routes = [],
			boats = {0: {cell = Vector2i(40, 3), yaw = 0.0}},
			piloted_boat = -1,
			dog_coord = AWAY,
			dog_cell = Vector2i(2, 2),
			dog_rescued = false,
		},
	}


# A small version 1 island: water around grass and sand, a quarry still being built (placed first),
# a logger camp, a tree, an axe and the camp's production timer.
func _v1_island(size: Vector2i) -> Dictionary:
	var terrain := {}
	for y in size.y:
		for x in size.x:
			terrain[Vector2i(x, y)] = GameTypes.Terrain.WATER
	for cell in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(1, 2), Vector2i(2, 2)]:
		terrain[cell] = GameTypes.Terrain.GRASS
	terrain[Vector2i(3, 2)] = GameTypes.Terrain.SAND
	return {
		island_name = "Old island",
		visited = true,
		sighted = true,
		width = size.x,
		height = size.y,
		terrain = terrain,
		resources = {Vector2i(2, 1): GameTypes.ResourceNodeType.TREE},
		items = {Vector2i(1, 2): GameTypes.ItemType.AXE},
		scavenged_cells = {Vector2i(2, 1): true},
		buildings = {
			Vector2i(3, 2): {type = QUARRY, cells = [Vector2i(3, 2)], rotation = 0, build_progress = 0.5},
			Vector2i(1, 1): {type = CAMP, cells = [Vector2i(1, 1)], rotation = 0},
		},
		next_production_times = {Vector2i(1, 1): 4.0},
		next_fuel_times = {},
		generator_running_states = {},
		consumer_powered_states = {Vector2i(1, 1): true},
		inventory = {amounts = {GameTypes.ResourceType.WOOD: 7}},
	}


func _write_v1_save(payload: Dictionary) -> void:
	var file := FileAccess.open(SaveManager.V1_SAVE_PATH, FileAccess.WRITE)
	file.store_var(payload)
	file.close()


func _remove_saves() -> void:
	for path in [SaveManager.SAVE_PATH, SaveManager.TEMP_PATH, SaveManager.V1_SAVE_PATH, SaveManager.V1_TEMP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
