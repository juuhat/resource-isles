extends SceneTree

# Headless check for the K9-DA rescue (the MAIN quest). Runs the real game scene from a fresh
# world and walks the flow end to end: the dog is hidden until its ring-1 island is reached, waits
# at a reachable spot there, can be rescued only from beside it, then follows the robot between
# islands, and the rescue survives a save round-trip. Also sweeps several world seeds to confirm
# the chosen spot is always reachable from where the robot lands.
#
# The game saves to SaveManager.SAVE_PATH as it plays, so any existing save is backed up first and
# restored at the end.
#
#   Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/dog_rescue_check.gd

const GameScene := preload("res://game.tscn")
const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const HexPathfinderScript := preload("res://scripts/island/hex_pathfinder.gd")

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

	var world: WorldData = game.world
	var dog: Dog = game.dog
	assert(WorldData.ring_of(world.dog_coord) == 1, "K9-DA must be stranded on ring 1")
	assert(not world.dog_rescued, "A fresh game starts with K9-DA stranded")
	assert(not dog.visible, "K9-DA stays hidden before his island is reached")
	assert(not game.quest_manager.is_completed(GameTypes.QuestId.RESCUE_THE_DOG))

	# Finishing the dock introduces the specific rescue-island discovery milestone.
	game.quest_manager.restore_completed({GameTypes.QuestId.REFINE: true})
	game.stat_tracker.add(GameTypes.Stat.DOCKS_BUILT, 1)
	assert(game.quest_manager.get_current_milestone().id == GameTypes.QuestId.FOLLOW_THE_SIGNAL)
	assert(not dog.visible, "Unlocking sailing alone does not reveal K9-DA")
	for coord in world.slots_within(1):
		if coord != WorldData.CENTER and coord != world.dog_coord:
			game._discover_island(coord)
			break
	assert(not game.quest_manager.is_completed(GameTypes.QuestId.FOLLOW_THE_SIGNAL),
		"Discovering another island cannot complete Follow the Signal")
	game._discover_island(world.dog_coord)
	assert(dog.visible, "Discovery reveals K9-DA before landing")
	assert(game.quest_manager.is_completed(GameTypes.QuestId.FOLLOW_THE_SIGNAL))
	assert(game.quest_manager.get_current_milestone().id == GameTypes.QuestId.STRIKE_IRON)
	game._switch_to_island(world.dog_coord, true)
	assert(dog.visible, "K9-DA is visible once his island is reached")
	assert(dog.mode == Dog.Mode.STRANDED)
	assert(dog.current_cell == world.dog_cell)
	assert(not game.quest_manager.is_completed(GameTypes.QuestId.RESCUE_THE_DOG),
		"Merely reaching the island must not complete the rescue")

	var island: IslandData = world.get_current()
	var robot: PlayerUnit = game.player_unit
	assert(not HexPathfinderScript.find_path(island, robot.current_cell, world.dog_cell).is_empty(),
		"K9-DA must be reachable from where the robot lands")
	robot.set_selected(true)
	game._refresh_action_bar()
	assert(not game._can_rescue_dog(), "Rescue is only offered beside K9-DA")

	var beside := _walkable_neighbor(island, world.dog_cell)
	robot.place_at(beside)
	game._refresh_action_bar()
	assert(game._can_rescue_dog(), "Rescue is offered beside K9-DA")
	assert(not game._rescue_action().is_empty())

	game._on_action_pressed(game.UnitAction.RESCUE)
	assert(world.dog_rescued)
	assert(game.quest_manager.is_completed(GameTypes.QuestId.RESCUE_THE_DOG), "Rescue completes the MAIN quest")
	assert(dog.mode == Dog.Mode.FOLLOWING and dog.leader == robot)
	assert(not game._can_rescue_dog(), "K9-DA can only be rescued once")

	# The rescued dog travels with the robot.
	game._switch_to_island(WorldData.CENTER, true)
	assert(dog.visible and dog.mode == Dog.Mode.FOLLOWING)
	assert(dog.is_on(game.world.get_island(WorldData.CENTER)), "K9-DA follows to the robot's island")
	assert(dog.position.is_equal_approx(game.world_view.renderer_for(WorldData.CENTER).get_cell_center(dog.current_cell)),
		"K9-DA stands on that island's ground")
	assert(HexGridScript.neighbors(robot.current_cell).has(dog.current_cell) or dog.current_cell == robot.current_cell,
		"K9-DA lands beside the robot")

	# And the rescue is persisted.
	game._save_game()
	var reloaded := WorldData.from_dict(SaveManager.read().get("world", {}), 0.0)
	assert(reloaded.dog_rescued and reloaded.dog_coord == world.dog_coord and reloaded.dog_cell == world.dog_cell,
		"Rescue state must survive a save round-trip")

	# Every seed puts K9-DA somewhere the robot can walk to.
	for seed_value in range(1, 21):
		var coord := WorldData.dog_slot_for_seed(seed_value)
		assert(WorldData.ring_of(coord) == 1)
		game.seed_value = seed_value
		var island_seed: int = game._island_seed(coord)
		var profile := IslandProfiles.get_profile(IslandProfiles.biome_for_coord(coord, seed_value))
		var generated: IslandData = game.generator.generate(profile, island_seed, game.building_manager)
		var start: Vector2i = game._find_unit_spawn_cell(generated)
		var cell: Vector2i = game._choose_dog_cell(generated, island_seed)
		assert(cell != start, "Seed %d: K9-DA must not spawn on the robot" % seed_value)
		assert(game._is_open_ground(generated, cell), "Seed %d: K9-DA must stand on open ground" % seed_value)
		assert(not HexPathfinderScript.find_path(generated, start, cell).is_empty(),
			"Seed %d: K9-DA must be reachable" % seed_value)

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
