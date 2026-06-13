extends Node2D

const IslandGeneratorScript := preload("res://scripts/island/island_generator.gd")
const IslandRendererScript := preload("res://scripts/island/island_renderer.gd")
const BuildingMenuScript := preload("res://scripts/ui/building_menu.gd")
const ResourceBarScript := preload("res://scripts/ui/resource_bar.gd")
const ResourceManagerScript := preload("res://scripts/resources/resource_manager.gd")
const ResourceNodeDatabaseScript := preload("res://scripts/resources/resource_node_database.gd")

const NO_BUILDING := -1

var generator := IslandGeneratorScript.new()
var renderer: IslandRenderer
var camera: Camera2D
var seed_value := 1
var zoom_step := 1.1
var min_zoom := 0.25
var max_zoom := 1.5
var is_panning := false
var selected_building_type := NO_BUILDING
var resource_manager: ResourceManager
var resource_node_database: ResourceNodeDatabase
var resource_bar: ResourceBar
var building_menu: BuildingMenu


func _ready() -> void:
	resource_manager = ResourceManagerScript.new()
	resource_node_database = ResourceNodeDatabaseScript.new()

	renderer = IslandRendererScript.new()
	renderer.name = "IslandRenderer"
	renderer.setup(resource_node_database)
	add_child(renderer)

	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.enabled = true
	camera.zoom = Vector2(0.375, 0.375)
	add_child(camera)

	_add_ui()
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

	if key_event.keycode == KEY_ESCAPE:
		building_menu.clear_selection_and_close()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var is_over_ui := get_viewport().gui_get_hovered_control() != null

		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_set_zoom(camera.zoom.x * zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_set_zoom(camera.zoom.x / zoom_step)
		elif event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			is_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not is_over_ui:
			if _try_harvest_resource():
				return

			if selected_building_type != NO_BUILDING:
				renderer.try_place_hovered_building(selected_building_type)

	if event is InputEventMouseMotion and is_panning:
		camera.position -= event.relative / camera.zoom.x

	if event is InputEventMouseMotion:
		renderer.set_hovered_world_position(get_global_mouse_position())


func _set_zoom(new_zoom: float) -> void:
	var clamped_zoom := clampf(new_zoom, min_zoom, max_zoom)
	camera.zoom = Vector2(clamped_zoom, clamped_zoom)
	renderer.queue_redraw()


func _try_harvest_resource() -> bool:
	var resource_node_type := renderer.try_harvest_hovered_resource()
	if resource_node_type == -1:
		return false

	var definition := resource_node_database.get_definition(resource_node_type)
	if definition == null:
		return false

	resource_manager.add_amount(definition.extracted_resource_type, definition.extraction_amount)
	return true


func _generate_island() -> void:
	var island := generator.generate_starter_island(seed_value)
	renderer.render(island)
	_apply_selected_building()
	_center_camera(island)


func _center_camera(island: IslandData) -> void:
	var island_size := Vector2(
		island.width * renderer.cell_size.x,
		island.height * renderer.cell_size.y
	)
	camera.position = island_size * 0.5


func _select_no_building() -> void:
	selected_building_type = NO_BUILDING
	_apply_selected_building()


func _select_building(building_type: int) -> void:
	selected_building_type = building_type
	_apply_selected_building()


func _apply_selected_building() -> void:
	if selected_building_type == NO_BUILDING:
		renderer.set_placement_preview(false)
		return

	renderer.set_placement_preview(true, selected_building_type)


func _add_ui() -> void:
	resource_bar = ResourceBarScript.new()
	add_child(resource_bar)
	resource_bar.setup(resource_manager)

	building_menu = BuildingMenuScript.new()
	building_menu.building_selected.connect(_select_building)
	building_menu.selection_cleared.connect(_select_no_building)
	add_child(building_menu)
