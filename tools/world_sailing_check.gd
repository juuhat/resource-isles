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
	var origin: IslandData = game.current_island
	var anchor := GameTypes.NO_CELL
	var rotation := 0
	for local in origin.terrain:
		rotation = game.building_manager.fit_rotation(local, GameTypes.BuildingType.DOCK, origin, 0)
		if game.building_manager.can_place(local, GameTypes.BuildingType.DOCK, origin, rotation):
			anchor = local
			break
	expect(anchor != GameTypes.NO_CELL, "Dock available")
	if anchor != GameTypes.NO_CELL:
		game.renderer.place_building_at(anchor, GameTypes.BuildingType.DOCK, rotation)
		game.player_unit.place_at(origin.buildings[anchor].cells[1])
		game.player_unit.set_selected(true)
		game.boats.board()
		var boat_id: int = game.player_unit.boat_id
		var navigation: WorldNavigation = game.world_navigation
		_check_sailing_hover(game)
		var target: Vector2i = game.world.dog_coord
		var locked_point := Nav.slot_center(target)
		var locked_cell := navigation.cell_from_position(locked_point)
		expect(not navigation.inside_frontier(locked_cell), "Fog boundary blocks outer region before quest")
		expect(not game.boats.command_to(locked_cell), "Cannot command boat through locked fog")
		var radius := navigation.sailing_radius()
		game._reveal_rings(1)
		expect(not game.dog.visible, "Ring unlock alone must not reveal K9-DA")
		expect(game.world_view.is_uncharted(target), "K9-DA's island stays on the chart until approach")
		expect(navigation.sailing_radius() > radius, "Quest unlock expands navigable sea")
		await create_timer(WorldView.FRONTIER_UNROLL_SECONDS + 0.1).timeout
		expect(is_equal_approx(game.world_view._chart_material.get_shader_parameter("frontier_radius"), navigation.sailing_radius()), "Chart and navigation share boundary once the sheet rolls back")
		expect(navigation.inside_frontier(locked_cell), "First ring becomes reachable")
		var initial_position: Vector3 = game.player_unit.position
		var started: int = Time.get_ticks_msec()
		expect(game.boats.sail_to_island(target), "Route to another island")
		print("World route planning: %d ms" % (Time.get_ticks_msec() - started))
		expect(game.player_unit.position == initial_position, "Selecting island does not teleport")
		var crossed_sea := false
		var steps := 0
		while game.player_unit.is_moving() and steps < 2000:
			var before: Vector3 = game.player_unit.position
			game.player_unit._process(0.25)
			expect(before.distance_to(game.player_unit.position) <= game.player_unit.move_speed * 0.25 + 0.01, "Continuous movement across island boundaries")
			expect(game.world.current_coord == WorldData.CENTER, "Sailing does not change active inventory")
			if navigation.slot_at(game.player_unit.current_cell) == WorldData.NO_COORD:
				crossed_sea = true
				break
			steps += 1
		expect(crossed_sea, "Cross ocean outside every island grid")
		game.boats.store_position()
		game.save_game()
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
		expect(game.boats.sail_to_island(target), "Continue voyage after reload")
		steps = 0
		while game.player_unit.is_moving() and steps < 2000:
			game.player_unit._process(0.25)
			steps += 1
		expect(not game.player_unit.is_moving(), "Boat reaches destination coast")
		expect(game.world.get_island(target).sighted and game.world.get_island(target).visited, "Approach reveals and discovers island before landing")
		# The chart over the island opens in real time; K9-DA shows once it has.
		await create_timer(WorldView.CHART_REVEAL_SECONDS + 0.1).timeout
		expect(game.player_unit.boat_id == boat_id and game.dog.visible, "K9-DA appears while the player is still aboard")
		expect(not game.world_view.is_uncharted(target), "Approach opens K9-DA's chart patch")
		expect(game.stat_tracker.get_value(GameTypes.Stat.DOG_ISLAND_DISCOVERED) == 1, "Approach records the rescue island discovery")
		expect(game.world_view._labels[target].text.contains(game.world.get_island(target).island_name), "Approach reveals island name")
		var discoveries: int = game.stat_tracker.get_value(GameTypes.Stat.ISLANDS_REACHED)
		game.boats.reveal_nearby_island(game.player_unit.current_cell)
		expect(game.stat_tracker.get_value(GameTypes.Stat.ISLANDS_REACHED) == discoveries, "Repeated approach does not duplicate discovery")
		expect(game.stat_tracker.get_value(GameTypes.Stat.DOG_ISLAND_DISCOVERED) == 1, "Repeated approach does not duplicate rescue island discovery")
		var landing: Vector2i = game.boats.landing_tile()
		expect(landing != GameTypes.NO_CELL, "Reach a valid shore landing")
		var water_cell: Vector2i = game.player_unit.current_cell
		game.boats.disembark()
		expect(game.world.current_coord == target and game.current_island.visited, "Landing activates already-discovered destination")
		expect(game.stat_tracker.get_value(GameTypes.Stat.ISLANDS_REACHED) == discoveries, "Landing does not count discovery twice")
		expect(game.resource_manager.inventory == game.current_island.inventory, "Landing switches island inventory")
		expect(game.world.boats[boat_id].cell == water_cell, "Boat stays at actual destination")
		expect(game.player_unit.current_cell == landing, "Robot lands on chosen shore tile")
		# Ashore, the robot walks the new island's ground; nothing hands it that island's renderer.
		expect(game.player_unit.position.is_equal_approx(game.renderer.get_cell_center(landing)), "Robot stands on the new island's ground")
		var inland := _open_neighbor(game.current_island, landing)
		expect(inland != GameTypes.NO_CELL and game._command_unit_to(inland), "Robot walks on the new island")
		_walk(game.player_unit)
		expect(game.player_unit.current_cell == inland
			and game.player_unit.position.is_equal_approx(game.renderer.get_cell_center(inland)), "Robot keeps to the new island's ground")
		expect(game._command_unit_to(landing), "Robot walks back to its boat")
		_walk(game.player_unit)
		game.boats.board()
		expect(game.player_unit.boat_id == boat_id and game.world.boats.size() == 1, "Same boat can be reboarded on new island")
		game.boats.command_to(navigation.cell_from_position(Vector3(navigation.sailing_radius() + 500.0, Nav.SEA_Y, 0.0)))
		expect(not game.player_unit.is_moving(), "Outer fog still blocks sailing after first unlock")
		expect(game.boats.sail_to_island(WorldData.CENTER), "Plan return voyage to original island")
		for step in 2000:
			if not game.player_unit.is_moving():
				break
			game.player_unit._process(0.25)
		game.boats.disembark()
		expect(game.world.current_coord == WorldData.CENTER and game.player_unit.boat_id == -1, "Return voyage lands on original island")
		expect(game.current_island.buildings[anchor].boat_launched, "Original dock remains unchanged after round trip")
		game.boats.board()
		expect(game.player_unit.boat_id == boat_id and game.world.boats.size() == 1, "World boat identity survives full round trip")
		if OS.get_cmdline_user_args().has("--screenshot"):
			var edge: Vector2i = game.world_navigation.cell_from_position(Vector3(game.world_navigation.sailing_radius() - 150.0, Nav.SEA_Y, 0.0))
			if game.boats.command_to(edge):
				for step in 2000:
					if not game.player_unit.is_moving():
						break
					game.player_unit._process(0.25)
				await _capture(game, "world_sailing_chart", game.player_unit.position, false)
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

# Island cells are world lattice cells: each island is centred on its own slot, picking finds its
# cells (negative rows too), and every renderer draws a cell exactly where the lattice has it.
func _check_coordinates(game: Node) -> void:
	for coord in game.world.islands:
		var island: IslandData = game.world.islands[coord]
		expect(island.has_cell(HexGrid.axial_to_offset(Nav.slot_axial(coord))), "Island is centred on its slot")
		var cells: Array = island.terrain.keys()
		for cell in [cells.front(), cells[cells.size() / 2], cells.back()]:
			expect(game.world_navigation.slot_at(cell) == coord, "Island cells belong to its slot")
			expect(game.world_navigation.cell_from_position(Nav.cell_center(cell)) == cell, "World picking handles negative rows")
			var renderer: IslandRenderer = game.world_view.renderer_for(coord)
			if renderer != null:
				expect(renderer.get_water_center(cell).is_equal_approx(Nav.cell_center(cell)), "Renderer aligns exactly to shared grid")
		if game.world_view.renderer_for(coord) != null:
			_check_water_grid(game, game.world_view.renderer_for(coord))

	# One picking path for land and sea: a tile is found at its own height, open sea at the surface,
	# also right past an island's edge (where the island's own picking snaps onto its last tile).
	var home: IslandData = game.current_island
	var land := GameTypes.NO_CELL
	var row_start := Vector2i(1_000_000, 0)
	for cell in home.terrain:
		if land == GameTypes.NO_CELL and HexPathfinder.is_open(home, cell):
			land = cell
		if cell.x < row_start.x:
			row_start = cell
	expect(_pick(game, land) == land, "Picking finds a tile at its height")
	var past_edge := row_start + Vector2i.LEFT
	expect(not home.has_cell(past_edge) and _pick(game, past_edge) == past_edge, "Picking finds the sea right past an island")
	var open_sea := row_start + Vector2i.LEFT * 6
	expect(game.world_navigation.slot_at(open_sea) == WorldData.NO_COORD and _pick(game, open_sea) == open_sea, "Picking finds open sea")

	# Moving an island keeps its shape, also by an odd number of rows (where adding the offset
	# to odd-r cells directly would shear it).
	var island := IslandData.new(4, 3)
	island.set_terrain(Vector2i(1, 1), GameTypes.Terrain.GRASS)
	var before: Array = island.terrain.keys()
	var offset := Vector2i(5, -7)
	island.shift(offset)
	var after: Array = island.terrain.keys()
	for index in before.size():
		var moved: Vector3 = Nav.cell_center(after[index]) - Nav.cell_center(before[index])
		expect(moved.is_equal_approx(Nav.cell_center(after[0]) - Nav.cell_center(before[0])), "Shift moves every cell the same way")
	expect(island.get_terrain(HexGrid.shift(Vector2i(1, 1), offset)) == GameTypes.Terrain.GRASS, "Shift keeps terrain")

	# An island whose cells start on an odd row: the water shader's own grid must still line up.
	var renderer := IslandRenderer.new()
	renderer.setup(game.resource_node_database, game.building_manager)
	game.world_view.add_child(renderer)
	renderer.position = game.renderer.position
	renderer.render(island)
	_check_water_grid(game, renderer)
	renderer.queue_free()


# Steering the boat, the cursor's cell (the same single pick as on foot) moves the sailing marker
# instead of lighting tiles up, and clicking the boat's cell selects the robot.
func _check_sailing_hover(game: Node) -> void:
	var robot: PlayerUnit = game.player_unit
	var camera: Camera3D = game.camera_rig.get_camera()
	var sea := GameTypes.NO_CELL
	for cell in HexGrid.neighbors(robot.current_cell):
		if game.world_navigation.can_sail(cell, robot.boat_id):
			sea = cell
			break
	expect(sea != GameTypes.NO_CELL, "Open water beside the boat")
	game._update_hover(camera.unproject_position(game.world_view.get_cell_center(sea)))
	var marker: MeshInstance3D = game.world_view._sailing_hover
	expect(game.hovered_cell == sea and game.renderer.hovered_cell == GameTypes.NO_CELL, "Sailing hover picks the water, not a tile")
	expect(marker != null and marker.visible
		and Vector2(marker.position.x, marker.position.z).is_equal_approx(Vector2(Nav.cell_center(sea).x, Nav.cell_center(sea).z)),
		"The sailing marker sits on the hovered water")
	robot.set_selected(false)
	game._update_hover(camera.unproject_position(game.world_view.get_cell_center(robot.current_cell)))
	expect(game._try_select_unit() and robot.selected, "Clicking the boat selects the robot")


# The cell a camera-like ray toward the top of `cell` picks.
func _pick(game: Node, cell: Vector2i) -> Vector2i:
	var target: Vector3 = game.world_view.get_cell_center(cell)
	var origin := target + Vector3(0.0, 900.0, 600.0)
	return game.world_view.cell_from_ray(origin, (target - origin).normalized())


func _open_neighbor(island: IslandData, cell: Vector2i) -> Vector2i:
	for neighbor in HexGrid.neighbors(cell):
		if HexPathfinder.is_open(island, neighbor) and not island.has_item(neighbor):
			return neighbor
	return GameTypes.NO_CELL


func _walk(robot: PlayerUnit) -> void:
	for step in 400:
		if not robot.is_moving():
			return
		robot._process(0.05)
	expect(false, "The robot never arrived")


# The water shader finds the cell under each fragment in its own grid, counted from island_origin
# with odd rows shifted half a tile, and looks it up in a land mask built from the renderer's water
# frame. Emulates that lookup at the centre of every tile.
func _check_water_grid(game: Node, renderer: IslandRenderer) -> void:
	var material: ShaderMaterial = renderer._water_material
	var origin: Vector2 = material.get_shader_parameter("island_origin")
	var frame: Rect2i = renderer._water_frame()
	expect(material.get_shader_parameter("cell_count") == frame.size, "Water mask covers the frame")
	var size := renderer.cell_size
	var min_center := Vector2(INF, INF)
	for cell in renderer.island.terrain:
		var center := renderer.get_water_center(cell)
		var local := Vector2(center.x, center.z) - origin
		var shader_cell: Vector2i = game.world_navigation.cell_from_position(Vector3(local.x - size.x * 0.5, 0.0, local.y - size.y * 0.5))
		expect(shader_cell + frame.position == cell, "Water shader finds each cell under its tile")
		var row_offset := 0.5 if (shader_cell.y & 1) != 0 else 0.0
		var shader_center := Vector2((shader_cell.x + row_offset + 0.5) * size.x, (shader_cell.y * 0.75 + 0.5) * size.y)
		expect(shader_center.is_equal_approx(local), "Water shader puts each hexagon on its tile")
		min_center = min_center.min(Vector2(center.x, center.z))
	var grid_min: Vector2 = material.get_shader_parameter("grid_min")
	expect((grid_min + origin).is_equal_approx(min_center), "Water depth field starts at the island's first tile")

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
