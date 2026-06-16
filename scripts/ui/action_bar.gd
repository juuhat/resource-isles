class_name ActionBar
extends CanvasLayer

# The player robot's command bar (Civ 6 unit-command style). A persistent portrait button
# sits in the bottom-right corner (mirroring the building-menu button in the bottom-left);
# clicking it selects the robot. Whatever actions the robot can take on its current tile —
# harvest a node, operate a manual generator, and so on — appear as icon buttons in a row to
# the LEFT of the portrait.
#
# It is a pure view: main.gd decides which actions exist and what each does, the bar just
# renders them and emits the pressed action's id (or a select request) back. The action row
# is hidden whenever there are no actions (e.g. the robot is standing on empty ground); the
# portrait is always visible. Add a new robot action by feeding set_actions another entry.

signal action_pressed(action_id: int)
signal select_requested

const PORTRAIT_TEXTURE := preload("res://assets/player/player_robot.png")
const CANCEL_TEXTURE := preload("res://assets/icons/cancel.png")
# Square footprint matching the building-menu button (88 px, 16 px from the screen edges).
const BUTTON_SIZE := 88.0
const EDGE_MARGIN := 16.0
const ICON_MAX_WIDTH := 64

var portrait: Button
var action_row: HBoxContainer


func _ready() -> void:
	_build_ui()
	set_actions([])
	set_selected(false)


# actions: an ordered Array of { id: int, icon: Texture2D, label: String, active: bool },
# rendered right-to-left next to the portrait. `active` marks an engaged toggle (e.g. a
# generator currently running); it overlays a cancel icon so the button reads as "cancel
# this task". The label becomes the button's tooltip.
func set_actions(actions: Array) -> void:
	if action_row == null:
		return

	for child in action_row.get_children():
		action_row.remove_child(child)
		child.queue_free()

	for action in actions:
		action_row.add_child(_build_action_button(action))

	action_row.visible = not actions.is_empty()


# Highlight the portrait while the robot is selected; dim it (as a "click to select" hint)
# otherwise.
func set_selected(is_selected: bool) -> void:
	if portrait != null:
		portrait.modulate = Color.WHITE if is_selected else Color(1.0, 1.0, 1.0, 0.6)


func _build_action_button(action: Dictionary) -> Button:
	var is_active: bool = action.get("active", false)

	var button := Button.new()
	button.icon = action.get("icon")
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", ICON_MAX_WIDTH)
	button.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	button.tooltip_text = action.get("label", "")
	# Idle actions are slightly dimmed; active ones render full strength and get a cancel
	# overlay so pressing the button reads as cancelling the running task.
	button.modulate = Color.WHITE if is_active else Color(1.0, 1.0, 1.0, 0.85)
	var action_id: int = action.get("id", -1)
	button.pressed.connect(func() -> void: action_pressed.emit(action_id))

	if is_active:
		button.add_child(_build_cancel_overlay())

	return button


# A cancel icon centered on top of an active action button. Ignores mouse input so the
# click still falls through to the button itself.
func _build_cancel_overlay() -> TextureRect:
	var overlay := TextureRect.new()
	overlay.texture = CANCEL_TEXTURE
	overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Inset so the cancel badge sits within the button rather than covering its edges.
	overlay.offset_left = 12.0
	overlay.offset_top = 12.0
	overlay.offset_right = -12.0
	overlay.offset_bottom = -12.0
	return overlay


func _build_ui() -> void:
	name = "ActionBar"

	# Portrait: bottom-right corner, mirror of the building-menu button on the left.
	portrait = Button.new()
	portrait.icon = PORTRAIT_TEXTURE
	portrait.expand_icon = true
	portrait.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait.add_theme_constant_override("icon_max_width", ICON_MAX_WIDTH + 8)
	portrait.anchor_left = 1.0
	portrait.anchor_top = 1.0
	portrait.anchor_right = 1.0
	portrait.anchor_bottom = 1.0
	portrait.offset_left = -(EDGE_MARGIN + BUTTON_SIZE)
	portrait.offset_top = -(EDGE_MARGIN + BUTTON_SIZE)
	portrait.offset_right = -EDGE_MARGIN
	portrait.offset_bottom = -EDGE_MARGIN
	portrait.pressed.connect(func() -> void: select_requested.emit())
	add_child(portrait)

	# Action row: anchored just left of the portrait, grows leftward to fit its buttons.
	action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	action_row.alignment = BoxContainer.ALIGNMENT_END
	action_row.anchor_left = 1.0
	action_row.anchor_top = 1.0
	action_row.anchor_right = 1.0
	action_row.anchor_bottom = 1.0
	var row_right := -(EDGE_MARGIN + BUTTON_SIZE + EDGE_MARGIN)
	action_row.offset_left = row_right
	action_row.offset_right = row_right
	action_row.offset_top = -(EDGE_MARGIN + BUTTON_SIZE)
	action_row.offset_bottom = -EDGE_MARGIN
	action_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(action_row)
