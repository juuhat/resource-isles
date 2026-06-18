class_name WorldData
extends RefCounted

# Islands keyed by their world-map hex coordinate (axial Vector2i). The starter sits
# at CENTER; other slots are generated on demand when the player clicks them on the
# world map. Dictionaries preserve insertion order, so keys() doubles as discovery
# order (used for naming and quick cycling). See docs/island-unlocks.md.

const CENTER := Vector2i(0, 0)
# How many rings out the world map reveals at the start. 0 = only the starter
# island, 1 = the starter plus the first ring of three islands, etc. Boat tiers
# will grow this later via reveal_additional_rings().
const STARTING_REVEALED_RINGS := 0

var islands: Dictionary = {}
var current_coord := CENTER
var revealed_rings := STARTING_REVEALED_RINGS


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


func get_current() -> IslandData:
	return get_island(current_coord)


func set_current(coord: Vector2i) -> bool:
	if not has_island(coord):
		return false

	current_coord = coord
	return true


# Reveal more rings on the world map — the hook a boat-tier unlock will call.
func reveal_additional_rings(count: int = 1) -> void:
	revealed_rings = maxi(0, revealed_rings + count)


# --- Save/load ---
# The whole discovered world: every island keyed by its world-map coord, plus which slot is
# current and how many rings are revealed. `reference_time` is forwarded to each island so its
# production/fuel timers can be rebased (see IslandData.to_dict). Islands are restored straight
# into the dict (not via add_island) so their saved names are preserved verbatim.

func to_dict(reference_time: float) -> Dictionary:
	var serialized_islands := {}
	for coord in islands:
		serialized_islands[coord] = (islands[coord] as IslandData).to_dict(reference_time)
	return {
		current_coord = current_coord,
		revealed_rings = revealed_rings,
		islands = serialized_islands,
	}


static func from_dict(data: Dictionary, reference_time: float) -> WorldData:
	var world := WorldData.new()
	world.current_coord = data.get("current_coord", CENTER)
	world.revealed_rings = int(data.get("revealed_rings", STARTING_REVEALED_RINGS))
	var serialized_islands: Dictionary = data.get("islands", {})
	for coord in serialized_islands:
		world.islands[coord] = IslandData.from_dict(serialized_islands[coord], reference_time)
	return world
