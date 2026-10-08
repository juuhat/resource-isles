class_name QuestHighlight
extends Node3D

# Makes a model stand out as something a quest wants the player to find. A soft gold glow plays over
# its surfaces (quest_glow.gdshader, set as each mesh's material_overlay, so the model keeps its own
# materials), a few gold motes rise off its faces, and a pool of light with a ring and a spreading
# ripple lies on the ground under it (quest_halo.gdshader). Gold keeps quest objects apart from the
# teal of blueprints and robot tech. Quests choose what glows through their highlights (QuestTarget);
# the renderer and ShipWreck put it on the active quests' targets.
#
# It works on any Node3D at any scale, once the node is in the tree:
#   QuestHighlight.attach(model)   # returns the highlight already there, if there is one
#   QuestHighlight.detach(model)   # fades it out, then gives the meshes their own overlays back
#   QuestHighlight.set_on(model, highlighted)   # either, from a recomputed condition
# It lives as the model's child, so it is freed with the model (the renderer's re-render) and follows
# it if it moves. The halo sits under the bottom of the model's bounds and is sized to clear them;
# pass a halo_radius (world units) to size it yourself, or 0 for no halo (an object that isn't
# standing on the ground).

const GLOW_SHADER := preload("res://assets/shaders/quest/quest_glow.gdshader")
const HALO_SHADER := preload("res://assets/shaders/quest/quest_halo.gdshader")
const COLOR := Color("#ffc857")
const MOTE_COLOR := Color("#ffe39a")
const FADE_SECONDS := 0.5
# The default halo radius as a multiple of half the model's footprint diagonal, so the ring clears it.
const HALO_MARGIN := 1.45
# The halo's lift off the ground, in world units, so it never fights the tile top.
const HALO_LIFT := 0.4
# One mote per MOTE_SPACING world units of the model's bounds diagonal, within these limits.
const MOTES_MIN := 5
const MOTES_MAX := 12
const MOTE_SPACING := 12.0
const MOTE_SECONDS := 1.8
const MOTE_POINTS_MAX := 256
# The world direction the glow's band of light sweeps along: mostly up, tilted so it also travels
# across something lying flat (like the radar dish fallen beside the wreck).
const SWEEP_AXIS := Vector3(0.55, 1.0, 0.3)

# World units; negative fits it to the model, 0 leaves out the halo and motes.
var halo_radius := -1.0
var _glow: ShaderMaterial
var _halo_material: ShaderMaterial
var _halo: MeshInstance3D
var _motes: CPUParticles3D
# MeshInstance3D -> the material_overlay it had before.
var _meshes := {}
# The model's bounds and the halo's spot, in the model's own space, and the model's transform when
# they were last placed in the world.
var _local_bounds := AABB()
var _ground_local := Vector3.ZERO
var _placed_at := Transform3D()
var _placed := false
var _strength := 1.0
var _fading := false


# Highlights target (in the tree). Idempotent: an existing highlight is kept, and brought back if
# it is fading out.
static func attach(target: Node3D, radius := -1.0) -> QuestHighlight:
	var highlight := find_on(target)
	if highlight == null:
		highlight = QuestHighlight.new()
		highlight.name = "QuestHighlight"
		highlight.halo_radius = radius
		target.add_child(highlight)
	highlight._fading = false
	highlight._set_strength(1.0)
	if highlight._motes != null:
		highlight._motes.emitting = true
	return highlight


# Attaches or detaches target's highlight, for a caller that recomputes whether it should glow.
static func set_on(target: Node3D, highlighted: bool, radius := -1.0) -> void:
	if highlighted:
		attach(target, radius)
	else:
		detach(target)


# Fades target's highlight out, if it has one; it frees itself once gone.
static func detach(target: Node3D) -> void:
	var highlight := find_on(target)
	if highlight != null:
		highlight._fading = true
		if highlight._motes != null:
			highlight._motes.emitting = false


static func find_on(target: Node3D) -> QuestHighlight:
	for child in target.get_children():
		if child is QuestHighlight and not child.is_queued_for_deletion():
			return child
	return null


func is_fading() -> bool:
	return _fading


func _init() -> void:
	_glow = ShaderMaterial.new()
	_glow.shader = GLOW_SHADER
	_glow.set_shader_parameter("color", COLOR)
	_glow.set_shader_parameter("sweep_axis", SWEEP_AXIS.normalized())


func _enter_tree() -> void:
	var target := get_parent()
	var nodes := target.find_children("*", "MeshInstance3D", true, false)
	if target is MeshInstance3D:
		nodes.append(target)
	for node in nodes:
		if is_ancestor_of(node):
			continue
		var mesh := node as MeshInstance3D
		_meshes[mesh] = mesh.material_overlay
		mesh.material_overlay = _glow


func _exit_tree() -> void:
	for mesh in _meshes:
		if is_instance_valid(mesh) and mesh.material_overlay == _glow:
			mesh.material_overlay = _meshes[mesh]
	_meshes.clear()


func _ready() -> void:
	var bounds := _measure()
	var to_local := global_transform.affine_inverse()
	_local_bounds = to_local * bounds
	var center := bounds.get_center()
	_ground_local = to_local * Vector3(center.x, bounds.position.y, center.z)
	# Seconds of offset taken from where it stands, so neighbouring objects glint in turn and a
	# re-render doesn't restart the sweep.
	var phase := fposmod(center.x * 0.031 + center.z * 0.017, 10.0)
	_glow.set_shader_parameter("phase", phase)

	var radius := halo_radius
	if radius < 0.0:
		radius = Vector2(bounds.size.x, bounds.size.z).length() * 0.5 * HALO_MARGIN
	if radius > 0.0:
		_add_halo(radius, phase)
	_add_motes(bounds)
	_set_strength(_strength)
	_follow()


func _process(delta: float) -> void:
	if _fading:
		_set_strength(maxf(_strength - delta / FADE_SECONDS, 0.0))
		if _strength <= 0.0:
			queue_free()
			return
	_follow()


# The highlighted meshes' bounds in world space.
func _measure() -> AABB:
	var bounds := AABB(global_position, Vector3.ZERO)
	var has := false
	for mesh: MeshInstance3D in _meshes:
		var box := mesh.global_transform * mesh.get_aabb()
		bounds = box if not has else bounds.merge(box)
		has = true
	return bounds


# Keeps the sweep's span and the halo with the model when it moves.
func _follow() -> void:
	var placed := global_transform
	if _placed and placed.is_equal_approx(_placed_at):
		return
	_placed = true
	_placed_at = placed
	# The model's extent along the sweep's axis, from its bounds' corners.
	var bounds := placed * _local_bounds
	var axis := SWEEP_AXIS.normalized()
	var from := INF
	var to := -INF
	for corner in 8:
		var along := bounds.get_endpoint(corner).dot(axis)
		from = minf(from, along)
		to = maxf(to, along)
	_glow.set_shader_parameter("sweep_from", from)
	_glow.set_shader_parameter("sweep_to", to)
	if _halo != null:
		_halo.global_position = placed * _ground_local + Vector3.UP * HALO_LIFT
	# The motes' start points are offsets from the model's origin (_surface_points).
	if _motes != null:
		_motes.global_position = placed.origin


func _set_strength(value: float) -> void:
	_strength = value
	_glow.set_shader_parameter("strength", value)
	if _halo_material != null:
		_halo_material.set_shader_parameter("strength", value)


# The halo and motes are top-level, so they keep their world size under a scaled model.
func _add_halo(radius: float, phase: float) -> void:
	_halo_material = ShaderMaterial.new()
	_halo_material.shader = HALO_SHADER
	_halo_material.set_shader_parameter("color", COLOR)
	_halo_material.set_shader_parameter("phase", phase)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	_halo = MeshInstance3D.new()
	_halo.name = "Halo"
	_halo.mesh = plane
	_halo.material_override = _halo_material
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.top_level = true
	add_child(_halo)


# Little gold gems that rise off the object's faces, turning as they go, and shrink away. More, and
# bigger, for a bigger object.
func _add_motes(bounds: AABB) -> void:
	var points := _surface_points()
	if points.is_empty():
		return
	var span := bounds.size.length()
	var size := clampf(span * 0.05, 1.5, 5.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = MOTE_COLOR
	var gem := SphereMesh.new()
	gem.radius = size
	gem.height = size * 2.8
	gem.radial_segments = 4
	gem.rings = 1
	gem.material = material
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.0))
	grow.add_point(Vector2(0.25, 1.0))
	grow.add_point(Vector2(1.0, 0.0))

	_motes = CPUParticles3D.new()
	_motes.name = "Motes"
	_motes.mesh = gem
	_motes.amount = clampi(roundi(span / MOTE_SPACING), MOTES_MIN, MOTES_MAX)
	_motes.lifetime = MOTE_SECONDS
	_motes.randomness = 0.5
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	_motes.emission_points = points
	_motes.direction = Vector3.UP
	_motes.spread = 12.0
	_motes.gravity = Vector3.ZERO
	var rise := clampf(span * 0.6, 20.0, 60.0)
	_motes.initial_velocity_min = rise / MOTE_SECONDS * 0.7
	_motes.initial_velocity_max = rise / MOTE_SECONDS * 1.1
	_motes.particle_flag_rotate_y = true
	_motes.angular_velocity_min = 90.0
	_motes.angular_velocity_max = 200.0
	_motes.scale_amount_curve = grow
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.top_level = true
	add_child(_motes)


# Where motes start: the middle of each face of the highlighted meshes, relative to the model's
# origin, thinned out to at most MOTE_POINTS_MAX.
func _surface_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	for mesh: MeshInstance3D in _meshes:
		if mesh.mesh == null:
			continue
		var faces := mesh.mesh.get_faces()
		var to_world := mesh.global_transform
		for i in range(0, faces.size() - 2, 3):
			points.append(to_world * ((faces[i] + faces[i + 1] + faces[i + 2]) / 3.0) - global_position)
	if points.size() <= MOTE_POINTS_MAX:
		return points
	var thinned := PackedVector3Array()
	var step := float(points.size()) / MOTE_POINTS_MAX
	for i in MOTE_POINTS_MAX:
		thinned.append(points[int(i * step)])
	return thinned
