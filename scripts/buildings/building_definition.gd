class_name BuildingDefinition
extends RefCounted

var id: int
var display_name: String
var texture: Texture2D
var cost: Dictionary
var footprint_size: Vector2i
var visual_size_tiles: Vector2
var visual_offset_tiles: Vector2

# Footprint cells must sit on this terrain.
var required_terrain: int = GameTypes.Terrain.GRASS
# Each entry { kind, type } must have at least one matching neighbor for placement to be legal.
var required_adjacent: Array[Dictionary] = []
# Placement is blocked if any neighbor matches any { kind, type } entry here.
var forbidden_adjacent: Array[Dictionary] = []
# Each entry { kind, type, amount } grants amount per matching neighbor.
var adjacency_yields: Array[Dictionary] = []


func _init(
	new_id: int,
	new_display_name: String,
	new_texture: Texture2D,
	new_cost: Dictionary,
	new_footprint_size: Vector2i = Vector2i.ONE,
	new_visual_size_tiles: Vector2 = Vector2.ONE,
	new_visual_offset_tiles: Vector2 = Vector2.ZERO
) -> void:
	id = new_id
	display_name = new_display_name
	texture = new_texture
	cost = new_cost
	footprint_size = new_footprint_size
	visual_size_tiles = new_visual_size_tiles
	visual_offset_tiles = new_visual_offset_tiles
