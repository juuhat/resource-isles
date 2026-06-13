class_name IslandRenderer
extends Node2D

const WATER_TEXTURE := preload("res://assets/tiles/water.png")
const SAND_TEXTURE := preload("res://assets/tiles/sand.png")
const GRASS_TEXTURE := preload("res://assets/tiles/grass.png")
const CRATE_TEXTURE := preload("res://assets/buildings/crate.png")

@export var cell_size := Vector2(128.0, 128.0)
@export var show_grid := false
@export var grid_line_width := 1.0

var island: IslandData
var resource_node_database: ResourceNodeDatabase
var hovered_cell := Vector2i(-1, -1)
var placement_preview_enabled := false
var placement_building_type := IslandData.BuildingType.CRATE


func render(new_island: IslandData) -> void:
	island = new_island
	queue_redraw()


func setup(new_resource_node_database: ResourceNodeDatabase) -> void:
	resource_node_database = new_resource_node_database


func _draw() -> void:
	if island == null:
		return

	_draw_terrain()
	_draw_sorted_objects()

	if show_grid:
		_draw_grid()

	_draw_hover()
	_draw_placement_preview()


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * cell_size.x, cell.y * cell_size.y)


func world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / cell_size.x),
		floori(world_position.y / cell_size.y)
	)


func set_hovered_world_position(world_position: Vector2) -> void:
	var cell := world_to_cell(world_position)

	if island == null or not island.is_in_bounds(cell):
		cell = Vector2i(-1, -1)

	if hovered_cell == cell:
		return

	hovered_cell = cell
	queue_redraw()


func set_placement_preview(enabled: bool, building_type: int = IslandData.BuildingType.CRATE) -> void:
	placement_preview_enabled = enabled
	placement_building_type = building_type
	queue_redraw()


func try_place_hovered_building(building_type: int = IslandData.BuildingType.CRATE) -> bool:
	if island == null or hovered_cell == Vector2i(-1, -1):
		return false

	var placed := island.place_building(hovered_cell, building_type)
	if placed:
		queue_redraw()

	return placed


func get_hovered_building_type() -> int:
	if island == null or hovered_cell == Vector2i(-1, -1):
		return -1

	return island.get_building_type(hovered_cell)


func get_hovered_resource_node_type() -> int:
	if island == null or hovered_cell == Vector2i(-1, -1):
		return -1

	return island.get_resource_node_type(hovered_cell)


func _draw_terrain() -> void:
	for y in range(island.height):
		for x in range(island.width):
			var cell := Vector2i(x, y)
			var terrain_type := island.get_terrain(cell)

			var pos := cell_to_world(cell)
			var rect := Rect2(pos, cell_size)
			draw_texture_rect(_texture_for_terrain(terrain_type), rect, false)


func _draw_grid() -> void:
	var color := Color(0.0, 0.0, 0.0, 0.28)
	var grid_size := Vector2(island.width * cell_size.x, island.height * cell_size.y)
	var line_width := _screen_pixels_to_world(grid_line_width)
	var half_width := line_width * 0.5

	for x in range(island.width + 1):
		var line_x := x * cell_size.x
		draw_rect(
			Rect2(Vector2(line_x - half_width, 0.0), Vector2(line_width, grid_size.y)),
			color,
			true
		)

	for y in range(island.height + 1):
		var line_y := y * cell_size.y
		draw_rect(
			Rect2(Vector2(0.0, line_y - half_width), Vector2(grid_size.x, line_width)),
			color,
			true
		)


func _draw_sorted_objects() -> void:
	var draw_items: Array[Dictionary] = []

	for cell in island.resources.keys():
		draw_items.append({
			"kind": "resource",
			"cell": cell,
			"type": island.resources[cell],
		})

	for cell in island.buildings.keys():
		draw_items.append({
			"kind": "building",
			"cell": cell,
			"type": island.buildings[cell],
		})

	draw_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_cell: Vector2i = a["cell"]
		var b_cell: Vector2i = b["cell"]

		if a_cell.y == b_cell.y:
			return a_cell.x < b_cell.x

		return a_cell.y < b_cell.y
	)

	for item in draw_items:
		var kind: String = item["kind"]
		var cell: Vector2i = item["cell"]
		var object_type: int = item["type"]

		if kind == "resource":
			_draw_resource(cell, object_type)
		else:
			_draw_building(cell, object_type)


func _draw_resource(cell: Vector2i, resource_node_type: int) -> void:
	var definition := resource_node_database.get_definition(resource_node_type)
	if definition == null or definition.texture == null:
		return

	var rect := Rect2(
		cell_to_world(cell) + Vector2(
			definition.visual_offset_tiles.x * cell_size.x,
			definition.visual_offset_tiles.y * cell_size.y
		),
		Vector2(
			definition.visual_size_tiles.x * cell_size.x,
			definition.visual_size_tiles.y * cell_size.y
		)
	)
	draw_texture_rect(definition.texture, rect, false)


func _draw_building(cell: Vector2i, building_type: int) -> void:
	var rect := Rect2(cell_to_world(cell), cell_size)
	draw_texture_rect(_texture_for_building(building_type), rect, false)


func _draw_hover() -> void:
	if hovered_cell == Vector2i(-1, -1):
		return

	var rect := Rect2(cell_to_world(hovered_cell), cell_size)
	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.16), true)


func _draw_placement_preview() -> void:
	if not placement_preview_enabled or hovered_cell == Vector2i(-1, -1):
		return

	var rect := Rect2(cell_to_world(hovered_cell), cell_size)
	var can_place := island.can_place_building(hovered_cell)
	var tint := Color(1.0, 1.0, 1.0, 0.55) if can_place else Color(1.0, 0.2, 0.2, 0.45)

	draw_texture_rect(_texture_for_building(placement_building_type), rect, false, tint)


func _screen_pixels_to_world(screen_pixels: float) -> float:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return screen_pixels

	return screen_pixels / camera.zoom.x


func _texture_for_terrain(terrain_type: int) -> Texture2D:
	match terrain_type:
		IslandData.Terrain.GRASS:
			return GRASS_TEXTURE
		IslandData.Terrain.SAND:
			return SAND_TEXTURE
		_:
			return WATER_TEXTURE


func _texture_for_building(building_type: int) -> Texture2D:
	match building_type:
		IslandData.BuildingType.CRATE:
			return CRATE_TEXTURE
		_:
			return CRATE_TEXTURE
