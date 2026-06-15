class_name WorldMap
extends CanvasLayer

# Strategic overlay (not a separate scene) showing every discovered island as a
# token the player can travel to. Islands are laid out in concentric rings around
# the starter island at the center, matching docs/island-unlocks.md. Selecting a
# token asks main to switch the active island; state stays in main.

signal island_selected(index: int)

const RING_SPACING := 160.0
const TOKEN_SIZE := Vector2(132.0, 92.0)

var world: WorldData
var root: Control
var tokens_layer: Control
var is_open := false


func setup(new_world: WorldData) -> void:
	world = new_world


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
	_rebuild_tokens()


func close() -> void:
	is_open = false
	root.visible = false


# Rebuild tokens if the map is showing (e.g. after a new island is discovered).
func refresh() -> void:
	if is_open:
		_rebuild_tokens()


func _build_ui() -> void:
	name = "WorldMap"

	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.06, 0.13, 0.18, 0.84)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	var title := Label.new()
	title.text = "World Map"
	title.add_theme_font_size_override("font_size", 28)
	title.position = Vector2(24.0, 20.0)
	root.add_child(title)

	var hint := Label.new()
	hint.text = "Click an island to travel.   [M] or [Esc] to close."
	hint.position = Vector2(24.0, 58.0)
	root.add_child(hint)

	tokens_layer = Control.new()
	tokens_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	tokens_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tokens_layer)


func _rebuild_tokens() -> void:
	for child in tokens_layer.get_children():
		child.queue_free()

	if world == null:
		return

	var center := get_viewport().get_visible_rect().size * 0.5

	for index in range(world.island_count()):
		var button := Button.new()
		button.custom_minimum_size = TOKEN_SIZE
		button.size = TOKEN_SIZE
		button.position = _token_position(index, center) - TOKEN_SIZE * 0.5

		var island := world.get_island(index)
		button.text = island.island_name if island != null else "World %d" % (index + 1)

		if index == world.current_index:
			button.text += "\n(here)"
			button.disabled = true
		else:
			button.pressed.connect(_on_token_pressed.bind(index))

		tokens_layer.add_child(button)


# Index 0 sits at the center; the rest spiral outward, ring k holding up to 6*k
# tokens (a hex-ish concentric layout).
func _token_position(index: int, center: Vector2) -> Vector2:
	if index == 0:
		return center

	var ring := 1
	var first_in_ring := 1
	while index >= first_in_ring + 6 * ring:
		first_in_ring += 6 * ring
		ring += 1

	var slot := index - first_in_ring
	var slots_in_ring := 6 * ring
	var angle := float(slot) / float(slots_in_ring) * TAU - PI * 0.5
	return center + Vector2(cos(angle), sin(angle)) * (RING_SPACING * ring)


func _on_token_pressed(index: int) -> void:
	island_selected.emit(index)
