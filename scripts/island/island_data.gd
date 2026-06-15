class_name IslandData
extends RefCounted

const HexGridScript := preload("res://scripts/island/hex_grid.gd")

var width: int
var height: int
var terrain: Dictionary = {}
var resources: Dictionary = {}
var scavenged_cells: Dictionary = {}
var buildings: Dictionary = {}
var building_next_production_times: Dictionary = {}


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


func _terrain_for_resource(resource_node_type: int) -> int:
	match resource_node_type:
		GameTypes.ResourceNodeType.STONE:
			return GameTypes.Terrain.STONE
		_:
			return GameTypes.Terrain.GRASS


func _has_building_on_cell(cell: Vector2i) -> bool:
	return get_building_anchor_cell(cell) != Vector2i(-1, -1)
