extends SceneTree

const MainScript := preload("res://scripts/main.gd")
const MenuScript := preload("res://scripts/ui/game_menu.gd")


func _initialize() -> void:
	call_deferred("_check_menu")


func _check_menu() -> void:
	var menu := MenuScript.new()
	root.add_child(menu)
	assert(not menu.is_open())
	assert(menu.launcher.visible)
	menu.launcher.pressed.emit()
	assert(menu.is_open())
	assert(paused, "Menu must pause gameplay")
	assert(not menu.launcher.visible)
	assert(menu.load_button.disabled == not SaveManager.has_save())
	menu.show_status("Saved successfully")
	assert(menu.status_label.text == "Saved successfully")
	menu._unhandled_input(_escape_event())
	assert(not menu.is_open())
	assert(not paused, "Escape must resume gameplay")
	assert(menu.launcher.visible)
	menu.open()
	menu.close()
	assert(not paused)
	menu.queue_free()
	await process_frame
	await _check_scene_reload()
	print("Game menu controls: PASS")
	quit()


func _check_scene_reload() -> void:
	# Exercise the real reload handler without starting gameplay or touching the player's save.
	var fixture_script := GDScript.new()
	fixture_script.source_code = (
		"extends \"res://scripts/main.gd\"\n"
		+ "func _ready() -> void: pass\n"
		+ "func _process(_delta: float) -> void: pass\n"
		+ "func _notification(_what: int) -> void: pass\n"
	)
	assert(fixture_script.reload() == OK)
	var fixture := Node3D.new()
	fixture.set_script(fixture_script)
	var packed := PackedScene.new()
	assert(packed.pack(fixture) == OK)
	fixture.free()
	var fixture_path := "res://tools/.game_menu_reload_check.tscn"
	assert(ResourceSaver.save(packed, fixture_path) == OK)
	var scene := (load(fixture_path) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	paused = true
	scene._reload_from_menu()
	assert(not paused, "Scene reload must resume the retained tree")
	await process_frame
	await process_frame
	assert(current_scene != null, "Reload must create the replacement scene")
	current_scene.queue_free()
	current_scene = null
	await process_frame
	DirAccess.remove_absolute(fixture_path)
	print("Menu scene reload: PASS")


func _escape_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	return event
