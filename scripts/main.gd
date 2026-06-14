extends Node2D

const IslandGeneratorScript := preload("res://scripts/island/island_generator.gd")
const IslandRendererScript := preload("res://scripts/island/island_renderer.gd")
const BuildingMenuScript := preload("res://scripts/ui/building_menu.gd")
const BuildingInfoPanelScript := preload("res://scripts/ui/building_info_panel.gd")
const ResourceBarScript := preload("res://scripts/ui/resource_bar.gd")
const ResourceManagerScript := preload("res://scripts/resources/resource_manager.gd")
const ResourceNodeDatabaseScript := preload("res://scripts/resources/resource_node_database.gd")
const BuildingCatalogScript := preload("res://scripts/buildings/building_catalog.gd")

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
var building_info_panel: BuildingInfoPanel


func _ready() -> void:
	resource_manager = ResourceManagerScript.new()
	resource_manager.resource_changed.connect(_on_resource_changed)
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
			if _try_select_building():
				return

			if _try_harvest_resource():
				return

			if selected_building_type != NO_BUILDING:
				_try_place_selected_building()

	if event is InputEventMouseMotion and is_panning:
		camera.position -= event.relative / camera.zoom.x

	if event is InputEventMouseMotion:
		renderer.set_hovered_world_position(get_global_mouse_position())


func _set_zoom(new_zoom: float) -> void:
	var clamped_zoom := clampf(new_zoom, min_zoom, max_zoom)
	camera.zoom = Vector2(clamped_zoom, clamped_zoom)
	renderer.queue_redraw()


func _try_harvest_resource() -> bool:
	var resource_node_type := renderer.get_hovered_resource_node_type()
	if resource_node_type == -1:
		return false

	var definition := resource_node_database.get_definition(resource_node_type)
	if definition == null:
		return true

	var current_time_seconds := Time.get_ticks_msec() / 1000.0
	if not renderer.island.can_extract_resource(renderer.hovered_cell, current_time_seconds):
		return true

	resource_manager.add_amount(definition.extracted_resource_type, definition.extraction_amount)
	renderer.island.mark_resource_extracted(
		renderer.hovered_cell,
		current_time_seconds + definition.extraction_interval_seconds
	)
	return true


func _try_select_building() -> bool:
	var building_type := renderer.get_hovered_building_type()
	if building_type == -1:
		return false

	building_info_panel.show_building(building_type, renderer.hovered_cell)
	return true


func _try_place_selected_building() -> bool:
	var cost := _get_building_cost(selected_building_type)
	if not resource_manager.can_afford(cost):
		return false

	if not renderer.try_place_hovered_building(selected_building_type):
		return false

	resource_manager.spend(cost)
	return true


func _get_building_cost(building_type: int) -> Dictionary:
	return BuildingCatalogScript.get_cost(building_type)


func _generate_island() -> void:
	var island := generator.generate_starter_island(seed_value)
	renderer.render(island)
	_apply_selected_building()
	_center_camera(island)


func _center_camera(_island: IslandData) -> void:
	var bounds := renderer.get_map_bounds()
	camera.position = bounds.position + bounds.size * 0.5


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

	renderer.set_placement_preview(
		true,
		selected_building_type,
		resource_manager.can_afford(_get_building_cost(selected_building_type))
	)


func _on_resource_changed(_resource_type: int, _amount: int) -> void:
	_apply_selected_building()


func _add_ui() -> void:
	resource_bar = ResourceBarScript.new()
	add_child(resource_bar)
	resource_bar.setup(resource_manager)

	building_info_panel = BuildingInfoPanelScript.new()
	add_child(building_info_panel)

	building_menu = BuildingMenuScript.new()
	building_menu.building_selected.connect(_select_building)
	building_menu.selection_cleared.connect(_select_no_building)
	add_child(building_menu)
