extends SceneTree

const CheckWatchdog := preload("res://tools/check_watchdog.gd")

var selected := false

func _initialize() -> void:
	CheckWatchdog.install(self)
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(400, 220)
	var bar := ActionBar.new()
	root.add_child(bar)
	await process_frame
	var viewport := bar.portrait_viewport
	CheckWatchdog.require(viewport.own_world_3d and viewport.transparent_bg)
	CheckWatchdog.require(viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
	CheckWatchdog.require(bar.portrait.icon == viewport.get_texture())
	var animator := viewport.find_child("AnimationPlayer", true, false) as AnimationPlayer
	CheckWatchdog.require(animator != null and animator.is_playing())
	CheckWatchdog.require(String(animator.current_animation).get_file().to_lower() == "idle")
	CheckWatchdog.require(animator.get_animation(animator.current_animation).loop_mode == Animation.LOOP_LINEAR)
	var head := viewport.find_child("HeadPivot", true, false) as Node3D
	animator.seek(0.0, true)
	var rest := head.transform
	animator.seek(0.75, true)
	CheckWatchdog.require(not head.transform.is_equal_approx(rest), "Portrait's idle animates the head")
	var blink = bar._portrait_blink
	CheckWatchdog.require(blink._eyes.size() == 2, "Portrait must blink both eyes")
	blink._blink_wait = 0.0
	bar._process(0.0)
	bar._process(0.08)
	for i in blink._eyes.size():
		var eye: MeshInstance3D = blink._eyes[i]
		var open_bounds: AABB = blink._eye_rest_transforms[i] * eye.get_aabb()
		var closed_bounds: AABB = eye.transform * eye.get_aabb()
		CheckWatchdog.require(closed_bounds.size.y < open_bounds.size.y * 0.1, "Portrait eye must close")
	bar._process(0.2)
	for i in blink._eyes.size():
		CheckWatchdog.require(blink._eyes[i].transform.is_equal_approx(blink._eye_rest_transforms[i]), "Portrait eye must reopen")
	for tool_name in PlayerUnit.WORK_CLIPS.values():
		CheckWatchdog.require(not (viewport.find_child(tool_name, true, false) as Node3D).visible)
	bar.select_requested.connect(func() -> void: selected = true)
	bar.portrait.pressed.emit()
	CheckWatchdog.require(selected, "Portrait still selects the player")
	bar.set_selected(true)
	CheckWatchdog.require(bar.portrait.modulate == Color.WHITE)
	bar.set_selected(false)
	CheckWatchdog.require(is_equal_approx(bar.portrait.modulate.a, 0.6))
	bar.set_selected(true)
	for i in 5:
		await process_frame
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[0])
	print("Player portrait: PASS")
	bar.free()
	quit()
