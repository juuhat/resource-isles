class_name HexPathfinder
extends RefCounted

# Breadth-first pathfinding over walkable (land) hex tiles. Step cost is uniform,
# so BFS yields a shortest path. Returns the list of cells to step through,
# excluding the start and including the goal. Empty when no path exists or the
# unit is already on the goal.

const HexGridScript := preload("res://scripts/island/hex_grid.gd")


static func is_walkable(island: IslandData, cell: Vector2i) -> bool:
	return island != null and island.is_in_bounds(cell) \
		and not GameTypes.is_water(island.get_terrain(cell))


static func find_path(island: IslandData, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if island == null or start == goal:
		return []

	if not is_walkable(island, goal) or not is_walkable(island, start):
		return []

	var came_from := {start: start}
	var frontier: Array[Vector2i] = [start]
	var head := 0

	while head < frontier.size():
		var current := frontier[head]
		head += 1

		if current == goal:
			break

		for neighbor in HexGridScript.neighbors(current):
			if came_from.has(neighbor) or not is_walkable(island, neighbor):
				continue

			came_from[neighbor] = current
			frontier.append(neighbor)

	if not came_from.has(goal):
		return []

	var path: Array[Vector2i] = []
	var cell := goal
	while cell != start:
		path.append(cell)
		cell = came_from[cell]

	path.reverse()
	return path
