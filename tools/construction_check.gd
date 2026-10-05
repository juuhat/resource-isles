extends SceneTree

# Headless check for robot construction. Runs the real game scene from a fresh world, unlocks the
# first buildings, and walks a blueprint through its life: placing it reserves the footprint and pays
# its cost but builds nothing (no production, no quest credit); the robot walks over and builds it on
# its own; interrupting it keeps the progress, which survives a save round-trip; the Build action
# resumes it; finishing it counts for Lay the Foundations, and once that unlocks Operate, powering it
# starts production. A cancelled
# blueprint refunds its cost.
#
# The game saves to SaveManager.SAVE_PATH as it plays, so any existing save is backed up first and
# restored at the end.
#
#   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/construction_check.gd

const GameScene := preload("res://game.tscn")
const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const HexPathfinderScript := preload("res://scripts/island/hex_pathfinder.gd")
# Seconds of real time any wait below may take before the check fails.
const TIMEOUT := 30.0

var _saved_bytes := PackedByteArray()
var _had_save := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_backup_save()
	SaveManager.delete_save()

	var game: Node = GameScene.instantiate()
	root.add_child(game)
	await process_frame

	var island: IslandData = game.current_island
	var renderer: IslandRenderer = game.renderer
	var robot: PlayerUnit = game.player_unit
	var stats: StatTracker = game.stat_tracker
	var resources: ResourceManager = game.resource_manager
	const CAMP := GameTypes.BuildingType.LOGGER_CAMP
	const QUARRY := GameTypes.BuildingType.QUARRY

	# Recover the tools and break ground, unlocking the camp and quarry.
	stats.add(GameTypes.Stat.TOOLS_COLLECTED, 3)
	stats.record_resource_gained(GameTypes.ResourceType.WOOD, 6)
	stats.record_resource_gained(GameTypes.ResourceType.STONE, 6)
	assert(game.quest_manager.is_building_unlocked(CAMP) and game.quest_manager.is_building_unlocked(QUARRY))
	resources.add_amount(GameTypes.ResourceType.WOOD, 6)
	resources.add_amount(GameTypes.ResourceType.STONE, 6)
	# Keep the wait short; the flow is the same at any build time.
	game.building_manager.get_definition(CAMP).build_seconds = 1.5

	# Place the camp a few steps from the robot so it has to walk.
	var cell := _free_cell(game, island, CAMP, robot.current_cell)
	assert(cell != GameTypes.NO_CELL, "Need a free spot for a logger camp")
	renderer.hovered_cell = cell
	game.selected_building_type = CAMP
	assert(game._try_place_selected_building(), "The camp blueprint is placed")
	assert(game.selected_building_type == game.NO_BUILDING, "Successful placement exits build mode")
	assert(not renderer.placement_preview_enabled, "Successful placement clears the preview")
	assert(island.is_under_construction(cell), "Placing puts down a blueprint")
	assert(resources.get_amount(GameTypes.ResourceType.WOOD) == 0, "The blueprint's cost is paid up front")
	assert(stats.get_value(GameTypes.Stat.LOGGER_CAMPS_BUILT) == 0, "A blueprint doesn't count as built")
	assert(_site_for(renderer, cell) != null, "The blueprint is drawn as a construction site")
	assert(robot.is_moving() and game.robot.pending_action_cell == cell, "The robot sets off to build it")

	await _frames(3)
	assert(not island.has_production_time(cell), "A blueprint doesn't produce")

	# The robot arrives and starts building by itself.
	assert(await _wait_until(func() -> bool: return game.robot.is_constructing), "The robot starts building on arrival")
	assert(game.robot.construct_cell == cell)
	await process_frame
	var wrench := robot._model.find_child("HeldWrench", true, false) as Node3D
	assert(robot._work_animations.has("build"), "The robot model has a Build clip")
	assert(robot._animation_player.current_animation == robot._work_animations["build"], "The robot plays Build")
	assert(wrench != null and wrench.visible, "The robot builds with the wrench in hand")
	assert(await _wait_until(func() -> bool: return island.get_build_progress(cell) > 0.2), "Building advances")

	# Interrupt it: send the robot away. The progress stays on the blueprint.
	var away := _open_cell_away_from(island, cell, robot.current_cell)
	assert(game._command_unit_to(away))
	assert(not game.robot.is_constructing, "Walking off pauses construction")
	var paused_at := island.get_build_progress(cell)
	assert(paused_at > 0.2 and island.is_under_construction(cell), "Interrupted progress is kept")

	# It survives a save round-trip; finished buildings from old saves have no progress key at all.
	game.save_game()
	var reloaded := WorldData.from_dict(SaveManager.read().get("world", {}), 0.0)
	var saved_island := reloaded.get_island(WorldData.CENTER)
	assert(saved_island.is_under_construction(cell), "The blueprint is saved")
	assert(absf(saved_island.get_build_progress(cell) - paused_at) < 0.05, "Its progress is saved")
	assert(not saved_island.is_under_construction(WorldBuilder.find_crashed_spaceship_cell(saved_island)),
		"Buildings without build progress load as finished")

	# Resume: send the robot back; arriving starts the Build action again.
	assert(await _wait_until(func() -> bool: return not robot.is_moving()))
	assert(game._command_unit_to(cell))
	assert(await _wait_until(func() -> bool: return not island.is_under_construction(cell)), "The robot finishes the camp")
	assert(stats.get_value(GameTypes.Stat.LOGGER_CAMPS_BUILT) == 1, "Finishing counts as built")
	assert(not game.robot.is_constructing)
	assert(_site_for(renderer, cell) == null, "The finished camp is drawn as a building")
	# The camp needs power, but hand-powering waits on Lay the Foundations (the quarry isn't built).
	robot.set_selected(true)
	game.refresh_action_bar()
	assert(game.robot._operate_action().is_empty(), "Operate is locked until Lay the Foundations")
	var completed: Dictionary = game.quest_manager.completed_to_dict()
	completed[GameTypes.QuestId.FOUNDATIONS] = true
	game.quest_manager.restore_completed(completed)
	# Once unlocked, the robot, still at its work spot, is offered Operate straight away.
	game.refresh_action_bar()
	assert(not game.robot._operate_action().is_empty(), "Operate is offered on the finished camp")
	game._on_action_pressed(GameTypes.UnitAction.OPERATE)
	assert(stats.get_value(GameTypes.Stat.BUILDINGS_OPERATED) == 1, "Operating counts for Live Wire")
	await _frames(3)
	assert(island.has_production_time(cell), "The powered camp starts its production cycle")
	game.robot.stop_operating()

	# Cancelling a blueprint refunds it.
	var quarry_cell := _free_cell(game, island, QUARRY, robot.current_cell)
	assert(quarry_cell != GameTypes.NO_CELL, "Need a free spot for a quarry")
	renderer.hovered_cell = quarry_cell
	game.selected_building_type = QUARRY
	assert(game._try_place_selected_building(), "The quarry blueprint is placed")
	assert(game.selected_building_type == game.NO_BUILDING, "Quarry placement also exits build mode")
	assert(resources.get_amount(GameTypes.ResourceType.STONE) == 0)
	game._on_building_delete_requested(quarry_cell, island)
	assert(not island.has_building(quarry_cell), "Cancelling removes the blueprint")
	assert(resources.get_amount(GameTypes.ResourceType.STONE) == 6, "Cancelling refunds the cost")
	assert(stats.get_value(GameTypes.Stat.QUARRIES_BUILT) == 0)

	root.remove_child(game)
	game.free()
	_restore_save()
	print("Construction: PASS")
	quit(0)


# A cell where building_type fits, 2+ steps from `near` but reachable from it.
func _free_cell(game: Node, island: IslandData, building_type: int, near: Vector2i) -> Vector2i:
	var search := HexPathfinderScript.search(island, near)
	var best := GameTypes.NO_CELL
	var best_cost := INF
	for cell in island.terrain.keys():
		var cost: float = search.cost.get(cell, INF)
		if cost < 2 or cost >= best_cost:
			continue
		if game.renderer._can_place_at(cell, building_type, 0) and game.building_manager.fit_rotation(cell, building_type, island, 0) == 0:
			best = cell
			best_cost = cost
	return best


func _open_cell_away_from(island: IslandData, cell: Vector2i, from: Vector2i) -> Vector2i:
	var search := HexPathfinderScript.search(island, from)
	for candidate in search.cost:
		if HexPathfinderScript.is_open(island, candidate) and not island.has_item(candidate) \
				and candidate != cell and not HexGridScript.neighbors(cell).has(candidate) and search.cost[candidate] >= 2:
			return candidate
	return GameTypes.NO_CELL


func _site_for(renderer: IslandRenderer, cell: Vector2i) -> ConstructionSite:
	for node in renderer.find_children("ConstructionSite*", "", true, false):
		if node is ConstructionSite and node.anchor_cell == cell:
			return node
	return null


func _wait_until(condition: Callable) -> bool:
	var start := Time.get_ticks_msec()
	while not condition.call():
		if Time.get_ticks_msec() - start > TIMEOUT * 1000.0:
			return false
		await process_frame
	return true


func _frames(count: int) -> void:
	for i in count:
		await process_frame


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
