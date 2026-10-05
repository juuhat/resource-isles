class_name SaveMigration
extends RefCounted

# Brings a save payload from an older version up to the current one, one version at a time. Each
# step works on the plain saved data of the version it reads, never through the game's classes,
# so later changes to those classes can't break loading an old save.

const HexGridScript := preload("res://scripts/island/hex_grid.gd")


# The payload upgraded as far as the steps below go. SaveManager rejects it if that still isn't
# the current version (an unknown or newer one).
static func upgrade(payload: Dictionary) -> Dictionary:
	var upgraded := payload
	if int(upgraded.get("version", 0)) == 1:
		upgraded = _v1_to_v2(upgraded)
	return upgraded


# --- Version 1 -> 2: island cells -> world lattice cells ---
# Version 1 kept each island's cells in its own grid, from (0, 0) to (width - 1, height - 1), and
# placed that grid on the world lattice only when needed. Version 2 keys everything by the world
# lattice. The placement below is exactly the one version 1 used, kept here as it was so later
# changes to how new islands are placed can't move an old save's islands.

static func _v1_to_v2(payload: Dictionary) -> Dictionary:
	var upgraded := payload.duplicate(true)
	upgraded.version = 2
	var world: Dictionary = upgraded.get("world", {})
	var islands: Dictionary = world.get("islands", {})
	var boats: Dictionary = world.get("boats", {})
	for coord in islands:
		var island: Dictionary = islands[coord]
		var origin := _v1_island_origin(coord, int(island.get("width", 0)), int(island.get("height", 0)))
		for key in [
			"terrain", "resources", "items", "scavenged_cells", "next_production_times",
			"next_fuel_times", "generator_running_states", "consumer_powered_states",
		]:
			if island.has(key):
				island[key] = _shifted_keys(island[key], origin)
		if island.has("buildings"):
			island.buildings = _shifted_buildings(island.buildings, origin)

		# Boats from before the shared world were kept per island; they live in the world now.
		var island_boats: Dictionary = island.get("boats", {})
		for old_id in island_boats:
			var id := _free_boat_id(boats)
			var boat: Dictionary = island_boats[old_id]
			boat.cell = HexGridScript.shift(boat.cell, origin)
			boats[id] = boat
			if coord == world.get("current_coord", Vector2i.ZERO) and old_id == int(island.get("piloted_boat", -1)):
				world.piloted_boat = id

		# K9-DA's cell was one of its island's.
		if coord == world.get("dog_coord", WorldData.NO_COORD) and world.has("dog_cell"):
			var dog_cell: Vector2i = world.dog_cell
			world.dog_cell = GameTypes.NO_CELL if dog_cell == Vector2i(-1, -1) else HexGridScript.shift(dog_cell, origin)

		for key in ["boats", "piloted_boat", "width", "height"]:
			island.erase(key)
	world.boats = boats
	return upgraded


# Where version 1 put an island's grid: centred on its world-map slot, in axial coordinates.
static func _v1_island_origin(coord: Vector2i, width: int, height: int) -> Vector2i:
	var slot := Vector2i(coord.x * 50 - coord.y * 4, coord.y * 58)
	return slot - HexGridScript.offset_to_axial(Vector2i(width / 2, height / 2))


# These keep the entries' order, which matters for buildings: power goes to the first built.
static func _shifted_keys(by_cell: Dictionary, origin: Vector2i) -> Dictionary:
	var result := {}
	for cell in by_cell:
		result[HexGridScript.shift(cell, origin)] = by_cell[cell]
	return result


static func _shifted_buildings(buildings: Dictionary, origin: Vector2i) -> Dictionary:
	var result := {}
	for anchor_cell in buildings:
		var building: Dictionary = buildings[anchor_cell]
		if building.has("cells"):
			var cells := []
			for cell in building.cells:
				cells.append(HexGridScript.shift(cell, origin))
			building.cells = cells
		result[HexGridScript.shift(anchor_cell, origin)] = building
	return result


static func _free_boat_id(boats: Dictionary) -> int:
	var id := 0
	while boats.has(id):
		id += 1
	return id
