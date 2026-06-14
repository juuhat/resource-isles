class_name IslandRenderer
extends Node2D

const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const TILE_TEXTURE := preload("res://assets/tiles/tile.png")
const CRATE_TEXTURE := preload("res://assets/buildings/crate.png")
const DOCK_TEXTURE := preload("res://assets/buildings/dock.png")
const HUB_TEXTURE := preload("res://assets/buildings/hub.png")

const SHALLOW_WATER_COLOR := Color("#29a9ef")
const DEEP_WATER_COLOR := Color("#176fa8")
const SAND_COLOR := Color("#f2a215")
const GRASS_COLOR := Color("#9bad18")
const STONE_COLOR := Color("#8e8791")
const WATER_REDRAW_INTERVAL := 0.08
const NORTH_SHORE_WATER_DIRECTIONS := [0, 4, 5]

@export var cell_size := Vector2(128.0, 128.0)
@export var show_grid := true
@export var grid_line_width := 1.0
@export var animate_water := true

var island: IslandData
var resource_node_database: ResourceNodeDatabase
var hovered_cell := Vector2i(-1, -1)
var placement_preview_enabled := false
var placement_building_type := IslandData.BuildingType.CRATE
var placement_can_afford := true
var water_time := 0.0
var water_redraw_elapsed := 0.0
var water_gradient_texture: ImageTexture
var map_bounds := Rect2(Vector2.ZERO, Vector2.ZERO)
var land_tiles: Array[Dictionary] = []
var water_tiles: Array[Dictionary] = []
var water_surface_tiles: Array[Dictionary] = []
var grid_line_segments := PackedVector2Array()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func _process(delta: float) -> void:
	if not animate_water:
		return

	water_redraw_elapsed += delta
	if water_redraw_elapsed < WATER_REDRAW_INTERVAL:
		return

	water_time += water_redraw_elapsed
	water_redraw_elapsed = 0.0
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
	return Vector2(
		(float(cell.x) + _row_column_offset(cell.y)) * cell_size.x,
		cell.y * cell_size.y * 0.75
	)


func world_to_cell(world_position: Vector2) -> Vector2i:
	if island == null:
		return Vector2i(-1, -1)

	if not get_map_bounds().grow(maxf(cell_size.x, cell_size.y) * 0.25).has_point(world_position):
		return Vector2i(-1, -1)

	var row := roundi(world_position.y / (cell_size.y * 0.75))
	var column := roundi(world_position.x / cell_size.x - _row_column_offset(row))
	var nearest_cell := Vector2i(column, row)
	var nearest_distance := INF

	for candidate_y in range(row - 1, row + 2):
		for candidate_x in range(column - 1, column + 2):
			var cell := Vector2i(candidate_x, candidate_y)
			if not island.is_in_bounds(cell):
				continue

			var points := HexGridScript.hex_points(cell_to_world(cell), cell_size)
			if HexGridScript.point_in_polygon(world_position, points):
				return cell

			var distance := world_position.distance_squared_to(_cell_center(cell))
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_cell = cell

	return nearest_cell if island.is_in_bounds(nearest_cell) else Vector2i(-1, -1)


func get_map_bounds() -> Rect2:
	if island == null:
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	if map_bounds.size == Vector2.ZERO:
		map_bounds = _calculate_map_bounds()

	return map_bounds


func set_hovered_world_position(world_position: Vector2) -> void:
	var cell := world_to_cell(world_position)

	if island == null or not island.is_in_bounds(cell):
		cell = Vector2i(-1, -1)

	if hovered_cell == cell:
		return

	hovered_cell = cell
	queue_redraw()


func set_placement_preview(
	enabled: bool,
	building_type: int = IslandData.BuildingType.CRATE,
	can_afford: bool = true
) -> void:
	placement_preview_enabled = enabled
	placement_building_type = building_type
	placement_can_afford = can_afford
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

	for tile in water_tiles:
		_draw_water_tile(tile)

	for tile in land_tiles:
		var terrain_type: int = tile["terrain_type"]
		var rect: Rect2 = tile["rect"]
		draw_texture_rect(TILE_TEXTURE, rect, false, _color_for_terrain(terrain_type))

	_draw_water_surface_details()


func _draw_water_tile(tile: Dictionary) -> void:
	var rect: Rect2 = tile["rect"]
	var depth: float = tile["depth"]
	draw_texture_rect(TILE_TEXTURE, rect, false, _water_color_for_depth(depth))


func _rebuild_terrain_cache() -> void:
	land_tiles.clear()
	water_tiles.clear()
	water_surface_tiles.clear()
	grid_line_segments.clear()

	if island == null:
		return

	map_bounds = _calculate_map_bounds()

	for y in range(island.height):
		for x in range(island.width):
			var cell := Vector2i(x, y)
			var terrain_type := island.get_terrain(cell)
			var rect := Rect2(cell_to_world(cell), cell_size)

			if terrain_type == IslandData.Terrain.WATER:
				var depth := _water_depth_factor(cell)
				water_tiles.append({
					"rect": rect,
					"depth": depth,
				})
				water_surface_tiles.append({
					"cell": cell,
					"rect": rect,
					"depth": depth,
					"shore_mask": _shore_mask_for_water_cell(cell),
					"draw_shimmer": _cell_noise(cell, 22.0) > 0.58,
				})
			else:
				land_tiles.append({
					"terrain_type": terrain_type,
					"rect": rect,
				})

	_rebuild_grid_cache()


func _draw_water_background() -> void:
	if water_gradient_texture == null:
		water_gradient_texture = _create_water_gradient_texture()

	draw_texture_rect(water_gradient_texture, map_bounds, false)


func _create_water_gradient_texture() -> ImageTexture:
	var bounds := map_bounds
	var texture_width := 256
	var texture_height := maxi(1, roundi(texture_width * bounds.size.y / bounds.size.x))
	var image := Image.create(texture_width, texture_height, false, Image.FORMAT_RGBA8)
	var shallow_color := Color("#47aba9")
	var deep_color := Color("#468099")
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


func _calculate_map_bounds() -> Rect2:
	var bounds := Rect2(cell_to_world(Vector2i.ZERO), cell_size)

	for y in range(island.height):
		for x in range(island.width):
			bounds = bounds.merge(Rect2(cell_to_world(Vector2i(x, y)), cell_size))

	return bounds


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
	var seed := _cell_noise(cell, 0.0)
	var phase := seed * TAU + water_time * lerpf(0.45, 0.85, _cell_noise(cell, 3.7))
	var alpha := 0.025 + (sin(phase) * 0.5 + 0.5) * 0.055
	var line_width := _screen_pixels_to_world(1.0)
	var shimmer_color := Color(0.82, 1.0, 1.0, alpha)
	var wave_count := 1 + int(depth > 0.65 and seed > 0.70)

	for index in range(wave_count):
		var local_phase := phase + index * 2.4
		var x_noise := _cell_noise(cell, 8.0 + index)
		var y_noise := _cell_noise(cell, 15.0 + index)
		var center := pos + Vector2(
			cell_size.x * (0.24 + x_noise * 0.52),
			cell_size.y * (0.30 + y_noise * 0.40 + sin(local_phase * 0.55) * 0.07)
		)
		var length := cell_size.x * (0.28 + depth * 0.18 + x_noise * 0.12)
		var height := cell_size.y * (0.018 + y_noise * 0.018)
		var points := PackedVector2Array([
			center + Vector2(-length, height * sin(local_phase)),
			center + Vector2(-length * 0.35, height * sin(local_phase + 1.2)),
			center + Vector2(length * 0.35, height * sin(local_phase + 2.4)),
			center + Vector2(length, height * sin(local_phase + 3.6)),
		])

		draw_polyline(points, shimmer_color, line_width, true)


func _cell_noise(cell: Vector2i, salt: float) -> float:
	var value := sin(float(cell.x) * 12.9898 + float(cell.y) * 78.233 + salt * 37.719) * 43758.5453
	return value - floorf(value)


func _draw_shoreline_foam(rect: Rect2, cell: Vector2i, shore_mask: int) -> void:
	var foam_phase := water_time * 0.9 + cell.x * 0.9 + cell.y * 0.6
	var pulse := sin(foam_phase) * 0.5 + 0.5
	var drift := sin(foam_phase * 0.7 + 1.8) * 0.5 + 0.5
	var foam_width := minf(cell_size.x, cell_size.y) * lerpf(0.045, 0.065, pulse)
	var foam_color := Color(0.86, 0.98, 1.0, 0.0).lerp(
		Color(0.98, 0.98, 0.92, 0.0),
		drift
	)
	foam_color.a = 0.26 + pulse * 0.08

	for direction_index in range(6):
		if NORTH_SHORE_WATER_DIRECTIONS.has(direction_index):
			continue

		if (shore_mask & _shore_bit(direction_index)) != 0:
			draw_polyline(_hex_edge_points(rect.position, direction_index), foam_color, foam_width, true)


func _shore_mask_for_water_cell(cell: Vector2i) -> int:
	var mask := 0

	for direction_index in range(6):
		if _is_land(HexGridScript.neighbor(cell, direction_index)):
			mask |= _shore_bit(direction_index)

	return mask


func _water_depth_factor(cell: Vector2i) -> float:
	var max_distance := 5
	var visited := {cell: true}
	var frontier: Array[Vector2i] = [cell]

	for distance in range(1, max_distance + 1):
		var next_frontier: Array[Vector2i] = []

		for frontier_cell in frontier:
			for neighbor in HexGridScript.neighbors(frontier_cell):
				if visited.has(neighbor):
					continue

				visited[neighbor] = true
				if _is_land(neighbor):
					return float(distance - 1) / float(max_distance)

				if island.is_in_bounds(neighbor):
					next_frontier.append(neighbor)

		frontier = next_frontier

	return 1.0


func _is_water(cell: Vector2i) -> bool:
	return island.is_in_bounds(cell) and island.get_terrain(cell) == IslandData.Terrain.WATER


func _is_land(cell: Vector2i) -> bool:
	return island.is_in_bounds(cell) and island.get_terrain(cell) != IslandData.Terrain.WATER


func _draw_grid() -> void:
	var color := Color(0.0, 0.0, 0.0, 0.03)
	var line_width := _screen_pixels_to_world(grid_line_width)

	draw_multiline(grid_line_segments, color, line_width, true)


func _rebuild_grid_cache() -> void:
	for y in range(island.height):
		for x in range(island.width):
			var cell := Vector2i(x, y)
			if island.get_terrain(cell) == IslandData.Terrain.WATER and _water_depth_factor(cell) > 0.2:
				continue

			var points := HexGridScript.hex_points(cell_to_world(cell), cell_size)

			for index in range(points.size()):
				grid_line_segments.append(points[index])
				grid_line_segments.append(points[(index + 1) % points.size()])


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
			"sort_cell": _get_last_footprint_cell(cell, island.buildings[cell]),
			"type": island.buildings[cell],
		})

	draw_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_cell: Vector2i = a.get("sort_cell", a["cell"])
		var b_cell: Vector2i = b.get("sort_cell", b["cell"])

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
	var rect := _footprint_bounds(cell, building_type)
	draw_texture_rect(_texture_for_building(building_type), rect, false)


func _draw_hover() -> void:
	if hovered_cell == Vector2i(-1, -1):
		return

	draw_colored_polygon(
		HexGridScript.hex_points(cell_to_world(hovered_cell), cell_size),
		Color(1.0, 1.0, 1.0, 0.16)
	)


func _draw_placement_preview() -> void:
	if not placement_preview_enabled or hovered_cell == Vector2i(-1, -1):
		return

	var rect := _footprint_bounds(hovered_cell, placement_building_type)
	var can_place := island.can_place_building(hovered_cell, placement_building_type) and placement_can_afford
	var tint := Color(1.0, 1.0, 1.0, 0.55) if can_place else Color(1.0, 0.2, 0.2, 0.45)

	for cell in island.get_building_footprint_cells(hovered_cell, placement_building_type):
		if island.is_in_bounds(cell):
			draw_colored_polygon(HexGridScript.hex_points(cell_to_world(cell), cell_size), tint)

	draw_texture_rect(_texture_for_building(placement_building_type), rect, false, tint)


func _row_column_offset(row: int) -> float:
	return 0.5 if row % 2 != 0 else 0.0


func _cell_center(cell: Vector2i) -> Vector2:
	return cell_to_world(cell) + cell_size * 0.5


func _shore_bit(direction_index: int) -> int:
	return 1 << direction_index


func _hex_edge_points(top_left: Vector2, direction_index: int) -> PackedVector2Array:
	var points := HexGridScript.hex_points(top_left, cell_size)
	var edge_indices := [
		Vector2i(1, 2),
		Vector2i(0, 1),
		Vector2i(5, 0),
		Vector2i(4, 5),
		Vector2i(3, 4),
		Vector2i(2, 3),
	]
	var edge: Vector2i = edge_indices[posmod(direction_index, edge_indices.size())]
	return PackedVector2Array([points[edge.x], points[edge.y]])


func _footprint_bounds(cell: Vector2i, building_type: int) -> Rect2:
	var bounds := Rect2(cell_to_world(cell), cell_size)

	for footprint_cell in island.get_building_footprint_cells(cell, building_type):
		bounds = bounds.merge(Rect2(cell_to_world(footprint_cell), cell_size))

	return bounds


func _get_last_footprint_cell(cell: Vector2i, building_type: int) -> Vector2i:
	var last_cell := cell

	for footprint_cell in island.get_building_footprint_cells(cell, building_type):
		if footprint_cell.y > last_cell.y or (
			footprint_cell.y == last_cell.y
			and footprint_cell.x > last_cell.x
		):
			last_cell = footprint_cell

	return last_cell


func _screen_pixels_to_world(screen_pixels: float) -> float:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return screen_pixels

	return screen_pixels / camera.zoom.x


func _color_for_terrain(terrain_type: int) -> Color:
	match terrain_type:
		IslandData.Terrain.GRASS:
			return GRASS_COLOR
		IslandData.Terrain.SAND:
			return SAND_COLOR
		IslandData.Terrain.STONE:
			return STONE_COLOR
		_:
			return SHALLOW_WATER_COLOR


func _water_color_for_depth(depth: float) -> Color:
	return SHALLOW_WATER_COLOR if depth <= 0.2 else DEEP_WATER_COLOR


func _texture_for_building(building_type: int) -> Texture2D:
	match building_type:
		IslandData.BuildingType.CRATE:
			return CRATE_TEXTURE
		IslandData.BuildingType.DOCK:
			return DOCK_TEXTURE
		IslandData.BuildingType.HUB:
			return HUB_TEXTURE
		_:
			return CRATE_TEXTURE
