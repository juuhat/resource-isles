class_name IslandRenderer
extends Node2D

const WATER_TEXTURE := preload("res://assets/water.png")
const SAND_TEXTURE := preload("res://assets/sand.png")
const GRASS_TEXTURE := preload("res://assets/grass.png")

@export var cell_size := Vector2(128.0, 128.0)
@export var show_grid := false
@export var grid_line_width := 1.0

var island: IslandData


func render(new_island: IslandData) -> void:
	island = new_island
	queue_redraw()


func _draw() -> void:
	if island == null:
		return

	_draw_terrain()

	if show_grid:
		_draw_grid()


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * cell_size.x, cell.y * cell_size.y)


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
