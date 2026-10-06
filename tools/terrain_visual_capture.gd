extends SceneTree

# Fixed-seed rendering comparison; never loads or writes the player's save.
# Run with a window, not --headless:
# Godot_v4.6.3-stable_win64_console.exe --path . --script res://tools/terrain_visual_capture.gd -- <output_directory>
# Outputs four play views, a seven-island overview, and sampled rendering statistics.
class CaptureGame extends "res://scripts/main.gd":
	func _try_load_game() -> bool:
		return false

	func save_game() -> bool:
		return true

const SAMPLE_FRAMES := 120
var _measurements: Array[Dictionary] = []
var _out_dir: String


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Terrain captures require a rendering window; omit --headless.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	_out_dir = args[0] if not args.is_empty() else "res://art/previews/terrain/latest"
	_out_dir = ProjectSettings.globalize_path(_out_dir)
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		push_error("Could not create capture directory: " + _out_dir)
		quit(1)
		return
	root.size = Vector2i(1600, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var game: Node = load("res://game.tscn").instantiate()
	game.set_script(CaptureGame)
	game.seed_value = 1
	root.add_child(game)
	await process_frame
	# Reveal the same seven islands for every run, including the overview benchmark.
	game.world.revealed_rings = 2
	for coord in game.world.island_slots():
		game.world.get_island(coord).visited = true
	game.world_view.refresh()
	# Chart patches open with time-based tweens; finish them before freezing scene updates.
	await create_timer(WorldView.CHART_REVEAL_SECONDS + 0.2).timeout
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.renderer.clear_interaction()
	var rig: CameraRig = game.camera_rig
	var mining_coord := WorldData.NO_COORD
	for coord in game.world.island_slots():
		if coord != WorldData.CENTER and coord != game.world.dog_coord:
			mining_coord = coord
			break
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	for entry in [["starter", WorldData.CENTER], ["mining", mining_coord]]:
		var renderer: IslandRenderer = game.world_view.renderer_for(entry[1])
		for shot in [["normal", 1200.0], ["close", 600.0]]:
			rig._distance = shot[1]
			rig._target_distance = shot[1]
			rig.center_on(renderer.get_map_center(), true)
			game.world_view.set_overview_amount(0.0)
			await _capture("%s_%s" % [entry[0], shot[0]])
	rig._distance = rig._overview_distance
	rig._target_distance = rig._distance
	rig._apply()
	game.world_view.set_overview_amount(1.0)
	await _capture("overview")
	if "--interactions" in args:
		await _capture_interactions(game)
	var report := {
		"seed": 1, "resolution": [1600, 900], "samples_per_view": SAMPLE_FRAMES,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "vsync": false,
		"note": "Wall frame times include engine scheduling. CPU/GPU render times cover the root viewport. Compare warmed runs on the same machine; desktop Mobile renderer is not a mobile-device benchmark.",
		"views": _measurements,
	}
	var file := FileAccess.open(_out_dir.path_join("metrics.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	root.remove_child(game)
	game.free()
	print("Terrain captures: PASS — ", _out_dir)
	quit()


func _capture(shot_name: String) -> void:
	# Warm pipelines, shadow maps, and the measurement query before sampling.
	for i in SAMPLE_FRAMES:
		await process_frame
		await RenderingServer.frame_post_draw
	var frames: Array[float] = []
	var cpu := 0.0
	var gpu := 0.0
	var draws := 0.0
	var last := Time.get_ticks_usec()
	for i in SAMPLE_FRAMES:
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frames.append(float(now - last) / 1000.0)
		last = now
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var mean := 0.0
	for frame_ms in frames:
		mean += frame_ms
	frames.sort()
	var record := {"view": shot_name, "frame_ms_mean": mean / SAMPLE_FRAMES,
		"frame_ms_p95": frames[int(SAMPLE_FRAMES * 0.95) - 1],
		"render_cpu_ms_mean": cpu / SAMPLE_FRAMES, "render_gpu_ms_mean": gpu / SAMPLE_FRAMES,
		"draw_calls_mean": draws / SAMPLE_FRAMES}
	_measurements.append(record)
	var path := _out_dir.path_join(shot_name + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Could not save " + path)
		quit(1)
	print(JSON.stringify(record))


func _capture_interactions(game: Node) -> void:
	var renderer: IslandRenderer = game.renderer
	var rig: CameraRig = game.camera_rig
	rig._distance = 800.0
	rig._target_distance = rig._distance
	rig.center_on(renderer.get_map_center(), true)
	game.world_view.set_overview_amount(0.0)
	var target := GameTypes.NO_CELL
	for cell in game.current_island.terrain:
		if game.current_island.get_terrain(cell) == GameTypes.Terrain.GRASS \
				and not game.current_island.resources.has(cell) and not game.current_island.has_building(cell):
			if target == GameTypes.NO_CELL or renderer.get_cell_center(cell).distance_to(renderer.get_map_center()) \
					< renderer.get_cell_center(target).distance_to(renderer.get_map_center()):
				target = cell
	renderer.is_cell_actionable = func(_cell: Vector2i) -> bool: return false
	renderer.set_hovered_cell(target)
	await _capture("hover_normal")
	renderer.is_cell_actionable = func(_cell: Vector2i) -> bool: return true
	renderer.refresh_hover()
	await _capture("hover_action")
	# Clear the callback just as placement mode's gameplay callback would veto actions.
	renderer.is_cell_actionable = Callable()
	renderer.set_placement_preview(true, GameTypes.BuildingType.LOGGER_CAMP)
	await _capture("placement")
	renderer.clear_interaction()
	renderer.set_explored(false)
	await _capture("unexplored")
	renderer.set_explored(true)
	# A grazing view makes the fixed-height sidewalls and waterline readable.
	rig._debug_pitch = -25.0
	rig._distance = 650.0
	rig._target_distance = rig._distance
	var shore := target
	var shore_z := -INF
	for cell in game.current_island.terrain:
		if game.current_island.get_terrain(cell) == GameTypes.Terrain.SAND:
			var center := renderer.get_cell_center(cell)
			if center.z > shore_z:
				shore_z = center.z
				shore = cell
	rig.center_on(renderer.get_cell_center(shore), true)
	await _capture("shore_side")
