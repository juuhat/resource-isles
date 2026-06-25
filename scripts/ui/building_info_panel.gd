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

var building_manager: BuildingManager
var panel: PanelContainer
var title_label: Label
var detail_box: VBoxContainer
var move_button: Button
var delete_button: Button

# The building currently described, so the action buttons know what they act on.
var current_building_type := -1
var current_anchor_cell := Vector2i(-1, -1)
var current_island: IslandData


func setup(new_building_manager: BuildingManager) -> void:
	building_manager = new_building_manager


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
	_add_text_line("Location: %d, %d" % [anchor_cell.x, anchor_cell.y])
	_build_production(building_type, anchor_cell, island)
	_build_input(building_type)
	_build_power(building_type, anchor_cell, island)
	_build_adjacency(building_type, anchor_cell, island)

	# Worldgen / story buildings (the wreck, etc.) are not the player's to move or scrap.
	var definition := building_manager.get_definition(building_type)
	var can_modify := definition != null and definition.player_buildable
	move_button.visible = can_modify
	delete_button.visible = can_modify

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


func _add_text_line(text: String) -> void:
	var label := Label.new()
	label.text = text
	detail_box.add_child(label)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _signed(amount: int) -> String:
	return "+%d" % amount if amount >= 0 else str(amount)
