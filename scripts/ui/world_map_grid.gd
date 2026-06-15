class_name WorldMapGrid
extends Control

# Draws the world map as a flat-color, thick-outline hex grid (cartoon style, see
# README art direction): the starter at the center, concentric rings of water with
# three island slots per ring (every other ring "corner", 120 deg apart). Clicking
# an island slot asks to enter it — travel if generated, otherwise generate then
# travel. Per-island art comes later; for now slots are stylized tokens.

signal slot_activated(coord: Vector2i)

const HEX_SIZE := 54.0
const OUTLINE_WIDTH := 4.0

const WATER_FILL := Color("#3a8fc0")
const ISLAND_FILL := Color("#9ea131")
const ISLAND_SAND := Color("#e3bc83")
const UNEXPLORED_FILL := Color("#356d92")
const OUTLINE := Color("#15202e")
const CURRENT_OUTLINE := Color("#f2c14e")
const TEXT_COLOR := Color("#10202c")
const LABEL_FONT_SIZE := 16

const CUBE_DIRS := [
	Vector3i(1, -1, 0),
	Vector3i(1, 0, -1),
	Vector3i(0, 1, -1),
	Vector3i(-1, 1, 0),
	Vector3i(-1, 0, 1),
	Vector3i(0, -1, 1),
]
# Island slots sit on every other ring corner -> 3 per ring, 120 deg apart.
const SLOT_DIRECTIONS := [0, 2, 4]

var world: WorldData
# How many rings out are revealed. A constant for now; boat tiers will drive it.
var revealed_rings := 2


func setup(new_world: WorldData) -> void:
	world = new_world


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _notification(what: int) -> void:
	# Re-center when the viewport/control is resized.
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	if world == null:
		return

	var center := size * 0.5

	# Water first (every revealed cell that is not an island slot)...
	for ring in range(0, revealed_rings + 1):
		for cube in _ring_cells_cube(ring):
			var coord := _cube_to_axial(cube)
			if not _is_island_slot(coord):
				_draw_water_hex(center, coord)

	# ...then island slots on top.
	for coord in _island_slots():
		_draw_island_hex(center, coord)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return

	var mouse_button := event as InputEventMouseButton
	if mouse_button.button_index != MOUSE_BUTTON_LEFT or not mouse_button.pressed:
		return

	var coord := _pixel_to_axial(size * 0.5, mouse_button.position)
	if _is_island_slot(coord):
		slot_activated.emit(coord)


func _draw_water_hex(center: Vector2, coord: Vector2i) -> void:
	var corners := _hex_corners(_axial_to_pixel(center, coord))
	draw_colored_polygon(corners, WATER_FILL)
	_draw_outline(corners, OUTLINE, OUTLINE_WIDTH)


func _draw_island_hex(center: Vector2, coord: Vector2i) -> void:
	var pos := _axial_to_pixel(center, coord)
	var corners := _hex_corners(pos)
	var generated := world.has_island(coord)
	var is_current := generated and coord == world.current_coord

	if generated:
		draw_colored_polygon(corners, ISLAND_FILL)
		draw_circle(pos, HEX_SIZE * 0.34, ISLAND_SAND)
	else:
		draw_colored_polygon(corners, UNEXPLORED_FILL)

	_draw_outline(corners, CURRENT_OUTLINE if is_current else OUTLINE, OUTLINE_WIDTH)

	var label := "?"
	if generated:
		var island := world.get_island(coord)
		label = island.island_name if island != null else ""
		if is_current:
			label += "\n(here)"

	_draw_label(pos, label)


func _draw_outline(corners: PackedVector2Array, color: Color, width: float) -> void:
	var closed := corners.duplicate()
	closed.append(corners[0])
	draw_polyline(closed, color, width, true)


func _draw_label(center: Vector2, text: String) -> void:
	if text.is_empty():
		return

	var font := get_theme_default_font()
	if font == null:
		return

	var lines := text.split("\n")
	var line_height := LABEL_FONT_SIZE + 3
	var y := center.y - (lines.size() - 1) * line_height * 0.5 + LABEL_FONT_SIZE * 0.35

	for line in lines:
		var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x
		draw_string(font, Vector2(center.x - width * 0.5, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, TEXT_COLOR)
		y += line_height


# --- hex math (axial Vector2i = (q, r); cube Vector3i = (x, y, z), x + y + z = 0) ---

func _island_slots() -> Array:
	var slots := [WorldData.CENTER]
	for ring in range(1, revealed_rings + 1):
		for direction in SLOT_DIRECTIONS:
			slots.append(_cube_to_axial(CUBE_DIRS[direction] * ring))

	return slots


func _is_island_slot(coord: Vector2i) -> bool:
	if coord == WorldData.CENTER:
		return true

	var ring := _axial_ring(coord)
	if ring < 1 or ring > revealed_rings:
		return false

	for direction in SLOT_DIRECTIONS:
		if _cube_to_axial(CUBE_DIRS[direction] * ring) == coord:
			return true

	return false


func _ring_cells_cube(radius: int) -> Array:
	if radius == 0:
		return [Vector3i(0, 0, 0)]

	var results := []
	var cube := CUBE_DIRS[4] * radius
	for i in range(6):
		for j in range(radius):
			results.append(cube)
			cube = cube + CUBE_DIRS[i]

	return results


func _axial_ring(coord: Vector2i) -> int:
	var x := coord.x
	var z := coord.y
	var y := -x - z
	return int((abs(x) + abs(y) + abs(z)) / 2)


func _cube_to_axial(cube: Vector3i) -> Vector2i:
	return Vector2i(cube.x, cube.z)


func _axial_to_pixel(center: Vector2, coord: Vector2i) -> Vector2:
	var x := HEX_SIZE * sqrt(3.0) * (coord.x + coord.y / 2.0)
	var y := HEX_SIZE * 1.5 * coord.y
	return center + Vector2(x, y)


func _pixel_to_axial(center: Vector2, point: Vector2) -> Vector2i:
	var local := point - center
	var q := (sqrt(3.0) / 3.0 * local.x - local.y / 3.0) / HEX_SIZE
	var r := (2.0 / 3.0 * local.y) / HEX_SIZE
	return _axial_round(q, r)


func _axial_round(q: float, r: float) -> Vector2i:
	var x := q
	var z := r
	var y := -x - z
	var rx := roundf(x)
	var ry := roundf(y)
	var rz := roundf(z)
	var dx := absf(rx - x)
	var dy := absf(ry - y)
	var dz := absf(rz - z)

	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry

	return Vector2i(int(rx), int(rz))


func _hex_corners(center: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(6):
		var angle := deg_to_rad(60.0 * i - 30.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * HEX_SIZE)

	return points
