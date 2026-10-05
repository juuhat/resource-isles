class_name PlayerUnit
extends Node3D

# The player-controlled robot (3D, see docs/3d-models.md). Holds a current
# hex cell and walks along a queued path of cells at a constant world-space speed on the
# XZ ground plane. The robot is an animated 3D model (salvage_robot.glb). When selected it shows a
# translucent hex cap on top of its tile, matching the placement-preview / hover highlight;
# deselected it has no marker. Movement logic is unchanged from the 2D version — only the
# coordinate type (Vector2 -> Vector3) differs.

signal arrived(cell: Vector2i)
signal entered_cell(cell: Vector2i)

const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const PLAYER_MODEL := preload("res://assets/models/units/salvage_robot.glb")
# Translucent blue selection cap, matching the renderer's hover/placement highlight tint.
const MARKER_COLOR := Color(0.35, 0.85, 1.0, 0.45)
# The model's native body height in glTF units (feet at y=0 to head top; the antenna rises
# above it) — used to scale it to the desired on-map size.
const MODEL_NATIVE_HEIGHT := 1.2
# Distance the body covers in one loop of each gait, in native model units, so playback can be
# matched to movement (tools/build_player_robot.py). Walk: two planted sweeps of a 0.395-unit
# leg through +/-0.34 radians, 4 * 0.395 * sin(0.34). Run: a planted sweep through +/-0.55
# radians, 2 * 0.395 * sin(0.55), lasts a quarter of the loop, so 4 times that.
const WALK_CYCLE_DISTANCE := 0.527
const RUN_CYCLE_DISTANCE := 1.6517
# Yaw offset (radians) applied so the model's modeled front points the right way. Used by
# both the rest pose and movement facing so they stay in sync.
const MODEL_YAW_OFFSET := 0.0
const SELECT_SOUNDS: Array[AudioStream] = [
	preload("res://assets/audio/sfx/player1.wav"),
	preload("res://assets/audio/sfx/player2.wav"),
	preload("res://assets/audio/sfx/player3.wav"),
]

@export var move_speed := 320.0
# Height 0.45 of a tile (docs/building-style-palette.md scale standard), which leaves the robot
# room to stand beside a building or in its work yard without touching it.
@export var visual_size_tiles := Vector2(0.45, 0.45)
# How quickly the model turns to face its travel direction (higher = snappier).
@export var turn_speed := 12.0

# Work clips (see set_work): the clip played while parked, and the tool node in the robot's
# hand that only shows during it (tools/build_player_robot.py).
# "operate" is the hand-PTO docking pose, its spindle spinning in a building's generator socket.
# "build" works a blueprint with the wrench.
const WORK_CLIPS := {"chop": "HeldAxe", "mine": "HeldPickaxe", "operate": "HeldPTO", "build": "HeldWrench"}
# How long a tool takes to pop into the hand when a swing starts.
const EQUIP_TIME := 0.15

# Where cells are and how high: anything with get_cell_center, get_step_height and cell_size. In
# the game that's the WorldView (every island and the sea); a check may use one IslandRenderer.
var ground
var navigation: WorldNavigation
var current_cell := GameTypes.NO_CELL
var selected := false
var boat_id := -1
var _vessel: Node3D

var _path: Array[Vector2i] = []
var _target_world := Vector3.ZERO
var _pending_cell := GameTypes.NO_CELL
var _moving := false
var _model: Node3D
var _animation_player: AnimationPlayer
var _idle_animation := ""
var _walk_animation := ""
var _run_animation := ""
# The gait played while moving (Run, or Walk for a model without one) and its cycle distance.
var _move_animation := ""
var _move_cycle_distance := WALK_CYCLE_DISTANCE
# Work kind ("chop", "mine") -> its clip name and its held tool node.
var _work_animations := {}
var _held_tools := {}
var _work := ""
var _marker: MeshInstance3D
var _marker_material: StandardMaterial3D
var _select_player: AudioStreamPlayer
var _last_sound_index := -1
# Optional last leg of a route, into a building's work spot (see follow_path).
var _spot_cell := GameTypes.NO_CELL
var _spot_position := Vector3.ZERO
var _at_spot := false
# Parked pose set by face_toward().
var _has_rest := false
var _rest_position := Vector3.ZERO
var _rest_yaw := 0.0


func _ready() -> void:
	_marker_material = StandardMaterial3D.new()
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marker_material.albedo_color = MARKER_COLOR

	_marker = MeshInstance3D.new()
	_marker.mesh = _build_hex_cap_mesh()
	_marker.material_override = _marker_material
	# Float just above the tile top, like the placement-preview / hover-highlight caps.
	_marker.position.y = 0.6
	_marker.visible = false
	add_child(_marker)

	# Scale the model so its height matches the intended on-map size (visual_size_tiles in
	# tile fractions). Its feet are at y=0, so it sits straight on the tile.
	_model = PLAYER_MODEL.instantiate()
	var cell_size: Vector2 = ground.cell_size if ground != null else Vector2(128.0, 128.0)
	var model_scale := (visual_size_tiles.y * cell_size.y) / MODEL_NATIVE_HEIGHT
	_model.scale = Vector3(model_scale, model_scale, model_scale)
	_model.rotation.y = MODEL_YAW_OFFSET
	add_child(_model)
	_setup_animations()

	_update_marker()

	_select_player = AudioStreamPlayer.new()
	add_child(_select_player)


func setup(new_ground, world_navigation: WorldNavigation = null) -> void:
	ground = new_ground
	navigation = world_navigation


func place_at(cell: Vector2i) -> void:
	current_cell = cell
	position = ground.get_cell_center(cell)
	_path.clear()
	_spot_cell = GameTypes.NO_CELL
	_at_spot = false
	_has_rest = false
	_moving = false
	visible = true
	_update_marker()


func mount_boat(id: int, cell: Vector2i, yaw: float) -> void:
	leave_boat()
	boat_id = id
	place_at(cell)
	_vessel = Node3D.new()
	add_child(_vessel)
	_vessel.rotation.y = yaw
	var hull := IslandRenderer.SALVAGE_SKIFF_MODEL.instantiate() as Node3D
	_vessel.add_child(hull)
	var size: float = ground.cell_size.x / IslandRenderer.TRUE_TILE_UNITS
	hull.scale = Vector3.ONE * size
	var helm := hull.find_child("PilotSpot", true, false) as Node3D
	_model.reparent(_vessel, false)
	_model.position = helm.position * size if helm != null else Vector3.ZERO
	_model.rotation.y = PI / 2.0
	set_work("operate")


func boat_yaw() -> float:
	return _vessel.rotation.y if _vessel != null else 0.0


func leave_boat() -> void:
	if _vessel != null:
		_model.reparent(self, false)
		_model.position = Vector3.ZERO
		_model.rotation.y = boat_yaw() + PI / 2.0
		_vessel.free()
		_vessel = null
	boat_id = -1
	set_work("")


# Walk the cells in `path`, then, with a spot_cell, one last leg straight to spot_position inside
# that cell (a building's work spot), which becomes the robot's cell.
func follow_path(path: Array[Vector2i], spot_cell := GameTypes.NO_CELL, spot_position := Vector3.ZERO) -> void:
	if path.is_empty() and spot_cell == GameTypes.NO_CELL:
		return

	_path = path.duplicate()
	_spot_cell = spot_cell
	_spot_position = spot_position
	_at_spot = false
	_has_rest = false
	_advance_to_next()


# Swap the rest of the route for `path` (from next_cell()), finishing the leg in progress first.
# Used when construction changes the map under a moving robot.
func reroute(path: Array[Vector2i], spot_cell := GameTypes.NO_CELL, spot_position := Vector3.ZERO) -> void:
	_path = path.duplicate()
	_spot_cell = spot_cell
	_spot_position = spot_position


# True while parked on (or walking into) a building's work spot.
func is_at_spot() -> bool:
	return _at_spot


# The cell the robot is standing on, or heading into while moving.
func next_cell() -> Vector2i:
	return _pending_cell if _moving else current_cell


func is_moving() -> bool:
	return _moving


# While parked, turn to face `world_target` and lean `nudge_tiles` of a tile toward it — the
# pose for working a building or resource node from beside it.
func face_toward(world_target: Vector3, nudge_tiles := 0.0) -> void:
	var flat := Vector3(world_target.x - position.x, 0.0, world_target.z - position.z)
	if flat.length() < 0.001:
		return
	var cell_size: Vector2 = ground.cell_size if ground != null else Vector2(128.0, 128.0)
	var base: Vector3 = position if _at_spot else ground.get_cell_center(current_cell)
	_rest_position = base + flat.normalized() * nudge_tiles * cell_size.x
	_rest_yaw = atan2(flat.x, flat.z) + MODEL_YAW_OFFSET
	_has_rest = true


# Work while parked: swing a tool ("chop" with the axe, "mine" with the pickaxe), dock the hand PTO
# into a building ("operate"), or "" to stop. Moving still plays the run clip; the work resumes
# once parked again.
func set_work(kind: String) -> void:
	_work = kind
	_update_animation()


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	if selected:
		_play_select_sound()
	_update_marker()


# The selection cap shows only while selected; deselected, the robot has no ground marker.
# Parked, it sits on the robot's tile even when the robot stands off-centre (leaning toward a
# target, or at a work spot); moving, it travels with the robot.
func _update_marker() -> void:
	if _marker == null:
		return
	_marker.visible = selected
	_marker.position = Vector3(0.0, 0.6, 0.0)
	if not _moving and ground != null and current_cell != GameTypes.NO_CELL:
		var center: Vector3 = ground.get_cell_center(current_cell)
		_marker.position = Vector3(center.x - position.x, 0.6, center.z - position.z)


# A flat hex outline-fill matching the tile, for the selection highlight (mirrors the
# renderer's _build_hex_cap_mesh).
func _build_hex_cap_mesh() -> ArrayMesh:
	var size: Vector2 = ground.cell_size if ground != null else Vector2(128.0, 128.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := HexGridScript.hex_corners_3d(Vector3.ZERO, size)
	st.set_normal(Vector3.UP)
	for i in range(6):
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(ring[i])
		st.add_vertex(ring[(i + 1) % 6])
	return st.commit()


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
	if _vessel != null:
		_vessel.rotation.y = lerp_angle(_vessel.rotation.y, atan2(-flat.z, flat.x), clampf(delta * turn_speed, 0.0, 1.0))
		return

	var target_yaw := atan2(flat.x, flat.z) + MODEL_YAW_OFFSET
	_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, clampf(delta * turn_speed, 0.0, 1.0))


func _process(delta: float) -> void:
	_update_animation()
	if not _moving:
		_settle(delta)
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
		if boat_id == -1:
			position.y = ground.get_step_height(current_cell, _pending_cell, position)


# Parked: ease into the pose from face_toward(), if any.
func _settle(delta: float) -> void:
	if not _has_rest or _model == null:
		return

	var weight := clampf(delta * turn_speed * 0.5, 0.0, 1.0)
	position = position.lerp(_rest_position, weight)
	_model.rotation.y = lerp_angle(_model.rotation.y, _rest_yaw, clampf(delta * turn_speed, 0.0, 1.0))
	_update_marker()


func _advance_to_next() -> void:
	if boat_id != -1 and navigation != null and not _path.is_empty() and not navigation.can_sail(_path[0], boat_id):
		_path.clear()
	if _path.is_empty():
		if _spot_cell != GameTypes.NO_CELL:
			# Last leg: straight into the building's work spot.
			_pending_cell = _spot_cell
			_target_world = _spot_position
			_spot_cell = GameTypes.NO_CELL
			_at_spot = true
			_moving = true
			return

		_moving = false
		_update_marker()
		arrived.emit(current_cell)
		return

	_pending_cell = _path.pop_front()
	# Sailable cells' centres are at the water's surface, so a boat floats there.
	_target_world = ground.get_cell_center(_pending_cell)
	_moving = true
	_update_marker()


func _setup_animations() -> void:
	_animation_player = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation_player == null:
		return
	for animation_name in _animation_player.get_animation_list():
		var clip := String(animation_name).get_slice("/", String(animation_name).get_slice_count("/") - 1).to_lower()
		if clip == "idle":
			_idle_animation = animation_name
		elif clip == "walk":
			_walk_animation = animation_name
		elif clip == "run":
			_run_animation = animation_name
		elif WORK_CLIPS.has(clip):
			_work_animations[clip] = animation_name
		else:
			continue
		_animation_player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	_move_animation = _run_animation if not _run_animation.is_empty() else _walk_animation
	_move_cycle_distance = RUN_CYCLE_DISTANCE if not _run_animation.is_empty() else WALK_CYCLE_DISTANCE
	for kind in WORK_CLIPS:
		var tool := _model.find_child(WORK_CLIPS[kind], true, false) as Node3D
		if tool != null:
			tool.visible = false
			_held_tools[kind] = tool
	_update_animation()


func _update_animation() -> void:
	if _animation_player == null:
		return
	var walking := _moving and boat_id == -1
	var working := (not _moving or boat_id != -1) and _work_animations.has(_work)
	var animation_name: String = _move_animation if walking else _idle_animation
	if working:
		animation_name = _work_animations[_work]
	# Match the in-place gait to translation, including changes to speed or model size.
	# Always reset this for idle/work so their timing doesn't inherit the gait's rate.
	var playback_speed := 1.0
	if walking and not _move_animation.is_empty():
		var cycle_distance := _move_cycle_distance * absf(_model.scale.z)
		var cycle_length := _animation_player.get_animation(_move_animation).length
		playback_speed = maxf(move_speed, 0.0) * cycle_length / maxf(cycle_distance, 0.001)
	_animation_player.speed_scale = playback_speed
	if not animation_name.is_empty() and _animation_player.current_animation != animation_name:
		_animation_player.play(animation_name, 0.12)
	for kind in _held_tools:
		_show_tool(_held_tools[kind], working and kind == _work)


# Pops a held tool into the hand (scaling up from nothing) or hides it.
func _show_tool(tool: Node3D, shown: bool) -> void:
	if tool.visible == shown:
		return
	tool.visible = shown
	if shown:
		tool.scale = Vector3.ONE * 0.01
		var tween := create_tween().tween_property(tool, "scale", Vector3.ONE, EQUIP_TIME)
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
