class_name WorldBuilder
extends RefCounted

# Fills a world in from its seed: every island on the disc and where K9-DA waits. All of it is
# derived from the world seed and each slot's coord, so a world comes out the same every run (see
# docs/island-generation.md).


# Generate every slot on the disc that doesn't exist yet. The whole archipelago is one world, so
# islands exist from the start (hidden under clouds until their ring is revealed); this also
# fills in new slots when the disc grows.
static func ensure_generated(world: WorldData, seed_value: int, building_manager: BuildingManager) -> void:
	for coord in world.all_slots():
		if not world.has_island(coord):
			world.add_island(coord, generate_island(coord, seed_value, building_manager))


# The center slot (World 1) is the crash site with the starting wreck (STARTER biome). It
# begins with no resources — the opening loop is scavenging the first wood by hand (see
# docs/progression-and-power.md). Other slots are frontier biomes and arrive
# with just enough to establish their first dock. The biome and per-island seed are both
# derived from the coord, so a slot's layout is intrinsic to where it is.
static func generate_island(coord: Vector2i, seed_value: int, building_manager: BuildingManager) -> IslandData:
	var profile := IslandProfiles.get_profile(IslandProfiles.biome_for_coord(coord, seed_value))
	var island := IslandGenerator.new().generate(profile, island_seed(coord, seed_value), building_manager)
	# Generated on cells from (0, 0); centre it on its slot of the world lattice.
	island.shift(WorldNavigation.island_origin(coord, Vector2i(profile.width, profile.height)))
	if coord != WorldData.CENTER:
		_stock_bootstrap_supplies(island, building_manager)
	return island


# Per-slot seed: combines the world seed with the hex coord so each island is distinct yet
# stable across runs (docs/island-generation.md).
static func island_seed(coord: Vector2i, seed_value: int) -> int:
	return hash(Vector3i(coord.x, coord.y, seed_value))


# A newly reached island arrives with exactly enough to build its first dock, which
# then lets it be the endpoint of a trade route — so a resource-barren island is
# never a soft-lock. There is no manual cargo step; all other goods come via trade
# routes once the dock exists (see docs/island-unlocks.md).
static func _stock_bootstrap_supplies(island: IslandData, building_manager: BuildingManager) -> void:
	var dock_cost := building_manager.get_cost(GameTypes.BuildingType.DOCK)
	for resource_type in dock_cost.keys():
		island.inventory.add_amount(resource_type, dock_cost[resource_type])


# --- K9-DA ---

# Give a new world its stranded dog: a ring-1 island (from the seed) and a spot on it.
static func place_dog(world: WorldData, seed_value: int) -> void:
	if world.dog_coord == WorldData.NO_COORD or not world.has_island(world.dog_coord):
		world.dog_coord = WorldData.dog_slot_for_seed(seed_value)
		world.dog_cell = GameTypes.NO_CELL

	if world.dog_cell == GameTypes.NO_CELL:
		world.dog_cell = choose_dog_cell(world.get_island(world.dog_coord), island_seed(world.dog_coord, seed_value))


# A cell the robot can walk to from where it lands, a few steps in so the player sees the dog on
# arrival and takes a short walk to reach it. Deterministic per island (seeded), so a world is
# stable across runs.
static func choose_dog_cell(island: IslandData, seed_of_island: int) -> Vector2i:
	const MIN_STEPS := 3
	const MAX_STEPS := 7
	var start := find_spawn_cell(island)
	# Breadth-first distances over walkable land from the robot's landing cell.
	var steps := {start: 0}
	var frontier: Array[Vector2i] = [start]
	var head := 0
	while head < frontier.size():
		var cell := frontier[head]
		head += 1
		for neighbor in HexGrid.neighbors(cell):
			if not steps.has(neighbor) and HexPathfinder.can_step(island, cell, neighbor):
				steps[neighbor] = steps[cell] + 1
				frontier.append(neighbor)

	var preferred: Array[Vector2i] = []
	var fallback: Array[Vector2i] = []
	for cell in steps:
		if cell == start or not is_open_ground(island, cell):
			continue
		if steps[cell] >= MIN_STEPS and steps[cell] <= MAX_STEPS:
			preferred.append(cell)
		else:
			fallback.append(cell)

	var candidates := preferred if not preferred.is_empty() else fallback
	if candidates.is_empty():
		return start

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_of_island
	return candidates[rng.randi_range(0, candidates.size() - 1)]


# --- Where units stand ---

# Where the robot appears on an island: beside the crashed spaceship if there is one, otherwise the
# first open ground.
static func find_spawn_cell(island: IslandData) -> Vector2i:
	var crashed_spaceship_cell := find_crashed_spaceship_cell(island)
	if crashed_spaceship_cell != GameTypes.NO_CELL:
		for neighbor in HexGrid.neighbors(crashed_spaceship_cell):
			if HexPathfinder.is_open(island, neighbor) and not island.has_item(neighbor):
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
