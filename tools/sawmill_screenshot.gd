extends SceneTree

# Renders the robot operating a sawmill from the game camera, at the closest and default zoom
# (plus a low side view of the PTO docking),
# to judge the sawmill and its shared PTO generator at game scale. Needs a window (not headless):
#
#   Godot_v4.6.3-stable_win64_console.exe --path . --script res://tools/sawmill_screenshot.gd -- <out_dir>
#
# The game saves to SaveManager.SAVE_PATH as it plays, so any existing save is backed up first and
# restored at the end.

const GameScene := preload("res://game.tscn")
const HexPathfinderScript := preload("res://scripts/island/hex_pathfinder.gd")

var _saved_bytes := PackedByteArray()
var _had_save := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://")
	_had_save = FileAccess.file_exists(SaveManager.SAVE_PATH)
	if _had_save:
		_saved_bytes = FileAccess.get_file_as_bytes(SaveManager.SAVE_PATH)
	SaveManager.delete_save()

	root.size = Vector2i(1600, 900)
	var game: Node = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	var robot: PlayerUnit = game.player_unit
	var island: IslandData = game.current_island
	var sawmill := _place_near(game, island, robot.current_cell)
	game.renderer.hovered_cell = sawmill
	game._command_unit_to_hovered()
	for i in 2000:
		if not robot.is_moving():
			break
		robot._process(0.05)
	print("Operating: ", game.robot.is_operating)

	var rig: CameraRig = game.camera_rig
	# Game views at the closest and default zoom, then a lower debug orbit from the robot's right
	# side (the generator side) to check the PTO docking into the socket.
	for shot in [["close", CameraRig.MIN_DISTANCE, 0.0, 0.0], ["default", 800.0, 0.0, 0.0],
			["side", CameraRig.MIN_DISTANCE, 80.0, -30.0]]:
		rig._target_distance = shot[1]
		rig._distance = shot[1]
		rig._debug_yaw = deg_to_rad(shot[2])
		rig._debug_pitch = shot[3]
		rig.center_on(game.renderer.get_cell_center(sawmill), true)
		for i in 90:
			await process_frame
		var image := root.get_texture().get_image()
		var path := out_dir.path_join("sawmill_%s.png" % shot[0])
		image.save_png(path)
		print("Saved ", path)

	root.remove_child(game)
	game.free()
	SaveManager.delete_save()
	if _had_save:
		var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(_saved_bytes)
		file.close()
	quit()


func _place_near(game: Node, island: IslandData, from: Vector2i) -> Vector2i:
	var steps: Dictionary = HexPathfinderScript.search(island, from).cost
	for cell in island.terrain.keys():
		if steps.get(cell, 0) >= 2 and steps[cell] < HexPathfinderScript.OBSTACLE_COST \
				and game.building_manager.can_place(cell, GameTypes.BuildingType.SAWMILL, island):
			game.renderer.place_building_at(cell, GameTypes.BuildingType.SAWMILL)
			return cell
	push_error("No site for a sawmill")
	return from
