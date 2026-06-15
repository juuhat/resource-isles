class_name WorldMap
extends CanvasLayer

# Strategic overlay (not a separate scene) hosting the hex-grid world map. State
# stays in main; selecting a slot asks main to enter that island (travel, or
# generate-then-travel). See docs/island-unlocks.md.

const WorldMapGridScript := preload("res://scripts/ui/world_map_grid.gd")

signal slot_activated(coord: Vector2i)

var world: WorldData
var root: Control
var grid: WorldMapGrid
var is_open := false


func setup(new_world: WorldData) -> void:
	world = new_world
	if grid != null:
		grid.setup(world)


func _ready() -> void:
	layer = 10
	_build_ui()
	close()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	is_open = true
	root.visible = true
	grid.refresh()


func close() -> void:
	is_open = false
	root.visible = false


# Rebuild if showing (e.g. after a new island is discovered or travelled to).
func refresh() -> void:
	if is_open:
		grid.refresh()


func _build_ui() -> void:
	name = "WorldMap"

	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color("#10303f")
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	grid = WorldMapGridScript.new()
	grid.setup(world)
	grid.slot_activated.connect(func(coord: Vector2i) -> void: slot_activated.emit(coord))
	root.add_child(grid)

	var title := Label.new()
	title.text = "World Map"
	title.add_theme_font_size_override("font_size", 28)
	title.position = Vector2(24.0, 20.0)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)

	var hint := Label.new()
	hint.text = "Click an island to travel.   Click an unexplored slot (?) to discover it.   [M] or [Esc] to close."
	hint.position = Vector2(24.0, 58.0)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)
