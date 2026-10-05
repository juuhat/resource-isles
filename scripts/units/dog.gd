class_name Dog
extends Node3D

# The dog companion (Companion Unit K9-DA), a 3D model that walks the hex grid on its own.
# It has two modes, driven by main.gd from the rescue state in WorldData:
#   STRANDED  — waiting at one cell on its ring-1 island until the robot walks up and rescues
#               it (the MAIN quest). It stays put so the player can always find it.
#   FOLLOWING — rescued: it trails the robot (the `leader`), walking to a cell beside it
#               whenever it falls behind and pottering about nearby otherwise. main.gd moves
#               it onto whichever island the robot travels to.
# Movement mirrors PlayerUnit (hex path, constant world-space speed on the XZ plane), but the
# dog steers itself instead of following commanded paths, and it has no selection or actions.

enum Mode {
	STRANDED,
	FOLLOWING,
}

const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const HexPathfinderScript := preload("res://scripts/island/hex_pathfinder.gd")
const DOG_MODEL := preload("res://assets/models/units/k9_da.glb")
# Rigid mechanical model, built by tools/build_k9_da.py with embedded clips.
const WALK_CYCLE_DISTANCE := 0.4

# How far the model's footprint should span, as a fraction of a tile's width. The dog is
# scaled by its widest horizontal extent so a long, low body fits the tile naturally.
@export var visual_size_tiles := 0.55
@export var move_speed := 180.0
# Speed used when it has fallen well behind the robot, so it keeps up with the faster robot.
@export var catch_up_speed := 340.0
# Path length (in steps) beyond which the dog switches to catch_up_speed.
@export var catch_up_steps := 4
# How quickly the model turns to face its travel direction (higher = snappier).
@export var turn_speed := 10.0
# Yaw offset (radians) so the model's modeled front points along its travel direction.
# Tune if the dog walks sideways/backwards once you see it in-game.
@export var model_yaw_offset := 0.0
# While following: how many steps from the robot the dog may drift before it heads back.
@export var follow_distance := 2
# How many cells out the dog may pick an idle potter target while near the robot.
@export var wander_radius := 1
# Idle pause between potters, seconds (randomized in this range).
@export var pause_min := 0.6
@export var pause_max := 2.5
# Pause before re-checking the robot's position after a walk, so it reacts promptly.
@export var follow_check_seconds := 0.3

# Where cells are and how high, as for PlayerUnit.ground: the WorldView in the game, or one
# IslandRenderer in a check.
var ground
var current_cell := GameTypes.NO_CELL
var mode := Mode.STRANDED
# The unit the dog follows in FOLLOWING mode (the player robot).
var leader: PlayerUnit

var _island: IslandData
var _path: Array[Vector2i] = []
var _target_world := Vector3.ZERO
var _pending_cell := GameTypes.NO_CELL
var _moving := false
var _speed := 180.0
var _pause_timer := 0.0
var _model: Node3D
var _anim_player: AnimationPlayer
var _walk_anim := ""
var _idle_anim := ""
var _hop_tween: Tween
# The model's resting height (set when it is fitted to the tile); hops return to it.
var _model_base_y := 0.0


func setup(new_ground) -> void:
	ground = new_ground


func _ready() -> void:
	_model = DOG_MODEL.instantiate()
	add_child(_model)
	_scale_model_to_tile()
	_model_base_y = _model.position.y
	_setup_animation()
	_stop_walk_anim()
	visible = false


# Leave the dog waiting at `cell` on `island` (its stranded spot before the rescue).
func strand(island: IslandData, cell: Vector2i) -> void:
	mode = Mode.STRANDED
	leader = null
	_place(island, cell)


# Start trailing `new_leader` around `island`, appearing at `cell` (beside the robot).
func follow(island: IslandData, cell: Vector2i, new_leader: PlayerUnit) -> void:
	mode = Mode.FOLLOWING
	leader = new_leader
	_place(island, cell)


# The cell the dog is standing on, or stepping into while moving.
func next_cell() -> Vector2i:
	return _pending_cell if _moving else current_cell


# Whether the dog is out and about on `island`.
func is_on(island: IslandData) -> bool:
	return visible and _island != null and _island == island


# Park the dog out of sight (e.g. its island hasn't been reached yet).
func halt() -> void:
	_island = null
	_path.clear()
	_moving = false
	visible = false
	_stop_walk_anim()


# A little double hop — the "you found me" beat when the robot rescues the dog.
func celebrate() -> void:
	if not visible or _model == null:
		return

	_pause_timer = maxf(_pause_timer, 1.2)
	if _hop_tween != null:
		_hop_tween.kill()
	var hop_height: float = (ground.cell_size.y if ground != null else 128.0) * 0.25
	_hop_tween = create_tween()
	for _hop in range(2):
		_hop_tween.tween_property(_model, "position:y", _model_base_y + hop_height, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_hop_tween.tween_property(_model, "position:y", _model_base_y, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _place(island: IslandData, cell: Vector2i) -> void:
	if island == null or ground == null or cell == GameTypes.NO_CELL:
		halt()
		return

	_island = island
	current_cell = cell
	position = ground.get_cell_center(current_cell)
	_path.clear()
	_moving = false
	_pause_timer = follow_check_seconds
	visible = true
	_stop_walk_anim()


func _process(delta: float) -> void:
	if _island == null or not visible:
		return

	if _moving:
		_advance_movement(delta)
	elif mode == Mode.FOLLOWING:
		_pause_timer -= delta
		if _pause_timer <= 0.0:
			_start_next_move()


func _advance_movement(delta: float) -> void:
	var to_target := _target_world - position
	_face_direction(to_target, delta)
	var distance := to_target.length()
	var step := _speed * delta

	if distance <= step or distance == 0.0:
		position = _target_world
		current_cell = _pending_cell
		_advance_to_next()
	else:
		position += to_target / distance * step
		position.y = ground.get_step_height(current_cell, _pending_cell, position)


func _advance_to_next() -> void:
	if _path.is_empty():
		_moving = false
		_pause_timer = follow_check_seconds
		_stop_walk_anim()
		return

	_pending_cell = _path.pop_front()
	_target_world = ground.get_cell_center(_pending_cell)
	_moving = true


# Head back to the robot if it has drifted too far; otherwise potter about near it now and then.
func _start_next_move() -> void:
	var path := _pick_follow_path()
	if not path.is_empty():
		_speed = catch_up_speed if path.size() > catch_up_steps else move_speed
	else:
		path = _pick_wander_path()
		if path.is_empty():
			_pause_timer = randf_range(pause_min, pause_max)
			return
		_speed = move_speed

	_path = path
	_play_walk_anim()
	_advance_to_next()


# The path to a cell beside the robot, or [] when the dog is already close enough (or the robot
# is unreachable). Stops one step short so the dog sits next to the robot, not on it.
func _pick_follow_path() -> Array[Vector2i]:
	if leader == null or leader.current_cell == GameTypes.NO_CELL:
		return []

	var path := HexPathfinderScript.find_path(_island, current_cell, leader.current_cell)
	if path.size() <= follow_distance:
		return []

	path.resize(path.size() - 1)
	return path


# An occasional short potter to a nearby cell while the robot is close. Only fires some of the
# time so the dog mostly sits by the robot rather than fidgeting constantly.
func _pick_wander_path() -> Array[Vector2i]:
	if randf() > 0.35:
		return []

	for _attempt in range(8):
		var offset := Vector2i(
			randi_range(-wander_radius, wander_radius),
			randi_range(-wander_radius, wander_radius)
		)
		var cell := current_cell + offset
		if cell == current_cell or not HexPathfinderScript.is_open(_island, cell):
			continue
		if leader != null and cell == leader.current_cell:
			continue

		var path := HexPathfinderScript.find_path(_island, current_cell, cell)
		if not path.is_empty() and path.size() <= wander_radius + 1:
			return path

	return []


# Smoothly turn the model so its front faces the horizontal travel direction.
func _face_direction(direction: Vector3, delta: float) -> void:
	if _model == null:
		return

	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.001:
		return

	var target_yaw := atan2(flat.x, flat.z) + model_yaw_offset
	_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, clampf(delta * turn_speed, 0.0, 1.0))


# --- Model sizing & animation -------------------------------------------------

# Scale the model so its widest horizontal extent matches visual_size_tiles of a tile, then
# offset it so its feet rest at y=0 and it sits centered on the cell. Done from the mesh
# AABB so we don't need to hard-code the model's native dimensions.
func _scale_model_to_tile() -> void:
	var aabb := _model_aabb()
	var horizontal := maxf(aabb.size.x, aabb.size.z)
	if horizontal < 0.0001:
		horizontal = maxf(aabb.size.y, 0.0001)

	var cell_size: Vector2 = ground.cell_size if ground != null else Vector2(128.0, 128.0)
	var scale := (visual_size_tiles * cell_size.x) / horizontal
	_model.scale = Vector3(scale, scale, scale)

	var center := aabb.get_center()
	_model.position = Vector3(-center.x * scale, -aabb.position.y * scale, -center.z * scale)


# The model's extent in its own local space. Prefer the skeleton's posed bone bounds: the dog
# is a skinned mesh whose bind-pose MeshInstance AABB is near-zero (the bones inflate it at
# runtime), so a mesh-AABB fit would scale it wildly. Fall back to mesh AABBs for any
# non-skinned model.
func _model_aabb() -> AABB:
	var skeleton := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton != null and skeleton.get_bone_count() > 0:
		var to_model := _model.global_transform.affine_inverse() * skeleton.global_transform
		var box := AABB(to_model * skeleton.get_bone_global_pose(0).origin, Vector3.ZERO)
		for i in range(1, skeleton.get_bone_count()):
			box = box.expand(to_model * skeleton.get_bone_global_pose(i).origin)
		return box

	var boxes: Array[AABB] = []
	_gather_mesh_aabbs(_model, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB(Vector3.ZERO, Vector3.ONE)

	var merged := boxes[0]
	for i in range(1, boxes.size()):
		merged = merged.merge(boxes[i])
	return merged


func _gather_mesh_aabbs(node: Node, parent_xform: Transform3D, out: Array[AABB]) -> void:
	var node_xform := parent_xform
	if node is Node3D:
		node_xform = parent_xform * (node as Node3D).transform

	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node_xform * (node as MeshInstance3D).get_aabb())

	for child in node.get_children():
		_gather_mesh_aabbs(child, node_xform, out)


# Find the model's embedded idle and walk clips. Movement remains gameplay-driven.
func _setup_animation() -> void:
	_anim_player = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_walk_anim = _pick_walk_anim_name()
	if _anim_player != null:
		for anim_name in _anim_player.get_animation_list():
			if anim_name.to_lower().contains("idle"):
				_idle_anim = anim_name
			_anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR


func _pick_walk_anim_name() -> String:
	if _anim_player == null:
		return ""

	for anim_name in _anim_player.get_animation_list():
		if anim_name.to_lower().contains("walk"):
			return anim_name
	return ""


func _play_walk_anim() -> void:
	if _anim_player != null and _walk_anim != "":
		var clip := _anim_player.get_animation(_walk_anim)
		_anim_player.speed_scale = _speed * clip.length / (WALK_CYCLE_DISTANCE * _model.scale.z)
		if _anim_player.current_animation != _walk_anim:
			_anim_player.play(_walk_anim, 0.12)


func _stop_walk_anim() -> void:
	if _anim_player != null:
		_anim_player.speed_scale = 1.0
		if _idle_anim != "":
			if _anim_player.current_animation != _idle_anim:
				_anim_player.play(_idle_anim, 0.12)
		else:
			_anim_player.stop()
