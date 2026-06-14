class_name BuildingDefinition
extends RefCounted

var id: int
var display_name: String
var texture: Texture2D
var cost: Dictionary
var footprint_size: Vector2i
var visual_size_tiles: Vector2
var visual_offset_tiles: Vector2


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
