extends SceneTree

# Headless check for robot access and clipping (TODO.md "Robot access and clipping"):
#   - pathfinding walks straight through buildings (the player can't wall the robot in) but
#     routes around resource nodes and the crashed spaceship, crossing one only when there is no
#     other way;
#   - sent somewhere new mid-step, the robot finishes the step and re-plans from there;
#   - on every island on the world map, every open tile is reachable without crossing a node;
#   - a resource node is worked from a neighbouring tile, the robot leaning toward it but clear
#     of its model;
#   - a building with a WorkSpot (the logger camp, the sawmill) is worked from its own yard,
#     reached by the shortest route straight onto its tile, then turned to face it;
#   - buildings can't be placed on the robot, and one placed on its route doesn't stop it.
#
# The game saves to SaveManager.SAVE_PATH as it plays, so any existing save is backed up first and
# restored at the end.
#
#   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/robot_access_check.gd

const CheckWatchdog := preload("res://tools/check_watchdog.gd")
const GameScene := preload("res://game.tscn")
const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const HexPathfinderScript := preload("res://scripts/island/hex_pathfinder.gd")

var _saved_bytes := PackedByteArray()
var _had_save := false
var _entered: Array[Vector2i] = []
var _failures := 0


func _initialize() -> void:
	CheckWatchdog.install(self)
	call_deferred("_run")


func _run() -> void:
	_backup_save()
	SaveManager.delete_save()

	_check_pathfinder()

	var game: Node = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	_check_map_islands(game)

	var robot: PlayerUnit = game.player_unit
	robot.entered_cell.connect(func(cell: Vector2i) -> void: _entered.append(cell))
	_check_resource_from_neighbour(game, robot)
	# Operate is a Lay the Foundations reward; the work-spot checks expect it on offer.
	var completed: Dictionary = game.quest_manager.completed_to_dict()
	completed[GameTypes.QuestId.FOUNDATIONS] = true
	game.quest_manager.restore_completed(completed)
	for building_type in [GameTypes.BuildingType.LOGGER_CAMP, GameTypes.BuildingType.SAWMILL]:
		_check_work_spot(game, robot, building_type)
	_check_placement_veto(game, robot)
	_check_walk_through_buildings(game, robot)

	root.remove_child(game)
	game.free()
	_restore_save()
	print("Robot access: PASS" if _failures == 0 else "Robot access: FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


# 7x7 grass islands: a wall of trees with one gap is walked around, not through; a wall of
# buildings is walked straight through; a cell sealed inside a ring of trees is still reachable,
# crossing exactly one tree.
func _check_pathfinder() -> void:
	var island := _grass_island()
	for y in range(0, 6):
		island.place_resource(Vector2i(3, y), GameTypes.ResourceNodeType.TREE)
	var path := HexPathfinderScript.find_path(island, Vector2i(0, 0), Vector2i(6, 0))
	_expect(not path.is_empty(), "A route exists around the tree wall")
	for cell in path:
		_expect(HexPathfinderScript.is_open(island, cell), "The route goes through the gap, not the trees")

	var walled := _grass_island()
	for y in 7:
		walled.place_building(Vector2i(3, y), GameTypes.BuildingType.LOGGER_CAMP, [Vector2i(3, y)], [GameTypes.Terrain.GRASS])
	path = HexPathfinderScript.find_path(walled, Vector2i(0, 3), Vector2i(6, 3))
	_expect(path.size() == 6, "A wall of buildings is walked straight through, no detour")

	var wreck := _grass_island()
	wreck.place_building(Vector2i(3, 3), GameTypes.BuildingType.CRASHED_SPACESHIP, [Vector2i(3, 3)], [GameTypes.Terrain.GRASS])
	path = HexPathfinderScript.find_path(wreck, Vector2i(2, 3), Vector2i(4, 3))
	_expect(not path.is_empty() and not path.has(Vector2i(3, 3)), "The crashed spaceship is walked around, not through")

	var sealed := _grass_island()
	var center := Vector2i(3, 3)
	for neighbor in HexGridScript.neighbors(center):
		sealed.place_resource(neighbor, GameTypes.ResourceNodeType.TREE)
	path = HexPathfinderScript.find_path(sealed, Vector2i(0, 0), center)
	_expect(not path.is_empty(), "A sealed cell is still reachable as a last resort")
	var crossed := path.filter(func(cell: Vector2i) -> bool: return not HexPathfinderScript.is_open(sealed, cell))
	_expect(crossed.size() == 1, "Reaching a sealed cell crosses exactly one obstacle")


# Command the robot onto a tree: it stops beside it without crossing anything solid, can harvest
# it, and leans toward it while staying clear of its model.
func _check_resource_from_neighbour(game: Node, robot: PlayerUnit) -> void:
	var island: IslandData = game.current_island
	var renderer: IslandRenderer = game.renderer
	var start := robot.current_cell
	var search := HexPathfinderScript.search(island, start)
	var target := GameTypes.NO_CELL
	for cell in island.resources.keys():
		if HexGridScript.neighbors(cell).has(start):
			continue
		for neighbor in HexGridScript.neighbors(cell):
			if HexPathfinderScript.is_open(island, neighbor) and search.cost.get(neighbor, INF) < HexPathfinderScript.OBSTACLE_COST:
				target = cell
				break
		if target != GameTypes.NO_CELL:
			break
	_expect(target != GameTypes.NO_CELL, "Need a resource node reachable over open ground")

	_command(game, target)
	_walk(robot)
	_expect(robot.current_cell != target, "The robot doesn't walk onto a resource node")
	_expect(HexGridScript.neighbors(target).has(robot.current_cell), "It works the node from beside it")
	for cell in _entered:
		_expect(not island.has_resource(cell), "The route crosses no resource node")
	_expect(game.robot.harvestable_cell == target, "Harvest is offered for the clicked node")

	_settle(robot)
	var cell_center := renderer.get_cell_center(robot.current_cell)
	var lean := Vector2(robot.position.x - cell_center.x, robot.position.z - cell_center.z).length()
	_expect(absf(lean - RobotController.WORK_LEAN_TILES * renderer.cell_size.x) < 2.0, "It leans toward the node")
	# Forest and rock clusters are roughly round, so compare footprint radii rather than boxes.
	var node_box := _object_aabb(renderer, renderer.get_cell_center(target))
	var robot_box := _robot_aabb(robot)
	var node_center := node_box.get_center()
	var distance := Vector2(robot.position.x - node_center.x, robot.position.z - node_center.z).length()
	var gap := distance - maxf(node_box.size.x, node_box.size.z) / 2.0 - maxf(robot_box.size.x, robot_box.size.z) / 2.0
	_expect(gap > 0.0, "Leaning in, it stays clear of the node's model (gap %.1f)" % gap)

	# Clicking the same node again from beside it is instant.
	_command(game, target)
	_expect(not robot.is_moving() and game.robot.harvestable_cell == target)

	# Sent off and then back to the node mid-step: it finishes the step, comes back and parks on its
	# own tile, its model and selection cap together.
	_command(game, _open_cell_away_from(island, robot.current_cell, 4))
	robot._process(0.05)
	_expect(robot.is_moving(), "It sets off")
	_command(game, target)
	_walk(robot)
	_settle(robot)
	_expect(HexGridScript.neighbors(target).has(robot.current_cell), "Redirected mid-step, it works the node from beside it")
	_expect(game.robot.harvestable_cell == target, "Harvest is offered on arrival")
	cell_center = renderer.get_cell_center(robot.current_cell)
	lean = Vector2(robot.position.x - cell_center.x, robot.position.z - cell_center.z).length()
	_expect(lean < RobotController.WORK_LEAN_TILES * renderer.cell_size.x + 2.0,
		"Redirected mid-step, it stands on its own tile (%.1f from its centre)" % lean)


# A building's WorkSpot: the robot takes the shortest route straight onto the building's tile,
# its last step going onto the parking spot, turns to face the building, stays clear of it, can
# Operate it there, and walks off normally.
func _check_work_spot(game: Node, robot: PlayerUnit, building_type: int) -> void:
	var island: IslandData = game.current_island
	var renderer: IslandRenderer = game.renderer
	var steps_from_robot: Dictionary = HexPathfinderScript.search(island, robot.current_cell).cost
	var camp := GameTypes.NO_CELL
	for cell in island.terrain.keys():
		if steps_from_robot.get(cell, 0) >= 3 and steps_from_robot[cell] < HexPathfinderScript.OBSTACLE_COST \
				and game.building_manager.can_place(cell, building_type, island):
			camp = cell
			break
	var label: String = game.building_manager.get_display_name(building_type)
	_expect(camp != GameTypes.NO_CELL, "Need a %s site a few steps from the robot" % label)
	_expect(renderer.place_building_at(camp, building_type))
	var spot = renderer.get_work_spot(camp)
	_expect(spot != null, "The %s model exports a WorkSpot" % label)

	var shortest: int = HexPathfinderScript.search(island, robot.current_cell).cost[camp]
	_command(game, camp)
	_walk(robot)
	_expect(robot.current_cell == camp, "The robot parks on the %s's own tile" % label)
	_expect(_entered.size() == shortest, "It takes the shortest route straight to the %s (%d steps, shortest %d)" % [label, _entered.size(), shortest])
	_expect(Vector2(robot.position.x - spot.x, robot.position.z - spot.z).length() < 1.0, "It stands on the work spot")
	_expect(game.robot.operable_cell == camp and not game.robot._operate_action().is_empty(), "Operate is offered from the yard")
	_settle(robot)
	var center := renderer.get_cell_center(camp)
	var facing := atan2(center.x - robot.position.x, center.z - robot.position.z)
	_expect(absf(angle_difference(robot._model.rotation.y, facing)) < 0.1, "It turns to face the %s" % label)
	_expect(not _robot_aabb(robot).intersects(_object_aabb(renderer, center).grow(-1.0)),
		"In the %s yard it stays clear of the building" % label)

	var away := _open_cell_away_from(island, camp, 3)
	_command(game, away)
	_walk(robot)
	_expect(robot.current_cell == away, "It walks off from the %s" % label)


func _check_placement_veto(game: Node, robot: PlayerUnit) -> void:
	var island: IslandData = game.current_island
	var renderer: IslandRenderer = game.renderer
	for cell in island.terrain.keys():
		if game.building_manager.can_place(cell, GameTypes.BuildingType.LOGGER_CAMP, island):
			robot.place_at(cell)
			renderer.hovered_cell = cell
			_expect(not renderer.try_place_hovered_building(GameTypes.BuildingType.LOGGER_CAMP),
				"A building can't be placed on the robot")
			_expect(not island.has_building(cell))
			return
	_expect(false, "Need a placeable cell for the veto check")


# Send the robot on a long walk and drop a building on a cell along its route: it isn't stopped
# or sent around, and still crosses no resource node.
func _check_walk_through_buildings(game: Node, robot: PlayerUnit) -> void:
	var island: IslandData = game.current_island
	var renderer: IslandRenderer = game.renderer
	robot.place_at(WorldBuilder.find_spawn_cell(island))
	var goal := _open_cell_away_from(island, robot.current_cell, 6)
	_command(game, goal)
	robot._process(0.05)
	var blocked := GameTypes.NO_CELL
	var blocked_type := -1
	for cell in robot._path.slice(1, robot._path.size() - 1):
		for building_type in GameTypes.BuildingType.values():
			if game.building_manager.get_definition(building_type).player_buildable \
					and game.building_manager.can_place(cell, building_type, island):
				blocked = cell
				blocked_type = building_type
				break
		if blocked != GameTypes.NO_CELL:
			break
	if blocked == GameTypes.NO_CELL:
		print("Robot access: walk-through skipped (nothing placeable along this route)")
		return

	renderer.hovered_cell = blocked
	_expect(renderer.try_place_hovered_building(blocked_type))
	game.robot.reroute()
	_walk(robot)
	_expect(robot.current_cell == goal, "A building placed on the route doesn't stop the robot")
	_expect(_entered.has(blocked), "It walks straight through the new building")
	for cell in _entered:
		_expect(not island.has_resource(cell), "It still crosses no resource node")


# Every island on the world map: every open tile (and every tool on the ground) can be reached from
# the robot's landing spot without crossing a tree, rock or ore node, so the last-resort crossing
# never actually happens in normal play. Reports any exceptions.
func _check_map_islands(game: Node) -> void:
	var sealed := 0
	for coord: Vector2i in game.world.islands:
		var island: IslandData = game.world.islands[coord]
		var start: Vector2i = WorldBuilder.find_spawn_cell(island)
		var costs: Dictionary = HexPathfinderScript.search(island, start).cost
		for cell in island.terrain.keys():
			if not HexPathfinderScript.is_walkable(island, cell) or island.has_resource(cell) \
					or HexPathfinderScript.is_solid_building(island, cell):
				continue
			if costs.get(cell, HexPathfinderScript.OBSTACLE_COST) >= HexPathfinderScript.OBSTACLE_COST:
				sealed += 1
				_expect(not island.has_item(cell), "%s: a tool is sealed in by nodes at %s" % [island.map_id, cell])
	print("Robot access: %d islands on the map, %d land tiles sealed in by nodes" % [game.world.islands.size(), sealed])


func _grass_island() -> IslandData:
	var island := IslandData.new(7, 7)
	for y in 7:
		for x in 7:
			island.set_terrain(Vector2i(x, y), GameTypes.Terrain.GRASS)
	return island


# Like assert, but counted, so a failed run can't still report PASS.
func _expect(condition: bool, message := "check") -> void:
	if not condition:
		_failures += 1
		push_error("FAILED: " + message)


func _command(game: Node, cell: Vector2i) -> void:
	_entered.clear()
	game.hovered_cell = cell
	_expect(game._command_unit_to_hovered(), "The robot accepts the command to %s" % cell)


func _walk(robot: PlayerUnit) -> void:
	for i in 2000:
		if not robot.is_moving():
			return
		robot._process(0.05)
	_expect(false, "The robot never arrived")


func _settle(robot: PlayerUnit) -> void:
	for i in 100:
		robot._process(0.05)


func _open_cell_away_from(island: IslandData, from: Vector2i, min_distance: int) -> Vector2i:
	var search := HexPathfinderScript.search(island, from)
	for cell in search.cost.keys():
		if search.cost[cell] >= min_distance and search.cost[cell] < HexPathfinderScript.OBSTACLE_COST \
				and HexPathfinderScript.is_open(island, cell) and not island.has_item(cell):
			return cell
	_expect(false, "Need an open cell %d steps away" % min_distance)
	return from


func _robot_aabb(robot: PlayerUnit) -> AABB:
	return _merged_aabb(robot._model)


# Bounds of the map object (building or resource model) standing on the cell centred at `center`.
func _object_aabb(renderer: IslandRenderer, center: Vector3) -> AABB:
	var objects: Node3D = renderer.get_node("Objects")
	for child in objects.get_children():
		if child is Node3D and Vector2(child.global_position.x - center.x, child.global_position.z - center.z).length() < 1.0:
			return _merged_aabb(child)
	_expect(false, "No model found on the cell")
	return AABB()


func _merged_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		# Skips hidden parts, such as the robot's held tools outside a swing.
		if not (mesh as MeshInstance3D).is_visible_in_tree():
			continue
		var box: AABB = (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


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
