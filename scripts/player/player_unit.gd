class_name PlayerUnit
extends Node3D

# The player-controlled robot (3D, see docs/3d-models.md). Holds a current
# hex cell and walks along a queued path of cells at a constant world-space speed on the
# XZ ground plane. The robot is a 3D model (player_model.glb); a flat disc under it is the
# selection/ground marker. Movement logic is unchanged from the 2D version — only the
# coordinate type (Vector2 -> Vector3) differs.

signal arrived(cell: Vector2i)
signal entered_cell(cell: Vector2i)

const PLAYER_MODEL := preload("res://assets/player/player_model.glb")
# The model's native height in glTF units (feet at y=0), from its mesh bounds — used to
# scale it to the desired on-map size.
const MODEL_NATIVE_HEIGHT := 1.2
# Yaw offset (radians) applied so the model's modeled front points the right way. Used by
# both the rest pose and movement facing so they stay in sync.
const MODEL_YAW_OFFSET := 0.0
const SELECT_SOUNDS: Array[AudioStream] = [
	preload("res://assets/audio/sfx/player1.wav"),
	preload("res://assets/audio/sfx/player2.wav"),
	preload("res://assets/audio/sfx/player3.wav"),
]

@export var move_speed := 320.0
@export var visual_size_tiles := Vector2(0.65, 0.65)
# How quickly the model turns to face its travel direction (higher = snappier).
@export var turn_speed := 12.0

var renderer: IslandRenderer
var current_cell := Vector2i(-1, -1)
var selected := false

var _path: Array[Vector2i] = []
var _target_world := Vector3.ZERO
var _pending_cell := Vector2i(-1, -1)
var _moving := false
var _model: Node3D
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

	# Scale the model so its height matches the intended on-map size (visual_size_tiles in
	# tile fractions). Its feet are at y=0, so it sits straight on the tile.
	_model = PLAYER_MODEL.instantiate()
	var cell_size := renderer.cell_size if renderer != null else Vector2(128.0, 128.0)
	var model_scale := (visual_size_tiles.y * cell_size.y) / MODEL_NATIVE_HEIGHT
	_model.scale = Vector3(model_scale, model_scale, model_scale)
	_model.rotation.y = MODEL_YAW_OFFSET
	add_child(_model)

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


# Smoothly turn the model so its front faces the horizontal travel direction, applying the
# same MODEL_YAW_OFFSET as the rest pose. Uses lerp_angle so it takes the shortest way around.
func _face_direction(direction: Vector3, delta: float) -> void:
	if _model == null:
		return

	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.001:
		return

	var target_yaw := atan2(flat.x, flat.z) + MODEL_YAW_OFFSET
	_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, clampf(delta * turn_speed, 0.0, 1.0))


func _process(delta: float) -> void:
	if not _moving:
		return

	var to_target := _target_world - position
	_face_direction(to_target, delta)
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
