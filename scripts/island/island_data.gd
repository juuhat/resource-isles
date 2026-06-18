class_name IslandData
extends RefCounted

const HexGridScript := preload("res://scripts/island/hex_grid.gd")

var island_name: String = ""
var inventory := Inventory.new()
var width: int
var height: int
var terrain: Dictionary = {}
var resources: Dictionary = {}
var items: Dictionary = {}
var scavenged_cells: Dictionary = {}
var buildings: Dictionary = {}
var building_next_production_times: Dictionary = {}
var building_next_fuel_times: Dictionary = {}
var generator_running_states: Dictionary = {}
var consumer_powered_states: Dictionary = {}


func _init(new_width: int = 0, new_height: int = 0) -> void:
	width = new_width
	height = new_height


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func set_terrain(cell: Vector2i, terrain_type: int) -> void:
	if is_in_bounds(cell):
		terrain[cell] = terrain_type


func get_terrain(cell: Vector2i) -> int:
	return terrain.get(cell, GameTypes.Terrain.WATER)


func can_place_building(
	cell: Vector2i,
	footprint_cells: Array[Vector2i],
	required_terrain: int
) -> bool:
	for footprint_cell in footprint_cells:
		if (
			not is_in_bounds(footprint_cell)
			or get_terrain(footprint_cell) != required_terrain
			or resources.has(footprint_cell)
			or _has_building_on_cell(footprint_cell)
		):
			return false

	return true


func place_building(
	cell: Vector2i,
	building_type: int,
	footprint_cells: Array[Vector2i],
	required_terrain: int
) -> bool:
	if not can_place_building(cell, footprint_cells, required_terrain):
		return false

	buildings[cell] = {type = building_type, cells = footprint_cells}
	return true


func has_building(cell: Vector2i) -> bool:
	return _has_building_on_cell(cell)


func get_building_type(cell: Vector2i) -> int:
	var anchor_cell := get_building_anchor_cell(cell)
	if anchor_cell == Vector2i(-1, -1):
		return -1

	return buildings[anchor_cell].type


func get_building_anchor_cell(cell: Vector2i) -> Vector2i:
	for anchor_cell in buildings.keys():
		if (buildings[anchor_cell].cells as Array).has(cell):
			return anchor_cell

	return Vector2i(-1, -1)


func get_building_footprint_cells(anchor_cell: Vector2i) -> Array[Vector2i]:
	if not buildings.has(anchor_cell):
		return []

	return buildings[anchor_cell].cells


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
		is_in_bounds(cell)
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
	if not is_in_bounds(cell) or items.has(cell):
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
		width = width,
		height = height,
		terrain = terrain.duplicate(),
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
	var island := IslandData.new(int(data.get("width", 0)), int(data.get("height", 0)))
	island.island_name = data.get("island_name", "")
	island.terrain = (data.get("terrain", {}) as Dictionary).duplicate()
	island.resources = (data.get("resources", {}) as Dictionary).duplicate()
	island.items = (data.get("items", {}) as Dictionary).duplicate()
	island.scavenged_cells = (data.get("scavenged_cells", {}) as Dictionary).duplicate()
	island.buildings = _buildings_from_dict(data.get("buildings", {}))
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
		}
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
		result[anchor_cell] = {type = int(saved.type), cells = cells}
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
		GameTypes.ResourceNodeType.COAL:
			# Quarried/mined deposits sit on rock (the STONE biome, see docs/island-generation.md).
			return GameTypes.Terrain.STONE
		_:
			return GameTypes.Terrain.GRASS


func _has_building_on_cell(cell: Vector2i) -> bool:
	return get_building_anchor_cell(cell) != Vector2i(-1, -1)
