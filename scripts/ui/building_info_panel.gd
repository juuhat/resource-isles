class_name BuildingInfoPanel
extends CanvasLayer

# Emitted by the Move / Delete buttons. main wires these up: move re-enters placement
# for the same building type (free), delete removes it outright.
signal move_requested(building_type: int, anchor_cell: Vector2i, island: IslandData)
signal delete_requested(anchor_cell: Vector2i, island: IslandData)

const POWER_ICON := preload("res://assets/icons/power.png")
# Shown for any resource type without a dedicated icon yet (matches ResourceBar's fallback).
const FALLBACK_ICON := preload("res://assets/icons/building.png")

const ICON_SIZE := Vector2(20.0, 20.0)
const SECTION_COLOR := Color("79dcc5")
const MUTED_COLOR := Color("9eafbb")
const WARN_COLOR := Color("ff8a7a")
# How often a shown Dock's route statuses (countdowns, cargo) are refreshed.
const ROUTE_REFRESH_SECONDS := 0.25

var building_manager: BuildingManager
var trade_manager: TradeManager
var world: WorldData
var panel: PanelContainer
var title_label: Label
var detail_box: VBoxContainer
var move_button: Button
var delete_button: Button

# The building currently described, so the action buttons know what they act on.
var current_building_type := -1
var current_anchor_cell := Vector2i(-1, -1)
var current_island: IslandData

# Dock only: [route, status Label] pairs refreshed on a timer, the route count they were built for
# (a change elsewhere triggers a rebuild), and the new-route form's pickers.
var _route_status_labels: Array = []
var _shown_route_count := -1
var _route_refresh_accum := 0.0
var _destination_picker: OptionButton
var _send_picker: OptionButton
var _return_picker: OptionButton
var _start_route_button: Button


func setup(new_building_manager: BuildingManager, new_trade_manager: TradeManager, new_world: WorldData) -> void:
	building_manager = new_building_manager
	trade_manager = new_trade_manager
	world = new_world


func _ready() -> void:
	_build_ui()
	hide_info()


func show_building(building_type: int, cell: Vector2i, island: IslandData) -> void:
	if panel == null:
		return

	var anchor_cell := cell
	if island != null:
		var resolved := island.get_building_anchor_cell(cell)
		if resolved != Vector2i(-1, -1):
			anchor_cell = resolved

	current_building_type = building_type
	current_anchor_cell = anchor_cell
	current_island = island

	title_label.text = _get_building_name(building_type)

	_clear(detail_box)
	var is_blueprint := island != null and island.is_under_construction(anchor_cell)
	if is_blueprint:
		_add_text_line("Under construction: %d%%" % int(island.get_build_progress(anchor_cell) * 100.0), SECTION_COLOR)
		_add_hint("The robot builds it. Right-click it with the robot selected to resume.")
	_add_text_line("Location: %d, %d" % [anchor_cell.x, anchor_cell.y])
	_build_production(building_type, anchor_cell, island)
	_build_input(building_type)
	_build_power(building_type, anchor_cell, island)
	_build_adjacency(building_type, anchor_cell, island)
	_route_status_labels.clear()
	_shown_route_count = -1
	if building_type == GameTypes.BuildingType.DOCK and island != null:
		_build_trade_routes(island)

	# Worldgen / story buildings (the wreck, etc.) are not the player's to move or scrap.
	var definition := building_manager.get_definition(building_type)
	var can_modify := definition != null and definition.player_buildable
	# A blueprint isn't moved; cancelling it refunds its materials.
	move_button.visible = can_modify and not is_blueprint
	delete_button.visible = can_modify
	delete_button.text = "Cancel (refund)" if is_blueprint else "Delete"

	panel.visible = true


func hide_info() -> void:
	if panel != null:
		panel.visible = false


func _build_ui() -> void:
	name = "BuildingInfoPanel"
	# Sit above the always-on quest tracker (default layer 0), which is pinned to the same
	# top-right corner — otherwise the tracker draws over this panel. Stays below the world
	# map (10) and screen fade (100).
	layer = 5

	panel = PanelContainer.new()
	# Fully opaque background so nothing behind the panel (e.g. the quest tracker) shows
	# through it.
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.11, 0.12, 0.15, 1.0)
	background.set_corner_radius_all(6)
	background.set_content_margin_all(0.0)
	panel.add_theme_stylebox_override("panel", background)
	# Pin the top-right corner and let the panel size itself to its content, growing left
	# and down. Pinning both horizontal offsets (the old approach) forced a fixed width that
	# pushed the content off to the right; growing from the anchor keeps it tidy at any size.
	panel.anchor_left = 1.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.offset_left = 0.0
	panel.offset_right = -16.0
	panel.offset_top = 68.0
	panel.offset_bottom = 68.0
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.custom_minimum_size = Vector2(200.0, 0.0)
	margin.add_child(content)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 18)
	content.add_child(title_label)

	detail_box = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 4)
	content.add_child(detail_box)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	content.add_child(actions)

	move_button = Button.new()
	move_button.text = "Move"
	move_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_button.pressed.connect(_on_move_pressed)
	actions.add_child(move_button)

	delete_button = Button.new()
	delete_button.text = "Delete"
	delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_button.pressed.connect(_on_delete_pressed)
	actions.add_child(delete_button)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(hide_info)
	content.add_child(close_button)


func _on_move_pressed() -> void:
	if current_anchor_cell == Vector2i(-1, -1):
		return
	hide_info()
	move_requested.emit(current_building_type, current_anchor_cell, current_island)


func _on_delete_pressed() -> void:
	if current_anchor_cell == Vector2i(-1, -1):
		return
	hide_info()
	delete_requested.emit(current_anchor_cell, current_island)


func _get_building_name(building_type: int) -> String:
	return building_manager.get_display_name(building_type)


func _build_production(building_type: int, anchor_cell: Vector2i, island: IslandData) -> void:
	if island == null:
		return

	var definition := building_manager.get_definition(building_type)
	if definition == null or definition.production_resource_type == -1:
		return

	var amount := building_manager.get_production_amount(anchor_cell, building_type, island)
	_add_icon_line(
		_resource_icon(definition.production_resource_type),
		"Produces %d / %.0fs" % [amount, definition.production_interval_seconds],
		ResourceManager.get_display_name_for_type(definition.production_resource_type),
	)


func _build_input(building_type: int) -> void:
	var definition := building_manager.get_definition(building_type)
	if definition == null or definition.input_resource_type == -1:
		return

	_add_icon_line(
		_resource_icon(definition.input_resource_type),
		"Consumes %d / %.0fs" % [definition.input_amount, definition.production_interval_seconds],
		ResourceManager.get_display_name_for_type(definition.input_resource_type),
	)


func _build_power(building_type: int, anchor_cell: Vector2i, island: IslandData) -> void:
	var definition := building_manager.get_definition(building_type)
	if definition == null:
		return

	if definition.power_generated > 0:
		var text := "+%d MW" % definition.power_generated
		if definition.fuel_resource_type != -1:
			if island != null and not island.is_generator_running(anchor_cell):
				text += " (stalled — no fuel)"
		_add_icon_line(POWER_ICON, text, "Power")
		if definition.fuel_resource_type != -1:
			_add_icon_line(
				_resource_icon(definition.fuel_resource_type),
				"Fuel %d / %.0fs" % [definition.fuel_amount, definition.fuel_interval_seconds],
				ResourceManager.get_display_name_for_type(definition.fuel_resource_type),
			)
		return

	if definition.power_consumed > 0:
		var text := "-%d MW" % definition.power_consumed
		if island != null and not island.is_consumer_powered(anchor_cell):
			text += " (unpowered)"
		_add_icon_line(POWER_ICON, text, "Power")
		_add_text_line("Hand-power: park the robot here and Operate to run it.")


func _build_adjacency(building_type: int, anchor_cell: Vector2i, island: IslandData) -> void:
	if island == null:
		return

	var adjacency := building_manager.get_adjacency_yield(anchor_cell, building_type, island)
	if adjacency.breakdown.is_empty():
		_add_text_line("Adjacency: none")
		return

	_add_text_line("Adjacency: %s" % _signed(adjacency.total))
	for entry in adjacency.breakdown:
		_add_text_line("  %s from %d %s" % [_signed(entry.amount), entry.count, entry.label])


# Icon per resource type, from the central ResourceDatabase (mirrors ResourceBar). Types with
# no icon there still render, with the shared FALLBACK_ICON.
func _resource_icon(resource_type: int) -> Texture2D:
	var definition := ResourceDatabase.get_definition(resource_type)
	if definition == null or definition.icon == null:
		return FALLBACK_ICON
	return definition.icon


func _add_icon_line(icon: Texture2D, text: String, tooltip: String = "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.tooltip_text = tooltip

	var texture_rect := TextureRect.new()
	texture_rect.texture = icon
	texture_rect.custom_minimum_size = ICON_SIZE
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(texture_rect)

	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.tooltip_text = tooltip
	row.add_child(label)

	detail_box.add_child(row)


func _add_text_line(text: String, color: Color = Color.TRANSPARENT) -> void:
	var label := Label.new()
	label.text = text
	if color != Color.TRANSPARENT:
		label.add_theme_color_override("font_color", color)
	detail_box.add_child(label)


# A muted explanatory line, wrapped so it doesn't stretch the panel.
func _add_hint(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 300.0
	label.add_theme_color_override("font_color", MUTED_COLOR)
	detail_box.add_child(label)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _signed(amount: int) -> String:
	return "+%d" % amount if amount >= 0 else str(amount)


# --- Dock: trade routes ---
# Lists every route touching this island (live status), then a form to open a new one from here.
# Each Dock carries one boat, so an island can start as many routes as it has Docks.

func _process(delta: float) -> void:
	if panel == null or not panel.visible or _shown_route_count == -1:
		return
	_route_refresh_accum += delta
	if _route_refresh_accum < ROUTE_REFRESH_SECONDS:
		return
	_route_refresh_accum = 0.0

	var coord := world.coord_of(current_island)
	# A route was added/removed elsewhere (or the Dock count changed): rebuild the whole panel.
	if trade_manager.routes_involving(coord).size() != _shown_route_count:
		show_building(current_building_type, current_anchor_cell, current_island)
		return
	var now := Time.get_ticks_msec() / 1000.0
	for entry in _route_status_labels:
		(entry[1] as Label).text = trade_manager.describe_status(entry[0], now)


func _build_trade_routes(island: IslandData) -> void:
	var coord := world.coord_of(island)
	var routes := trade_manager.routes_involving(coord)
	_shown_route_count = routes.size()
	var now := Time.get_ticks_msec() / 1000.0

	_add_section("TRADE ROUTES")
	var docks := trade_manager.dock_count(coord)
	_add_text_line("Boats: %d of %d in use (one per Dock)" % [trade_manager.routes_from(coord).size(), docks], MUTED_COLOR)

	for route in routes:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		detail_box.add_child(box)
		var header := HBoxContainer.new()
		box.add_child(header)
		var title := Label.new()
		title.text = "%s  ->  %s" % [_island_name(route.home_coord), _island_name(route.away_coord)]
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)
		var remove := Button.new()
		remove.text = "Remove"
		remove.tooltip_text = "Stop this route. Cargo aboard goes back to where it was loaded."
		remove.pressed.connect(_on_remove_route_pressed.bind(route))
		header.add_child(remove)
		var cargo := Label.new()
		cargo.text = "Out: %s  ·  Back: %s  ·  Delivered %d" % [
			_resource_name(route.outbound_resource), _resource_name(route.return_resource), route.delivered_total,
		]
		cargo.add_theme_color_override("font_color", MUTED_COLOR)
		box.add_child(cargo)
		var status := Label.new()
		status.text = trade_manager.describe_status(route, now)
		var idle := not trade_manager.blocked_reason(route).is_empty()
		status.add_theme_color_override("font_color", WARN_COLOR if idle else SECTION_COLOR)
		box.add_child(status)
		_route_status_labels.append([route, status])

	_build_new_route_form(coord)


func _build_new_route_form(coord: Vector2i) -> void:
	_add_section("NEW ROUTE FROM %s" % _island_name(coord).to_upper())
	var destinations := trade_manager.reachable_destinations(coord)
	if destinations.is_empty():
		_add_hint("Build a Dock on another island to open a route to it.")
		return
	if trade_manager.free_boats(coord) <= 0:
		_add_hint("Every boat here is busy. Build another Dock for another route.")
		return

	_destination_picker = OptionButton.new()
	for destination in destinations:
		_destination_picker.add_item(_island_name(destination))
		_destination_picker.set_item_metadata(_destination_picker.item_count - 1, destination)
	_add_form_row("To", _destination_picker)

	_send_picker = _resource_picker(GameTypes.ResourceType.WOOD)
	_add_form_row("Send", _send_picker)
	_return_picker = _resource_picker(TradeRoute.NO_RESOURCE)
	_add_form_row("Bring back", _return_picker)

	_start_route_button = Button.new()
	_start_route_button.text = "Start route"
	_start_route_button.pressed.connect(_on_start_route_pressed.bind(coord))
	detail_box.add_child(_start_route_button)
	_send_picker.item_selected.connect(func(_index: int) -> void: _update_start_button())
	_return_picker.item_selected.connect(func(_index: int) -> void: _update_start_button())
	_update_start_button()
	_add_hint("Boats carry %d per trip; farther islands take longer." % TradeManager.BOAT_CAPACITY)


func _resource_picker(selected_resource: int) -> OptionButton:
	var picker := OptionButton.new()
	picker.add_item("Nothing")
	picker.set_item_metadata(0, TradeRoute.NO_RESOURCE)
	for resource_type in GameTypes.ResourceType.values():
		picker.add_icon_item(_resource_icon(resource_type), _resource_name(resource_type))
		picker.set_item_metadata(picker.item_count - 1, resource_type)
		if resource_type == selected_resource:
			picker.select(picker.item_count - 1)
	picker.add_theme_constant_override("icon_max_width", int(ICON_SIZE.x))
	return picker


func _add_form_row(caption: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 84.0
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	detail_box.add_child(row)


func _update_start_button() -> void:
	var nothing := int(_send_picker.get_selected_metadata()) == TradeRoute.NO_RESOURCE \
			and int(_return_picker.get_selected_metadata()) == TradeRoute.NO_RESOURCE
	_start_route_button.disabled = nothing
	_start_route_button.tooltip_text = "Pick something to send or bring back." if nothing else ""


func _on_start_route_pressed(coord: Vector2i) -> void:
	trade_manager.create_route(
		coord,
		_destination_picker.get_selected_metadata(),
		int(_send_picker.get_selected_metadata()),
		int(_return_picker.get_selected_metadata())
	)
	show_building(current_building_type, current_anchor_cell, current_island)


func _on_remove_route_pressed(route: TradeRoute) -> void:
	trade_manager.remove_route(route)
	show_building(current_building_type, current_anchor_cell, current_island)


func _add_section(text: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 4.0
	detail_box.add_child(spacer)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", SECTION_COLOR)
	detail_box.add_child(label)


func _island_name(coord: Vector2i) -> String:
	var island := world.get_island(coord)
	return island.island_name if island != null else "?"


func _resource_name(resource_type: int) -> String:
	if resource_type == TradeRoute.NO_RESOURCE:
		return "nothing"
	return ResourceManager.get_display_name_for_type(resource_type)
