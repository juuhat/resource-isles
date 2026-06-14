class_name BuildingInfoPanel
extends CanvasLayer

var building_manager: BuildingManager
var panel: PanelContainer
var title_label: Label
var detail_label: Label


func setup(new_building_manager: BuildingManager) -> void:
	building_manager = new_building_manager


func _ready() -> void:
	_build_ui()
	hide_info()


func show_building(building_type: int, cell: Vector2i, island: IslandData) -> void:
	if panel == null:
		return

	title_label.text = _get_building_name(building_type)

	var anchor_cell := cell
	if island != null:
		var resolved := island.get_building_anchor_cell(cell)
		if resolved != Vector2i(-1, -1):
			anchor_cell = resolved

	var lines: Array[String] = ["Location: %d, %d" % [cell.x, cell.y]]

	var production_line := _format_production(building_type, anchor_cell, island)
	if not production_line.is_empty():
		lines.append(production_line)

	lines.append(_format_adjacency(building_type, anchor_cell, island))

	detail_label.text = "\n".join(lines)
	panel.visible = true


func hide_info() -> void:
	if panel != null:
		panel.visible = false


func _build_ui() -> void:
	name = "BuildingInfoPanel"

	panel = PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -236.0
	panel.offset_top = 68.0
	panel.offset_right = -16.0
	panel.offset_bottom = 176.0
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)

	title_label = Label.new()
	content.add_child(title_label)

	detail_label = Label.new()
	content.add_child(detail_label)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(hide_info)
	content.add_child(close_button)


func _get_building_name(building_type: int) -> String:
	return building_manager.get_display_name(building_type)


func _format_production(building_type: int, anchor_cell: Vector2i, island: IslandData) -> String:
	if island == null:
		return ""

	var definition := building_manager.get_definition(building_type)
	if definition == null or definition.production_resource_type == -1:
		return ""

	var amount := building_manager.get_production_amount(anchor_cell, building_type, island)
	return "Produces: %d %s / %.0fs" % [
		amount,
		ResourceManager.get_display_name_for_type(definition.production_resource_type),
		definition.production_interval_seconds,
	]


func _format_adjacency(building_type: int, anchor_cell: Vector2i, island: IslandData) -> String:
	if island == null:
		return ""

	var adjacency := building_manager.get_adjacency_yield(anchor_cell, building_type, island)
	if adjacency.breakdown.is_empty():
		return "Adjacency: none"

	var lines: Array[String] = ["Adjacency: %s" % _signed(adjacency.total)]
	for entry in adjacency.breakdown:
		lines.append("  %s from %d %s" % [_signed(entry.amount), entry.count, entry.label])

	return "\n".join(lines)


func _signed(amount: int) -> String:
	return "+%d" % amount if amount >= 0 else str(amount)
