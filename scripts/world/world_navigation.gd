class_name WorldNavigation
extends RefCounted

# The world lattice: one hex grid covering every island and the sea between them. Island data is
# keyed by its cells (IslandData), units stand on them and boats sail them. Each island sits where
# the world map puts it, and no two share a cell (WorldBuilder leaves out one that would).
const Grid := preload("res://scripts/island/hex_grid.gd")
const Ground := preload("res://scripts/island/hex_pathfinder.gd")
const CELL_SIZE := Vector2(128.0, 128.0)
# World units between rings, counted out from WorldData.CENTER: 50 cells.
const RING_SPACING := 6400.0
const SEA_Y := 6.0

var world: WorldData
# Cell -> the centre (WorldData key) of the island it belongs to. Open sea has no entry.
var regions: Dictionary = {}

func setup(data: WorldData) -> void:
	world = data
	rebuild_regions()

static func cell_center(cell: Vector2i) -> Vector3:
	var point := Grid.cell_center_3d(cell, CELL_SIZE) - Grid.cell_center_3d(Vector2i.ZERO, CELL_SIZE)
	point.y = SEA_Y
	return point

func rebuild_regions() -> void:
	regions.clear()
	for coord in world.islands:
		for cell in (world.islands[coord] as IslandData).terrain:
			regions[cell] = coord

# The island the cell belongs to (its centre, as WorldData keys it), or WorldData.NO_COORD for
# open sea.
func island_at(cell: Vector2i) -> Vector2i:
	return regions.get(cell, WorldData.NO_COORD)

func sailing_radius() -> float:
	return world.frontier_rings() * RING_SPACING

func inside_frontier(cell: Vector2i) -> bool:
	var point := cell_center(cell)
	return Vector2(point.x, point.z).length() + CELL_SIZE.x * 0.5 <= sailing_radius()

# Whether a boat may float on the cell (other than boat own_id): open sea or an island's water,
# inside the fog frontier and clear of other boats.
func can_sail(cell: Vector2i, own_id := -1) -> bool:
	if not inside_frontier(cell):
		return false
	var coord := island_at(cell)
	if coord != WorldData.NO_COORD:
		if not world.is_revealed(coord) or not _island_water(world.islands[coord], cell):
			return false
	for id in world.boats:
		if id != own_id and world.boats[id].cell == cell:
			return false
	return true

# Whether the robot can step ashore from a boat on boat_cell onto the neighbouring shore: a deck
# or unobstructed land on a revealed island, low enough to climb from the water (not a cliff,
# HexPathfinder.MAX_CLIMB). The boat stays afloat.
func can_land(boat_cell: Vector2i, shore: Vector2i) -> bool:
	var coord := island_at(shore)
	if coord == WorldData.NO_COORD or not world.is_revealed(coord):
		return false
	var island: IslandData = world.islands[coord]
	return Grid.neighbors(boat_cell).has(shore) and Ground.is_open(island, shore) \
		and not island.has_resource(shore) \
		and (Ground.is_deck(island, shore) or (not GameTypes.is_water(island.get_terrain(shore))
			and Ground.within_climb(island, boat_cell, shore)))

# The boat at the cell: a boat afloat there {id, cell}, or the skiff still moored at the end of a
# finished dock {id = -1, cell, anchor} (it becomes a world boat once launched); {} for none.
func boat_at(cell: Vector2i) -> Dictionary:
	for id in world.boats:
		if world.boats[id].cell == cell:
			return {id = id, cell = cell}
	var coord := island_at(cell)
	if coord == WorldData.NO_COORD:
		return {}
	var island: IslandData = world.islands[coord]
	var anchor := island.get_building_anchor_cell(cell)
	if anchor == GameTypes.NO_CELL:
		return {}
	var building: Dictionary = island.buildings[anchor]
	if int(building.type) == GameTypes.BuildingType.DOCK and not building.has("build_progress") \
			and not building.get("boat_launched", false) and building.cells.back() == cell:
		return {id = -1, cell = cell, anchor = anchor}
	return {}

# Where boat own_id can sail from start to goal (Sailing), or [] when it can't get there.
func find_path(start: Vector2i, goal: Vector2i, own_id := -1) -> Array[Vector2i]:
	if not can_sail(start, own_id) or not can_sail(goal, own_id):
		return []
	return Sailing.new(self, own_id).find_path(start, goal)

# A boat may float on an island's water, but not on a deck or a building, except the berth at the
# end of a dock whose boat has been launched.
static func _island_water(island: IslandData, cell: Vector2i) -> bool:
	if not GameTypes.is_water(island.get_terrain(cell)) or Ground.is_deck(island, cell):
		return false
	if island.has_building(cell):
		var anchor := island.get_building_anchor_cell(cell)
		var building: Dictionary = island.buildings[anchor]
		if int(building.type) != GameTypes.BuildingType.DOCK or building.has("build_progress") or building.cells.back() != cell:
			return false
		if not building.get("boat_launched", false):
			return false
	return true

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
		return GameTypes.NO_CELL
	var distance := (SEA_Y - origin.y) / direction.y
	if distance < 0.0:
		return GameTypes.NO_CELL
	return cell_from_position(origin + direction * distance)


# Sailing (HexPathfinder.Movement): onto any cell can_sail allows for the boat, steered toward the
# goal by hex distance.
class Sailing extends HexPathfinder.Movement:
	var navigation: WorldNavigation
	var boat_id: int

	func _init(sailed: WorldNavigation, own_id: int) -> void:
		navigation = sailed
		boat_id = own_id

	func can_step(_from: Vector2i, to: Vector2i) -> bool:
		return navigation.can_sail(to, boat_id)

	func estimate(cell: Vector2i, goal: Vector2i) -> int:
		return HexGrid.distance(cell, goal) if goal != GameTypes.NO_CELL else 0
