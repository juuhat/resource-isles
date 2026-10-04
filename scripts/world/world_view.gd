class_name WorldView
extends Node3D

# The whole world as one place: the flat-disc planet floating in space (docs/intro-story.md),
# with every island at full scale on it. One calm ocean sits inside a snow-capped mountain range on a rocky,
# tapering underside; sea water spills off the edge into the starfield. Each revealed island has
# its own IslandRenderer standing on its slot, and the rings not yet revealed sit under thick
# soft fog that fades when a ring is revealed. Unvisited islands show muted coastlines;
# landing restores their full detail. Trade routes run across the open sea with their
# boats, and island names float over the slots once the camera pulls back.
#
# Slots live on the world hex lattice (WorldData keys islands by axial coord and trade trips are
# timed by hex distance); this decides where each one sits in world space. The planet itself is
# authored in small "disc units" (one ring = DISC_UNIT) and scaled up into the world; islands,
# clouds, labels and routes are placed directly in world units. main.gd owns the camera and
# routes picks through slot_at_ray.

const IslandRendererScript := preload("res://scripts/island/island_renderer.gd")
const Navigation := preload("res://scripts/world/world_navigation.gd")
const FrontierFogShader := preload("res://assets/shaders/world_map/frontier_fog.gdshader")
const DiscOceanShader := preload("res://assets/shaders/world_map/disc_ocean.gdshader")
const WaterfallShader := preload("res://assets/shaders/world_map/waterfall.gdshader")
const IslandFogShader := preload("res://assets/shaders/world_map/island_fog.gdshader")
const SurfaceNoise := preload("res://assets/shaders/water_toon/PerlinNoise.png")
const DistortNoise := preload("res://assets/shaders/water_toon/WaterDistortion.png")

# World units between rings; ring k's slots sit k * RING_SPACING from the centre. Islands are
# ~30 x 24 cells of 128 units, so this leaves a wide strait between neighbours.
const RING_SPACING := 6400.0
# The planet's geometry is authored at one ring = DISC_UNIT and scaled up by DISC_SCALE.
const DISC_UNIT := 11.0
const DISC_SCALE := RING_SPACING / DISC_UNIT
# Open sea beyond the outermost ring, in rings.
const DISC_MARGIN := 0.85
# World height of the open sea: just under the islands' own seabed tiles (IslandRenderer
# WATER_FLOOR_Y), so it only shows where an island's toon water has faded out.
const SEA_LEVEL_Y := -10.0
const RIM_SEGMENTS := 128
# The mountain range ringing the sea runs from its foothills under the shallows (RANGE_INNER) out
# to the cliff edge over the underside (RANGE_OUTER), in disc units from the ocean's edge.
const RANGE_INNER := -2.2
const RANGE_OUTER := 3.4
const RANGE_ROWS := 10
# The range's outer edge hangs this low, overlapping the top of the underside so no seam shows.
const RANGE_EDGE_Y := -1.8
# Rows of the craggy cliff below that edge: x = radius offset from RANGE_OUTER, y = height.
const RANGE_SKIRT: Array[Vector2] = [Vector2(-0.1, -3.2), Vector2(-0.35, -5.2)]
# The passes the waterfalls run out through sit this high above the sea.
const PASS_FLOOR := 0.12
const WATERFALL_COUNT := 7
const CLOUD_COUNT := 4

# A ground point within this distance of a slot centre belongs to that slot's island.
const ISLAND_PICK_RADIUS := 2700.0
# Cloud banks cover roughly an island's footprint.
const FOG_BANK_RADIUS := 3000.0
const FOG_LIFT_SECONDS := 1.8
const LABEL_HEIGHT := 900.0
# Trade lanes start/end this far out from each slot centre, clear of the island.
const ROUTE_CLEARANCE := 2600.0
const ROUTE_Y := 8.0

const CLOUD_COLOR := Color("#f4f6f8")
const SNOW_COLOR := Color("#e9f3f6")
const SNOW_SHADOW_COLOR := Color("#a9c3d4")
const MOUNTAIN_ROCK_COLOR := Color("#6b5d53")
const MOUNTAIN_HIGH_ROCK_COLOR := Color("#8e8a88")
const FOOTHILL_COLOR := Color("#5f6d4b")
const SOIL_COLOR := Color("#7a4f33")
const ROCK_COLOR := Color("#7d5a41")
const ROCK_DEEP_COLOR := Color("#624533")
const CURRENT_COLOR := Color("#f2c14e")
const ROUTE_COLOR := Color("#f4ead2")
const BOAT_HULL_COLOR := Color("#c8783c")
const BOAT_SAIL_COLOR := Color("#f4ead2")
const LABEL_COLOR := Color("#f7f1e3")
const UNCHARTED_LABEL_COLOR := Color("#c9d6df")
const LABEL_OUTLINE := Color("#15202e")

# Render layer for the planet's rim and underside, so only they catch the bounce light.
const PLANET_LAYER := 2

var world: WorldData
var resource_node_database: ResourceNodeDatabase
var building_manager: BuildingManager

var _disc_radius := 0.0 # disc units
var _charted_radius := -1.0 # disc units
var _planet: Node3D
var _surface: Node3D
var _clouds: Node3D
var _islands: Node3D
var _fog: Node3D
var _frontier_fog: MeshInstance3D
var _sailing_hover: MeshInstance3D
var _labels_root: Node3D
var _routes: Node3D
var _ocean_material: ShaderMaterial
var _time := 0.0
var _show_grid := true
var _overview := 0.0

# coord -> IslandRenderer, for every revealed island.
var _renderers: Dictionary = {}
# coord -> Node3D cloud bank, for every slot still hidden.
var _fog_banks: Dictionary = {}
# coord -> Label3D
var _labels: Dictionary = {}
var _hovered := WorldData.NO_COORD
# One entry per trade route: {route: TradeRoute, boat: Node3D, start: Vector3, end: Vector3}
var _boats: Array[Dictionary] = []

var _shared_materials: Dictionary = {}


func setup(
	new_world: WorldData,
	new_resource_node_database: ResourceNodeDatabase,
	new_building_manager: BuildingManager
) -> void:
	world = new_world
	resource_node_database = new_resource_node_database
	building_manager = new_building_manager


func _ready() -> void:
	_add_bounce_light()

	_planet = Node3D.new()
	_planet.name = "Planet"
	_planet.position.y = SEA_LEVEL_Y
	_planet.scale = Vector3.ONE * DISC_SCALE
	add_child(_planet)
	_surface = Node3D.new()
	_planet.add_child(_surface)
	_clouds = Node3D.new()
	_planet.add_child(_clouds)

	_islands = Node3D.new()
	_islands.name = "Islands"
	add_child(_islands)
	_fog = Node3D.new()
	_fog.name = "Fog"
	add_child(_fog)
	_labels_root = Node3D.new()
	_labels_root.name = "Labels"
	add_child(_labels_root)
	_routes = Node3D.new()
	_routes.name = "Routes"
	add_child(_routes)


# Bring everything in line with world state: the disc size and charted area, a renderer for every
# revealed island, cloud banks over the rest (lifting any whose ring was just revealed), labels
# and routes. Islands already rendered are left alone, so this is cheap to call after any change.
func refresh() -> void:
	if world == null or _planet == null:
		return

	var disc_radius := (world.world_rings() + DISC_MARGIN) * DISC_UNIT
	if not is_equal_approx(disc_radius, _disc_radius):
		_disc_radius = disc_radius
		_build_planet()

	var charted_radius := (world.revealed_rings + 0.5) * DISC_UNIT
	if not is_equal_approx(charted_radius, _charted_radius):
		_charted_radius = charted_radius
		_ocean_material.set_shader_parameter("charted_radius", _charted_radius)
		_build_clouds()
		_build_frontier_fog()

	_sync_islands()
	_build_labels()
	_build_routes()


# The renderer drawing the island at `coord`, or null if it is not revealed (or not generated).
func renderer_for(coord: Vector2i) -> IslandRenderer:
	return _renderers.get(coord)


func show_sailing_hover(point: Vector3, color: Color) -> void:
	if _sailing_hover == null:
		_sailing_hover = MeshInstance3D.new()
		add_child(_sailing_hover)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var ring := HexGrid.hex_corners_3d(Vector3.ZERO, Navigation.CELL_SIZE)
		for index in 6:
			for vertex in [Vector3.ZERO, ring[index], ring[(index + 1) % 6]]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(vertex)
		_sailing_hover.mesh = surface.commit()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_sailing_hover.material_override = material
	_sailing_hover.position = point + Vector3.UP * 0.7
	_sailing_hover.material_override.albedo_color = color
	_sailing_hover.visible = true


func hide_sailing_hover() -> void:
	if _sailing_hover != null:
		_sailing_hover.visible = false


# The foot of this continuous fog bank shares WorldNavigation's sailing boundary.
func _build_frontier_fog() -> void:
	if _frontier_fog != null:
		_frontier_fog.free()
	_frontier_fog = MeshInstance3D.new()
	_frontier_fog.name = "SailingFrontierFog"
	_fog.add_child(_frontier_fog)
	var radius := (world.revealed_rings + 0.5) * RING_SPACING
	var rings := [Vector2(radius - 128.0, Navigation.SEA_Y), Vector2(radius + 192.0, 420.0), Vector2(world_disc_radius(), 420.0)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for band in range(rings.size() - 1):
		for segment in 192:
			var a := TAU * segment / 192.0
			var b := TAU * (segment + 1) / 192.0
			var points: Array[Vector3] = []
			for ring in [rings[band], rings[band + 1]]:
				for angle in [a, b]:
					points.append(Vector3(cos(angle) * ring.x, ring.y, sin(angle) * ring.x))
			for index in [0, 2, 1, 1, 2, 3]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(points[index])
	_frontier_fog.mesh = surface.commit()
	_frontier_fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = FrontierFogShader
	material.set_shader_parameter("frontier_radius", radius)
	material.set_shader_parameter("cloud_noise", DistortNoise)
	_frontier_fog.material_override = material


func set_show_grid(value: bool) -> void:
	_show_grid = value
	for coord in _renderers:
		(_renderers[coord] as IslandRenderer).set_show_grid(value)


# 0 while playing, 1 in the full-disc overview (the camera's zoom). Fades in the navigator's
# chart on the sea and the island labels.
func set_overview_amount(amount: float) -> void:
	if is_equal_approx(amount, _overview):
		return
	_overview = amount
	if _ocean_material != null:
		_ocean_material.set_shader_parameter("chart_visibility", _chart_visibility())
	_apply_label_fade()


# The chart stays off the sea until the camera is well into the overview.
func _chart_visibility() -> float:
	return clampf((_overview - 0.5) / 0.4, 0.0, 1.0)


# Where the overview camera looks and how far back it sits to frame the whole disc.
func overview_pivot() -> Vector3:
	return Vector3(0.0, SEA_LEVEL_Y - world_disc_radius() * 0.22, 0.0)


func overview_distance() -> float:
	return world_disc_radius() * 2.6


func world_disc_radius() -> float:
	return _disc_radius * DISC_SCALE


# The slot whose island lies under a camera ray (any slot, revealed or not), or NO_COORD when
# the ray meets open sea.
func slot_at_ray(origin: Vector3, direction: Vector3) -> Vector2i:
	if world == null or absf(direction.y) < 0.00001:
		return WorldData.NO_COORD
	var t := (IslandRendererScript.WATER_TOP_Y - origin.y) / direction.y
	if t < 0.0:
		return WorldData.NO_COORD
	var hit := origin + direction * t
	var best := WorldData.NO_COORD
	var best_distance := ISLAND_PICK_RADIUS
	for coord in world.all_slots():
		var center := slot_position(coord)
		var distance := Vector2(hit.x - center.x, hit.z - center.z).length()
		if distance < best_distance:
			best_distance = distance
			best = coord
	return best


func set_hovered(coord: Vector2i) -> void:
	if coord == _hovered:
		return
	_hovered = coord
	_style_labels()


func set_current_coord(_coord: Vector2i) -> void:
	for coord in _renderers:
		(_renderers[coord] as IslandRenderer).set_explored(world.get_island(coord).visited or world.get_island(coord).sighted)
	_style_labels()


# Where a slot sits in the world (on the water plane).
static func slot_position(coord: Vector2i) -> Vector3:
	var center := Navigation.slot_center(coord)
	center.y = 0.0
	return center


func _process(delta: float) -> void:
	_time += delta
	if _clouds != null:
		_clouds.rotation.y = _time * 0.004
	_update_boats()


# --- Islands and the cloud banks over unrevealed rings ---

func _sync_islands() -> void:
	for coord in world.all_slots():
		var island := world.get_island(coord)
		if island != null and world.is_revealed(coord):
			if not _renderers.has(coord):
				_add_renderer(coord, island)
			(_renderers[coord] as IslandRenderer).set_explored(island.visited or island.sighted)
			if _fog_banks.has(coord):
				_lift_fog_bank(coord)
		elif not _fog_banks.has(coord):
			var bank := _make_fog_bank(coord)
			_fog.add_child(bank)
			_fog_banks[coord] = bank


func _add_renderer(coord: Vector2i, island: IslandData) -> void:
	var renderer: IslandRenderer = IslandRendererScript.new()
	renderer.name = "Island_%d_%d" % [coord.x, coord.y]
	renderer.setup(resource_node_database, building_manager)
	renderer.world_data = world
	renderer.show_grid = _show_grid
	# In the tree first (its _ready builds the scene roots), then positioned so the island's grid
	# centre sits on the slot, then rendered (the water shader needs the final world position).
	_islands.add_child(renderer)
	var global_zero := Navigation.local_to_world(coord, island, Vector2i.ZERO)
	var origin := Navigation.cell_center(global_zero) - HexGrid.cell_center_3d(Vector2i.ZERO, renderer.cell_size)
	origin.y = 0.0
	renderer.position = origin
	renderer.render(island)
	renderer.set_explored(island.visited or island.sighted)
	_renderers[coord] = renderer


# A low, soft veil marks an unknown destination without resembling weather clouds.
func _make_fog_bank(coord: Vector2i) -> Node3D:
	var bank := Node3D.new()
	bank.position = slot_position(coord)
	var veil := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * FOG_BANK_RADIUS * 2.0
	veil.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = IslandFogShader
	material.set_shader_parameter("seed", float(coord.x * 7 + coord.y * 13))
	veil.material_override = material
	veil.position.y = 80.0
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bank.add_child(veil)
	return bank


# Fade the veil to expose the reachable island's silhouette.
func _lift_fog_bank(coord: Vector2i) -> void:
	var bank: Node3D = _fog_banks[coord]
	_fog_banks.erase(coord)
	var tween := bank.create_tween().set_parallel(true)
	var veil := bank.get_child(0) as MeshInstance3D
	var material := veil.material_override as ShaderMaterial
	tween.tween_method(func(value: float): material.set_shader_parameter("opacity", value),
		1.0, 0.0, FOG_LIFT_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(bank, "scale", Vector3(1.15, 1.0, 1.15), FOG_LIFT_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(bank.queue_free)


# --- Labels ---

func _build_labels() -> void:
	_clear(_labels_root)
	_labels.clear()
	for coord in world.all_slots():
		var label := Label3D.new()
		label.font_size = 48
		label.outline_size = 12
		label.pixel_size = 0.0003
		label.fixed_size = true
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.render_priority = 10
		label.outline_render_priority = 9
		label.outline_modulate = LABEL_OUTLINE
		label.position = slot_position(coord) + Vector3(0.0, LABEL_HEIGHT, 0.0)
		_labels_root.add_child(label)
		_labels[coord] = label
	_style_labels()


func _style_labels() -> void:
	for coord in _labels:
		var label: Label3D = _labels[coord]
		var island := world.get_island(coord)
		var revealed := world.is_revealed(coord) and island != null
		var is_current: bool = revealed and coord == world.current_coord
		if not revealed:
			label.text = "?"
			if coord == _hovered:
				label.text += "\nUncharted\n" + locked_island_hint(coord)
		elif not island.visited:
			label.text = "Unexplored"
			# Until rescued, K9-DA's island is flagged on the map so the player knows where to sail.
			if world.is_dog_stranded_on(coord):
				label.text += "\nK9-DA's signal"
			if coord == _hovered:
				label.text += "\nClick to sail here"
		else:
			label.text = ("▼ %s" if is_current else "%s") % island.island_name
			if world.is_dog_stranded_on(coord):
				label.text += "\nK9-DA is here"
		var color := LABEL_COLOR if revealed else UNCHARTED_LABEL_COLOR
		if is_current or coord == _hovered:
			color = CURRENT_COLOR
		label.modulate = color
		label.scale = Vector3.ONE * (1.2 if coord == _hovered else 1.0)
	_apply_label_fade()


func locked_island_hint(coord: Vector2i) -> String:
	if WorldData.ring_of(coord) == 1:
		return "Build a Dock to complete Set Sail"
	return "Beyond your sailing range"


# Labels only appear once the camera has pulled well back.
func _apply_label_fade() -> void:
	var alpha := clampf((_overview - 0.15) / 0.35, 0.0, 1.0)
	for coord in _labels:
		var label: Label3D = _labels[coord]
		label.visible = alpha > 0.0
		label.modulate.a = alpha
		label.outline_modulate.a = alpha


# --- Environment ---

# The planet's underside faces away from the sun; a dim, cool bounce from below keeps its rock
# readable against the dark sky instead of vanishing into it. It lights only the planet layer.
func _add_bounce_light() -> void:
	var bounce := DirectionalLight3D.new()
	bounce.name = "PlanetBounce"
	bounce.light_color = Color("#8fa8d6")
	bounce.light_energy = 1.1
	bounce.light_cull_mask = 1 << (PLANET_LAYER - 1)
	bounce.rotation = Vector3(deg_to_rad(60.0), deg_to_rad(-30.0), 0.0)
	add_child(bounce)


# --- The planet: ocean, mountain range, rocky underside, waterfalls (in disc units) ---

func _build_planet() -> void:
	_clear(_surface)

	var ocean := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (_disc_radius * 2.0 + 2.0)
	ocean.mesh = plane
	# Just under local transparent water to avoid two coplanar surfaces at their overlap.
	ocean.position.y = (Navigation.SEA_Y - 0.2 - SEA_LEVEL_Y) / DISC_SCALE
	_ocean_material = ShaderMaterial.new()
	_ocean_material.shader = DiscOceanShader
	_ocean_material.set_shader_parameter("disc_radius", _disc_radius)
	_ocean_material.set_shader_parameter("ring_spacing", DISC_UNIT)
	_ocean_material.set_shader_parameter("world_scale", DISC_SCALE)
	_ocean_material.set_shader_parameter("chart_visibility", _chart_visibility())
	_ocean_material.set_shader_parameter("surface_noise", SurfaceNoise)
	_ocean_material.set_shader_parameter("distort_noise", DistortNoise)
	ocean.material_override = _ocean_material
	# The plane is square; the shader discards everything outside the disc.
	_ocean_material.set_shader_parameter("charted_radius", _charted_radius)
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_surface.add_child(ocean)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Each waterfall pours out through its own pass in the range: x = angle, y = width.
	var falls: Array[Vector2] = []
	for i in range(WATERFALL_COUNT):
		falls.append(Vector2(TAU * (float(i) + rng.randf_range(0.15, 0.85)) / WATERFALL_COUNT,
			rng.randf_range(0.8, 1.6)))
	_surface.add_child(_build_mountain_range(falls))
	_surface.add_child(_build_underside(rng))
	for i in range(WATERFALL_COUNT):
		_surface.add_child(_build_waterfall(falls[i].x, falls[i].y, float(i)))


func _build_mountain_range(falls: Array[Vector2]) -> MeshInstance3D:
	# One continuous ring of terrain: ridged noise raises crags and knife-edge ridges along a crest
	# that wanders between the shore and the outer cliff, slow noise lifts whole massifs and sinks
	# saddles between them, and each waterfall cuts a pass out to the edge. Fixed seeds keep the
	# skyline the same whenever the world rebuilds.
	var ridges := FastNoiseLite.new()
	ridges.seed = 1707
	ridges.noise_type = FastNoiseLite.TYPE_PERLIN
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves = 3
	ridges.frequency = 0.12
	var massifs := FastNoiseLite.new()
	massifs.seed = 1708
	massifs.noise_type = FastNoiseLite.TYPE_PERLIN
	massifs.fractal_octaves = 2
	massifs.frequency = 0.035
	var rng := RandomNumberGenerator.new()
	rng.seed = 1709

	# About one disc unit per column along the shore, so a peak spans a handful of facets.
	var segments := maxi(RIM_SEGMENTS, int(TAU * _disc_radius))
	var row_step := (RANGE_OUTER - RANGE_INNER) / RANGE_ROWS
	var points := []
	for row in range(RANGE_ROWS + 1):
		var ring := []
		for segment in range(segments):
			var u := RANGE_INNER + row * row_step
			var angle := TAU * segment / segments
			# Break up the grid, but keep the edges true: under the shallows and over the underside.
			if row > 0 and row < RANGE_ROWS:
				u += rng.randf_range(-0.3, 0.3) * row_step
				angle += rng.randf_range(-0.35, 0.35) * TAU / segments
			var x := cos(angle) * (_disc_radius + u)
			var z := sin(angle) * (_disc_radius + u)
			ring.append(Vector3(x, _range_height(x, z, u, angle, falls, ridges, massifs), z))
		points.append(ring)
	# The cliff carries on down the outside as a craggy skirt, so the range runs straight into
	# the underside's rock instead of sitting on it like a separate layer.
	for skirt in RANGE_SKIRT:
		var ring := []
		for segment in range(segments):
			var angle := TAU * (segment + rng.randf_range(-0.3, 0.3)) / segments
			var radius := _disc_radius + RANGE_OUTER + skirt.x + rng.randf_range(-0.35, 0.35)
			ring.append(Vector3(cos(angle) * radius, skirt.y + rng.randf_range(-0.5, 0.5),
				sin(angle) * radius))
		points.append(ring)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for row in range(points.size() - 1):
		var cliff := row >= RANGE_ROWS
		for segment in range(segments):
			var next := (segment + 1) % segments
			var a: Vector3 = points[row][segment]
			var b: Vector3 = points[row][next]
			var c: Vector3 = points[row + 1][segment]
			var d: Vector3 = points[row + 1][next]
			# Alternate the diagonal so the facets don't line up into stripes.
			if (row + segment) % 2 == 0:
				_range_facet(st, a, b, d, cliff, massifs, rng)
				_range_facet(st, a, d, c, cliff, massifs, rng)
			else:
				_range_facet(st, a, b, c, cliff, massifs, rng)
				_range_facet(st, b, d, c, cliff, massifs, rng)
	st.generate_normals()
	var instance := MeshInstance3D.new()
	instance.name = "MountainRange"
	instance.mesh = st.commit()
	instance.material_override = _vertex_color_material(0.9)
	instance.layers = 1 | (1 << (PLANET_LAYER - 1))
	return instance


# Height of the range at (x, z), `u` disc units out from the ocean's edge.
func _range_height(x: float, z: float, u: float, angle: float, falls: Array[Vector2],
		ridges: FastNoiseLite, massifs: FastNoiseLite) -> float:
	var massif := massifs.get_noise_2d(x, z)
	# The slopes climb from the shallows toward a wandering crest, then hold their height and
	# break off in a steep cliff at the outer edge, straight down onto the underside's wall.
	var crest := 0.9 + massif * 0.9
	var rise := smoothstep(RANGE_INNER, crest, u) if u < crest \
		else 1.0 - pow(smoothstep(crest, RANGE_OUTER + 0.6, u), 2.5)
	var crag := (ridges.get_noise_2d(x, z) + 1.0) * 0.5
	var peak := (1.8 + 7.0 * crag * crag) * clampf(0.9 + massif * 0.9, 0.4, 1.5)
	# Some of each peak still stands at the outer edge, so the cliff top is ragged, not a ledge.
	var height := -0.6 + (RANGE_EDGE_Y + 0.6) * smoothstep(RANGE_OUTER - 1.2, RANGE_OUTER, u) \
		+ pow(rise, 0.75) * peak
	# Passes: a flat floor just above the sea, dropping off the cliff at the outer edge.
	var pass_floor := minf(lerpf(-0.6, PASS_FLOOR, smoothstep(RANGE_INNER, -0.6, u)),
		lerpf(PASS_FLOOR, RANGE_EDGE_Y, smoothstep(RANGE_OUTER - 0.7, RANGE_OUTER, u)))
	for fall in falls:
		var arc := absf(angle_difference(angle, fall.x)) * (_disc_radius + u)
		height = lerpf(height, pass_floor,
			1.0 - smoothstep(fall.y * 0.5 + 0.5, fall.y * 0.5 + 2.6, arc))
	# Never dip below the sea where the ocean's circular edge would show.
	return maxf(height, lerpf(-1.0, PASS_FLOOR - 0.02, smoothstep(-0.9, -0.2, u)))


# Snow settles on high faces, and lower down on the flatter ones; steep faces stay bare rock.
# `cliff` faces are the skirt down the outside, shading from mountain rock into the underside's.
func _range_facet(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, cliff: bool,
		massifs: FastNoiseLite, rng: RandomNumberGenerator) -> void:
	var center := (a + b + c) / 3.0
	if cliff:
		var depth := clampf((RANGE_EDGE_Y - center.y) / (RANGE_EDGE_Y - RANGE_SKIRT[-1].y), 0.0, 1.0)
		var rock := MOUNTAIN_ROCK_COLOR.lerp(ROCK_COLOR, depth).darkened(rng.randf_range(0.0, 0.15))
		_facet(st, a, b, c, Vector3(0.0, center.y, 0.0), rock)
		return
	var normal := (b - a).cross(c - a).normalized()
	var flatness := absf(normal.y)
	# Sample the massif noise transposed so the snow line doesn't simply track the high ground.
	var snow_line := 2.3 + massifs.get_noise_2d(center.z, center.x) * 1.6 + (0.8 - flatness) * 3.0
	var color: Color
	if flatness > 0.45 and center.y > snow_line:
		color = SNOW_COLOR.lerp(Color.WHITE, rng.randf_range(0.0, 0.6))
		if flatness < 0.7:
			color = color.lerp(SNOW_SHADOW_COLOR, 0.55)
	else:
		color = MOUNTAIN_ROCK_COLOR.lerp(MOUNTAIN_HIGH_ROCK_COLOR, clampf(center.y / 4.5, 0.0, 1.0))
		# Grassy foothills only on the sea side; the outer slopes fall away as bare cliff.
		var inland := Vector2(center.x, center.z).length() < _disc_radius + 0.6
		if inland and center.y < 0.9 and flatness > 0.8:
			color = FOOTHILL_COLOR
		color = color.darkened(rng.randf_range(0.0, 0.12) + (0.75 - flatness) * 0.15)
	_facet(st, a, b, c, center + Vector3.DOWN, color)


func _facet(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		interior: Vector3, color: Color) -> void:
	# Godot's front faces wind clockwise; orient each face away from `interior`.
	var outward := (b - a).cross(c - a).dot((a + b + c) / 3.0 - interior) > 0.0
	st.set_color(color)
	st.add_vertex(a)
	st.add_vertex(c if outward else b)
	st.add_vertex(b if outward else c)


func _build_underside(rng: RandomNumberGenerator) -> MeshInstance3D:
	var r := _disc_radius
	# A deep bowl: steep walls under the rim, then rounding into a craggy point, so the
	# underside reads from the usual three-quarter view rather than hiding behind the mountains.
	var depth := r * 0.8
	var profile: Array[Vector2] = [
		Vector2(r + RANGE_OUTER - 0.6, -2.0),
		Vector2(r + RANGE_OUTER - 0.8, -depth * 0.1),
		Vector2(r + 1.0, -depth * 0.22),
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
	# Keep the top edge tucked under the mountains' outer cliff and the tip closed.
	for segment in range(RIM_SEGMENTS):
		jitter[0][segment] = Vector2.ZERO
		jitter[profile.size() - 1][segment] = Vector2.ZERO
	var instance := MeshInstance3D.new()
	instance.mesh = _lathe(profile, colors, jitter, false)
	instance.material_override = _vertex_color_material(1.0)
	instance.layers = 1 | (1 << (PLANET_LAYER - 1))
	return instance


func _build_waterfall(angle: float, width: float, fall_seed: float) -> MeshInstance3D:
	var outward := Vector3(cos(angle), 0.0, sin(angle))
	var tangent := Vector3(-sin(angle), 0.0, cos(angle))
	var r := _disc_radius
	var fall := r * 0.6
	var lip := r + RANGE_OUTER - 0.7
	var surface := PASS_FLOOR + 0.06
	var run_steps := 4
	var fall_steps := 14

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Rows along the ribbon with their UV.y: a short run out from the sea along the pass floor,
	# then over the lip and down in a gentle outward arc.
	var rows: Array[Vector3] = []
	var along: Array[float] = []
	for i in range(run_steps):
		var t := float(i) / run_steps
		rows.append(outward * lerpf(r - 1.0, lip, t) + Vector3.UP * surface)
		along.append(t * 0.06)
	for i in range(fall_steps + 1):
		var t := float(i) / fall_steps
		var out := lip + sqrt(minf(t * 5.0, 1.0)) * 1.2 + t * t * 2.5
		rows.append(outward * out + Vector3.UP * (surface - pow(t, 1.5) * fall))
		along.append(0.06 + t * 0.94)
	for i in range(rows.size() - 1):
		var t0 := along[i]
		var t1 := along[i + 1]
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


# --- Drifting clouds over the uncharted sea (in disc units) ---

func _build_clouds() -> void:
	_clear(_clouds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var material := _flat_material(CLOUD_COLOR, 1.0)
	var min_radius := clampf(_charted_radius + DISC_UNIT * 0.6, _disc_radius * 0.3, _disc_radius * 0.8)
	var max_radius := _disc_radius * 0.96
	for i in range(CLOUD_COUNT):
		var angle := TAU * (float(i) + rng.randf_range(0.0, 0.7)) / CLOUD_COUNT
		var radius := rng.randf_range(min_radius, max_radius)
		var cluster := Node3D.new()
		var count := rng.randi_range(3, 5)
		var puff_scale := rng.randf_range(0.6, 1.0)
		for j in range(count):
			var puff := _make_puff(material, puff_scale * rng.randf_range(0.7, 1.15))
			puff.position = Vector3(
				(j - count * 0.5 + 0.5) * puff_scale * 0.95,
				rng.randf_range(-0.2, 0.4) * puff_scale,
				rng.randf_range(-0.5, 0.5) * puff_scale
			)
			cluster.add_child(puff)
		cluster.position = Vector3(cos(angle) * radius, rng.randf_range(1.6, 2.6), sin(angle) * radius)
		cluster.rotation.y = rng.randf() * TAU
		_clouds.add_child(cluster)


func _make_puff(material: Material, radius: float) -> MeshInstance3D:
	var puff := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	puff.mesh = sphere
	puff.material_override = material
	# Shadows from clouds read as dark holes in the calm sea, not as cloud shade.
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puff.scale = Vector3(1.0, 0.62, 1.0)
	return puff


# --- Trade routes (in world units) ---

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
		var side := direction.cross(Vector3.UP) * 18.0
		var start := home + direction * ROUTE_CLEARANCE
		var end := away - direction * ROUTE_CLEARANCE
		var length := start.distance_to(end)
		var dash := 140.0
		var along := 0.0
		while along < length:
			var a := start + direction * along
			var b := start + direction * minf(along + dash, length)
			a.y = ROUTE_Y
			b.y = ROUTE_Y
			for vertex in [a - side, b - side, b + side, a - side, b + side, a + side]:
				st.set_normal(Vector3.UP)
				st.add_vertex(vertex)
			along += dash * 2.2

		var boat := _make_boat()
		_routes.add_child(boat)
		_boats.append({route = route, boat = boat, start = start, end = end})

	var dashes := MeshInstance3D.new()
	dashes.mesh = st.commit()
	dashes.material_override = _flat_material(Color(ROUTE_COLOR, 0.6), 0.0, true, true)
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
		boat.position = start.lerp(end, t) + Vector3(0.0, sin(_time * 3.0 + t * 20.0) * 3.0, 0.0)
		boat.rotation.y = atan2(-heading.z, heading.x)
		boat.rotation.z = sin(_time * 2.2 + t * 13.0) * 0.08


# A little sailboat about a cell long — big enough to spot from the overview.
func _make_boat() -> Node3D:
	var boat := Node3D.new()
	var hull := MeshInstance3D.new()
	var hull_mesh := BoxMesh.new()
	hull_mesh.size = Vector3(150.0, 40.0, 66.0)
	hull.mesh = hull_mesh
	hull.material_override = _flat_material(BOAT_HULL_COLOR, 0.8)
	hull.position.y = 20.0
	boat.add_child(hull)
	var sail := MeshInstance3D.new()
	var sail_mesh := PrismMesh.new()
	sail_mesh.size = Vector3(84.0, 110.0, 8.0)
	sail.mesh = sail_mesh
	sail.material_override = _flat_material(BOAT_SAIL_COLOR, 0.8)
	sail.position = Vector3(6.0, 95.0, 0.0)
	boat.add_child(sail)
	return boat


# --- Helpers ---

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


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
