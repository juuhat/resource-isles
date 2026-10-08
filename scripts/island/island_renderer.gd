class_name IslandRenderer
extends Node3D

# 3D island renderer (see docs/3d-models.md). Terrain is built from
# code-generated hex prisms (one shared mesh, one instance per cell, tinted by terrain
# and raised by elevation). Buildings, resource nodes, ground items, and dock boats are
# drawn as upright Sprite3D billboards reusing the existing 2D art (the 2.5D approach).
#
# The public interface is kept compatible with the 2D renderer it replaces so main.gd
# and player_unit.gd are largely unchanged: render(), refresh(), get_cell_center(),
# cell_to_world(), world_to_cell(), set_hovered_cell(), set_placement_preview(),
# try_place_hovered_building(), get_hovered_building_type(), hovered_cell, cell_size.
#
# Every island on the disc has its own renderer (see WorldView). Island cells are world lattice
# cells (WorldNavigation), and every renderer sits at the same offset from the world origin, so a
# cell's renderer-local centre is just HexGrid.cell_center_3d(cell). The public positional API
# (get_cell_center, get_step_height, get_map_center, world_to_cell, cell_from_ray) speaks world
# space, so units, popups and the camera never need to know the renderer's offset.

const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const HexPathfinderScript := preload("res://scripts/island/hex_pathfinder.gd")
const BladeSpinnerScript := preload("res://scripts/island/blade_spinner.gd")
const PowerIndicatorScript := preload("res://scripts/island/power_indicator.gd")
const PoweredSpinnerScript := preload("res://scripts/island/powered_spinner.gd")
const ConstructionSiteScript := preload("res://scripts/island/construction_site.gd")
const ShipWreckScript := preload("res://scripts/island/ship_wreck.gd")
const TERRAIN_SHADER := preload("res://assets/shaders/terrain.gdshader")
const TERRAIN_NOISE := preload("res://assets/shaders/terrain_noise.tres")
# Toon water (see assets/shaders/water_toon.gdshader): a transparent animated plane whose
# depth bands, foam rim and swell lines all key off the distance to the nearest land hex —
# exact near the shore (per-cell land mask), baked coarse further out (set in _rebuild_water).
const WATER_TOON_SHADER := preload("res://assets/shaders/water_toon.gdshader")
const WATER_SURFACE_NOISE := preload("res://assets/shaders/water_toon/PerlinNoise.png")
const WATER_DISTORT_NOISE := preload("res://assets/shaders/water_toon/WaterDistortion.png")
# The tier-1 boat (tools/build_salvage_skiff.py), moored at a dock's BoatSpot.
const SALVAGE_SKIFF_MODEL := preload("res://assets/models/boats/salvage_skiff.glb")
const MOORED_BOAT_NAME := "MooredBoat"

const ITEM_TEXTURES := {
	GameTypes.ItemType.AXE: preload("res://assets/icons/axe.png"),
	GameTypes.ItemType.PICKAXE: preload("res://assets/icons/pickaxe.png"),
}
# The robot's lost tools lying on the ground (tools/build_robot_tools.py), at true tile scale with
# their origin on the ground at the centre of their bounds. ITEM_TEXTURES is the fallback.
const ITEM_MODELS := {
	GameTypes.ItemType.AXE: preload("res://assets/models/items/axe.glb"),
	GameTypes.ItemType.PICKAXE: preload("res://assets/models/items/pickaxe.glb"),
	GameTypes.ItemType.WRENCH: preload("res://assets/models/items/wrench.glb"),
}

# Model units per tile for BuildingDefinition.true_tile_model (lowpoly_kit.TILE).
const TRUE_TILE_UNITS := 2.0
# How much of a step onto or off a deck the hop up or down takes (see get_step_height): the dock's
# walkway starts 0.1 of a step out from the quay tile's centre (tools/build_dock.py, WALK_X0).
const DECK_STEP_FRACTION := 0.15
# Red "no power" bolt over unpowered consumers: its height and the gap above the roof, in tiles.
const POWER_INDICATOR_HEIGHT_TILES := 0.5
const POWER_INDICATOR_GAP_TILES := 0.12
# Moving parts a power consumer's model may carry, spun while it is powered (PoweredSpinner):
# node name -> [model-local axis, degrees per second]. FlywheelPivot and SocketRotor come with
# the shared PTO generator (tools/build_shared_generator.py); SawBladePivot is the sawmill's.
# The logger's felling axe (AxeHelvePivot) rests in the tree's notch and swings back STRIKE
# degrees about its vertical shaft once per stroke.
const AXE_STRIKE_DEGREES := 40.0 # matches STRIKE_DEGREES in tools/build_logger_camp.py
const AXE_CHOP_SECONDS := 1.6
const BELLOWS_PERIOD_SECONDS := 1.6
const BELLOWS_HEIGHT := 0.20 # native model units, tools/build_furnace.py
const POWERED_SPIN_PARTS := {
	"SawBladePivot": [Vector3(0, 0, -1), 420.0],
	"AxePulleyPivot": [Vector3(1, 0, 0), 360.0],
	"DrillPivot": [Vector3(0, 1, 0), 360.0],
	"DrillPulleyPivot": [Vector3(1, 0, 0), 360.0],
	"FlywheelPivot": [Vector3(1, 0, 0), 300.0],
	"SocketRotor": [Vector3(0, 0, 1), 300.0],
	"BellowsCamPivot": [Vector3(1, 0, 0), 360.0 / BELLOWS_PERIOD_SECONDS],
}

const SAND_COLOR := Color("#d3b586")
const GRASS_COLOR := Color("#879347")
const STONE_COLOR := Color("#8a8794")
const GRID_IDLE_ALPHA := 0.045
const GRID_PLACEMENT_ALPHA := 0.18
# Hover tint for a cell the selected robot can work (see is_cell_actionable): the terrain colour
# pulled most of the way to this green.
const ACTION_HOVER_COLOR := Color("#4fe36f")
const ACTION_HOVER_WEIGHT := 0.8
# Seabed tones seen through the translucent water. The coast shelf is a pale aqua sand so the
# shallows read turquoise over it; the water shader supplies the depth colours themselves.
const SEABED_COAST_COLOR := Color("#7cc9c6")
const SEABED_OCEAN_COLOR := Color("#1c8fe9")

# Prism top heights (world units). Land stands at its elevation level (IslandData.get_elevation):
# level 0 is a beach just above the water, and each level is a step higher. Each ground's usual
# level gives sand, grass and rock the gentle steps islands had before cells got their own heights;
# an island design raises cells further for plateaus and cliffy shores.
const WATER_TOP_Y := 6.0
const SAND_TOP_Y := 14.0
const ELEVATION_STEP := 6.0
const GRASS_TOP_Y := SAND_TOP_Y + ELEVATION_STEP
const MAX_TOP_Y := SAND_TOP_Y + IslandData.MAX_ELEVATION * ELEVATION_STEP
# How much of a step between tiles of different heights a walking unit takes to climb up (or drop
# down) it, ending (or starting) right at the tiles' shared edge, so it never cuts into the cliff.
const CLIMB_FRACTION := 0.14
# Picking walks a camera ray down through the island's heights in steps this long (see
# cell_from_ray).
const PICK_STEP := 4.0

# Water cells are flat tiles at one level (no basin) a few units under the translucent
# surface plane, so the shelf and its drop-off read with a little parallax. They still drop to
# WATER_FLOOR_Y underneath so the map edges read as solid water rather than a thin sheet.
const WATER_TILE_TOP_Y := WATER_TOP_Y - 3.0
const COAST_SEABED_TOP_Y := WATER_TILE_TOP_Y
const OCEAN_SEABED_TOP_Y := WATER_TILE_TOP_Y
const WATER_FLOOR_Y := -8.0

# The island's toon-water plane is a disc around the island, fading out over its last
# WATER_FADE_WIDTH units into the shared open sea (WorldView), whose deep water looks the same.
# It reaches past the island's farthest land by the shore shading's reach (far_distance) and the
# fade, so a small island's plane is small too; never more than WATER_PLANE_RADIUS, which a
# ring island's plane stayed under so neighbours' planes never overlapped.
const WATER_PLANE_RADIUS := 3150.0
const WATER_FADE_WIDTH := 650.0

@export var cell_size := Vector2(128.0, 128.0)
@export var show_grid := true

var island: IslandData
var world_data: WorldData
var resource_node_database: ResourceNodeDatabase
var building_manager: BuildingManager
var hovered_cell := GameTypes.NO_CELL
var placement_preview_enabled := false
var placement_building_type := GameTypes.BuildingType.LOGGER_CAMP
var placement_can_afford := true
# The player's chosen footprint turn (60-degree steps, R while placing). Placement may use another
# for an auto_rotate building, see placement_rotation_at.
var placement_rotation := 0
# Optional veto on building placement, set by main: returns true for a cell a unit is standing on
# (or walking into), so construction never drops geometry on the robot or the dog.
var is_cell_occupied_by_unit := Callable()
# Optional, set by main: true for a cell the selected robot would start working on if sent there
# (harvest, operate, rescue). The hover tints such a cell green instead of brightening it.
var is_cell_actionable := Callable()
# Optional, set by WorldView: (GameTypes.QuestTargetKind, value) -> true while an active quest
# highlights that target (QuestManager.is_highlighted), so it glows (QuestHighlight).
var is_quest_highlighted := Callable()
# Anchor cell -> world position of the building model's WorkSpot marker, if it has one.
var _work_spots := {}
# Cell -> the ground item's model there, and the wreck's ShipWreck, for update_quest_highlights.
var _item_models := {}
var _wrecks: Array[ShipWreck] = []

var _terrain_root: Node3D
var _objects_root: Node3D
var _preview_root: Node3D
var _grid_instance: MeshInstance3D
var _water_instance: MeshInstance3D
var _water_material: ShaderMaterial
var _prism_mesh: ArrayMesh
var _cap_mesh: ArrayMesh
var _terrain_materials := {}
# cell -> the terrain MeshInstance3D for that cell, so hover can recolor it in place.
var _tiles := {}
var _highlighted_cell := GameTypes.NO_CELL
var _explored := true
# The top of the island's tallest land tile, set by _rebuild_terrain (see _max_top_y).
var _land_top_y := WATER_TOP_Y


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
	hovered_cell = GameTypes.NO_CELL
	_highlighted_cell = GameTypes.NO_CELL
	_rebuild_terrain()
	_rebuild_water()
	_rebuild_grid()
	_rebuild_objects()
	_rebuild_preview()
	_apply_exploration_style()


# Object-only rebuild — cheaper, for placements and ground-item pickups (replaces the
# old queue_redraw() calls).
func refresh() -> void:
	_rebuild_objects()
	_rebuild_preview()


func set_show_grid(value: bool) -> void:
	show_grid = value
	if _grid_instance != null:
		_grid_instance.visible = value and _explored


# Keep the coastline readable before discovery, without revealing resources or buildings.
func set_explored(value: bool) -> void:
	if value == _explored:
		return
	_explored = value
	clear_interaction()
	_apply_exploration_style()


# While the chart patch over a newly discovered island opens, show only the objects the opening
# has reached, so none stand up through the chart. An infinite radius shows them all again.
func reveal_objects_within(center: Vector3, radius: float) -> void:
	for child: Node3D in _objects_root.get_children():
		var offset := child.global_position - center
		child.visible = Vector2(offset.x, offset.z).length() < radius


func _apply_exploration_style() -> void:
	if _terrain_root == null:
		return
	for tile: MeshInstance3D in _terrain_root.get_children():
		var terrain_type: int = tile.get_meta("terrain_type")
		tile.visible = _explored or not GameTypes.is_water(terrain_type)
		tile.set_instance_shader_parameter("explored", _explored)
	_objects_root.visible = _explored
	_preview_root.visible = _explored
	_grid_instance.visible = show_grid and _explored
	_water_instance.visible = _explored and island != null


# --- Coordinate mapping (delegates to HexGrid, see Phase 1) ---

func cell_to_world(cell: Vector2i) -> Vector3:
	return HexGridScript.cell_to_world_3d(cell, cell_size)


# World-space centre of a cell's top surface — where a unit, popup or the camera aims.
func get_cell_center(cell: Vector2i) -> Vector3:
	return position + _local_cell_center(cell)


func _local_cell_center(cell: Vector2i) -> Vector3:
	var center := HexGridScript.cell_center_3d(cell, cell_size)
	center.y = _cell_top_y(cell)
	var decks := HexPathfinderScript.deck_cells(island) if island != null else {}
	if decks.has(cell) and building_manager != null:
		# A deck's floor (the dock's pier), raised above its building's anchor ground.
		var anchor_cell: Vector2i = decks[cell]
		var definition := building_manager.get_definition(island.get_building_type(anchor_cell))
		center.y = _cell_top_y(anchor_cell) + definition.deck_height_tiles * cell_size.x
	return center


# Height of a unit at world_position on its way from from_cell to the neighbouring to_cell. It
# walks a straight line between the tile centres and keeps to the ground under it: level across
# a tile, then up (or down) the step at the tiles' shared edge, rather than on a ramp that would
# float over the lower tile and sink into the higher one. Stepping onto or off a deck, the pier's
# boards reach back over the quay's tile, so the unit hops up onto them as it sets off (or down
# off them as it arrives) instead.
func get_step_height(from_cell: Vector2i, to_cell: Vector2i, world_position: Vector3) -> float:
	var from := get_cell_center(from_cell)
	var to := get_cell_center(to_cell)
	if is_equal_approx(from.y, to.y):
		return world_position.y

	var decks := HexPathfinderScript.deck_cells(island) if island != null else {}
	var onto := decks.has(to_cell) and not decks.has(from_cell)
	var off := decks.has(from_cell) and not decks.has(to_cell)
	# The stretch of the leg (0 at from, 1 at to) over which the unit climbs or drops.
	var climb := Vector2(0.5 - CLIMB_FRACTION, 0.5) if to.y > from.y else Vector2(0.5, 0.5 + CLIMB_FRACTION)
	if onto:
		climb = Vector2(0.0, DECK_STEP_FRACTION)
	elif off:
		climb = Vector2(1.0 - DECK_STEP_FRACTION, 1.0)

	var leg := Vector2(to.x - from.x, to.z - from.z)
	var along := Vector2(world_position.x - from.x, world_position.z - from.z).dot(leg) / maxf(leg.length_squared(), 0.001)
	var t := clampf((along - climb.x) / (climb.y - climb.x), 0.0, 1.0)
	return lerpf(from.y, to.y, smoothstep(0.0, 1.0, t))


func world_to_cell(world_position: Vector3) -> Vector2i:
	return _local_to_cell(world_position - position)


func _local_to_cell(local_position: Vector3) -> Vector2i:
	if island == null:
		return GameTypes.NO_CELL

	var point := Vector2(local_position.x, local_position.z)
	var row := roundi(local_position.z / (cell_size.y * 0.75))
	var column := roundi(local_position.x / cell_size.x - _row_offset(row))
	var nearest_cell := Vector2i(column, row)
	var nearest_distance := INF

	for candidate_y in range(row - 1, row + 2):
		for candidate_x in range(column - 1, column + 2):
			var cell := Vector2i(candidate_x, candidate_y)
			if not island.has_cell(cell):
				continue

			if _cell_contains_xz(cell, point):
				return cell

			var center := HexGridScript.cell_center_3d(cell, cell_size)
			var distance := point.distance_squared_to(Vector2(center.x, center.z))
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_cell = cell

	return nearest_cell if island.has_cell(nearest_cell) else GameTypes.NO_CELL


func get_map_center() -> Vector3:
	return position + _local_map_center()


# Renderer-local centre of the bounds of the island's cell centres, at grass height.
func _local_map_center() -> Vector3:
	if island == null or island.terrain.is_empty():
		return Vector3.ZERO
	var bounds := _cell_center_bounds()
	var mid := bounds.get_center()
	return Vector3(mid.x, GRASS_TOP_Y, mid.y)


# The renderer-local XZ rectangle spanned by the centres of all the island's cells.
func _cell_center_bounds() -> Rect2:
	var min_xz := Vector2(INF, INF)
	var max_xz := Vector2(-INF, -INF)
	for cell in island.terrain:
		var center := HexGridScript.cell_center_3d(cell, cell_size)
		min_xz = min_xz.min(Vector2(center.x, center.z))
		max_xz = max_xz.max(Vector2(center.x, center.z))
	return Rect2(min_xz, max_xz - min_xz)


# Highlights the cell under the cursor (picked by WorldView.cell_from_ray), or nothing for a cell
# that isn't this island's. Placement previews follow it.
func set_hovered_cell(cell: Vector2i) -> void:
	if island == null or not island.has_cell(cell):
		cell = GameTypes.NO_CELL

	if hovered_cell == cell:
		return

	hovered_cell = cell
	_update_hover()
	if placement_preview_enabled:
		_rebuild_preview()


# Picks the hovered cell from a camera ray with per-tile height awareness: the ray is walked down
# from the top of the island's tallest tile to its seabed, and the first of the island's cells it
# passes into below that cell's top is the one under the cursor. A taller tile in front hides
# the one behind it, and pointing at the side of a cliff picks the cliff's tile.
func cell_from_ray(origin: Vector3, direction: Vector3) -> Vector2i:
	var local_origin := origin - position
	var bottom = _ray_plane_xz(local_origin, direction, WATER_TILE_TOP_Y)
	if bottom == null:
		return GameTypes.NO_CELL
	if island == null:
		return _local_to_cell(bottom)

	var top = _ray_plane_xz(local_origin, direction, _max_top_y())
	if top == null:
		top = local_origin
	var top_point: Vector3 = top
	var bottom_point: Vector3 = bottom
	var steps := maxi(1, ceili(Vector2(bottom_point.x - top_point.x, bottom_point.z - top_point.z).length() / PICK_STEP))
	for step in range(steps + 1):
		var point := top_point.lerp(bottom_point, float(step) / float(steps))
		var cell := _local_to_cell(point)
		if island.has_cell(cell) and point.y <= _local_cell_center(cell).y:
			return cell

	return _local_to_cell(bottom_point)


# Drop the hover highlight and any placement preview — used when this island stops being the
# one the player is working on.
func clear_interaction() -> void:
	placement_preview_enabled = false
	_update_grid_style()
	hovered_cell = GameTypes.NO_CELL
	_update_hover()
	_rebuild_preview()


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
	_update_grid_style()
	_rebuild_preview()
	# Placement mode turns the right-click into "cancel", so the action tint comes and goes.
	_update_hover()


# Re-tint the hovered cell after something outside the renderer changed whether it is
# actionable (robot selected or deselected, an action started or unlocked).
func refresh_hover() -> void:
	_update_hover()


func rotate_placement(steps: int) -> void:
	placement_rotation = posmod(placement_rotation + steps, 6)
	_rebuild_preview()


# The footprint turn a building placed at anchor_cell would get (BuildingManager.fit_rotation).
func placement_rotation_at(anchor_cell: Vector2i, building_type: int) -> int:
	return building_manager.fit_rotation(anchor_cell, building_type, island, placement_rotation)


# as_blueprint places it under construction, for the robot to build (IslandData.place_building).
func try_place_hovered_building(building_type: int = GameTypes.BuildingType.LOGGER_CAMP, as_blueprint := false) -> bool:
	if island == null or hovered_cell == GameTypes.NO_CELL:
		return false

	var rotation := placement_rotation_at(hovered_cell, building_type)
	if not _can_place_at(hovered_cell, building_type, rotation):
		return false

	var placed := building_manager.try_place(hovered_cell, building_type, island, rotation, as_blueprint)
	if placed:
		refresh()

	return placed


func remove_building(anchor_cell: Vector2i) -> bool:
	if island == null:
		return false

	var removed := building_manager.remove(anchor_cell, island)
	if removed:
		refresh()

	return removed


# Place a building at a specific (non-hovered) cell. Used to restore a building lifted for a
# move back to its original cell when the move is cancelled.
func place_building_at(anchor_cell: Vector2i, building_type: int, rotation: int = 0) -> bool:
	if island == null:
		return false

	var placed := building_manager.try_place(anchor_cell, building_type, island, rotation)
	if placed:
		refresh()

	return placed


func _can_place_at(anchor_cell: Vector2i, building_type: int, rotation: int) -> bool:
	if not building_manager.can_place(anchor_cell, building_type, island, rotation):
		return false
	if is_cell_occupied_by_unit.is_valid():
		for cell in building_manager.get_footprint_cells(anchor_cell, building_type, rotation):
			if is_cell_occupied_by_unit.call(cell):
				return false
	return true


# World position of the WorkSpot marker in the building model anchored at anchor_cell (where the
# robot stands to work it, see tools/lowpoly_kit.py marker()), or null when it has none.
func get_work_spot(anchor_cell: Vector2i) -> Variant:
	if not _work_spots.has(anchor_cell):
		return null
	return position + _work_spots[anchor_cell]


# Renderer-local position of `node`, a descendant of `model` (a child of _objects_root, which sits
# at the renderer origin). Walks the transforms by hand so it works before the renderer is in the
# scene tree.
func _local_position_in(node: Node3D, model: Node3D) -> Vector3:
	var xform := node.transform
	var parent := node.get_parent()
	while parent != null and parent != model:
		if parent is Node3D:
			xform = (parent as Node3D).transform * xform
		parent = parent.get_parent()
	return (model.transform * xform).origin


func get_hovered_building_type() -> int:
	if island == null or hovered_cell == GameTypes.NO_CELL:
		return -1

	return island.get_building_type(hovered_cell)


func get_hovered_resource_node_type() -> int:
	if island == null or hovered_cell == GameTypes.NO_CELL:
		return -1

	return island.get_resource_node_type(hovered_cell)


# --- Terrain ---

func _rebuild_terrain() -> void:
	_clear(_terrain_root)
	_tiles.clear()
	_land_top_y = WATER_TOP_Y
	if island == null:
		return

	for cell in island.terrain:
		var terrain_type := island.get_terrain(cell)
		# Deep ocean needs no seabed prism — the translucent water surface plane covers
		# it. Only the shallow coast shelf and land are built as tiles.
		if terrain_type == GameTypes.Terrain.WATER:
			continue
		var is_water := GameTypes.is_water(terrain_type)

		var tile := MeshInstance3D.new()
		tile.set_meta("terrain_type", terrain_type)
		tile.mesh = _prism_mesh
		# Land caps use their terrain colour; the submerged seabed uses sandy ground so
		# the blue reads as the translucent water above it, not painted-on floor.
		tile.material_override = _terrain_material(terrain_type)
		tile.set_instance_shader_parameter("hover_state", 0)
		tile.set_instance_shader_parameter("explored", _explored)
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
			var top := _cell_top_y(cell)
			tile.position = Vector3(center.x, 0.0, center.z)
			tile.scale = Vector3(1.0, top, 1.0)
			_land_top_y = maxf(_land_top_y, top)
		_terrain_root.add_child(tile)
		# Land and shallow coast are hover targets; deep ocean is purely visual.
		if _is_plot_cell(terrain_type):
			_tiles[cell] = tile


# Base flat colour for a cell's tile (drives the brightened hover highlight).
func _base_tile_color(terrain_type: int) -> Color:
	return _seabed_color(terrain_type) if GameTypes.is_water(terrain_type) else _color_for_terrain(terrain_type)


# One material per terrain type, shared by its cells; interaction is per-instance state.
func _terrain_material(terrain_type: int) -> ShaderMaterial:
	if _terrain_materials.has(terrain_type):
		return _terrain_materials[terrain_type]

	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	material.set_shader_parameter("ground_noise", TERRAIN_NOISE)
	material.set_shader_parameter("base_color", _base_tile_color(terrain_type))
	# WorldView keeps every renderer at height 0, so world heights match the local constants.
	material.set_shader_parameter("water_level", WATER_TOP_Y)
	# Match the existing sRGB feedback blends before the shader converts them to linear light.
	material.set_shader_parameter("hover_color", _base_tile_color(terrain_type).lightened(0.35))
	material.set_shader_parameter("action_hover_color", _base_tile_color(terrain_type).lerp(ACTION_HOVER_COLOR, ACTION_HOVER_WEIGHT))
	material.set_shader_parameter("silhouette_color", Color("#89959b"))
	match terrain_type:
		GameTypes.Terrain.GRASS:
			material.set_shader_parameter("patch_dark", Color("#737f43"))
			material.set_shader_parameter("patch_light", Color("#9da55d"))
			material.set_shader_parameter("soil_color", Color("#a18d65"))
			material.set_shader_parameter("soil_strength", 0.5)
			material.set_shader_parameter("side_color", Color("#80694a"))
			# Turf over the soil, and weathered rock under it on a cliff.
			material.set_shader_parameter("lip_color", Color("#6b7639"))
			material.set_shader_parameter("lip_depth", 1.6)
			material.set_shader_parameter("cliff_color", Color("#7a6e60"))
			material.set_shader_parameter("rock_strength", 1.0)
		GameTypes.Terrain.STONE:
			# Slate ground with a narrow patch range, so the green-grey deposit
			# rocks (lowpoly_kit 'stone', #89938D) stand apart from it.
			material.set_shader_parameter("patch_dark", Color("#7e7b89"))
			material.set_shader_parameter("patch_light", Color("#97949f"))
			material.set_shader_parameter("side_color", Color("#686673"))
		GameTypes.Terrain.SAND:
			material.set_shader_parameter("patch_dark", Color("#c3a779"))
			material.set_shader_parameter("patch_light", Color("#dfc499"))
			material.set_shader_parameter("side_color", Color("#b99b70"))
			# Raised sand weathers into sandstone.
			material.set_shader_parameter("cliff_color", Color("#a58f70"))
			material.set_shader_parameter("rock_strength", 1.0)
		_:
			material.set_shader_parameter("detail_strength", 0.0)
	_terrain_materials[terrain_type] = material
	return material


func _seabed_color(terrain_type: int) -> Color:
	return SEABED_COAST_COLOR if terrain_type == GameTypes.Terrain.COAST else SEABED_OCEAN_COLOR


# --- Water ---

# A single horizontal plane around the island at water height, fading out at _water_radius into
# the shared open sea. The shader gets the island's per-cell land mask (exact hex distance
# near the shore) and a coarse baked shore-distance field (the broad depth gradient) —
# mobile-safe, no depth-buffer reads, so the plane itself needs no subdivision. The renderer must
# already sit at its world position (the shader maps world space back onto the island's cells).
func _rebuild_water() -> void:
	if _water_instance == null:
		return

	if island == null or island.terrain.is_empty():
		_water_instance.visible = false
		return

	var bake := _build_shore_distance_texture()
	var center := _local_map_center()
	var radius := _water_radius(center, bake["far_distance"])
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	_water_instance.mesh = plane

	# The shader looks cells up in its own grid, numbered from the frame's corner; island_origin
	# and grid_min are given relative to that corner.
	var frame := _water_frame()
	var frame_offset := HexGridScript.cell_to_world_3d(frame.position, cell_size)
	var frame_origin := Vector2(position.x + frame_offset.x, position.z + frame_offset.z)
	_water_material.set_shader_parameter("island_origin", frame_origin)
	_water_material.set_shader_parameter("fade_center", Vector2(position.x + center.x, position.z + center.z))
	_water_material.set_shader_parameter("fade_radius", radius)
	_water_material.set_shader_parameter("fade_width", WATER_FADE_WIDTH)

	_water_material.set_shader_parameter("cell_mask", _build_land_mask_texture(frame))
	_water_material.set_shader_parameter("cell_count", frame.size)
	_water_material.set_shader_parameter("cell_size", cell_size)
	_water_material.set_shader_parameter("shore_distance", bake["texture"])
	_water_material.set_shader_parameter("grid_min", bake["min"] - Vector2(frame_offset.x, frame_offset.z))
	_water_material.set_shader_parameter("grid_size", bake["size"])
	_water_material.set_shader_parameter("far_distance", bake["far_distance"])

	_water_instance.position = Vector3(center.x, WATER_TOP_Y, center.z)
	_water_instance.visible = true


# How far the water plane reaches from its (renderer-local) centre: past the farthest land cell by
# the shore shading's reach and the fade, plus a cell to spare. Further out, the toon water is the
# same deep water as the open sea.
func _water_radius(center: Vector3, far_distance: float) -> float:
	var reach := 0.0
	for cell in island.terrain:
		if not GameTypes.is_water(island.get_terrain(cell)):
			var point := HexGridScript.cell_center_3d(cell, cell_size)
			reach = maxf(reach, Vector2(point.x - center.x, point.z - center.z).length())
	return minf(WATER_PLANE_RADIUS, reach + far_distance + WATER_FADE_WIDTH + cell_size.x)


# The toon water material. Colours and animation are tuned in the shader's uniform defaults;
# only the noise textures are bound here and the per-island data in _rebuild_water.
func _make_toon_water_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = WATER_TOON_SHADER
	material.set_shader_parameter("surface_noise", WATER_SURFACE_NOISE)
	material.set_shader_parameter("distort_noise", WATER_DISTORT_NOISE)
	return material


# The rectangle of cells the water shader numbers its own grid by: it covers the island and starts
# on an even row, so the shader's odd rows (shifted half a tile) are the world's odd rows too.
func _water_frame() -> Rect2i:
	var min_cell := Vector2i.MAX
	var max_cell := Vector2i.MIN
	for cell in island.terrain:
		min_cell = min_cell.min(cell)
		max_cell = max_cell.max(cell)
	min_cell.y -= posmod(min_cell.y, 2)
	return Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)


# One texel per cell of the frame, R = 1 for land. The shader tests the cells around each fragment
# against this to get the exact distance to the hexagonal coastline.
func _build_land_mask_texture(frame: Rect2i) -> ImageTexture:
	var image := Image.create(frame.size.x, frame.size.y, false, Image.FORMAT_R8)
	for cell in island.terrain:
		if not GameTypes.is_water(island.get_terrain(cell)):
			var texel: Vector2i = cell - frame.position
			image.set_pixel(texel.x, texel.y, Color(1.0, 0.0, 0.0))
	return ImageTexture.create_from_image(image)


# Bakes a coarse field over the map's world bounds: each texel is the distance from that world
# point to the nearest land hex, normalized by far_distance. Hexes are treated as their
# inscribed circle, which overestimates a little near corners — fine, since the shader takes
# the exact per-cell distance near the shore and only relies on this further out.
func _build_shore_distance_texture() -> Dictionary:
	var min_xz := Vector2(INF, INF)
	var max_xz := Vector2(-INF, -INF)
	var land_centers: Array[Vector2] = []

	for cell in island.terrain:
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

	# Inscribed radius of the pointy-top hex: the nearer of the side edge and the slanted edge.
	var half := cell_size * 0.5
	var inner_radius := minf(half.x, half.x * half.y / Vector2(half.x, half.y * 0.5).length())
	var far_distance := cell_size.x * 6.0
	var texture_width := 128
	var texture_height := maxi(1, roundi(texture_width * size.y / size.x))
	var image := Image.create(texture_width, texture_height, false, Image.FORMAT_R8)

	for j in range(texture_height):
		for i in range(texture_width):
			var point := min_xz + Vector2(
				(float(i) + 0.5) / float(texture_width) * size.x,
				(float(j) + 0.5) / float(texture_height) * size.y
			)
			var nearest := INF
			for land in land_centers:
				nearest = minf(nearest, point.distance_squared_to(land))
			var shore := 1.0
			if not land_centers.is_empty():
				shore = clampf((sqrt(nearest) - inner_radius) / far_distance, 0.0, 1.0)
			image.set_pixel(i, j, Color(shore, 0.0, 0.0))

	return {
		"texture": ImageTexture.create_from_image(image),
		"min": min_xz,
		"size": size,
		"far_distance": far_distance,
	}


# --- Grid ---

# A single line-mesh tracing the top hexagon of every land and shallow-coast cell. Lines sit
# just above the tile top to avoid z-fighting; only deep ocean is skipped, so the grid reads
# as the island's plots (coast lines sit on the seabed, seen through the water).
func _rebuild_grid() -> void:
	if _grid_instance == null:
		return

	_grid_instance.visible = show_grid and _explored

	if island == null:
		_grid_instance.mesh = null
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var has_segments := false

	for cell in island.terrain:
		var terrain_type := island.get_terrain(cell)
		if not _is_plot_cell(terrain_type):
			continue

		var center := HexGridScript.cell_center_3d(cell, cell_size)
		center.y = _tile_top_y(cell) + 0.5
		var corners := HexGridScript.hex_corners_3d(center, cell_size)
		for i in range(6):
			st.add_vertex(corners[i])
			st.add_vertex(corners[(i + 1) % 6])
			has_segments = true

	_grid_instance.mesh = st.commit() if has_segments else null


func _make_grid_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.0, 0.0, 0.0, GRID_IDLE_ALPHA)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _update_grid_style() -> void:
	if _grid_instance == null:
		return
	var material := _grid_instance.material_override as StandardMaterial3D
	material.albedo_color.a = GRID_PLACEMENT_ALPHA if placement_preview_enabled else GRID_IDLE_ALPHA


# --- Objects (billboards) ---

func _rebuild_objects() -> void:
	_clear(_objects_root)
	_work_spots.clear()
	_item_models.clear()
	_wrecks.clear()
	if island == null:
		return

	for cell in island.resources.keys():
		_spawn_resource(cell, island.resources[cell])

	for cell in island.items.keys():
		_spawn_item(cell, island.items[cell])

	for anchor_cell in island.buildings.keys():
		var building_type: int = island.buildings[anchor_cell].type
		_spawn_building(anchor_cell, building_type)

	# Parked boats on this island's cells; the piloted one is drawn by the robot.
	var boats: Dictionary = world_data.boats if world_data != null else {}
	for id in boats:
		var boat_cell: Vector2i = boats[id].cell
		if id == world_data.piloted_boat or not island.has_cell(boat_cell):
			continue
		var boat := SALVAGE_SKIFF_MODEL.instantiate() as Node3D
		_objects_root.add_child(boat)
		boat.scale = Vector3.ONE * cell_size.x / TRUE_TILE_UNITS
		boat.position = get_water_center(boat_cell) - position
		boat.rotation.y = float(boats[id].get("yaw", 0.0))


func _spawn_resource(cell: Vector2i, resource_node_type: int) -> void:
	var definition := resource_node_database.get_definition(resource_node_type)
	if definition == null:
		return

	if definition.model != null:
		var model := _spawn_model(definition.model, [cell], definition.visual_size_tiles, definition.visual_offset_tiles, definition.visual_rotation_y)
		if model != null:
			if definition.true_tile_model:
				_set_true_tile_scale(model, [cell])
			if definition.visual_yaw_variation > 0.0:
				# Derived from the cell so the heading stays put across refreshes.
				var t := float(absi(hash(cell)) % 1001) / 1000.0
				model.rotation.y += deg_to_rad(lerpf(-1.0, 1.0, t) * definition.visual_yaw_variation)
		return

	if definition.texture == null:
		return

	var sprite := _make_billboard(definition.texture, definition.visual_size_tiles, definition.visual_offset_tiles)
	sprite.position = _ground_anchor([cell]) + _offset_xz(definition.visual_offset_tiles)
	_lift_to_ground(sprite)
	_objects_root.add_child(sprite)


# Instances a 3D model on a (multi-cell) footprint: rotated to its heading, auto-scaled so
# its width spans size_tiles, and lifted so its lowest point rests on the ground.
func _spawn_model(
	scene: PackedScene,
	cells: Array,
	size_tiles: Vector2,
	offset_tiles: Vector2,
	rotation_y_degrees: float = 0.0,
	spin_node_name: String = "",
	spin_axis: Vector3 = Vector3.ZERO,
	spin_speed_degrees: float = 0.0
) -> Node3D:
	var model := scene.instantiate() as Node3D
	if model == null:
		return null

	# Added at origin first so its untransformed bounds read as native model space. Rotate
	# before measuring so the auto-scale fits the rotated footprint.
	_objects_root.add_child(model)
	model.rotation.y = deg_to_rad(rotation_y_degrees)
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

	return model


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
	var scene: PackedScene = ITEM_MODELS.get(item_type)
	if scene != null:
		var model := scene.instantiate() as Node3D
		var model_scale := cell_size.x / TRUE_TILE_UNITS
		model.scale = Vector3(model_scale, model_scale, model_scale)
		model.position = _ground_anchor([cell])
		# Dropped in the crash, so each lies at its own angle; derived from the cell so it stays
		# put across refreshes.
		model.rotation.y = deg_to_rad(float(absi(hash(cell)) % 360))
		_objects_root.add_child(model)
		_item_models[cell] = model
		_highlight_item(cell)
		return

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

	var under_construction := island.is_under_construction(anchor_cell)
	if definition.model != null:
		var rotation := island.get_building_rotation(anchor_cell)
		var model := _spawn_building_model(definition, footprint, rotation)
		if model != null:
			var spot := model.find_child("WorkSpot", true, false) as Node3D
			if spot != null:
				_work_spots[anchor_cell] = _local_position_in(spot, model)
			if island.buildings[anchor_cell].get("boat_launched", false):
				var moored := model.find_child(MOORED_BOAT_NAME, true, false)
				if moored != null:
					moored.free()
			if building_type == GameTypes.BuildingType.CRASHED_SPACESHIP:
				_dress_ship_wreck(anchor_cell, model)
		if model != null and under_construction:
			_dress_construction_site(anchor_cell, model, _spawn_building_model(definition, footprint, rotation))
			return
		if model != null and definition.power_consumed > 0:
			_spawn_power_indicator(anchor_cell, footprint, model)
			_add_powered_spinner(anchor_cell, model)
		return

	if definition.texture == null:
		return

	var sprite := _make_billboard(definition.texture, definition.visual_size_tiles, definition.visual_offset_tiles)
	sprite.position = _ground_anchor(footprint) + _offset_xz(definition.visual_offset_tiles)
	if under_construction:
		sprite.modulate = Color(0.45, 1.0, 0.9, 0.5)
	_lift_to_ground(sprite)
	_objects_root.add_child(sprite)


# A blueprint: the model printed up to the robot's progress inside a hologram of the finished
# building (ConstructionSite). It has no power bolt or spinning parts until it is built.
func _dress_construction_site(anchor_cell: Vector2i, model: Node3D, ghost_model: Node3D) -> void:
	# A teal plate on the reserved tiles, so the plot reads even before anything is built.
	for cell in island.get_building_footprint_cells(anchor_cell):
		var plate := MeshInstance3D.new()
		plate.mesh = _cap_mesh
		plate.material_override = _make_overlay_material(Color(0.36, 0.95, 0.86, 0.28))
		var center := _local_cell_center(cell)
		plate.position = Vector3(center.x, center.y + 0.6, center.z)
		_objects_root.add_child(plate)

	var site := ConstructionSiteScript.new()
	site.name = "ConstructionSite"
	_objects_root.add_child(site)
	site.setup(island, anchor_cell, model, ghost_model)


# The crashed ship shows each part broken or repaired, and a part under repair being printed
# (ShipWreck). It sits beside the model, unscaled, as ConstructionSite does.
func _dress_ship_wreck(anchor_cell: Vector2i, model: Node3D) -> void:
	var wreck := ShipWreckScript.new()
	wreck.name = "ShipWreck"
	wreck.is_quest_highlighted = is_quest_highlighted
	_objects_root.add_child(wreck)
	wreck.setup(world_data, island, anchor_cell, model)
	_wrecks.append(wreck)


# Puts the quest glow on whatever the active quests highlight here, and takes it off what they no
# longer do. Called when a quest completes; a render or refresh applies it as it draws.
func update_quest_highlights() -> void:
	for cell in _item_models:
		_highlight_item(cell)
	for wreck in _wrecks:
		wreck.update_quest_highlights()


func _highlight_item(cell: Vector2i) -> void:
	var model: Node3D = _item_models[cell]
	if is_instance_valid(model):
		QuestHighlight.set_on(model, is_quest_highlighted.is_valid()
			and is_quest_highlighted.call(GameTypes.QuestTargetKind.ITEM, island.items.get(cell, -1)))


# A building's model sized, placed and turned on its footprint, under _objects_root. Shared by
# placed buildings and the placement ghost so the ghost shows exactly what will be built.
func _spawn_building_model(definition: BuildingDefinition, footprint: Array, rotation: int) -> Node3D:
	var model := _spawn_model(
		definition.model,
		footprint,
		definition.visual_size_tiles,
		definition.visual_offset_tiles,
		definition.visual_rotation_y,
		definition.spin_node_name,
		definition.spin_axis,
		definition.spin_speed_degrees
	)
	if model != null:
		_fit_placed_model(model, definition, footprint, rotation)
		_moor_boat(model)
	return model


# Finishes a placed building's model after _spawn_model. A true_tile_model gets the kit's fixed
# scale (TILE model units per tile) with its origin, the footprint centroid, set right on the
# anchor tile's ground, so parts may reach below it. Then the model turns with its footprint:
# HexGrid rotation steps are counter-clockwise from above, as is a positive Y rotation. The origin
# sits on the footprint centroid, which the footprint turns about too, so the two stay matched.
func _fit_placed_model(model: Node3D, definition: BuildingDefinition, footprint: Array, rotation: int) -> void:
	if definition.true_tile_model:
		_set_true_tile_scale(model, footprint)
	model.rotation.y += deg_to_rad(60.0 * rotation)


# The kit's fixed scale (TILE model units per tile), with the model's origin set right on the
# footprint's ground anchor instead of fitted to its bounds.
func _set_true_tile_scale(model: Node3D, footprint: Array) -> void:
	var model_scale := cell_size.x / TRUE_TILE_UNITS
	model.scale = Vector3(model_scale, model_scale, model_scale)
	model.position = _ground_anchor(footprint)


# Floats the red power bolt over a consumer's roof. It shows/hides itself from the island's
# powered flag each frame, so it reacts to generators and the robot's Operate action without
# waiting for a re-render.
func _spawn_power_indicator(anchor_cell: Vector2i, footprint: Array, model: Node3D) -> void:
	var bounds := _objects_root.global_transform.affine_inverse() * _instance_aabb(model)
	var ground := _ground_anchor(footprint)
	var indicator := PowerIndicatorScript.new()
	indicator.name = "PowerIndicator"
	# Sits on the roof's top point; the bolt itself is lifted along screen-up from here.
	indicator.position = Vector3(ground.x, bounds.end.y, ground.z)
	_objects_root.add_child(indicator)
	indicator.setup(
		island,
		anchor_cell,
		POWER_INDICATOR_HEIGHT_TILES * cell_size.x,
		POWER_INDICATOR_GAP_TILES * cell_size.x
	)


# Spins whichever POWERED_SPIN_PARTS the consumer's model carries while the building is powered.
func _add_powered_spinner(anchor_cell: Vector2i, model: Node3D) -> void:
	var spinner := PoweredSpinnerScript.new()
	spinner.island = island
	spinner.anchor_cell = anchor_cell
	for part_name in POWERED_SPIN_PARTS:
		var part := model.find_child(part_name, true, false) as Node3D
		if part != null:
			spinner.add_target(part, POWERED_SPIN_PARTS[part_name][0], POWERED_SPIN_PARTS[part_name][1])
	var helve := model.find_child("AxeHelvePivot", true, false) as Node3D
	if helve != null:
		spinner.add_chop(helve, Vector3(0, -1, 0), AXE_STRIKE_DEGREES, AXE_CHOP_SECONDS)
	var bellows := model.find_child("BellowsBody", true, false) as Node3D
	var bellows_top := model.find_child("BellowsTop", true, false) as Node3D
	if bellows != null and bellows_top != null:
		spinner.add_bellows(bellows, bellows_top, BELLOWS_HEIGHT, BELLOWS_PERIOD_SECONDS)
	if spinner.has_targets():
		model.add_child(spinner)
	else:
		spinner.free()


# A building with a mooring (the dock) gets the salvage skiff tied up at its BoatSpot. Both are
# authored at true tile scale with the boat's bow along the marker's +X, so the skiff simply
# hangs off the marker and turns with the building; being part of the model, it shows in the
# placement ghost too.
func _moor_boat(model: Node3D) -> void:
	var boat_spot := model.find_child("BoatSpot", true, false) as Node3D
	if boat_spot == null:
		return
	var boat := SALVAGE_SKIFF_MODEL.instantiate() as Node3D
	boat.name = MOORED_BOAT_NAME
	boat_spot.add_child(boat)


func get_water_center(cell: Vector2i) -> Vector3:
	var center := HexGridScript.cell_center_3d(cell, cell_size) + position
	center.y = position.y + WATER_TOP_Y
	return center


# --- Placement preview ---

func _rebuild_preview() -> void:
	if _preview_root == null:
		return

	_clear(_preview_root)

	if not placement_preview_enabled or island == null or hovered_cell == GameTypes.NO_CELL:
		return

	var rotation := placement_rotation_at(hovered_cell, placement_building_type)
	var footprint := building_manager.get_footprint_cells(hovered_cell, placement_building_type, rotation)
	var can_place := _can_place_at(hovered_cell, placement_building_type, rotation) and placement_can_afford
	var tint := Color(0.45, 1.0, 0.5, 0.4) if can_place else Color(1.0, 0.3, 0.3, 0.4)

	for cell in footprint:
		if not island.has_cell(cell):
			continue
		var marker := MeshInstance3D.new()
		marker.mesh = _cap_mesh
		marker.material_override = _make_overlay_material(tint)
		var center := _local_cell_center(cell)
		marker.position = Vector3(center.x, center.y + 0.6, center.z)
		_preview_root.add_child(marker)

	var definition := building_manager.get_definition(placement_building_type)
	if definition != null and definition.model != null:
		# A see-through copy of the model, sized and turned exactly as it will be placed (a
		# multi-tile shape reads its rotation from the model, which a flat billboard can't show).
		# Built under _objects_root like a placed building, then moved over; both roots sit at the
		# renderer's origin, so reparenting keeps it in place.
		var ghost_model := _spawn_building_model(definition, footprint, rotation)
		if ghost_model != null:
			ghost_model.reparent(_preview_root)
			for node in ghost_model.find_children("*", "GeometryInstance3D", true, false):
				(node as GeometryInstance3D).transparency = 0.55
				(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif definition != null and definition.texture != null:
		var ghost := _make_billboard(definition.texture, definition.visual_size_tiles, definition.visual_offset_tiles)
		ghost.modulate = Color(1.0, 1.0, 1.0, 0.6)
		ghost.position = _ground_anchor(footprint) + _offset_xz(definition.visual_offset_tiles)
		_lift_to_ground(ghost)
		_preview_root.add_child(ghost)

	# Yield highlight: only meaningful for a legal spot, so the player reads the value
	# of a placement they can actually commit. Mark the neighbor cells that change output
	# (blue = deposits tapped, orange = crowding penalty) and float the net per-cycle gain.
	if can_place and definition != null and not definition.adjacency_yields.is_empty():
		var yield_cells := building_manager.get_yield_cells(hovered_cell, placement_building_type, island, rotation)
		for cell in yield_cells.positive:
			_preview_root.add_child(_make_yield_marker(cell, Color(0.4, 0.85, 1.0, 0.5)))
		for cell in yield_cells.negative:
			_preview_root.add_child(_make_yield_marker(cell, Color(1.0, 0.55, 0.2, 0.5)))

		# A generator's adjacency shapes its power; everything else shapes resource output.
		if definition.category == GameTypes.BuildingCategory.POWER:
			var power := building_manager.get_power_generated(hovered_cell, placement_building_type, island, rotation)
			_preview_root.add_child(_make_yield_label(footprint, power, " MW"))
		else:
			var output := building_manager.get_production_amount(hovered_cell, placement_building_type, island, rotation)
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
	var center := _local_cell_center(cell)
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

# Recolor the cell under the cursor in place (brightened terrain, or green when the robot can
# work it), restoring the previously hovered cell. Recoloring the actual tile avoids the depth/parallax artifacts
# of a separate overlay mesh floating above the surface.
func _update_hover() -> void:
	if _highlighted_cell != GameTypes.NO_CELL:
		_restore_tile(_highlighted_cell)
		_highlighted_cell = GameTypes.NO_CELL

	if island == null or hovered_cell == GameTypes.NO_CELL or not _explored:
		return

	var tile = _tiles.get(hovered_cell)
	if tile != null:
		var actionable: bool = is_cell_actionable.is_valid() and is_cell_actionable.call(hovered_cell)
		tile.set_instance_shader_parameter("hover_state", 2 if actionable else 1)
		_highlighted_cell = hovered_cell


func _restore_tile(cell: Vector2i) -> void:
	var tile = _tiles.get(cell)
	if tile != null and island != null:
		tile.set_instance_shader_parameter("hover_state", 0)


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
# Centroid of a footprint's tile centres, at the height of its first (anchor) tile: a footprint can
# span terrains of different heights, like the dock's sand and coast.
func _ground_anchor(cells: Array) -> Vector3:
	var sum := Vector3.ZERO
	for cell in cells:
		sum += _local_cell_center(cell)
	var ground := sum / float(maxi(1, cells.size()))
	if not cells.is_empty():
		ground.y = _local_cell_center(cells[0]).y
	return ground


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


# The height of an elevation level's tile top (see IslandData.get_elevation).
static func elevation_top_y(level: int) -> float:
	return SAND_TOP_Y + level * ELEVATION_STEP


# Where a unit stands on the cell: its land tile's top, or the water's surface.
func _cell_top_y(cell: Vector2i) -> float:
	var terrain_type := _terrain_of(cell)
	if GameTypes.is_water(terrain_type):
		return WATER_TOP_Y
	return elevation_top_y(island.get_elevation(cell))


# The top of the island's tallest tile or deck: where picking starts walking a ray down.
func _max_top_y() -> float:
	var top := _land_top_y
	for cell in HexPathfinderScript.deck_cells(island):
		top = maxf(top, _local_cell_center(cell).y)
	return top


# Top height of a water cell's seabed prism: coast sits just under the surface, open ocean
# drops deeper, so the basin gets shallower toward the shore.
func _water_seabed_top_y(terrain_type: int) -> float:
	return COAST_SEABED_TOP_Y if terrain_type == GameTypes.Terrain.COAST else OCEAN_SEABED_TOP_Y


# Visible top height of a cell's tile: its land top, or the dropped seabed top for water.
func _tile_top_y(cell: Vector2i) -> float:
	var terrain_type := _terrain_of(cell)
	return _water_seabed_top_y(terrain_type) if GameTypes.is_water(terrain_type) else _cell_top_y(cell)


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


func _row_offset(row: int) -> float:
	return 0.5 if row % 2 != 0 else 0.0


func _clear(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		child.queue_free()
