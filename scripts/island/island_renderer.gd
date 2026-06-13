class_name IslandRenderer
extends Node2D

const WATER_TEXTURE := preload("res://assets/tiles/water.png")
const SAND_TEXTURE := preload("res://assets/tiles/sand.png")
const GRASS_TEXTURE := preload("res://assets/tiles/grass.png")
const CRATE_TEXTURE := preload("res://assets/buildings/crate.png")
const SHORE_UP := 1
const SHORE_DOWN := 2
const SHORE_LEFT := 4
const SHORE_RIGHT := 8

@export var cell_size := Vector2(128.0, 128.0)
@export var show_grid := false
@export var grid_line_width := 1.0
@export var animate_water := false

var island: IslandData
var resource_node_database: ResourceNodeDatabase
var hovered_cell := Vector2i(-1, -1)
var placement_preview_enabled := false
var placement_building_type := IslandData.BuildingType.CRATE
var water_time := 0.0
var water_gradient_texture: ImageTexture
var land_tiles: Array[Dictionary] = []
var water_tiles: Array[Rect2] = []
var water_surface_tiles: Array[Dictionary] = []


func _process(delta: float) -> void:
	if not animate_water:
		return

	water_time += delta
	queue_redraw()


func render(new_island: IslandData) -> void:
	island = new_island
	water_gradient_texture = null
	_rebuild_terrain_cache()
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
	_draw_water_background()

	for rect in water_tiles:
		_draw_water_tile(rect)

	for tile in land_tiles:
		var texture: Texture2D = tile["texture"]
		var rect: Rect2 = tile["rect"]
		draw_texture_rect(texture, rect, false)

	_draw_water_surface_details()


func _draw_water_tile(rect: Rect2) -> void:
	draw_texture_rect(WATER_TEXTURE, rect, false, Color(1.0, 1.0, 1.0, 0.20))


func _rebuild_terrain_cache() -> void:
	land_tiles.clear()
	water_tiles.clear()
	water_surface_tiles.clear()

	if island == null:
		return

	for y in range(island.height):
		for x in range(island.width):
			var cell := Vector2i(x, y)
			var terrain_type := island.get_terrain(cell)
			var rect := Rect2(cell_to_world(cell), cell_size)

			if terrain_type == IslandData.Terrain.WATER:
				water_tiles.append(rect)
				water_surface_tiles.append({
					"cell": cell,
					"rect": rect,
					"depth": _water_depth_factor(cell),
					"shore_mask": _shore_mask_for_water_cell(cell),
					"draw_shimmer": (x + y) % 3 == 0,
				})
			else:
				land_tiles.append({
					"texture": _texture_for_terrain(terrain_type),
					"rect": rect,
				})


func _draw_water_background() -> void:
	if water_gradient_texture == null:
		water_gradient_texture = _create_water_gradient_texture()

	var island_size := Vector2(island.width * cell_size.x, island.height * cell_size.y)
	draw_texture_rect(water_gradient_texture, Rect2(Vector2.ZERO, island_size), false)


func _create_water_gradient_texture() -> ImageTexture:
	var texture_width := 256
	var texture_height := maxi(1, roundi(texture_width * float(island.height) / float(island.width)))
	var image := Image.create(texture_width, texture_height, false, Image.FORMAT_RGBA8)
	var shallow_color := Color(0.24, 0.62, 0.75, 1.0)
	var deep_color := Color(0.04, 0.24, 0.48, 1.0)
	var shallow_buffer_tiles := 3.0
	var max_depth_tiles := 10.0
	var land_rects := _get_land_rects_in_tile_space()

	for y in range(texture_height):
		for x in range(texture_width):
			var point := Vector2(
				(float(x) + 0.5) / float(texture_width) * float(island.width),
				(float(y) + 0.5) / float(texture_height) * float(island.height)
			)
			var distance := _distance_to_nearest_land(point, land_rects)
			var gradient := clampf(
				(distance - shallow_buffer_tiles) / max_depth_tiles,
				0.0,
				1.0
			)
			gradient = gradient * gradient * (3.0 - 2.0 * gradient)
			image.set_pixel(x, y, shallow_color.lerp(deep_color, gradient))

	return ImageTexture.create_from_image(image)


func _get_land_rects_in_tile_space() -> Array[Rect2]:
	var land_rects: Array[Rect2] = []

	for y in range(island.height):
		for x in range(island.width):
			var cell := Vector2i(x, y)
			if _is_land(cell):
				land_rects.append(Rect2(Vector2(x, y), Vector2.ONE))

	return land_rects


func _distance_to_nearest_land(point: Vector2, land_rects: Array[Rect2]) -> float:
	if land_rects.is_empty():
		return 0.0

	var nearest := INF
	for rect in land_rects:
		var distance := _distance_to_rect(point, rect)
		if distance < nearest:
			nearest = distance

	return nearest


func _distance_to_rect(point: Vector2, rect: Rect2) -> float:
	var dx := maxf(maxf(rect.position.x - point.x, 0.0), point.x - rect.end.x)
	var dy := maxf(maxf(rect.position.y - point.y, 0.0), point.y - rect.end.y)
	return Vector2(dx, dy).length()


func _draw_water_surface_details() -> void:
	for tile in water_surface_tiles:
		var cell: Vector2i = tile["cell"]
		var depth: float = tile["depth"]
		var rect: Rect2 = tile["rect"]

		if tile["draw_shimmer"]:
			_draw_water_shimmer(cell, depth)

		var shore_mask: int = tile["shore_mask"]
		if shore_mask != 0:
			_draw_shoreline_foam(rect, cell, shore_mask)


func _draw_water_shimmer(cell: Vector2i, depth: float) -> void:
	if depth < 0.18:
		return

	var pos := cell_to_world(cell)
	var phase := (cell.x * 0.77) + (cell.y * 1.23) + water_time * 2.1
	var alpha := (sin(phase) * 0.5 + 0.5) * 0.11
	var line_width := _screen_pixels_to_world(0.5)
	var shimmer_color := Color(0.82, 1.0, 1.0, alpha)
	var wave_count := 1 + int(depth > 0.55)

	for index in range(wave_count):
		var local_phase := phase + index * 2.4
		var center := pos + Vector2(
			cell_size.x * (0.32 + 0.28 * index),
			cell_size.y * (0.42 + sin(local_phase * 0.7) * 0.13)
		)
		var length := cell_size.x * (0.18 + depth * 0.10)
		var height := cell_size.y * 0.025
		var points := PackedVector2Array([
			center + Vector2(-length, height * sin(local_phase)),
			center + Vector2(-length * 0.35, height * sin(local_phase + 1.2)),
			center + Vector2(length * 0.35, height * sin(local_phase + 2.4)),
			center + Vector2(length, height * sin(local_phase + 3.6)),
		])

		draw_polyline(points, shimmer_color, line_width, true)


func _draw_shoreline_foam(rect: Rect2, cell: Vector2i, shore_mask: int) -> void:
	var pos := rect.position
	var foam_width := minf(cell_size.x, cell_size.y) * 0.14
	var pulse := (sin(water_time * 3.0 + cell.x * 0.9 + cell.y * 0.6) * 0.5 + 0.5)
	var foam_color := Color(0.92, 1.0, 0.96, 0.30 + pulse * 0.18)

	if (shore_mask & SHORE_UP) != 0:
		draw_rect(Rect2(pos, Vector2(cell_size.x, foam_width)), foam_color, true)

	if (shore_mask & SHORE_DOWN) != 0:
		draw_rect(
			Rect2(pos + Vector2(0.0, cell_size.y - foam_width), Vector2(cell_size.x, foam_width)),
			foam_color,
			true
		)

	if (shore_mask & SHORE_LEFT) != 0:
		draw_rect(Rect2(pos, Vector2(foam_width, cell_size.y)), foam_color, true)

	if (shore_mask & SHORE_RIGHT) != 0:
		draw_rect(
			Rect2(pos + Vector2(cell_size.x - foam_width, 0.0), Vector2(foam_width, cell_size.y)),
			foam_color,
			true
		)


func _shore_mask_for_water_cell(cell: Vector2i) -> int:
	var mask := 0

	if _is_land(cell + Vector2i.UP):
		mask |= SHORE_UP

	if _is_land(cell + Vector2i.DOWN):
		mask |= SHORE_DOWN

	if _is_land(cell + Vector2i.LEFT):
		mask |= SHORE_LEFT

	if _is_land(cell + Vector2i.RIGHT):
		mask |= SHORE_RIGHT

	return mask


func _water_depth_factor(cell: Vector2i) -> float:
	var max_distance := 5

	for distance in range(1, max_distance + 1):
		for offset_x in range(-distance, distance + 1):
			var offset_y := distance - absi(offset_x)
			if _is_land(cell + Vector2i(offset_x, offset_y)):
				return float(distance - 1) / float(max_distance)

			if offset_y != 0 and _is_land(cell + Vector2i(offset_x, -offset_y)):
				return float(distance - 1) / float(max_distance)

	return 1.0


func _is_water(cell: Vector2i) -> bool:
	return island.is_in_bounds(cell) and island.get_terrain(cell) == IslandData.Terrain.WATER


func _is_land(cell: Vector2i) -> bool:
	return island.is_in_bounds(cell) and island.get_terrain(cell) != IslandData.Terrain.WATER


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
