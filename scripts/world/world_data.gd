class_name WorldData
extends RefCounted

# Islands keyed by their centre: the world cell the middle of their design sits on, from the world
# map (WorldMap, assets/world/world_map.cfg). Every island on the map is built up front
# (WorldBuilder.add_map_islands) so the whole archipelago exists as one world; islands past the
# sailing frontier simply stay hidden under clouds, and an island counts as discovered when the
# robot approaches close enough to reveal it (IslandData.visited). Dictionaries preserve insertion
# order, so keys() doubles as map order (used for naming). See docs/world-map-and-island-designs.md.

# The middle of the world, which the rings are counted out from.
const CENTER := Vector2i(0, 0)
# Returned by coord_of for an island that is not in this world.
const NO_COORD := Vector2i(-99999, -99999)
# How many rings out the world map reveals at the start. 0 = only the start island's ring, 1 =
# the first ring of islands as well, etc. Quests grow this via reveal_additional_rings().
const STARTING_REVEALED_RINGS := 0
# The disc is always at least this many rings wide, so the clouded frontier reads as a big
# world still to explore; it grows if more rings than this are ever revealed.
const MIN_WORLD_RINGS := 4

var islands: Dictionary = {}
# The island the robot starts on: the world map's start island, the crash site.
var start_coord := CENTER
var current_coord := CENTER
var revealed_rings := STARTING_REVEALED_RINGS
var boats: Dictionary = {}
var piloted_boat := -1
# Standing boat links between islands, run by TradeManager. Saved with the world.
var trade_routes: Array[TradeRoute] = []
# The K9-DA rescue (the MAIN quest): the ring-1 island the dog is stranded on, the cell it waits
# at there, and whether the robot has picked it up. Until rescued it stays put on dog_coord; once
# rescued it follows the robot between islands. NO_COORD / (-1, -1) until main assigns them.
var dog_coord := NO_COORD
var dog_cell := GameTypes.NO_CELL
var dog_rescued := false
# The cells the robot has seen inside the radar frontier; the rest lies under exploration fog.
var exploration := ExplorationMap.new()


func next_boat_id() -> int:
	var id := 0
	while boats.has(id):
		id += 1
	return id


func has_island(coord: Vector2i) -> bool:
	return islands.has(coord)


func get_island(coord: Vector2i) -> IslandData:
	return islands.get(coord)


func add_island(coord: Vector2i, island: IslandData) -> void:
	islands[coord] = island
	if island.island_name.is_empty():
		island.island_name = "World %d" % islands.size()


func island_count() -> int:
	return islands.size()


func ordered_coords() -> Array:
	return islands.keys()


# Discovered islands, in generation order — the set [ and ] inspect with the camera.
func visited_coords() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coord in islands:
		if (islands[coord] as IslandData).visited:
			result.append(coord)
	return result


# The world-map coord an island sits at, or NO_COORD if it is not in this world.
func coord_of(island: IslandData) -> Vector2i:
	for coord in islands:
		if islands[coord] == island:
			return coord
	return NO_COORD


func get_current() -> IslandData:
	return get_island(current_coord)


func set_current(coord: Vector2i) -> bool:
	if not has_island(coord):
		return false

	current_coord = coord
	return true


# Reveal more rings — lifts the clouds off their islands. The hook a boat-tier unlock calls.
func reveal_additional_rings(count: int = 1) -> void:
	revealed_rings = maxi(0, revealed_rings + count)


# Whether the island centred on coord is out of the clouds: inside the sailing frontier, the same
# reach as WorldNavigation.sailing_radius.
func is_revealed(coord: Vector2i) -> bool:
	return rings_out(coord) <= revealed_rings + 0.5


# How many rings the disc holds: the revealed rings plus a clouded frontier, never fewer than
# MIN_WORLD_RINGS.
func world_rings() -> int:
	return maxi(MIN_WORLD_RINGS, revealed_rings)


# How many rings out from the middle of the world a cell lies: 1.0 is one RING_SPACING from CENTER.
# An island's ring is that of its centre.
static func rings_out(cell: Vector2i) -> float:
	var point := WorldNavigation.cell_center(cell) - WorldNavigation.cell_center(CENTER)
	return Vector2(point.x, point.z).length() / WorldNavigation.RING_SPACING


# True while K9-DA still waits on the island at `coord` for the robot to pick it up.
func is_dog_stranded_on(coord: Vector2i) -> bool:
	return not dog_rescued and dog_coord == coord


# --- Save/load ---
# The whole discovered world: every island keyed by its centre, plus which island the game started
# on and which is current, how many rings are revealed, and the trade routes. `reference_time` is
# forwarded to each island and route so their timers can be rebased (see IslandData.to_dict).
# Islands are restored straight into the dict (not via add_island) so their saved names are
# preserved verbatim.

func to_dict(reference_time: float) -> Dictionary:
	var serialized_islands := {}
	for coord in islands:
		serialized_islands[coord] = (islands[coord] as IslandData).to_dict(reference_time)
	var serialized_routes := []
	for route in trade_routes:
		serialized_routes.append(route.to_dict(reference_time))
	return {
		start_coord = start_coord,
		current_coord = current_coord,
		revealed_rings = revealed_rings,
		islands = serialized_islands,
		trade_routes = serialized_routes,
		boats = boats.duplicate(true),
		piloted_boat = piloted_boat,
		dog_coord = dog_coord,
		dog_cell = dog_cell,
		dog_rescued = dog_rescued,
		exploration = exploration.to_dict(),
	}


static func from_dict(data: Dictionary, reference_time: float) -> WorldData:
	var world := WorldData.new()
	world.start_coord = data.get("start_coord", CENTER)
	world.current_coord = data.get("current_coord", CENTER)
	world.revealed_rings = int(data.get("revealed_rings", STARTING_REVEALED_RINGS))
	world.boats = (data.get("boats", {}) as Dictionary).duplicate(true)
	world.piloted_boat = int(data.get("piloted_boat", -1))
	var serialized_islands: Dictionary = data.get("islands", {})
	for coord in serialized_islands:
		world.islands[coord] = IslandData.from_dict(serialized_islands[coord], reference_time)
	for route_data in data.get("trade_routes", []):
		var route := TradeRoute.from_dict(route_data, reference_time)
		# Drop a route whose island is gone (e.g. a hand-edited save) rather than crash on it.
		if world.has_island(route.home_coord) and world.has_island(route.away_coord):
			world.trade_routes.append(route)
	# Without dog data, WorldBuilder.add_map_islands strands K9-DA where the map says.
	world.dog_coord = data.get("dog_coord", NO_COORD)
	world.dog_cell = data.get("dog_cell", GameTypes.NO_CELL)
	world.dog_rescued = bool(data.get("dog_rescued", false))
	# Older saves start with everything unexplored; main charts their discovered islands again.
	world.exploration = ExplorationMap.from_dict(data.get("exploration", {}))
	return world
