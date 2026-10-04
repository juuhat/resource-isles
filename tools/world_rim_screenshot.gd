extends SceneTree

# Renders the world overview (the whole disc and its mountain rim) from the default overview angle,
# a dragged orbit and a lower edge-on view, to judge the rim at the scale players see it. Needs a
# window (not headless):
#
#   Godot_v4.6.3-stable_win64_console.exe --path . --script res://tools/world_rim_screenshot.gd -- <out_dir>
#
# The game writes user://savegame.sav as it plays, so any existing save is backed up first and
# restored at the end.

const GameScene := preload("res://game.tscn")

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

	var rig: CameraRig = game.camera_rig
	rig.toggle_overview()
	rig._distance = rig._target_distance
	# Overview as the player first sees it, an orbit to another stretch of the range, and a low
	# grazing view from closer in to see the peaks' silhouettes.
	for shot in [["overview", 1.0, 0.0, 0.0], ["orbit", 1.0, 2.2, 0.0], ["low", 0.55, 0.9, -18.0]]:
		rig._distance = rig._overview_distance * shot[1]
		rig._target_distance = rig._distance
		rig._overview_yaw = shot[2]
		rig._debug_pitch = shot[3]
		for i in 60:
			await process_frame
		var image := root.get_texture().get_image()
		var path := out_dir.path_join("world_rim_%s.png" % shot[0])
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
