class_name ResourceNodeDefinition
extends RefCounted

var id: int
var display_name: String
var texture: Texture2D
var footprint_size: Vector2i
var visual_size_tiles: Vector2
var visual_offset_tiles: Vector2
var extracted_resource_type: int
var extraction_amount: int
var extraction_interval_seconds: float


func _init(
	new_id: int,
	new_display_name: String,
	new_texture: Texture2D,
	new_extracted_resource_type: int,
	new_extraction_amount: int,
	new_extraction_interval_seconds: float,
	new_footprint_size: Vector2i = Vector2i.ONE,
	new_visual_size_tiles: Vector2 = Vector2.ONE,
	new_visual_offset_tiles: Vector2 = Vector2.ZERO
) -> void:
	id = new_id
	display_name = new_display_name
	texture = new_texture
	footprint_size = new_footprint_size
	visual_size_tiles = new_visual_size_tiles
	visual_offset_tiles = new_visual_offset_tiles
	extracted_resource_type = new_extracted_resource_type
	extraction_amount = new_extraction_amount
	extraction_interval_seconds = new_extraction_interval_seconds
