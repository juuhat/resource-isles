class_name HarvestButton
extends CanvasLayer

# A pickaxe action button shown on the left edge of the screen when the robot is
# parked on a harvestable node. Pressing it toggles continuous harvesting.

signal pressed

const PICKAXE_TEXTURE := preload("res://assets/icons/pickaxe.png")
const ICON_SIZE := 64.0

var panel: PanelContainer
var label: Label


func _ready() -> void:
	_build_ui()
	hide_button()


func show_for(definition: ResourceNodeDefinition, is_harvesting := false) -> void:
	if panel == null:
		return

	var node_name := definition.display_name if definition != null else ""
	if is_harvesting:
		label.text = "Stop harvesting" if node_name.is_empty() else "Stop (%s)" % node_name
	elif node_name.is_empty():
		label.text = "Harvest"
	else:
		label.text = "Harvest %s" % node_name

	panel.visible = true


func hide_button() -> void:
	if panel != null:
		panel.visible = false


func _build_ui() -> void:
	name = "HarvestButton"

	panel = PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = 24.0
	panel.offset_top = -64.0
	panel.offset_right = 124.0
	panel.offset_bottom = 64.0
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(content)

	var button := TextureButton.new()
	button.texture_normal = PICKAXE_TEXTURE
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(func() -> void: pressed.emit())
	content.add_child(button)

	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(label)
