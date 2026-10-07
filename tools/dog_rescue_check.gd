extends SceneTree

# Headless check for the K9-DA rescue (the MAIN quest). Runs the real game scene from a fresh
# world and walks the flow end to end: the dog is hidden until its island in the home waters is reached, waits
# at the world map's k9da spot there, reachable from where the robot lands, can be rescued only
# from beside it, then follows the robot between islands, and the rescue survives a save round-trip.
#
# The game saves to SaveManager.SAVE_PATH as it plays, so any existing save is backed up first and
# restored at the end.
#
#   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/dog_rescue_check.gd

const CheckWatchdog := preload("res://tools/check_watchdog.gd")
const GameScene := preload("res://game.tscn")
const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const HexPathfinderScript := preload("res://scripts/island/hex_pathfinder.gd")

var _saved_bytes := PackedByteArray()
var _had_save := false


func _initialize() -> void:
	CheckWatchdog.install(self)
	call_deferred("_run")


func _run() -> void:
	_backup_save()
	SaveManager.delete_save()

	var game: Node = GameScene.instantiate()
	root.add_child(game)
	await process_frame

	var world: WorldData = game.world
	var dog: Dog = game.dog
	CheckWatchdog.require(world.is_revealed(world.dog_coord) and WorldData.rings_out(world.dog_coord) < 1.0,
		"K9-DA must be stranded in the home waters, closer than ring 1 and sailable from the start")
	var map_dog := WorldMap.load_file().placements.filter(func(placement: WorldMap.Placement) -> bool: return placement.k9da)
	CheckWatchdog.require(map_dog.size() == 1 and world.dog_coord == map_dog[0].center
		and world.get_island(world.dog_coord).map_id == map_dog[0].id, "K9-DA waits on the world map's k9da island")
	CheckWatchdog.require(not world.dog_rescued, "A fresh game starts with K9-DA stranded")
	CheckWatchdog.require(not dog.visible, "K9-DA stays hidden before his island is reached")
	CheckWatchdog.require(not game.quest_manager.is_completed(GameTypes.QuestId.RESCUE_THE_DOG))

	# Finishing the dock introduces the specific rescue-island discovery milestone.
	game.quest_manager.restore_completed({GameTypes.QuestId.REFINE: true})
	game.stat_tracker.add(GameTypes.Stat.DOCKS_BUILT, 1)
	CheckWatchdog.require(game.quest_manager.get_current_milestone().id == GameTypes.QuestId.FOLLOW_THE_SIGNAL)
	CheckWatchdog.require(not dog.visible, "Unlocking sailing alone does not reveal K9-DA")
	for coord: Vector2i in world.islands:
		if coord != world.start_coord and coord != world.dog_coord and roundi(WorldData.rings_out(coord)) == 1:
			game.discover_island(coord)
			break
	CheckWatchdog.require(not game.quest_manager.is_completed(GameTypes.QuestId.FOLLOW_THE_SIGNAL),
		"Discovering another island cannot complete Follow the Signal")
	game.discover_island(world.dog_coord)
	CheckWatchdog.require(not dog.visible, "K9-DA waits for the chart over his island to open")
	await create_timer(WorldView.CHART_REVEAL_SECONDS + 0.1).timeout
	CheckWatchdog.require(dog.visible, "Discovery reveals K9-DA before landing")
	CheckWatchdog.require(game.quest_manager.is_completed(GameTypes.QuestId.FOLLOW_THE_SIGNAL))
	CheckWatchdog.require(game.quest_manager.get_current_milestone().id == GameTypes.QuestId.COPPER_GLINT)
	game.switch_to_island(world.dog_coord, true)
	CheckWatchdog.require(dog.visible, "K9-DA is visible once his island is reached")
	CheckWatchdog.require(dog.mode == Dog.Mode.STRANDED)
	CheckWatchdog.require(dog._anim_player.current_animation == dog._lying_anim, "Dog lies down before rescue")
	CheckWatchdog.require(dog.current_cell == world.dog_cell)
	CheckWatchdog.require(not game.quest_manager.is_completed(GameTypes.QuestId.RESCUE_THE_DOG),
		"Merely reaching the island must not complete the rescue")

	var island: IslandData = world.get_current()
	var robot: PlayerUnit = game.player_unit
	CheckWatchdog.require(not HexPathfinderScript.find_path(island, robot.current_cell, world.dog_cell).is_empty(),
		"K9-DA must be reachable from where the robot lands")
	robot.set_selected(true)
	game.refresh_action_bar()
	CheckWatchdog.require(not game.robot._can_rescue_dog(), "Rescue is only offered beside K9-DA")

	var beside := _walkable_neighbor(island, world.dog_cell)
	robot.place_at(beside)
	game.refresh_action_bar()
	CheckWatchdog.require(game.robot._can_rescue_dog(), "Rescue is offered beside K9-DA")
	CheckWatchdog.require(not game.robot._rescue_action().is_empty())

	game._on_action_pressed(GameTypes.UnitAction.RESCUE)
	CheckWatchdog.require(world.dog_rescued)
	CheckWatchdog.require(game.quest_manager.is_completed(GameTypes.QuestId.RESCUE_THE_DOG), "Rescue completes the MAIN quest")
	CheckWatchdog.require(dog.mode == Dog.Mode.FOLLOWING and dog.leader == robot)
	CheckWatchdog.require(dog._anim_player.current_animation == dog._idle_anim, "Rescue returns dog to standing idle")
	CheckWatchdog.require(not game.robot._can_rescue_dog(), "K9-DA can only be rescued once")

	# The rescue island's copper opens the boat's cargo hold, to haul it home.
	CheckWatchdog.require(island.resources.values().has(GameTypes.ResourceNodeType.COPPER_ORE), "K9-DA's island has copper")
	CheckWatchdog.require(not game.quest_manager.is_upgrade_active(GameTypes.RobotUpgrade.CARGO_HOLD), "Rescue alone doesn't open the cargo hold")
	game.stat_tracker.add(GameTypes.Stat.COPPER_ORE_GATHERED, 6)
	CheckWatchdog.require(game.quest_manager.is_upgrade_active(GameTypes.RobotUpgrade.CARGO_HOLD), "Copper opens the cargo hold")
	CheckWatchdog.require(game.quest_manager.get_current_milestone().id == GameTypes.QuestId.HAUL_IT_HOME)

	# The rescued dog travels with the robot.
	game.switch_to_island(world.start_coord, true)
	CheckWatchdog.require(dog.visible and dog.mode == Dog.Mode.FOLLOWING)
	CheckWatchdog.require(dog.is_on(game.world.get_island(world.start_coord)), "K9-DA follows to the robot's island")
	CheckWatchdog.require(dog.position.is_equal_approx(game.world_view.renderer_for(world.start_coord).get_cell_center(dog.current_cell)),
		"K9-DA stands on that island's ground")
	CheckWatchdog.require(HexGridScript.neighbors(robot.current_cell).has(dog.current_cell) or dog.current_cell == robot.current_cell,
		"K9-DA lands beside the robot")

	# And the rescue is persisted.
	game.save_game()
	var reloaded := WorldData.from_dict(SaveManager.read().get("world", {}), 0.0)
	CheckWatchdog.require(reloaded.dog_rescued and reloaded.dog_coord == world.dog_coord and reloaded.dog_cell == world.dog_cell,
		"Rescue state must survive a save round-trip")

	game.queue_free()
	await process_frame
	_restore_save()
	print("K9-DA rescue: PASS")
	quit()


func _walkable_neighbor(island: IslandData, cell: Vector2i) -> Vector2i:
	for neighbor in HexGridScript.neighbors(cell):
		if HexPathfinderScript.is_walkable(island, neighbor):
			return neighbor
	return cell


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
