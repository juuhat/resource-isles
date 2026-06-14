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
