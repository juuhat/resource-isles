class_name IslandRenderer
extends Node3D

# 3D island renderer (see docs/3d-models.md). Terrain is built from
# code-generated hex prisms (one shared mesh, one instance per cell, tinted by terrain
# and raised by elevation). Buildings, resource nodes, ground items, and dock boats are
# drawn as upright Sprite3D billboards reusing the existing 2D art (the 2.5D approach).
#
# The public interface is kept compatible with the 2D renderer it replaces so main.gd
# and player_unit.gd are largely unchanged: render(), refresh(), get_cell_center(),
# cell_to_world(), world_to_cell(), set_hovered_world_position(), set_placement_preview(),
# try_place_hovered_building(), get_hovered_building_type(), hovered_cell, cell_size.

const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const BladeSpinnerScript := preload("res://scripts/island/blade_spinner.gd")
# Roystan toon water (see assets/shaders/water_toon.gdshader): a transparent animated
# plane with a flat tint plus scrolling noise; the shoreline foam band comes from the baked
# per-island shore-distance field (set in _rebuild_water), not the depth buffer.
const WATER_TOON_SHADER := preload("res://assets/shaders/water_toon.gdshader")
const WATER_SURFACE_NOISE := preload("res://assets/shaders/water_toon/PerlinNoise.png")
const WATER_DISTORT_NOISE := preload("res://assets/shaders/water_toon/WaterDistortion.png")
const ROWBOAT_TEXTURE := preload("res://assets/vehicles/rowboat.png")

const ITEM_TEXTURES := {
	GameTypes.ItemType.AXE: preload("res://assets/icons/axe.png"),
	GameTypes.ItemType.PICKAXE: preload("res://assets/icons/pickaxe.png"),
	GameTypes.ItemType.HAMMER: preload("res://assets/icons/hammer.png"),
}

const BOAT_SIZE_TILES := Vector2(0.8, 0.8)

# Cartoon outline for tinted models: an inverted-hull pass grows the mesh along its normals,
# culls the front faces and paints the remaining back faces, leaving a rim around the
# silhouette. The rim is a darkened shade of the model's own tint (softer than pure black, and
# cohesive per resource). Grow is in model-local units (multiplied by the instance scale), so
# all stone-deposit variants share one consistent outline thickness.
const MODEL_OUTLINE_DARKEN := 0.25
const MODEL_OUTLINE_GROW := 0.024

const SAND_COLOR := Color("#e3bc83")
const GRASS_COLOR := Color("#9ea131")
const STONE_COLOR := Color("#8e8791")
const SHORE_FOAM_COLOR := Color("#ffffff40")
# Single flat translucent surface tint; depth comes from the seabed showing through.
const WATER_SURFACE_COLOR := Color("#2d62a5")
const WATER_SURFACE_ALPHA := 0.55

# Seabed ground tones (Minecraft-style): the floor under water is real ground, not blue —
# the blue comes from the translucent surface plane above it. Coast is a sandy shelf, the
# open-ocean floor is a darker, muddier sand.
const SEABED_COAST_COLOR := Color("#19a5ff")
const SEABED_OCEAN_COLOR := Color("#1c8fe9")

# Prism top heights per terrain (world units). Land sits above water for a layered
# island silhouette; the differences are small so unit movement reads as gentle steps.
const WATER_TOP_Y := 6.0
const SAND_TOP_Y := 14.0
const GRASS_TOP_Y := 20.0
const STONE_TOP_Y := 26.0

# Water cells are flat tiles at one level (no basin) just under the translucent surface
# plane. They still drop to WATER_FLOOR_Y underneath so the map edges read as solid water
# rather than a thin sheet. Coast and ocean share the level so all water is flush.
const WATER_TILE_TOP_Y := WATER_TOP_Y - 1.0
const COAST_SEABED_TOP_Y := WATER_TILE_TOP_Y
const OCEAN_SEABED_TOP_Y := WATER_TILE_TOP_Y
const WATER_FLOOR_Y := -8.0

@export var cell_size := Vector2(128.0, 128.0)
@export var show_grid := true

var island: IslandData
var resource_node_database: ResourceNodeDatabase
var building_manager: BuildingManager
var hovered_cell := Vector2i(-1, -1)
var placement_preview_enabled := false
var placement_building_type := GameTypes.BuildingType.LOGGER_CAMP
var placement_can_afford := true

var _terrain_root: Node3D
var _objects_root: Node3D
var _preview_root: Node3D
var _grid_instance: MeshInstance3D
var _water_instance: MeshInstance3D
var _water_material: ShaderMaterial
var _prism_mesh: ArrayMesh
var _cap_mesh: ArrayMesh
var _terrain_materials := {}
var _seabed_materials := {}
var _highlight_materials := {}
# Flat material per model tint colour, shared across every recolored instance (the per-colour
# inverted-hull outline rides along as each material's next_pass).
var _flat_model_materials := {}
# cell -> the terrain MeshInstance3D for that cell, so hover can recolor it in place.
var _tiles := {}
var _highlighted_cell := Vector2i(-1, -1)


func _ready() -> void:
	_prism_mesh = _build_hex_prism_mesh()
	_cap_mesh = _build_hex_cap_mesh()

	_terrain_root = Node3D.new()
	_terrain_root.name = "Terrain"
	add_child(_terrain_root)

	_objects_root = Node3D.new()
	_objects_root.name = "Objects"
	add_child(_objects_root)

	_preview_root = Node3D.new()
	_preview_root.name = "PlacementPreview"
	add_child(_preview_root)

	_grid_instance = MeshInstance3D.new()
	_grid_instance.name = "Grid"
	_grid_instance.material_override = _make_grid_material()
	add_child(_grid_instance)

	_water_instance = MeshInstance3D.new()
	_water_instance.name = "Water"
	_water_instance.visible = false
	_water_material = _make_toon_water_material()
	_water_instance.material_override = _water_material
	add_child(_water_instance)


func setup(new_resource_node_database: ResourceNodeDatabase, new_building_manager: BuildingManager) -> void:
	resource_node_database = new_resource_node_database
	building_manager = new_building_manager


# Full rebuild — terrain and all objects. Called on island entry/switch.
func render(new_island: IslandData) -> void:
	island = new_island
	hovered_cell = Vector2i(-1, -1)
	_highlighted_cell = Vector2i(-1, -1)
	_rebuild_terrain()
	_rebuild_water()
	_rebuild_grid()
	_rebuild_objects()
	_rebuild_preview()


# Object-only rebuild — cheaper, for placements and ground-item pickups (replaces the
# old queue_redraw() calls).
func refresh() -> void:
	_rebuild_objects()
	_rebuild_preview()


func set_show_grid(value: bool) -> void:
	show_grid = value
	if _grid_instance != null:
		_grid_instance.visible = value


# --- Coordinate mapping (delegates to HexGrid, see Phase 1) ---

func cell_to_world(cell: Vector2i) -> Vector3:
	return HexGridScript.cell_to_world_3d(cell, cell_size)


func get_cell_center(cell: Vector2i) -> Vector3:
	var center := HexGridScript.cell_center_3d(cell, cell_size)
	center.y = _terrain_top_y(_terrain_of(cell))
	return center


func world_to_cell(world_position: Vector3) -> Vector2i:
	if island == null:
		return Vector2i(-1, -1)

	var point := Vector2(world_position.x, world_position.z)
	var row := roundi(world_position.z / (cell_size.y * 0.75))
	var column := roundi(world_position.x / cell_size.x - _row_offset(row))
	var nearest_cell := Vector2i(column, row)
	var nearest_distance := INF

	for candidate_y in range(row - 1, row + 2):
		for candidate_x in range(column - 1, column + 2):
			var cell := Vector2i(candidate_x, candidate_y)
			if not island.is_in_bounds(cell):
				continue

			if _cell_contains_xz(cell, point):
				return cell

			var center := HexGridScript.cell_center_3d(cell, cell_size)
			var distance := point.distance_squared_to(Vector2(center.x, center.z))
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_cell = cell

	return nearest_cell if island.is_in_bounds(nearest_cell) else Vector2i(-1, -1)


func get_map_center() -> Vector3:
	if island == null:
		return Vector3.ZERO

	var min_xz := Vector2(INF, INF)
	var max_xz := Vector2(-INF, -INF)
	for y in range(island.height):
		for x in range(island.width):
			var center := HexGridScript.cell_center_3d(Vector2i(x, y), cell_size)
			min_xz.x = minf(min_xz.x, center.x)
			min_xz.y = minf(min_xz.y, center.z)
			max_xz.x = maxf(max_xz.x, center.x)
			max_xz.y = maxf(max_xz.y, center.z)

	var mid := (min_xz + max_xz) * 0.5
	return Vector3(mid.x, GRASS_TOP_Y, mid.y)


func get_map_radius() -> float:
	if island == null:
		return cell_size.x

	return 0.5 * maxf(island.width * cell_size.x, island.height * cell_size.y * 0.75)


func set_hovered_from_ray(origin: Vector3, direction: Vector3) -> void:
	var cell := cell_from_ray(origin, direction)

	if island == null or not island.is_in_bounds(cell):
		cell = Vector2i(-1, -1)

	if hovered_cell == cell:
		return

	hovered_cell = cell
	_update_hover()
	if placement_preview_enabled:
		_rebuild_preview()


# Picks the hovered cell from a camera ray with per-tile height awareness: intersect the
# land plane for an approximate cell, then re-intersect at that cell's actual top height so
# the selection lands on the tile under the cursor rather than on a fixed-height plane.
func cell_from_ray(origin: Vector3, direction: Vector3) -> Vector2i:
	var approx = _ray_plane_xz(origin, direction, GRASS_TOP_Y)
	if approx == null:
		return Vector2i(-1, -1)

	var cell := world_to_cell(approx)
	if island != null and island.is_in_bounds(cell):
		var refined = _ray_plane_xz(origin, direction, _terrain_top_y(island.get_terrain(cell)))
		if refined != null:
			cell = world_to_cell(refined)

	return cell


# Ray/horizontal-plane intersection, returning the hit as a Vector3 (or null if the ray is
# parallel to or points away from the plane).
func _ray_plane_xz(origin: Vector3, direction: Vector3, plane_y: float):
	if absf(direction.y) < 0.00001:
		return null
	var t := (plane_y - origin.y) / direction.y
	if t < 0.0:
		return null
	return origin + direction * t


func set_placement_preview(
	enabled: bool,
	building_type: int = GameTypes.BuildingType.LOGGER_CAMP,
	can_afford: bool = true
) -> void:
	placement_preview_enabled = enabled
	placement_building_type = building_type
	placement_can_afford = can_afford
	_rebuild_preview()


func try_place_hovered_building(building_type: int = GameTypes.BuildingType.LOGGER_CAMP) -> bool:
	if island == null or hovered_cell == Vector2i(-1, -1):
		return false

	var placed := building_manager.try_place(hovered_cell, building_type, island)
	if placed:
		refresh()

	return placed


func get_hovered_building_type() -> int:
	if island == null or hovered_cell == Vector2i(-1, -1):
		return -1

	return island.get_building_type(hovered_cell)


func get_hovered_resource_node_type() -> int:
	if island == null or hovered_cell == Vector2i(-1, -1):
		return -1

	return island.get_resource_node_type(hovered_cell)


# --- Terrain ---

func _rebuild_terrain() -> void:
	_clear(_terrain_root)
	_tiles.clear()
	if island == null:
		return

	for y in range(island.height):
		for x in range(island.width):
			var cell := Vector2i(x, y)
			var terrain_type := island.get_terrain(cell)
			# Deep ocean needs no seabed prism — the translucent water surface plane covers
			# it. Only the shallow coast shelf and land are built as tiles.
			if terrain_type == GameTypes.Terrain.WATER:
				continue
			var is_water := GameTypes.is_water(terrain_type)

			var tile := MeshInstance3D.new()
			tile.mesh = _prism_mesh
			# Land caps use their terrain colour; the submerged seabed uses sandy ground so
			# the blue reads as the translucent water above it, not painted-on floor.
			tile.material_override = _base_tile_material(terrain_type)
			# The prism mesh is centered on its origin, so place it at the cell center (not
			# the top-left anchor) to line up with units, objects, and mouse picking.
			var center := HexGridScript.cell_center_3d(cell, cell_size)
			if is_water:
				# Seabed prism: top dropped below the water surface, walls falling to the
				# shared floor — visible through the translucent surface plane as depth.
				var seabed_top := _water_seabed_top_y(terrain_type)
				tile.position = Vector3(center.x, WATER_FLOOR_Y, center.z)
				tile.scale = Vector3(1.0, seabed_top - WATER_FLOOR_Y, 1.0)
			else:
				tile.position = Vector3(center.x, 0.0, center.z)
				tile.scale = Vector3(1.0, _terrain_top_y(terrain_type), 1.0)
			_terrain_root.add_child(tile)
			# Land and shallow coast are hover targets; deep ocean is purely visual.
			if _is_plot_cell(terrain_type):
				_tiles[cell] = tile


# Flat colour for a land cap (grass/sand/stone). The submerged seabed uses _seabed_material.
func _tile_material(terrain_type: int) -> Material:
	return _terrain_material(terrain_type)


# Base material for a cell's tile: sandy seabed for water cells, terrain colour for land.
# Used when (re)building tiles and when restoring a tile after a hover.
func _base_tile_material(terrain_type: int) -> Material:
	return _seabed_material(terrain_type) if GameTypes.is_water(terrain_type) else _terrain_material(terrain_type)


# Base flat colour for a cell's tile (drives the brightened hover highlight).
func _base_tile_color(terrain_type: int) -> Color:
	return _seabed_color(terrain_type) if GameTypes.is_water(terrain_type) else _color_for_terrain(terrain_type)


func _terrain_material(terrain_type: int) -> StandardMaterial3D:
	if _terrain_materials.has(terrain_type):
		return _terrain_materials[terrain_type]

	var material := StandardMaterial3D.new()
	material.albedo_color = _color_for_terrain(terrain_type)
	material.roughness = 1.0
	# Cull disabled keeps every face visible regardless of winding — robust for the
	# code-generated prism, cheap for opaque terrain.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_terrain_materials[terrain_type] = material
	return material


# Sandy ground for a submerged water cell. Coast is a lighter shelf, open ocean a darker
# floor; the blue tint comes from the translucent surface plane drawn above, not from here.
func _seabed_material(terrain_type: int) -> StandardMaterial3D:
	if _seabed_materials.has(terrain_type):
		return _seabed_materials[terrain_type]

	var material := StandardMaterial3D.new()
	material.albedo_color = _seabed_color(terrain_type)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_seabed_materials[terrain_type] = material
	return material


func _seabed_color(terrain_type: int) -> Color:
	return SEABED_COAST_COLOR if terrain_type == GameTypes.Terrain.COAST else SEABED_OCEAN_COLOR


# --- Water ---

# A single horizontal plane covering the map (plus open-ocean margin) at water height. The
# shader reads a baked shore-distance field (mobile-safe — no depth-buffer reads) for the
# shallow tint and shoreline foam, so the plane itself needs no subdivision.
func _rebuild_water() -> void:
	if _water_instance == null:
		return

	if island == null:
		_water_instance.visible = false
		return

	var bake := _build_shore_distance_texture()
	var extent: float = maxf(bake["size"].x, bake["size"].y)
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent, extent) * 2.5
	_water_instance.mesh = plane

	_water_material.set_shader_parameter("shore_distance", bake["texture"])
	_water_material.set_shader_parameter("grid_min", bake["min"])
	_water_material.set_shader_parameter("grid_size", bake["size"])

	var center := get_map_center()
	_water_instance.position = Vector3(center.x, WATER_TOP_Y, center.z)
	_water_instance.visible = true


# The Roystan toon water material: one flat translucent tint plus scrolling, distorted
# shoreline foam. The foam still uses the baked shore-distance field (set per-island in
# _rebuild_water); depth perception comes from the seabed beneath, not a color gradient.
func _make_toon_water_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = WATER_TOON_SHADER
	material.set_shader_parameter("surfaceNoise", WATER_SURFACE_NOISE)
	material.set_shader_parameter("distortNoise", WATER_DISTORT_NOISE)
	# One flat translucent tint — no shallow/deep gradient. Depth is read from the sandy
	# seabed showing through: lighter coast shelf vs darker ocean floor. Alpha controls how
	# much floor is visible (toward 1.0 hides it, lower reveals more).
	material.set_shader_parameter("water_color", Color(WATER_SURFACE_COLOR, WATER_SURFACE_ALPHA))
	material.set_shader_parameter("foam_color", SHORE_FOAM_COLOR)
	material.set_shader_parameter("foam_distance", 0.04)
	material.set_shader_parameter("surface_noise_cutoff", 1.0)
	material.set_shader_parameter("surface_distortion_amount", 0.18)
	material.set_shader_parameter("surface_noise_scale", Vector2(0.012, 0.018))
	material.set_shader_parameter("distort_noise_scale", 0.006)
	material.set_shader_parameter("surface_noise_scroll", Vector2(0.018, 0.011))
	material.set_shader_parameter("wave_streak_color", Color(Color("#cdefff"), 0.24))
	material.set_shader_parameter("wave_streak_strength", 0.42)
	material.set_shader_parameter("wave_streak_cutoff", 0.76)
	material.set_shader_parameter("wave_streak_softness", 0.025)
	material.set_shader_parameter("wave_streak_scale", Vector2(0.0014, 0.006))
	material.set_shader_parameter("wave_streak_scroll", Vector2(0.018, 0.004))
	material.set_shader_parameter("wave_patch_scale", 0.0028)
	return material


# Bakes a grayscale field over the map's world bounds: each texel is the normalized distance
# from that world point to the nearest land cell (0 at the shore, 1 in open water). The water
# shader reads it for the shallow/deep tint and the shoreline foam band.
func _build_shore_distance_texture() -> Dictionary:
	var min_xz := Vector2(INF, INF)
	var max_xz := Vector2(-INF, -INF)
	var land_centers: Array[Vector2] = []

	for y in range(island.height):
		for x in range(island.width):
			var cell := Vector2i(x, y)
			var center := HexGridScript.cell_center_3d(cell, cell_size)
			var xz := Vector2(center.x, center.z)
			min_xz.x = minf(min_xz.x, xz.x)
			min_xz.y = minf(min_xz.y, xz.y)
			max_xz.x = maxf(max_xz.x, xz.x)
			max_xz.y = maxf(max_xz.y, xz.y)
			if not GameTypes.is_water(island.get_terrain(cell)):
				land_centers.append(xz)

	var size := max_xz - min_xz
	if size.x <= 0.0:
		size.x = cell_size.x
	if size.y <= 0.0:
		size.y = cell_size.y

	var shore_buffer := cell_size.x * 0.5  # one half-tile out still reads as shore
	var max_distance := cell_size.x * 6.0  # how far the shallow ring extends
	var texture_width := 128
	var texture_height := maxi(1, roundi(texture_width * size.y / size.x))
	var image := Image.create(texture_width, texture_height, false, Image.FORMAT_RGBA8)

	for j in range(texture_height):
		for i in range(texture_width):
			var point := min_xz + Vector2(
				(float(i) + 0.5) / float(texture_width) * size.x,
				(float(j) + 0.5) / float(texture_height) * size.y
			)
			var nearest := INF
			for land in land_centers:
				var d := point.distance_to(land)
				if d < nearest:
					nearest = d
			var shore := 1.0 if land_centers.is_empty() else clampf((nearest - shore_buffer) / max_distance, 0.0, 1.0)
			image.set_pixel(i, j, Color(shore, shore, shore, 1.0))

	return {
		"texture": ImageTexture.create_from_image(image),
		"min": min_xz,
		"size": size,
	}


# --- Grid ---

# A single line-mesh tracing the top hexagon of every land and shallow-coast cell. Lines sit
# just above the tile top to avoid z-fighting; only deep ocean is skipped, so the grid reads
# as the island's plots (coast lines sit on the seabed, seen through the water).
func _rebuild_grid() -> void:
	if _grid_instance == null:
		return

	_grid_instance.visible = show_grid

	if island == null:
		_grid_instance.mesh = null
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var has_segments := false

	for y in range(island.height):
		for x in range(island.width):
			var cell := Vector2i(x, y)
			var terrain_type := island.get_terrain(cell)
			if not _is_plot_cell(terrain_type):
				continue

			var center := HexGridScript.cell_center_3d(cell, cell_size)
			center.y = _tile_top_y(terrain_type) + 0.5
			var corners := HexGridScript.hex_corners_3d(center, cell_size)
			for i in range(6):
				st.add_vertex(corners[i])
				st.add_vertex(corners[(i + 1) % 6])
				has_segments = true

	_grid_instance.mesh = st.commit() if has_segments else null


func _make_grid_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.0, 0.0, 0.0, 0.1)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


# Brightened terrain material for the cell under the cursor — the hover indicator.
func _highlight_material(terrain_type: int) -> StandardMaterial3D:
	if _highlight_materials.has(terrain_type):
		return _highlight_materials[terrain_type]

	var material := StandardMaterial3D.new()
	material.albedo_color = _base_tile_color(terrain_type).lightened(0.35)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_highlight_materials[terrain_type] = material
	return material


# --- Objects (billboards) ---

func _rebuild_objects() -> void:
	_clear(_objects_root)
	if island == null:
		return

	for cell in island.resources.keys():
		_spawn_resource(cell, island.resources[cell])

	for cell in island.items.keys():
		_spawn_item(cell, island.items[cell])

	for anchor_cell in island.buildings.keys():
		var building_type: int = island.buildings[anchor_cell].type
		_spawn_building(anchor_cell, building_type)
		if building_type == GameTypes.BuildingType.DOCK:
			var boat_cell := _dock_boat_cell(anchor_cell)
			if boat_cell != Vector2i(-1, -1):
				_spawn_boat(boat_cell)


func _spawn_resource(cell: Vector2i, resource_node_type: int) -> void:
	var definition := resource_node_database.get_definition(resource_node_type)
	if definition == null:
		return

	if definition.model != null:
		_spawn_model(definition.model, [cell], definition.visual_size_tiles, definition.visual_offset_tiles, definition.visual_rotation_y, definition.model_tint)
		return

	if definition.texture == null:
		return

	var sprite := _make_billboard(definition.texture, definition.visual_size_tiles, definition.visual_offset_tiles)
	sprite.position = _ground_anchor([cell]) + _offset_xz(definition.visual_offset_tiles)
	_lift_to_ground(sprite)
	_objects_root.add_child(sprite)


# Instances a 3D model on a (multi-cell) footprint: rotated to its heading, auto-scaled so
# its width spans size_tiles, and lifted so its lowest point rests on the ground. When tint
# has alpha > 0 the model's own materials are replaced by one flat colour (texture-free
# low-poly look), so a single shared mesh can stand in for several recolored variants.
func _spawn_model(
	scene: PackedScene,
	cells: Array,
	size_tiles: Vector2,
	offset_tiles: Vector2,
	rotation_y_degrees: float = 0.0,
	tint: Color = Color(0.0, 0.0, 0.0, 0.0),
	spin_node_name: String = "",
	spin_axis: Vector3 = Vector3.ZERO,
	spin_speed_degrees: float = 0.0
) -> void:
	var model := scene.instantiate() as Node3D
	if model == null:
		return

	# Added at origin first so its untransformed bounds read as native model space. Rotate
	# before measuring so the auto-scale fits the rotated footprint.
	_objects_root.add_child(model)
	model.rotation.y = deg_to_rad(rotation_y_degrees)
	if tint.a > 0.0:
		_paint_flat(model, tint)
	var bounds := _instance_aabb(model)
	var native_width := maxf(bounds.size.x, bounds.size.z)
	if native_width <= 0.0:
		native_width = 1.0

	var model_scale := (size_tiles.x * cell_size.x) / native_width
	model.scale = Vector3(model_scale, model_scale, model_scale)

	var ground := _ground_anchor(cells) + _offset_xz(offset_tiles)
	# Lift so the model's lowest point (bounds.position.y, scaled) sits on the tile.
	model.position = Vector3(ground.x, ground.y - bounds.position.y * model_scale, ground.z)

	# Drive a spinning sub-mesh (e.g. windmill blades) if the model has one. owned=false so
	# it's found among the instanced .glb's nodes regardless of scene ownership.
	if spin_node_name != "":
		var spin_target := model.find_child(spin_node_name, true, false) as Node3D
		if spin_target != null:
			var spinner := BladeSpinnerScript.new()
			spinner.target = spin_target
			spinner.axis = spin_axis
			spinner.degrees_per_second = spin_speed_degrees
			model.add_child(spinner)


# Replaces every mesh surface's material with one flat, fully-lit colour, discarding the
# model's own textures/materials. The material is shared per colour, so all stone deposits
# (and all coal seams, etc.) reuse a single material regardless of instance count.
func _paint_flat(root: Node3D, color: Color) -> void:
	var material := _flat_model_material(color)
	var stack: Array = [root]
	while stack.size() > 0:
		var node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is MeshInstance3D:
			# material_override beats every surface material on the mesh in one shot.
			node.material_override = material


func _flat_model_material(color: Color) -> StandardMaterial3D:
	if _flat_model_materials.has(color):
		return _flat_model_materials[color]

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	# Banded toon lighting (a hard light/shadow step instead of a smooth gradient) for the
	# cartoon look; the inverted-hull pass below draws the black outline.
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.next_pass = _outline_material(color)
	_flat_model_materials[color] = material
	return material


# Inverted-hull outline pass for a given tint: unshaded back faces in a darkened shade of the
# tint, grown along the normals so they peek out behind the model as a silhouette rim.
func _outline_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color.darkened(MODEL_OUTLINE_DARKEN)
	material.cull_mode = BaseMaterial3D.CULL_FRONT
	material.grow = true
	material.grow_amount = MODEL_OUTLINE_GROW
	return material


# Native bounds of a freshly-instanced model (added at origin), merged over its meshes.
func _instance_aabb(root: Node3D) -> AABB:
	var combined := AABB()
	var has := false
	var stack: Array = [root]
	while stack.size() > 0:
		var node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is MeshInstance3D:
			var world_aabb: AABB = node.global_transform * node.get_aabb()
			if not has:
				combined = world_aabb
				has = true
			else:
				combined = combined.merge(world_aabb)
	return combined


func _spawn_item(cell: Vector2i, item_type: int) -> void:
	var texture: Texture2D = ITEM_TEXTURES.get(item_type)
	if texture == null:
		return

	var sprite := _make_billboard(texture, Vector2(0.5, 0.5), Vector2.ZERO)
	sprite.position = _ground_anchor([cell])
	_lift_to_ground(sprite)
	_objects_root.add_child(sprite)


func _spawn_building(anchor_cell: Vector2i, building_type: int) -> void:
	var definition := building_manager.get_definition(building_type)
	if definition == null:
		return

	var footprint := island.get_building_footprint_cells(anchor_cell)
	if footprint.is_empty():
		footprint = [anchor_cell]

	if definition.model != null:
		_spawn_model(
			definition.model,
			footprint,
			definition.visual_size_tiles,
			definition.visual_offset_tiles,
			definition.visual_rotation_y,
			Color(0.0, 0.0, 0.0, 0.0),
			definition.spin_node_name,
			definition.spin_axis,
			definition.spin_speed_degrees
		)
		return

	if definition.texture == null:
		return

	var sprite := _make_billboard(definition.texture, definition.visual_size_tiles, definition.visual_offset_tiles)
	sprite.position = _ground_anchor(footprint) + _offset_xz(definition.visual_offset_tiles)
	_lift_to_ground(sprite)
	_objects_root.add_child(sprite)


func _spawn_boat(water_cell: Vector2i) -> void:
	var sprite := _make_billboard(ROWBOAT_TEXTURE, BOAT_SIZE_TILES, Vector2.ZERO)
	sprite.position = get_cell_center(water_cell)
	_lift_to_ground(sprite)
	_objects_root.add_child(sprite)


# --- Placement preview ---

func _rebuild_preview() -> void:
	if _preview_root == null:
		return

	_clear(_preview_root)

	if not placement_preview_enabled or island == null or hovered_cell == Vector2i(-1, -1):
		return

	var footprint := building_manager.get_footprint_cells(hovered_cell, placement_building_type)
	var can_place := building_manager.can_place(hovered_cell, placement_building_type, island) and placement_can_afford
	var tint := Color(0.45, 1.0, 0.5, 0.4) if can_place else Color(1.0, 0.3, 0.3, 0.4)

	for cell in footprint:
		if not island.is_in_bounds(cell):
			continue
		var marker := MeshInstance3D.new()
		marker.mesh = _cap_mesh
		marker.material_override = _make_overlay_material(tint)
		var center := get_cell_center(cell)
		marker.position = Vector3(center.x, center.y + 0.6, center.z)
		_preview_root.add_child(marker)

	var definition := building_manager.get_definition(placement_building_type)
	if definition != null and definition.texture != null:
		var ghost := _make_billboard(definition.texture, definition.visual_size_tiles, definition.visual_offset_tiles)
		ghost.modulate = Color(1.0, 1.0, 1.0, 0.6)
		ghost.position = _ground_anchor(footprint) + _offset_xz(definition.visual_offset_tiles)
		_lift_to_ground(ghost)
		_preview_root.add_child(ghost)

	# Yield highlight: only meaningful for a legal spot, so the player reads the value
	# of a placement they can actually commit. Mark the neighbor cells that change output
	# (blue = deposits tapped, orange = crowding penalty) and float the net per-cycle gain.
	if can_place and definition != null and not definition.adjacency_yields.is_empty():
		var yield_cells := building_manager.get_yield_cells(hovered_cell, placement_building_type, island)
		for cell in yield_cells.positive:
			_preview_root.add_child(_make_yield_marker(cell, Color(0.4, 0.85, 1.0, 0.5)))
		for cell in yield_cells.negative:
			_preview_root.add_child(_make_yield_marker(cell, Color(1.0, 0.55, 0.2, 0.5)))

		# A generator's adjacency shapes its power; everything else shapes resource output.
		if definition.category == GameTypes.BuildingCategory.POWER:
			var power := building_manager.get_power_generated(hovered_cell, placement_building_type, island)
			_preview_root.add_child(_make_yield_label(footprint, power, " MW"))
		else:
			var output := building_manager.get_production_amount(hovered_cell, placement_building_type, island)
			_preview_root.add_child(_make_yield_label(footprint, output, ""))


# A flat hex cap tinted over a neighbor cell that contributes to placement yield.
# Drawn on top (no depth test) so it stays visible over the tall stone-deposit models
# sitting on the very cells it needs to highlight, rather than being buried at their base.
func _make_yield_marker(cell: Vector2i, color: Color) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.mesh = _cap_mesh
	var material := _make_overlay_material(color)
	material.no_depth_test = true
	marker.material_override = material
	var center := get_cell_center(cell)
	marker.position = Vector3(center.x, center.y + 0.55, center.z)
	return marker


# Billboarded "+N" floating over the footprint, showing the building's per-cycle output
# at this spot. Matches the FloatingText scale (font 22 @ pixel_size 1.5).
func _make_yield_label(footprint: Array, output: int, unit: String) -> Label3D:
	var label := Label3D.new()
	label.text = "+%d%s" % [output, unit]
	label.font_size = 28
	label.pixel_size = 1.5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(0.6, 1.0, 0.65, 1.0)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.outline_size = 8
	var anchor := _ground_anchor(footprint)
	label.position = Vector3(anchor.x, anchor.y + 5.0, anchor.z)
	return label


# --- Hover ---

# Recolor the cell under the cursor in place (brightened terrain), restoring the
# previously hovered cell. Recoloring the actual tile avoids the depth/parallax artifacts
# of a separate overlay mesh floating above the surface.
func _update_hover() -> void:
	if _highlighted_cell != Vector2i(-1, -1):
		_restore_tile(_highlighted_cell)
		_highlighted_cell = Vector2i(-1, -1)

	if island == null or hovered_cell == Vector2i(-1, -1):
		return

	var tile = _tiles.get(hovered_cell)
	if tile != null:
		tile.material_override = _highlight_material(island.get_terrain(hovered_cell))
		_highlighted_cell = hovered_cell


func _restore_tile(cell: Vector2i) -> void:
	var tile = _tiles.get(cell)
	if tile != null and island != null:
		tile.material_override = _base_tile_material(island.get_terrain(cell))


# --- Sprite helper ---

# Builds a sprite laid flat on the ground (top-down decal) rather than an upright billboard.
func _make_billboard(texture: Texture2D, size_tiles: Vector2, _offset_tiles: Vector2) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	# Lay the sprite flat in the XZ plane, facing up; image top points away from the camera.
	sprite.rotation.x = -PI / 2.0
	sprite.shaded = false
	sprite.double_sided = true
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	# Scissor cut so the sprite writes depth and sorts correctly against terrain.
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD

	var target_width := size_tiles.x * cell_size.x
	var texture_width := maxi(1, texture.get_width())
	sprite.pixel_size = target_width / float(texture_width)
	return sprite


# Nudge a flat sprite just above the tile surface so it doesn't z-fight with the terrain top.
func _lift_to_ground(sprite: Sprite3D) -> void:
	sprite.position.y += 0.5


func _offset_xz(offset_tiles: Vector2) -> Vector3:
	return Vector3(offset_tiles.x * cell_size.x, 0.0, offset_tiles.y * cell_size.y)


# Ground point at the center of a (multi-cell) footprint, at land-surface height.
func _ground_anchor(cells: Array) -> Vector3:
	var sum := Vector3.ZERO
	for cell in cells:
		sum += get_cell_center(cell)
	return sum / float(maxi(1, cells.size()))


# --- Mesh builders ---

func _build_hex_prism_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Unit-height prism (y 0..1); instances scale Y to the desired top height. Normals are
	# set explicitly per face (flat shading) so the top is a uniformly lit flat hex cap and
	# the walls don't smooth into it (which would read as a rounded, shaded bump).
	var top := HexGridScript.hex_corners_3d(Vector3(0.0, 1.0, 0.0), cell_size)
	var bottom := HexGridScript.hex_corners_3d(Vector3.ZERO, cell_size)
	var center_top := Vector3(0.0, 1.0, 0.0)

	st.set_normal(Vector3.UP)
	for i in range(6):
		st.add_vertex(center_top)
		st.add_vertex(top[i])
		st.add_vertex(top[(i + 1) % 6])

	for i in range(6):
		var b0 := bottom[i]
		var b1 := bottom[(i + 1) % 6]
		var t0 := top[i]
		var t1 := top[(i + 1) % 6]
		var mid := (b0 + b1) * 0.5
		st.set_normal(Vector3(mid.x, 0.0, mid.z).normalized())
		st.add_vertex(b0)
		st.add_vertex(b1)
		st.add_vertex(t1)
		st.add_vertex(b0)
		st.add_vertex(t1)
		st.add_vertex(t0)

	return st.commit()


func _build_hex_cap_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var ring := HexGridScript.hex_corners_3d(Vector3.ZERO, cell_size)
	st.set_normal(Vector3.UP)
	for i in range(6):
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(ring[i])
		st.add_vertex(ring[(i + 1) % 6])

	return st.commit()


func _make_overlay_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


# --- Small helpers ---

func _terrain_of(cell: Vector2i) -> int:
	if island == null:
		return GameTypes.Terrain.WATER
	return island.get_terrain(cell)


func _terrain_top_y(terrain_type: int) -> float:
	match terrain_type:
		GameTypes.Terrain.GRASS:
			return GRASS_TOP_Y
		GameTypes.Terrain.SAND:
			return SAND_TOP_Y
		GameTypes.Terrain.STONE:
			return STONE_TOP_Y
		_:
			return WATER_TOP_Y


# Top height of a water cell's seabed prism: coast sits just under the surface, open ocean
# drops deeper, so the basin gets shallower toward the shore.
func _water_seabed_top_y(terrain_type: int) -> float:
	return COAST_SEABED_TOP_Y if terrain_type == GameTypes.Terrain.COAST else OCEAN_SEABED_TOP_Y


# Visible top height of a cell's tile: a land cap height, or the dropped seabed top for water.
func _tile_top_y(terrain_type: int) -> float:
	return _water_seabed_top_y(terrain_type) if GameTypes.is_water(terrain_type) else _terrain_top_y(terrain_type)


# Cells that read as interactive plots: land and shallow coast get the grid and hover
# highlight; deep ocean does not.
func _is_plot_cell(terrain_type: int) -> bool:
	return terrain_type != GameTypes.Terrain.WATER


# Land caps only — water cells render the seabed via _seabed_color, so this is never
# called with WATER/COAST.
func _color_for_terrain(terrain_type: int) -> Color:
	match terrain_type:
		GameTypes.Terrain.GRASS:
			return GRASS_COLOR
		GameTypes.Terrain.SAND:
			return SAND_COLOR
		_:
			return STONE_COLOR


func _cell_contains_xz(cell: Vector2i, point: Vector2) -> bool:
	var center := HexGridScript.cell_center_3d(cell, cell_size)
	var corners := HexGridScript.hex_corners_3d(center, cell_size)
	var polygon := PackedVector2Array()
	for corner in corners:
		polygon.append(Vector2(corner.x, corner.z))
	return HexGridScript.point_in_polygon(point, polygon)


func _dock_boat_cell(dock_cell: Vector2i) -> Vector2i:
	for neighbor in HexGridScript.neighbors(dock_cell):
		if island.is_in_bounds(neighbor) and GameTypes.is_water(island.get_terrain(neighbor)):
			return neighbor
	return Vector2i(-1, -1)


func _row_offset(row: int) -> float:
	return 0.5 if row % 2 != 0 else 0.0


func _clear(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		child.queue_free()
