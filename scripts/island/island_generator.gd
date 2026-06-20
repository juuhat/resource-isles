class_name IslandGenerator
extends RefCounted

# Procedural island generator, driven by an IslandProfile (the biome's contract). The same
# generic passes shape every island; the profile chooses the base terrain, resources, and
# landmarks, and the seed varies the exact layout. After generating, the result is validated
# against the profile's contract and re-rolled if it fails — so variety never produces a broken
# (un-dockable / resource-missing) island. See docs/island-generation.md.

const IslandDataScript := preload("res://scripts/island/island_data.gd")
const HexGridScript := preload("res://scripts/island/hex_grid.gd")

# How many re-rolls a failed contract gets before we give up and return the best-effort island.
const MAX_GENERATION_ATTEMPTS := 12

var rng := RandomNumberGenerator.new()


# Generate the island for `profile` using `seed_value` as the per-island seed (derive it from the
# world seed and coord in main.gd). building_manager is needed only for landmark placement
# (the crashed spaceship footprint/terrain); it may be null for biomes without landmarks.
func generate(
	profile: IslandProfile,
	seed_value: int,
	building_manager: BuildingManager = null
) -> IslandData:
	var island: IslandData
	for attempt in range(MAX_GENERATION_ATTEMPTS + 1):
		# Re-rolls perturb the seed deterministically, so a given (seed, profile) always resolves
		# to the same accepted island — reproducible even when the first roll is rejected.
		rng.seed = seed_value + attempt
		island = _generate_once(profile, building_manager)
		if _satisfies_contract(island, profile):
			return island
	push_warning("IslandGenerator: contract unmet after %d attempts (biome %d)" % [
		MAX_GENERATION_ATTEMPTS + 1, profile.biome])
	return island


func _generate_once(profile: IslandProfile, building_manager: BuildingManager) -> IslandData:
	var island := IslandDataScript.new(profile.width, profile.height)
	_fill_water(island)
	_carve_land_blob(island, profile.primary_terrain)
	_smooth_land_edges(island, profile.primary_terrain, 2)
	_add_sand_border(island, profile.primary_terrain, profile.sand_border_width)
	if profile.place_crashed_spaceship:
		_place_required_crashed_spaceship(island, building_manager)
	for feature in profile.terrain_features:
		_place_terrain_patches(island, profile.primary_terrain, feature.terrain, feature.count)
	for entry in profile.resource_table:
		_place_resource_entry(island, entry)
	if profile.place_starter_tools:
		_place_starter_tools(island)
	# Final pass: classify shallow Coast vs deep Ocean now that all land is settled.
	_classify_coastal_water(island, profile.coast_rings)
	return island


# The contract the profile guarantees: a dock can be built (a sand cell touching coast) and every
# required resource type actually landed at least once. A roll that fails is re-rolled.
func _satisfies_contract(island: IslandData, profile: IslandProfile) -> bool:
	if not _has_dockable_shore(island):
		return false
	for entry in profile.resource_table:
		if not _has_resource_of_type(island, entry.node_type):
			return false
	return true


func _has_dockable_shore(island: IslandData) -> bool:
	for cell in island.terrain.keys():
		if island.get_terrain(cell) != GameTypes.Terrain.SAND:
			continue
		for neighbor in HexGridScript.neighbors(cell):
			if island.get_terrain(neighbor) == GameTypes.Terrain.COAST:
				return true
	return false


func _has_resource_of_type(island: IslandData, node_type: int) -> bool:
	for cell in island.resources.keys():
		if island.resources[cell] == node_type:
			return true
	return false


# Multi-source flood from every land cell outward: water cells within `rings` steps of land
# become shallow Coast; the rest stay deep Ocean. Run last, so the generation steps above
# (which treat all water as WATER) are unaffected.
func _classify_coastal_water(island: IslandData, rings: int) -> void:
	var visited := {}
	var frontier: Array[Vector2i] = []

	for y in range(island.height):
		for x in range(island.width):
			var cell := Vector2i(x, y)
			if not GameTypes.is_water(island.get_terrain(cell)):
				visited[cell] = true
				frontier.append(cell)

	var distance := 0
	while not frontier.is_empty() and distance < rings:
		distance += 1
		var next_frontier: Array[Vector2i] = []
		for cell in frontier:
			for neighbor in HexGridScript.neighbors(cell):
				if visited.has(neighbor) or not island.is_in_bounds(neighbor):
					continue
				visited[neighbor] = true
				if island.get_terrain(neighbor) == GameTypes.Terrain.WATER:
					island.set_terrain(neighbor, GameTypes.Terrain.COAST)
					next_frontier.append(neighbor)
		frontier = next_frontier


# Scatters the robot's three lost tools on open base-land cells. Order follows the ItemType
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

	_shuffle(candidates)

	var tools := [GameTypes.ItemType.AXE, GameTypes.ItemType.PICKAXE, GameTypes.ItemType.HAMMER]
	for index in range(mini(tools.size(), candidates.size())):
		island.place_item(candidates[index], tools[index])


func _fill_water(island: IslandData) -> void:
	for y in range(island.height):
		for x in range(island.width):
			island.set_terrain(Vector2i(x, y), GameTypes.Terrain.WATER)


func _carve_land_blob(island: IslandData, land_terrain: int) -> void:
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
				island.set_terrain(cell, land_terrain)


func _smooth_land_edges(island: IslandData, land_terrain: int, passes: int) -> void:
	for pass_index in range(passes):
		var to_land: Array[Vector2i] = []
		var to_water: Array[Vector2i] = []

		for y in range(island.height):
			for x in range(island.width):
				var cell := Vector2i(x, y)
				var land_neighbors := _neighbor_land_count(island, cell, land_terrain)

				if island.get_terrain(cell) == land_terrain:
					if land_neighbors <= 1:
						to_water.append(cell)
				elif land_neighbors >= 4:
					to_land.append(cell)

		for cell in to_water:
			island.set_terrain(cell, GameTypes.Terrain.WATER)

		for cell in to_land:
			island.set_terrain(cell, land_terrain)


func _neighbor_land_count(island: IslandData, cell: Vector2i, land_terrain: int) -> int:
	var count := 0

	for neighbor in HexGridScript.neighbors(cell):
		if island.get_terrain(neighbor) == land_terrain:
			count += 1

	return count


func _add_sand_border(island: IslandData, land_terrain: int, width: int) -> void:
	if width <= 0:
		return

	var to_sand: Array[Vector2i] = []

	for cell in island.terrain.keys():
		if island.get_terrain(cell) != land_terrain:
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


# Places one resource_table entry: a cluster-shaped scatter (count clusters of 3) or single
# scattered nodes (count of them), stopping early if the island runs out of valid cells.
func _place_resource_entry(island: IslandData, entry: Dictionary) -> void:
	var node_type: int = entry.node_type
	var count: int = entry.count

	if entry.cluster:
		for _i in range(count):
			var cluster := _pick_resource_cluster(island, node_type)
			if cluster.is_empty():
				return
			for cell in cluster:
				island.place_resource(cell, node_type)
	else:
		for _i in range(count):
			var cell := _pick_open_resource_cell(island, node_type)
			if cell == Vector2i(-1, -1):
				return
			island.place_resource(cell, node_type)


func _place_required_crashed_spaceship(island: IslandData, building_manager: BuildingManager) -> void:
	var center := Vector2(island.width * 0.5, island.height * 0.52)
	var best_cell := Vector2i(-1, -1)
	var best_distance := INF
	var crashed_spaceship_definition := building_manager.get_definition(GameTypes.BuildingType.CRASHED_SPACESHIP) if building_manager else null
	var required_terrains: Array[int] = crashed_spaceship_definition.required_terrains if crashed_spaceship_definition != null else [GameTypes.Terrain.GRASS] as Array[int]

	for cell in island.terrain.keys():
		var footprint := building_manager.get_footprint_cells(cell, GameTypes.BuildingType.CRASHED_SPACESHIP) if building_manager else [cell] as Array[Vector2i]
		if not island.can_place_building(cell, footprint, required_terrains):
			continue

		var distance := Vector2(float(cell.x), float(cell.y)).distance_squared_to(center)
		if distance < best_distance:
			best_distance = distance
			best_cell = cell

	if best_cell != Vector2i(-1, -1):
		var footprint := building_manager.get_footprint_cells(best_cell, GameTypes.BuildingType.CRASHED_SPACESHIP) if building_manager else [best_cell] as Array[Vector2i]
		island.place_building(best_cell, GameTypes.BuildingType.CRASHED_SPACESHIP, footprint, required_terrains)
		return

	# Last resort: force a central cell to a terrain the wreck accepts, then stamp it there.
	var fallback_terrain: int = required_terrains[0] if not required_terrains.is_empty() else GameTypes.Terrain.GRASS
	var fallback_cell := Vector2i(
		clampi(roundi(center.x), 0, island.width - 1),
		clampi(roundi(center.y), 0, island.height - 1)
	)
	island.set_terrain(fallback_cell, fallback_terrain)
	var fallback_footprint := building_manager.get_footprint_cells(fallback_cell, GameTypes.BuildingType.CRASHED_SPACESHIP) if building_manager else [fallback_cell] as Array[Vector2i]
	island.place_building(fallback_cell, GameTypes.BuildingType.CRASHED_SPACESHIP, fallback_footprint, required_terrains)


# Stamps `count` hex patches of `feature_terrain` onto cells currently of `base_terrain`.
func _place_terrain_patches(island: IslandData, base_terrain: int, feature_terrain: int, count: int) -> void:
	for _i in range(count):
		var center := _pick_terrain_patch_center(island, base_terrain)
		if center == Vector2i(-1, -1):
			return
		for cell in _patch_cells(center):
			island.set_terrain(cell, feature_terrain)


func _pick_terrain_patch_center(island: IslandData, base_terrain: int) -> Vector2i:
	var candidates: Array[Vector2i] = []

	for cell in island.terrain.keys():
		if _can_place_terrain_patch_at(island, cell, base_terrain):
			candidates.append(cell)

	if candidates.is_empty():
		return Vector2i(-1, -1)

	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _can_place_terrain_patch_at(island: IslandData, center: Vector2i, base_terrain: int) -> bool:
	for cell in _patch_cells(center):
		if island.get_terrain(cell) != base_terrain or island.has_building(cell):
			return false

	return true


func _patch_cells(center: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.append(center)
	cells.append_array(HexGridScript.neighbors(center))
	return cells


func _pick_resource_cluster(island: IslandData, node_type: int) -> Array:
	var candidates: Array = []

	for cell in island.terrain.keys():
		for direction_index in range(6):
			var cluster := _resource_cluster_cells(cell, direction_index)
			if _can_place_resource_cluster(island, cluster, node_type):
				candidates.append(cluster)

	if candidates.is_empty():
		return []

	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _resource_cluster_cells(cell: Vector2i, direction_index: int) -> Array:
	return [
		cell,
		HexGridScript.neighbor(cell, direction_index),
		HexGridScript.neighbor(cell, direction_index + 1),
	]


func _can_place_resource_cluster(island: IslandData, cells: Array, node_type: int) -> bool:
	for cell in cells:
		if not island.can_place_resource(cell, node_type):
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


# Seeded Fisher-Yates so placement stays deterministic with the island seed (Array.shuffle()
# would use the global RNG instead).
func _shuffle(cells: Array[Vector2i]) -> void:
	for index in range(cells.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var temp := cells[index]
		cells[index] = cells[swap]
		cells[swap] = temp
