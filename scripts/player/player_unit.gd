class_name PlayerUnit
extends Node3D

# The player-controlled robot (3D, see docs/3d-conversion.md Phase 3). Holds a current
# hex cell and walks along a queued path of cells at a constant world-space speed on the
# XZ ground plane. The robot is an upright Sprite3D billboard reusing the 2D art; a flat
# disc under it is the selection/ground marker. Movement logic is unchanged from the 2D
# version — only the coordinate type (Vector2 -> Vector3) differs.

signal arrived(cell: Vector2i)
signal entered_cell(cell: Vector2i)

const ROBOT_TEXTURE := preload("res://assets/player/player_robot.png")
const SELECT_SOUNDS: Array[AudioStream] = [
	preload("res://assets/audio/sfx/player1.wav"),
	preload("res://assets/audio/sfx/player2.wav"),
	preload("res://assets/audio/sfx/player3.wav"),
]

@export var move_speed := 320.0
@export var visual_size_tiles := Vector2(0.65, 0.65)

var renderer: IslandRenderer
var current_cell := Vector2i(-1, -1)
var selected := false

var _path: Array[Vector2i] = []
var _target_world := Vector3.ZERO
var _pending_cell := Vector2i(-1, -1)
var _moving := false
var _sprite: Sprite3D
var _marker: MeshInstance3D
var _marker_material: StandardMaterial3D
var _select_player: AudioStreamPlayer
var _last_sound_index := -1


func _ready() -> void:
	_marker_material = StandardMaterial3D.new()
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var disc := CylinderMesh.new()
	disc.top_radius = renderer.cell_size.x * 0.3 if renderer != null else 38.0
	disc.bottom_radius = disc.top_radius
	disc.height = 1.0
	disc.radial_segments = 24
	_marker = MeshInstance3D.new()
	_marker.mesh = disc
	_marker.material_override = _marker_material
	_marker.position.y = 1.0
	add_child(_marker)

	_sprite = Sprite3D.new()
	_sprite.texture = ROBOT_TEXTURE
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.shaded = false
	_sprite.double_sided = true
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	var cell_size := renderer.cell_size if renderer != null else Vector2(128.0, 128.0)
	_sprite.pixel_size = (visual_size_tiles.x * cell_size.x) / float(maxi(1, ROBOT_TEXTURE.get_width()))
	_sprite.position.y = ROBOT_TEXTURE.get_height() * _sprite.pixel_size * 0.5
	add_child(_sprite)

	_update_marker_color()

	_select_player = AudioStreamPlayer.new()
	add_child(_select_player)


func setup(new_renderer: IslandRenderer) -> void:
	renderer = new_renderer


func place_at(cell: Vector2i) -> void:
	current_cell = cell
	position = renderer.get_cell_center(cell)
	_path.clear()
	_moving = false
	visible = true


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
	if selected:
		_play_select_sound()
	_update_marker_color()


func _update_marker_color() -> void:
	if _marker_material == null:
		return
	_marker_material.albedo_color = Color(0.35, 0.85, 1.0, 0.5) if selected else Color(0.0, 0.0, 0.0, 0.22)


func _play_select_sound() -> void:
	if _select_player == null or SELECT_SOUNDS.is_empty():
		return

	var index := randi() % SELECT_SOUNDS.size()
	if index == _last_sound_index and SELECT_SOUNDS.size() > 1:
		index = (index + 1) % SELECT_SOUNDS.size()
	_last_sound_index = index

	_select_player.stream = SELECT_SOUNDS[index]
	_select_player.play()


func _process(delta: float) -> void:
	if not _moving:
		return

	var to_target := _target_world - position
	var distance := to_target.length()
	var step := move_speed * delta

	if distance <= step or distance == 0.0:
		position = _target_world
		current_cell = _pending_cell
		entered_cell.emit(current_cell)
		_advance_to_next()
	else:
		position += to_target / distance * step


func _advance_to_next() -> void:
	if _path.is_empty():
		_moving = false
		arrived.emit(current_cell)
		return

	_pending_cell = _path.pop_front()
	_target_world = renderer.get_cell_center(_pending_cell)
	_moving = true
