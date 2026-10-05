class_name ConstructionSite
extends Node3D

# Dresses a blueprint (IslandData.is_under_construction) on the map. The building is drawn twice: the
# real model, printed up from the ground to the robot's build progress with a glowing seam on the cut
# (construction_reveal.gdshader), and a teal hologram of the finished building over the rest
# (construction_hologram.gdshader). Sparks fly from the seam while the robot is working. Like
# PowerIndicator, it polls its island each frame, so the renderer needs no per-frame loop, and it is
# freed with the objects on the next re-render (which completing the building triggers).

const REVEAL_SHADER := preload("res://assets/shaders/construction/construction_reveal.gdshader")
const HOLOGRAM_SHADER := preload("res://assets/shaders/construction/construction_hologram.gdshader")
const SPARK_COLOR := Color("#ffd27a")
# How quickly the drawn cut catches up with the build progress, so it glides instead of stepping.
const CATCH_UP_RATE := 10.0
# Seconds sparks keep flying after progress last moved.
const SPARK_LINGER := 0.25

# Source material -> its reveal copy, shared by every construction site.
static var _reveal_materials := {}
static var _hologram_material: ShaderMaterial
static var _spark_material: StandardMaterial3D

var island: IslandData
var anchor_cell := GameTypes.NO_CELL
var _solid: Array[GeometryInstance3D] = []
var _ghost: Array[GeometryInstance3D] = []
var _bounds := AABB()
var _measured := false
var _shown := -1.0
var _last_progress := -1.0
var _spark_time := 0.0
var _sparks: CPUParticles3D


# solid_model is the building as it will stand, ghost_model a second copy of it for the hologram.
func setup(new_island: IslandData, new_anchor_cell: Vector2i, solid_model: Node3D, ghost_model: Node3D) -> void:
	island = new_island
	anchor_cell = new_anchor_cell
	for node in solid_model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		_solid.append(mesh_instance)
		if mesh_instance.material_override != null:
			mesh_instance.material_override = reveal_material(mesh_instance.material_override)
			continue
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, reveal_material(mesh_instance.get_active_material(surface)))
	var ghost_nodes: Array = ghost_model.find_children("*", "GeometryInstance3D", true, false) if ghost_model != null else []
	for node in ghost_nodes:
		var geometry := node as GeometryInstance3D
		geometry.material_override = _hologram()
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghost.append(geometry)
	_sparks = _make_sparks()
	add_child(_sparks)


func _process(delta: float) -> void:
	if island == null:
		return
	if not _measured:
		_measure()
	var progress := island.get_build_progress(anchor_cell)
	if _shown < 0.0:
		_shown = progress
	_shown = lerpf(_shown, progress, 1.0 - exp(-CATCH_UP_RATE * delta))
	var height := lerpf(_bounds.position.y, _bounds.end.y, _shown)
	for geometry in _solid:
		geometry.set_instance_shader_parameter("build_height", height)
	for geometry in _ghost:
		geometry.set_instance_shader_parameter("build_height", height)

	if _last_progress >= 0.0 and progress > _last_progress:
		_spark_time = SPARK_LINGER
	_last_progress = progress
	_spark_time -= delta
	_sparks.emitting = _spark_time > 0.0
	var center := _bounds.get_center()
	_sparks.global_position = Vector3(center.x, height, center.z)


# The model's world-space bounds, read once it is in the tree.
func _measure() -> void:
	var has := false
	for geometry in _solid:
		var box: AABB = geometry.global_transform * (geometry as VisualInstance3D).get_aabb()
		_bounds = box if not has else _bounds.merge(box)
		has = true
	_measured = true
	var spread := maxf(_bounds.size.x, _bounds.size.z) * 0.35
	_sparks.emission_box_extents = Vector3(spread, 1.0, spread)


# A reveal material carrying the look of `source` (a glTF import's StandardMaterial3D).
static func reveal_material(source: Material) -> ShaderMaterial:
	if source != null and _reveal_materials.has(source):
		return _reveal_materials[source]
	var material := ShaderMaterial.new()
	material.shader = REVEAL_SHADER
	if source is BaseMaterial3D:
		var base := source as BaseMaterial3D
		material.set_shader_parameter("albedo", base.albedo_color)
		if base.albedo_texture != null:
			material.set_shader_parameter("albedo_texture", base.albedo_texture)
		material.set_shader_parameter("use_vertex_color", base.vertex_color_use_as_albedo)
		material.set_shader_parameter("metallic", base.metallic)
		material.set_shader_parameter("roughness", base.roughness)
	else:
		material.set_shader_parameter("albedo", Color(0.8, 0.8, 0.8))
	if source != null:
		_reveal_materials[source] = material
	return material


static func _hologram() -> ShaderMaterial:
	if _hologram_material == null:
		_hologram_material = ShaderMaterial.new()
		_hologram_material.shader = HOLOGRAM_SHADER
	return _hologram_material


func _make_sparks() -> CPUParticles3D:
	if _spark_material == null:
		_spark_material = StandardMaterial3D.new()
		_spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spark_material.albedo_color = SPARK_COLOR
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 2.5
	mesh.material = _spark_material
	var sparks := CPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.mesh = mesh
	sparks.amount = 28
	sparks.lifetime = 0.55
	sparks.emitting = false
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparks.direction = Vector3.UP
	sparks.spread = 70.0
	sparks.initial_velocity_min = 40.0
	sparks.initial_velocity_max = 95.0
	sparks.gravity = Vector3(0.0, -260.0, 0.0)
	sparks.scale_amount_min = 0.6
	sparks.scale_amount_max = 1.3
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sparks
