class_name IslandData
extends RefCounted

enum Terrain {
	WATER,
	SAND,
	GRASS,
}

enum BuildingType {
	CRATE,
}

enum ResourceNodeType {
	TREE,
}

var width: int
var height: int
var terrain: Dictionary = {}
var resources: Dictionary = {}
var resource_next_extraction_times: Dictionary = {}
var buildings: Dictionary = {}


func _init(new_width: int = 0, new_height: int = 0) -> void:
	width = new_width
	height = new_height


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func set_terrain(cell: Vector2i, terrain_type: int) -> void:
	if is_in_bounds(cell):
		terrain[cell] = terrain_type


func get_terrain(cell: Vector2i) -> int:
	return terrain.get(cell, Terrain.WATER)


func can_place_building(cell: Vector2i) -> bool:
	return (
		is_in_bounds(cell)
		and get_terrain(cell) == Terrain.GRASS
		and not resources.has(cell)
		and not buildings.has(cell)
	)


func place_building(cell: Vector2i, building_type: int) -> bool:
	if not can_place_building(cell):
		return false

	buildings[cell] = building_type
	return true


func has_building(cell: Vector2i) -> bool:
	return buildings.has(cell)


func get_building_type(cell: Vector2i) -> int:
	return buildings.get(cell, -1)


func can_place_resource(cell: Vector2i) -> bool:
	return (
		is_in_bounds(cell)
		and get_terrain(cell) == Terrain.GRASS
		and not resources.has(cell)
		and not buildings.has(cell)
	)


func place_resource(cell: Vector2i, resource_node_type: int) -> bool:
	if not can_place_resource(cell):
		return false

	resources[cell] = resource_node_type
	resource_next_extraction_times[cell] = 0.0
	return true


func has_resource(cell: Vector2i) -> bool:
	return resources.has(cell)


func get_resource_node_type(cell: Vector2i) -> int:
	return resources.get(cell, -1)


func can_extract_resource(cell: Vector2i, current_time_seconds: float) -> bool:
	return has_resource(cell) and current_time_seconds >= get_next_extraction_time(cell)


func mark_resource_extracted(cell: Vector2i, next_extraction_time_seconds: float) -> void:
	if has_resource(cell):
		resource_next_extraction_times[cell] = next_extraction_time_seconds


func get_next_extraction_time(cell: Vector2i) -> float:
	return resource_next_extraction_times.get(cell, 0.0)
