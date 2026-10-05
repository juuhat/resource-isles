extends SceneTree

var selected := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(400, 220)
	var bar := ActionBar.new()
	root.add_child(bar)
	await process_frame
	var viewport := bar.portrait_viewport
	assert(viewport.own_world_3d and viewport.transparent_bg)
	assert(viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
	assert(bar.portrait.icon == viewport.get_texture())
	var animator := viewport.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(animator != null and animator.is_playing())
	assert(String(animator.current_animation).get_file().to_lower() == "idle")
	assert(animator.get_animation(animator.current_animation).loop_mode == Animation.LOOP_LINEAR)
	var head := viewport.find_child("HeadPivot", true, false) as Node3D
	animator.seek(0.0, true)
	var rest := head.transform
	animator.seek(0.75, true)
	assert(not head.transform.is_equal_approx(rest), "Portrait's idle animates the head")
	for tool_name in PlayerUnit.WORK_CLIPS.values():
		assert(not (viewport.find_child(tool_name, true, false) as Node3D).visible)
	bar.select_requested.connect(func() -> void: selected = true)
	bar.portrait.pressed.emit()
	assert(selected, "Portrait still selects the player")
	bar.set_selected(true)
	assert(bar.portrait.modulate == Color.WHITE)
	bar.set_selected(false)
	assert(is_equal_approx(bar.portrait.modulate.a, 0.6))
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
