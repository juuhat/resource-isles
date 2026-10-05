class_name HexPathfinder
extends RefCounted

# Shortest paths over land hex tiles (and decks over the water, like the dock's pier). Buildings are walked through (the player can't wall the
# robot in with their own construction); resource nodes — trees, rocks, ore — are walked around,
# and crossed only when there is no other way (OBSTACLE_COST outweighs any detour), so a unit can
# never be trapped and every land cell stays reachable. Paths exclude the start and include the
# goal; they are empty when no path exists or the unit is already on the goal.

const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const BuildingDefinitionsScript := preload("res://scripts/buildings/building_definitions.gd")

# Cost of stepping onto a resource node, versus 1 for any other land: a path is effectively
# "fewest nodes crossed, then fewest steps".
const OBSTACLE_COST := 1000


# Ground a unit can stand on in principle: land (anything but water / off the map), or a finished
# building's deck out over the water (the dock's pier, see deck_cells).
static func is_walkable(island: IslandData, cell: Vector2i) -> bool:
	return island != null and _is_walkable(island, deck_cells(island), cell)


# Land with nothing solid on it: no building and no resource node — somewhere a unit can park
# without overlapping a model. A deck is open too: it's a floor, not a model to stand clear of.
# Ground items don't count: the robot picks them up by walking over them.
static func is_open(island: IslandData, cell: Vector2i) -> bool:
	if island == null:
		return false
	if deck_cells(island).has(cell):
		return true
	return is_walkable(island, cell) and not island.has_building(cell) and not island.has_resource(cell)


static func is_deck(island: IslandData, cell: Vector2i) -> bool:
	return island != null and deck_cells(island).has(cell)


# Every tile of a finished building's walkable floor (BuildingDefinition.deck_tiles), like the
# dock's pier, mapped to that building's anchor. A blueprint has no floor yet. Cached on the island
# until its buildings change, so the result is shared: read it, don't modify it.
static func deck_cells(island: IslandData) -> Dictionary:
	if island.deck_cells_revision == island.building_revision:
		return island.deck_cells_cache

	var decks := {}
	for anchor_cell in island.buildings:
		var building: Dictionary = island.buildings[anchor_cell]
		var definition := BuildingDefinitionsScript.get_definition(int(building.type))
		# build_progress marks a blueprint (IslandData.is_under_construction, without its lookup).
		if definition == null or definition.deck_tiles.is_empty() or building.has("build_progress"):
			continue
		var cells: Array = building.get("cells", [])
		for index in definition.deck_tiles:
			if index < cells.size():
				decks[cells[index]] = anchor_cell
	island.deck_cells_cache = decks
	island.deck_cells_revision = island.building_revision
	return decks


# Whether a unit can step from `from` onto the neighbouring `to`. A deck is boarded only from its
# own building's tiles (the pier from the dock's quay), never straight off the water's edge
# beside it.
static func can_step(island: IslandData, from: Vector2i, to: Vector2i) -> bool:
	return island != null and _can_step(island, deck_cells(island), from, to)


static func _is_walkable(island: IslandData, decks: Dictionary, cell: Vector2i) -> bool:
	return island.is_in_bounds(cell) and (not GameTypes.is_water(island.get_terrain(cell)) or decks.has(cell))


static func _can_step(island: IslandData, decks: Dictionary, from: Vector2i, to: Vector2i) -> bool:
	if not _is_walkable(island, decks, to):
		return false
	if decks.has(from) or decks.has(to):
		return island.get_building_anchor_cell(from) == island.get_building_anchor_cell(to)
	return true


# Buildings are passable; resource nodes are not (except as a last resort, see OBSTACLE_COST).
static func step_cost(island: IslandData, cell: Vector2i) -> int:
	return OBSTACLE_COST if island.has_resource(cell) else 1


static func find_path(island: IslandData, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if island == null or start == goal:
		return []

	if not is_walkable(island, goal) or not is_walkable(island, start):
		return []

	return path_to(search(island, start, goal), goal)


# Dijkstra from start over walkable ground. Returns {cost = {cell: total cost}, came_from = {cell:
# previous cell}}, covering every reachable cell, or stopping early once `goal` is settled.
static func search(island: IslandData, start: Vector2i, goal := GameTypes.NO_CELL) -> Dictionary:
	var cost := {start: 0}
	var came_from := {start: start}
	var settled := {}
	var heap: Array = [[0, start]]
	var decks := deck_cells(island)

	while not heap.is_empty():
		var entry: Array = _heap_pop(heap)
		var current: Vector2i = entry[1]
		if settled.has(current):
			continue
		settled[current] = true
		if current == goal:
			break

		for neighbor in HexGridScript.neighbors(current):
			if settled.has(neighbor) or not _can_step(island, decks, current, neighbor):
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
