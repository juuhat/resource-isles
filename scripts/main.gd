extends Node2D

const IslandGeneratorScript := preload("res://scripts/island/island_generator.gd")
const IslandRendererScript := preload("res://scripts/island/island_renderer.gd")

var generator := IslandGeneratorScript.new()
var renderer: IslandRenderer
var camera: Camera2D
var seed_value := 1
var zoom_step := 1.1
var min_zoom := 0.25
var max_zoom := 1.5
var is_panning := false


func _ready() -> void:
	renderer = IslandRendererScript.new()
	renderer.name = "IslandRenderer"
	add_child(renderer)

	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.enabled = true
	camera.zoom = Vector2(0.375, 0.375)
	add_child(camera)

	_add_debug_label()
	_generate_island()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
		seed_value += 1
		_generate_island()

	if key_event.keycode == KEY_SPACE:
		renderer.show_grid = not renderer.show_grid
		renderer.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_set_zoom(camera.zoom.x * zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_set_zoom(camera.zoom.x / zoom_step)
		elif event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			is_panning = event.pressed

	if event is InputEventMouseMotion and is_panning:
		camera.position -= event.relative / camera.zoom.x


func _set_zoom(new_zoom: float) -> void:
	var clamped_zoom := clampf(new_zoom, min_zoom, max_zoom)
	camera.zoom = Vector2(clamped_zoom, clamped_zoom)
	renderer.queue_redraw()


func _generate_island() -> void:
	var island := generator.generate_starter_island(seed_value)
	renderer.render(island)
	_center_camera(island)


func _center_camera(island: IslandData) -> void:
	var island_size := Vector2(
		island.width * renderer.cell_size.x,
		island.height * renderer.cell_size.y
	)
	camera.position = island_size * 0.5


func _add_debug_label() -> void:
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "DebugOverlay"
	add_child(canvas_layer)

	var label := Label.new()
	label.text = "Enter: regenerate   Space: grid   Mouse wheel: zoom   Right/middle drag: pan"
	label.position = Vector2(16, 16)
	label.add_theme_color_override("font_color", Color.html("#17343a"))
	canvas_layer.add_child(label)
