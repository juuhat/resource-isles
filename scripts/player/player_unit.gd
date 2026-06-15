class_name PlayerUnit
extends Node2D

# The player-controlled robot. Holds a current hex cell and walks along a queued
# path of cells at a constant world-space speed. Emits `arrived` once the whole
# path is consumed so the caller can trigger an on-arrival action (e.g. harvesting).

signal arrived(cell: Vector2i)

const ROBOT_TEXTURE := preload("res://assets/player/player_robot_cute.png")

@export var move_speed := 320.0
@export var visual_size_tiles := Vector2(0.65, 0.65)

var renderer: IslandRenderer
var current_cell := Vector2i(-1, -1)
var selected := false

var _path: Array[Vector2i] = []
var _target_world := Vector2.ZERO
var _pending_cell := Vector2i(-1, -1)
var _moving := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	z_index = 10


func setup(new_renderer: IslandRenderer) -> void:
	renderer = new_renderer


func place_at(cell: Vector2i) -> void:
	current_cell = cell
	position = renderer.get_cell_center(cell)
	_path.clear()
	_moving = false
	visible = true
	queue_redraw()


func follow_path(path: Array[Vector2i]) -> void:
	if path.is_empty():
		return

	_path = path.duplicate()
	_advance_to_next()


func is_moving() -> bool:
	return _moving


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	queue_redraw()


func _process(delta: float) -> void:
	if not _moving:
		return

	var to_target := _target_world - position
	var distance := to_target.length()
	var step := move_speed * delta

	if distance <= step or distance == 0.0:
		position = _target_world
		current_cell = _pending_cell
		_advance_to_next()
	else:
		position += to_target / distance * step

	queue_redraw()


func _advance_to_next() -> void:
	if _path.is_empty():
		_moving = false
		arrived.emit(current_cell)
		return

	_pending_cell = _path.pop_front()
	_target_world = renderer.get_cell_center(_pending_cell)
	_moving = true


func _draw() -> void:
	if renderer == null:
		return

	var cell_size := renderer.cell_size
	var size := Vector2(visual_size_tiles.x * cell_size.x, visual_size_tiles.y * cell_size.y)

	_draw_ground_marker(cell_size)

	# Anchor the sprite so its feet rest near the cell center.
	var rect := Rect2(Vector2(-size.x * 0.5, -size.y * 0.78), size)
	draw_texture_rect(ROBOT_TEXTURE, rect, false)


func _draw_ground_marker(cell_size: Vector2) -> void:
	var radius := cell_size.x * 0.3
	var color := Color(0.35, 0.85, 1.0, 0.35) if selected else Color(0.0, 0.0, 0.0, 0.18)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, radius, color)
	if selected:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(0.5, 0.95, 1.0, 0.7), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
