extends SceneTree

const CheckWatchdog := preload("res://tools/check_watchdog.gd")
const GameScene := preload("res://game.tscn")
const Grid := preload("res://scripts/island/hex_grid.gd")
var failures := 0
var saved_bytes := PackedByteArray()
var had_save := false

func _initialize() -> void:
	CheckWatchdog.install(self)
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
	player.place_at(anchor)
	expect(game.boats.nearby_boat().is_empty(), "Cannot board from the quay two cells away")
	var approach: Dictionary = game.robot.plan_approach(berth, anchor)
	expect(not approach.is_empty() and approach.path.back() == pier, "Boat command approaches via pier")
	player.place_at(pier)
	player.set_selected(true)
	game.refresh_action_bar()
	expect(not game.boats.nearby_boat().is_empty(), "Pilot offered beside boat")
	var pilot: Array = game.boats.actions().filter(func(a: Dictionary) -> bool: return a.id == GameTypes.UnitAction.PILOT_BOAT)
	expect(pilot.size() == 1 and pilot[0].icon == BoatController.BOAT_ICON and not pilot[0].active, "Pilot shows the boat")
	# With the cargo hold open (Copper Glint), Cargo comes before the boat button aboard and ashore.
	var completed: Dictionary = game.quest_manager.completed_to_dict()
	completed[GameTypes.QuestId.COPPER_GLINT] = true
	game.quest_manager.restore_completed(completed)
	var action_ids := func() -> Array: return game.boats.actions().map(func(a: Dictionary) -> int: return a.id)
	expect(action_ids.call() == [GameTypes.UnitAction.CARGO, GameTypes.UnitAction.PILOT_BOAT], "Ashore: Cargo, then Pilot boat")
	# Once rescued, K9-DA follows the robot ashore and comes aboard with it.
	game.world.dog_rescued = true
	game.robot.sync_dog()
	expect(game.dog.is_on(island), "Rescued K9-DA follows the robot ashore")
	game._on_action_pressed(GameTypes.UnitAction.PILOT_BOAT)
	await process_frame
	expect(player.boat_id == 0 and player.current_cell == berth, "Board the boat")
	await _check_companion_aboard(game)
	expect(action_ids.call() == [GameTypes.UnitAction.CARGO, GameTypes.UnitAction.DISEMBARK], "Aboard: Cargo, then Disembark")
	var leave: Array = game.boats.actions().filter(func(a: Dictionary) -> bool: return a.id == GameTypes.UnitAction.DISEMBARK)
	expect(leave.size() == 1 and leave[0].icon == BoatController.BOAT_ICON and leave[0].active, "Disembark shows the boat crossed out")
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
	expect(not game.world_navigation.can_sail(pier), "Boat cannot pass through pier")
	var sea := GameTypes.NO_CELL
	for cell in island.terrain:
		if game.world_navigation.can_sail(cell, 0) and not game.world_navigation.find_path(berth, cell, 0).is_empty() \
				and not Grid.neighbors(cell).any(func(shore: Vector2i) -> bool: return game.world_navigation.can_land(cell, shore)):
			sea = cell
			break
	expect(sea != GameTypes.NO_CELL, "Find reachable open sea")
	if sea == GameTypes.NO_CELL:
		return
	expect(game._command_unit_to(sea), "Command boat to water")
	var steps := 0
	while player.is_moving() and steps < 1000:
		player._process(0.5)
		steps += 1
	expect(player.current_cell == sea and not player.is_moving(), "Boat reaches water destination")
	expect(is_equal_approx(player.position.y, renderer.get_water_center(sea).y), "Boat floats at surface")
	game.boats.disembark()
	expect(player.boat_id == 0, "Cannot disembark at sea")
	var restored := WorldData.from_dict(game.world.to_dict(0.0), 0.0)
	expect(restored.piloted_boat == 0 and restored.boats[0].cell == sea, "Boat position and occupant survive save")
	expect(restored.get_current().buildings[anchor].boat_launched, "Launch state survives save")
	game._spawn_player_unit()
	game.robot.sync_dog()
	expect(player.boat_id == 0 and player.current_cell == sea, "Reload resumes piloting")
	expect(game.dog.mode == Dog.Mode.ABOARD and game.dog.global_position.is_equal_approx(player.companion_seat().global_position),
		"Reload puts K9-DA back aboard")
	_check_sailing_reroute(game)
	expect(game._command_unit_to(berth), "Return boat to berth")
	steps = 0
	while player.is_moving() and steps < 1000:
		player._process(0.5)
		steps += 1
	expect(game._command_unit_to(pier), "Choose pier as landing")
	game._on_action_pressed(GameTypes.UnitAction.DISEMBARK)
	expect(player.boat_id == -1 and player.current_cell == pier, "Disembark onto pier")
	expect(game.dog.mode == Dog.Mode.FOLLOWING and game.dog.is_on(island) and game.dog.rotation == Vector3.ZERO,
		"K9-DA steps ashore with the robot")
	expect(game.world.boats[0].cell == berth and game.world.piloted_boat == -1, "Boat stays parked afloat")
	# Right-clicking the boat from the quay walks out along the pier and boards it.
	player.place_at(anchor)
	expect(game._command_unit_to(berth), "Command the robot to the boat")
	steps = 0
	while player.is_moving() and steps < 1000:
		player._process(0.5)
		steps += 1
	expect(player.boat_id == 0 and player.current_cell == berth and game.world.boats.size() == 1, "Clicking the boat boards the same boat")
	game._on_building_move_requested(GameTypes.BuildingType.DOCK, anchor, island)
	game._cancel_building_move()
	await process_frame
	expect(island.buildings[anchor].boat_launched and renderer.find_children(IslandRenderer.MOORED_BOAT_NAME, "", true, false).is_empty(), "Moving/cancelling dock does not duplicate launched boat")
	# An occupied / non-neighbouring shore never qualifies as a landing.
	expect(not game.world_navigation.can_land(berth, anchor), "Landing requires immediate adjacency")
	island.resources[pier] = GameTypes.ResourceNodeType.TREE
	# A deck remains open in ground pathfinding; resource occupancy must still veto transfer.
	expect(not game.world_navigation.can_land(berth, pier), "Landing rejects resource obstacles")
	island.resources.erase(pier)
	game._on_building_delete_requested(anchor, island)
	expect(player.boat_id == 0 and player.current_cell == berth, "Removing dock leaves piloted boat afloat")

# A boat whose route gets blocked (here by another boat) re-plans around it (_reroute_unit), and one
# whose destination gets taken stops beside it instead of sailing in.
func _check_sailing_reroute(game: Node) -> void:
	var player: PlayerUnit = game.player_unit
	var navigation: WorldNavigation = game.world_navigation
	var start := player.current_cell
	var reach: Dictionary = WorldNavigation.Sailing.new(navigation, player.boat_id).search(start).cost
	var goal := GameTypes.NO_CELL
	for cell in reach:
		if reach[cell] >= 6 and reach[cell] <= 12:
			goal = cell
			break
	expect(goal != GameTypes.NO_CELL, "Open water a few cells out")
	if goal == GameTypes.NO_CELL:
		return
	var route := navigation.find_path(start, goal, player.boat_id)
	expect(game._command_unit_to(goal), "Sail out")
	var blocker: Vector2i = route[3]
	game.world.boats[99] = {cell = blocker, yaw = 0.0}
	game.robot.reroute()
	var sailed := _sail(player)
	expect(not sailed.has(blocker) and player.current_cell == goal, "A boat re-plans around a blocked cell")

	game.world.boats.erase(99)
	expect(game._command_unit_to(start), "Sail back")
	game.world.boats[99] = {cell = start, yaw = 0.0}
	game.robot.reroute()
	_sail(player)
	expect(player.current_cell != start and Grid.neighbors(start).has(player.current_cell),
		"A boat whose destination is taken stops beside it")
	game.world.boats.erase(99)


# K9-DA sits at the skiff's CompanionSpot: on the deck, inside the hull, and clear of the robot at
# the helm. (Its tail curls along the deck beside the robot's feet, so it is left out of the robot
# test: its slanted box overlaps theirs though the meshes don't touch.)
func _check_companion_aboard(game: Node) -> void:
	var dog: Dog = game.dog
	var player: PlayerUnit = game.player_unit
	var seat := player.companion_seat()
	expect(seat != null and dog.mode == Dog.Mode.ABOARD and dog.visible, "K9-DA comes aboard")
	if seat == null:
		return
	for frame in 20:
		await process_frame
	expect(dog._anim_player.current_animation == dog._sit_anim, "K9-DA sits in the boat")
	expect(dog.global_position.is_equal_approx(seat.global_position), "K9-DA sits at the CompanionSpot")
	var vessel := player._vessel
	var hull := _merge(_mesh_boxes(vessel.get_child(0), vessel))
	var robot_boxes := _mesh_boxes(player._model, vessel)
	var tail := dog._model.find_child("TailPivot", true, false)
	var on_deck := true
	var inside := true
	var clear := true
	# Paws may rest a hair into the deck boards: a hundredth of a model unit.
	var tolerance: float = game.renderer.cell_size.x / IslandRenderer.TRUE_TILE_UNITS * 0.01
	for box in _mesh_boxes(dog._model, vessel):
		on_deck = on_deck and box.position.y >= seat.position.y - tolerance
		inside = inside and box.position.x >= hull.position.x and box.end.x <= hull.end.x \
			and box.position.z >= hull.position.z and box.end.z <= hull.end.z
	for box in _mesh_boxes(dog._model, vessel, tail):
		for robot_box in robot_boxes:
			clear = clear and not box.intersects(robot_box)
	expect(on_deck, "K9-DA rests on the deck, not through it")
	expect(inside, "K9-DA fits inside the hull")
	expect(clear, "K9-DA sits clear of the robot at the helm")


# The visible meshes under `node` (skipping those under `skip`), as boxes in `frame`'s space.
func _mesh_boxes(node: Node, frame: Node3D, skip: Node = null) -> Array[AABB]:
	var to_frame := frame.global_transform.affine_inverse()
	var boxes: Array[AABB] = []
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.is_visible_in_tree() and (skip == null or not skip.is_ancestor_of(mesh)):
			boxes.append(to_frame * mesh.global_transform * mesh.get_aabb())
	return boxes


func _merge(boxes: Array[AABB]) -> AABB:
	var merged := boxes[0]
	for box in boxes:
		merged = merged.merge(box)
	return merged


# Sails until the boat stops; the cells it passed through, in order.
func _sail(player: PlayerUnit) -> Array[Vector2i]:
	var sailed: Array[Vector2i] = []
	for step in 2000:
		if not player.is_moving():
			break
		player._process(0.1)
		if sailed.is_empty() or sailed.back() != player.current_cell:
			sailed.append(player.current_cell)
	return sailed
