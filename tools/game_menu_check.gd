extends SceneTree

const CheckWatchdog := preload("res://tools/check_watchdog.gd")
const MainScript := preload("res://scripts/main.gd")
const MenuScript := preload("res://scripts/ui/game_menu.gd")


func _initialize() -> void:
	CheckWatchdog.install(self)
	call_deferred("_check_menu")


func _check_menu() -> void:
	var menu := MenuScript.new()
	root.add_child(menu)
	CheckWatchdog.require(not menu.is_open())
	CheckWatchdog.require(menu.launcher.visible)
	menu.launcher.pressed.emit()
	CheckWatchdog.require(menu.is_open())
	CheckWatchdog.require(paused, "Menu must pause gameplay")
	CheckWatchdog.require(not menu.launcher.visible)
	CheckWatchdog.require(menu.load_button.disabled == not SaveManager.has_save())
	menu.show_status("Saved successfully")
	CheckWatchdog.require(menu.status_label.text == "Saved successfully")
	menu._unhandled_input(_escape_event())
	CheckWatchdog.require(not menu.is_open())
	CheckWatchdog.require(not paused, "Escape must resume gameplay")
	CheckWatchdog.require(menu.launcher.visible)
	menu.open()
	menu.close()
	CheckWatchdog.require(not paused)
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
	CheckWatchdog.require(fixture_script.reload() == OK)
	var fixture := Node3D.new()
	fixture.set_script(fixture_script)
	var packed := PackedScene.new()
	CheckWatchdog.require(packed.pack(fixture) == OK)
	fixture.free()
	var fixture_path := "res://tools/.game_menu_reload_check.tscn"
	CheckWatchdog.require(ResourceSaver.save(packed, fixture_path) == OK)
	var scene := (load(fixture_path) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	paused = true
	scene._reload_from_menu()
	CheckWatchdog.require(not paused, "Scene reload must resume the retained tree")
	await process_frame
	await process_frame
	CheckWatchdog.require(current_scene != null, "Reload must create the replacement scene")
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
