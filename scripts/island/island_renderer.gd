class_name IslandRenderer
extends Node3D

# 3D island renderer (see docs/3d-conversion.md, Phase 2). Terrain is built from
# code-generated hex prisms (one shared mesh, one instance per cell, tinted by terrain
# and raised by elevation). Buildings, resource nodes, ground items, and dock boats are
# drawn as upright Sprite3D billboards reusing the existing 2D art (the 2.5D approach).
#
# The public interface is kept compatible with the 2D renderer it replaces so main.gd
# and player_unit.gd are largely unchanged: render(), refresh(), get_cell_center(),
# cell_to_world(), world_to_cell(), set_hovered_world_position(), set_placement_preview(),
# try_place_hovered_building(), get_hovered_building_type(), hovered_cell, cell_size.

const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const ROWBOAT_TEXTURE := preload("res://assets/vehicles/rowboat.png")

const ITEM_TEXTURES := {
	GameTypes.ItemType.AXE: preload("res://assets/icons/axe.png"),
	GameTypes.ItemType.PICKAXE: preload("res://assets/icons/pickaxe.png"),
	GameTypes.ItemType.HAMMER: preload("res://assets/icons/hammer.png"),
}

const BOAT_SIZE_TILES := Vector2(0.8, 0.8)

const SAND_COLOR := Color("#e3bc83")
const GRASS_COLOR := Color("#9ea131")
const STONE_COLOR := Color("#8e8791")
const SHALLOW_WATER_COLOR := Color("#479bd2")
const DEEP_WATER_COLOR := Color("#2a7ebf")

# Prism top heights per terrain (world units). Land sits above water for a layered
# island silhouette; the differences are small so unit movement reads as gentle steps.
const WATER_TOP_Y := 6.0
const SAND_TOP_Y := 14.0
const GRASS_TOP_Y := 20.0
const STONE_TOP_Y := 26.0

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
var _hover_mesh: MeshInstance3D
var _prism_mesh: ArrayMesh
var _cap_mesh: ArrayMesh
var _terrain_materials := {}


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

	_hover_mesh = MeshInstance3D.new()
	_hover_mesh.name = "Hover"
	_hover_mesh.mesh = _cap_mesh
	_hover_mesh.material_override = _make_overlay_material(Color(1.0, 1.0, 1.0, 0.18))
	_hover_mesh.visible = false
	add_child(_hover_mesh)


func setup(new_resource_node_database: ResourceNodeDatabase, new_building_manager: BuildingManager) -> void:
	resource_node_database = new_resource_node_database
	building_manager = new_building_manager


# Full rebuild — terrain and all objects. Called on island entry/switch.
func render(new_island: IslandData) -> void:
	island = new_island
	hovered_cell = Vector2i(-1, -1)
	if _hover_mesh != null:
		_hover_mesh.visible = false
	_rebuild_terrain()
	_rebuild_objects()
	_rebuild_preview()


# Object-only rebuild — cheaper, for placements and ground-item pickups (replaces the
# old queue_redraw() calls).
func refresh() -> void:
	_rebuild_objects()
	_rebuild_preview()


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


# Y of the horizontal plane main.gd raycasts against for mouse picking — the land
# surface, where most interaction happens.
func ground_pick_y() -> float:
	return GRASS_TOP_Y


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


func set_hovered_world_position(world_position: Vector3) -> void:
	var cell := world_to_cell(world_position)

	if island == null or not island.is_in_bounds(cell):
		cell = Vector2i(-1, -1)

	if hovered_cell == cell:
		return

	hovered_cell = cell
	_update_hover_mesh()
	if placement_preview_enabled:
		_rebuild_preview()


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
	if island == null:
		return

	for y in range(island.height):
		for x in range(island.width):
			var cell := Vector2i(x, y)
			var terrain_type := island.get_terrain(cell)
			var tile := MeshInstance3D.new()
			tile.mesh = _prism_mesh
			tile.material_override = _terrain_material(terrain_type)
			tile.position = cell_to_world(cell)
			tile.scale = Vector3(1.0, _terrain_top_y(terrain_type), 1.0)
			_terrain_root.add_child(tile)


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
	if definition == null or definition.texture == null:
		return

	var sprite := _make_billboard(definition.texture, definition.visual_size_tiles, definition.visual_offset_tiles)
	sprite.position = _ground_anchor([cell]) + _offset_xz(definition.visual_offset_tiles)
	_lift_to_ground(sprite)
	_objects_root.add_child(sprite)


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
	if definition == null or definition.texture == null:
		return

	var footprint := island.get_building_footprint_cells(anchor_cell)
	if footprint.is_empty():
		footprint = [anchor_cell]

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


# --- Hover ---

func _update_hover_mesh() -> void:
	if _hover_mesh == null:
		return

	if hovered_cell == Vector2i(-1, -1):
		_hover_mesh.visible = false
		return

	var center := get_cell_center(hovered_cell)
	_hover_mesh.position = Vector3(center.x, center.y + 0.5, center.z)
	_hover_mesh.visible = true


# --- Billboard helper ---

func _make_billboard(texture: Texture2D, size_tiles: Vector2, _offset_tiles: Vector2) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.shaded = false
	sprite.double_sided = true
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	# Scissor cut so the sprite writes depth and sorts correctly against terrain.
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD

	var target_width := size_tiles.x * cell_size.x
	var texture_width := maxi(1, texture.get_width())
	sprite.pixel_size = target_width / float(texture_width)
	return sprite


# Raise a (centered) Sprite3D so its bottom edge rests on the ground at its current XZ.
func _lift_to_ground(sprite: Sprite3D) -> void:
	if sprite.texture == null:
		return
	var world_height := sprite.texture.get_height() * sprite.pixel_size
	sprite.position.y += world_height * 0.5


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

	# Unit-height prism (y 0..1); instances scale Y to the desired top height.
	var top := HexGridScript.hex_corners_3d(Vector3(0.0, 1.0, 0.0), cell_size)
	var bottom := HexGridScript.hex_corners_3d(Vector3.ZERO, cell_size)
	var center_top := Vector3(0.0, 1.0, 0.0)

	for i in range(6):
		var a := top[i]
		var b := top[(i + 1) % 6]
		st.add_vertex(center_top)
		st.add_vertex(a)
		st.add_vertex(b)

	for i in range(6):
		var b0 := bottom[i]
		var b1 := bottom[(i + 1) % 6]
		var t0 := top[i]
		var t1 := top[(i + 1) % 6]
		st.add_vertex(b0)
		st.add_vertex(b1)
		st.add_vertex(t1)
		st.add_vertex(b0)
		st.add_vertex(t1)
		st.add_vertex(t0)

	st.generate_normals()
	return st.commit()


func _build_hex_cap_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var ring := HexGridScript.hex_corners_3d(Vector3.ZERO, cell_size)
	for i in range(6):
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(ring[i])
		st.add_vertex(ring[(i + 1) % 6])

	st.generate_normals()
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


func _color_for_terrain(terrain_type: int) -> Color:
	match terrain_type:
		GameTypes.Terrain.GRASS:
			return GRASS_COLOR
		GameTypes.Terrain.SAND:
			return SAND_COLOR
		GameTypes.Terrain.STONE:
			return STONE_COLOR
		_:
			return SHALLOW_WATER_COLOR


func _cell_contains_xz(cell: Vector2i, point: Vector2) -> bool:
	var center := HexGridScript.cell_center_3d(cell, cell_size)
	var corners := HexGridScript.hex_corners_3d(center, cell_size)
	var polygon := PackedVector2Array()
	for corner in corners:
		polygon.append(Vector2(corner.x, corner.z))
	return HexGridScript.point_in_polygon(point, polygon)


func _dock_boat_cell(dock_cell: Vector2i) -> Vector2i:
	for neighbor in HexGridScript.neighbors(dock_cell):
		if island.is_in_bounds(neighbor) and island.get_terrain(neighbor) == GameTypes.Terrain.WATER:
			return neighbor
	return Vector2i(-1, -1)


func _row_offset(row: int) -> float:
	return 0.5 if row % 2 != 0 else 0.0


func _clear(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		child.queue_free()
