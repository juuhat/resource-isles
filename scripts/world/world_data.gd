class_name WorldData
extends RefCounted

# Islands keyed by their world hex coordinate (axial Vector2i). The starter sits at CENTER.
# Every slot on the disc is generated up front (main._ensure_world_generated) so the whole
# archipelago exists as one world; unrevealed rings simply stay hidden under clouds, and an
# island counts as discovered once the robot first lands on it (IslandData.visited).
# Dictionaries preserve insertion order, so keys() doubles as generation order (used for
# naming). See docs/island-unlocks.md.

const CENTER := Vector2i(0, 0)
# Returned by coord_of for an island that is not in this world.
const NO_COORD := Vector2i(-99999, -99999)
# How many rings out the world map reveals at the start. 0 = only the starter
# island, 1 = the starter plus the first ring of three islands, etc. Boat tiers
# will grow this later via reveal_additional_rings().
const STARTING_REVEALED_RINGS := 0
# The disc is always at least this many rings wide, so the clouded frontier reads as a big
# world still to explore; it grows if more rings than this are ever revealed.
const MIN_WORLD_RINGS := 4

var islands: Dictionary = {}
var current_coord := CENTER
var revealed_rings := STARTING_REVEALED_RINGS
# Standing boat links between islands, run by TradeManager. Saved with the world.
var trade_routes: Array[TradeRoute] = []
# The K9-DA rescue (the MAIN quest): the ring-1 island the dog is stranded on, the cell it waits
# at there, and whether the robot has picked it up. Until rescued it stays put on dog_coord; once
# rescued it follows the robot between islands. NO_COORD / (-1, -1) until main assigns them.
var dog_coord := NO_COORD
var dog_cell := Vector2i(-1, -1)
var dog_rescued := false


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


# Islands the robot has landed on, in generation order — the set [ and ] cycle through.
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


func is_revealed(coord: Vector2i) -> bool:
	return ring_of(coord) <= revealed_rings


# How many rings the disc holds (and how many are generated): the revealed rings plus a
# clouded frontier, never fewer than MIN_WORLD_RINGS.
func world_rings() -> int:
	return maxi(MIN_WORLD_RINGS, revealed_rings)


# --- Island slots ---
# Island slots sit on the world hex lattice: the centre, then three per ring on every other
# ring "corner", 120 deg apart (ring k's slots are k hexes out). See docs/island-unlocks.md.

const CUBE_DIRS := [
	Vector3i(1, -1, 0),
	Vector3i(1, 0, -1),
	Vector3i(0, 1, -1),
	Vector3i(-1, 1, 0),
	Vector3i(-1, 0, 1),
	Vector3i(0, -1, 1),
]
const SLOT_DIRECTIONS := [0, 2, 4]


# Every slot on the revealed rings, centre first, then ring by ring.
func island_slots() -> Array[Vector2i]:
	return slots_within(revealed_rings)


# Every slot on the disc, revealed or still under the clouds.
func all_slots() -> Array[Vector2i]:
	return slots_within(world_rings())


static func slots_within(rings: int) -> Array[Vector2i]:
	var slots: Array[Vector2i] = [CENTER]
	for ring in range(1, rings + 1):
		for direction in SLOT_DIRECTIONS:
			var cube: Vector3i = CUBE_DIRS[direction] * ring
			slots.append(Vector2i(cube.x, cube.z))
	return slots


# Which ring a hex coord lies on (0 = the centre).
static func ring_of(coord: Vector2i) -> int:
	return int((absi(coord.x) + absi(coord.y) + absi(-coord.x - coord.y)) / 2)


# The ring-1 slot K9-DA is stranded on, picked from the world seed so each world is stable
# across runs. Ring 1 is what Set Sail reveals, so the rescue is always within first reach.
static func dog_slot_for_seed(seed_value: int) -> Vector2i:
	var ring_one := slots_within(1).slice(1)
	return ring_one[posmod(seed_value, ring_one.size())]


# True while K9-DA still waits on the island at `coord` for the robot to pick it up.
func is_dog_stranded_on(coord: Vector2i) -> bool:
	return not dog_rescued and dog_coord == coord


# --- Save/load ---
# The whole discovered world: every island keyed by its world-map coord, plus which slot is
# current, how many rings are revealed, and the trade routes. `reference_time` is forwarded to
# each island and route so their timers can be rebased (see IslandData.to_dict). Islands are
# restored straight into the dict (not via add_island) so their saved names are preserved
# verbatim. Saves from before trade routes simply load with none.

func to_dict(reference_time: float) -> Dictionary:
	var serialized_islands := {}
	for coord in islands:
		serialized_islands[coord] = (islands[coord] as IslandData).to_dict(reference_time)
	var serialized_routes := []
	for route in trade_routes:
		serialized_routes.append(route.to_dict(reference_time))
	return {
		current_coord = current_coord,
		revealed_rings = revealed_rings,
		islands = serialized_islands,
		trade_routes = serialized_routes,
		dog_coord = dog_coord,
		dog_cell = dog_cell,
		dog_rescued = dog_rescued,
	}


static func from_dict(data: Dictionary, reference_time: float) -> WorldData:
	var world := WorldData.new()
	world.current_coord = data.get("current_coord", CENTER)
	world.revealed_rings = int(data.get("revealed_rings", STARTING_REVEALED_RINGS))
	var serialized_islands: Dictionary = data.get("islands", {})
	for coord in serialized_islands:
		world.islands[coord] = IslandData.from_dict(serialized_islands[coord], reference_time)
	for route_data in data.get("trade_routes", []):
		var route := TradeRoute.from_dict(route_data, reference_time)
		# Drop a route whose island is gone (e.g. a hand-edited save) rather than crash on it.
		if world.has_island(route.home_coord) and world.has_island(route.away_coord):
			world.trade_routes.append(route)
	# Saves from before the rescue have no dog data; main assigns a fresh spot (and treats an
	# already-completed rescue quest as rescued) — see main._ensure_dog_placed.
	world.dog_coord = data.get("dog_coord", NO_COORD)
	world.dog_cell = data.get("dog_cell", Vector2i(-1, -1))
	world.dog_rescued = bool(data.get("dog_rescued", false))
	return world
