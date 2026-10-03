class_name WorldMap
extends CanvasLayer

# Strategic overlay (not a separate scene) showing the world as what it is: a flat-disc planet
# floating in space (WorldMapDisc, rendered in its own 3D world inside a SubViewport). State
# stays in main; selecting a slot asks main to enter that island (travel, or
# generate-then-travel). See docs/island-unlocks.md.
#
# Mouse: click an island to enter it, drag to orbit, wheel to zoom, double-click to reset.

const WorldMapDiscScript := preload("res://scripts/world/world_map_disc.gd")

const DRAG_THRESHOLD := 6.0
const HINT_TEXT := "Click an island to travel  ·  Click a ? to discover it  ·  Drag to orbit  ·  Scroll to zoom  ·  [M] / [Esc] close"

signal slot_activated(coord: Vector2i)

var world: WorldData
var root: Control
var viewport: SubViewport
var disc: WorldMapDisc
var status_label: Label
var is_open := false

var _left_down := false
var _dragging := false
var _press_position := Vector2.ZERO


func setup(new_world: WorldData) -> void:
	world = new_world
	if disc != null:
		disc.setup(world)


func _ready() -> void:
	layer = 10
	_build_ui()
	close()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	is_open = true
	root.visible = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	disc.process_mode = Node.PROCESS_MODE_INHERIT
	disc.refresh()
	disc.play_intro()
	_update_hover(root.get_local_mouse_position())


func close() -> void:
	is_open = false
	root.visible = false
	_left_down = false
	_dragging = false
	# Nothing to draw or animate while hidden.
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	disc.process_mode = Node.PROCESS_MODE_DISABLED


# Rebuild if showing (e.g. after a new island is discovered or travelled to).
func refresh() -> void:
	if is_open:
		disc.refresh()


func _build_ui() -> void:
	name = "WorldMap"

	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(_on_gui_input)
	add_child(root)

	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(container)

	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.handle_input_locally = false
	container.add_child(viewport)

	disc = WorldMapDiscScript.new()
	disc.setup(world)
	viewport.add_child(disc)

	var title := Label.new()
	title.text = "World Map"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color("#15202e"))
	title.position = Vector2(24.0, 20.0)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)

	var hint := Label.new()
	hint.text = HINT_TEXT
	hint.add_theme_constant_override("outline_size", 6)
	hint.add_theme_color_override("font_outline_color", Color("#15202e"))
	hint.position = Vector2(24.0, 58.0)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)

	# What a click would do right now, pinned to the bottom centre.
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 20)
	status_label.add_theme_constant_override("outline_size", 8)
	status_label.add_theme_color_override("font_outline_color", Color("#15202e"))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	status_label.offset_left = -400.0
	status_label.offset_right = 400.0
	status_label.offset_top = -64.0
	status_label.offset_bottom = -32.0
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status_label)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					disc.zoom(0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					disc.zoom(1.1)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_on_drag_button(button)
		root.accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _left_down and not _dragging and motion.position.distance_to(_press_position) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			disc.orbit(motion.relative)
		_update_hover(motion.position)
		root.accept_event()


# Any mouse button drags to orbit; a left click without a drag picks a slot.
func _on_drag_button(button: InputEventMouseButton) -> void:
	if button.pressed:
		if button.double_click:
			disc.reset_view()
		_left_down = true
		_dragging = false
		_press_position = button.position
		return

	var was_click := _left_down and not _dragging and button.button_index == MOUSE_BUTTON_LEFT
	_left_down = false
	_dragging = false
	if was_click:
		var coord := disc.slot_at_screen(_to_viewport(button.position))
		if coord != WorldData.NO_COORD:
			slot_activated.emit(coord)


func _update_hover(screen_position: Vector2) -> void:
	var coord := WorldData.NO_COORD if _dragging else disc.slot_at_screen(_to_viewport(screen_position))
	disc.set_hovered(coord)
	status_label.text = _describe_slot(coord)


func _describe_slot(coord: Vector2i) -> String:
	if coord == WorldData.NO_COORD:
		return ""
	if not world.has_island(coord):
		return "Uncharted island — click to discover it"
	var island := world.get_island(coord)
	if coord == world.current_coord:
		return "%s — you are here" % island.island_name
	return "%s — click to travel" % island.island_name


# Overlay and viewport share the full screen at 1:1 (stretch, no shrink), but map through the
# size ratio anyway so a future stretch_shrink doesn't silently break picking.
func _to_viewport(screen_position: Vector2) -> Vector2:
	var screen_size := root.size
	if screen_size.x <= 0.0 or screen_size.y <= 0.0:
		return screen_position
	return screen_position * Vector2(viewport.size) / screen_size
