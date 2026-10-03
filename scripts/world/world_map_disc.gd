class_name WorldMapDisc
extends Node3D

# The world map as a literal place: the flat-disc planet floating in space
# (docs/intro-story.md). One calm ocean sits inside an icy rim on a rocky, tapering underside;
# sea water spills off the edge into space, and clouds drift over the uncharted outer rings.
# Every island slot is drawn on the disc — generated islands as miniatures of their real
# terrain and buildings, undiscovered slots as a "?" in the mist — with the starter island (and
# the wreck) at the dead centre. Trade routes run across the water with their boats.
#
# Slots still live on the world hex lattice (WorldData keys islands by axial coord and trade
# trips are timed by hex distance); this only decides where on the disc each one is drawn.
# WorldMap owns the viewport and feeds mouse input in via orbit/zoom/slot_at_screen.

const StarfieldSkyShader := preload("res://assets/shaders/world_map/starfield_sky.gdshader")
const DiscOceanShader := preload("res://assets/shaders/world_map/disc_ocean.gdshader")
const WaterfallShader := preload("res://assets/shaders/world_map/waterfall.gdshader")
const SurfaceNoise := preload("res://assets/shaders/water_toon/PerlinNoise.png")
const HexGridScript := preload("res://scripts/island/hex_grid.gd")

# Disc units between rings; ring k's slots sit k * RING_SPACING from the centre.
const RING_SPACING := 11.0
# The disc is always at least this many rings wide, so the uncharted frontier reads as a big
# world still to explore; it grows if more rings than this are ever revealed.
const MIN_DISC_RINGS := 4
# Open sea beyond the outermost ring, in rings.
const DISC_MARGIN := 0.85
const RIM_SEGMENTS := 128
const WATERFALL_COUNT := 7
const CLOUD_COUNT := 11

# Island miniatures: hex width of one island cell, and each terrain's prism top height.
const MINI_CELL_WIDTH := 0.55
const MINI_BASE_Y := -0.4
const MINI_TOP_Y := {
	GameTypes.Terrain.SAND: 0.35,
	GameTypes.Terrain.GRASS: 0.6,
	GameTypes.Terrain.STONE: 0.9,
}
const MINI_COAST_Y := 0.04

const SLOT_PICK_RADIUS := 5.5
const LABEL_HEIGHT := 3.6

const SAND_COLOR := Color("#e3bc83")
const GRASS_COLOR := Color("#9ea131")
const STONE_COLOR := Color("#8e8791")
const COAST_COLOR := Color("#63c4c0")
const BUILDING_COLOR := Color("#efe2c4")
const WRECK_COLOR := Color("#3fb6a8")
const ICE_COLOR := Color("#e9f3f6")
const ICE_SHADOW_COLOR := Color("#a9cad8")
const SOIL_COLOR := Color("#7a4f33")
const ROCK_COLOR := Color("#7d5a41")
const ROCK_DEEP_COLOR := Color("#624533")
const CLOUD_COLOR := Color("#f4f6f8")
const MIST_COLOR := Color(0.85, 0.92, 0.96, 0.55)
const MARKER_COLOR := Color("#f4ead2")
const CURRENT_COLOR := Color("#f2c14e")
const ROUTE_COLOR := Color("#f4ead2")
const BOAT_HULL_COLOR := Color("#c8783c")
const BOAT_SAIL_COLOR := Color("#f4ead2")
const LABEL_COLOR := Color("#f7f1e3")
const LABEL_OUTLINE := Color("#15202e")

# Camera orbit limits and feel.
const PITCH_MIN := deg_to_rad(18.0)
const PITCH_MAX := deg_to_rad(82.0)
const DEFAULT_PITCH := deg_to_rad(30.0)
const CAMERA_SMOOTHING := 8.0

var world: WorldData

var _disc_radius := 0.0
var _charted_radius := -1.0
var _planet: Node3D
var _surface: Node3D
var _clouds: Node3D
var _islands: Node3D
var _routes: Node3D
var _ocean_material: ShaderMaterial
var _camera: Camera3D
var _time := 0.0

# coord -> {marker: MeshInstance3D, label: Label3D}
var _slot_nodes: Dictionary = {}
var _hovered := WorldData.NO_COORD
var _pin: Node3D
# One entry per trade route: {route: TradeRoute, boat: Node3D, start: Vector3, end: Vector3}
var _boats: Array[Dictionary] = []

var _yaw := -PI * 0.5
var _pitch := DEFAULT_PITCH
var _distance := 100.0
var _target_yaw := -PI * 0.5
var _target_pitch := DEFAULT_PITCH
var _target_distance := 100.0

var _shared_materials: Dictionary = {}


func setup(new_world: WorldData) -> void:
	world = new_world


func _ready() -> void:
	_build_environment()

	_planet = Node3D.new()
	_planet.name = "Planet"
	add_child(_planet)
	_surface = Node3D.new()
	_planet.add_child(_surface)
	_clouds = Node3D.new()
	_planet.add_child(_clouds)
	_islands = Node3D.new()
	_planet.add_child(_islands)
	_routes = Node3D.new()
	_planet.add_child(_routes)

	_camera = Camera3D.new()
	_camera.fov = 38.0
	_camera.near = 0.5
	_camera.far = 2000.0
	add_child(_camera)
	_camera.make_current()


# Rebuild everything that depends on world state: the disc size, the charted area, islands,
# routes. Cheap enough to run whenever the map opens or the world changes.
func refresh() -> void:
	if world == null or _planet == null:
		return

	var rings := maxi(MIN_DISC_RINGS, world.revealed_rings)
	var disc_radius := (rings + DISC_MARGIN) * RING_SPACING
	if not is_equal_approx(disc_radius, _disc_radius):
		_disc_radius = disc_radius
		_build_planet()
		_target_distance = _default_distance()
		_distance = _target_distance

	var charted_radius := (world.revealed_rings + 0.5) * RING_SPACING
	if not is_equal_approx(charted_radius, _charted_radius):
		_charted_radius = charted_radius
		_ocean_material.set_shader_parameter("charted_radius", _charted_radius)
		_build_clouds()

	_build_islands()
	_build_routes()


# Swoop the camera in from further out, as the map opens.
func play_intro() -> void:
	_distance = _target_distance * 1.45
	_pitch = clampf(_target_pitch + 0.35, PITCH_MIN, PITCH_MAX)
	_yaw = _target_yaw - 0.5


func orbit(relative: Vector2) -> void:
	_target_yaw += relative.x * 0.006
	_target_pitch = clampf(_target_pitch + relative.y * 0.004, PITCH_MIN, PITCH_MAX)


func zoom(factor: float) -> void:
	_target_distance = clampf(_target_distance * factor, _disc_radius * 1.0, _disc_radius * 4.0)


func reset_view() -> void:
	_target_yaw = -PI * 0.5
	_target_pitch = DEFAULT_PITCH
	_target_distance = _default_distance()


# The island slot under a screen point, or WorldData.NO_COORD.
func slot_at_screen(screen_position: Vector2) -> Vector2i:
	if world == null or _camera == null:
		return WorldData.NO_COORD

	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	var best := WorldData.NO_COORD
	var best_distance := SLOT_PICK_RADIUS
	for coord in world.island_slots():
		# Test against a point a little above the water so tall islands and their labels are
		# easy to hit from a low camera angle.
		var center := _planet.position + slot_position(coord) + Vector3(0.0, 0.6, 0.0)
		var distance := _ray_point_distance(origin, direction, center)
		if distance < best_distance:
			best_distance = distance
			best = coord
	return best


func set_hovered(coord: Vector2i) -> void:
	if coord == _hovered:
		return
	_set_slot_highlight(_hovered, false)
	_hovered = coord
	_set_slot_highlight(_hovered, true)


# Where a slot sits on the disc (planet-local, on the water plane).
static func slot_position(coord: Vector2i) -> Vector3:
	# Axial -> plane, scaled so a ring-1 slot is exactly RING_SPACING out.
	var x := sqrt(3.0) * (coord.x + coord.y * 0.5)
	var z := 1.5 * coord.y
	return Vector3(x, 0.0, z) * (RING_SPACING / sqrt(3.0))


func _process(delta: float) -> void:
	_time += delta

	# Ease the camera toward its target orbit.
	var blend := 1.0 - exp(-CAMERA_SMOOTHING * delta)
	_yaw = lerpf(_yaw, _target_yaw, blend)
	_pitch = lerpf(_pitch, _target_pitch, blend)
	_distance = lerpf(_distance, _target_distance, blend)
	var offset := Vector3(cos(_yaw) * cos(_pitch), sin(_pitch), sin(_yaw) * cos(_pitch)) * _distance
	var look_target := Vector3(0.0, -_disc_radius * 0.22, 0.0)
	_camera.position = look_target + offset
	_camera.look_at(look_target, Vector3.UP)

	# The planet floats: a slow bob, and the clouds drift around it.
	_planet.position.y = sin(_time * 0.6) * 0.35
	_clouds.rotation.y = _time * 0.012

	if _pin != null:
		_pin.position.y = LABEL_HEIGHT + 1.2 + sin(_time * 2.4) * 0.25
		_pin.rotation.y = _time * 1.2

	_update_boats()


# --- Environment ---

func _build_environment() -> void:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = StarfieldSkyShader
	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#7d93b5")
	environment.ambient_light_energy = 0.75
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	# A low, warm "sun" off to one side, so the rim and underside get a lit and a shadowed half.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#fff1dc")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.rotation = Vector3(deg_to_rad(-42.0), deg_to_rad(150.0), 0.0)
	add_child(sun)

	# The underside faces away from the sun; a dim, cool bounce from below keeps its rock
	# readable against the dark sky instead of vanishing into it.
	var bounce := DirectionalLight3D.new()
	bounce.light_color = Color("#8fa8d6")
	bounce.light_energy = 1.1
	bounce.rotation = Vector3(deg_to_rad(60.0), deg_to_rad(-30.0), 0.0)
	add_child(bounce)


# --- The planet: ocean, ice rim, rocky underside, waterfalls ---

func _build_planet() -> void:
	_clear(_surface)

	var ocean := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (_disc_radius * 2.0 + 2.0)
	ocean.mesh = plane
	_ocean_material = ShaderMaterial.new()
	_ocean_material.shader = DiscOceanShader
	_ocean_material.set_shader_parameter("disc_radius", _disc_radius)
	_ocean_material.set_shader_parameter("ring_spacing", RING_SPACING)
	_ocean_material.set_shader_parameter("surface_noise", SurfaceNoise)
	ocean.material_override = _ocean_material
	# The plane is square; the shader discards everything outside the disc.
	_ocean_material.set_shader_parameter("charted_radius", _charted_radius)
	_surface.add_child(ocean)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_surface.add_child(_build_ice_rim(rng))
	_surface.add_child(_build_underside(rng))
	for i in range(WATERFALL_COUNT):
		var angle := TAU * (float(i) + rng.randf_range(0.15, 0.85)) / WATERFALL_COUNT
		_surface.add_child(_build_waterfall(angle, rng.randf_range(0.8, 1.6), float(i)))


func _build_ice_rim(rng: RandomNumberGenerator) -> MeshInstance3D:
	var r := _disc_radius
	var profile: Array[Vector2] = [
		Vector2(r - 1.2, -0.6),
		Vector2(r - 0.9, 0.8),
		Vector2(r - 0.3, 1.9),
		Vector2(r + 0.7, 2.3),
		Vector2(r + 1.7, 1.8),
		Vector2(r + 2.2, 0.4),
		Vector2(r + 2.0, -1.2),
	]
	var colors: Array[Color] = [
		ICE_SHADOW_COLOR, ICE_COLOR, ICE_COLOR, ICE_COLOR, ICE_COLOR, ICE_SHADOW_COLOR, ICE_SHADOW_COLOR,
	]
	# Snow drifts: the crest wobbles a little in height around the rim.
	var jitter := _lathe_jitter(rng, profile.size(), 0.0)
	for segment in range(RIM_SEGMENTS):
		var wobble := sin(segment * 0.37) * 0.12 + sin(segment * 1.13 + 2.0) * 0.08
		for row in [2, 3, 4]:
			jitter[row][segment] = Vector2(0.0, wobble * (1.0 if row == 3 else 0.6))
	var mesh := _lathe(profile, colors, jitter, true)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _vertex_color_material(0.55)
	return instance


func _build_underside(rng: RandomNumberGenerator) -> MeshInstance3D:
	var r := _disc_radius
	# A deep bowl: steep walls under the rim, then rounding into a craggy point, so the
	# underside reads from the usual three-quarter view rather than hiding behind the ice.
	var depth := r * 0.8
	var profile: Array[Vector2] = [
		Vector2(r + 1.9, -0.9),
		Vector2(r + 1.7, -depth * 0.1),
		Vector2(r + 0.6, -depth * 0.22),
		Vector2(r * 0.96, -depth * 0.36),
		Vector2(r * 0.86, -depth * 0.5),
		Vector2(r * 0.7, -depth * 0.64),
		Vector2(r * 0.5, -depth * 0.78),
		Vector2(r * 0.28, -depth * 0.9),
		Vector2(r * 0.09, -depth * 0.98),
		Vector2(0.0, -depth),
	]
	var colors: Array[Color] = [
		SOIL_COLOR, SOIL_COLOR, ROCK_COLOR, ROCK_COLOR.lightened(0.08), ROCK_COLOR,
		ROCK_DEEP_COLOR.lightened(0.06), ROCK_DEEP_COLOR, ROCK_DEEP_COLOR, ROCK_DEEP_COLOR,
		ROCK_DEEP_COLOR,
	]
	var jitter := _lathe_jitter(rng, profile.size(), r * 0.045)
	# Keep the top edge tucked under the ice and the tip closed.
	for segment in range(RIM_SEGMENTS):
		jitter[0][segment] = Vector2.ZERO
		jitter[profile.size() - 1][segment] = Vector2.ZERO
	var instance := MeshInstance3D.new()
	instance.mesh = _lathe(profile, colors, jitter, false)
	instance.material_override = _vertex_color_material(1.0)
	return instance


func _build_waterfall(angle: float, width: float, fall_seed: float) -> MeshInstance3D:
	var outward := Vector3(cos(angle), 0.0, sin(angle))
	var tangent := Vector3(-sin(angle), 0.0, cos(angle))
	var r := _disc_radius
	var fall := r * 0.6
	var steps := 14

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array[Vector3] = []
	for i in range(steps + 1):
		var t := float(i) / steps
		# Spill over the crest, then fall with a gentle outward arc.
		var spill := clampf(t * 6.0, 0.0, 1.0)
		var out := r + 1.0 + spill * 1.6 + t * t * 2.5
		var y := 2.1 - spill * 1.6 - t * fall
		rows.append(outward * out + Vector3(0.0, y, 0.0))
	for i in range(steps):
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var a0 := rows[i] - tangent * width * 0.5
		var b0 := rows[i] + tangent * width * 0.5
		var a1 := rows[i + 1] - tangent * width * 0.5
		var b1 := rows[i + 1] + tangent * width * 0.5
		for vertex in [[a0, Vector2(0, t0)], [b0, Vector2(1, t0)], [b1, Vector2(1, t1)],
				[a0, Vector2(0, t0)], [b1, Vector2(1, t1)], [a1, Vector2(0, t1)]]:
			st.set_uv(vertex[1])
			st.add_vertex(vertex[0])

	var material := ShaderMaterial.new()
	material.shader = WaterfallShader
	material.set_shader_parameter("seed", fall_seed)
	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


# Revolve `profile` (x = radius, y = height) around the Y axis. `jitter[row][segment]` nudges
# each vertex (x = radius offset, y = height offset) for a rocky or drifted look.
func _lathe(profile: Array[Vector2], colors: Array[Color], jitter: Array, smooth: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0 if smooth else -1)

	var points := []
	for row in range(profile.size()):
		var ring := []
		for segment in range(RIM_SEGMENTS):
			var angle := TAU * segment / RIM_SEGMENTS
			var offset: Vector2 = jitter[row][segment]
			var radius := maxf(profile[row].x + offset.x, 0.0)
			ring.append(Vector3(cos(angle) * radius, profile[row].y + offset.y, sin(angle) * radius))
		points.append(ring)

	for row in range(profile.size() - 1):
		for segment in range(RIM_SEGMENTS):
			var next := (segment + 1) % RIM_SEGMENTS
			var a: Vector3 = points[row][segment]
			var b: Vector3 = points[row][next]
			var c: Vector3 = points[row + 1][segment]
			var d: Vector3 = points[row + 1][next]
			var top_color := colors[row]
			var bottom_color := colors[row + 1]
			for vertex in [[a, top_color], [b, top_color], [d, bottom_color],
					[a, top_color], [d, bottom_color], [c, bottom_color]]:
				st.set_color(vertex[1])
				st.add_vertex(vertex[0])

	st.generate_normals()
	return st.commit()


func _lathe_jitter(rng: RandomNumberGenerator, rows: int, amount: float) -> Array:
	var jitter := []
	for row in range(rows):
		var ring := []
		for segment in range(RIM_SEGMENTS):
			ring.append(Vector2(rng.randf_range(-amount, amount), rng.randf_range(-amount, amount) * 0.4))
		jitter.append(ring)
	return jitter


# --- Clouds over the uncharted sea ---

func _build_clouds() -> void:
	_clear(_clouds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var material := _flat_material(CLOUD_COLOR, 1.0)
	var min_radius := clampf(_charted_radius + RING_SPACING * 0.6, _disc_radius * 0.3, _disc_radius * 0.8)
	var max_radius := _disc_radius * 0.96
	for i in range(CLOUD_COUNT):
		var angle := TAU * (float(i) + rng.randf_range(0.0, 0.7)) / CLOUD_COUNT
		var radius := rng.randf_range(min_radius, max_radius)
		var cluster := _make_puff_cluster(rng, material, rng.randi_range(3, 5), rng.randf_range(1.2, 2.2))
		cluster.position = Vector3(cos(angle) * radius, rng.randf_range(4.0, 7.0), sin(angle) * radius)
		cluster.rotation.y = rng.randf() * TAU
		_clouds.add_child(cluster)


func _make_puff_cluster(rng: RandomNumberGenerator, material: Material, count: int, puff_scale: float) -> Node3D:
	var cluster := Node3D.new()
	for i in range(count):
		var puff := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		var radius := puff_scale * rng.randf_range(0.7, 1.15)
		sphere.radius = radius
		sphere.height = radius * 2.0
		sphere.radial_segments = 16
		sphere.rings = 8
		puff.mesh = sphere
		puff.material_override = material
		# Shadows from clouds read as dark holes in the calm sea, not as cloud shade.
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.position = Vector3(
			(i - count * 0.5 + 0.5) * puff_scale * 0.95,
			rng.randf_range(-0.2, 0.4) * puff_scale,
			rng.randf_range(-0.5, 0.5) * puff_scale
		)
		puff.scale = Vector3(1.0, 0.68, 1.0)
		cluster.add_child(puff)
	return cluster


# --- Island slots ---

func _build_islands() -> void:
	_clear(_islands)
	_slot_nodes.clear()
	_pin = null

	for coord in world.island_slots():
		var slot := Node3D.new()
		slot.position = slot_position(coord)
		_islands.add_child(slot)

		var is_current := world.has_island(coord) and coord == world.current_coord
		var label_text := "?"
		var extent := 3.6
		if world.has_island(coord):
			var island := world.get_island(coord)
			var mini := _build_island_mini(island)
			slot.add_child(mini)
			extent = mini.get_meta("extent", extent)
			label_text = island.island_name
		else:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(coord)
			var mist := _make_puff_cluster(rng, _flat_material(MIST_COLOR, 1.0, true), 3, 1.7)
			mist.position.y = 0.9
			slot.add_child(mist)

		var marker := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = extent + 0.5
		torus.outer_radius = extent + 0.8
		torus.rings = 48
		torus.ring_segments = 6
		marker.mesh = torus
		marker.material_override = _flat_material(CURRENT_COLOR if is_current else MARKER_COLOR, 0.0)
		marker.position.y = 0.05
		marker.scale = Vector3(1.0, 0.35, 1.0)
		marker.visible = is_current
		slot.add_child(marker)

		var label := Label3D.new()
		label.text = label_text
		label.font_size = 104 if label_text == "?" else 72
		label.pixel_size = 0.03
		label.outline_size = 16
		label.modulate = LABEL_COLOR
		label.outline_modulate = LABEL_OUTLINE
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.render_priority = 10
		label.outline_render_priority = 9
		label.position.y = LABEL_HEIGHT
		slot.add_child(label)

		if is_current:
			_pin = _make_pin()
			slot.add_child(_pin)

		_slot_nodes[coord] = {marker = marker, label = label, current = is_current}

	_set_slot_highlight(_hovered, true)


func _set_slot_highlight(coord: Vector2i, on: bool) -> void:
	if not _slot_nodes.has(coord):
		return
	var nodes: Dictionary = _slot_nodes[coord]
	var marker: MeshInstance3D = nodes.marker
	var label: Label3D = nodes.label
	marker.visible = on or nodes.current
	label.scale = Vector3.ONE * (1.2 if on else 1.0)
	label.modulate = CURRENT_COLOR if on else LABEL_COLOR


# The island's real terrain as a tiny hex-prism model, centred on its land, with a turquoise
# shelf of coast cells around it and a block for each building (teal for the wreck).
func _build_island_mini(island: IslandData) -> Node3D:
	var root := Node3D.new()
	var cell_size := Vector2(MINI_CELL_WIDTH, MINI_CELL_WIDTH * 2.0 / sqrt(3.0))

	var land: Array[Vector2i] = []
	var coast: Array[Vector2i] = []
	for cell in island.terrain:
		var terrain: int = island.terrain[cell]
		if MINI_TOP_Y.has(terrain):
			land.append(cell)
		elif terrain == GameTypes.Terrain.COAST:
			coast.append(cell)
	if land.is_empty():
		return root

	var min_xz := Vector2(INF, INF)
	var max_xz := Vector2(-INF, -INF)
	for cell in land:
		var center := HexGridScript.cell_center_3d(cell, cell_size)
		min_xz = min_xz.min(Vector2(center.x, center.z))
		max_xz = max_xz.max(Vector2(center.x, center.z))
	var mid := (min_xz + max_xz) * 0.5
	var origin := Vector3(-mid.x, 0.0, -mid.y)
	root.set_meta("extent", 0.5 * maxf(max_xz.x - min_xz.x, max_xz.y - min_xz.y) + MINI_CELL_WIDTH)

	var prism := _hex_prism_mesh(cell_size)
	var land_multimesh := _prism_multimesh(prism, land.size())
	for i in range(land.size()):
		var cell := land[i]
		var terrain: int = island.terrain[cell]
		var top: float = MINI_TOP_Y[terrain]
		var pos := HexGridScript.cell_center_3d(cell, cell_size) + origin
		pos.y = MINI_BASE_Y
		land_multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1.0, top - MINI_BASE_Y, 1.0)), pos))
		land_multimesh.set_instance_color(i, _terrain_color(terrain))
	root.add_child(_multimesh_instance(land_multimesh))

	if not coast.is_empty():
		var coast_multimesh := _prism_multimesh(prism, coast.size())
		for i in range(coast.size()):
			var pos := HexGridScript.cell_center_3d(coast[i], cell_size) + origin
			pos.y = MINI_BASE_Y
			coast_multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1.0, MINI_COAST_Y - MINI_BASE_Y, 1.0)), pos))
			coast_multimesh.set_instance_color(i, COAST_COLOR)
		var coast_instance := _multimesh_instance(coast_multimesh)
		coast_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(coast_instance)

	for anchor in island.buildings:
		var building: Dictionary = island.buildings[anchor]
		var is_wreck: bool = building.type == GameTypes.BuildingType.CRASHED_SPACESHIP
		var footprint: Array = building.get("cells", [anchor])
		var center := Vector3.ZERO
		for cell in footprint:
			center += HexGridScript.cell_center_3d(cell, cell_size)
		center /= maxf(footprint.size(), 1)
		var terrain := island.get_terrain(anchor)
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		var footprint_size := MINI_CELL_WIDTH * (1.3 if is_wreck else 0.62) * sqrt(float(footprint.size()))
		mesh.size = Vector3(footprint_size, footprint_size * (0.8 if is_wreck else 0.9), footprint_size)
		box.mesh = mesh
		box.material_override = _flat_material(WRECK_COLOR if is_wreck else BUILDING_COLOR, 0.8)
		var ground: float = MINI_TOP_Y.get(terrain, MINI_TOP_Y[GameTypes.Terrain.GRASS])
		box.position = center + origin + Vector3(0.0, ground + mesh.size.y * 0.5, 0.0)
		box.rotation.y = 0.5 if is_wreck else 0.0
		root.add_child(box)

	return root


func _prism_multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = count
	return multimesh


func _multimesh_instance(multimesh: MultiMesh) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = _vertex_color_material(0.9)
	return instance


# Unit-height hex prism (y 0..1) with flat per-face normals, like the island renderer's tiles.
func _hex_prism_mesh(cell_size: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := HexGridScript.hex_corners_3d(Vector3(0.0, 1.0, 0.0), cell_size)
	var bottom := HexGridScript.hex_corners_3d(Vector3.ZERO, cell_size)

	st.set_normal(Vector3.UP)
	for i in range(6):
		st.add_vertex(Vector3(0.0, 1.0, 0.0))
		st.add_vertex(top[i])
		st.add_vertex(top[(i + 1) % 6])
	for i in range(6):
		var b0 := bottom[i]
		var b1 := bottom[(i + 1) % 6]
		var t0 := top[i]
		var t1 := top[(i + 1) % 6]
		var mid := (b0 + b1) * 0.5
		st.set_normal(Vector3(mid.x, 0.0, mid.z).normalized())
		for vertex in [b0, b1, t1, b0, t1, t0]:
			st.add_vertex(vertex)
	return st.commit()


func _make_pin() -> Node3D:
	var pin := Node3D.new()
	var cone := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.55
	mesh.bottom_radius = 0.0
	mesh.height = 1.1
	mesh.radial_segments = 4
	mesh.rings = 1
	cone.mesh = mesh
	cone.material_override = _flat_material(CURRENT_COLOR, 0.6)
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pin.add_child(cone)
	pin.position.y = LABEL_HEIGHT + 1.2
	return pin


# --- Trade routes ---

func _build_routes() -> void:
	_clear(_routes)
	_boats.clear()
	if world.trade_routes.is_empty():
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for route in world.trade_routes:
		var home := slot_position(route.home_coord)
		var away := slot_position(route.away_coord)
		var direction := (away - home).normalized()
		var side := direction.cross(Vector3.UP) * 0.14
		var start := home + direction * 3.2
		var end := away - direction * 3.2
		var length := start.distance_to(end)
		var dash := 0.9
		var along := 0.0
		while along < length:
			var a := start + direction * along
			var b := start + direction * minf(along + dash, length)
			a.y = 0.06
			b.y = 0.06
			for vertex in [a - side, b - side, b + side, a - side, b + side, a + side]:
				st.set_normal(Vector3.UP)
				st.add_vertex(vertex)
			along += dash * 1.9

		var boat := _make_boat()
		_routes.add_child(boat)
		_boats.append({route = route, boat = boat, start = start, end = end})

	var dashes := MeshInstance3D.new()
	dashes.mesh = st.commit()
	dashes.material_override = _flat_material(ROUTE_COLOR, 0.0, false, true)
	dashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_routes.add_child(dashes)
	_update_boats()


func _update_boats() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for entry in _boats:
		var route: TradeRoute = entry.route
		var start: Vector3 = entry.start
		var end: Vector3 = entry.end
		var t := 0.0
		var heading := end - start
		match route.phase:
			TradeRoute.Phase.OUTBOUND:
				t = route.phase_progress(now)
			TradeRoute.Phase.RETURNING:
				t = 1.0 - route.phase_progress(now)
				heading = -heading
		var boat: Node3D = entry.boat
		boat.position = start.lerp(end, t) + Vector3(0.0, 0.1 + sin(_time * 3.0 + t * 20.0) * 0.05, 0.0)
		boat.rotation.y = atan2(-heading.z, heading.x)
		boat.rotation.z = sin(_time * 2.2 + t * 13.0) * 0.08


func _make_boat() -> Node3D:
	var boat := Node3D.new()
	var hull := MeshInstance3D.new()
	var hull_mesh := BoxMesh.new()
	hull_mesh.size = Vector3(1.1, 0.3, 0.5)
	hull.mesh = hull_mesh
	hull.material_override = _flat_material(BOAT_HULL_COLOR, 0.8)
	hull.position.y = 0.15
	boat.add_child(hull)
	var sail := MeshInstance3D.new()
	var sail_mesh := PrismMesh.new()
	sail_mesh.size = Vector3(0.6, 0.8, 0.06)
	sail.mesh = sail_mesh
	sail.material_override = _flat_material(BOAT_SAIL_COLOR, 0.8)
	sail.position = Vector3(0.05, 0.7, 0.0)
	boat.add_child(sail)
	return boat


# --- Helpers ---

func _default_distance() -> float:
	return _disc_radius * 2.7


func _terrain_color(terrain: int) -> Color:
	match terrain:
		GameTypes.Terrain.GRASS:
			return GRASS_COLOR
		GameTypes.Terrain.SAND:
			return SAND_COLOR
		_:
			return STONE_COLOR


func _vertex_color_material(roughness: float) -> StandardMaterial3D:
	var key := "vc_%s" % roughness
	if not _shared_materials.has(key):
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = true
		material.roughness = roughness
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shared_materials[key] = material
	return _shared_materials[key]


func _flat_material(color: Color, roughness: float, transparent: bool = false, unshaded: bool = false) -> StandardMaterial3D:
	var key := "flat_%s_%s_%s_%s" % [color.to_html(), roughness, transparent, unshaded]
	if not _shared_materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = roughness
		if transparent or color.a < 1.0:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if unshaded:
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shared_materials[key] = material
	return _shared_materials[key]


func _ray_point_distance(origin: Vector3, direction: Vector3, point: Vector3) -> float:
	var along := (point - origin).dot(direction)
	if along < 0.0:
		return INF
	return (origin + direction * along).distance_to(point)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
