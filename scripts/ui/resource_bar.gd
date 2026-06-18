class_name ResourceBar
extends CanvasLayer

# Top-of-screen stock readout. It is DATA-DRIVEN over GameTypes.ResourceType: one entry per
# resource type, each REVEALED only once the player has ever gathered that resource (lifetime
# total >= 1, read from the StatTracker). New resource types added to the enum show up here
# automatically — give them an icon below; the display name is derived from the enum key.

const ResourceManagerScript := preload("res://scripts/resources/resource_manager.gd")
const WOOD_ICON := preload("res://assets/icons/wood_log.png")
const STONE_ICON := preload("res://assets/icons/stone.png")
const PLANKS_ICON := preload("res://assets/icons/wood_plank.png")
const COAL_ICON := preload("res://assets/icons/coal_ore.png")
const POWER_ICON := preload("res://assets/icons/power.png")
# Shown for any resource type without a dedicated icon yet (a dev nudge, not a final look).
const FALLBACK_ICON := preload("res://assets/icons/building.png")

const ICON_SIZE := Vector2(32.0, 32.0)

var resource_manager: ResourceManager
var power_manager: PowerManager
var stat_tracker: StatTracker
# resource_type -> Label (the count) and resource_type -> Control (the show/hide row entry).
var resource_labels: Dictionary = {}
var resource_entries: Dictionary = {}
var power_label: Label
var power_icon: TextureRect


func setup(
	new_resource_manager: ResourceManager,
	new_power_manager: PowerManager,
	new_stat_tracker: StatTracker
) -> void:
	resource_manager = new_resource_manager
	resource_manager.resource_changed.connect(_on_resource_changed)
	power_manager = new_power_manager
	power_manager.power_changed.connect(_on_power_changed)
	stat_tracker = new_stat_tracker
	# Lifetime totals crossing 1 are what reveal a resource's icon.
	stat_tracker.stat_changed.connect(_on_stat_changed)
	_refresh_all()


func _ready() -> void:
	_build_ui()
	_refresh_all()


# Icon per resource type. Types missing here still appear, with FALLBACK_ICON.
func _resource_icon(resource_type: int) -> Texture2D:
	match resource_type:
		GameTypes.ResourceType.WOOD:
			return WOOD_ICON
		GameTypes.ResourceType.STONE:
			return STONE_ICON
		GameTypes.ResourceType.PLANKS:
			return PLANKS_ICON
		GameTypes.ResourceType.COAL:
			return COAL_ICON
		GameTypes.ResourceType.IRON_ORE:
			# Placeholder: reuses the stone icon until iron art exists.
			return STONE_ICON
		_:
			return FALLBACK_ICON


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

	# One entry per resource type, in enum order. capitalize() turns the enum key into a
	# label ("IRON_ORE" -> "Iron Ore"), so names stay in sync with the enum for free.
	var names := GameTypes.ResourceType.keys()
	var values := GameTypes.ResourceType.values()
	for i in values.size():
		var resource_type: int = values[i]
		var display_name := String(names[i]).capitalize()
		var label := _add_resource_entry(row, _resource_icon(resource_type), display_name)
		resource_labels[resource_type] = label
		# The entry's row container is the icon+label HBox we just appended.
		resource_entries[resource_type] = row.get_child(row.get_child_count() - 1)

	power_label = _add_power_entry(row)


# Redraw every label and re-evaluate which resources are revealed. Call after the active
# island (and thus the resource_manager's inventory) changes.
func refresh() -> void:
	_refresh_all()


func _refresh_all() -> void:
	if resource_manager == null or resource_labels.is_empty():
		return

	for resource_type in resource_labels.keys():
		_update_label(resource_type)
		_update_visibility(resource_type)

	if power_manager != null:
		_update_power(power_manager.total_generated, power_manager.total_consumed)


func _on_resource_changed(resource_type: int, _amount: int) -> void:
	_update_label(resource_type)


func _on_stat_changed(_stat: int, _value: int) -> void:
	# A lifetime total may have just crossed 1 and unlocked a resource's icon. Re-checking
	# every entry is cheap (a handful of types) and avoids mapping stat -> resource here.
	for resource_type in resource_entries.keys():
		_update_visibility(resource_type)


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


# A resource is shown once it has ever been gathered (lifetime total >= 1). Once revealed it
# stays revealed — lifetime totals only go up — even on an island where the current stock is 0.
func _update_visibility(resource_type: int) -> void:
	if not resource_entries.has(resource_type):
		return
	var entry: Control = resource_entries[resource_type]
	entry.visible = stat_tracker != null and stat_tracker.lifetime_gathered(resource_type) >= 1


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
