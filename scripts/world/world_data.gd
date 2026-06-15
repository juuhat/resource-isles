class_name WorldData
extends RefCounted

# Holds every island the player has generated/discovered plus a pointer to the
# one currently loaded into the renderer. The robot, camera, and simulation all
# operate on get_current(); other islands persist untouched (their buildings and
# resources are kept) until the player switches back to them.
#
# Step 2 of docs/island-unlocks.md: data structure + current-island pointer only.
# Future steps add per-island world-map metadata (ring/radius, sea position,
# discovered flag) and per-island inventory once inter-island logistics arrive.

var islands: Array[IslandData] = []
var current_index: int = -1


func add_island(island: IslandData) -> int:
	islands.append(island)
	var index := islands.size() - 1
	if island.island_name.is_empty():
		island.island_name = "World %d" % (index + 1)
	return index


func island_count() -> int:
	return islands.size()


func get_current() -> IslandData:
	return get_island(current_index)


func get_island(index: int) -> IslandData:
	if index < 0 or index >= islands.size():
		return null

	return islands[index]


func set_current(index: int) -> bool:
	if index < 0 or index >= islands.size():
		return false

	current_index = index
	return true
