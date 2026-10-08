class_name WorldBuilder
extends RefCounted

# Puts the world map's islands into a world (see docs/world-map-and-island-designs.md), and finds
# where units stand on an island.


# Builds every island on the map that the world doesn't have yet, matched by map id: all of them
# for a new world, and for a saved one any island added to the map since. A saved island stays as
# it was saved, even if the map has moved or changed it since, and an island that would overlap one
# already there is left out. A new world starts on the map's start island, and a world without
# K9-DA gets it at the k9da marker of the map's k9da island. Islands keep the map's order, so the
# default names count up it ("World 1", "World 2", ...). New islands start with an empty stock.
static func add_map_islands(world: WorldData, map: WorldMap, building_manager: BuildingManager) -> void:
	for error in map.errors:
		push_error("World map: " + error)
	var new_world := world.islands.is_empty()
	var known_ids := {}
	var taken := {}
	for coord in world.islands:
		var existing: IslandData = world.islands[coord]
		known_ids[existing.map_id] = true
		for cell in existing.terrain:
			taken[cell] = true

	for placement: WorldMap.Placement in map.placements:
		if known_ids.has(placement.id):
			continue
		var design := IslandDesign.load_named(placement.design)
		if not design.errors.is_empty():
			for error in design.errors:
				push_error("World map [%s]: %s" % [placement.id, error])
			continue
		var island := design.build(placement.center, placement.rotation, placement.mirror, building_manager)
		if not design.build_errors.is_empty():
			for error in design.build_errors:
				push_error("World map [%s]: %s" % [placement.id, error])
			continue
		if world.has_island(placement.center) or island.terrain.keys().any(func(cell: Vector2i) -> bool: return taken.has(cell)):
			push_warning("World map [%s]: left out, it would overlap an island already in the world" % placement.id)
			continue

		island.map_id = placement.id
		island.island_name = placement.name
		world.add_island(placement.center, island)
		for cell in island.terrain:
			taken[cell] = true
		if new_world and placement.start:
			world.start_coord = placement.center
			world.current_coord = placement.center
		if placement.k9da and world.dog_coord == WorldData.NO_COORD:
			world.dog_coord = placement.center
			world.dog_cell = design.marker_cell("k9da", placement.center, placement.rotation, placement.mirror)


# --- Where units stand ---

# Where the robot appears on an island: beside the crashed spaceship if there is one, otherwise the
# first open ground.
static func find_spawn_cell(island: IslandData) -> Vector2i:
	var crashed_spaceship_cell := find_crashed_spaceship_cell(island)
	if crashed_spaceship_cell != GameTypes.NO_CELL:
		for neighbor in HexGrid.neighbors(crashed_spaceship_cell):
			if HexPathfinder.is_open(island, neighbor) and not island.has_item(neighbor) \
					and HexPathfinder.within_climb(island, neighbor, crashed_spaceship_cell):
				return neighbor

	for cell in island.terrain:
		if is_open_ground(island, cell):
			return cell

	# No open ground at all: the island's first cell, as good as any.
	return island.terrain.keys().front() if not island.terrain.is_empty() else GameTypes.NO_CELL


# Walkable land with nothing on it — somewhere a unit can stand without overlapping anything.
static func is_open_ground(island: IslandData, cell: Vector2i) -> bool:
	return HexPathfinder.is_open(island, cell) and not island.has_item(cell)


static func find_crashed_spaceship_cell(island: IslandData) -> Vector2i:
	for cell in island.buildings.keys():
		if island.buildings[cell].type == GameTypes.BuildingType.CRASHED_SPACESHIP:
			return cell

	return GameTypes.NO_CELL
