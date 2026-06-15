class_name ResourceBar
extends CanvasLayer

const ResourceManagerScript := preload("res://scripts/resources/resource_manager.gd")
const WOOD_ICON := preload("res://assets/icons/wood_log.png")
const STONE_ICON := preload("res://assets/icons/stone.png")
const POWER_ICON := preload("res://assets/icons/power.png")

const ICON_SIZE := Vector2(32.0, 32.0)

var resource_manager: ResourceManager
var power_manager: PowerManager
var resource_labels: Dictionary = {}
var power_label: Label
var power_icon: TextureRect


func setup(new_resource_manager: ResourceManager, new_power_manager: PowerManager) -> void:
	resource_manager = new_resource_manager
	resource_manager.resource_changed.connect(_on_resource_changed)
	power_manager = new_power_manager
	power_manager.power_changed.connect(_on_power_changed)
	_refresh_all()


func _ready() -> void:
	_build_ui()
	_refresh_all()


func _build_ui() -> void:
	name = "ResourceBar"

	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.0
	panel.offset_left = 16.0
	panel.offset_top = 12.0
	panel.offset_right = -16.0
	panel.offset_bottom = 52.0
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)

	resource_labels[GameTypes.ResourceType.WOOD] = _add_resource_entry(
		row,
		WOOD_ICON,
		"Wood"
	)
	resource_labels[GameTypes.ResourceType.STONE] = _add_resource_entry(
		row,
		STONE_ICON,
		"Stone"
	)
	power_label = _add_power_entry(row)


func _refresh_all() -> void:
	if resource_manager == null or resource_labels.is_empty():
		return

	for resource_type in resource_labels.keys():
		_update_label(resource_type)

	if power_manager != null:
		_update_power(power_manager.total_generated, power_manager.total_consumed)


func _on_resource_changed(resource_type: int, _amount: int) -> void:
	_update_label(resource_type)


func _on_power_changed(generated: int, consumed: int) -> void:
	_update_power(generated, consumed)


func _update_power(generated: int, consumed: int) -> void:
	if power_label == null:
		return

	var net := generated - consumed
	power_label.text = "%s%d MW" % ["+" if net >= 0 else "-", abs(net)]
	power_label.modulate = Color("#e06c6c") if net < 0 else Color.WHITE
	if power_icon != null:
		power_icon.modulate = Color("#e06c6c") if net < 0 else Color.WHITE


func _update_label(resource_type: int) -> void:
	if resource_manager == null or not resource_labels.has(resource_type):
		return

	var label: Label = resource_labels[resource_type]
	label.text = str(resource_manager.get_amount(resource_type))


func _add_resource_entry(parent: Container, icon: Texture2D, tooltip: String) -> Label:
	var entry := _create_icon_entry(parent, icon, tooltip)
	var label := Label.new()
	label.tooltip_text = tooltip
	entry.add_child(label)
	return label


func _add_power_entry(parent: Container) -> Label:
	var entry := _create_icon_entry(parent, POWER_ICON, "Power")
	power_icon = entry.get_child(0) as TextureRect
	var label := Label.new()
	label.tooltip_text = "Power"
	entry.add_child(label)
	return label


func _create_icon_entry(parent: Container, icon: Texture2D, tooltip: String) -> HBoxContainer:
	var entry := HBoxContainer.new()
	entry.tooltip_text = tooltip
	entry.add_theme_constant_override("separation", 4)
	parent.add_child(entry)

	var texture_rect := TextureRect.new()
	texture_rect.texture = icon
	texture_rect.custom_minimum_size = ICON_SIZE
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.tooltip_text = tooltip
	entry.add_child(texture_rect)

	return entry
