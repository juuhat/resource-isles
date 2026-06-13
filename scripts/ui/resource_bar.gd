class_name ResourceBar
extends CanvasLayer

const ResourceManagerScript := preload("res://scripts/resources/resource_manager.gd")

var resource_manager: ResourceManager
var resource_labels: Dictionary = {}


func setup(new_resource_manager: ResourceManager) -> void:
	resource_manager = new_resource_manager
	resource_manager.resource_changed.connect(_on_resource_changed)
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

	var wood_label := Label.new()
	resource_labels[ResourceManager.ResourceType.WOOD] = wood_label
	row.add_child(wood_label)

	var stone_label := Label.new()
	resource_labels[ResourceManager.ResourceType.STONE] = stone_label
	row.add_child(stone_label)


func _refresh_all() -> void:
	if resource_manager == null or resource_labels.is_empty():
		return

	for resource_type in resource_labels.keys():
		_update_label(resource_type)


func _on_resource_changed(resource_type: int, _amount: int) -> void:
	_update_label(resource_type)


func _update_label(resource_type: int) -> void:
	if resource_manager == null or not resource_labels.has(resource_type):
		return

	var label: Label = resource_labels[resource_type]
	label.text = "%s: %d" % [
		resource_manager.get_display_name(resource_type),
		resource_manager.get_amount(resource_type),
	]
