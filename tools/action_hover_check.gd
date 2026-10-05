extends SceneTree

# Headless check for robot actions from the map:
#   - with the robot selected, hovering a cell it can work (a resource node once harvesting is
#     unlocked, a building that draws power once operating is) tints the tile green; open
#     ground, a locked node or building, an unselected robot, and placement mode get the plain
#     brightened hover;
#   - right-clicking such a cell walks the robot over and starts the work on arrival (harvest
#     with the chop swing, operate), and right-clicking it again leaves the work running.
#
# The game writes user://savegame.sav as it plays, so any existing save is backed up first and
# restored at the end.
#
#   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/action_hover_check.gd

const GameScene := preload("res://game.tscn")
const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const HexPathfinderScript := preload("res://scripts/island/hex_pathfinder.gd")

var _saved_bytes := PackedByteArray()
var _had_save := false
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_backup_save()
	SaveManager.delete_save()

	var game: Node = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	var robot: PlayerUnit = game.player_unit
	var island: IslandData = game.current_island
	var tree := _tree_with_open_neighbour(game, island)
	var open := _open_cell_away_from(island, robot.current_cell, 2)

	robot.set_selected(true)
	game._refresh_action_bar()
	_expect(not _is_green(game, tree), "A node isn't actionable before harvesting is unlocked")

	_unlock(game, GameTypes.RobotUpgrade.HARVESTING)
	game._refresh_action_bar()
	_expect(_is_green(game, tree), "Hovering a node the robot can harvest tints it green")
	_expect(not _is_green(game, open), "Open ground gets the plain hover")
	robot.set_selected(false)
	game._refresh_action_bar()
	_expect(not _is_green(game, tree), "No green hover while the robot isn't selected")
	robot.set_selected(true)
	game._select_building(GameTypes.BuildingType.LOGGER_CAMP)
	_expect(not _is_green(game, tree), "No green hover while placing a building")
	game._select_no_building()
	_expect(_is_green(game, tree), "The green hover returns after placement mode")

	_command(game, tree)
	_walk(robot)
	_expect(game.is_harvesting and game.harvest_cell == tree, "Right-clicking a node starts harvesting on arrival")
	_expect(robot._work == "chop", "Harvesting a tree plays the chop swing")
	_command(game, tree)
	_expect(game.is_harvesting, "Right-clicking the node being harvested leaves it running")

	var sawmill := _place_near(game, island, robot.current_cell, GameTypes.BuildingType.SAWMILL)
	_expect(game._building_consumes_power(sawmill), "The sawmill draws power")
	_expect(not _is_green(game, sawmill), "A building isn't actionable before operating is unlocked")
	_unlock(game, GameTypes.RobotUpgrade.OPERATING)
	game._refresh_action_bar()
	_expect(_is_green(game, sawmill), "Hovering a building the robot can power tints it green")
	_command(game, sawmill)
	_walk(robot)
	_expect(not game.is_harvesting, "Walking off stops harvesting")
	_expect(game.is_operating, "Right-clicking a powered building starts operating on arrival")
	_expect(robot._work == "operate", "Operating plays the hand-PTO docking pose")

	_command(game, open)
	_walk(robot)
	_expect(not game.is_operating and not game.is_harvesting and robot._work == "",
		"Right-clicking open ground just moves")

	_check_hover_path(game)

	root.remove_child(game)
	game.free()
	_restore_save()
	print("Action hover: PASS" if _failures == 0 else "Action hover: FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _is_green(game: Node, cell: Vector2i) -> bool:
	var renderer: IslandRenderer = game.renderer
	renderer.hovered_cell = cell
	renderer.refresh_hover()
	var tile: MeshInstance3D = renderer._tiles[cell]
	return tile.material_override == renderer._action_highlight_material(game.current_island.get_terrain(cell))


func _unlock(game: Node, robot_upgrade: int) -> void:
	var completed: Dictionary = game.quest_manager.completed_to_dict()
	for quest in game.quest_manager.quests:
		for reward in quest.rewards:
			if reward.kind == GameTypes.RewardKind.ROBOT_UPGRADE \
					and reward.robot_upgrade == robot_upgrade:
				completed[quest.id] = true
	game.quest_manager.restore_completed(completed)


func _tree_with_open_neighbour(game: Node, island: IslandData) -> Vector2i:
	for cell in island.resources.keys():
		var definition = game.resource_node_database.get_definition(island.resources[cell])
		if definition.extracted_resource_type != GameTypes.ResourceType.WOOD:
			continue
		for neighbor in HexGridScript.neighbors(cell):
			if HexPathfinderScript.is_open(island, neighbor):
				return cell
	_expect(false, "Need a tree with an open neighbour")
	return GameTypes.NO_CELL


func _place_near(game: Node, island: IslandData, from: Vector2i, building_type: int) -> Vector2i:
	var steps: Dictionary = HexPathfinderScript.search(island, from).cost
	for cell in island.terrain.keys():
		if steps.get(cell, 0) >= 3 and steps[cell] < HexPathfinderScript.OBSTACLE_COST \
				and game.building_manager.can_place(cell, building_type, island):
			_expect(game.renderer.place_building_at(cell, building_type))
			return cell
	_expect(false, "Need a site for building %d" % building_type)
	return GameTypes.NO_CELL


func _open_cell_away_from(island: IslandData, from: Vector2i, min_distance: int) -> Vector2i:
	var search := HexPathfinderScript.search(island, from)
	for cell in search.cost.keys():
		if search.cost[cell] >= min_distance and search.cost[cell] < HexPathfinderScript.OBSTACLE_COST \
				and HexPathfinderScript.is_open(island, cell) and not island.has_item(cell):
			return cell
	_expect(false, "Need an open cell %d steps away" % min_distance)
	return from


# On foot, the cursor's cell (picked once for land and sea) lights its tile up on the robot's
# island, nothing out at sea, and is what clicking the robot selects it by.
func _check_hover_path(game: Node) -> void:
	var robot: PlayerUnit = game.player_unit
	var island: IslandData = game.current_island
	var land := _open_cell_away_from(island, robot.current_cell, 1)
	_hover(game, land)
	_expect(game.hovered_cell == land and game.renderer.hovered_cell == land, "Hovering a tile lights it up")
	var sea := land
	while island.has_cell(sea):
		sea += Vector2i.LEFT
	_hover(game, sea)
	_expect(game.hovered_cell == sea and game.renderer.hovered_cell == GameTypes.NO_CELL, "Hovering the sea on foot lights nothing up")
	_expect(not game.world_view._sailing_hover or not game.world_view._sailing_hover.visible, "No sailing marker on foot")
	robot.set_selected(false)
	_hover(game, robot.current_cell)
	_expect(game._try_select_unit() and robot.selected, "Clicking the robot's tile selects it")


# Moves the cursor to where `cell`'s top shows on screen.
func _hover(game: Node, cell: Vector2i) -> void:
	var camera: Camera3D = game.camera_rig.get_camera()
	game._update_hover(camera.unproject_position(game.world_view.get_cell_center(cell)))


func _command(game: Node, cell: Vector2i) -> void:
	game.hovered_cell = cell
	_expect(game._command_unit_to_hovered(), "The robot accepts the command to %s" % cell)


func _walk(robot: PlayerUnit) -> void:
	for i in 2000:
		if not robot.is_moving():
			return
		robot._process(0.05)
	_expect(false, "The robot never arrived")


func _expect(condition: bool, message := "") -> void:
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
