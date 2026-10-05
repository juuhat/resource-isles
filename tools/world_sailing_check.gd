extends SceneTree

const GameScene := preload("res://game.tscn")
const Nav := preload("res://scripts/world/world_navigation.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAILED: " + message)

func _run() -> void:
	var had_save := FileAccess.file_exists(SaveManager.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveManager.SAVE_PATH) if had_save else PackedByteArray()
	SaveManager.delete_save()
	var game: Node = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	_check_coordinates(game)
	_check_legacy_migration()
	var origin: IslandData = game.current_island
	var anchor := Vector2i(-1, -1)
	var rotation := 0
	for local in origin.terrain:
		rotation = game.building_manager.fit_rotation(local, GameTypes.BuildingType.DOCK, origin, 0)
		if game.building_manager.can_place(local, GameTypes.BuildingType.DOCK, origin, rotation):
			anchor = local
			break
	expect(anchor != Vector2i(-1, -1), "Dock available")
	if anchor != Vector2i(-1, -1):
		game.renderer.place_building_at(anchor, GameTypes.BuildingType.DOCK, rotation)
		game.player_unit.place_at(origin.buildings[anchor].cells[1])
		game.player_unit.set_selected(true)
		game._board_boat()
		var boat_id: int = game.player_unit.boat_id
		var navigation: WorldNavigation = game.world_navigation
		var target: Vector2i = game.world.dog_coord
		var locked_point := Nav.slot_center(target)
		var locked_cell := navigation.cell_from_position(locked_point)
		expect(not navigation.inside_frontier(locked_cell), "Fog boundary blocks outer region before quest")
		expect(not game._command_boat_to(locked_cell), "Cannot command boat through locked fog")
		var radius := navigation.sailing_radius()
		game._reveal_rings(1)
		expect(not game.dog.visible, "Ring unlock alone must not reveal K9-DA")
		expect(game.world_view._fog_banks.has(target), "K9-DA's island stays fogged until approach")
		expect(navigation.sailing_radius() > radius, "Quest unlock expands navigable sea")
		expect(is_equal_approx(game.world_view._frontier_fog.material_override.get_shader_parameter("frontier_radius"), navigation.sailing_radius()), "Fog and navigation share boundary")
		expect(navigation.inside_frontier(locked_cell), "First ring becomes reachable")
		var initial_position: Vector3 = game.player_unit.position
		var started: int = Time.get_ticks_msec()
		expect(game._sail_to_island(target), "Route to another island")
		print("World route planning: %d ms" % (Time.get_ticks_msec() - started))
		expect(game.player_unit.position == initial_position, "Selecting island does not teleport")
		var crossed_sea := false
		var steps := 0
		while game.player_unit.is_moving() and steps < 2000:
			var before: Vector3 = game.player_unit.position
			game.player_unit._process(0.25)
			expect(before.distance_to(game.player_unit.position) <= game.player_unit.move_speed * 0.25 + 0.01, "Continuous movement across island boundaries")
			expect(game.world.current_coord == WorldData.CENTER, "Sailing does not change active inventory")
			if navigation.region_at(game.player_unit.current_cell).is_empty():
				crossed_sea = true
				break
			steps += 1
		expect(crossed_sea, "Cross ocean outside every island grid")
		game._store_boat_position()
		game._save_game()
		var at_sea: Vector2i = game.player_unit.current_cell
		if OS.get_cmdline_user_args().has("--screenshot"):
			await _capture(game, "world_sailing_sea", game.player_unit.position, false)
		root.remove_child(game)
		game.free()
		await process_frame
		game = GameScene.instantiate()
		root.add_child(game)
		await process_frame
		expect(game.player_unit.boat_id == boat_id and game.player_unit.current_cell == at_sea, "Reload restores boat and robot in open ocean")
		expect(game.player_unit.position.is_equal_approx(Nav.cell_center(at_sea)), "Reload does not move boat to shore")
		expect(game._sail_to_island(target), "Continue voyage after reload")
		steps = 0
		while game.player_unit.is_moving() and steps < 2000:
			game.player_unit._process(0.25)
			steps += 1
		expect(not game.player_unit.is_moving(), "Boat reaches destination coast")
		expect(game.world.get_island(target).sighted and game.world.get_island(target).visited, "Approach reveals and discovers island before landing")
		expect(game.player_unit.boat_id == boat_id and game.dog.visible, "K9-DA appears while the player is still aboard")
		expect(not game.world_view._fog_banks.has(target), "Approach clears K9-DA's island fog")
		expect(game.stat_tracker.get_value(GameTypes.Stat.DOG_ISLAND_DISCOVERED) == 1, "Approach records the rescue island discovery")
		expect(game.world_view._labels[target].text.contains(game.world.get_island(target).island_name), "Approach reveals island name")
		var discoveries: int = game.stat_tracker.get_value(GameTypes.Stat.ISLANDS_REACHED)
		game._reveal_nearby_island(game.player_unit.current_cell)
		expect(game.stat_tracker.get_value(GameTypes.Stat.ISLANDS_REACHED) == discoveries, "Repeated approach does not duplicate discovery")
		expect(game.stat_tracker.get_value(GameTypes.Stat.DOG_ISLAND_DISCOVERED) == 1, "Repeated approach does not duplicate rescue island discovery")
		var landing: Vector2i = game._landing_tile()
		expect(landing != Vector2i(-1, -1), "Reach a valid shore landing")
		var water_cell: Vector2i = game.player_unit.current_cell
		game._disembark_boat()
		expect(game.world.current_coord == target and game.current_island.visited, "Landing activates already-discovered destination")
		expect(game.stat_tracker.get_value(GameTypes.Stat.ISLANDS_REACHED) == discoveries, "Landing does not count discovery twice")
		expect(game.resource_manager.inventory == game.current_island.inventory, "Landing switches island inventory")
		expect(game.world.boats[boat_id].cell == water_cell, "Boat stays at actual destination")
		expect(game.player_unit.current_cell == Nav.world_to_local(target, game.current_island, landing), "Robot lands on chosen shore tile")
		game._board_boat()
		expect(game.player_unit.boat_id == boat_id and game.world.boats.size() == 1, "Same boat can be reboarded on new island")
		game._command_boat_to(navigation.cell_from_position(Vector3(navigation.sailing_radius() + 500.0, Nav.SEA_Y, 0.0)))
		expect(not game.player_unit.is_moving(), "Outer fog still blocks sailing after first unlock")
		expect(game._sail_to_island(WorldData.CENTER), "Plan return voyage to original island")
		for step in 2000:
			if not game.player_unit.is_moving():
				break
			game.player_unit._process(0.25)
		game._disembark_boat()
		expect(game.world.current_coord == WorldData.CENTER and game.player_unit.boat_id == -1, "Return voyage lands on original island")
		expect(game.current_island.buildings[anchor].boat_launched, "Original dock remains unchanged after round trip")
		game._board_boat()
		expect(game.player_unit.boat_id == boat_id and game.world.boats.size() == 1, "World boat identity survives full round trip")
		if OS.get_cmdline_user_args().has("--screenshot"):
			var edge: Vector2i = game.world_navigation.cell_from_position(Vector3(game.world_navigation.sailing_radius() - 150.0, Nav.SEA_Y, 0.0))
			if game._command_boat_to(edge):
				for step in 2000:
					if not game.player_unit.is_moving():
						break
					game.player_unit._process(0.25)
				await _capture(game, "world_sailing_fog", game.player_unit.position, false)
			await _capture(game, "world_sailing_overview", game.player_unit.position, true)
	root.remove_child(game)
	game.free()
	await process_frame
	SaveManager.delete_save()
	if had_save:
		var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(saved)
	print("World sailing: PASS" if failures == 0 else "World sailing: FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func _check_coordinates(game: Node) -> void:
	for coord in game.world.islands:
		var island: IslandData = game.world.islands[coord]
		for local in [Vector2i.ZERO, Vector2i(3, 3), Vector2i(4, 4), Vector2i(island.width - 1, island.height - 1)]:
			var cell := Nav.local_to_world(coord, island, local)
			expect(Nav.world_to_local(coord, island, cell) == local, "Local/world coordinates round trip")
			expect(game.world_navigation.cell_from_position(Nav.cell_center(cell)) == cell, "World picking handles negative rows")
			for neighbor in HexGrid.neighbors(local):
				expect(HexGrid.neighbors(cell).has(Nav.local_to_world(coord, island, neighbor)), "Shared lattice preserves neighbours")
			var renderer: IslandRenderer = game.world_view.renderer_for(coord)
			if renderer != null:
				expect(renderer.get_water_center(local).is_equal_approx(Nav.cell_center(cell)), "Renderer aligns exactly to shared grid")

func _check_legacy_migration() -> void:
	var old := WorldData.new()
	var island := IslandData.new(30, 24)
	island.boats[2] = {cell = Vector2i(5, 5), yaw = 1.0}
	island.piloted_boat = 2
	old.add_island(Vector2i.ZERO, island)
	var navigation := Nav.new()
	navigation.setup(old)
	navigation.migrate_boats()
	expect(old.boats.size() == 1 and old.piloted_boat == 0, "Old local boats migrate with occupant")
	expect(old.boats[0].cell == Nav.local_to_world(Vector2i.ZERO, island, Vector2i(5, 5)), "Migration preserves world location")
	navigation.migrate_boats()
	expect(old.boats.size() == 1 and island.boats.is_empty(), "Migration runs only once")

func _capture(game: Node, name: String, point: Vector3, overview: bool) -> void:
	root.size = Vector2i(1400, 900)
	game.camera_rig.center_on(point, true)
	if overview:
		game.camera_rig.toggle_overview()
		game.camera_rig._distance = game.camera_rig._target_distance
	else:
		game.camera_rig._distance = 600.0
		game.camera_rig._target_distance = 600.0
	for frame in 40:
		await process_frame
	root.get_texture().get_image().save_png("res://.godot/%s.png" % name)
