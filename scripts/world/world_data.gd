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
