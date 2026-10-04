class_name BoatNavigation
extends RefCounted

const Grid := preload("res://scripts/island/hex_grid.gd")
const Ground := preload("res://scripts/island/hex_pathfinder.gd")

static func can_sail(island: IslandData, cell: Vector2i, own_id := -1) -> bool:
	if not island.is_in_bounds(cell) or not GameTypes.is_water(island.get_terrain(cell)) or Ground.is_deck(island, cell):
		return false
	if island.has_building(cell):
		var anchor := island.get_building_anchor_cell(cell)
		var building: Dictionary = island.buildings[anchor]
		if int(building.type) != GameTypes.BuildingType.DOCK or building.has("build_progress") or building.cells.back() != cell:
			return false
		if not building.get("boat_launched", false):
			return false
	for id in island.boats:
		if id != own_id and island.boats[id].cell == cell:
			return false
	return true

static func find_path(island: IslandData, start: Vector2i, goal: Vector2i, own_id := -1) -> Array[Vector2i]:
	if not can_sail(island, start, own_id) or not can_sail(island, goal, own_id):
		return []
	var frontier: Array[Vector2i] = [start]
	var previous := {start: start}
	var head := 0
	while head < frontier.size():
		var cell := frontier[head]
		head += 1
		if cell == goal:
			break
		for neighbor in Grid.neighbors(cell):
			if not previous.has(neighbor) and can_sail(island, neighbor, own_id):
				previous[neighbor] = cell
				frontier.append(neighbor)
	return Ground.path_to({came_from = previous}, goal)

# Decks and unobstructed shoreline ground are valid transfers. The boat stays afloat.
static func can_land(island: IslandData, boat_cell: Vector2i, shore: Vector2i) -> bool:
	return Grid.neighbors(boat_cell).has(shore) and Ground.is_open(island, shore) \
		and not island.has_resource(shore) \
		and (Ground.is_deck(island, shore) or not GameTypes.is_water(island.get_terrain(shore)))
