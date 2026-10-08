extends SceneTree

# Draws the world map (assets/world/world_map.cfg) as one top-down image, so islands can be placed
# without sailing around in the game (docs/world-map-and-island-designs.md):
#   - every island cell coloured by its ground, with a dot for a deposit, a tool or the wreck;
#   - each island's id and centre, which is what a section's `center` says, and K9-DA's spot;
#   - a grid of world cells with their coordinates (column, row; odd rows sit half a cell right);
#   - the ring frontiers: the home waters open at the start, what the radar reveals, and further out;
#   - the edge of the sea at 4.5 rings, and the mountains;
#   - circled in red and listed, any island that breaks a rule of tools/world_map_rules.gd.
#
# The whole map by default, or a closer look around a cell with --around column,row and --cells
# (how many cells out from it). It loads no scene and touches no save, but writing text takes a
# rendering window, so leave out --headless:
#
#   Godot_v4.6.3-stable_win64_console.exe --path . --script res://tools/world_map_preview.gd -- [output.png] [--around 25,-29] [--cells 40]

const WorldMapRules := preload("res://tools/world_map_rules.gd")
const Nav := preload("res://scripts/world/world_navigation.gd")

const DEFAULT_OUTPUT := "res://art/previews/world_map/world_map.png"
const WHOLE_MAP_SIZE := 3200
const AROUND_SIZE := 1600
const DEFAULT_AROUND_CELLS := 40


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("The map preview writes text, which needs a rendering window; leave out --headless.")
		quit(1)
		return
	var options := _read_options(OS.get_cmdline_user_args())
	if options.has("error"):
		push_error(options.error)
		quit(1)
		return

	var manager := BuildingManager.new()
	var map := WorldMap.load_file()
	var problems := WorldMapRules.problems(map, manager)
	var canvas := MapCanvas.new()
	var size: int = options.size
	canvas.setup(map, manager, problems, options.center, options.half_extent, size)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(size, size)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(canvas)
	root.add_child(viewport)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw

	var output: String = options.output
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var error := viewport.get_texture().get_image().save_png(output)
	if error != OK:
		push_error("Couldn't write %s (%s)" % [output, error_string(error)])
		quit(1)
		return
	print("World map preview: %s (%d islands)" % [ProjectSettings.globalize_path(output), map.placements.size()])
	for placement in map.placements:
		print("  %-16s %-12s centre %d,%d" % [placement.id, placement.design, placement.center.x, placement.center.y])
	if problems.is_empty():
		print("No problems with the map.")
	for problem in problems:
		print("  PROBLEM " + problem.message)
	quit()


# {output, center (world xz), half_extent (world units), size (pixels)}, or {error}.
func _read_options(args: PackedStringArray) -> Dictionary:
	var output := DEFAULT_OUTPUT
	var around := GameTypes.NO_CELL
	var cells := DEFAULT_AROUND_CELLS
	var index := 0
	while index < args.size():
		var arg := args[index]
		if arg == "--around" or arg == "--cells":
			if index + 1 >= args.size():
				return {error = "%s needs a value" % arg}
			var value := args[index + 1]
			if arg == "--cells":
				if not value.is_valid_int() or int(value) <= 0:
					return {error = "--cells is a whole number of cells, not '%s'" % value}
				cells = int(value)
			else:
				var parts := value.split(",")
				if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
					return {error = "--around is a cell, column,row, not '%s'" % value}
				around = Vector2i(int(parts[0]), int(parts[1]))
			index += 2
			continue
		output = arg
		index += 1

	if around == GameTypes.NO_CELL:
		var disc := (WorldData.MIN_WORLD_RINGS + WorldView.DISC_MARGIN) * Nav.RING_SPACING
		return {output = output, center = Vector2.ZERO, half_extent = disc + 400.0, size = WHOLE_MAP_SIZE}
	var point := Nav.cell_center(around)
	return {output = output, center = Vector2(point.x, point.z), half_extent = cells * Nav.CELL_SIZE.x, size = AROUND_SIZE}


# Draws the map once, in image pixels: world xz points go through to_image.
class MapCanvas extends Node2D:
	const SEA_COLOR := Color(0.14, 0.43, 0.53) # the open sea's deep_color (disc_ocean.gdshader)
	const BEYOND_COLOR := Color("#0d141d")
	const MOUNTAIN_COLOR := Color("#6b5d53")
	const GRID_COLOR := Color(1.0, 1.0, 1.0, 0.09)
	const GRID_LABEL_COLOR := Color(1.0, 1.0, 1.0, 0.6)
	const FRONTIER_COLOR := Color("#f2c14e")
	const PROBLEM_COLOR := Color("#ff4d4d")
	const LABEL_COLOR := Color("#f7f1e3")
	const OUTLINE_COLOR := Color("#15202e")
	const LEGEND_BACK := Color(0.08, 0.12, 0.17, 0.88)
	const TERRAIN_COLORS := {
		GameTypes.Terrain.SAND: Color("#d3b586"),
		GameTypes.Terrain.GRASS: Color("#879347"),
		GameTypes.Terrain.STONE: Color("#8a8794"),
		GameTypes.Terrain.COAST: Color("#7cc9c6"),
	}
	const DEPOSIT_COLORS := {
		GameTypes.ResourceNodeType.TREE: Color("#2c6e2a"),
		GameTypes.ResourceNodeType.LEAF_TREE: Color("#5f9a2e"),
		GameTypes.ResourceNodeType.PALM_TREE: Color("#8fae3a"),
		GameTypes.ResourceNodeType.STONE: Color("#ecebe6"),
		GameTypes.ResourceNodeType.IRON_ORE: Color("#a9533b"),
		GameTypes.ResourceNodeType.COAL: Color("#1b1b1e"),
		GameTypes.ResourceNodeType.COPPER_ORE: Color("#e8822e"),
	}
	const ITEM_COLOR := Color("#ffd93b")
	const WRECK_COLOR := Color("#ffffff")
	const K9DA_COLOR := Color("#ff6a3d")

	var _map: WorldMap
	var _problems: Array[Dictionary]
	# {placement, design, island} for every island that builds, in map order.
	var _islands: Array[Dictionary] = []
	var _center := Vector2.ZERO
	var _half_extent := 1.0
	var _size := 1
	var _scale := 1.0
	var _font: Font


	func setup(map: WorldMap, manager: BuildingManager, problems: Array[Dictionary], center: Vector2, half_extent: float, size: int) -> void:
		_map = map
		_problems = problems
		_center = center
		_half_extent = half_extent
		_size = size
		_scale = size / (half_extent * 2.0)
		_font = ThemeDB.fallback_font
		for placement in map.placements:
			var design := IslandDesign.load_named(placement.design)
			if not design.errors.is_empty():
				continue
			var island := design.build(placement.center, placement.rotation, placement.mirror, manager)
			if design.build_errors.is_empty():
				_islands.append({placement = placement, design = design, island = island})


	func to_image(world: Vector2) -> Vector2:
		return (world - _center) * _scale + Vector2(_size, _size) * 0.5


	func _xz(cell: Vector2i) -> Vector2:
		var point := Nav.cell_center(cell)
		return Vector2(point.x, point.z)


	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(_size, _size)), BEYOND_COLOR)
		_draw_sea()
		_draw_grid()
		_draw_frontiers()
		for entry in _islands:
			_draw_island(entry)
		for entry in _islands:
			_draw_island_label(entry)
		_draw_legend()


	func _draw_sea() -> void:
		var middle := to_image(Vector2.ZERO)
		var edge := (WorldData.MIN_WORLD_RINGS + WorldView.DISC_MARGIN) * Nav.RING_SPACING
		var foothills := edge + WorldView.RANGE_INNER * WorldView.DISC_SCALE
		draw_circle(middle, edge * _scale, MOUNTAIN_COLOR)
		draw_circle(middle, foothills * _scale, SEA_COLOR)


	# Every `step` columns and rows, a faint line and, every other one, its number at the edges.
	func _draw_grid() -> void:
		var cell_pixels := Nav.CELL_SIZE.x * _scale
		var step := 10 if cell_pixels < 12.0 else 5
		var font_size := 15 if _size > 2000 else 14
		var first := _cell_at(to_world(Vector2.ZERO))
		var last := _cell_at(to_world(Vector2(_size, _size)))
		for column in range(_round_up(first.x, step), last.x + 1, step):
			var x := to_image(_xz(Vector2i(column, 0))).x
			draw_line(Vector2(x, 0), Vector2(x, _size), GRID_COLOR, 1.0)
			if column % (step * 2) == 0:
				_text(str(column), Vector2(x, 18), font_size, GRID_LABEL_COLOR, true)
				_text(str(column), Vector2(x, _size - 8), font_size, GRID_LABEL_COLOR, true)
		for row in range(_round_up(first.y, step), last.y + 1, step):
			var y := to_image(_xz(Vector2i(0, row))).y
			draw_line(Vector2(0, y), Vector2(_size, y), GRID_COLOR, 1.0)
			if row % (step * 2) == 0:
				_text(str(row), Vector2(6, y - 3), font_size, GRID_LABEL_COLOR)
				_text(str(row), Vector2(_size - 44, y - 3), font_size, GRID_LABEL_COLOR)


	# What each ring frontier opens: the sailing radius once that many rings are revealed.
	func _draw_frontiers() -> void:
		var middle := to_image(Vector2.ZERO)
		for ring in range(0, WorldData.MIN_WORLD_RINGS + 1):
			var radius := WorldData.frontier_rings_for(ring) * Nav.RING_SPACING * _scale
			draw_arc(middle, radius, 0.0, TAU, 256, Color(FRONTIER_COLOR, 0.55), 2.0)
			var title := "home waters: open at the start" if ring == 0 else ("revealed by the radar" if ring == 1 else "ring %d revealed" % ring)
			if ring == WorldData.MIN_WORLD_RINGS:
				title += ": edge of the sea"
			var at := middle + Vector2(cos(-PI * 0.3), sin(-PI * 0.3)) * radius
			_text(title, at + Vector2(6, -6), 18, FRONTIER_COLOR)


	func _draw_island(entry: Dictionary) -> void:
		var island: IslandData = entry.island
		var cell_pixels := Nav.CELL_SIZE.x * _scale
		for cell: Vector2i in island.terrain:
			draw_colored_polygon(_hex(cell), TERRAIN_COLORS.get(island.get_terrain(cell), SEA_COLOR))
		var dot := maxf(1.5, cell_pixels * 0.28)
		for cell: Vector2i in island.resources:
			draw_circle(to_image(_xz(cell)), dot, DEPOSIT_COLORS.get(island.resources[cell], Color.MAGENTA))
		for cell: Vector2i in island.items:
			draw_circle(to_image(_xz(cell)), dot, ITEM_COLOR)
		for anchor: Vector2i in island.buildings:
			for cell: Vector2i in island.get_building_footprint_cells(anchor):
				draw_circle(to_image(_xz(cell)), dot * 1.4, WRECK_COLOR)
		var placement: WorldMap.Placement = entry.placement
		if placement.k9da:
			var design: IslandDesign = entry.design
			var spot := design.marker_cell("k9da", placement.center, placement.rotation, placement.mirror)
			if spot != GameTypes.NO_CELL:
				draw_circle(to_image(_xz(spot)), dot * 1.5, OUTLINE_COLOR)
				draw_circle(to_image(_xz(spot)), dot * 1.1, K9DA_COLOR)
		if _has_problem(placement.id):
			draw_arc(to_image(_xz(placement.center)), _reach(island, placement.center) * _scale + 10.0, 0.0, TAU, 96, PROBLEM_COLOR, 3.0)


	# The id over the island, and under it the centre as world_map.cfg writes it.
	func _draw_island_label(entry: Dictionary) -> void:
		var island: IslandData = entry.island
		var placement: WorldMap.Placement = entry.placement
		var top := INF
		for cell: Vector2i in island.terrain:
			top = minf(top, to_image(_xz(cell)).y)
		var x := to_image(_xz(placement.center)).x
		var role := " (start)" if placement.start else (" (K9-DA)" if placement.k9da else "")
		var color := PROBLEM_COLOR if _has_problem(placement.id) else LABEL_COLOR
		_text(String(placement.id) + role, Vector2(x, top - 24), 20, color, true)
		_text("%d,%d" % [placement.center.x, placement.center.y], Vector2(x, top - 6), 16, color, true)


	func _draw_legend() -> void:
		var lines: Array = [
			["World map: %d islands" % _islands.size(), LABEL_COLOR],
			["sand, grass, rock, coast", null],
			["pine, leaf tree, palm, stone, iron, coal, copper", null],
			["tool, wreck, K9-DA", null],
			["grid: column,row as in world_map.cfg; odd rows sit half a cell right", GRID_LABEL_COLOR],
		]
		if _problems.is_empty():
			lines.append(["No problems with the map", Color("#7ee08a")])
		for problem in _problems:
			lines.append([problem.message, PROBLEM_COLOR])
		var width := 0.0
		for line in lines:
			width = maxf(width, _font.get_string_size(line[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x)
		var box := Rect2(Vector2(60, 40), Vector2(width + 60, lines.size() * 24 + 16))
		draw_rect(box, LEGEND_BACK)
		var swatches := [
			TERRAIN_COLORS.values(),
			DEPOSIT_COLORS.values(),
			[ITEM_COLOR, WRECK_COLOR, K9DA_COLOR],
		]
		for index in lines.size():
			var y := box.position.y + 26 + index * 24
			var x := box.position.x + 14
			if typeof(lines[index][1]) == TYPE_NIL:
				var colors: Array = swatches[index - 1]
				for color in colors:
					draw_circle(Vector2(x + 6, y - 5), 6, color)
					# Coal is as dark as the box.
					draw_arc(Vector2(x + 6, y - 5), 6.5, 0.0, TAU, 24, Color(1.0, 1.0, 1.0, 0.45), 1.0)
					x += 16
				x += 6
			_text(lines[index][0], Vector2(x, y), 16, LABEL_COLOR if typeof(lines[index][1]) == TYPE_NIL else lines[index][1])


	func _hex(cell: Vector2i) -> PackedVector2Array:
		var points := PackedVector2Array()
		var point := Nav.cell_center(cell)
		for corner in HexGrid.hex_corners_3d(point, Nav.CELL_SIZE):
			points.append(to_image(Vector2(corner.x, corner.z)))
		return points


	func _reach(island: IslandData, center: Vector2i) -> float:
		var reach := 0.0
		for cell: Vector2i in island.terrain:
			reach = maxf(reach, _xz(cell).distance_to(_xz(center)))
		return reach


	func _has_problem(id: StringName) -> bool:
		for problem in _problems:
			if (problem.islands as Array).has(id):
				return true
		return false


	func to_world(image_point: Vector2) -> Vector2:
		return (image_point - Vector2(_size, _size) * 0.5) / _scale + _center


	# The cell nearest a world xz point, near enough for the grid's extent.
	func _cell_at(world: Vector2) -> Vector2i:
		var row := roundi(world.y / (Nav.CELL_SIZE.y * 0.75))
		return Vector2i(roundi(world.x / Nav.CELL_SIZE.x), row)


	func _round_up(value: int, step: int) -> int:
		return ceili(float(value) / step) * step


	func _text(text: String, at: Vector2, font_size: int, color: Color, centered := false) -> void:
		var point := at
		if centered:
			point.x -= _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
		draw_string_outline(_font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, OUTLINE_COLOR)
		draw_string(_font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
