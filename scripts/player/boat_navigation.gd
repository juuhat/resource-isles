class_name BoatNavigation
extends RefCounted

# Boat rules on one island's own cells: where a boat may float, and where it may land. Open sea and
# other boats are WorldNavigation's concern.

const Grid := preload("res://scripts/island/hex_grid.gd")
const Ground := preload("res://scripts/island/hex_pathfinder.gd")

static func can_sail(island: IslandData, cell: Vector2i) -> bool:
	if not island.has_cell(cell) or not GameTypes.is_water(island.get_terrain(cell)) or Ground.is_deck(island, cell):
		return false
	if island.has_building(cell):
		var anchor := island.get_building_anchor_cell(cell)
		var building: Dictionary = island.buildings[anchor]
		if int(building.type) != GameTypes.BuildingType.DOCK or building.has("build_progress") or building.cells.back() != cell:
			return false
		if not building.get("boat_launched", false):
			return false
	return true

# Decks and unobstructed shoreline ground are valid transfers. The boat stays afloat.
static func can_land(island: IslandData, boat_cell: Vector2i, shore: Vector2i) -> bool:
	return Grid.neighbors(boat_cell).has(shore) and Ground.is_open(island, shore) \
		and not island.has_resource(shore) \
		and (Ground.is_deck(island, shore) or not GameTypes.is_water(island.get_terrain(shore)))
