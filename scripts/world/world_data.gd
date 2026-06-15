class_name WorldData
extends RefCounted

# Islands keyed by their world-map hex coordinate (axial Vector2i). The starter sits
# at CENTER; other slots are generated on demand when the player clicks them on the
# world map. Dictionaries preserve insertion order, so keys() doubles as discovery
# order (used for naming and quick cycling). See docs/island-unlocks.md.

const CENTER := Vector2i(0, 0)

var islands: Dictionary = {}
var current_coord := CENTER


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
