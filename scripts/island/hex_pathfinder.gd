class_name HexPathfinder
extends RefCounted

# Shortest paths over hex cells, for any way of moving (Movement): walking an island here, sailing
# the world's waters in WorldNavigation. Paths exclude the start and include the goal; they are
# empty when no path exists or the mover is already on the goal.
#
# Walking covers land hex tiles (and decks over the water, like the dock's pier). Buildings are
# walked through (the player can't wall the robot in with their own construction); resource nodes —
# trees, rocks, ore — and solid landmarks like the crashed spaceship are walked around, and crossed
# only when there is no other way (OBSTACLE_COST outweighs any detour), so nothing the player does
# can trap a unit. Cliffs (see MAX_CLIMB) are never crossed: an island's design keeps its land
# reachable, with ramps down to its beaches (tools/world_map_rules.gd checks).

const BuildingDefinitionsScript := preload("res://scripts/buildings/building_definitions.gd")

# Cost of stepping onto a resource node, versus 1 for any other land: a path is effectively
# "fewest nodes crossed, then fewest steps".
const OBSTACLE_COST := 1000
# The most elevation levels (IslandData.get_elevation) a unit climbs or drops in one step, so sand
# beside rock (levels 0 and 2) is still a step. A taller one is a cliff: no unit walks up or down
# it, works a tile across it, or steps ashore onto its top from a boat.
const MAX_CLIMB := 2


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


# Whether neighbouring `a` and `b` stand close enough in height (MAX_CLIMB) for a unit to step
# between them, or to work one from the other. The water counts as level 0, a beach's, so a boat
# lands the robot on low ground only.
static func within_climb(island: IslandData, a: Vector2i, b: Vector2i) -> bool:
	if island == null:
		return false
	var decks := deck_cells(island)
	return absi(_level(island, decks, a) - _level(island, decks, b)) <= MAX_CLIMB


static func _is_walkable(island: IslandData, decks: Dictionary, cell: Vector2i) -> bool:
	return island.has_cell(cell) and (not GameTypes.is_water(island.get_terrain(cell)) or decks.has(cell))


static func _can_step(island: IslandData, decks: Dictionary, from: Vector2i, to: Vector2i) -> bool:
	if not _is_walkable(island, decks, to):
		return false
	if decks.has(from) or decks.has(to):
		return island.get_building_anchor_cell(from) == island.get_building_anchor_cell(to)
	return absi(_level(island, decks, from) - _level(island, decks, to)) <= MAX_CLIMB


# A cell's elevation level: a deck stands at its building's anchor's, and water at 0.
static func _level(island: IslandData, decks: Dictionary, cell: Vector2i) -> int:
	if decks.has(cell):
		cell = decks[cell]
	return 0 if GameTypes.is_water(island.get_terrain(cell)) else island.get_elevation(cell)


# Buildings are passable; resource nodes and solid landmarks (the crashed spaceship,
# BuildingDefinition.solid) are not, except as a last resort (see OBSTACLE_COST).
static func step_cost(island: IslandData, cell: Vector2i) -> int:
	return OBSTACLE_COST if island.has_resource(cell) or is_solid_building(island, cell) else 1


static func is_solid_building(island: IslandData, cell: Vector2i) -> bool:
	var definition := BuildingDefinitionsScript.get_definition(island.get_building_type(cell))
	return definition != null and definition.solid


static func find_path(island: IslandData, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if island == null or start == goal:
		return []

	if not is_walkable(island, goal) or not is_walkable(island, start):
		return []

	return path_to(search(island, start, goal), goal)


# Walking the island from start (see Movement.search).
static func search(island: IslandData, start: Vector2i, goal := GameTypes.NO_CELL) -> Dictionary:
	return Walking.new(island).search(start, goal)


# A way of moving over the hex grid: where a mover may step and what each step costs. Every path is
# found by its search: Walking an island below, Sailing the world's waters in WorldNavigation.
class Movement extends RefCounted:
	# Whether the mover may step from `from` onto the neighbouring `to`.
	func can_step(_from: Vector2i, _to: Vector2i) -> bool:
		return false

	# The cost of stepping onto `cell`, at least 1.
	func step_cost(_cell: Vector2i) -> int:
		return 1

	# A lower bound on the cost from `cell` to `goal`, steering a search toward the goal (A*). 0, the
	# default, searches outward evenly (Dijkstra).
	func estimate(_cell: Vector2i, _goal: Vector2i) -> int:
		return 0

	# Shortest paths from start: {cost = {cell: total cost}, came_from = {cell: previous cell}},
	# covering every reachable cell, or stopping early once `goal` is settled.
	func search(start: Vector2i, goal := GameTypes.NO_CELL) -> Dictionary:
		var cost := {start: 0}
		var came_from := {start: start}
		var settled := {}
		var heap: Array = [[estimate(start, goal), start]]

		while not heap.is_empty():
			var current: Vector2i = HexPathfinder._heap_pop(heap)[1]
			if settled.has(current):
				continue
			settled[current] = true
			if current == goal:
				break

			for neighbor in HexGrid.neighbors(current):
				if settled.has(neighbor) or not can_step(current, neighbor):
					continue
				var new_cost: int = cost[current] + step_cost(neighbor)
				if not cost.has(neighbor) or new_cost < cost[neighbor]:
					cost[neighbor] = new_cost
					came_from[neighbor] = current
					HexPathfinder._heap_push(heap, [new_cost + estimate(neighbor, goal), neighbor])

		return {cost = cost, came_from = came_from}

	# The cheapest path from start to goal, or [] (see path_to).
	func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
		if start == goal:
			return []
		return HexPathfinder.path_to(search(start, goal), goal)


# Walking an island: over land and decks, around resource nodes (see the top of this file).
class Walking extends Movement:
	var island: IslandData
	var decks: Dictionary

	func _init(walked: IslandData) -> void:
		island = walked
		decks = HexPathfinder.deck_cells(walked)

	func can_step(from: Vector2i, to: Vector2i) -> bool:
		return HexPathfinder._can_step(island, decks, from, to)

	func step_cost(cell: Vector2i) -> int:
		return HexPathfinder.step_cost(island, cell)


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
