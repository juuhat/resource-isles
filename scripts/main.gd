extends Node2D

const IslandGeneratorScript := preload("res://scripts/island/island_generator.gd")
const IslandRendererScript := preload("res://scripts/island/island_renderer.gd")
const BuildingMenuScript := preload("res://scripts/ui/building_menu.gd")
const BuildingInfoPanelScript := preload("res://scripts/ui/building_info_panel.gd")
const ResourceBarScript := preload("res://scripts/ui/resource_bar.gd")
const ResourceManagerScript := preload("res://scripts/resources/resource_manager.gd")
const ResourceNodeDatabaseScript := preload("res://scripts/resources/resource_node_database.gd")
const BuildingManagerScript := preload("res://scripts/buildings/building_manager.gd")
const ProductionManagerScript := preload("res://scripts/buildings/production_manager.gd")
const PowerManagerScript := preload("res://scripts/buildings/power_manager.gd")
const FloatingTextScript := preload("res://scripts/ui/floating_text.gd")
const ChopMinigameScript := preload("res://scripts/ui/chop_minigame.gd")
const HarvestButtonScript := preload("res://scripts/ui/harvest_button.gd")
const PlayerUnitScript := preload("res://scripts/player/player_unit.gd")
const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const HexPathfinderScript := preload("res://scripts/island/hex_pathfinder.gd")

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
var current_island: IslandData
var building_manager: BuildingManager
var production_manager: ProductionManager
var power_manager: PowerManager
var resource_manager: ResourceManager
var resource_node_database: ResourceNodeDatabase
var resource_bar: ResourceBar
var building_menu: BuildingMenu
var building_info_panel: BuildingInfoPanel
var chop_minigame: ChopMinigame
var harvest_button: HarvestButton
var player_unit: PlayerUnit
var active_scavenge_cell := Vector2i(-1, -1)
var pending_action_cell := Vector2i(-1, -1)
var harvestable_cell := Vector2i(-1, -1)


func _ready() -> void:
	building_manager = BuildingManagerScript.new()
	resource_manager = ResourceManagerScript.new()
	resource_manager.resource_changed.connect(_on_resource_changed)
	resource_node_database = ResourceNodeDatabaseScript.new()
	building_manager.setup(resource_node_database)
	production_manager = ProductionManagerScript.new()
	production_manager.setup(building_manager, resource_manager)
	production_manager.produced.connect(_on_building_produced)
	production_manager.input_consumed.connect(_on_input_consumed)
	power_manager = PowerManagerScript.new()
	power_manager.setup(building_manager, resource_manager)
	power_manager.fuel_consumed.connect(_on_fuel_consumed)

	renderer = IslandRendererScript.new()
	renderer.name = "IslandRenderer"
	renderer.setup(resource_node_database, building_manager)
	add_child(renderer)

	player_unit = PlayerUnitScript.new()
	player_unit.name = "PlayerUnit"
	player_unit.setup(renderer)
	player_unit.arrived.connect(_on_unit_arrived)
	add_child(player_unit)

	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.enabled = true
	camera.zoom = Vector2(0.375, 0.375)
	add_child(camera)

	_add_ui()
	_generate_island()


func _process(_delta: float) -> void:
	if current_island == null:
		return

	var current_time_seconds := Time.get_ticks_msec() / 1000.0
	power_manager.update(current_island, current_time_seconds)
	production_manager.update(current_island, current_time_seconds)


func _unhandled_input(event: InputEvent) -> void:
	if chop_minigame != null and chop_minigame.active:
		return

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
		_deselect_unit()


func _input(event: InputEvent) -> void:
	if chop_minigame != null and chop_minigame.active:
		return

	if event is InputEventMouseButton:
		var is_over_ui := get_viewport().gui_get_hovered_control() != null

		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_set_zoom(camera.zoom.x * zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_set_zoom(camera.zoom.x / zoom_step)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed and not is_over_ui:
			if player_unit != null and player_unit.selected:
				_command_unit_to_hovered()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not is_over_ui:
			if selected_building_type != NO_BUILDING:
				_try_place_selected_building()
				return

			if _try_select_unit():
				return

			_deselect_unit()
			_try_select_building()

	if event is InputEventMouseMotion and is_panning:
		camera.position -= event.relative / camera.zoom.x

	if event is InputEventMouseMotion:
		renderer.set_hovered_world_position(get_global_mouse_position())


func _set_zoom(new_zoom: float) -> void:
	var clamped_zoom := clampf(new_zoom, min_zoom, max_zoom)
	camera.zoom = Vector2(clamped_zoom, clamped_zoom)
	renderer.queue_redraw()


func _command_unit_to_hovered() -> bool:
	if player_unit == null or current_island == null:
		return false

	var cell := renderer.hovered_cell
	if cell == Vector2i(-1, -1) or not HexPathfinderScript.is_walkable(current_island, cell):
		return false

	pending_action_cell = cell

	if cell == player_unit.current_cell:
		_on_unit_arrived(cell)
		return true

	var path := HexPathfinderScript.find_path(current_island, player_unit.current_cell, cell)
	if path.is_empty():
		pending_action_cell = Vector2i(-1, -1)
		return false

	harvestable_cell = Vector2i(-1, -1)
	harvest_button.hide_button()
	player_unit.follow_path(path)
	return true


func _on_unit_arrived(cell: Vector2i) -> void:
	if cell != pending_action_cell:
		return

	pending_action_cell = Vector2i(-1, -1)
	harvestable_cell = cell if current_island.get_resource_node_type(cell) != -1 else Vector2i(-1, -1)
	_refresh_harvest_button()


func _refresh_harvest_button() -> void:
	if (
		harvestable_cell == Vector2i(-1, -1)
		or player_unit == null
		or player_unit.is_moving()
		or player_unit.current_cell != harvestable_cell
	):
		harvest_button.hide_button()
		return

	var resource_node_type := current_island.get_resource_node_type(harvestable_cell)
	if resource_node_type == -1:
		harvest_button.hide_button()
		return

	harvest_button.show_for(resource_node_database.get_definition(resource_node_type))


func _on_harvest_pressed() -> void:
	if harvestable_cell == Vector2i(-1, -1):
		return

	var resource_node_type := current_island.get_resource_node_type(harvestable_cell)
	if resource_node_type == -1:
		return

	var definition := resource_node_database.get_definition(resource_node_type)
	if definition == null:
		return

	harvest_button.hide_button()
	active_scavenge_cell = harvestable_cell
	chop_minigame.start(definition, _resource_color(definition.extracted_resource_type))


func _on_chop_finished(resource_type: int, total_amount: int) -> void:
	var cell := active_scavenge_cell
	active_scavenge_cell = Vector2i(-1, -1)
	if cell == Vector2i(-1, -1) or current_island == null:
		_refresh_harvest_button()
		return

	if total_amount > 0:
		resource_manager.add_amount(resource_type, total_amount)
		_spawn_floating_text(
			renderer.get_cell_center(cell),
			"+%d %s" % [total_amount, ResourceManager.get_display_name_for_type(resource_type)],
			_resource_color(resource_type)
		)

	_refresh_harvest_button()


func _on_chop_cancelled() -> void:
	active_scavenge_cell = Vector2i(-1, -1)
	_refresh_harvest_button()


func _on_building_produced(anchor_cell: Vector2i, resource_type: int, amount: int) -> void:
	_spawn_floating_text(
		renderer.get_cell_center(anchor_cell),
		"+%d %s" % [amount, ResourceManager.get_display_name_for_type(resource_type)],
		_resource_color(resource_type),
		16
	)


func _on_fuel_consumed(anchor_cell: Vector2i, resource_type: int, amount: int) -> void:
	_spawn_floating_text(
		renderer.get_cell_center(anchor_cell),
		"-%d %s" % [amount, ResourceManager.get_display_name_for_type(resource_type)],
		_resource_color(resource_type),
		16
	)


func _on_input_consumed(anchor_cell: Vector2i, resource_type: int, amount: int) -> void:
	_spawn_floating_text(
		renderer.get_cell_center(anchor_cell),
		"-%d %s" % [amount, ResourceManager.get_display_name_for_type(resource_type)],
		_resource_color(resource_type),
		16
	)


func _spawn_floating_text(world_position: Vector2, text: String, color: Color, font_size := 22) -> void:
	var floating := FloatingTextScript.new()
	floating.text = text
	floating.color = color
	floating.font_size = font_size
	floating.position = world_position
	add_child(floating)


func _resource_color(resource_type: int) -> Color:
	match resource_type:
		GameTypes.ResourceType.WOOD:
			return Color("#d79a4f")
		GameTypes.ResourceType.STONE:
			return Color("#cfcfd6")
		GameTypes.ResourceType.PLANKS:
			return Color("#e8c07a")
		_:
			return Color.WHITE


func _try_select_unit() -> bool:
	if player_unit == null or player_unit.current_cell == Vector2i(-1, -1):
		return false

	if renderer.hovered_cell != player_unit.current_cell:
		return false

	player_unit.set_selected(true)
	return true


func _deselect_unit() -> void:
	if player_unit != null:
		player_unit.set_selected(false)


func _try_select_building() -> bool:
	var building_type := renderer.get_hovered_building_type()
	if building_type == -1:
		return false

	building_info_panel.show_building(building_type, renderer.hovered_cell, current_island)
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
	return building_manager.get_cost(building_type)


func _generate_island() -> void:
	current_island = generator.generate_starter_island(seed_value, building_manager)
	renderer.render(current_island)
	_spawn_player_unit()
	_apply_selected_building()
	_center_camera(current_island)


func _spawn_player_unit() -> void:
	if player_unit == null:
		return

	pending_action_cell = Vector2i(-1, -1)
	harvestable_cell = Vector2i(-1, -1)
	if harvest_button != null:
		harvest_button.hide_button()
	player_unit.place_at(_find_unit_spawn_cell())


func _find_unit_spawn_cell() -> Vector2i:
	var hub_cell := _find_hub_cell()
	if hub_cell != Vector2i(-1, -1):
		for neighbor in HexGridScript.neighbors(hub_cell):
			if HexPathfinderScript.is_walkable(current_island, neighbor) and not current_island.has_building(neighbor):
				return neighbor

	for y in range(current_island.height):
		for x in range(current_island.width):
			var cell := Vector2i(x, y)
			if (
				HexPathfinderScript.is_walkable(current_island, cell)
				and not current_island.has_building(cell)
				and not current_island.has_resource(cell)
			):
				return cell

	return Vector2i.ZERO


func _find_hub_cell() -> Vector2i:
	for cell in current_island.buildings.keys():
		if current_island.buildings[cell].type == GameTypes.BuildingType.HUB:
			return cell

	return Vector2i(-1, -1)


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
	resource_bar.setup(resource_manager, power_manager)

	building_info_panel = BuildingInfoPanelScript.new()
	building_info_panel.setup(building_manager)
	add_child(building_info_panel)

	building_menu = BuildingMenuScript.new()
	building_menu.setup(building_manager)
	building_menu.building_selected.connect(_select_building)
	building_menu.selection_cleared.connect(_select_no_building)
	add_child(building_menu)

	chop_minigame = ChopMinigameScript.new()
	chop_minigame.finished.connect(_on_chop_finished)
	chop_minigame.cancelled.connect(_on_chop_cancelled)
	add_child(chop_minigame)

	harvest_button = HarvestButtonScript.new()
	harvest_button.pressed.connect(_on_harvest_pressed)
	add_child(harvest_button)
