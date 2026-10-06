class_name WorldView
extends Node3D

# The whole world as one place: the flat-disc planet floating in space (docs/intro-story.md),
# with every island at full scale on it. One calm ocean sits inside a snow-capped mountain range on a rocky,
# tapering underside; sea water spills off the edge into the starfield. Each revealed island has
# its own IslandRenderer standing on its slot, and everything not yet charted lies under the
# unscanned chart of hex tiles in two layers: near-black tiles beyond the radar frontier, where no
# boat can sail, and slate exploration fog over every cell inside it the robot has not seen yet
# (WorldData.exploration), plus a patch over each reachable island until the robot's sight reaches
# and discovers it. Islands nobody has found are not shown at all; only K9-DA's signal pings where
# its island lies. Ring unlocks roll the dark tiles back into fog; the robot's sight clears the
# fog; discovery opens the island's patch; landing restores its full detail. Trade routes run
# across the open sea with their boats, and island names float over the slots once the camera
# pulls back.
#
# Slots live on the world hex lattice (WorldData keys islands by axial coord and trade trips are
# timed by hex distance); this decides where each one sits in world space. The planet itself is
# authored in small "disc units" (one ring = DISC_UNIT) and scaled up into the world; islands,
# the chart, labels and routes are placed directly in world units. main.gd owns the camera and
# routes picks through slot_at_ray.

const IslandRendererScript := preload("res://scripts/island/island_renderer.gd")
const Navigation := preload("res://scripts/world/world_navigation.gd")
const UnchartedChartShader := preload("res://assets/shaders/world_map/uncharted_chart.gdshader")
const ChartScanNoise := preload("res://assets/shaders/world_map/chart_scan_noise.tres")
const DiscOceanShader := preload("res://assets/shaders/world_map/disc_ocean.gdshader")
const WaterfallShader := preload("res://assets/shaders/world_map/waterfall.gdshader")
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

# A ground point within this distance of a slot centre belongs to that slot's island.
const ISLAND_PICK_RADIUS := 2700.0
# The uncharted chart lies flat just above the tallest silhouette tiles (STONE_TOP_Y).
const CHART_Y := 30.0
# K9-DA's signal pings on the chart this far around its island until the island is discovered.
const SIGNAL_RADIUS := 760.0
# An island's patch reaches this far past its land (an island's own water runs roughly 1150 units
# from its centre).
const PATCH_MARGIN := 200.0
# The patch's hole while it is closed: far enough below zero that no tile ever switches off.
const PATCH_CLOSED := -400.0
# How far past a patch its tiles may still show: its ragged edge (JITTER + BROAD in
# uncharted_chart.gdshader) and a loose tile beyond.
const CHART_EDGE_REACH := 220.0
# An object shows once the opening has cleared it by this much, past the tiles' ragged edge.
const OBJECT_CLEARANCE := 180.0
const CHART_REVEAL_SECONDS := 2.2
# Patches the chart shader takes (its uniform arrays).
const MAX_CHART_ITEMS := 64
const FRONTIER_UNROLL_SECONDS := 3.0
const LABEL_HEIGHT := 900.0
# Trade lanes start/end this far out from each slot centre, clear of the island.
const ROUTE_CLEARANCE := 2600.0
const ROUTE_Y := 8.0

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

# Discovery has finished opening the chart over the island at `coord`.
signal patch_opened(coord: Vector2i)

var world: WorldData
var resource_node_database: ResourceNodeDatabase
var building_manager: BuildingManager
var navigation: WorldNavigation
# The width and depth of a cell. With get_cell_center and get_step_height this makes the world view
# the ground units walk on, across every island and the sea.
var cell_size := Navigation.CELL_SIZE

var _disc_radius := 0.0 # disc units
var _charted_radius := -1.0 # disc units
var _planet: Node3D
var _surface: Node3D
var _islands: Node3D
var _chart: MeshInstance3D
var _chart_material: ShaderMaterial
# The frontier the chart currently shows, behind the real one while the sheet rolls back.
var _chart_frontier := -1.0
var _frontier_tween: Tween
# The explored cells as the chart shader reads them (ExplorationMap.cells), refreshed when they
# change.
var _explored_image: Image
var _explored_texture: ImageTexture
var _explored_dirty := true
var _sailing_hover: MeshInstance3D
var _labels_root: Node3D
var _routes: Node3D
var _ocean_material: ShaderMaterial
var _time := 0.0
var _show_grid := true
var _overview := 0.0

# coord -> IslandRenderer, for every revealed island.
var _renderers: Dictionary = {}
# coord -> Vector4 chart patch (centre x, z; radius; hole), for every reachable island not yet
# discovered, and for those whose patch is still opening.
var _chart_patches: Dictionary = {}
# coord -> true while discovery opens that island's patch.
var _opening: Dictionary = {}
# coord -> Label3D
var _labels: Dictionary = {}
var _hovered := WorldData.NO_COORD
# One entry per trade route: {route: TradeRoute, boat: Node3D, start: Vector3, end: Vector3}
var _boats: Array[Dictionary] = []

var _shared_materials: Dictionary = {}


func setup(
	new_world: WorldData,
	new_resource_node_database: ResourceNodeDatabase,
	new_building_manager: BuildingManager,
	new_navigation: WorldNavigation
) -> void:
	world = new_world
	resource_node_database = new_resource_node_database
	building_manager = new_building_manager
	navigation = new_navigation
	world.exploration.changed.connect(func() -> void: _explored_dirty = true)
	_explored_dirty = true


func _ready() -> void:
	_add_bounce_light()

	_planet = Node3D.new()
	_planet.name = "Planet"
	_planet.position.y = SEA_LEVEL_Y
	_planet.scale = Vector3.ONE * DISC_SCALE
	add_child(_planet)
	_surface = Node3D.new()
	_planet.add_child(_surface)

	_islands = Node3D.new()
	_islands.name = "Islands"
	add_child(_islands)
	_chart = MeshInstance3D.new()
	_chart.name = "UnchartedChart"
	_chart.position.y = CHART_Y
	_chart.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_chart_material = ShaderMaterial.new()
	_chart_material.shader = UnchartedChartShader
	_chart_material.set_shader_parameter("scan_noise", ChartScanNoise)
	_chart_material.set_shader_parameter("ring_spacing", RING_SPACING)
	# Over the island water and trade lanes, which are transparent too.
	_chart_material.render_priority = 1
	_chart.material_override = _chart_material
	add_child(_chart)
	_labels_root = Node3D.new()
	_labels_root.name = "Labels"
	add_child(_labels_root)
	_routes = Node3D.new()
	_routes.name = "Routes"
	add_child(_routes)


# Bring everything in line with world state: the disc size and charted area, a renderer for every
# reachable island, fog banks over undiscovered islands, labels
# and routes. Islands already rendered are left alone, so this is cheap to call after any change.
func refresh() -> void:
	if world == null or _planet == null:
		return

	var disc_radius := (world.world_rings() + DISC_MARGIN) * DISC_UNIT
	if not is_equal_approx(disc_radius, _disc_radius):
		_disc_radius = disc_radius
		_build_planet()
		var sheet := PlaneMesh.new()
		sheet.size = Vector2.ONE * world_disc_radius() * 2.0
		_chart.mesh = sheet
		_chart_material.set_shader_parameter("disc_radius", world_disc_radius())

	var charted_radius := (world.revealed_rings + 0.5) * DISC_UNIT
	if not is_equal_approx(charted_radius, _charted_radius):
		_charted_radius = charted_radius
		_ocean_material.set_shader_parameter("charted_radius", _charted_radius)
		_roll_back_frontier()

	_sync_islands()
	if _explored_dirty:
		_upload_exploration()
	_build_labels()
	_build_routes()


# The renderer drawing the island at `coord`, or null if it is not revealed (or not generated).
func renderer_for(coord: Vector2i) -> IslandRenderer:
	return _renderers.get(coord)


# The renderer of the island the cell belongs to, or null for open sea (or an island not drawn).
func renderer_at(cell: Vector2i) -> IslandRenderer:
	return _renderers.get(navigation.slot_at(cell))


# World-space centre of a cell's top: an island tile at its own height, open sea at its surface.
func get_cell_center(cell: Vector2i) -> Vector3:
	var renderer := renderer_at(cell)
	return renderer.get_cell_center(cell) if renderer != null else Navigation.cell_center(cell)


# A walking unit's height between two neighbouring cells (see IslandRenderer.get_step_height).
func get_step_height(from_cell: Vector2i, to_cell: Vector2i, world_position: Vector3) -> float:
	var renderer := renderer_at(to_cell)
	return renderer.get_step_height(from_cell, to_cell, world_position) if renderer != null else world_position.y


# The cell under a camera ray: on an island, the tile it meets at that tile's own height; off every
# island, the sea cell it meets at the surface.
func cell_from_ray(origin: Vector3, direction: Vector3) -> Vector2i:
	var sea_cell := navigation.cell_from_ray(origin, direction)
	var renderer := renderer_at(sea_cell)
	if renderer != null:
		var cell := renderer.cell_from_ray(origin, direction)
		if renderer.island.has_cell(cell):
			return cell
	return sea_cell


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
	_sync_islands()
	_style_labels()


# Where a slot sits in the world (on the water plane).
static func slot_position(coord: Vector2i) -> Vector3:
	var center := Navigation.slot_center(coord)
	center.y = 0.0
	return center


func _process(delta: float) -> void:
	_time += delta
	_update_boats()
	if _explored_dirty:
		_upload_exploration()


# --- Islands and the uncharted chart over them ---

func _sync_islands() -> void:
	for coord in world.all_slots():
		var island := world.get_island(coord)
		if island == null or not world.is_revealed(coord):
			continue
		if not _renderers.has(coord):
			_add_renderer(coord, island)
		var discovered := island.visited or island.sighted
		(_renderers[coord] as IslandRenderer).set_explored(discovered)
		# The island the robot is on is never under the chart (a new game starts there before
		# discovering it).
		if not discovered and coord != world.current_coord and not _chart_patches.has(coord):
			_chart_patches[coord] = _closed_patch(coord)
		elif discovered and _chart_patches.has(coord) and not _opening.has(coord):
			_open_patch(coord)
	_update_chart()


# Whether the chart still hides the slot: beyond the frontier, or under a patch not yet opened.
func is_uncharted(coord: Vector2i) -> bool:
	return not world.is_revealed(coord) or (_chart_patches.has(coord) and not _opening.has(coord))


func _add_renderer(coord: Vector2i, island: IslandData) -> void:
	var renderer: IslandRenderer = IslandRendererScript.new()
	renderer.name = "Island_%d_%d" % [coord.x, coord.y]
	renderer.setup(resource_node_database, building_manager)
	renderer.world_data = world
	renderer.show_grid = _show_grid
	# In the tree first (its _ready builds the scene roots), then positioned, then rendered (the
	# water shader needs the final world position). Island cells are world lattice cells, so every
	# renderer gets the same offset: the one putting each cell where WorldNavigation has it.
	_islands.add_child(renderer)
	var origin := Navigation.cell_center(Vector2i.ZERO) - HexGrid.cell_center_3d(Vector2i.ZERO, renderer.cell_size)
	origin.y = 0.0
	renderer.position = origin
	renderer.render(island)
	renderer.set_explored(island.visited or island.sighted)
	_renderers[coord] = renderer


# A patch of fog covering the island's land until the robot's sight reaches it.
func _closed_patch(coord: Vector2i) -> Vector4:
	var center := slot_position(coord)
	return Vector4(center.x, center.z, _patch_radius(coord), PATCH_CLOSED)


# How far an island's patch reaches from its slot: past its land by PATCH_MARGIN.
func _patch_radius(coord: Vector2i) -> float:
	var island := world.get_island(coord)
	var center := slot_position(coord)
	var land := 0.0
	for cell in island.terrain:
		if not GameTypes.is_water(island.get_terrain(cell)):
			var point := Navigation.cell_center(cell)
			land = maxf(land, Vector2(point.x - center.x, point.z - center.z).length())
	return land + PATCH_MARGIN


# The island's cells its patch covers. Discovery explores them all, so opening the patch leaves
# no exploration fog over the island (the patch's ragged tiles reach CHART_EDGE_REACH past it);
# the water beyond is explored by sight.
func island_chart_cells(coord: Vector2i) -> Array[Vector2i]:
	var island := world.get_island(coord)
	var center := slot_position(coord)
	var reach := _patch_radius(coord) + CHART_EDGE_REACH
	var cells: Array[Vector2i] = []
	for cell in island.terrain:
		var point := Navigation.cell_center(cell)
		if Vector2(point.x - center.x, point.z - center.z).length() <= reach:
			cells.append(cell)
	return cells


# Discovery opens a hole at the island's centre that spreads out until the patch is gone. The
# island's objects stand taller than the chart, so each one appears as the opening reaches it.
func _open_patch(coord: Vector2i) -> void:
	_opening[coord] = true
	var closed: Vector4 = _chart_patches[coord]
	var renderer: IslandRenderer = _renderers[coord]
	var center := slot_position(coord)
	var open_to := func(hole: float) -> void:
		var piece: Vector4 = _chart_patches[coord]
		piece.w = hole
		_chart_patches[coord] = piece
		_update_chart()
		renderer.reveal_objects_within(center, hole - OBJECT_CLEARANCE)
	open_to.call(closed.w)
	var tween := create_tween()
	tween.tween_method(open_to, closed.w, closed.z + CHART_EDGE_REACH, CHART_REVEAL_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func() -> void:
		_chart_patches.erase(coord)
		_opening.erase(coord)
		_update_chart()
		renderer.reveal_objects_within(center, INF)
		patch_opened.emit(coord))


# Whether discovery is still opening the chart over the slot's island.
func is_opening(coord: Vector2i) -> bool:
	return _opening.has(coord)


# Ring unlocks roll the sheet back to the new frontier; loading a game sets it at once.
func _roll_back_frontier() -> void:
	var frontier := navigation.sailing_radius()
	if _frontier_tween != null:
		_frontier_tween.kill()
	if _chart_frontier < 0.0 or frontier < _chart_frontier:
		_chart_frontier = frontier
		return
	_frontier_tween = create_tween()
	_frontier_tween.tween_method(func(radius: float) -> void:
		_chart_frontier = radius
		_update_chart(),
		_chart_frontier, frontier, FRONTIER_UNROLL_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# Hand the chart its frontier, patches and K9-DA's ping.
func _update_chart() -> void:
	var patches := PackedVector4Array()
	for coord in _chart_patches:
		patches.append(_chart_patches[coord])
	_chart_material.set_shader_parameter("frontier_radius", _chart_frontier)
	_chart_material.set_shader_parameter("patches", _padded(patches))
	_chart_material.set_shader_parameter("patch_count", mini(patches.size(), MAX_CHART_ITEMS))
	_chart_material.set_shader_parameter("ping", _signal_ping())


# K9-DA's signal, the one island the chart gives away: once Set Sail charts the dog's ring it pings
# over the island until the robot discovers it. x, y = centre, z = radius (0 for none).
func _signal_ping() -> Vector3:
	var coord := world.dog_coord
	if not world.is_dog_stranded_on(coord) or not world.is_revealed(coord) or not world.has_island(coord) \
			or world.get_island(coord).visited:
		return Vector3.ZERO
	var center := slot_position(coord)
	return Vector3(center.x, center.z, SIGNAL_RADIUS)


# Whether the map shows the island at all: discovered, or giving off K9-DA's signal. The rest stay
# hidden until the robot finds them.
func is_on_map(coord: Vector2i) -> bool:
	var island := world.get_island(coord)
	if island == null or not world.is_revealed(coord):
		return false
	return island.visited or world.is_dog_stranded_on(coord)


# Hand the chart the explored cells, one byte per cell, as a texture.
func _upload_exploration() -> void:
	if world == null or _chart_material == null:
		return
	_explored_dirty = false
	var map := world.exploration
	if map.radius == 0:
		_chart_material.set_shader_parameter("explored_radius", -1)
		return
	if _explored_image != null and _explored_image.get_width() == map.size():
		_explored_image.set_data(map.size(), map.size(), false, Image.FORMAT_R8, map.cells)
		_explored_texture.update(_explored_image)
	else:
		_explored_image = Image.create_from_data(map.size(), map.size(), false, Image.FORMAT_R8, map.cells)
		_explored_texture = ImageTexture.create_from_image(_explored_image)
		_chart_material.set_shader_parameter("explored_map", _explored_texture)
	_chart_material.set_shader_parameter("explored_radius", map.radius)


static func _padded(items: PackedVector4Array) -> PackedVector4Array:
	var padded := items.slice(0, MAX_CHART_ITEMS)
	padded.resize(MAX_CHART_ITEMS)
	return padded


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
		if not is_on_map(coord):
			# Islands nobody has found yet are left for the player to discover.
			label.text = ""
		elif not island.visited:
			# Until rescued, K9-DA's island is flagged on the map so the player knows where to sail.
			label.text = "K9-DA's signal"
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
		label.visible = alpha > 0.0 and not label.text.is_empty()
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
