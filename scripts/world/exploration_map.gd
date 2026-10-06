class_name ExplorationMap
extends RefCounted

# Which world lattice cells the robot has seen. Inside the radar frontier everything starts
# unexplored and the robot's sight clears it cell by cell (as units explore in Civilization); the
# chart shader draws whatever is still unexplored as fog.
#
# Cells are kept as a square of axial coordinates centred on the world centre, one byte each
# (EXPLORED or 0), so WorldView hands the bytes straight to the chart shader as a texture. The
# square grows when the robot sees past it. Saved compressed with the world.

const Grid := preload("res://scripts/island/hex_grid.gd")
const EXPLORED := 255
# The square starts this many cells out from the centre and grows in steps of at least as much.
const MIN_RADIUS := 64

# Emitted when cells become explored, so a view can redraw.
signal changed

# Axial coordinates run from -radius to radius on both axes.
var radius := 0
var cells := PackedByteArray()


func size() -> int:
	return radius * 2 + 1


func is_explored(cell: Vector2i) -> bool:
	var index := _index(Grid.offset_to_axial(cell))
	return index >= 0 and cells[index] != 0


# Marks the cells explored; true if any of them was new.
func explore(explored_cells: Array[Vector2i]) -> bool:
	var any_new := false
	for cell in explored_cells:
		var axial := Grid.offset_to_axial(cell)
		var reach := maxi(absi(axial.x), absi(axial.y))
		if reach > radius:
			_grow(reach)
		var index := _index(axial)
		if cells[index] == 0:
			cells[index] = EXPLORED
			any_new = true
	if any_new:
		changed.emit()
	return any_new


# Every cell within `steps` of `cell`.
static func cells_around(cell: Vector2i, steps: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var center := Grid.offset_to_axial(cell)
	for q in range(-steps, steps + 1):
		for r in range(maxi(-steps, -q - steps), mini(steps, -q + steps) + 1):
			result.append(Grid.axial_to_offset(center + Vector2i(q, r)))
	return result


func _index(axial: Vector2i) -> int:
	if cells.is_empty() or absi(axial.x) > radius or absi(axial.y) > radius:
		return -1
	return (axial.y + radius) * size() + axial.x + radius


func _grow(reach: int) -> void:
	var old_radius := radius
	var old_size := size() if not cells.is_empty() else 0
	var old_cells := cells
	radius = maxi(reach, maxi(radius + MIN_RADIUS, MIN_RADIUS))
	cells = PackedByteArray()
	cells.resize(size() * size())
	var shift := radius - old_radius
	for row in old_size:
		var start := (row + shift) * size() + shift
		for column in old_size:
			cells[start + column] = old_cells[row * old_size + column]


# --- Save/load ---

func to_dict() -> Dictionary:
	return {radius = radius, cells = cells.compress(FileAccess.COMPRESSION_DEFLATE)}


static func from_dict(data: Dictionary) -> ExplorationMap:
	var map := ExplorationMap.new()
	var saved_radius := int(data.get("radius", 0))
	var packed: PackedByteArray = data.get("cells", PackedByteArray())
	if saved_radius <= 0 or packed.is_empty():
		return map
	var unpacked := packed.decompress((saved_radius * 2 + 1) * (saved_radius * 2 + 1), FileAccess.COMPRESSION_DEFLATE)
	if unpacked.size() == (saved_radius * 2 + 1) * (saved_radius * 2 + 1):
		map.radius = saved_radius
		map.cells = unpacked
	return map
