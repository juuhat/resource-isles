class_name IslandDesign
extends RefCounted

# A hand-made island: its land, deposits, items, landmarks and named spots, read from an .island
# text file in assets/world/islands/. The world map (WorldMap) says where each design goes, and
# build() stamps it onto the world lattice there as an IslandData. The format, in short (see
# docs/world-map-and-island-designs.md):
#
#   [grid]                    one character per hex (see LEGEND), one space between them, every
#   . s s s .                 odd row indented one space more: the game's hexes use odd-r rows,
#    s g T g s                so the text looks like the island. Draw land only; the coast is
#   . s S s .                 added around it. A short row ends in water.
#
#   [heights]                 optional, laid out like the grid: a land cell's elevation level,
#   . 0 . 3 .                 0 (a beach) to IslandData.MAX_ELEVATION, or '.' for its ground's
#    0 1 3 3 3                usual level (sand 0, grass 1, rock 2). A short grid leaves the
#                             rest at their usual levels.
#
#   [landmarks]               a building placed with the island: type, anchor cell, rotation
#   crashed_spaceship 3,1 0
#
#   [markers]                 a named spot (MARKERS): k9da is where K9-DA waits on its island
#   k9da 1,1
#
# A cell in a design is column,row from the grid's top-left cell, odd-r like a world cell. A #
# starts a comment, to the end of the line.

const HexGridScript := preload("res://scripts/island/hex_grid.gd")
const IslandDataScript := preload("res://scripts/island/island_data.gd")

const DIRECTORY := "res://assets/world/islands"
const EXTENSION := "island"
const SECTIONS: Array[String] = ["grid", "heights", "landmarks", "markers"]
const MARKERS: Array[String] = ["k9da"]
# Water up to this many steps from land is shallow Coast and belongs to the island; past it lies
# the open sea. Matches a generated island's coast (IslandProfile.coast_rings).
const COAST_RINGS := 2

# What each grid character stands for: the ground, and a deposit or item on it. Deposits sit on
# rock, pines and leaf trees on grass and palms on sand, the ground IslandData.can_place_resource
# allows them on.
const LEGEND := {
	".": {terrain = GameTypes.Terrain.WATER},
	"s": {terrain = GameTypes.Terrain.SAND},
	"g": {terrain = GameTypes.Terrain.GRASS},
	"r": {terrain = GameTypes.Terrain.STONE},
	"T": {terrain = GameTypes.Terrain.GRASS, resource = GameTypes.ResourceNodeType.TREE},
	"L": {terrain = GameTypes.Terrain.GRASS, resource = GameTypes.ResourceNodeType.LEAF_TREE},
	"P": {terrain = GameTypes.Terrain.SAND, resource = GameTypes.ResourceNodeType.PALM_TREE},
	"S": {terrain = GameTypes.Terrain.STONE, resource = GameTypes.ResourceNodeType.STONE},
	"I": {terrain = GameTypes.Terrain.STONE, resource = GameTypes.ResourceNodeType.IRON_ORE},
	"C": {terrain = GameTypes.Terrain.STONE, resource = GameTypes.ResourceNodeType.COAL},
	"U": {terrain = GameTypes.Terrain.STONE, resource = GameTypes.ResourceNodeType.COPPER_ORE},
	"a": {terrain = GameTypes.Terrain.GRASS, item = GameTypes.ItemType.AXE},
	"p": {terrain = GameTypes.Terrain.GRASS, item = GameTypes.ItemType.PICKAXE},
	"w": {terrain = GameTypes.Terrain.GRASS, item = GameTypes.ItemType.WRENCH},
}

var design_name := ""
# The grid's widest row and its number of rows.
var size := Vector2i.ZERO
# Design cell -> terrain, for every land cell; water isn't kept.
var land: Dictionary = {}
# Design cell -> elevation level, for the land cells [heights] gives one.
var heights: Dictionary = {}
# Design cell -> ResourceNodeType / ItemType.
var resources: Dictionary = {}
var items: Dictionary = {}
# {type: BuildingType, cell, rotation}, in file order.
var landmarks: Array[Dictionary] = []
# Marker name -> design cell.
var markers: Dictionary = {}
# What is wrong with the file, one line each, naming the file line. Don't build a design with errors.
var errors: PackedStringArray = []
# What didn't fit the last time build() ran.
var build_errors: PackedStringArray = []


static func path_for(name: String) -> String:
	return "%s/%s.%s" % [DIRECTORY, name, EXTENSION]


# Every design in DIRECTORY, by name, sorted.
static func all_names() -> PackedStringArray:
	var names := PackedStringArray()
	for file in DirAccess.get_files_at(DIRECTORY):
		if file.get_extension() == EXTENSION:
			names.append(file.get_basename())
	names.sort()
	return names


static func load_named(name: String) -> IslandDesign:
	var path := path_for(name)
	if not FileAccess.file_exists(path):
		var missing := IslandDesign.new()
		missing.design_name = name
		missing.errors.append("%s: there is no design file %s" % [name, path])
		return missing
	return parse(FileAccess.get_file_as_string(path), name)


# Reads a design from the text of an .island file. Whatever is wrong with it goes in errors.
static func parse(text: String, name := "") -> IslandDesign:
	var design := IslandDesign.new()
	design.design_name = name
	var lines := {grid = [], heights = [], landmarks = [], markers = []}
	var section := ""
	var line_number := 0
	for raw_line in text.replace("\r", "").split("\n"):
		line_number += 1
		var line := raw_line.get_slice("#", 0).rstrip(" \t")
		var stripped := line.strip_edges()
		if stripped.is_empty():
			continue
		if stripped.begins_with("[") and stripped.ends_with("]"):
			var header := stripped.substr(1, stripped.length() - 2).strip_edges()
			if not SECTIONS.has(header):
				design._error(line_number, "unknown section [%s]; the sections are [grid], [heights], [landmarks] and [markers]" % header)
			elif not (lines[header] as Array).is_empty():
				design._error(line_number, "a second [%s] section" % header)
			section = header
			continue
		if section == "":
			design._error(line_number, "this needs to be in a section; the grid starts with [grid]")
		elif lines.has(section):
			(lines[section] as Array).append([line_number, line])

	design._read_grid(lines.grid)
	design._read_heights(lines.heights)
	design._read_landmarks(lines.landmarks)
	design._read_markers(lines.markers)
	return design


# The cell in the middle of the grid, which lands on a placement's centre.
func middle() -> Vector2i:
	return Vector2i((size.x - 1) / 2, (size.y - 1) / 2)


# Where the design's `cell` lands in the world when its middle sits on `center`: mirrored east-west
# first if `mirror`, then turned `rotation` x 60 degrees counter-clockwise (seen from above) about
# the middle. Done in axial coordinates, so the shape holds on either row parity.
func world_cell(cell: Vector2i, center: Vector2i, rotation := 0, mirror := false) -> Vector2i:
	var offset := HexGridScript.offset_to_axial(cell) - HexGridScript.offset_to_axial(middle())
	if mirror:
		offset = Vector2i(-offset.x - offset.y, offset.y)
	var axial := HexGridScript.offset_to_axial(center) + HexGridScript.rotate_axial(offset, rotation)
	return HexGridScript.axial_to_offset(axial)


# Where the named marker lands for a placement (see world_cell), or NO_CELL if the design has none.
func marker_cell(marker: String, center: Vector2i, rotation := 0, mirror := false) -> Vector2i:
	if not markers.has(marker):
		return GameTypes.NO_CELL
	return world_cell(markers[marker], center, rotation, mirror)


# The island this design makes with its middle on `center` (see world_cell): its land, the coast
# ring around it, deposits, items and landmarks, on world cells. Landmarks are placed by
# building_manager under the player's placement rules, so it is needed when there are any. What
# doesn't fit goes in build_errors, emptied first; an island with build errors is incomplete.
func build(
	center: Vector2i, rotation := 0, mirror := false, building_manager: BuildingManager = null
) -> IslandData:
	build_errors.clear()
	var ground := {}
	for cell in land:
		ground[world_cell(cell, center, rotation, mirror)] = land[cell]
	_add_coast(ground)

	var island: IslandData = IslandDataScript.new()
	# Row by row, as a generated island's cells are.
	var cells := ground.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for cell in cells:
		island.terrain[cell] = ground[cell]
	for cell in heights:
		island.set_elevation(world_cell(cell, center, rotation, mirror), heights[cell])

	for cell in resources:
		if not island.place_resource(world_cell(cell, center, rotation, mirror), resources[cell]):
			build_errors.append("%s: the deposit at %d,%d can't sit on its ground" % [design_name, cell.x, cell.y])
	for cell in items:
		island.place_item(world_cell(cell, center, rotation, mirror), items[cell])
	for landmark in landmarks:
		_place_landmark(island, landmark, center, rotation, mirror, building_manager)
	for marker in markers:
		if island.has_building(world_cell(markers[marker], center, rotation, mirror)):
			build_errors.append("%s: the %s marker is under a landmark" % [design_name, marker])
	return island


func _place_landmark(
	island: IslandData,
	landmark: Dictionary,
	center: Vector2i,
	rotation: int,
	mirror: bool,
	building_manager: BuildingManager
) -> void:
	var type_name := String(GameTypes.BuildingType.find_key(landmark.type)).to_lower()
	var cell: Vector2i = landmark.cell
	if building_manager == null:
		build_errors.append("%s: placing the %s needs a BuildingManager" % [design_name, type_name])
		return
	# A building can't be mirrored, so on a mirrored island it faces the mirrored direction.
	var facing: int = 3 - landmark.rotation if mirror else landmark.rotation
	var anchor := world_cell(cell, center, rotation, mirror)
	if not building_manager.try_place(anchor, landmark.type, island, posmod(facing + rotation, 6)):
		build_errors.append("%s: the %s at %d,%d doesn't fit (its ground, footprint or neighbours)"
			% [design_name, type_name, cell.x, cell.y])


# Water up to COAST_RINGS steps from land, lagoons included, becomes Coast and part of the island.
static func _add_coast(ground: Dictionary) -> void:
	var frontier: Array = ground.keys()
	for _ring in COAST_RINGS:
		var next_frontier: Array = []
		for cell in frontier:
			for neighbor in HexGridScript.neighbors(cell):
				if not ground.has(neighbor):
					ground[neighbor] = GameTypes.Terrain.COAST
					next_frontier.append(neighbor)
		frontier = next_frontier


# --- Reading the file ---

func _read_grid(lines: Array) -> void:
	if lines.is_empty():
		errors.append("%s: there is no grid; draw the island under [grid]" % _file_name())
		return
	_read_cells(lines, func(cell: Vector2i, character: String, line_number: int) -> void:
		size.x = maxi(size.x, cell.x + 1)
		if not LEGEND.has(character):
			_error(line_number, "'%s' isn't in the legend (IslandDesign.LEGEND)" % character)
		else:
			_add_cell(cell, LEGEND[character]))
	size.y = lines.size()


# The [heights] grid, laid out like [grid]: a digit for a land cell's level, '.' for its usual one.
func _read_heights(lines: Array) -> void:
	_read_cells(lines, func(cell: Vector2i, character: String, line_number: int) -> void:
		if character == ".":
			return
		if not character.is_valid_int() or int(character) > IslandDataScript.MAX_ELEVATION:
			_error(line_number, "'%s' isn't a height; use a level from 0 to %d, or '.' for the ground's usual one"
				% [character, IslandDataScript.MAX_ELEVATION])
		elif not land.has(cell):
			_error(line_number, "%d,%d is water in the grid; only land has a height" % [cell.x, cell.y])
		else:
			heights[cell] = int(character))


# Reads a grid of one character per hex, one space between them, every odd row indented one space
# more than the first, calling read_cell(cell, character, line_number) for each cell.
func _read_cells(lines: Array, read_cell: Callable) -> void:
	var base_indent := 0
	for row in lines.size():
		var line_number: int = lines[row][0]
		var line: String = lines[row][1]
		if line.contains("\t"):
			_error(line_number, "a tab; indent with spaces")
			continue
		var content := line.lstrip(" ")
		var indent := line.length() - content.length()
		if row == 0:
			base_indent = indent
		elif indent != base_indent + row % 2:
			_error(line_number, "row %d should be indented %d space(s), not %d: every odd row sits half a hex to the right"
				% [row, base_indent + row % 2, indent])
			continue
		for index in content.length():
			var character := content[index]
			if index % 2 == 1:
				if character != " ":
					_error(line_number, "'%s' is joined to the cell before it; put one space between cells" % character)
					break
			elif character == " ":
				_error(line_number, "two spaces between cells; use one, and '.' for water")
				break
			else:
				read_cell.call(Vector2i(index / 2, row), character, line_number)


func _add_cell(cell: Vector2i, entry: Dictionary) -> void:
	if GameTypes.is_water(entry.terrain):
		return
	land[cell] = entry.terrain
	if entry.has("resource"):
		resources[cell] = entry.resource
	if entry.has("item"):
		items[cell] = entry.item


# One landmark per line: building type, anchor cell, and an optional rotation in 60-degree steps.
func _read_landmarks(lines: Array) -> void:
	for entry in lines:
		var line_number: int = entry[0]
		var words := (entry[1] as String).replace("\t", " ").split(" ", false)
		if words.size() < 2 or words.size() > 3:
			_error(line_number, "a landmark is: type column,row [rotation], e.g. crashed_spaceship 12,9 0")
			continue
		var type: int = GameTypes.BuildingType.get(words[0].to_upper(), -1)
		if type == -1:
			_error(line_number, "'%s' isn't a building type" % words[0])
			continue
		var cell := _read_cell(line_number, words[1])
		if cell == GameTypes.NO_CELL:
			continue
		var rotation := 0
		if words.size() == 3:
			if not words[2].is_valid_int() or int(words[2]) < 0 or int(words[2]) > 5:
				_error(line_number, "rotation is a whole number from 0 to 5 (60-degree steps), not '%s'" % words[2])
				continue
			rotation = int(words[2])
		landmarks.append({type = type, cell = cell, rotation = rotation})


# One marker per line: its name and cell. A marker is somewhere a unit stands, so it needs open
# land: no deposit or item there (and no landmark, checked by build()).
func _read_markers(lines: Array) -> void:
	for entry in lines:
		var line_number: int = entry[0]
		var words := (entry[1] as String).replace("\t", " ").split(" ", false)
		if words.size() != 2:
			_error(line_number, "a marker is: name column,row, e.g. k9da 8,6")
			continue
		var marker := words[0]
		if not MARKERS.has(marker):
			_error(line_number, "'%s' isn't a marker; the markers are: %s" % [marker, ", ".join(PackedStringArray(MARKERS))])
			continue
		if markers.has(marker):
			_error(line_number, "a second %s marker" % marker)
			continue
		var cell := _read_cell(line_number, words[1])
		if cell == GameTypes.NO_CELL:
			continue
		if resources.has(cell) or items.has(cell):
			_error(line_number, "the %s marker needs open ground, not a deposit or an item" % marker)
			continue
		markers[marker] = cell


# A design cell written column,row, on the island's land; NO_CELL, with an error, if it isn't one.
func _read_cell(line_number: int, text: String) -> Vector2i:
	var parts := text.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		_error(line_number, "'%s' isn't a cell; write column,row, e.g. 12,9" % text)
		return GameTypes.NO_CELL
	var cell := Vector2i(int(parts[0]), int(parts[1]))
	if not land.has(cell):
		_error(line_number, "%d,%d isn't on the island's land" % [cell.x, cell.y])
		return GameTypes.NO_CELL
	return cell


func _error(line_number: int, message: String) -> void:
	errors.append("%s:%d: %s" % [_file_name(), line_number, message])


func _file_name() -> String:
	return "%s.%s" % [design_name if design_name != "" else "design", EXTENSION]
