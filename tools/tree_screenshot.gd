extends SceneTree

# Renders the starter island's tree stands from the game camera, at the closest and default zoom,
# to judge the pine, leaf and palm trees against the grass and sand at game scale. Needs a window
# (not headless), and never loads or writes the player's save:
#
#   Godot_v4.6.3-stable_win64_console.exe --path . --script res://tools/tree_screenshot.gd -- <out_dir>

class CaptureGame extends "res://scripts/main.gd":
	func _try_load_game() -> bool:
		return false

	func save_game() -> bool:
		return true


const SHOTS := [
	["pine", GameTypes.ResourceNodeType.TREE],
	["leaf", GameTypes.ResourceNodeType.LEAF_TREE],
	["palm", GameTypes.ResourceNodeType.PALM_TREE],
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://")
	root.size = Vector2i(1600, 900)
	var game: Node = load("res://game.tscn").instantiate()
	game.set_script(CaptureGame)
	root.add_child(game)
	await process_frame
	var island: IslandData = game.current_island
	var rig: CameraRig = game.camera_rig
	for shot in SHOTS:
		var cell := GameTypes.NO_CELL
		for candidate in island.resources:
			if island.resources[candidate] == shot[1]:
				cell = candidate
				break
		if cell == GameTypes.NO_CELL:
			push_error("No %s trees on the starter island" % shot[0])
			continue
		for zoom in [["close", CameraRig.MIN_DISTANCE], ["default", 800.0]]:
			rig._target_distance = zoom[1]
			rig._distance = zoom[1]
			rig.center_on(game.renderer.get_cell_center(cell), true)
			for i in 60:
				await process_frame
			var path := out_dir.path_join("trees_%s_%s.png" % [shot[0], zoom[0]])
			root.get_texture().get_image().save_png(path)
			print("Saved ", path)
	quit()
