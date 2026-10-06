extends SceneTree

# Headless check for multi-tile building footprints (docs/building-footprints.md):
#   - HexGrid turns an axial shape about its anchor on both row parities: a three-tile triangle
#     stays three mutually adjacent tiles at every rotation, and six turns come back round;
#   - the dock covers a sand tile, the coast tile beside it and a water berth beyond, in a line,
#     auto-rotating toward the water, and all three tiles belong to it;
#   - its model moors the salvage skiff and puts the robot's work spot on the shore tile;
#   - the built pier is a deck the robot walks out onto from the quay, at the boards' height, and
#     a robot left on it when the dock is removed is put back ashore;
#   - a building's rotation survives a save round trip, and a one-tile dock from an older save
#     grows to three tiles on load.
#
# The game saves to SaveManager.SAVE_PATH as it plays, so any existing save is backed up first and
# restored at the end.
#
#   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/footprint_check.gd

const CheckWatchdog := preload("res://tools/check_watchdog.gd")
const GameScene := preload("res://game.tscn")
const HexGridScript := preload("res://scripts/island/hex_grid.gd")

const TRIANGLE: Array[Vector2i] = [Vector2i.ZERO, HexGridScript.AXIAL_EAST, HexGridScript.AXIAL_NORTH_EAST]

var _saved_bytes := PackedByteArray()
var _had_save := false
var _failures := 0


func _initialize() -> void:
	CheckWatchdog.install(self)
	call_deferred("_run")


func _run() -> void:
	_backup_save()
	SaveManager.delete_save()

	_check_shapes()
	_check_dock_limit()

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


func _check_dock_limit() -> void:
	var manager := BuildingManager.new()
	var island := IslandData.new(10, 6)
	var other_island := IslandData.new(10, 6)
	var dock := GameTypes.BuildingType.DOCK
	var first := Vector2i(1, 2)
	var second := Vector2i(6, 2)
	for data in [island, other_island]:
		for anchor in [first, second]:
			var cells := manager.get_footprint_cells(anchor, dock)
			data.set_terrain(cells[0], GameTypes.Terrain.SAND)
			data.set_terrain(cells[1], GameTypes.Terrain.COAST)
			data.set_terrain(cells[2], GameTypes.Terrain.WATER)
	_expect(manager.can_place(first, dock, island) and manager.can_place(second, dock, island),
		"Both dock sites are valid before placement")
	_expect(manager.try_place(first, dock, island, 0, true), "First dock blueprint places")
	_expect(not manager.has_dock(island, first), "Relocation ignores the dock being moved")
	_expect(not manager.can_place(second, dock, island) and not manager.try_place(second, dock, island),
		"A blueprint blocks a second dock")
	_expect(manager.try_place(first, dock, other_island), "Another island can have its own dock")
	island.set_build_progress(first, 1.0)
	island.complete_construction(first)
	_expect(not manager.try_place(second, dock, island), "A finished dock blocks a second dock")
	var restored := IslandData.from_dict(island.to_dict(0.0), 0.0)
	_expect(not manager.can_place(second, dock, restored), "The dock limit survives saving and loading")
	_expect(manager.remove(first, island) and manager.try_place(second, dock, island),
		"Removing or lifting the dock frees its slot for relocation")
	_expect(manager.remove(second, island) and manager.try_place(first, dock, island),
		"Cancelling relocation can restore the original dock")


func _check_dock(game: Node) -> void:
	var island: IslandData = game.current_island
	var renderer: IslandRenderer = game.renderer
	var manager: BuildingManager = game.building_manager
	var dock := GameTypes.BuildingType.DOCK

	var anchor := GameTypes.NO_CELL
	var rotation := 0
	for cell in island.terrain.keys():
		if island.get_terrain(cell) != GameTypes.Terrain.SAND:
			continue
		var fitted := manager.fit_rotation(cell, dock, island, 0)
		if manager.can_place(cell, dock, island, fitted):
			anchor = cell
			rotation = fitted
			break
	_expect(anchor != GameTypes.NO_CELL, "Some sand tile takes a dock")
	if anchor == GameTypes.NO_CELL:
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

	_check_pier(game, anchor, rotation, cells)

	var restored := IslandData.from_dict(island.to_dict(0.0), 0.0)
	_expect(restored.get_building_rotation(anchor) == rotation and restored.get_building_footprint_cells(anchor) == cells,
		"Rotation and tiles survive a save round trip")
	renderer.remove_building(anchor)


# The pier is a deck: walked out onto from the quay only, at the height of its boards, and only
# once the dock is built. A robot left on it when the dock goes is put back ashore.
func _check_pier(game: Node, anchor: Vector2i, rotation: int, cells: Array[Vector2i]) -> void:
	var island: IslandData = game.current_island
	var renderer: IslandRenderer = game.renderer
	var pier := cells[1]
	var start: Vector2i = game.player_unit.current_cell

	_expect(HexPathfinder.is_walkable(island, pier) and HexPathfinder.is_open(island, pier), "The pier is walkable floor")
	_expect(not HexPathfinder.is_walkable(island, cells[2]), "The berth stays water")
	for neighbor in HexGridScript.neighbors(pier):
		if not cells.has(neighbor):
			_expect(not HexPathfinder.can_step(island, neighbor, pier), "The pier is boarded only from the quay (%s)" % neighbor)
	_expect(HexPathfinder.can_step(island, anchor, pier), "The quay steps onto the pier")
	var deck_y := renderer.get_cell_center(anchor).y + 0.1 * renderer.cell_size.x
	_expect(is_equal_approx(renderer.get_cell_center(pier).y, deck_y), "Units stand on the pier's boards")

	var plan: Dictionary = game.robot.plan_approach(pier, start)
	_expect(not plan.is_empty() and plan.spot_cell == GameTypes.NO_CELL and not plan.path.is_empty()
		and plan.path[-1] == pier and plan.path[-2] == anchor, "Clicking the pier walks the robot out onto it via the quay")
	var mid := renderer.get_cell_center(anchor).lerp(renderer.get_cell_center(pier), 0.5)
	_expect(is_equal_approx(renderer.get_step_height(anchor, pier, mid), deck_y), "Halfway out, the robot is up on the boards")

	game.player_unit.place_at(pier)
	game.robot.land_stranded_units(anchor)  # nothing to do while the dock stands
	_expect(game.player_unit.current_cell == pier, "The robot stays on a standing pier")
	var blueprint := island.detach_building(anchor)
	blueprint.build_progress = 0.5
	island.set_building_record(anchor, blueprint)
	_expect(not HexPathfinder.is_walkable(island, pier), "A blueprint dock has no pier to walk on")
	island.complete_construction(anchor)
	renderer.remove_building(anchor)
	game.robot.land_stranded_units(anchor)
	_expect(game.player_unit.current_cell == anchor, "A robot left on a removed pier goes back ashore")
	renderer.place_building_at(anchor, GameTypes.BuildingType.DOCK, rotation)
	game.player_unit.place_at(start)


# An older save holds the dock as just its sand tile.
func _check_migration(game: Node) -> void:
	var island: IslandData = game.current_island
	var manager: BuildingManager = game.building_manager
	var dock := GameTypes.BuildingType.DOCK
	for cell in island.terrain.keys():
		if manager.can_place(cell, dock, island, manager.fit_rotation(cell, dock, island, 0)):
			var old_cells: Array[Vector2i] = [cell]
			island.set_building_record(cell, {type = dock, cells = old_cells})
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
