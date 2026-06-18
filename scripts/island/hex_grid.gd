class_name HexGrid
extends RefCounted

const NEIGHBOR_DIRECTIONS_EVEN_R: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(0, -1),
	Vector2i(-1, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]
const NEIGHBOR_DIRECTIONS_ODD_R: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(1, 1),
]


static func neighbor(cell: Vector2i, direction_index: int) -> Vector2i:
	return cell + neighbor_offset(cell, direction_index)


static func neighbor_offset(cell: Vector2i, direction_index: int) -> Vector2i:
	var directions := NEIGHBOR_DIRECTIONS_ODD_R if cell.y % 2 != 0 else NEIGHBOR_DIRECTIONS_EVEN_R
	return directions[posmod(direction_index, directions.size())]


static func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []

	for direction_index in range(6):
		cells.append(neighbor(cell, direction_index))

	return cells


static func hex_points(top_left: Vector2, size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		top_left + Vector2(size.x * 0.5, 0.0),
		top_left + Vector2(size.x, size.y * 0.25),
		top_left + Vector2(size.x, size.y * 0.75),
		top_left + Vector2(size.x * 0.5, size.y),
		top_left + Vector2(0.0, size.y * 0.75),
		top_left + Vector2(0.0, size.y * 0.25),
	])


static func point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	var inside := false
	var previous_index := polygon.size() - 1

	for index in range(polygon.size()):
		var current := polygon[index]
		var previous := polygon[previous_index]
		var crosses_y := (current.y > point.y) != (previous.y > point.y)

		if crosses_y:
			var intersection_x := (
				(previous.x - current.x) * (point.y - current.y) / (previous.y - current.y)
				+ current.x
			)
			if point.x < intersection_x:
				inside = not inside

		previous_index = index

	return inside


# --- 3D coordinate mapping (see docs/3d-models.md) ---
# These are the dimension-bridge between the cell-based simulation and the planned
# 3D renderer. They mirror the 2D layout used by IslandRenderer exactly (pointy-top,
# odd-r offset: odd rows shift half a tile, rows pack at 0.75 spacing) but place cells
# on the XZ ground plane with Y left at 0 for the caller to raise by tile height. The
# 2D renderer is unaffected; nothing calls these until Phase 2.


# Top-left-equivalent anchor of a cell's bounding box on the ground plane. This is the
# 3D analogue of IslandRenderer.cell_to_world (its 2D Y becomes Z here).
static func cell_to_world_3d(cell: Vector2i, cell_size: Vector2) -> Vector3:
	return Vector3(
		(float(cell.x) + _row_offset_3d(cell.y)) * cell_size.x,
		0.0,
		float(cell.y) * cell_size.y * 0.75
	)


# Center of a cell on the ground plane — where a unit, building, or sprite sits.
static func cell_center_3d(cell: Vector2i, cell_size: Vector2) -> Vector3:
	return cell_to_world_3d(cell, cell_size) + Vector3(cell_size.x * 0.5, 0.0, cell_size.y * 0.5)


# The six hex corners on the ground plane, in the same winding as hex_points so edge
# and neighbor indexing stays consistent. Used by Phase 2 to build the prism mesh and
# tile outlines.
static func hex_corners_3d(center: Vector3, cell_size: Vector2) -> PackedVector3Array:
	var half_x := cell_size.x * 0.5
	var quarter_z := cell_size.y * 0.25
	var half_z := cell_size.y * 0.5
	return PackedVector3Array([
		center + Vector3(0.0, 0.0, -half_z),
		center + Vector3(half_x, 0.0, -quarter_z),
		center + Vector3(half_x, 0.0, quarter_z),
		center + Vector3(0.0, 0.0, half_z),
		center + Vector3(-half_x, 0.0, quarter_z),
		center + Vector3(-half_x, 0.0, -quarter_z),
	])


static func _row_offset_3d(row: int) -> float:
	return 0.5 if row % 2 != 0 else 0.0
