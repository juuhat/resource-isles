class_name HexPathfinder
extends RefCounted

# Shortest paths over land hex tiles. Buildings are walked through (the player can't wall the
# robot in with their own construction); resource nodes — trees, rocks, ore — are walked around,
# and crossed only when there is no other way (OBSTACLE_COST outweighs any detour), so a unit can
# never be trapped and every land cell stays reachable. Paths exclude the start and include the
# goal; they are empty when no path exists or the unit is already on the goal.

const HexGridScript := preload("res://scripts/island/hex_grid.gd")

# Cost of stepping onto a resource node, versus 1 for any other land: a path is effectively
# "fewest nodes crossed, then fewest steps".
const OBSTACLE_COST := 1000


# Land a unit can stand on in principle (anything but water / off the map).
static func is_walkable(island: IslandData, cell: Vector2i) -> bool:
	return island != null and island.is_in_bounds(cell) \
		and not GameTypes.is_water(island.get_terrain(cell))


# Land with nothing solid on it: no building and no resource node — somewhere a unit can park
# without overlapping a model. Ground items don't count: the robot picks them up by walking
# over them.
static func is_open(island: IslandData, cell: Vector2i) -> bool:
	return is_walkable(island, cell) and not island.has_building(cell) and not island.has_resource(cell)


# Buildings are passable; resource nodes are not (except as a last resort, see OBSTACLE_COST).
static func step_cost(island: IslandData, cell: Vector2i) -> int:
	return OBSTACLE_COST if island.has_resource(cell) else 1


static func find_path(island: IslandData, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if island == null or start == goal:
		return []

	if not is_walkable(island, goal) or not is_walkable(island, start):
		return []

	return path_to(search(island, start, goal), goal)


# Dijkstra from start over walkable land. Returns {cost = {cell: total cost}, came_from = {cell:
# previous cell}}, covering every reachable cell, or stopping early once `goal` is settled.
static func search(island: IslandData, start: Vector2i, goal := Vector2i(-1, -1)) -> Dictionary:
	var cost := {start: 0}
	var came_from := {start: start}
	var settled := {}
	var heap: Array = [[0, start]]

	while not heap.is_empty():
		var entry: Array = _heap_pop(heap)
		var current: Vector2i = entry[1]
		if settled.has(current):
			continue
		settled[current] = true
		if current == goal:
			break

		for neighbor in HexGridScript.neighbors(current):
			if settled.has(neighbor) or not is_walkable(island, neighbor):
				continue
			var new_cost: int = cost[current] + step_cost(island, neighbor)
			if not cost.has(neighbor) or new_cost < cost[neighbor]:
				cost[neighbor] = new_cost
				came_from[neighbor] = current
				_heap_push(heap, [new_cost, neighbor])

	return {cost = cost, came_from = came_from}


# The path to `goal` recorded by search(), or [] when it wasn't reached.
static func path_to(result: Dictionary, goal: Vector2i) -> Array[Vector2i]:
	var came_from: Dictionary = result.came_from
	if not came_from.has(goal):
		return []

	var path: Array[Vector2i] = []
	var cell := goal
	while came_from[cell] != cell:
		path.append(cell)
		cell = came_from[cell]

	path.reverse()
	return path


# Binary min-heap of [cost, cell] pairs, ordered by cost.
static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if heap[parent][0] <= heap[i][0]:
			break
		var swap = heap[parent]
		heap[parent] = heap[i]
		heap[i] = swap
		i = parent


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		while true:
			var smallest := i
			for child in [2 * i + 1, 2 * i + 2]:
				if child < heap.size() and heap[child][0] < heap[smallest][0]:
					smallest = child
			if smallest == i:
				break
			var swap = heap[smallest]
			heap[smallest] = heap[i]
			heap[i] = swap
			i = smallest
	return top
