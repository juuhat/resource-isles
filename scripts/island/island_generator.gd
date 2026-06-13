class_name IslandGenerator
extends RefCounted

const IslandDataScript := preload("res://scripts/island/island_data.gd")
const STARTER_ISLAND_WIDTH := 34
const STARTER_ISLAND_HEIGHT := 24

var rng := RandomNumberGenerator.new()


func generate_starter_island(seed_value: int = 0) -> IslandData:
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value

	var island := IslandDataScript.new(STARTER_ISLAND_WIDTH, STARTER_ISLAND_HEIGHT)
	_fill_water(island)
	_carve_grass_blob(island)
	_add_sand_border(island)
	_place_trees(island)
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
				(point.x - center.x) / 8.8,
				(point.y - center.y) / 5.6
			).length()
			var edge_noise := rng.randf_range(-0.18, 0.18)

			if normalized_distance + edge_noise < 1.0:
				island.set_terrain(cell, IslandData.Terrain.GRASS)

	# Add a couple of chunky peninsulas so the shape feels authored.
	var center_cell := Vector2i(roundi(center.x), roundi(center.y))
	_fill_rect(island, Rect2i(center_cell.x - 7, center_cell.y - 3, 5, 4), IslandData.Terrain.GRASS)
	_fill_rect(island, Rect2i(center_cell.x + 2, center_cell.y - 2, 5, 4), IslandData.Terrain.GRASS)
	_fill_rect(island, Rect2i(center_cell.x - 2, center_cell.y + 2, 7, 2), IslandData.Terrain.GRASS)


func _add_sand_border(island: IslandData) -> void:
	var to_sand: Array[Vector2i] = []

	for cell in island.terrain.keys():
		if island.get_terrain(cell) != IslandData.Terrain.GRASS:
			continue

		for neighbor in _cardinal_neighbors(cell):
			if island.get_terrain(neighbor) == IslandData.Terrain.WATER:
				to_sand.append(cell)
				break

	for cell in to_sand:
		island.set_terrain(cell, IslandData.Terrain.SAND)


func _fill_rect(island: IslandData, rect: Rect2i, terrain_type: int) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			island.set_terrain(Vector2i(x, y), terrain_type)


func _place_trees(island: IslandData) -> void:
	for index in range(2):
		var cell := _pick_open_grass_cell(island)
		if cell != Vector2i(-1, -1):
			island.place_resource(cell, IslandData.ResourceNodeType.TREE)


func _pick_open_grass_cell(island: IslandData) -> Vector2i:
	var candidates: Array[Vector2i] = []

	for cell in island.terrain.keys():
		if island.can_place_resource(cell):
			candidates.append(cell)

	if candidates.is_empty():
		return Vector2i(-1, -1)

	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _cardinal_neighbors(cell: Vector2i) -> Array[Vector2i]:
	return [
		cell + Vector2i.LEFT,
		cell + Vector2i.RIGHT,
		cell + Vector2i.UP,
		cell + Vector2i.DOWN,
	]
