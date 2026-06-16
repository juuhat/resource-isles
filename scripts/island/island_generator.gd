class_name IslandGenerator
extends RefCounted

const IslandDataScript := preload("res://scripts/island/island_data.gd")
const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const STARTER_ISLAND_WIDTH := 30
const STARTER_ISLAND_HEIGHT := 24
const SAND_BORDER_WIDTH := 1

var rng := RandomNumberGenerator.new()


# place_crashed_spaceship forces the central wreck — the win-condition ship the
# robot starts beside. Only the starter island (World 1) gets it; later islands
# are discovered, not crash sites.
func generate_starter_island(
	seed_value: int = 0,
	building_manager: BuildingManager = null,
	place_crashed_spaceship: bool = true
) -> IslandData:
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value

	var island := IslandDataScript.new(STARTER_ISLAND_WIDTH, STARTER_ISLAND_HEIGHT)
	_fill_water(island)
	_carve_grass_blob(island)
	_smooth_grass_edges(island, 2)
	_add_sand_border(island, SAND_BORDER_WIDTH)
	if place_crashed_spaceship:
		_place_required_crashed_spaceship(island, building_manager)
	_place_stone_patch(island)
	_place_trees(island)
	_place_stones(island)
	# Only the starter island scatters the robot's lost tools — they drive the opening
	# "Hello World" quest (recover them to unlock harvesting). Other islands skip this.
	if place_crashed_spaceship:
		_place_starter_tools(island)
	return island


# Scatters the robot's three lost tools on open grass cells. Order follows the ItemType
# list; if there aren't three free cells (a tiny island), it places as many as it can.
func _place_starter_tools(island: IslandData) -> void:
	var candidates: Array[Vector2i] = []
	for cell in island.terrain.keys():
		if (
			island.get_terrain(cell) == GameTypes.Terrain.GRASS
			and not island.has_resource(cell)
			and not island.has_building(cell)
			and not island.has_item(cell)
		):
			candidates.append(cell)

	if candidates.is_empty():
		return

	# Seeded Fisher-Yates so tool placement stays deterministic with the island seed
	# (Array.shuffle() would use the global RNG instead).
	for index in range(candidates.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var temp := candidates[index]
		candidates[index] = candidates[swap]
		candidates[swap] = temp

	var tools := [GameTypes.ItemType.AXE, GameTypes.ItemType.PICKAXE, GameTypes.ItemType.HAMMER]
	for index in range(mini(tools.size(), candidates.size())):
		island.place_item(candidates[index], tools[index])


func _fill_water(island: IslandData) -> void:
	for y in range(island.height):
		for x in range(island.width):
			island.set_terrain(Vector2i(x, y), GameTypes.Terrain.WATER)


func _carve_grass_blob(island: IslandData) -> void:
	var center := Vector2(island.width * 0.5, island.height * 0.52)

	for y in range(island.height):
		for x in range(island.width):
			var cell := Vector2i(x, y)
			var point := Vector2(x, y)
			var normalized_distance := Vector2(
				(point.x - center.x) / 5.6,
				(point.y - center.y) / 4.6
			).length()
			var edge_noise := rng.randf_range(-0.055, 0.055)

			if normalized_distance + edge_noise < 1.0:
				island.set_terrain(cell, GameTypes.Terrain.GRASS)


func _smooth_grass_edges(island: IslandData, passes: int) -> void:
	for pass_index in range(passes):
		var to_grass: Array[Vector2i] = []
		var to_water: Array[Vector2i] = []

		for y in range(island.height):
			for x in range(island.width):
				var cell := Vector2i(x, y)
				var land_neighbors := _neighbor_land_count(island, cell)

				if island.get_terrain(cell) == GameTypes.Terrain.GRASS:
					if land_neighbors <= 1:
						to_water.append(cell)
				elif land_neighbors >= 4:
					to_grass.append(cell)

		for cell in to_water:
			island.set_terrain(cell, GameTypes.Terrain.WATER)

		for cell in to_grass:
			island.set_terrain(cell, GameTypes.Terrain.GRASS)


func _neighbor_land_count(island: IslandData, cell: Vector2i) -> int:
	var count := 0

	for neighbor in HexGridScript.neighbors(cell):
		if island.get_terrain(neighbor) == GameTypes.Terrain.GRASS:
			count += 1

	return count


func _add_sand_border(island: IslandData, width: int) -> void:
	if width <= 0:
		return

	var to_sand: Array[Vector2i] = []

	for cell in island.terrain.keys():
		if island.get_terrain(cell) != GameTypes.Terrain.GRASS:
			continue

		for neighbor in HexGridScript.neighbors(cell):
			if island.get_terrain(neighbor) == GameTypes.Terrain.WATER:
				to_sand.append(cell)
				break

	for cell in to_sand:
		island.set_terrain(cell, GameTypes.Terrain.SAND)

	for pass_index in range(width - 1):
		_expand_sand_into_water(island)


func _expand_sand_into_water(island: IslandData) -> void:
	var to_sand: Array[Vector2i] = []

	for y in range(island.height):
		for x in range(island.width):
			var cell := Vector2i(x, y)
			if island.get_terrain(cell) != GameTypes.Terrain.WATER:
				continue

			for neighbor in HexGridScript.neighbors(cell):
				if island.get_terrain(neighbor) == GameTypes.Terrain.SAND:
					to_sand.append(cell)
					break

	for cell in to_sand:
		island.set_terrain(cell, GameTypes.Terrain.SAND)


func _place_trees(island: IslandData) -> void:
	var cluster := _pick_forest_cluster(island)
	if cluster.is_empty():
		return

	for cell in cluster:
		island.place_resource(cell, GameTypes.ResourceNodeType.TREE)


func _place_stones(island: IslandData) -> void:
	for index in range(2):
		var cell := _pick_open_resource_cell(island, GameTypes.ResourceNodeType.STONE)
		if cell != Vector2i(-1, -1):
			island.place_resource(cell, GameTypes.ResourceNodeType.STONE)


func _place_stone_patch(island: IslandData) -> void:
	var center := _pick_stone_patch_center(island)
	if center == Vector2i(-1, -1):
		return

	for cell in _stone_patch_cells(center):
		island.set_terrain(cell, GameTypes.Terrain.STONE)


func _place_required_crashed_spaceship(island: IslandData, building_manager: BuildingManager) -> void:
	var center := Vector2(island.width * 0.5, island.height * 0.52)
	var best_cell := Vector2i(-1, -1)
	var best_distance := INF
	var crashed_spaceship_definition := building_manager.get_definition(GameTypes.BuildingType.CRASHED_SPACESHIP) if building_manager else null
	var required_terrain: int = crashed_spaceship_definition.required_terrain if crashed_spaceship_definition != null else GameTypes.Terrain.GRASS

	for cell in island.terrain.keys():
		var footprint := building_manager.get_footprint_cells(cell, GameTypes.BuildingType.CRASHED_SPACESHIP) if building_manager else [cell] as Array[Vector2i]
		if not island.can_place_building(cell, footprint, required_terrain):
			continue

		var distance := Vector2(float(cell.x), float(cell.y)).distance_squared_to(center)
		if distance < best_distance:
			best_distance = distance
			best_cell = cell

	if best_cell != Vector2i(-1, -1):
		var footprint := building_manager.get_footprint_cells(best_cell, GameTypes.BuildingType.CRASHED_SPACESHIP) if building_manager else [best_cell] as Array[Vector2i]
		island.place_building(best_cell, GameTypes.BuildingType.CRASHED_SPACESHIP, footprint, required_terrain)
		return

	var fallback_cell := Vector2i(
		clampi(roundi(center.x), 0, island.width - 1),
		clampi(roundi(center.y), 0, island.height - 1)
	)
	island.set_terrain(fallback_cell, required_terrain)
	var fallback_footprint := building_manager.get_footprint_cells(fallback_cell, GameTypes.BuildingType.CRASHED_SPACESHIP) if building_manager else [fallback_cell] as Array[Vector2i]
	island.place_building(fallback_cell, GameTypes.BuildingType.CRASHED_SPACESHIP, fallback_footprint, required_terrain)


func _pick_stone_patch_center(island: IslandData) -> Vector2i:
	var candidates: Array[Vector2i] = []

	for cell in island.terrain.keys():
		if _can_place_stone_patch_at(island, cell):
			candidates.append(cell)

	if candidates.is_empty():
		return Vector2i(-1, -1)

	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _can_place_stone_patch_at(island: IslandData, center: Vector2i) -> bool:
	for cell in _stone_patch_cells(center):
		if island.get_terrain(cell) != GameTypes.Terrain.GRASS or island.has_building(cell):
			return false

	return true


func _stone_patch_cells(center: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.append(center)
	cells.append_array(HexGridScript.neighbors(center))
	return cells


func _pick_forest_cluster(island: IslandData) -> Array:
	var candidates: Array = []

	for cell in island.terrain.keys():
		for direction_index in range(6):
			var cluster := _forest_cluster_cells(cell, direction_index)
			if _can_place_forest_cluster(island, cluster):
				candidates.append(cluster)

	if candidates.is_empty():
		return []

	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _forest_cluster_cells(cell: Vector2i, direction_index: int) -> Array:
	return [
		cell,
		HexGridScript.neighbor(cell, direction_index),
		HexGridScript.neighbor(cell, direction_index + 1),
	]


func _can_place_forest_cluster(island: IslandData, cells: Array) -> bool:
	for cell in cells:
		if not island.can_place_resource(cell, GameTypes.ResourceNodeType.TREE):
			return false

	return true


func _pick_open_resource_cell(island: IslandData, resource_node_type: int) -> Vector2i:
	var candidates: Array[Vector2i] = []

	for cell in island.terrain.keys():
		if island.can_place_resource(cell, resource_node_type):
			candidates.append(cell)

	if candidates.is_empty():
		return Vector2i(-1, -1)

	return candidates[rng.randi_range(0, candidates.size() - 1)]
