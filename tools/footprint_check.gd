extends SceneTree

# Headless check for multi-tile building footprints (docs/building-footprints.md):
#   - HexGrid turns an axial shape about its anchor on both row parities: a three-tile triangle
#     stays three mutually adjacent tiles at every rotation, and six turns come back round;
#   - the dock covers a sand tile, the coast tile beside it and a water berth beyond, in a line,
#     auto-rotating toward the water, and all three tiles belong to it;
#   - its model moors the salvage skiff and puts the robot's work spot on the shore tile, and the
#     robot clicked onto the pier tile walks to that spot;
#   - a building's rotation survives a save round trip, and a one-tile dock from an older save
#     grows to three tiles on load.
#
# The game writes user://savegame.sav as it plays, so any existing save is backed up first and
# restored at the end.
#
#   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/footprint_check.gd

const GameScene := preload("res://game.tscn")
const HexGridScript := preload("res://scripts/island/hex_grid.gd")

const TRIANGLE: Array[Vector2i] = [Vector2i.ZERO, HexGridScript.AXIAL_EAST, HexGridScript.AXIAL_NORTH_EAST]

var _saved_bytes := PackedByteArray()
var _had_save := false
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_backup_save()
	SaveManager.delete_save()

	_check_shapes()

	var game: Node = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	_check_dock(game)
	_check_migration(game)

	root.remove_child(game)
	game.free()
	_restore_save()
	print("Footprints: PASS" if _failures == 0 else "Footprints: FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _check_shapes() -> void:
	for anchor in [Vector2i(5, 4), Vector2i(5, 5)]:  # an even and an odd row
		for direction in 6:
			_expect(HexGridScript.footprint_cells(anchor, [HexGridScript.AXIAL_EAST], direction)[0] == HexGridScript.neighbor(anchor, direction),
				"Turning AXIAL_EAST %d steps from %s gives neighbour %d" % [direction, anchor, direction])
		for rotation in 6:
			var cells := HexGridScript.footprint_cells(anchor, TRIANGLE, rotation)
			_expect(cells[0] == anchor, "The anchor stays put")
			for a in cells:
				for b in cells:
					_expect(a == b or HexGridScript.neighbors(a).has(b),
						"Triangle tiles %s and %s touch (rotation %d, anchor %s)" % [a, b, rotation, anchor])
		_expect(HexGridScript.footprint_cells(anchor, TRIANGLE, 6) == HexGridScript.footprint_cells(anchor, TRIANGLE, 0),
			"Six turns come back round")
	for cell in [Vector2i(3, -3), Vector2i(-2, 7), Vector2i(4, 0)]:
		_expect(HexGridScript.axial_to_offset(HexGridScript.offset_to_axial(cell)) == cell, "Axial round trip for %s" % cell)


func _check_dock(game: Node) -> void:
	var island: IslandData = game.current_island
	var renderer: IslandRenderer = game.renderer
	var manager: BuildingManager = game.building_manager
	var dock := GameTypes.BuildingType.DOCK

	var anchor := Vector2i(-1, -1)
	var rotation := 0
	for cell in island.terrain.keys():
		if island.get_terrain(cell) != GameTypes.Terrain.SAND:
			continue
		var fitted := manager.fit_rotation(cell, dock, island, 0)
		if manager.can_place(cell, dock, island, fitted):
			anchor = cell
			rotation = fitted
			break
	_expect(anchor != Vector2i(-1, -1), "Some sand tile takes a dock")
	if anchor == Vector2i(-1, -1):
		return

	var cells := manager.get_footprint_cells(anchor, dock, rotation)
	_expect(cells.size() == 3 and island.get_terrain(cells[1]) == GameTypes.Terrain.COAST,
		"The dock's second tile is the coast beside its sand")
	_expect(cells.size() == 3 and island.get_terrain(cells[2]) in [GameTypes.Terrain.COAST, GameTypes.Terrain.WATER]
		and HexGridScript.neighbors(cells[1]).has(cells[2]) and not HexGridScript.neighbors(cells[0]).has(cells[2]),
		"The berth is water, straight on past the pier")
	_expect(renderer.place_building_at(anchor, dock, rotation), "The dock places")
	_expect(island.get_building_anchor_cell(cells[1]) == anchor, "The pier tile belongs to the dock")
	_expect(island.get_building_anchor_cell(cells[2]) == anchor, "The berth belongs to the dock")
	_expect(island.get_building_rotation(anchor) == rotation, "The dock keeps its rotation")

	var spot = renderer.get_work_spot(anchor)
	_expect(spot != null and renderer.world_to_cell(spot) == anchor, "The work spot is on the shore tile")
	var boats := renderer.find_children(IslandRenderer.MOORED_BOAT_NAME, "", true, false)
	_expect(boats.size() == 1, "The dock moors one boat")
	if boats.size() == 1:
		# world_to_cell takes positions in the renderer's parent space, as get_work_spot returns.
		var boat_cell := renderer.world_to_cell(renderer.position + renderer.to_local((boats[0] as Node3D).global_position))
		_expect(boat_cell == cells[2], "The boat lies on the berth tile")

	var plan: Dictionary = game._plan_approach(cells[1], game.player_unit.current_cell)
	_expect(not plan.is_empty() and plan.spot_cell == anchor, "Clicking the pier sends the robot to the shore spot")

	var restored := IslandData.from_dict(island.to_dict(0.0), 0.0)
	_expect(restored.get_building_rotation(anchor) == rotation and restored.get_building_footprint_cells(anchor) == cells,
		"Rotation and tiles survive a save round trip")
	renderer.remove_building(anchor)


# An older save holds the dock as just its sand tile.
func _check_migration(game: Node) -> void:
	var island: IslandData = game.current_island
	var manager: BuildingManager = game.building_manager
	var dock := GameTypes.BuildingType.DOCK
	for cell in island.terrain.keys():
		if manager.can_place(cell, dock, island, manager.fit_rotation(cell, dock, island, 0)):
			var old_cells: Array[Vector2i] = [cell]
			island.buildings[cell] = {type = dock, cells = old_cells}
			manager.migrate_footprints(island)
			var cells := island.get_building_footprint_cells(cell)
			_expect(cells.size() == 3 and island.get_terrain(cells[1]) == GameTypes.Terrain.COAST,
				"A one-tile dock from an old save grows onto the coast and its berth")
			island.remove_building(cell)
			return
	_expect(false, "Found a tile to test migration on")


# Like assert, but counted, so a failed run can't still report PASS.
func _expect(condition: bool, message := "check") -> void:
	if not condition:
		_failures += 1
		push_error("FAILED: " + message)


func _backup_save() -> void:
	_had_save = FileAccess.file_exists(SaveManager.SAVE_PATH)
	if _had_save:
		_saved_bytes = FileAccess.get_file_as_bytes(SaveManager.SAVE_PATH)


func _restore_save() -> void:
	SaveManager.delete_save()
	if _had_save:
		var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(_saved_bytes)
		file.close()
