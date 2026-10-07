extends SceneTree

# Headless check for repairing the crashed ship's radar (docs/copper-and-the-radar.md): the robot's
# Repair action at the wreck is locked until First Melt, takes three copper ingots from the island's
# stock when it starts, can be paused and resumed (also across a save) without paying again, and
# finishing it completes Eyes on the Horizon, which reveals the first ring of islands.
#
#   powershell -ExecutionPolicy Bypass -File tools/run_checks.ps1 -Filter radar

const CheckWatchdog := preload("res://tools/check_watchdog.gd")
const GameScene := preload("res://game.tscn")
const RADAR := GameTypes.ShipPart.RADAR
const INGOT := GameTypes.ResourceType.COPPER_INGOT

var failures := 0


func _initialize() -> void:
	CheckWatchdog.install(self)
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
	await _check_repair(game)
	root.remove_child(game)
	game.free()
	await process_frame
	SaveManager.delete_save()
	if had_save:
		var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(saved)
	print("Radar repair: PASS" if failures == 0 else "Radar repair: FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)


func _check_repair(game: Node) -> void:
	var world: WorldData = game.world
	var island: IslandData = game.current_island
	var robot: RobotController = game.robot
	var wreck := WorldBuilder.find_crashed_spaceship_cell(island)
	CheckWatchdog.require(wreck != GameTypes.NO_CELL, "The start island has the wreck")
	var beside := _walkable_neighbor(island, wreck)
	CheckWatchdog.require(beside != GameTypes.NO_CELL, "The wreck can be worked from beside it")
	expect(world.revealed_rings == 0 and world.next_ship_part() == RADAR, "A new game starts with the radar broken and only the home waters open")
	expect(_sweep(game) == 0.0, "The chart shows no radar sweep while the radar is broken")

	game.player_unit.place_at(beside)
	game.player_unit.set_selected(true)
	expect(not robot.is_actionable_cell(wreck), "The wreck isn't worked before repairing is unlocked")
	_arrive_at(game, wreck)
	expect(robot._repair_action().is_empty(), "No Repair action before First Melt")

	game.quest_manager.restore_completed({GameTypes.QuestId.FIRST_MELT: true})
	expect(game.quest_manager.get_current_milestone().id == GameTypes.QuestId.EYES_ON_THE_HORIZON, "The radar lesson follows First Melt")
	expect(robot.is_actionable_cell(wreck), "With repairing unlocked the wreck lights up")
	_arrive_at(game, wreck)
	expect(not robot.is_repairing and world.ship_repairs.is_empty(), "Without copper ingots the repair doesn't start")
	expect(not robot._repair_action().is_empty(), "The Repair action is offered beside the wreck")

	island.inventory.set_amount(INGOT, 4)
	game._on_action_pressed(GameTypes.UnitAction.REPAIR)
	expect(robot.is_repairing and island.inventory.get_amount(INGOT) == 1, "Starting the repair takes three copper ingots")
	robot._update_repair(ShipRepairs.work_seconds(RADAR) * 0.5)
	expect(is_equal_approx(float(world.ship_repairs[RADAR]), 0.5), "The repair makes progress while the robot works")
	game._on_action_pressed(GameTypes.UnitAction.REPAIR)
	expect(not robot.is_repairing, "The repair can be paused")

	game.save_game()
	var reloaded := WorldData.from_dict(SaveManager.read().get("world", {}), 0.0)
	expect(is_equal_approx(float(reloaded.ship_repairs.get(RADAR, -1.0)), 0.5), "Repair progress survives a save")

	game._on_action_pressed(GameTypes.UnitAction.REPAIR)
	expect(robot.is_repairing and island.inventory.get_amount(INGOT) == 1, "Resuming doesn't pay again")
	robot._update_repair(ShipRepairs.work_seconds(RADAR))
	expect(world.is_ship_part_repaired(RADAR) and not robot.is_repairing, "Working on finishes the radar")
	expect(game.stat_tracker.get_value(GameTypes.Stat.SHIP_PARTS_REPAIRED) == 1, "The repair counts toward quests")
	expect(game.quest_manager.is_completed(GameTypes.QuestId.EYES_ON_THE_HORIZON), "Repairing the radar completes Eyes on the Horizon")
	expect(world.revealed_rings == 1, "The radar reveals the first ring of islands")
	expect(game.quest_manager.get_current_milestone().id == GameTypes.QuestId.STRIKE_IRON, "Iron follows the radar")
	expect(robot._repair_action().is_empty() and not robot.is_actionable_cell(wreck), "Nothing is left to repair")
	# Let the chart roll back to the new frontier, and the sweep fade in, before the scene goes.
	await create_timer(maxf(WorldView.FRONTIER_UNROLL_SECONDS, WorldView.RADAR_POWER_UP_SECONDS) + 0.1).timeout
	expect(is_equal_approx(_sweep(game), 1.0), "The repaired radar's sweep circles the chart")


# How strongly the chart shows the radar's sweep.
func _sweep(game: Node) -> float:
	return float(game.world_view._chart_material.get_shader_parameter("radar_sweep"))


# The robot was sent to `target` and stands where it can work it.
func _arrive_at(game: Node, target: Vector2i) -> void:
	game.robot.pending_action_cell = target
	game.robot.on_arrived()


func _walkable_neighbor(island: IslandData, cell: Vector2i) -> Vector2i:
	for footprint_cell in island.get_building_footprint_cells(island.get_building_anchor_cell(cell)):
		for neighbor in HexGrid.neighbors(footprint_cell):
			if HexPathfinder.is_walkable(island, neighbor):
				return neighbor
	return GameTypes.NO_CELL
