extends SceneTree

const GameScene := preload("res://game.tscn")
const Navigation := preload("res://scripts/player/boat_navigation.gd")
const Grid := preload("res://scripts/island/hex_grid.gd")
var failures := 0
var saved_bytes := PackedByteArray()
var had_save := false

func _initialize() -> void:
	call_deferred("_run")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAILED: " + message)

func _run() -> void:
	had_save = FileAccess.file_exists(SaveManager.SAVE_PATH)
	if had_save:
		saved_bytes = FileAccess.get_file_as_bytes(SaveManager.SAVE_PATH)
	SaveManager.delete_save()
	var game := GameScene.instantiate()
	root.add_child(game)
	await process_frame
	var island: IslandData = game.current_island
	var anchor := GameTypes.NO_CELL
	var rotation := 0
	for cell in island.terrain:
		rotation = game.building_manager.fit_rotation(cell, GameTypes.BuildingType.DOCK, island, 0)
		if game.building_manager.can_place(cell, GameTypes.BuildingType.DOCK, island, rotation):
			anchor = cell
			break
	expect(anchor != GameTypes.NO_CELL, "Find a dock location")
	if anchor != GameTypes.NO_CELL:
		await _check_trip(game, anchor, rotation)
	root.remove_child(game)
	game.free()
	await process_frame
	if had_save:
		var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(saved_bytes)
	else:
		SaveManager.delete_save()
	print("Boat navigation: PASS" if failures == 0 else "Boat navigation: FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func _check_trip(game: Node, anchor: Vector2i, rotation: int) -> void:
	var island: IslandData = game.current_island
	var renderer: IslandRenderer = game.renderer
	var player: PlayerUnit = game.player_unit
	renderer.place_building_at(anchor, GameTypes.BuildingType.DOCK, rotation)
	var cells := island.get_building_footprint_cells(anchor)
	var pier := cells[1]
	var berth := cells[2]
	var global_berth := WorldNavigation.local_to_world(game.world.current_coord, island, berth)
	player.place_at(anchor)
	expect(game._nearby_boat().is_empty(), "Cannot board from the quay two cells away")
	var approach: Dictionary = game._plan_approach(berth, anchor)
	expect(not approach.is_empty() and approach.path.back() == pier, "Boat command approaches via pier")
	player.place_at(pier)
	player.set_selected(true)
	game._refresh_action_bar()
	expect(not game._nearby_boat().is_empty(), "Pilot offered beside boat")
	game._on_action_pressed(game.UnitAction.PILOT_BOAT)
	await process_frame
	expect(player.boat_id == 0 and player.current_cell == global_berth, "Board the boat")
	expect(player._work == "operate" and player._model.get_parent() == player._vessel, "Robot powers helm aboard")
	expect(renderer.find_children(IslandRenderer.MOORED_BOAT_NAME, "", true, false).is_empty(), "Launched boat no longer duplicated on dock")
	if OS.get_cmdline_user_args().has("--screenshot"):
		root.size = Vector2i(1200, 800)
		game.camera_rig._target_distance = CameraRig.MIN_DISTANCE
		game.camera_rig._distance = CameraRig.MIN_DISTANCE
		game.camera_rig.center_on(player.position, true)
		for frame in 30:
			await process_frame
		root.get_texture().get_image().save_png("res://.godot/boat_preview.png")
	expect(not game._command_unit_to(anchor), "Boat cannot move onto land")
	expect(not Navigation.can_sail(island, pier, 0), "Boat cannot pass through pier")
	var sea := GameTypes.NO_CELL
	for cell in island.terrain:
		if Navigation.can_sail(island, cell, 0) and not Navigation.find_path(island, berth, cell, 0).is_empty() \
				and not Grid.neighbors(cell).any(func(shore: Vector2i) -> bool: return Navigation.can_land(island, cell, shore)):
			sea = cell
			break
	expect(sea != GameTypes.NO_CELL, "Find reachable open sea")
	if sea == GameTypes.NO_CELL:
		return
	expect(game._command_unit_to(sea), "Command boat to water")
	var global_sea := WorldNavigation.local_to_world(game.world.current_coord, island, sea)
	var steps := 0
	while player.is_moving() and steps < 1000:
		player._process(0.5)
		steps += 1
	expect(player.current_cell == global_sea and not player.is_moving(), "Boat reaches water destination")
	expect(is_equal_approx(player.position.y, renderer.get_water_center(sea).y), "Boat floats at surface")
	game._disembark_boat()
	expect(player.boat_id == 0, "Cannot disembark at sea")
	var restored := WorldData.from_dict(game.world.to_dict(0.0), 0.0)
	expect(restored.piloted_boat == 0 and restored.boats[0].cell == global_sea, "Boat position and occupant survive save")
	expect(restored.get_current().buildings[anchor].boat_launched, "Launch state survives save")
	game._spawn_player_unit()
	expect(player.boat_id == 0 and player.current_cell == global_sea, "Reload resumes piloting")
	expect(game._command_unit_to(berth), "Return boat to berth")
	steps = 0
	while player.is_moving() and steps < 1000:
		player._process(0.5)
		steps += 1
	expect(game._command_unit_to(pier), "Choose pier as landing")
	game._on_action_pressed(game.UnitAction.DISEMBARK)
	expect(player.boat_id == -1 and player.current_cell == pier, "Disembark onto pier")
	expect(game.world.boats[0].cell == global_berth and game.world.piloted_boat == -1, "Boat stays parked afloat")
	game._board_boat()
	expect(player.boat_id == 0 and game.world.boats.size() == 1, "Reboard the same boat")
	game._on_building_move_requested(GameTypes.BuildingType.DOCK, anchor, island)
	game._cancel_building_move()
	await process_frame
	expect(island.buildings[anchor].boat_launched and renderer.find_children(IslandRenderer.MOORED_BOAT_NAME, "", true, false).is_empty(), "Moving/cancelling dock does not duplicate launched boat")
	# An occupied / non-neighbouring shore never qualifies as a landing.
	expect(not Navigation.can_land(island, berth, anchor), "Landing requires immediate adjacency")
	island.resources[pier] = GameTypes.ResourceNodeType.TREE
	# A deck remains open in ground pathfinding; resource occupancy must still veto transfer.
	expect(not Navigation.can_land(island, berth, pier), "Landing rejects resource obstacles")
	island.resources.erase(pier)
	game._on_building_delete_requested(anchor, island)
	expect(player.boat_id == 0 and player.current_cell == global_berth, "Removing dock leaves piloted boat afloat")
