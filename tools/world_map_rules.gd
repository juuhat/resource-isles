extends RefCounted

# The rules the world map has to keep for the game to work (docs/world-map-and-island-designs.md),
# checked on the islands built from it. tools/world_map_check.gd fails on any problem; the map
# preview can use the same list to mark the islands involved.
#
#   - no two islands share a cell (each island's coast reaches 2 cells past its land), or the game
#     leaves the later one out;
#   - every island lies within the sea: SEA_RINGS rings of the centre, inside the mountains;
#   - every island has a shore a dock can be built on;
#   - the robot can reach every item, and a tile beside every deposit, without climbing over
#     deposits: on the start island from where it wakes, elsewhere from the shore;
#   - the start island is revealed from the start and has the crashed spaceship and the robot's
#     three tools;
#   - K9-DA waits on another island, at a marked spot reachable from the shore, and all of that
#     island lies in the home waters (WorldData.HOME_WATERS_RINGS), sailable from the start;
#   - no other island's centre lies in the home waters: the rest wait for the radar.
#
# A problem is {islands: Array[StringName] (the ids involved), message: String}.

# The farthest any island may reach: the sailing frontier of a world with all its rings revealed.
const SEA_RINGS := WorldData.MIN_WORLD_RINGS + 0.5
const START_TOOLS: Array[int] = [GameTypes.ItemType.AXE, GameTypes.ItemType.PICKAXE, GameTypes.ItemType.WRENCH]


# Every problem with the map. Designs come from assets/world/islands unless `designs` (name ->
# IslandDesign) has them, which a check uses to try designs made to break a rule.
static func problems(map: WorldMap, building_manager: BuildingManager, designs := {}) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for error in map.errors:
		found.append(_problem([], "World map: " + error))

	var islands := {}
	var placements := {}
	var built_designs := {}
	for placement: WorldMap.Placement in map.placements:
		var design: IslandDesign = designs.get(placement.design, null)
		if design == null:
			design = IslandDesign.load_named(placement.design)
		if not design.errors.is_empty():
			for error in design.errors:
				found.append(_problem([placement.id], "[%s] %s" % [placement.id, error]))
			continue
		var island := design.build(placement.center, placement.rotation, placement.mirror, building_manager)
		if not design.build_errors.is_empty():
			for error in design.build_errors:
				found.append(_problem([placement.id], "[%s] %s" % [placement.id, error]))
			continue
		islands[placement.id] = island
		placements[placement.id] = placement
		built_designs[placement.id] = design

	_find_overlaps(islands, found)
	for id: StringName in islands:
		var island: IslandData = islands[id]
		var placement: WorldMap.Placement = placements[id]
		_check_sea_edge(id, island, found)
		_check_dock_shore(id, island, building_manager, found)
		var sources := _landing_cells(island)
		if placement.start:
			sources = [WorldBuilder.find_spawn_cell(island)]
		var reached := _reached(island, sources)
		_check_items(id, island, reached, found)
		_check_deposits(id, island, reached, found)
		if placement.start:
			_check_start(id, island, placement, found)
		if placement.k9da:
			_check_k9da(id, island, placement, built_designs[id], reached, found)
		elif not placement.start and WorldData.rings_out(placement.center) <= _home_waters():
			found.append(_problem([id], "[%s] lies %.2f rings out, in the home waters; only the start and K9-DA's islands may, the rest wait for the radar to reveal them"
				% [id, WorldData.rings_out(placement.center)]))
	return found


# How far the sea is open at the start, in rings: the home waters.
static func _home_waters() -> float:
	return WorldData.frontier_rings_for(WorldData.STARTING_REVEALED_RINGS)


static func _problem(ids: Array, message: String) -> Dictionary:
	var islands: Array[StringName] = []
	islands.assign(ids)
	return {islands = islands, message = message}


# Each pair of islands that shares a cell, once, with the first cell they share.
static func _find_overlaps(islands: Dictionary, found: Array[Dictionary]) -> void:
	var owners := {}
	var reported := {}
	for id: StringName in islands:
		for cell: Vector2i in (islands[id] as IslandData).terrain:
			var other: StringName = owners.get(cell, &"")
			if other == &"":
				owners[cell] = id
			elif not reported.has("%s|%s" % [other, id]):
				reported["%s|%s" % [other, id]] = true
				found.append(_problem([other, id], "[%s] and [%s] overlap at %d,%d: an island's coast reaches 2 cells past its land, and no cell can belong to both"
					% [other, id, cell.x, cell.y]))


static func _check_sea_edge(id: StringName, island: IslandData, found: Array[Dictionary]) -> void:
	for cell: Vector2i in island.terrain:
		if WorldData.rings_out(cell) > SEA_RINGS:
			found.append(_problem([id], "[%s] runs past the edge of the sea at %d,%d: keep every island within %.1f rings of the centre"
				% [id, cell.x, cell.y, SEA_RINGS]))
			return


static func _check_dock_shore(id: StringName, island: IslandData, building_manager: BuildingManager, found: Array[Dictionary]) -> void:
	for cell: Vector2i in island.terrain:
		if island.get_terrain(cell) != GameTypes.Terrain.SAND:
			continue
		for rotation in 6:
			if building_manager.can_place(cell, GameTypes.BuildingType.DOCK, island, rotation):
				return
	found.append(_problem([id], "[%s] has nowhere to build a dock: it needs sand beside the coast, with room for the pier" % id))


# Open land the robot can step onto from a boat: next to the island's own water.
static func _landing_cells(island: IslandData) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in island.terrain:
		if not HexPathfinder.is_open(island, cell) or GameTypes.is_water(island.get_terrain(cell)):
			continue
		for neighbor in HexGrid.neighbors(cell):
			if island.has_cell(neighbor) and GameTypes.is_water(island.get_terrain(neighbor)):
				cells.append(cell)
				break
	return cells


# The cells the robot can walk to from `sources` without stepping onto a deposit or a solid
# landmark (HexPathfinder.step_cost 1), as a set.
static func _reached(island: IslandData, sources: Array[Vector2i]) -> Dictionary:
	var reached := {}
	var frontier: Array[Vector2i] = []
	for cell in sources:
		if HexPathfinder.is_walkable(island, cell) and HexPathfinder.step_cost(island, cell) == 1:
			reached[cell] = true
			frontier.append(cell)
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for neighbor in HexGrid.neighbors(cell):
			if not reached.has(neighbor) and HexPathfinder.can_step(island, cell, neighbor) \
					and HexPathfinder.step_cost(island, neighbor) == 1:
				reached[neighbor] = true
				frontier.append(neighbor)
	return reached


static func _check_items(id: StringName, island: IslandData, reached: Dictionary, found: Array[Dictionary]) -> void:
	for cell: Vector2i in island.items:
		if not reached.has(cell):
			found.append(_problem([id], "[%s] the %s at %d,%d is walled in by deposits"
				% [id, _item_name(island.items[cell]), cell.x, cell.y]))


# A deposit is worked from a tile beside it.
static func _check_deposits(id: StringName, island: IslandData, reached: Dictionary, found: Array[Dictionary]) -> void:
	for cell: Vector2i in island.resources:
		if not HexGrid.neighbors(cell).any(func(neighbor: Vector2i) -> bool: return reached.has(neighbor)):
			found.append(_problem([id], "[%s] the %s deposit at %d,%d is walled in by other deposits, so the robot can't work it"
				% [id, _deposit_name(island.resources[cell]), cell.x, cell.y]))


static func _check_start(id: StringName, island: IslandData, placement: WorldMap.Placement, found: Array[Dictionary]) -> void:
	var limit := _home_waters()
	if WorldData.rings_out(placement.center) > limit:
		found.append(_problem([id], "[%s] is the start island but lies %.2f rings out, under the clouds when the game starts; keep it within %.1f"
			% [id, WorldData.rings_out(placement.center), limit]))
	if WorldBuilder.find_crashed_spaceship_cell(island) == GameTypes.NO_CELL:
		found.append(_problem([id], "[%s] is the start island but has no crashed spaceship" % id))
	for tool in START_TOOLS:
		if not island.items.values().has(tool):
			found.append(_problem([id], "[%s] is the start island but has no %s for the robot to find" % [id, _item_name(tool)]))


# K9-DA's spot must be reachable from the shore, where the robot lands to rescue it.
static func _check_k9da(
	id: StringName,
	island: IslandData,
	placement: WorldMap.Placement,
	design: IslandDesign,
	reached: Dictionary,
	found: Array[Dictionary]
) -> void:
	if placement.start:
		found.append(_problem([id], "[%s] K9-DA must wait on another island than the start island" % id))
	# All of it, coast included, so the boat can sail right around it before the radar is repaired.
	var home_radius := _home_waters() * WorldNavigation.RING_SPACING
	var farthest := 0.0
	for cell: Vector2i in island.terrain:
		var point := WorldNavigation.cell_center(cell)
		farthest = maxf(farthest, Vector2(point.x, point.z).length() + WorldNavigation.CELL_SIZE.x * 0.5)
	if farthest > home_radius:
		found.append(_problem([id], "[%s] is K9-DA's island but reaches %.2f rings out, past the home waters (%.2f), which are all the boat can sail before the radar is repaired"
			% [id, farthest / WorldNavigation.RING_SPACING, _home_waters()]))
	var spot := design.marker_cell("k9da", placement.center, placement.rotation, placement.mirror)
	if spot == GameTypes.NO_CELL:
		found.append(_problem([id], "[%s] is K9-DA's island but its design %s has no k9da marker" % [id, placement.design]))
	elif not placement.start and not reached.has(spot):
		found.append(_problem([id], "[%s] K9-DA's spot at %d,%d can't be reached from the shore without climbing over deposits"
			% [id, spot.x, spot.y]))


static func _item_name(item: int) -> String:
	return String(GameTypes.ItemType.find_key(item)).to_lower()


static func _deposit_name(node_type: int) -> String:
	return String(GameTypes.ResourceNodeType.find_key(node_type)).to_lower().replace("_", " ")
