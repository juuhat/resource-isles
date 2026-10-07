extends SceneTree

# Renders the crashed ship from the game camera in each repair state of the radar (broken, half
# repaired, repaired), at the closest and default zoom, to judge the wreck model
# (tools/build_spaceship.py) at game scale. Needs a window (not headless). Boots game.tscn, which
# autosaves, so give it a throwaway user:// folder (on Windows, APPDATA):
#
#   $env:APPDATA = "$env:TEMP\resource-isles-shots"
#   Godot_v4.6.3-stable_win64_console.exe --path . --script res://tools/ship_wreck_screenshot.gd -- <out_dir>

const GameScene := preload("res://game.tscn")
const RADAR := GameTypes.ShipPart.RADAR


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://")
	if OS.get_environment("APPDATA").find("resource-isles") == -1:
		push_error("Run with a throwaway APPDATA (see the header): the game would overwrite your save")
		quit(1)
		return

	root.size = Vector2i(1600, 900)
	var game: Node = GameScene.instantiate()
	root.add_child(game)
	await process_frame
	var world: WorldData = game.world
	var wreck := WorldBuilder.find_crashed_spaceship_cell(game.current_island)
	var rig: CameraRig = game.camera_rig

	for state in [["broken", -1.0], ["repairing", 0.55], ["repaired", 1.0]]:
		world.ship_repairs.erase(RADAR)
		if state[1] >= 0.0:
			world.ship_repairs[RADAR] = state[1]
		for shot in [["close", CameraRig.MIN_DISTANCE], ["default", 800.0]]:
			rig._target_distance = shot[1]
			rig._distance = shot[1]
			rig.center_on(game.renderer.get_cell_center(wreck), true)
			for i in 60:
				await process_frame
			var path := out_dir.path_join("ship_wreck_%s_%s.png" % [state[0], shot[0]])
			root.get_texture().get_image().save_png(path)
			print("Saved ", path)

	root.remove_child(game)
	game.free()
	quit()
