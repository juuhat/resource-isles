class_name Dog
extends Node3D

# The dog companion (Companion Unit K9-DA), a 3D model that wanders the island on its own.
# It picks a random nearby walkable cell, walks there along a hex path at a constant
# world-space speed on the XZ ground plane, pauses, then picks another — purely ambient
# for now (testing). Movement mirrors PlayerUnit, but the dog steers itself instead of
# following commanded paths, and it has no selection marker or actions.

const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const HexPathfinderScript := preload("res://scripts/island/hex_pathfinder.gd")
const DOG_MODEL := preload("res://assets/models/units/dog.glb")
# Walking animation lives in its own glTF (same rig); merged into the model's player below.
const DOG_WALK_ANIM := preload("res://assets/models/units/dog_animation_walking.glb")

# How far the model's footprint should span, as a fraction of a tile's width. The dog is
# scaled by its widest horizontal extent so a long, low body fits the tile naturally.
@export var visual_size_tiles := 0.55
@export var move_speed := 180.0
# How quickly the model turns to face its travel direction (higher = snappier).
@export var turn_speed := 10.0
# Yaw offset (radians) so the model's modeled front points along its travel direction.
# Tune if the dog walks sideways/backwards once you see it in-game.
@export var model_yaw_offset := 0.0
# How many cells out the dog may pick its next wander target.
@export var wander_radius := 4
# Idle pause between walks, seconds (randomized in this range).
@export var pause_min := 0.8
@export var pause_max := 3.0

var renderer: IslandRenderer
var current_cell := Vector2i(-1, -1)

var _island: IslandData
var _path: Array[Vector2i] = []
var _target_world := Vector3.ZERO
var _pending_cell := Vector2i(-1, -1)
var _moving := false
var _pause_timer := 0.0
var _model: Node3D
var _anim_player: AnimationPlayer
var _walk_anim := ""


func setup(new_renderer: IslandRenderer) -> void:
	renderer = new_renderer


func _ready() -> void:
	_model = DOG_MODEL.instantiate()
	add_child(_model)
	_scale_model_to_tile()
	_setup_animation()
	visible = false


# Drop the dog onto the given island at a random walkable cell and start it wandering.
func begin(island: IslandData) -> void:
	_island = island
	current_cell = _find_spawn_cell()
	if current_cell == Vector2i(-1, -1):
		visible = false
		return

	position = renderer.get_cell_center(current_cell)
	_path.clear()
	_moving = false
	_pause_timer = randf_range(pause_min, pause_max)
	visible = true
	_stop_walk_anim()


# Park the dog (e.g. when leaving its island). It keeps its place but stops moving.
func halt() -> void:
	_island = null
	_path.clear()
	_moving = false
	visible = false
	_stop_walk_anim()


func _process(delta: float) -> void:
	if _island == null or not visible:
		return

	if _moving:
		_advance_movement(delta)
	else:
		_pause_timer -= delta
		if _pause_timer <= 0.0:
			_start_next_wander()


func _advance_movement(delta: float) -> void:
	var to_target := _target_world - position
	_face_direction(to_target, delta)
	var distance := to_target.length()
	var step := move_speed * delta

	if distance <= step or distance == 0.0:
		position = _target_world
		current_cell = _pending_cell
		_advance_to_next()
	else:
		position += to_target / distance * step


func _advance_to_next() -> void:
	if _path.is_empty():
		_moving = false
		_pause_timer = randf_range(pause_min, pause_max)
		_stop_walk_anim()
		return

	_pending_cell = _path.pop_front()
	_target_world = renderer.get_cell_center(_pending_cell)
	_moving = true


# Pick a reachable nearby cell and walk to it; if none is found, wait and try again.
func _start_next_wander() -> void:
	var path := _pick_wander_path()
	if path.is_empty():
		_pause_timer = randf_range(pause_min, pause_max)
		return

	_path = path
	_play_walk_anim()
	_advance_to_next()


func _pick_wander_path() -> Array[Vector2i]:
	for _attempt in range(12):
		var offset := Vector2i(
			randi_range(-wander_radius, wander_radius),
			randi_range(-wander_radius, wander_radius)
		)
		var cell := current_cell + offset
		if cell == current_cell or not HexPathfinderScript.is_walkable(_island, cell):
			continue

		var path := HexPathfinderScript.find_path(_island, current_cell, cell)
		if not path.is_empty():
			return path

	return []


func _find_spawn_cell() -> Vector2i:
	var candidates: Array[Vector2i] = []
	for y in range(_island.height):
		for x in range(_island.width):
			var cell := Vector2i(x, y)
			if HexPathfinderScript.is_walkable(_island, cell) and not _island.has_building(cell):
				candidates.append(cell)

	if candidates.is_empty():
		return Vector2i(-1, -1)

	return candidates[randi() % candidates.size()]


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

	var cell_size := renderer.cell_size if renderer != null else Vector2(128.0, 128.0)
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


# Find an AnimationPlayer on the model (or merge one in from the dedicated walking glTF) and
# remember the name of a looping walk animation to play while moving. Best-effort: if nothing
# is found the dog still walks, just without leg motion.
func _setup_animation() -> void:
	_anim_player = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_merge_walk_animation()
	_walk_anim = _pick_walk_anim_name()
	if _walk_anim != "":
		var anim := _anim_player.get_animation(_walk_anim)
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR


# Copy animations from the separate walking glTF into the model's AnimationPlayer (both were
# exported from the same rig, so the bone track paths line up). Creates a player if the base
# model has none.
func _merge_walk_animation() -> void:
	var walk_scene := DOG_WALK_ANIM.instantiate()
	var source := walk_scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source != null:
		if _anim_player == null:
			_anim_player = AnimationPlayer.new()
			_model.add_child(_anim_player)

		for library_name in source.get_animation_library_list():
			var source_library := source.get_animation_library(library_name)
			var dest_library: AnimationLibrary
			if _anim_player.has_animation_library(library_name):
				dest_library = _anim_player.get_animation_library(library_name)
			else:
				dest_library = AnimationLibrary.new()
				_anim_player.add_animation_library(library_name, dest_library)

			for anim_name in source_library.get_animation_list():
				if not dest_library.has_animation(anim_name):
					dest_library.add_animation(anim_name, source_library.get_animation(anim_name))

	walk_scene.queue_free()


func _pick_walk_anim_name() -> String:
	if _anim_player == null:
		return ""

	# Meshy/Unreal exports don't name the clip "walk" (e.g. "Armature|Unreal Take|baselayer"),
	# and the base model ships a 1-frame rest clip ("...|clip0|..."). So prefer a name that does
	# say "walk", otherwise take the longest clip — the real walk cycle, not the static pose.
	var best := ""
	var best_length := -1.0
	for anim_name in _anim_player.get_animation_list():
		if anim_name.to_lower().contains("walk"):
			return anim_name
		var length := _anim_player.get_animation(anim_name).length
		if length > best_length:
			best_length = length
			best = anim_name

	return best


func _play_walk_anim() -> void:
	if _anim_player != null and _walk_anim != "" and _anim_player.current_animation != _walk_anim:
		_anim_player.play(_walk_anim)


func _stop_walk_anim() -> void:
	if _anim_player != null and _anim_player.is_playing():
		_anim_player.stop()
