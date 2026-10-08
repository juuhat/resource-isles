extends SceneTree

# Renders the quest highlight (QuestHighlight) from the game camera on a fresh starter island: each
# of the robot's lost tools while Recover Your Tools is active, then the wreck's broken radar once the
# chain is moved on to Eyes on the Horizon. Each at the closest and the default zoom, a few moments
# apart so the glow's sweep and the halo's ripple show. Needs a window (not headless), and never loads
# or writes the player's save:
#
#   Godot_v4.6.3-stable_win64_console.exe --path . --script res://tools/quest_highlight_screenshot.gd -- <out_dir>

class CaptureGame extends "res://scripts/main.gd":
	func _try_load_game() -> bool:
		return false

	func save_game() -> bool:
		return true


const ITEM_NAMES := {
	GameTypes.ItemType.AXE: "axe",
	GameTypes.ItemType.PICKAXE: "pickaxe",
	GameTypes.ItemType.WRENCH: "wrench",
}
# Seconds into the effect for each frame of a shot.
const MOMENTS := [0.4, 1.2, 2.0, 2.8]

var _out_dir := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://")
	root.size = Vector2i(1600, 900)
	var game: Node = load("res://game.tscn").instantiate()
	game.set_script(CaptureGame)
	root.add_child(game)
	await process_frame
	var island: IslandData = game.current_island
	for cell in island.items:
		await _shoot(game, ITEM_NAMES.get(island.items[cell], "item"), cell)

	game.quest_manager.restore_completed({GameTypes.QuestId.FIRST_MELT: true})
	game.world_view.update_quest_highlights()
	await _shoot(game, "radar", WorldBuilder.find_crashed_spaceship_cell(island))
	quit()


func _shoot(game: Node, shot_name: String, cell: Vector2i) -> void:
	var rig: CameraRig = game.camera_rig
	for zoom in [["close", CameraRig.MIN_DISTANCE], ["default", 800.0]]:
		rig._target_distance = zoom[1]
		rig._distance = zoom[1]
		rig.center_on(game.renderer.get_cell_center(cell), true)
		var waited := 0.0
		for moment: float in MOMENTS:
			await create_timer(moment - waited).timeout
			waited = moment
			var path := _out_dir.path_join("quest_highlight_%s_%s_%.1f.png" % [shot_name, zoom[0], moment])
			root.get_texture().get_image().save_png(path)
			print("Saved ", path)
