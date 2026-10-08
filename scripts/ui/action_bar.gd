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

const PLAYER_MODEL := preload("res://assets/models/units/salvage_robot.glb")
const CANCEL_TEXTURE := preload("res://assets/icons/cancel.png")
# Square footprint matching the building-menu button (88 px, 16 px from the screen edges).
const BUTTON_SIZE := 88.0
const EDGE_MARGIN := 16.0
const ICON_MAX_WIDTH := 64

var _portrait_blink: RefCounted

var portrait: Button
var action_row: HBoxContainer
var portrait_viewport: SubViewport


func _process(delta: float) -> void:
	if _portrait_blink != null:
		_portrait_blink.update(delta)


func _ready() -> void:
	_build_ui()
	set_actions([])
	set_selected(false)


# actions: an ordered Array of { id: int, icon: Texture2D, label: String, active: bool },
# laid out left to right, the last one next to the portrait. `active` marks an engaged toggle (e.g. a
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
	button.text = action.get("caption", "")
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", ICON_MAX_WIDTH)
	if not button.text.is_empty():
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.add_theme_constant_override("icon_max_width", 48)
		button.add_theme_font_size_override("font_size", 14)
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
	portrait.tooltip_text = "Select player and center camera"
	portrait.icon = _build_player_portrait()
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


# A separate, tiny world keeps the portrait's idle pose and lighting independent of play.
func _build_player_portrait() -> Texture2D:
	portrait_viewport = SubViewport.new()
	portrait_viewport.name = "PlayerPortrait"
	portrait_viewport.size = Vector2i(176, 176)
	portrait_viewport.own_world_3d = true
	portrait_viewport.transparent_bg = true
	portrait_viewport.gui_disable_input = true
	portrait_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(portrait_viewport)

	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.65
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	portrait_viewport.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	portrait_viewport.add_child(light)

	var model := PLAYER_MODEL.instantiate() as Node3D
	portrait_viewport.add_child(model)
	_portrait_blink = PlayerUnit.RobotBlink.new(model)
	for tool_name in PlayerUnit.WORK_CLIPS.values():
		var tool := model.find_child(tool_name, true, false) as Node3D
		if tool != null:
			tool.hide()
	var animation_player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player != null:
		for animation_name in animation_player.get_animation_list():
			if String(animation_name).get_file().to_lower() == "idle":
				animation_player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
				animation_player.play(animation_name)
				break

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.85
	portrait_viewport.add_child(camera)
	var portrait_center := Vector3(0.0, 1.0, 0.0)
	camera.look_at_from_position(portrait_center + Vector3(0.7, 0.2, 3.0), portrait_center)
	camera.current = true
	return portrait_viewport.get_texture()
