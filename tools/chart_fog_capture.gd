extends SceneTree

# Fixed-seed captures of the uncharted map: the starting frontier around the home island, a
# reachable island still waiting to be discovered, the overview before and after Set Sail, and the
# exploration fog cleared along a voyage.
# Never loads or writes the player's save. Run with a window, not --headless:
# Godot_v4.6.3-stable_win64_console.exe --path . --script res://tools/chart_fog_capture.gd -- <output_directory>
class CaptureGame extends "res://scripts/main.gd":
	func _try_load_game() -> bool:
		return false

	func save_game() -> bool:
		return true

var _out_dir: String


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_out_dir = ProjectSettings.globalize_path(args[0] if not args.is_empty() else "res://art/previews/chart_fog/latest")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	root.size = Vector2i(1600, 900)
	var game: Node = load("res://game.tscn").instantiate()
	game.set_script(CaptureGame)
	game.seed_value = 1
	root.add_child(game)
	await process_frame
	var home: IslandRenderer = game.world_view.renderer_for(WorldData.CENTER)
	var target: Vector2i = game.world.dog_coord
	var toward := WorldView.slot_position(target).normalized()

	# Start of the game: only the home ring is charted.
	await _shoot(game, "start_edge", home.get_map_center() + toward * 2600.0, 1400.0)
	await _shoot(game, "start_overview", Vector3.ZERO, -1.0)

	# Set Sail: the first ring is charted, its islands still undiscovered.
	game._reveal_rings(1)
	await _shoot(game, "ring_rolling_back", home.get_map_center() + toward * 3400.0, 2600.0)
	await create_timer(WorldView.FRONTIER_UNROLL_SECONDS).timeout
	await _shoot(game, "ring_fog", home.get_map_center() + toward * 2600.0, 2600.0)
	await _shoot(game, "ring_island", WorldView.slot_position(target), 1500.0)
	await _shoot(game, "ring_overview", Vector3.ZERO, -1.0)

	# Sailing out clears the exploration fog in the boat's wake.
	var distance := 1200.0
	while distance < 4000.0:
		game.look_around(game.world_navigation.cell_from_position(home.get_map_center() + toward * distance))
		distance += 128.0
	await _shoot(game, "explored_wake", home.get_map_center() + toward * 3600.0, 2600.0)
	await _shoot(game, "explored_overview", Vector3.ZERO, -1.0)

	# Sailing close discovers the island: its patch opens from the centre.
	game.discover_island(target)
	await create_timer(WorldView.CHART_REVEAL_SECONDS * 0.35).timeout
	await _shoot(game, "island_opening", WorldView.slot_position(target), 1500.0)
	await create_timer(WorldView.CHART_REVEAL_SECONDS * 0.65).timeout
	await _shoot(game, "island_discovered", WorldView.slot_position(target), 1500.0)
	root.remove_child(game)
	game.free()
	print("Chart fog captures: PASS — ", _out_dir)
	quit()


# distance < 0 frames the whole disc.
func _shoot(game: Node, shot_name: String, focus: Vector3, distance: float) -> void:
	var rig: CameraRig = game.camera_rig
	if distance < 0.0:
		rig._distance = rig._overview_distance
		rig._target_distance = rig._distance
		rig._apply()
		game.world_view.set_overview_amount(1.0)
	else:
		rig._distance = distance
		rig._target_distance = distance
		rig.center_on(focus, true)
		game.world_view.set_overview_amount(0.0)
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join(shot_name + ".png"))
