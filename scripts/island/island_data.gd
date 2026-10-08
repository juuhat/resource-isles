class_name IslandData
extends RefCounted

# One island: its terrain, resources, items and buildings, keyed by cell. Cells are on the world
# lattice shared by every island and the sea between them (see WorldNavigation), so a cell means
# the same tile everywhere. The island's own cells are exactly the keys of `terrain`, water
# included; see has_cell.

const HexGridScript := preload("res://scripts/island/hex_grid.gd")
# The highest elevation level a land cell can have (see get_elevation).
const MAX_ELEVATION := 6

var island_name: String = ""
# The island's id on the world map (WorldMap), which ties a saved island to its entry there.
var map_id: StringName = &""
# Whether the robot has approached close enough to reveal this island. The saved key remains
# `visited` for compatibility; it gates camera inspection and the one-time discovery stat.
var visited := false
var sighted := false
var inventory := Inventory.new()
var terrain: Dictionary = {}
# Land cell -> elevation level, where it isn't its ground's usual one (see get_elevation).
var elevation: Dictionary = {}
var resources: Dictionary = {}
var items: Dictionary = {}
var scavenged_cells: Dictionary = {}
# Anchor cell -> building entry {type, cells, rotation, [build_progress], [boat_launched],
# [recipe]}. Add, remove or replace entries only through place_building / remove_building /
# set_building_record / detach_building / set_buildings, which keep _anchor_by_cell and
# building_revision in step; editing the fields of an existing entry (boat_launched, recipe) is fine.
var buildings: Dictionary = {}
# Every footprint cell -> its building's anchor, so a cell lookup doesn't scan every building.
var _anchor_by_cell: Dictionary = {}
# Bumped whenever a building is added, removed or finished, so data derived from the buildings
# (HexPathfinder.deck_cells) knows to recompute.
var building_revision := 0
# HexPathfinder.deck_cells' result, valid while deck_cells_revision == building_revision.
var deck_cells_cache: Dictionary = {}
var deck_cells_revision := -1
var building_next_production_times: Dictionary = {}
var building_next_fuel_times: Dictionary = {}
var generator_running_states: Dictionary = {}
var consumer_powered_states: Dictionary = {}


# A new island covers a width x height block of cells from (0, 0), all water: the generator's
# canvas (and a test island's). shift() then moves it to its place in the world.
func _init(width: int = 0, height: int = 0) -> void:
	for y in range(height):
		for x in range(width):
			terrain[Vector2i(x, y)] = GameTypes.Terrain.WATER


# Whether the cell is part of this island (water included).
func has_cell(cell: Vector2i) -> bool:
	return terrain.has(cell)


func set_terrain(cell: Vector2i, terrain_type: int) -> void:
	if has_cell(cell):
		terrain[cell] = terrain_type


func get_terrain(cell: Vector2i) -> int:
	return terrain.get(cell, GameTypes.Terrain.WATER)


# How high a land cell stands, in levels from 0 (a beach) to MAX_ELEVATION: its own level if it
# has one (an island design's [heights]), otherwise its ground's usual level. The renderer turns
# levels into heights (IslandRenderer.elevation_top_y). Water has no level.
func get_elevation(cell: Vector2i) -> int:
	return elevation.get(cell, default_elevation(get_terrain(cell)))


func set_elevation(cell: Vector2i, level: int) -> void:
	if has_cell(cell) and not GameTypes.is_water(get_terrain(cell)):
		elevation[cell] = clampi(level, 0, MAX_ELEVATION)


# Each ground's usual level: the heights every island had before cells got their own.
static func default_elevation(terrain_type: int) -> int:
	match terrain_type:
		GameTypes.Terrain.GRASS:
			return 1
		GameTypes.Terrain.STONE:
			return 2
		_:
			return 0


# cell_terrains optionally overrides required_terrains per footprint cell (same order); an
# empty entry, or none, falls back to required_terrains. A building stands level: every land cell
# of its footprint is at one elevation (water cells, like a dock's pier, have none).
func can_place_building(
	cell: Vector2i,
	footprint_cells: Array[Vector2i],
	required_terrains: Array[int],
	cell_terrains: Array = []
) -> bool:
	var level := -1
	for index in footprint_cells.size():
		var footprint_cell := footprint_cells[index]
		var allowed: Array = required_terrains
		if index < cell_terrains.size() and not (cell_terrains[index] as Array).is_empty():
			allowed = cell_terrains[index]
		if (
			not has_cell(footprint_cell)
			or not allowed.has(get_terrain(footprint_cell))
			or resources.has(footprint_cell)
			or _has_building_on_cell(footprint_cell)
		):
			return false
		if not GameTypes.is_water(get_terrain(footprint_cell)):
			if level == -1:
				level = get_elevation(footprint_cell)
			elif get_elevation(footprint_cell) != level:
				return false

	return true


# rotation is the footprint's turn in 60-degree steps (see HexGrid.footprint_cells), kept so the
# renderer can turn the model to match and a moved building can be put back as it was.
# under_construction places a blueprint: the footprint is reserved, but the building does nothing
# until the robot finishes building it (see is_under_construction).
func place_building(
	cell: Vector2i,
	building_type: int,
	footprint_cells: Array[Vector2i],
	required_terrains: Array[int],
	rotation: int = 0,
	cell_terrains: Array = [],
	under_construction := false
) -> bool:
	if not can_place_building(cell, footprint_cells, required_terrains, cell_terrains):
		return false

	var building := {type = building_type, cells = footprint_cells, rotation = rotation}
	if under_construction:
		building.build_progress = 0.0
	set_building_record(cell, building)
	return true


func remove_building(anchor_cell: Vector2i) -> bool:
	if detach_building(anchor_cell).is_empty():
		return false

	# Drop every per-building bit of state keyed on this anchor so a future building on
	# the same cell starts fresh rather than inheriting stale timers / power flags.
	building_next_production_times.erase(anchor_cell)
	building_next_fuel_times.erase(anchor_cell)
	generator_running_states.erase(anchor_cell)
	consumer_powered_states.erase(anchor_cell)
	return true


# Puts a building entry on the map as is, replacing any entry already at anchor_cell. No placement
# rules are checked: for restoring an entry taken off with detach_building, or writing an old-save
# shape in a check.
func set_building_record(anchor_cell: Vector2i, building: Dictionary) -> void:
	_unindex_building(anchor_cell)
	buildings[anchor_cell] = building
	for cell in building.get("cells", []):
		_anchor_by_cell[cell] = anchor_cell
	building_revision += 1


# Takes a building's entry off the map and returns it ({} if none), keeping its timers and power
# state, unlike remove_building: for code that puts it straight back (footprint migration).
func detach_building(anchor_cell: Vector2i) -> Dictionary:
	if not buildings.has(anchor_cell):
		return {}

	var building: Dictionary = buildings[anchor_cell]
	_unindex_building(anchor_cell)
	buildings.erase(anchor_cell)
	building_revision += 1
	return building


# Replaces every building at once (loading a save).
func set_buildings(new_buildings: Dictionary) -> void:
	buildings = {}
	_anchor_by_cell.clear()
	for anchor_cell in new_buildings:
		set_building_record(anchor_cell, new_buildings[anchor_cell])


func _unindex_building(anchor_cell: Vector2i) -> void:
	if not buildings.has(anchor_cell):
		return
	for cell in buildings[anchor_cell].get("cells", []):
		# Leave a cell another building has since claimed.
		if _anchor_by_cell.get(cell, GameTypes.NO_CELL) == anchor_cell:
			_anchor_by_cell.erase(cell)


func has_building(cell: Vector2i) -> bool:
	return _has_building_on_cell(cell)


func get_building_type(cell: Vector2i) -> int:
	var anchor_cell := get_building_anchor_cell(cell)
	if anchor_cell == GameTypes.NO_CELL:
		return -1

	return buildings[anchor_cell].type


func get_building_anchor_cell(cell: Vector2i) -> Vector2i:
	return _anchor_by_cell.get(cell, GameTypes.NO_CELL)


func get_building_footprint_cells(anchor_cell: Vector2i) -> Array[Vector2i]:
	if not buildings.has(anchor_cell):
		return []

	return buildings[anchor_cell].cells


func get_building_rotation(anchor_cell: Vector2i) -> int:
	if not buildings.has(anchor_cell):
		return 0

	return int(buildings[anchor_cell].get("rotation", 0))


# --- Construction ---
# A blueprint is a building entry carrying build_progress (0..1). It holds its footprint and has
# its materials already paid, but produces, burns and draws nothing, and only counts as built once
# complete_construction drops the key. Entries without one (every older save) are finished.

# True for a blueprint, given any of its cells.
func is_under_construction(cell: Vector2i) -> bool:
	var anchor_cell := get_building_anchor_cell(cell)
	return anchor_cell != GameTypes.NO_CELL and buildings[anchor_cell].has("build_progress")


# True for a finished building, given any of its cells.
func is_building_complete(cell: Vector2i) -> bool:
	return has_building(cell) and not is_under_construction(cell)


func get_build_progress(anchor_cell: Vector2i) -> float:
	if not buildings.has(anchor_cell):
		return 0.0
	return float(buildings[anchor_cell].get("build_progress", 1.0))


func set_build_progress(anchor_cell: Vector2i, progress: float) -> void:
	if buildings.has(anchor_cell) and buildings[anchor_cell].has("build_progress"):
		buildings[anchor_cell].build_progress = clampf(progress, 0.0, 1.0)


func complete_construction(anchor_cell: Vector2i) -> void:
	if buildings.has(anchor_cell) and buildings[anchor_cell].erase("build_progress"):
		building_revision += 1


# The output of the recipe a processor with several (the furnace) is set to, or -1 for none. See
# BuildingManager.get_recipe.
func get_recipe(anchor_cell: Vector2i) -> int:
	if not buildings.has(anchor_cell):
		return -1
	return int(buildings[anchor_cell].get("recipe", -1))


func set_recipe(anchor_cell: Vector2i, output: int) -> void:
	if buildings.has(anchor_cell):
		buildings[anchor_cell].recipe = output


# Anchors of every blueprint on the island.
func construction_sites() -> Array[Vector2i]:
	var sites: Array[Vector2i] = []
	for anchor_cell in buildings:
		if buildings[anchor_cell].has("build_progress"):
			sites.append(anchor_cell)
	return sites


func has_production_time(anchor_cell: Vector2i) -> bool:
	return building_next_production_times.has(anchor_cell)


func get_next_production_time(anchor_cell: Vector2i) -> float:
	return building_next_production_times.get(anchor_cell, 0.0)


func set_next_production_time(anchor_cell: Vector2i, next_time_seconds: float) -> void:
	building_next_production_times[anchor_cell] = next_time_seconds


func has_fuel_time(anchor_cell: Vector2i) -> bool:
	return building_next_fuel_times.has(anchor_cell)


func get_next_fuel_time(anchor_cell: Vector2i) -> float:
	return building_next_fuel_times.get(anchor_cell, 0.0)


func set_next_fuel_time(anchor_cell: Vector2i, next_time_seconds: float) -> void:
	building_next_fuel_times[anchor_cell] = next_time_seconds


func is_generator_running(anchor_cell: Vector2i) -> bool:
	return generator_running_states.get(anchor_cell, false)


func set_generator_running(anchor_cell: Vector2i, running: bool) -> void:
	generator_running_states[anchor_cell] = running


func is_consumer_powered(anchor_cell: Vector2i) -> bool:
	return consumer_powered_states.get(anchor_cell, false)


func set_consumer_powered(anchor_cell: Vector2i, powered: bool) -> void:
	consumer_powered_states[anchor_cell] = powered


func can_place_resource(cell: Vector2i, resource_node_type: int = GameTypes.ResourceNodeType.TREE) -> bool:
	return (
		has_cell(cell)
		and get_terrain(cell) == _terrain_for_resource(resource_node_type)
		and not resources.has(cell)
		and not _has_building_on_cell(cell)
	)


func place_resource(cell: Vector2i, resource_node_type: int) -> bool:
	if not can_place_resource(cell, resource_node_type):
		return false

	resources[cell] = resource_node_type
	return true


func has_resource(cell: Vector2i) -> bool:
	return resources.has(cell)


func can_scavenge(cell: Vector2i) -> bool:
	return has_resource(cell) and not scavenged_cells.has(cell)


func mark_scavenged(cell: Vector2i) -> void:
	scavenged_cells[cell] = true


func get_resource_node_type(cell: Vector2i) -> int:
	return resources.get(cell, -1)


# Loose ground pickups (GameTypes.ItemType). The robot collects one by walking onto its
# cell; see main.gd's entered-cell handler.
func place_item(cell: Vector2i, item_type: int) -> bool:
	if not has_cell(cell) or items.has(cell):
		return false

	items[cell] = item_type
	return true


func has_item(cell: Vector2i) -> bool:
	return items.has(cell)


func get_item_type(cell: Vector2i) -> int:
	return items.get(cell, -1)


# Removes the item on a cell and returns its type, or -1 if there was none.
func take_item(cell: Vector2i) -> int:
	if not items.has(cell):
		return -1

	var item_type: int = items[cell]
	items.erase(cell)
	return item_type


# Moves the whole island by an axial offset (see HexGrid.shift), keeping the order of every
# cell-keyed collection and each building's footprint. Used once, to put a freshly generated
# island (built on cells from (0, 0)) at its place in the world.
func shift(axial_offset: Vector2i) -> void:
	terrain = _shifted_keys(terrain, axial_offset)
	elevation = _shifted_keys(elevation, axial_offset)
	resources = _shifted_keys(resources, axial_offset)
	items = _shifted_keys(items, axial_offset)
	scavenged_cells = _shifted_keys(scavenged_cells, axial_offset)
	building_next_production_times = _shifted_keys(building_next_production_times, axial_offset)
	building_next_fuel_times = _shifted_keys(building_next_fuel_times, axial_offset)
	generator_running_states = _shifted_keys(generator_running_states, axial_offset)
	consumer_powered_states = _shifted_keys(consumer_powered_states, axial_offset)
	var shifted_buildings := {}
	for anchor_cell in buildings:
		var building: Dictionary = buildings[anchor_cell].duplicate()
		var cells: Array[Vector2i] = []
		for cell in building.cells:
			cells.append(HexGridScript.shift(cell, axial_offset))
		building.cells = cells
		shifted_buildings[HexGridScript.shift(anchor_cell, axial_offset)] = building
	set_buildings(shifted_buildings)


static func _shifted_keys(by_cell: Dictionary, axial_offset: Vector2i) -> Dictionary:
	var result := {}
	for cell in by_cell:
		result[HexGridScript.shift(cell, axial_offset)] = by_cell[cell]
	return result


# --- Save/load ---
# Serialize the full mutable island state to plain Variant-native data (ints, floats,
# Strings, bools, Vector2i, and nested Dictionaries/Arrays) so SaveManager can write it with
# FileAccess.store_var. Nothing here references the renderer or managers — views are rebuilt
# from this data when the island is re-entered.
#
# `reference_time` is the gameplay clock (Time.get_ticks_msec()/1000.0) at save time. The
# production/fuel "next fire" times are absolute ticks-since-engine-start, which reset to ~0
# every launch, so they are stored RELATIVE to now (seconds remaining) and rebased onto the
# fresh clock on load — otherwise every timer would be wildly overdue or far in the future.

func to_dict(reference_time: float) -> Dictionary:
	return {
		island_name = island_name,
		map_id = map_id,
		visited = visited,
		sighted = sighted,
		terrain = terrain.duplicate(),
		elevation = elevation.duplicate(),
		resources = resources.duplicate(),
		items = items.duplicate(),
		scavenged_cells = scavenged_cells.duplicate(),
		buildings = _buildings_to_dict(),
		next_production_times = _to_relative_times(building_next_production_times, reference_time),
		next_fuel_times = _to_relative_times(building_next_fuel_times, reference_time),
		generator_running_states = generator_running_states.duplicate(),
		consumer_powered_states = consumer_powered_states.duplicate(),
		inventory = inventory.to_dict(),
	}


static func from_dict(data: Dictionary, reference_time: float) -> IslandData:
	var island := IslandData.new()
	island.island_name = data.get("island_name", "")
	island.map_id = StringName(data.get("map_id", ""))
	# Saves from before the shared world only ever held islands the robot had landed on.
	island.visited = bool(data.get("visited", true))
	island.sighted = bool(data.get("sighted", island.visited))
	island.terrain = (data.get("terrain", {}) as Dictionary).duplicate()
	# Saves from before cells had their own elevation stand at their grounds' usual levels.
	island.elevation = (data.get("elevation", {}) as Dictionary).duplicate()
	island.resources = (data.get("resources", {}) as Dictionary).duplicate()
	island.items = (data.get("items", {}) as Dictionary).duplicate()
	island.scavenged_cells = (data.get("scavenged_cells", {}) as Dictionary).duplicate()
	island.set_buildings(_buildings_from_dict(data.get("buildings", {})))
	island.building_next_production_times = _to_absolute_times(
		data.get("next_production_times", {}), reference_time
	)
	island.building_next_fuel_times = _to_absolute_times(
		data.get("next_fuel_times", {}), reference_time
	)
	island.generator_running_states = (data.get("generator_running_states", {}) as Dictionary).duplicate()
	island.consumer_powered_states = (data.get("consumer_powered_states", {}) as Dictionary).duplicate()
	island.inventory = Inventory.from_dict(data.get("inventory", {}))
	return island


func _buildings_to_dict() -> Dictionary:
	var result := {}
	for anchor_cell in buildings:
		var building: Dictionary = buildings[anchor_cell]
		result[anchor_cell] = {
			type = int(building.type),
			cells = (building.cells as Array).duplicate(),
			rotation = int(building.get("rotation", 0)),
		}
		if building.has("build_progress"):
			result[anchor_cell].build_progress = float(building.build_progress)
		if building.get("boat_launched", false):
			result[anchor_cell].boat_launched = true
		if building.has("recipe"):
			result[anchor_cell].recipe = int(building.recipe)
	return result


# Rebuild the `cells` footprint as a typed Array[Vector2i] — store_var round-trips it as an
# untyped Array, but place_building/get_building_footprint_cells expect the typed form.
static func _buildings_from_dict(saved_buildings: Dictionary) -> Dictionary:
	var result := {}
	for anchor_cell in saved_buildings:
		var saved: Dictionary = saved_buildings[anchor_cell]
		var cells: Array[Vector2i] = []
		for cell in saved.get("cells", []):
			cells.append(cell)
		result[anchor_cell] = {type = int(saved.type), cells = cells, rotation = int(saved.get("rotation", 0))}
		if saved.has("build_progress"):
			result[anchor_cell].build_progress = float(saved.build_progress)
		if saved.get("boat_launched", false):
			result[anchor_cell].boat_launched = true
		if saved.has("recipe"):
			result[anchor_cell].recipe = int(saved.recipe)
	return result


static func _to_relative_times(times: Dictionary, reference_time: float) -> Dictionary:
	var result := {}
	for cell in times:
		result[cell] = maxf(0.0, float(times[cell]) - reference_time)
	return result


static func _to_absolute_times(times: Dictionary, reference_time: float) -> Dictionary:
	var result := {}
	for cell in times:
		result[cell] = reference_time + float(times[cell])
	return result


func _terrain_for_resource(resource_node_type: int) -> int:
	match resource_node_type:
		GameTypes.ResourceNodeType.STONE, \
		GameTypes.ResourceNodeType.IRON_ORE, \
		GameTypes.ResourceNodeType.COAL, \
		GameTypes.ResourceNodeType.COPPER_ORE:
			# Quarried/mined deposits sit on rock (the STONE biome, see docs/island-generation.md).
			return GameTypes.Terrain.STONE
		_:
			return GameTypes.Terrain.GRASS


func _has_building_on_cell(cell: Vector2i) -> bool:
	return _anchor_by_cell.has(cell)
