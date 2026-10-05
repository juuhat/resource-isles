class_name PowerIndicator
extends Node3D

# Red lightning bolt floating above a power-consuming building, shown while the building is
# unpowered. Like BladeSpinner, each indicator drives itself: it polls its island's powered
# flag (set every frame by PowerManager, including the robot's Operate hand-power) so the
# renderer needs no per-frame loop, and it is freed with the objects on the next re-render.
# The bolt stays screen-aligned with the camera so its face is always readable.

const BOLT_MODEL := preload("res://assets/models/ui/power_bolt.glb")
const BOLT_COLOR := Color("#e8261b")
const OUTLINE_COLOR := Color("#3a0906")
const BOB_HEIGHT := 4.0
const BOB_SPEED := 2.4
const POP_SPEED := 10.0
const SWAY_RADIANS := 0.35

static var _material: StandardMaterial3D
static var _outline_material: StandardMaterial3D

var island: IslandData
var anchor_cell := GameTypes.NO_CELL
var _bolt: Node3D
# Distance from this node (placed on the roof's top point) to the bolt's centre, along the
# camera's screen-up axis, so the bolt's tip clears the roof on screen at any camera pitch.
var _lift := 0.0
var _phase := 0.0
var _pop := 0.0


# height is the bolt's on-screen height and gap the clearance below its tip, in world units.
func setup(new_island: IslandData, new_anchor_cell: Vector2i, height: float, gap: float) -> void:
	island = new_island
	anchor_cell = new_anchor_cell
	_lift = height * 0.5 + gap
	_bolt = BOLT_MODEL.instantiate() as Node3D
	_bolt.scale = Vector3.ONE * height
	_apply_material(_bolt)
	add_child(_bolt)
	# Stagger the bob so a row of unpowered buildings doesn't move in lockstep.
	_phase = float(absi(anchor_cell.x * 7 + anchor_cell.y * 13) % 17)
	visible = _is_unpowered()


func _process(delta: float) -> void:
	var unpowered := _is_unpowered()
	if not unpowered:
		visible = false
		_pop = 0.0
		return

	if not visible:
		visible = true
	_pop = minf(_pop + delta * POP_SPEED, 1.0)
	_phase += delta * BOB_SPEED
	_bolt.position.y = _lift + sin(_phase) * BOB_HEIGHT
	# A gentle sway shows off the bolt's thickness without ever turning it edge-on.
	_bolt.rotation.y = sin(_phase * 0.5) * SWAY_RADIANS

	# Screen-aligned: copy the camera's orientation so the bolt's face (+Z) points back at the
	# viewer at every zoom pitch, from the low hero angle to near top-down.
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		global_basis = camera.global_basis.orthonormalized()
	# Slight overshoot on appearing so the warning catches the eye once, then settles.
	scale = Vector3.ONE * (1.0 + sin(_pop * PI) * 0.25)


func _is_unpowered() -> bool:
	return island != null and island.buildings.has(anchor_cell) and not island.is_consumer_powered(anchor_cell)


static func _apply_material(root: Node) -> void:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = BOLT_COLOR
		_material.roughness = 1.0
		_material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		# A little self-glow keeps the red saturated on the shadowed side and at dusk tones.
		_material.emission_enabled = true
		_material.emission = BOLT_COLOR
		_material.emission_energy_multiplier = 0.35

		# The model's "Power bolt outline" shell encloses the bolt; drawing only its back faces
		# leaves a dark rim around the silhouette (see tools/build_power_bolt.py).
		_outline_material = StandardMaterial3D.new()
		_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline_material.albedo_color = OUTLINE_COLOR
		_outline_material.cull_mode = BaseMaterial3D.CULL_FRONT

	var stack: Array = [root]
	while stack.size() > 0:
		var node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is MeshInstance3D:
			var is_outline := String(node.name).to_lower().contains("outline")
			node.material_override = _outline_material if is_outline else _material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
