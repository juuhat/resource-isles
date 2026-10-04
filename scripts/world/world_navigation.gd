class_name WorldNavigation
extends RefCounted

# Islands retain local save coordinates, but every tile and intervening sea cell belongs to
# this shared lattice. Rounded slot spacing keeps the original world layout within one tile.
const Grid := preload("res://scripts/island/hex_grid.gd")
const Ground := preload("res://scripts/island/hex_pathfinder.gd")
const LocalBoats := preload("res://scripts/player/boat_navigation.gd")
const CELL_SIZE := Vector2(128.0, 128.0)
const RING_SPACING := 6400.0
const SEA_Y := 6.0

var world: WorldData
var regions: Dictionary = {}

func setup(data: WorldData) -> void:
	world = data
	rebuild_regions()

static func slot_axial(coord: Vector2i) -> Vector2i:
	return Vector2i(coord.x * 50 - coord.y * 4, coord.y * 58)

static func slot_center(coord: Vector2i) -> Vector3:
	return cell_center(Grid.axial_to_offset(slot_axial(coord)))

static func cell_center(cell: Vector2i) -> Vector3:
	var point := Grid.cell_center_3d(cell, CELL_SIZE) - Grid.cell_center_3d(Vector2i.ZERO, CELL_SIZE)
	point.y = SEA_Y
	return point

static func island_origin(coord: Vector2i, island: IslandData) -> Vector2i:
	return slot_axial(coord) - Grid.offset_to_axial(Vector2i(island.width / 2, island.height / 2))

static func local_to_world(coord: Vector2i, island: IslandData, cell: Vector2i) -> Vector2i:
	return Grid.axial_to_offset(island_origin(coord, island) + Grid.offset_to_axial(cell))

static func world_to_local(coord: Vector2i, island: IslandData, cell: Vector2i) -> Vector2i:
	return Grid.axial_to_offset(Grid.offset_to_axial(cell) - island_origin(coord, island))

func rebuild_regions() -> void:
	regions.clear()
	for coord in world.islands:
		var island: IslandData = world.islands[coord]
		for y in island.height:
			for x in island.width:
				var local := Vector2i(x, y)
				regions[local_to_world(coord, island, local)] = {coord = coord, cell = local}

func region_at(cell: Vector2i) -> Dictionary:
	return regions.get(cell, {})

func sailing_radius() -> float:
	return (world.revealed_rings + 0.5) * RING_SPACING

func inside_frontier(cell: Vector2i) -> bool:
	var point := cell_center(cell)
	return Vector2(point.x, point.z).length() + CELL_SIZE.x * 0.5 <= sailing_radius()

func can_sail(cell: Vector2i, own_id := -1) -> bool:
	if not inside_frontier(cell):
		return false
	var region := region_at(cell)
	if not region.is_empty():
		if not world.is_revealed(region.coord):
			return false
		var island: IslandData = world.islands[region.coord]
		# Legacy local boats are migrated at startup; only world-owned boats block sailing.
		if not LocalBoats.can_sail(island, region.cell):
			return false
	for id in world.boats:
		if id != own_id and world.boats[id].cell == cell:
			return false
	return true

func can_land(boat_cell: Vector2i, shore: Vector2i) -> bool:
	if not Grid.neighbors(boat_cell).has(shore):
		return false
	var region := region_at(shore)
	if region.is_empty() or not world.is_revealed(region.coord):
		return false
	var island: IslandData = world.islands[region.coord]
	return Ground.is_open(island, region.cell) and not island.has_resource(region.cell) \
		and (Ground.is_deck(island, region.cell) or not GameTypes.is_water(island.get_terrain(region.cell)))

func find_path(start: Vector2i, goal: Vector2i, own_id := -1) -> Array[Vector2i]:
	if not can_sail(start, own_id) or not can_sail(goal, own_id):
		return []
	var previous := {start: start}
	var cost := {start: 0}
	var settled := {}
	var heap: Array = [[_distance(start, goal), start]]
	while not heap.is_empty():
		var cell: Vector2i = Ground._heap_pop(heap)[1]
		if settled.has(cell):
			continue
		settled[cell] = true
		if cell == goal:
			return Ground.path_to({came_from = previous}, goal)
		for neighbor in Grid.neighbors(cell):
			if settled.has(neighbor) or not can_sail(neighbor, own_id):
				continue
			var next_cost: int = cost[cell] + 1
			if not cost.has(neighbor) or next_cost < cost[neighbor]:
				cost[neighbor] = next_cost
				previous[neighbor] = cell
				Ground._heap_push(heap, [next_cost + _distance(neighbor, goal), neighbor])
	return []

static func _distance(a: Vector2i, b: Vector2i) -> int:
	var delta := Grid.offset_to_axial(a) - Grid.offset_to_axial(b)
	return maxi(absi(delta.x), maxi(absi(delta.y), absi(delta.x + delta.y)))

func cell_from_position(point: Vector3) -> Vector2i:
	# Cube rounding also handles negative rows and the ocean outside any island rectangle.
	var r := point.z / (CELL_SIZE.y * 0.75)
	var q := point.x / CELL_SIZE.x - r * 0.5
	var cube := Vector3(q, -q - r, r)
	var rounded := Vector3(roundf(cube.x), roundf(cube.y), roundf(cube.z))
	var error := (rounded - cube).abs()
	if error.x > error.y and error.x > error.z:
		rounded.x = -rounded.y - rounded.z
	elif error.y > error.z:
		rounded.y = -rounded.x - rounded.z
	else:
		rounded.z = -rounded.x - rounded.y
	return Grid.axial_to_offset(Vector2i(int(rounded.x), int(rounded.z)))

func cell_from_ray(origin: Vector3, direction: Vector3) -> Vector2i:
	if absf(direction.y) < 0.00001:
		return Vector2i(-99999, -99999)
	var distance := (SEA_Y - origin.y) / direction.y
	if distance < 0.0:
		return Vector2i(-99999, -99999)
	return cell_from_position(origin + direction * distance)

func migrate_boats() -> void:
	for coord in world.islands:
		var island: IslandData = world.islands[coord]
		for old_id in island.boats:
			var id := world.next_boat_id()
			var boat: Dictionary = island.boats[old_id].duplicate(true)
			boat.cell = local_to_world(coord, island, boat.cell)
			world.boats[id] = boat
			if coord == world.current_coord and old_id == island.piloted_boat:
				world.piloted_boat = id
		island.boats.clear()
		island.piloted_boat = -1
