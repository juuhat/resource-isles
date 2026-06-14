class_name IslandGenerator
extends RefCounted

const IslandDataScript := preload("res://scripts/island/island_data.gd")
const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const STARTER_ISLAND_WIDTH := 30
const STARTER_ISLAND_HEIGHT := 24
const SAND_BORDER_WIDTH := 1

var rng := RandomNumberGenerator.new()


func generate_starter_island(seed_value: int = 0) -> IslandData:
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value

	var island := IslandDataScript.new(STARTER_ISLAND_WIDTH, STARTER_ISLAND_HEIGHT)
	_fill_water(island)
	_carve_grass_blob(island)
	_smooth_grass_edges(island, 2)
	_add_sand_border(island, SAND_BORDER_WIDTH)
	_place_required_hub(island)
	_place_stone_patch(island)
	_place_trees(island)
	_place_boulders(island)
	return island


func _fill_water(island: IslandData) -> void:
	for y in range(island.height):
		for x in range(island.width):
			island.set_terrain(Vector2i(x, y), IslandData.Terrain.WATER)


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
				island.set_terrain(cell, IslandData.Terrain.GRASS)


func _smooth_grass_edges(island: IslandData, passes: int) -> void:
	for pass_index in range(passes):
		var to_grass: Array[Vector2i] = []
		var to_water: Array[Vector2i] = []

		for y in range(island.height):
			for x in range(island.width):
				var cell := Vector2i(x, y)
				var land_neighbors := _neighbor_land_count(island, cell)

				if island.get_terrain(cell) == IslandData.Terrain.GRASS:
					if land_neighbors <= 1:
						to_water.append(cell)
				elif land_neighbors >= 4:
					to_grass.append(cell)

		for cell in to_water:
			island.set_terrain(cell, IslandData.Terrain.WATER)

		for cell in to_grass:
			island.set_terrain(cell, IslandData.Terrain.GRASS)


func _neighbor_land_count(island: IslandData, cell: Vector2i) -> int:
	var count := 0

	for neighbor in HexGridScript.neighbors(cell):
		if island.get_terrain(neighbor) == IslandData.Terrain.GRASS:
			count += 1

	return count


func _add_sand_border(island: IslandData, width: int) -> void:
	if width <= 0:
		return

	var to_sand: Array[Vector2i] = []

	for cell in island.terrain.keys():
		if island.get_terrain(cell) != IslandData.Terrain.GRASS:
			continue

		for neighbor in HexGridScript.neighbors(cell):
			if island.get_terrain(neighbor) == IslandData.Terrain.WATER:
				to_sand.append(cell)
				break

	for cell in to_sand:
		island.set_terrain(cell, IslandData.Terrain.SAND)

	for pass_index in range(width - 1):
		_expand_sand_into_water(island)


func _expand_sand_into_water(island: IslandData) -> void:
	var to_sand: Array[Vector2i] = []

	for y in range(island.height):
		for x in range(island.width):
			var cell := Vector2i(x, y)
			if island.get_terrain(cell) != IslandData.Terrain.WATER:
				continue

			for neighbor in HexGridScript.neighbors(cell):
				if island.get_terrain(neighbor) == IslandData.Terrain.SAND:
					to_sand.append(cell)
					break

	for cell in to_sand:
		island.set_terrain(cell, IslandData.Terrain.SAND)


func _place_trees(island: IslandData) -> void:
	for index in range(2):
		var cell := _pick_open_resource_cell(island, IslandData.ResourceNodeType.TREE)
		if cell != Vector2i(-1, -1):
			island.place_resource(cell, IslandData.ResourceNodeType.TREE)


func _place_boulders(island: IslandData) -> void:
	for index in range(2):
		var cell := _pick_open_resource_cell(island, IslandData.ResourceNodeType.BOULDER)
		if cell != Vector2i(-1, -1):
			island.place_resource(cell, IslandData.ResourceNodeType.BOULDER)


func _place_stone_patch(island: IslandData) -> void:
	var center := _pick_stone_patch_center(island)
	if center == Vector2i(-1, -1):
		return

	for cell in _stone_patch_cells(center):
		island.set_terrain(cell, IslandData.Terrain.STONE)


func _place_required_hub(island: IslandData) -> void:
	var center := Vector2(island.width * 0.5, island.height * 0.52)
	var best_cell := Vector2i(-1, -1)
	var best_distance := INF

	for cell in island.terrain.keys():
		if not island.can_place_building(cell, IslandData.BuildingType.HUB):
			continue

		var distance := Vector2(float(cell.x), float(cell.y)).distance_squared_to(center)
		if distance < best_distance:
			best_distance = distance
			best_cell = cell

	if best_cell != Vector2i(-1, -1):
		island.place_building(best_cell, IslandData.BuildingType.HUB)
		return

	var fallback_cell := Vector2i(
		clampi(roundi(center.x), 0, island.width - 1),
		clampi(roundi(center.y), 0, island.height - 1)
	)
	island.set_terrain(fallback_cell, IslandData.Terrain.GRASS)
	island.place_building(fallback_cell, IslandData.BuildingType.HUB)


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
		if island.get_terrain(cell) != IslandData.Terrain.GRASS or island.has_building(cell):
			return false

	return true


func _stone_patch_cells(center: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.append(center)
	cells.append_array(HexGridScript.neighbors(center))
	return cells


func _pick_open_resource_cell(island: IslandData, resource_node_type: int) -> Vector2i:
	var candidates: Array[Vector2i] = []

	for cell in island.terrain.keys():
		if island.can_place_resource(cell, resource_node_type):
			candidates.append(cell)

	if candidates.is_empty():
		return Vector2i(-1, -1)

	return candidates[rng.randi_range(0, candidates.size() - 1)]
